// Package storage defines the persistence interface for chat conversations.
// The interface is intentionally small so future backends (SQLite, Postgres,
// Redis, etc.) can be added by implementing Store without touching any other
// package.
package storage

import (
	"time"

	openai "github.com/sashabaranov/go-openai"
)

const MessageRoleError = "error"

type Scope struct {
	TenantID string
	UserID   string
}

func (s Scope) Key() string {
	return s.TenantID + ":" + s.UserID
}

// TraceToolCall captures a single function call request inside an assistant message.
type TraceToolCall struct {
	ID   string `yaml:"id"   json:"id"`
	Name string `yaml:"name" json:"name"`
	Args string `yaml:"args" json:"args"`
}

// TraceToolDef records one tool definition that was offered to the LLM in a round.
type TraceToolDef struct {
	Name        string      `yaml:"name"                   json:"name"`
	Description string      `yaml:"description,omitempty"  json:"description,omitempty"`
	Parameters  interface{} `yaml:"parameters,omitempty"   json:"parameters,omitempty"`
}

// ToolDefFromOpenAI converts an openai.Tool to a TraceToolDef for trace recording.
func ToolDefFromOpenAI(t openai.Tool) TraceToolDef {
	return TraceToolDef{
		Name:        t.Function.Name,
		Description: t.Function.Description,
		Parameters:  t.Function.Parameters,
	}
}

// TokenUsage records prompt/completion/total token counts for one LLM round,
// including reasoning and cache breakdowns when available.
type TokenUsage struct {
	PromptTokens     int `yaml:"prompt_tokens"               json:"prompt_tokens"`
	CompletionTokens int `yaml:"completion_tokens"            json:"completion_tokens"`
	TotalTokens      int `yaml:"total_tokens"                 json:"total_tokens"`
	ReasoningTokens  int `yaml:"reasoning_tokens,omitempty"   json:"reasoning_tokens,omitempty"`
	CachedTokens     int `yaml:"cached_tokens,omitempty"      json:"cached_tokens,omitempty"`
}

// TraceMessage is a slim, YAML-serialisable representation of an OpenAI chat
// message, used to record what was sent to and received from the LLM.
type TraceMessage struct {
	Role             string          `yaml:"role"                        json:"role"`
	Content          string          `yaml:"content,omitempty"           json:"content,omitempty"`
	Refusal          string          `yaml:"refusal,omitempty"           json:"refusal,omitempty"`
	ReasoningContent string          `yaml:"reasoning_content,omitempty" json:"reasoning_content,omitempty"`
	Name             string          `yaml:"name,omitempty"              json:"name,omitempty"`
	ToolCallID       string          `yaml:"tool_call_id,omitempty"      json:"tool_call_id,omitempty"`
	ToolCalls        []TraceToolCall `yaml:"tool_calls,omitempty"        json:"tool_calls,omitempty"`
}

// ToolResult records the outcome of a single tool invocation within one LLM round.
type ToolResult struct {
	Name       string `yaml:"name"        json:"name"`
	Args       string `yaml:"args"        json:"args"`
	Result     string `yaml:"result"      json:"result"`
	DurationMs int64  `yaml:"duration_ms" json:"duration_ms"`
}

// UsedParams records the effective LLM generation parameters that were actually
// sent to the API for a given assistant reply — after merging global config,
// per-model config, and any per-request UI overrides.
// Pointer fields are nil when the parameter was not set (provider default used).
type UsedParams struct {
	Temperature *float32 `yaml:"temperature,omitempty" json:"temperature,omitempty"`
	MaxTokens   int      `yaml:"max_tokens,omitempty"  json:"max_tokens,omitempty"`
	TopP        *float32 `yaml:"top_p,omitempty"       json:"top_p,omitempty"`
	TopK        int      `yaml:"top_k,omitempty"       json:"top_k,omitempty"`
}

