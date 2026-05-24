package handler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"path"
	"strings"
	"time"

	"promptd/internal/auth"
	"promptd/internal/chat"
	"promptd/internal/llm"
	"promptd/internal/storage"

	"github.com/google/uuid"
	"go.uber.org/zap"
)

type executeRequest struct {
	// Exactly one of SystemPrompt or SystemPromptName must be set.
	SystemPrompt     string `json:"system_prompt"`      // inline system prompt text
	SystemPromptName string `json:"system_prompt_name"` // named prompt from config (RBAC enforced)

	Provider string `json:"provider"`
	Model    string `json:"model"`
	Message  string `json:"message"`
	// Tools controls which tools are exposed to the model.
	// Absent or null → no tools.
	// ["*"] → all tools the service account's roles allow.
	// ["web_*", "calc"] → only tools matching these patterns (still filtered by policy).
	Tools     []string  `json:"tools"`
	NoHistory bool      `json:"no_history"` // when true, skip persisting to conversation history
	Params    LLMParams `json:"params"`
}

type executeResponse struct {
	Reply          string              `json:"reply"`
	Model          string              `json:"model"`
	Provider       string              `json:"provider,omitempty"`
	ConversationID string              `json:"conversation_id,omitempty"`
	TimeTakenMs    int64               `json:"time_taken_ms"`
	LLMCalls       int                 `json:"llm_calls"`
	ToolCalls      int                 `json:"tool_calls"`
	UsedParams     *storage.UsedParams `json:"used_params,omitempty"`
	TokenUsage     *storage.TokenUsage `json:"token_usage,omitempty"`
	Trace          []storage.LLMRound  `json:"trace,omitempty"`
}

func (h *Handler) Execute(w http.ResponseWriter, r *http.Request) {
	// Extend the write deadline: LLM calls with tool loops can run well beyond
	// the server's global WriteTimeout. EOF on the client is the symptom when
	// the global deadline fires before the response is written.
	extendLLMWriteDeadline(w)

	principal := requestPrincipal(r)
	if principal == nil || !principal.Policy.Permissions.Chat {
		writeJSON(w, http.StatusForbidden, errorResponse{Error: "chat not allowed"})
		return
	}

	var req executeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid request body"})
		return
	}
	if strings.TrimSpace(req.Message) == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "message is required"})
		return
	}
	if req.SystemPrompt != "" && req.SystemPromptName != "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "only one of system_prompt or system_prompt_name may be set"})
		return
	}

	// Resolve system prompt text.
	systemPromptText := strings.TrimSpace(req.SystemPrompt)
	if req.SystemPromptName != "" {
		if err := h.requireAllowedSystemPrompt(principal, req.SystemPromptName); err != nil {
			status := http.StatusBadRequest
			if err.Error() == "system prompt not allowed" {
				status = http.StatusForbidden
			}
			writeJSON(w, status, errorResponse{Error: err.Error()})
			return
		}
		systemPromptText = h.systemPrompts[req.SystemPromptName]
	}
	if systemPromptText == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "system_prompt or system_prompt_name is required"})
		return
	}

	// Resolve tools: intersect caller-requested patterns with the principal's policy.
	// req.Tools == nil means no tools; otherwise the patterns gate which tools are exposed.
	allowedTools := h.resolveExecuteTools(req.Tools, principal)

	// Create a session — persisted (default) or ephemeral (no_history: true).
	scope := requestScopeFromPrincipal(principal)
	var session *chat.Session
	sessionID := uuid.New().String()
	if req.NoHistory {
		session = chat.NewEphemeral()
		sessionID = session.ID()
	} else {
		session = h.store.Get(scope, sessionID)
		if req.SystemPromptName != "" {
			session.SetSystemPrompt(req.SystemPromptName)
		}
	}

	start := time.Now()
	session.Add(llm.RoleUser, req.Message, nil)

	reply, finalMsg, model, providerUsed, llmCalls, toolCalls, trace, usedParams, tokenUsage, err := h.runExecute(
		r.Context(), principal, sessionID, session,
		req.Model, req.Provider, req.Params,
		systemPromptText, allowedTools,
	)
	if err != nil {
		h.log.Error("execute failed",
			zap.String("session_id", sessionID),
			zap.Bool("no_history", req.NoHistory),
			zap.Error(err),
		)
		session.AddErrorMessage(err.Error(), model, providerUsed)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error(), Model: model, Provider: providerUsed})
		return
	}

	timeTaken := time.Since(start).Milliseconds()
	session.AddFinalMessage(finalMsg, "chat", model, providerUsed, nil, timeTaken, llmCalls, toolCalls, trace, usedParams)
	h.log.Info("execute",
		zap.String("session_id", sessionID),
		zap.Bool("no_history", req.NoHistory),
		zap.Int64("time_ms", timeTaken),
		zap.Int("llm_calls", llmCalls),
		zap.Int("tool_calls", toolCalls),
		zap.String("model", model),
		zap.String("provider", providerUsed),
	)

	if !principal.Policy.Permissions.TracesRead {
		trace = nil
	}

	conversationID := ""
	if !req.NoHistory {
		conversationID = sessionID
	}

	writeJSON(w, http.StatusOK, executeResponse{
		Reply:          reply,
		Model:          model,
		Provider:       providerUsed,
		ConversationID: conversationID,
		TimeTakenMs:    timeTaken,
		LLMCalls:       llmCalls,
		ToolCalls:      toolCalls,
		UsedParams:     usedParams,
		TokenUsage:     tokenUsage,
		Trace:          trace,
	})
}

