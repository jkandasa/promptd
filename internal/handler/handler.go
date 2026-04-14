package handler

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"math/rand"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"

	"chatbot/internal/chat"
	"chatbot/internal/llmlog"
	"chatbot/internal/storage"
	"chatbot/internal/tools"

	openai "github.com/sashabaranov/go-openai"
	"go.uber.org/zap"
)

type ModelInfo struct {
	ID   string `json:"id"`
	Name string `json:"name,omitempty"`
}

type ModelSelector struct {
	models          []ModelInfo
	selectionMethod string
	currentIndex    int
	mu              sync.Mutex
}

func NewModelSelector(models []string, selectionMethod string) *ModelSelector {
	if len(models) == 0 {
		models = []string{"anthropic/claude-sonnet-4-6"}
	}
	if selectionMethod == "" {
		selectionMethod = "auto"
	}
	info := make([]ModelInfo, len(models))
	for i, m := range models {
		info[i] = ModelInfo{ID: m}
	}
	return &ModelSelector{
		models:          info,
		selectionMethod: selectionMethod,
		currentIndex:    0,
	}
}

func (m *ModelSelector) GetModel(preferredModel string) (string, string) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// If user specified a model, use that
	if preferredModel != "" {
		for _, model := range m.models {
			if model.ID == preferredModel {
				return model.ID, model.Name
			}
		}
	}

	// Use selection method (random or round_robin)
	switch m.selectionMethod {
	case "random":
		idx := rand.Intn(len(m.models))
		return m.models[idx].ID, m.models[idx].Name
	default: // round_robin
		model := m.models[m.currentIndex]
		m.currentIndex = (m.currentIndex + 1) % len(m.models)
		return model.ID, model.Name
	}
}

func (m *ModelSelector) GetAvailableModels() []ModelInfo {
	return m.models
}

func (m *ModelSelector) GetSelectionMethod() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.selectionMethod
}

type Handler struct {
	client              *openai.Client
	modelSelector       *ModelSelector
	systemPrompts       map[string]string
	defaultSystemPrompt string
	registry            *tools.Registry
	store               *chat.SessionStore
	storageStore        storage.Store
	log                 *zap.Logger
	staticFS            fs.FS
	uiConfig            UIConfig
	uploadDir           string
}

type UIConfig struct {
	AppName           string             `json:"appName,omitempty"`
	AppIcon           string             `json:"appIcon,omitempty"`
	WelcomeTitle      string             `json:"welcomeTitle"`
	AIDisclaimer      string             `json:"aiDisclaimer"`
	PromptSuggestions []string           `json:"promptSuggestions"`
	SystemPrompts     []SystemPromptInfo `json:"systemPrompts,omitempty"`
}

type SystemPromptInfo struct {
	Name string `json:"name"`
}

func New(apiKey, baseURL string, systemPrompts map[string]string, defaultSystemPrompt string, modelSelector *ModelSelector, registry *tools.Registry, store *chat.SessionStore, storageStore storage.Store, log *zap.Logger, staticFS fs.FS, uiConfig UIConfig, uploadDir string) *Handler {
	cfg := openai.DefaultConfig(apiKey)
	cfg.BaseURL = baseURL
	cfg.HTTPClient = &http.Client{Transport: llmlog.NewTransport(nil, log)}

	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		// Fatal: the upload handler will fail on every request if the directory cannot be created.
		log.Fatal("failed to create upload directory", zap.String("dir", uploadDir), zap.Error(err))
	}

	return &Handler{
		client:              openai.NewClientWithConfig(cfg),
		modelSelector:       modelSelector,
		systemPrompts:       systemPrompts,
		defaultSystemPrompt: defaultSystemPrompt,
		registry:            registry,
		store:               store,
		storageStore:        storageStore,
		log:                 log,
		staticFS:            staticFS,
		uiConfig:            uiConfig,
		uploadDir:           uploadDir,
	}
}

