package scheduler

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"promptd/internal/llm"
	"promptd/internal/storage"
	"promptd/internal/tools"

	openai "github.com/openai/openai-go/v3"
	"go.uber.org/zap"
)

const maxRunnerIterations = 20

// RunConfig holds per-execution parameters.
type RunConfig struct {
	Prompt       string
	ModelID      string // empty → use selector default
	Provider     string // optional: pin execution to a specific provider
	SystemPrompt string // literal system prompt text (not a name)
	// AllowedTools: nil = all tools, []string{} = no tools, non-empty = filtered set.
	AllowedTools []string
	// Params overrides LLM generation parameters (nil = use model/global defaults).
	Params *storage.UsedParams
	// TraceEnabled overrides the runner's global trace flag (nil = use runner default).
	TraceEnabled *bool
}

// RunResult holds the output of a completed execution.
type RunResult struct {
	Response     string
	ModelUsed    string
	ProviderUsed string
	LLMCalls     int
	ToolCalls    int
	Trace        []storage.LLMRound
}

// ModelResolver resolves a preferred model ID (and optional provider name) to
// the actual model ID, display name, provider name, and provider client to use.
type ModelResolver interface {
	ResolveModel(preferred, provider string) (id, name, providerUsed string, client *openai.Client)
}

// Runner executes prompts against the LLM without managing a session.
type Runner struct {
	resolver     ModelResolver
	registry     *tools.Registry
	log          *zap.Logger
	traceEnabled bool
}

// NewRunner creates a Runner.
func NewRunner(resolver ModelResolver, registry *tools.Registry, log *zap.Logger, traceEnabled bool) *Runner {
	return &Runner{
		resolver:     resolver,
		registry:     registry,
		log:          log,
		traceEnabled: traceEnabled,
	}
}

// Run executes the prompt and returns the final response along with trace data.
func (r *Runner) Run(ctx context.Context, cfg RunConfig) (*RunResult, error) {
	model, _, providerUsed, client := r.resolver.ResolveModel(cfg.ModelID, cfg.Provider)

	// Build filtered tool list.
	openaiTools := r.filterTools(cfg.AllowedTools)

	// Build initial message list.
	messages := make([]llm.Message, 0, 2)
	if cfg.SystemPrompt != "" {
		messages = append(messages, llm.Message{
			Role:    llm.RoleSystem,
			Content: cfg.SystemPrompt,
		})
	}
	messages = append(messages, llm.Message{
		Role:    llm.RoleUser,
		Content: cfg.Prompt,
	})

	// Resolve effective trace setting: per-run override takes precedence over runner default.
	traceOn := r.traceEnabled
	if cfg.TraceEnabled != nil {
		traceOn = *cfg.TraceEnabled
	}

	var trace []storage.LLMRound
	llmCalls, toolCalls := 0, 0

	for {
		if llmCalls >= maxRunnerIterations {
			return nil, fmt.Errorf("exceeded max tool call iterations (%d)", maxRunnerIterations)
		}
		llmCalls++

		body := map[string]any{
			"model":    model,
			"messages": schedulerMessagesToRaw(messages),
		}
		if len(openaiTools) > 0 {
			body["tools"] = openaiTools
		}
		if p := cfg.Params; p != nil {
			if p.Temperature != nil {
				body["temperature"] = *p.Temperature
			}
			if p.MaxTokens != 0 {
				body["max_tokens"] = p.MaxTokens
			}
			if p.TopP != nil {
				body["top_p"] = *p.TopP
			}
		}

		var availableTools []storage.TraceToolDef
		for _, t := range openaiTools {
			availableTools = append(availableTools, storage.ToolDefFromOpenAI(t))
		}

		llmStart := time.Now()
		resp, err := createSchedulerChatCompletion(ctx, client, body)
		llmDurationMs := time.Since(llmStart).Milliseconds()
		if err != nil {
			return nil, fmt.Errorf("LLM error: %w", err)
		}
		if len(resp.Choices) == 0 {
			return nil, fmt.Errorf("LLM returned no choices")
		}
		choice := resp.Choices[0]

		if choice.FinishReason != llm.FinishReasonToolCalls {
			if choice.Message.Content == "" {
				return nil, fmt.Errorf("model returned empty response (finish_reason: %q)", choice.FinishReason)
			}
			if traceOn {
				trace = append(trace, storage.LLMRound{
					Request:        storage.ToTraceMessages(messages),
					Response:       storage.ToTraceMessage(choice.Message),
					LLMDurationMs:  llmDurationMs,
					AvailableTools: availableTools,
					Usage:          runnerTraceUsage(resp.Usage),
				})
			}
			return &RunResult{
				Response:     choice.Message.Content,
				ModelUsed:    model,
				ProviderUsed: providerUsed,
				LLMCalls:     llmCalls,
				ToolCalls:    toolCalls,
				Trace:        trace,
			}, nil
		}

		// Append assistant tool-call message and execute each tool.
		// Strip ReasoningContent — some providers (e.g. Groq) reject it in history.
		assistantMsg := choice.Message
		assistantMsg.ReasoningContent = ""
		messages = append(messages, assistantMsg)
		round := storage.LLMRound{
			Request:        storage.ToTraceMessages(messages[:len(messages)-1]),
			Response:       storage.ToTraceMessage(assistantMsg),
			LLMDurationMs:  llmDurationMs,
			AvailableTools: availableTools,
			Usage:          runnerTraceUsage(resp.Usage),
		}
		for _, tc := range choice.Message.ToolCalls {
			toolCalls++
			toolStart := time.Now()
			result, toolErr := r.executeTool(ctx, tc)
			toolDurationMs := time.Since(toolStart).Milliseconds()
			round.ToolResults = append(round.ToolResults, storage.ToolResult{
				Name:       tc.Function.Name,
				Args:       tc.Function.Arguments,
				Result:     result,
				DurationMs: toolDurationMs,
			})
			messages = append(messages, llm.Message{
				Role:       llm.RoleTool,
				ToolCallID: tc.ID,
				Content:    result,
				Name:       tc.Function.Name,
			})
			if toolErr != nil {
				r.log.Warn("scheduler tool error", zap.String("tool", tc.Function.Name), zap.Error(toolErr))
			}
		}
		if traceOn {
			trace = append(trace, round)
		}
	}
}