// runExecute drives a stateless LLM tool-call loop using pre-resolved tools and
// a system prompt text (rather than a session-stored prompt name).
func (h *Handler) runExecute(
	ctx context.Context,
	principal *auth.Principal,
	sessionID string,
	session *chat.Session,
	preferredModel, provider string,
	reqParams LLMParams,
	systemPromptText string,
	allowedTools []llm.Tool,
) (string, llm.Message, string, string, int, int, []storage.LLMRound, *storage.UsedParams, *storage.TokenUsage, error) {
	llmCalls := 0
	toolCalls := 0
	var trace []storage.LLMRound
	var totalUsage storage.TokenUsage

	scope := requestScopeFromPrincipal(principal)

	if preferredModel != "" && provider != "" && !principal.Policy.AllowModel(provider, preferredModel) {
		return "", llm.Message{}, preferredModel, provider, llmCalls, toolCalls, trace, nil, nil, fmt.Errorf("model %q is not allowed", preferredModel)
	}

	model, _, providerUsed, llmClient := h.resolveAllowedModel(principal, preferredModel, provider)
	providerEntry := h.providers.ProviderEntry(providerUsed)
	if model == "" || providerUsed == "" || llmClient == nil || providerEntry == nil {
		return "", llm.Message{}, preferredModel, provider, llmCalls, toolCalls, trace, nil, nil, fmt.Errorf("no allowed model available")
	}
	if !principal.Policy.AllowModel(providerUsed, model) {
		return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, nil, nil, fmt.Errorf("model %q from provider %q is not allowed", model, providerUsed)
	}

	modelParams := h.providers.GetModelParamsForProvider(model, provider)
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
			return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, usagePtr(&totalUsage),
				fmt.Errorf("exceeded max tool call iterations (%d)", maxToolIterations)
		}
		llmCalls++

		requestBody, requestMsgs, err := h.buildChatCompletionRequest(ctx, scope, session, providerEntry, model, modelParams, allowedTools, systemPromptText)
		if err != nil {
			return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, usagePtr(&totalUsage), fmt.Errorf("build chat request: %w", err)
		}

		var availableTools []storage.TraceToolDef
		for _, t := range allowedTools {
			availableTools = append(availableTools, storage.ToolDefFromOpenAI(t))
		}

		h.log.Debug("execute llm request",
			zap.String("session_id", sessionID),
			zap.String("model", model),
			zap.Any("messages", requestMsgs),
		)

		llmStart := time.Now()
		resp, err := createRawChatCompletion(ctx, providerEntry, requestBody)
		llmDurationMs := time.Since(llmStart).Milliseconds()
		if err != nil {
			return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, usagePtr(&totalUsage), fmt.Errorf("LLM error: %w", err)
		}
		if len(resp.Choices) == 0 {
			return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, usagePtr(&totalUsage), fmt.Errorf("LLM returned no choices")
		}

		accumulateUsage(&totalUsage, resp.Usage)

		choice := resp.Choices[0]
		choice.Message = sanitizeAssistantMessage(choice.Message)

		h.log.Debug("execute llm response",
			zap.String("session_id", sessionID),
			zap.String("finish_reason", string(choice.FinishReason)),
			zap.Int("prompt_tokens", resp.Usage.PromptTokens),
			zap.Int("completion_tokens", resp.Usage.CompletionTokens),
			zap.String("reply", choice.Message.Content),
			zap.Int64("llm_duration_ms", llmDurationMs),
		)

		if choice.FinishReason != llm.FinishReasonToolCalls {
			if choice.Message.Content == "" {
				return "", llm.Message{}, model, providerUsed, llmCalls, toolCalls, trace, usedParams, usagePtr(&totalUsage),
					fmt.Errorf("model returned an empty response (finish_reason: %q)", choice.FinishReason)
			}
			if h.TraceEnabled {
				trace = append(trace, storage.LLMRound{
					Request:        storage.ToTraceMessages(requestMsgs),
					Response:       storage.ToTraceMessage(choice.Message),
					LLMDurationMs:  llmDurationMs,
					AvailableTools: availableTools,
					Usage:          traceUsage(resp.Usage),
				})
			}
			return choice.Message.Content, choice.Message, model, providerUsed, llmCalls, toolCalls, trace, usedParams, usagePtr(&totalUsage), nil
		}

		session.AddMessage(choice.Message)

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
			result, toolErr := h.executeTool(ctx, principal, tc)
			toolDurationMs := time.Since(toolStart).Milliseconds()
			h.log.Debug("execute tool",
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
			session.AddMessage(llm.Message{
				Role:       llm.RoleTool,
				ToolCallID: tc.ID,
				Content:    result,
				Name:       tc.Function.Name,
			})
			if toolErr != nil {
				h.log.Warn("execute tool error", zap.String("tool", tc.Function.Name), zap.Error(toolErr))
			}
		}
		if h.TraceEnabled {
			trace = append(trace, round)
		}
	}
}

