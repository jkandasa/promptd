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

// LLMParams holds optional generation parameters that can be set globally
// or per model in the config, and overridden per-request from the UI.
type LLMParams struct {
	Temperature *float32 `json:"temperature,omitempty" yaml:"temperature,omitempty"`
	MaxTokens   int      `json:"max_tokens,omitempty"  yaml:"max_tokens,omitempty"`
	TopP        *float32 `json:"top_p,omitempty"       yaml:"top_p,omitempty"`
	TopK        int      `json:"top_k,omitempty"       yaml:"top_k,omitempty"`
}

type ModelInfo struct {
	ID       string    `json:"id"`
	Name     string    `json:"name,omitempty"`
	Params   LLMParams `json:"params,omitempty"`
	IsManual bool      `json:"is_manual,omitempty"`
}

type ModelSelector struct {
	models          []ModelInfo
	selectionMethod string
	currentIndex    int
	source          string // "static" | "discovered"
	lastUpdated     time.Time
	refreshInterval time.Duration // 0 if autodiscover disabled
	mu              sync.Mutex
}

func NewModelSelector(models []ModelInfo, selectionMethod string) *ModelSelector {
	if len(models) == 0 {
		models = []ModelInfo{{ID: "anthropic/claude-sonnet-4-6"}}
	}
	if selectionMethod == "" {
		selectionMethod = "round_robin"
	}
	return &ModelSelector{
		models:          models,
		selectionMethod: selectionMethod,
		currentIndex:    0,
		source:          "static",
		lastUpdated:     time.Now(),
	}
}

// SetRefreshInterval records the autodiscover interval so it can be surfaced to the UI.
func (m *ModelSelector) SetRefreshInterval(d time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.refreshInterval = d
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
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]ModelInfo(nil), m.models...) // copy
}

func (m *ModelSelector) UpdateModels(infos []ModelInfo) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.models = infos
	m.currentIndex = 0 // reset round-robin index on update
	m.source = "discovered"
	m.lastUpdated = time.Now()
}

func (m *ModelSelector) GetSelectionMethod() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.selectionMethod
}

type Handler struct {
	client              *openai.Client
	ModelSelector       *ModelSelector
	GlobalParams        LLMParams   // global config defaults; applied to discovered models
	StaticModels        []ModelInfo // models explicitly listed in config (is_manual=true)
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
		ModelSelector:       modelSelector,
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
	SessionID    string    `json:"session_id"`
	Message      string    `json:"message"`
	Files        []string  `json:"files,omitempty"`
	Model        string    `json:"model,omitempty"`
	SystemPrompt string    `json:"system_prompt,omitempty"`
	Params       LLMParams `json:"params,omitempty"` // UI overrides; zero values ignored
}