// LLMRound captures one full request/response cycle with the LLM, including
// any tool calls that were made and their results.
type LLMRound struct {
	Request        []TraceMessage `yaml:"request"                  json:"request"`
	Response       TraceMessage   `yaml:"response"                 json:"response"`
	LLMDurationMs  int64          `yaml:"llm_duration_ms"          json:"llm_duration_ms"`
	ToolResults    []ToolResult   `yaml:"tool_results,omitempty"   json:"tool_results,omitempty"`
	AvailableTools []TraceToolDef `yaml:"available_tools,omitempty" json:"available_tools,omitempty"`
	Usage          *TokenUsage    `yaml:"usage,omitempty"          json:"usage,omitempty"`
}

// ToTraceMessage converts an openai SDK message to our slim TraceMessage.
func ToTraceMessage(m openai.ChatCompletionMessage) TraceMessage {
	tm := TraceMessage{
		Role:             m.Role,
		Content:          m.Content,
		Refusal:          m.Refusal,
		ReasoningContent: m.ReasoningContent,
		Name:             m.Name,
		ToolCallID:       m.ToolCallID,
	}
	for _, tc := range m.ToolCalls {
		tm.ToolCalls = append(tm.ToolCalls, TraceToolCall{
			ID:   tc.ID,
			Name: tc.Function.Name,
			Args: tc.Function.Arguments,
		})
	}
	return tm
}

// ToTraceMessages converts a slice of openai SDK messages to TraceMessages.
func ToTraceMessages(msgs []openai.ChatCompletionMessage) []TraceMessage {
	out := make([]TraceMessage, len(msgs))
	for i, m := range msgs {
		out[i] = ToTraceMessage(m)
	}
	return out
}

// MessageToolCall stores a single tool-call request on an intermediate assistant
// message. These are transient (never persisted) but must survive the
// storage.Message round-trip so that History() → ToOpenAI() can reconstruct
// the correct openai.ChatCompletionMessage for the active tool loop.
type MessageToolCall struct {
	ID        string `yaml:"-" json:"-"` // never persisted
	Name      string `yaml:"-" json:"-"`
	Arguments string `yaml:"-" json:"-"`
}

// UploadedFile stores file metadata attached to a user message.
type UploadedFile struct {
	ID        string `yaml:"id"         json:"id"`
	Filename  string `yaml:"filename"   json:"filename"`
	Size      int64  `yaml:"size"       json:"size"`
	URL       string `yaml:"url"        json:"url"`
	CreatedAt int64  `yaml:"created_at" json:"created_at"`
	TenantID  string `yaml:"tenant_id,omitempty" json:"-"`
	UserID    string `yaml:"user_id,omitempty" json:"-"`
}

// Message is a single turn in a conversation.
// Only user and assistant messages are persisted for display; intermediate
// tool/function messages are stored for LLM context but carry no display metadata.
type Message struct {
	ID             string    `yaml:"id"      json:"id"`
	Role           string    `yaml:"role"    json:"role"`
	Content        string    `yaml:"content" json:"content"`
	SentAt         time.Time `yaml:"sent_at" json:"sent_at"`
	CompactSummary bool      `yaml:"compact_summary,omitempty" json:"compact_summary,omitempty"`
	// Metadata — non-zero only for final assistant replies.
	Model       string         `yaml:"model,omitempty"         json:"model,omitempty"`
	Provider    string         `yaml:"provider,omitempty"      json:"provider,omitempty"`
	Files       []UploadedFile `yaml:"files,omitempty" json:"files,omitempty"`
	TimeTakenMs int64          `yaml:"time_taken_ms,omitempty" json:"time_taken_ms,omitempty"`
	LLMCalls    int            `yaml:"llm_calls,omitempty"     json:"llm_calls,omitempty"`
	ToolCalls   int            `yaml:"tool_calls,omitempty"    json:"tool_calls,omitempty"`
	// UsedParams records the effective generation parameters sent to the LLM.
	// Nil/zero fields were not set (provider default was used).
	UsedParams *UsedParams `yaml:"used_params,omitempty"  json:"used_params,omitempty"`
	// Fields needed to replay the conversation to the LLM (tool messages).
	ToolCallID string `yaml:"tool_call_id,omitempty" json:"tool_call_id,omitempty"`
	Name       string `yaml:"name,omitempty"        json:"name,omitempty"`
	// InlineToolCalls holds the tool-call requests for transient intermediate
	// assistant messages. Tagged yaml:"-" so they are never written to disk.
	InlineToolCalls []MessageToolCall `yaml:"-" json:"-"`
	Transient       bool              `yaml:"-" json:"-"`
	// Trace holds the raw LLM round-trip data for this assistant reply.
	// It is cleaned up by the background trace purge job after TraceTTL.
	Trace []LLMRound `yaml:"trace,omitempty" json:"trace,omitempty"`
}