type chatRequest struct {
	SessionID    string   `json:"session_id"`
	Message      string   `json:"message"`
	Files        []string `json:"files,omitempty"`
	Model        string   `json:"model,omitempty"`
	SystemPrompt string   `json:"system_prompt,omitempty"`
}

type chatResponse struct {
	Reply          string             `json:"reply"`
	Model          string             `json:"model"`
	TimeTaken      int64              `json:"time_taken_ms"`
	LLMCalls       int                `json:"llm_calls"`
	ToolCalls      int                `json:"tool_calls"`
	UserMsgID      string             `json:"user_msg_id"`
	AssistantMsgID string             `json:"assistant_msg_id"`
	Trace          []storage.LLMRound `json:"trace,omitempty"`
}

type errorResponse struct {
	Error string `json:"error"`
	Model string `json:"model,omitempty"`
}

func (h *Handler) buildMessages(session *chat.Session) []openai.ChatCompletionMessage {
	var messages []openai.ChatCompletionMessage
	promptName := session.SystemPrompt()
	if promptName == "" || h.systemPrompts[promptName] == "" {
		promptName = h.defaultSystemPrompt
	}
	if prompt := h.systemPrompts[promptName]; prompt != "" {
		messages = append(messages, openai.ChatCompletionMessage{
			Role:    openai.ChatMessageRoleSystem,
			Content: prompt,
		})
	}
	return append(messages, filterHistory(session.History())...)
}

// filterHistory strips intermediate tool-call scaffolding from completed prior
// turns, keeping only user messages and assistant messages that have text
// content. Tool-call-only assistant messages (no content) and tool-result
// messages from already-completed turns waste tokens and are not needed for
// future LLM calls — the final assistant text reply already summarises them.
//
// Messages from the last user message onward are left untouched because they
// belong to the currently active tool-call loop and must remain intact for the
// OpenAI API contract.
func filterHistory(history []openai.ChatCompletionMessage) []openai.ChatCompletionMessage {
	// Find the index of the last user message. Everything from there onward is
	// the active turn and must not be touched.
	lastUserIdx := -1
	for i := len(history) - 1; i >= 0; i-- {
		if history[i].Role == openai.ChatMessageRoleUser {
			lastUserIdx = i
			break
		}
	}

	filtered := make([]openai.ChatCompletionMessage, 0, len(history))
	for i, msg := range history {
		if i >= lastUserIdx {
			// Active turn — keep everything as-is.
			filtered = append(filtered, msg)
			continue
		}
		// Prior turns: keep only user messages and assistant messages that
		// carry actual text content. Drop pure tool-call assistant messages
		// (content == "" and ToolCalls set) and all tool-result messages.
		switch msg.Role {
		case openai.ChatMessageRoleUser:
			filtered = append(filtered, msg)
		case openai.ChatMessageRoleAssistant:
			if msg.Content != "" {
				filtered = append(filtered, msg)
			}
			// else: pure tool-call request — drop it
			// openai.ChatMessageRoleTool: drop entirely
		}
	}
	return filtered
}

func (h *Handler) hasSystemPrompt(promptName string) bool {
	if promptName == "" {
		return true
	}
	_, ok := h.systemPrompts[promptName]
	return ok
}

// traceUsage converts an openai.Usage to our storage.TokenUsage, including
// reasoning and cached-prompt token breakdowns when the provider returns them.
func traceUsage(u openai.Usage) *storage.TokenUsage {
	tu := &storage.TokenUsage{
		PromptTokens:     u.PromptTokens,
		CompletionTokens: u.CompletionTokens,
		TotalTokens:      u.TotalTokens,
	}
	if u.CompletionTokensDetails != nil {
		tu.ReasoningTokens = u.CompletionTokensDetails.ReasoningTokens
	}
	if u.PromptTokensDetails != nil {
		tu.CachedTokens = u.PromptTokensDetails.CachedTokens
	}
	return tu
}

// maxToolIterations caps the tool-call loop to prevent infinite loops from
// misbehaving or adversarially-prompted models.
const maxToolIterations = 20

