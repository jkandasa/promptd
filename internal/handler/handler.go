package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"strings"
	"time"

	"chatbot/internal/chat"
	"chatbot/internal/llmlog"
	"chatbot/internal/tools"

	openai "github.com/sashabaranov/go-openai"
	"go.uber.org/zap"
)

type Handler struct {
	client       *openai.Client
	model        string
	systemPrompt string
	registry     *tools.Registry
	store        *chat.SessionStore
	log          *zap.Logger
	staticFS     fs.FS
	uiConfig     UIConfig
}

type UIConfig struct {
	WelcomeTitle      string   `json:"welcomeTitle"`
	AIDisclaimer      string   `json:"aiDisclaimer"`
	PromptSuggestions []string `json:"promptSuggestions"`
}

func New(apiKey, baseURL, model, systemPrompt string, registry *tools.Registry, store *chat.SessionStore, log *zap.Logger, staticFS fs.FS, uiConfig UIConfig) *Handler {
	cfg := openai.DefaultConfig(apiKey)
	cfg.BaseURL = baseURL
	cfg.HTTPClient = &http.Client{Transport: llmlog.NewTransport(nil, log)}
	return &Handler{
		client:       openai.NewClientWithConfig(cfg),
		model:        model,
		systemPrompt: systemPrompt,
		registry:     registry,
		store:        store,
		log:          log,
		staticFS:     staticFS,
		uiConfig:     uiConfig,
	}
}

type chatRequest struct {
	SessionID string `json:"session_id"`
	Message   string `json:"message"`
}

type chatResponse struct {
	Reply     string  `json:"reply"`
	TimeTaken float64 `json:"time_taken_ms"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func (h *Handler) buildMessages(session *chat.Session) []openai.ChatCompletionMessage {
	var messages []openai.ChatCompletionMessage
	if h.systemPrompt != "" {
		messages = append(messages, openai.ChatCompletionMessage{
			Role:    openai.ChatMessageRoleSystem,
			Content: h.systemPrompt,
		})
	}
	return append(messages, session.History()...)
}

// runLLM sends the current session to the LLM and handles any tool calls in a loop
// until the model returns a final text response.
func (h *Handler) runLLM(ctx context.Context, sessionID string, session *chat.Session) (string, error) {
	for {
		req := openai.ChatCompletionRequest{
			Model:    h.model,
			Messages: h.buildMessages(session),
		}
		if h.registry != nil && !h.registry.Empty() {
			req.Tools = h.registry.OpenAITools()
		}

		h.log.Debug("llm request",
			zap.String("session_id", sessionID),
			zap.String("model", h.model),
			zap.Any("messages", req.Messages),
		)

		resp, err := h.client.CreateChatCompletion(ctx, req)
		if err != nil {
			return "", fmt.Errorf("LLM error: %w", err)
		}

		choice := resp.Choices[0]

		h.log.Debug("llm response",
			zap.String("session_id", sessionID),
			zap.String("finish_reason", string(choice.FinishReason)),
			zap.Int("prompt_tokens", resp.Usage.PromptTokens),
			zap.Int("completion_tokens", resp.Usage.CompletionTokens),
			zap.String("reply", choice.Message.Content),
		)

		// No tool calls — we have the final answer.
		if choice.FinishReason != openai.FinishReasonToolCalls {
			if choice.Message.Content == "" {
				return "", fmt.Errorf("model returned an empty response (finish_reason: %q) — the model may not support tool calling", choice.FinishReason)
			}
			session.AddMessage(choice.Message)
			return choice.Message.Content, nil
		}

		// Append the assistant message that contains the tool call requests.
		session.AddMessage(choice.Message)

		// Execute each requested tool and append its result.
		for _, tc := range choice.Message.ToolCalls {
			result, toolErr := h.executeTool(ctx, tc)
			h.log.Debug("tool executed",
				zap.String("tool", tc.Function.Name),
				zap.String("args", tc.Function.Arguments),
				zap.String("result", result),
			)
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
		// Loop: send tool results back to the LLM.
	}
}

func (h *Handler) executeTool(ctx context.Context, tc openai.ToolCall) (string, error) {
	tool, ok := h.registry.Get(tc.Function.Name)
	if !ok {
		return fmt.Sprintf("tool %q not found", tc.Function.Name), nil
	}
	result, err := tool.Execute(ctx, json.RawMessage(tc.Function.Arguments))
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
	if req.Message == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "message is required"})
		return
	}
	if req.SessionID == "" {
		req.SessionID = "default"
	}

	start := time.Now()

	session := h.store.Get(req.SessionID)
	session.Add(openai.ChatMessageRoleUser, req.Message)

	reply, err := h.runLLM(r.Context(), req.SessionID, session)
	if err != nil {
		h.log.Error("llm call failed", zap.String("session_id", req.SessionID), zap.Error(err))
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}

	timeTaken := time.Since(start).Milliseconds()
	h.log.Info("chat", zap.String("session_id", req.SessionID), zap.Int("history_len", len(session.History())), zap.Int64("time_ms", timeTaken))
	writeJSON(w, http.StatusOK, chatResponse{Reply: reply, TimeTaken: float64(timeTaken)})
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

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	http.ServeContent(w, r, "index.html", time.Time{}, index.(io.ReadSeeker))
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func (h *Handler) UIConfig(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, h.uiConfig)
}