func (r *Runner) filterTools(allowed []string) []llm.Tool {
	if r.registry == nil || r.registry.Empty() {
		return nil
	}
	if allowed == nil {
		// nil = all tools
		return r.registry.OpenAITools()
	}
	if len(allowed) == 0 {
		// empty slice = no tools
		return nil
	}
	allowedSet := make(map[string]bool, len(allowed))
	for _, name := range allowed {
		allowedSet[name] = true
	}
	var filtered []llm.Tool
	for _, t := range r.registry.OpenAITools() {
		if allowedSet[t.Function.Name] {
			filtered = append(filtered, t)
		}
	}
	return filtered
}

func (r *Runner) executeTool(ctx context.Context, tc llm.ToolCall) (string, error) {
	tool, ok := r.registry.Get(tc.Function.Name)
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

func runnerTraceUsage(u llm.Usage) *storage.TokenUsage {
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

func schedulerMessagesToRaw(messages []llm.Message) []map[string]any {
	out := make([]map[string]any, 0, len(messages))
	for _, msg := range messages {
		m := map[string]any{"role": msg.Role, "content": msg.Content}
		if msg.Name != "" {
			m["name"] = msg.Name
		}
		if msg.ToolCallID != "" {
			m["tool_call_id"] = msg.ToolCallID
		}
		if len(msg.ToolCalls) > 0 {
			m["tool_calls"] = msg.ToolCalls
		}
		out = append(out, m)
	}
	return out
}

func createSchedulerChatCompletion(ctx context.Context, client *openai.Client, body any) (llm.ChatCompletionResponse, error) {
	var resp llm.ChatCompletionResponse
	if client == nil {
		return resp, fmt.Errorf("provider client not configured")
	}
	if err := client.Execute(ctx, http.MethodPost, "chat/completions", body, &resp); err != nil {
		return resp, err
	}
	return resp, nil
}
