// Package storage defines the persistence interface for chat conversations.
// The interface is intentionally small so future backends (SQLite, Postgres,
// Redis, etc.) can be added by implementing Store without touching any other
// package.
package storage

import (
	"time"

	openai "github.com/sashabaranov/go-openai"
)

// Message is a single turn in a conversation.
// Only user and assistant messages are persisted for display; intermediate
// tool/function messages are stored for LLM context but carry no display metadata.
type Message struct {
	ID      string    `yaml:"id"      json:"id"`
	Role    string    `yaml:"role"    json:"role"`
	Content string    `yaml:"content" json:"content"`
	SentAt  time.Time `yaml:"sent_at" json:"sent_at"`
	// Metadata — non-zero only for final assistant replies.
	Model       string `yaml:"model,omitempty"         json:"model,omitempty"`
	TimeTakenMs int64  `yaml:"time_taken_ms,omitempty" json:"time_taken_ms,omitempty"`
	// Fields needed to replay the conversation to the LLM (tool messages).
	ToolCallID string `yaml:"tool_call_id,omitempty" json:"tool_call_id,omitempty"`
	Name       string `yaml:"name,omitempty"        json:"name,omitempty"`
}

// Conversation is the top-level unit that the storage layer persists.
type Conversation struct {
	ID        string    `yaml:"id"         json:"id"`
	Title     string    `yaml:"title"      json:"title"`
	Model     string    `yaml:"model"      json:"model"`
	Pinned    bool      `yaml:"pinned,omitempty" json:"pinned,omitempty"`
	CreatedAt time.Time `yaml:"created_at" json:"created_at"`
	UpdatedAt time.Time `yaml:"updated_at" json:"updated_at"`
	Messages  []Message `yaml:"messages"   json:"messages"`
}

// Store is the persistence interface. Every method is synchronous and
// thread-safe. Implementations may block on I/O.
type Store interface {
	// Save creates or fully replaces the conversation record.
	Save(c *Conversation) error

	// Load returns the conversation with the given ID, or ErrNotFound.
	Load(id string) (*Conversation, error)

	// List returns lightweight metadata for all conversations
	// (Messages field is empty) ordered newest-first.
	List() ([]*Conversation, error)

	// Delete permanently removes the conversation.
	Delete(id string) error
}

// ToOpenAI converts storage messages back to the openai SDK type.
func ToOpenAI(msgs []Message) []openai.ChatCompletionMessage {
	out := make([]openai.ChatCompletionMessage, len(msgs))
	for i, m := range msgs {
		out[i] = openai.ChatCompletionMessage{
			Role:       m.Role,
			Content:    m.Content,
			ToolCallID: m.ToolCallID,
			Name:       m.Name,
		}
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