// accumulateUsage adds the counts from one LLM response into a running total.
// TotalTokens is recomputed as prompt+completion when the provider omits it.
func accumulateUsage(dst *storage.TokenUsage, u llm.Usage) {
	dst.PromptTokens += u.PromptTokens
	dst.CompletionTokens += u.CompletionTokens
	total := u.TotalTokens
	if total == 0 {
		total = u.PromptTokens + u.CompletionTokens
	}
	dst.TotalTokens += total
	if u.CompletionTokensDetails != nil {
		dst.ReasoningTokens += u.CompletionTokensDetails.ReasoningTokens
	}
	if u.PromptTokensDetails != nil {
		dst.CachedTokens += u.PromptTokensDetails.CachedTokens
	}
}

// usagePtr returns a pointer to u if any token counts are non-zero, else nil.
func usagePtr(u *storage.TokenUsage) *storage.TokenUsage {
	if u.PromptTokens == 0 && u.CompletionTokens == 0 && u.TotalTokens == 0 {
		return nil
	}
	return u
}

// resolveExecuteTools intersects the caller-requested tool patterns with the
// tools permitted by the principal's policy. A nil/empty requested list means
// no tools. ["*"] means all policy-permitted tools.
func (h *Handler) resolveExecuteTools(requested []string, principal *auth.Principal) []llm.Tool {
	if len(requested) == 0 {
		return nil
	}
	if h.registry == nil || h.registry.Empty() {
		return nil
	}
	policyAllowed := principal.Policy.FilterAllowedToolNames(h.registry.Names())
	if len(policyAllowed) == 0 {
		return nil
	}
	var final []string
	for _, name := range policyAllowed {
		if executeMatchesAnyPattern(name, requested) {
			final = append(final, name)
		}
	}
	if len(final) == 0 {
		return nil
	}
	return h.registry.OpenAIToolsByNames(final)
}

func executeMatchesAnyPattern(name string, patterns []string) bool {
	for _, pat := range patterns {
		if matched, _ := path.Match(pat, name); matched {
			return true
		}
	}
	return false
}