// runLLM sends the current session to the LLM and handles any tool calls in a loop
// until the model returns a final text response. It does NOT append the final
// assistant message to the session — the caller must do that (so it can attach metadata).
// Returns the reply text, the final assistant message, model used, LLM call count,
// tool call count, and the full trace of all LLM round-trips.
func (h *Handler) runLLM(ctx context.Context, sessionID string, session *chat.Session, preferredModel string) (string, openai.ChatCompletionMessage, string, int, int, []storage.LLMRound, error) {
	llmCalls := 0
	toolCalls := 0
	var trace []storage.LLMRound
	model, _ := h.modelSelector.GetModel(preferredModel)
	for {
		if llmCalls >= maxToolIterations {
			return "", openai.ChatCompletionMessage{}, model, llmCalls, toolCalls, trace, fmt.Errorf("exceeded max tool call iterations (%d)", maxToolIterations)
		}
		llmCalls++
		requestMsgs := h.buildMessages(session)
		req := openai.ChatCompletionRequest{
			Model:    model,
			Messages: requestMsgs,
		}
		if h.registry != nil && !h.registry.Empty() {
			req.Tools = h.registry.OpenAITools()
		}

		// Snapshot available tools for the trace before the API call.
		var availableTools []storage.TraceToolDef
		for _, t := range req.Tools {
			availableTools = append(availableTools, storage.TraceToolDef{
				Name:        t.Function.Name,
				Description: t.Function.Description,
			})
		}

		h.log.Debug("llm request",
			zap.String("session_id", sessionID),
			zap.String("model", model),
			zap.Any("messages", req.Messages),
		)

		llmStart := time.Now()
		resp, err := h.client.CreateChatCompletion(ctx, req)
		llmDurationMs := time.Since(llmStart).Milliseconds()
		if err != nil {
			return "", openai.ChatCompletionMessage{}, model, llmCalls, toolCalls, trace, fmt.Errorf("LLM error: %w", err)
		}

		if len(resp.Choices) == 0 {
			return "", openai.ChatCompletionMessage{}, model, llmCalls, toolCalls, trace, fmt.Errorf("LLM returned no choices")
		}
		choice := resp.Choices[0]

		h.log.Debug("llm response",
			zap.String("session_id", sessionID),
			zap.String("finish_reason", string(choice.FinishReason)),
			zap.Int("prompt_tokens", resp.Usage.PromptTokens),
			zap.Int("completion_tokens", resp.Usage.CompletionTokens),
			zap.String("reply", choice.Message.Content),
			zap.Int64("llm_duration_ms", llmDurationMs),
		)

		// No tool calls — we have the final answer. Record the round and return.
		if choice.FinishReason != openai.FinishReasonToolCalls {
			if choice.Message.Content == "" {
				return "", openai.ChatCompletionMessage{}, model, llmCalls, toolCalls, trace, fmt.Errorf("model returned an empty response (finish_reason: %q) — the model may not support tool calling", choice.FinishReason)
			}
			trace = append(trace, storage.LLMRound{
				Request:        storage.ToTraceMessages(requestMsgs),
				Response:       storage.ToTraceMessage(choice.Message),
				LLMDurationMs:  llmDurationMs,
				AvailableTools: availableTools,
				Usage:          traceUsage(resp.Usage),
			})
			return choice.Message.Content, choice.Message, model, llmCalls, toolCalls, trace, nil
		}

		// Append the assistant message that contains the tool call requests.
		session.AddMessage(choice.Message)

		// Execute each requested tool, timing each one individually.
		round := storage.LLMRound{
			Request:        storage.ToTraceMessages(requestMsgs),
			Response:       storage.ToTraceMessage(choice.Message),
			LLMDurationMs:  llmDurationMs,
			AvailableTools: availableTools,
			Usage:          traceUsage(resp.Usage),
		}
		for _, tc := range choice.Message.ToolCalls {
			toolCalls++
			toolStart := time.Now()
			result, toolErr := h.executeTool(ctx, tc)
			toolDurationMs := time.Since(toolStart).Milliseconds()
			h.log.Debug("tool executed",
				zap.String("tool", tc.Function.Name),
				zap.String("args", tc.Function.Arguments),
				zap.String("result", result),
				zap.Int64("tool_duration_ms", toolDurationMs),
			)
			round.ToolResults = append(round.ToolResults, storage.ToolResult{
				Name:       tc.Function.Name,
				Args:       tc.Function.Arguments,
				Result:     result,
				DurationMs: toolDurationMs,
			})
			session.AddMessage(openai.ChatCompletionMessage{
				Role:       openai.ChatMessageRoleTool,
				ToolCallID: tc.ID,
				Content:    result,
				Name:       tc.Function.Name,
			})
			if toolErr != nil {
				h.log.Warn("tool error", zap.String("tool", tc.Function.Name), zap.Error(toolErr))
			}
		}
		trace = append(trace, round)
		// Loop: send tool results back to the LLM.
	}
}