// Conversation is the top-level unit that the storage layer persists.
type Conversation struct {
	TenantID                  string      `yaml:"tenant_id"  json:"tenant_id,omitempty"`
	UserID                    string      `yaml:"user_id"    json:"user_id,omitempty"`
	ID                        string      `yaml:"id"         json:"id"`
	Title                     string      `yaml:"title"      json:"title"`
	Model                     string      `yaml:"model"      json:"model"`
	Provider                  string      `yaml:"provider,omitempty"      json:"provider,omitempty"`
	SystemPrompt              string      `yaml:"system_prompt,omitempty" json:"system_prompt,omitempty"`
	Params                    *UsedParams `yaml:"params,omitempty"        json:"params,omitempty"`
	Pinned                    bool        `yaml:"pinned,omitempty" json:"pinned,omitempty"`
	CompactedThroughMessageID string      `yaml:"compacted_through_message_id,omitempty" json:"compacted_through_message_id,omitempty"`
	CompactSummaryMessageID   string      `yaml:"compact_summary_message_id,omitempty" json:"compact_summary_message_id,omitempty"`
	CreatedAt                 time.Time   `yaml:"created_at" json:"created_at"`
	UpdatedAt                 time.Time   `yaml:"updated_at" json:"updated_at"`
	Messages                  []Message   `yaml:"messages"   json:"messages"`
}

// Store is the persistence interface. Every method is synchronous and
// thread-safe. Implementations may block on I/O.
type Store interface {
	// Save creates or fully replaces the conversation record.
	Save(scope Scope, c *Conversation) error

	// Load returns the conversation with the given ID, or ErrNotFound.
	Load(scope Scope, id string) (*Conversation, error)

	// List returns lightweight metadata for all conversations
	// (Messages field is empty) ordered newest-first.
	List(scope Scope) ([]*Conversation, error)

	// Delete permanently removes the conversation.
	Delete(scope Scope, id string) error

	// PurgeTraces removes the Trace field from all assistant messages whose
	// SentAt is before cutoff. Only files that are actually modified are rewritten.
	PurgeTraces(cutoff time.Time) error
}

// ToOpenAI converts storage messages back to the openai SDK type.
func ToOpenAI(msgs []Message) []openai.ChatCompletionMessage {
	out := make([]openai.ChatCompletionMessage, 0, len(msgs))
	for _, m := range msgs {
		if m.Role == MessageRoleError {
			continue
		}
		msg := openai.ChatCompletionMessage{
			Role:       m.Role,
			Content:    m.Content,
			ToolCallID: m.ToolCallID,
			Name:       m.Name,
		}
		if m.CompactSummary {
			continue
		}
		for _, tc := range m.InlineToolCalls {
			msg.ToolCalls = append(msg.ToolCalls, openai.ToolCall{
				ID:   tc.ID,
				Type: openai.ToolTypeFunction,
				Function: openai.FunctionCall{
					Name:      tc.Name,
					Arguments: tc.Arguments,
				},
			})
		}
		out = append(out, msg)
	}
	return out
}

// FromOpenAI converts openai SDK messages to storage messages.
func FromOpenAI(msgs []openai.ChatCompletionMessage) []Message {
	out := make([]Message, len(msgs))
	for i, m := range msgs {
		out[i] = Message{
			Role:       m.Role,
			Content:    m.Content,
			ToolCallID: m.ToolCallID,
			Name:       m.Name,
		}
	}
	return out
}