type chatResponse struct {
	Reply          string              `json:"reply"`
	Model          string              `json:"model"`
	TimeTaken      int64               `json:"time_taken_ms"`
	LLMCalls       int                 `json:"llm_calls"`
	ToolCalls      int                 `json:"tool_calls"`
	UserMsgID      string              `json:"user_msg_id"`
	AssistantMsgID string              `json:"assistant_msg_id"`
	Trace          []storage.LLMRound  `json:"trace,omitempty"`
	UsedParams     *storage.UsedParams `json:"used_params,omitempty"`
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
// tool call count, the full trace of all LLM round-trips, the effective params used,
// and any error.
func (h *Handler) runLLM(ctx context.Context, sessionID string, session *chat.Session, preferredModel string, reqParams LLMParams) (string, openai.ChatCompletionMessage, string, int, int, []storage.LLMRound, *storage.UsedParams, error) {
	llmCalls := 0
	toolCalls := 0
	var trace []storage.LLMRound
	model, _ := h.ModelSelector.GetModel(preferredModel)

	// Resolve effective params: model-config defaults, overridden by UI request.
	var modelParams LLMParams
	h.ModelSelector.mu.Lock()
	for _, m := range h.ModelSelector.models {
		if m.ID == model {
			modelParams = m.Params
			break
		}
	}
	h.ModelSelector.mu.Unlock()
	// UI request params override model-config params.
	if reqParams.Temperature != nil {
		modelParams.Temperature = reqParams.Temperature
	}
	if reqParams.MaxTokens != 0 {
		modelParams.MaxTokens = reqParams.MaxTokens
	}
	if reqParams.TopP != nil {
		modelParams.TopP = reqParams.TopP
	}
	if reqParams.TopK != 0 {
		modelParams.TopK = reqParams.TopK
	}

	// Build the UsedParams record from the effective (merged) params.
	// Only include fields that are actually set so the UI can distinguish
	// "explicitly set to X" from "not set / provider default".
	var usedParams *storage.UsedParams
	if modelParams.Temperature != nil || modelParams.MaxTokens != 0 || modelParams.TopP != nil || modelParams.TopK != 0 {
		usedParams = &storage.UsedParams{
			Temperature: modelParams.Temperature,
			MaxTokens:   modelParams.MaxTokens,
			TopP:        modelParams.TopP,
			TopK:        modelParams.TopK,
		}
	}

	for {
		if llmCalls >= maxToolIterations {
			return "", openai.ChatCompletionMessage{}, model, llmCalls, toolCalls, trace, usedParams, fmt.Errorf("exceeded max tool call iterations (%d)", maxToolIterations)
		}
		llmCalls++
		requestMsgs := h.buildMessages(session)
		req := openai.ChatCompletionRequest{
			Model:    model,
			Messages: requestMsgs,
		}
		if modelParams.Temperature != nil {
			req.Temperature = *modelParams.Temperature
		}
		if modelParams.MaxTokens != 0 {
			req.MaxTokens = modelParams.MaxTokens
		}
		if modelParams.TopP != nil {
			req.TopP = *modelParams.TopP
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
			return "", openai.ChatCompletionMessage{}, model, llmCalls, toolCalls, trace, usedParams, fmt.Errorf("LLM error: %w", err)
		}

		if len(resp.Choices) == 0 {
			return "", openai.ChatCompletionMessage{}, model, llmCalls, toolCalls, trace, usedParams, fmt.Errorf("LLM returned no choices")
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
				return "", openai.ChatCompletionMessage{}, model, llmCalls, toolCalls, trace, usedParams, fmt.Errorf("model returned an empty response (finish_reason: %q) — the model may not support tool calling", choice.FinishReason)
			}
			trace = append(trace, storage.LLMRound{
				Request:        storage.ToTraceMessages(requestMsgs),
				Response:       storage.ToTraceMessage(choice.Message),
				LLMDurationMs:  llmDurationMs,
				AvailableTools: availableTools,
				Usage:          traceUsage(resp.Usage),
			})
			return choice.Message.Content, choice.Message, model, llmCalls, toolCalls, trace, usedParams, nil
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
	// Persist the current UI param overrides on the conversation so they can be
	// restored when the conversation is loaded again. Nil means "use config defaults".
	var convParams *storage.UsedParams
	if req.Params.Temperature != nil || req.Params.MaxTokens != 0 || req.Params.TopP != nil || req.Params.TopK != 0 {
		convParams = &storage.UsedParams{
			Temperature: req.Params.Temperature,
			MaxTokens:   req.Params.MaxTokens,
			TopP:        req.Params.TopP,
			TopK:        req.Params.TopK,
		}
	}
	session.SetParams(convParams)
	userMsgID := session.Add(openai.ChatMessageRoleUser, userContent)

	reply, finalMsg, model, llmCalls, toolCalls, trace, usedParams, err := h.runLLM(r.Context(), req.SessionID, session, req.Model, req.Params)
	if err != nil {
		h.log.Error("llm call failed", zap.String("session_id", req.SessionID), zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error(), Model: model})
		return
	}

	timeTaken := time.Since(start).Milliseconds()
	assistantMsgID := session.AddFinalMessage(finalMsg, model, timeTaken, llmCalls, toolCalls, trace, usedParams)
	h.log.Info("chat", zap.String("session_id", req.SessionID), zap.Int("history_len", len(session.History())), zap.Int64("time_ms", timeTaken), zap.Int("llm_calls", llmCalls), zap.Int("tool_calls", toolCalls), zap.String("model", model))
	writeJSON(w, http.StatusOK, chatResponse{Reply: reply, Model: model, TimeTaken: timeTaken, LLMCalls: llmCalls, ToolCalls: toolCalls, UserMsgID: userMsgID, AssistantMsgID: assistantMsgID, Trace: trace, UsedParams: usedParams})
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
	discover := r.URL.Query().Get("discover") == "true"
	if discover {
		if err := h.DiscoverAndUpdateModels(r.Context()); err != nil {
			http.Error(w, fmt.Sprintf("discover failed: %v", err), http.StatusInternalServerError)
			return
		}
	}
	models := h.ModelSelector.GetAvailableModels()
	m := h.ModelSelector
	m.mu.Lock()
	source := m.source
	count := len(m.models)
	updatedAt := m.lastUpdated.Format(time.RFC3339)
	refreshInterval := ""
	if m.refreshInterval > 0 {
		refreshInterval = m.refreshInterval.String()
	}
	method := m.selectionMethod
	m.mu.Unlock()

	resp := map[string]interface{}{
		"models":           models,
		"selection_method": method,
		"source":           source,
		"count":            count,
		"updated_at":       updatedAt,
		"refresh_interval": refreshInterval,
		"global_params":    h.GlobalParams,
	}
	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) DiscoverAndUpdateModels(ctx context.Context) error {
	resp, err := h.client.ListModels(ctx)
	if err != nil {
		return fmt.Errorf("list models: %w", err)
	}
	// Build a lookup of static (manually-configured) models by ID so we can
	// preserve their per-model params and manual flag when autodiscover runs.
	staticByID := make(map[string]ModelInfo, len(h.StaticModels))
	for _, m := range h.StaticModels {
		staticByID[m.ID] = m
	}
	// Track which static model IDs were matched by the provider response.
	matchedStatic := make(map[string]bool, len(h.StaticModels))

	var infos []ModelInfo
	for _, md := range resp.Models {
		if sm, ok := staticByID[md.ID]; ok {
			// Static model: keep its merged params and mark it as manual.
			infos = append(infos, sm)
			matchedStatic[md.ID] = true
		} else {
			// Discovered-only model: apply global params baseline.
			infos = append(infos, ModelInfo{ID: md.ID, Params: h.GlobalParams})
		}
	}
	// Append static models that the provider didn't return — they may be
	// hosted elsewhere or the provider list may be incomplete.
	for _, sm := range h.StaticModels {
		if !matchedStatic[sm.ID] {
			infos = append(infos, sm)
		}
	}
	h.ModelSelector.UpdateModels(infos)
	h.log.Info("models updated from provider", zap.Int("count", len(infos)))
	return nil
}

func (h *Handler) StartAutodiscover(ctx context.Context, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := h.DiscoverAndUpdateModels(ctx); err != nil {
				h.log.Warn("autodiscover tick failed", zap.Error(err))
			}
		}
	}
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