func (h *Handler) executeTool(ctx context.Context, tc openai.ToolCall) (string, error) {
	tool, ok := h.registry.Get(tc.Function.Name)
	if !ok {
		return fmt.Sprintf("tool %q not found", tc.Function.Name), nil
	}
	args := tc.Function.Arguments
	if args == "" {
		args = "{}"
	}
	result, err := tool.Execute(ctx, json.RawMessage(args))
	if err != nil {
		return fmt.Sprintf("error: %v", err), err
	}
	return result, nil
}

func (h *Handler) Chat(w http.ResponseWriter, r *http.Request) {
	var req chatRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	if req.Message == "" && len(req.Files) == 0 {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "message or files is required"})
		return
	}
	if req.SessionID == "" {
		req.SessionID = "default"
	}

	start := time.Now()

	session := h.store.Get(req.SessionID)

	// Build user message content - include file info if files are attached
	var userContent string
	if len(req.Files) > 0 {
		fileInfo := "Attached files:\n"
		for _, f := range req.Files {
			fileInfo += "- " + f + "\n"
		}
		if req.Message != "" {
			userContent = fileInfo + "\nUser request: " + req.Message
		} else {
			userContent = fileInfo
		}
	} else {
		userContent = req.Message
	}

	// Record the user's explicit model choice before the first persist so it's
	// included in the very first save (triggered by Add below).
	if !h.hasSystemPrompt(req.SystemPrompt) {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid system prompt"})
		return
	}
	session.SetModel(req.Model)
	session.SetSystemPrompt(req.SystemPrompt)
	userMsgID := session.Add(openai.ChatMessageRoleUser, userContent)

	reply, finalMsg, model, llmCalls, toolCalls, trace, err := h.runLLM(r.Context(), req.SessionID, session, req.Model)
	if err != nil {
		h.log.Error("llm call failed", zap.String("session_id", req.SessionID), zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error(), Model: model})
		return
	}

	timeTaken := time.Since(start).Milliseconds()
	assistantMsgID := session.AddFinalMessage(finalMsg, model, timeTaken, llmCalls, toolCalls, trace)
	h.log.Info("chat", zap.String("session_id", req.SessionID), zap.Int("history_len", len(session.History())), zap.Int64("time_ms", timeTaken), zap.Int("llm_calls", llmCalls), zap.Int("tool_calls", toolCalls), zap.String("model", model))
	writeJSON(w, http.StatusOK, chatResponse{Reply: reply, Model: model, TimeTaken: timeTaken, LLMCalls: llmCalls, ToolCalls: toolCalls, UserMsgID: userMsgID, AssistantMsgID: assistantMsgID, Trace: trace})
}

func (h *Handler) Reset(w http.ResponseWriter, r *http.Request) {
	var req struct {
		SessionID string `json:"session_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.SessionID == "" {
		req.SessionID = "default"
	}
	h.store.Get(req.SessionID).Reset()
	h.log.Info("session reset", zap.String("session_id", req.SessionID))
	w.WriteHeader(http.StatusNoContent)
}

// ServeUI is an SPA-aware static file handler.
// Known assets (anything with a real file extension) are served directly.
// All other paths fall back to index.html so client-side routing works.
func (h *Handler) ServeUI(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/")

	// Try to open the requested path in the embedded FS.
	f, err := h.staticFS.Open(path)
	if err == nil {
		f.Close()
		// File exists — serve it directly.
		http.FileServer(http.FS(h.staticFS)).ServeHTTP(w, r)
		return
	}

	// Unknown path → serve index.html (SPA fallback).
	index, err := h.staticFS.Open("index.html")
	if err != nil {
		http.Error(w, "ui not found", http.StatusNotFound)
		return
	}
	defer index.Close()

	seeker, ok := index.(io.ReadSeeker)
	if !ok {
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	http.ServeContent(w, r, "index.html", time.Time{}, seeker)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		// Headers already committed; log only.
		_ = err // caller's logger not available here — acceptable for this helper
	}
}

func (h *Handler) UIConfig(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, h.uiConfig)
}

func (h *Handler) ListModels(w http.ResponseWriter, r *http.Request) {
	models := h.modelSelector.GetAvailableModels()
	method := h.modelSelector.GetSelectionMethod()
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"models":           models,
		"selection_method": method,
	})
}

// ListTools returns all registered tools with their name and description.
func (h *Handler) ListTools(w http.ResponseWriter, r *http.Request) {
	if h.registry == nil {
		writeJSON(w, http.StatusOK, map[string]any{"tools": []any{}})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tools": h.registry.List()})
}

type UploadedFile struct {
	ID        string `json:"id"`
	Filename  string `json:"filename"`
	Size      int64  `json:"size"`
	URL       string `json:"url"`
	CreatedAt int64  `json:"created_at"`
}

func (h *Handler) Upload(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(10 << 20); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "failed to parse form"})
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "no file uploaded"})
		return
	}
	defer file.Close()

	// Use a UUID as the stored filename to avoid path traversal and name collisions.
	// The original filename is preserved only in the response metadata.
	fileID := uuid.New().String()
	filePath := filepath.Join(h.uploadDir, fileID)

	out, err := os.Create(filePath)
	if err != nil {
		h.log.Error("failed to create file", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to save file"})
		return
	}
	defer out.Close()

	if _, err := io.Copy(out, file); err != nil {
		h.log.Error("failed to write file", zap.Error(err))
		if removeErr := os.Remove(filePath); removeErr != nil {
			h.log.Warn("failed to clean up partial upload", zap.String("path", filePath), zap.Error(removeErr))
		}
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to save file"})
		return
	}

	uploadedFile := UploadedFile{
		ID:        fileID,
		Filename:  header.Filename,
		Size:      header.Size,
		URL:       "/files/" + fileID,
		CreatedAt: time.Now().UnixMilli(),
	}

	h.log.Info("file uploaded", zap.String("filename", header.Filename), zap.String("id", fileID))
	writeJSON(w, http.StatusOK, uploadedFile)
}

func (h *Handler) ServeFile(w http.ResponseWriter, r *http.Request) {
	fileID := strings.TrimPrefix(r.URL.Path, "/files/")
	if fileID == "" {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	filePath := filepath.Join(h.uploadDir, fileID)
	if !isUnderDir(filePath, h.uploadDir) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	http.ServeFile(w, r, filePath)
}

func (h *Handler) DeleteFile(w http.ResponseWriter, r *http.Request) {
	fileID := strings.TrimPrefix(r.URL.Path, "/files/")
	if fileID == "" {
		http.Error(w, "file not found", http.StatusNotFound)
		return
	}

	filePath := filepath.Join(h.uploadDir, fileID)
	if !isUnderDir(filePath, h.uploadDir) {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	if err := os.Remove(filePath); err != nil {
		h.log.Warn("failed to delete file", zap.String("file_id", fileID), zap.Error(err))
		http.Error(w, "failed to delete file", http.StatusInternalServerError)
		return
	}

	h.log.Info("file deleted", zap.String("file_id", fileID))
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// isUnderDir reports whether path is inside (or equal to) dir after cleaning both.
func isUnderDir(path, dir string) bool {
	cleanPath := filepath.Clean(path)
	cleanDir := filepath.Clean(dir)
	return strings.HasPrefix(cleanPath, cleanDir+string(os.PathSeparator)) || cleanPath == cleanDir
}

// ListConversations returns all conversations (without messages) ordered newest-first.
func (h *Handler) ListConversations(w http.ResponseWriter, r *http.Request) {
	if h.storageStore == nil {
		writeJSON(w, http.StatusOK, []*storage.Conversation{})
		return
	}
	convs, err := h.storageStore.List()
	if err != nil {
		h.log.Error("failed to list conversations", zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to list conversations"})
		return
	}
	writeJSON(w, http.StatusOK, convs)
}

// GetConversation returns a single conversation including full message history.
func (h *Handler) GetConversation(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id"})
		return
	}
	if h.storageStore == nil {
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
		return
	}
	conv, err := h.storageStore.Load(id)
	if err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "not found"})
		} else {
			h.log.Error("failed to load conversation", zap.String("id", id), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to load conversation"})
		}
		return
	}
	writeJSON(w, http.StatusOK, conv)
}

// DeleteConversation removes a conversation from storage and evicts it from the in-memory cache.
func (h *Handler) DeleteConversation(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id"})
		return
	}
	if err := h.store.Delete(id); err != nil {
		h.log.Error("failed to delete conversation", zap.String("id", id), zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to delete conversation"})
		return
	}
	h.log.Info("conversation deleted", zap.String("id", id))
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// DeleteMessage removes a single message from a conversation.
func (h *Handler) DeleteMessage(w http.ResponseWriter, r *http.Request) {
	convID := r.PathValue("id")
	msgID := r.PathValue("msgId")
	if convID == "" || msgID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id or message id"})
		return
	}
	if err := h.store.DeleteMessage(convID, msgID); err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "message not found"})
		} else {
			h.log.Error("failed to delete message", zap.String("conv_id", convID), zap.String("msg_id", msgID), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to delete message"})
		}
		return
	}
	h.log.Info("message deleted", zap.String("conv_id", convID), zap.String("msg_id", msgID))
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// DeleteMessagesFrom removes a message and all messages after it from a conversation.
// Used when a user edits a message — all subsequent turns are discarded.
func (h *Handler) DeleteMessagesFrom(w http.ResponseWriter, r *http.Request) {
	convID := r.PathValue("id")
	msgID := r.PathValue("msgId")
	if convID == "" || msgID == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id or message id"})
		return
	}
	if err := h.store.DeleteMessagesFrom(convID, msgID); err != nil {
		if errors.Is(err, storage.ErrNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "message not found"})
		} else {
			h.log.Error("failed to truncate messages", zap.String("conv_id", convID), zap.String("msg_id", msgID), zap.Error(err))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to truncate messages"})
		}
		return
	}
	h.log.Info("messages truncated from", zap.String("conv_id", convID), zap.String("msg_id", msgID))
	writeJSON(w, http.StatusOK, map[string]string{"status": "truncated"})
}

// RenameConversation updates the title of a conversation.
func (h *Handler) RenameConversation(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id"})
		return
	}
	var body struct {
		Title string `json:"title"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	if err := h.store.RenameTitle(id, body.Title); err != nil {
		h.log.Error("failed to rename conversation", zap.String("id", id), zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to rename conversation"})
		return
	}
	h.log.Info("conversation renamed", zap.String("id", id), zap.String("title", body.Title))
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// TogglePinConversation flips the pinned state of a conversation.
func (h *Handler) TogglePinConversation(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "missing conversation id"})
		return
	}
	pinned, err := h.store.TogglePin(id)
	if err != nil {
		h.log.Error("failed to toggle pin", zap.String("id", id), zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "failed to toggle pin"})
		return
	}
	h.log.Info("conversation pin toggled", zap.String("id", id), zap.Bool("pinned", pinned))
	writeJSON(w, http.StatusOK, map[string]bool{"pinned": pinned})
}
