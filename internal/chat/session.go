package chat

import (
	"sync"
	"time"
	"unicode/utf8"

	"chatbot/internal/storage"

	"github.com/google/uuid"
	openai "github.com/sashabaranov/go-openai"
)

// Session holds the in-memory conversation state for a single chat session.
// It is backed by a storage.Store so every mutation is persisted.
type Session struct {
	mu    sync.Mutex
	conv  storage.Conversation // authoritative record (id, title, model, messages…)
	store storage.Store        // may be nil (no persistence)
}

// ID returns the session / conversation ID.
func (s *Session) ID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.conv.ID
}

// Title returns the human-readable conversation title.
func (s *Session) Title() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.conv.Title
}

// Add appends a plain role/content message and persists. Returns the new message ID.
func (s *Session) Add(role, content string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	id := uuid.New().String()
	s.conv.Messages = append(s.conv.Messages, storage.Message{ID: id, Role: role, Content: content, SentAt: time.Now()})
	s.conv.UpdatedAt = time.Now()
	// Auto-title from first user message (truncated to 60 runes).
	if s.conv.Title == "" && role == openai.ChatMessageRoleUser {
		s.conv.Title = truncate(content, 60)
	}
	s.persist()
	return id
}

// AddFinalMessage appends the final assistant reply with its associated
// performance metadata. Returns the new message ID.
func (s *Session) AddFinalMessage(msg openai.ChatCompletionMessage, model string, timeTakenMs int64, llmCalls int, toolCalls int) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	id := uuid.New().String()
	s.conv.Messages = append(s.conv.Messages, storage.Message{
		ID:          id,
		Role:        msg.Role,
		Content:     msg.Content,
		ToolCallID:  msg.ToolCallID,
		Name:        msg.Name,
		SentAt:      time.Now(),
		Model:       model,
		TimeTakenMs: timeTakenMs,
		LLMCalls:    llmCalls,
		ToolCalls:   toolCalls,
	})
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return id
}

// AddMessage appends an openai message to the in-memory history for LLM context
// but does NOT persist it to storage. Only user and assistant messages are stored.
func (s *Session) AddMessage(msg openai.ChatCompletionMessage) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.conv.Messages = append(s.conv.Messages, storage.Message{
		ID:         uuid.New().String(),
		Role:       msg.Role,
		Content:    msg.Content,
		ToolCallID: msg.ToolCallID,
		Name:       msg.Name,
		SentAt:     time.Now(),
		Transient:  true,
	})
	s.conv.UpdatedAt = time.Now()
	// Intentionally no s.persist() call — tool and intermediate assistant messages
	// are kept in memory for LLM context only and are never written to disk.
}

// SetModel records the user's explicit model choice for this conversation.
// Pass an empty string to clear it (i.e. revert to auto).
func (s *Session) SetModel(model string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.conv.Model == model {
		return
	}
	s.conv.Model = model
	s.conv.UpdatedAt = time.Now()
	s.persist()
}

// SetSystemPrompt records the user's explicit system prompt name.
// Pass an empty string to clear it.
func (s *Session) SetSystemPrompt(promptName string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.conv.SystemPrompt == promptName {
		return
	}
	s.conv.SystemPrompt = promptName
	s.conv.UpdatedAt = time.Now()
	s.persist()
}

// SystemPrompt returns the selected system prompt name for this conversation.
func (s *Session) SystemPrompt() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.conv.SystemPrompt
}

// History returns a copy of the message slice as openai messages.
func (s *Session) History() []openai.ChatCompletionMessage {
	s.mu.Lock()
	defer s.mu.Unlock()
	return storage.ToOpenAI(s.conv.Messages)
}

// Reset clears the message history and resets the title.
func (s *Session) Reset() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.conv.Messages = nil
	s.conv.Title = ""
	s.conv.Model = ""
	s.conv.SystemPrompt = ""
	s.conv.UpdatedAt = time.Now()
	s.persist()
}

// Snapshot returns a copy of the underlying Conversation (with messages).
func (s *Session) Snapshot() storage.Conversation {
	s.mu.Lock()
	defer s.mu.Unlock()
	c := s.conv
	msgs := make([]storage.Message, len(s.conv.Messages))
	copy(msgs, s.conv.Messages)
	c.Messages = msgs
	return c
}

// persist saves to the store while already holding s.mu — callers must hold the lock.
// Only user and assistant messages are written; tool/intermediate messages are
// kept in memory for LLM context but are never stored on disk.
func (s *Session) persist() {
	if s.store == nil {
		return
	}
	c := s.conv
	msgs := make([]storage.Message, 0, len(s.conv.Messages))
	for _, m := range s.conv.Messages {
		if !m.Transient && (m.Role == openai.ChatMessageRoleUser || m.Role == openai.ChatMessageRoleAssistant) {
			msgs = append(msgs, m)
		}
	}
	c.Messages = msgs
	_ = s.store.Save(&c) // best-effort; errors are silent to avoid blocking callers
}

// truncate shortens s to at most n runes, appending "…" if cut.
func truncate(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	runes := []rune(s)
	return string(runes[:n]) + "…"
}

// ── SessionStore ──────────────────────────────────────────────────────────────

// SessionStore manages in-memory sessions, optionally backed by a storage.Store.
type SessionStore struct {
	mu       sync.Mutex
	sessions map[string]*Session
	store    storage.Store // may be nil
}

const sessionTTL = 24 * time.Hour

// NewSessionStore returns a store backed by the given storage.Store (may be nil).
func NewSessionStore(st storage.Store) *SessionStore {
	ss := &SessionStore{
		sessions: make(map[string]*Session),
		store:    st,
	}
	go ss.evictLoop()
	return ss
}

// Get returns the in-memory session for id, loading from storage if necessary.
// A brand-new session is created if neither cache nor storage has it.
func (ss *SessionStore) Get(id string) *Session {
	ss.mu.Lock()
	defer ss.mu.Unlock()

	if s, ok := ss.sessions[id]; ok {
		return s
	}

	// Try to restore from storage.
	var conv storage.Conversation
	if ss.store != nil {
		if c, err := ss.store.Load(id); err == nil {
			conv = *c
		}
	}

	// If storage had nothing, initialise a fresh record.
	if conv.ID == "" {
		conv = storage.Conversation{
			ID:        id,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
	}

	s := &Session{conv: conv, store: ss.store}
	ss.sessions[id] = s
	return s
}

// Delete removes the session from cache and from storage.
func (ss *SessionStore) Delete(id string) error {
	ss.mu.Lock()
	delete(ss.sessions, id)
	ss.mu.Unlock()

	if ss.store != nil {
		if err := ss.store.Delete(id); err != nil && err != storage.ErrNotFound {
			return err
		}
	}
	return nil
}

// DeleteMessage removes a single message (by msgID) from the in-memory session
// and persists the updated conversation. If the session is not in the cache it
// is loaded from storage, mutated, and saved back.
func (ss *SessionStore) DeleteMessage(convID, msgID string) error {
	// Obtain the in-memory session (loads from storage if not cached).
	s := ss.Get(convID)

	s.mu.Lock()
	defer s.mu.Unlock()

	found := false
	filtered := s.conv.Messages[:0]
	for _, m := range s.conv.Messages {
		if m.ID == msgID {
			found = true
			continue
		}
		filtered = append(filtered, m)
	}
	if !found {
		return storage.ErrNotFound
	}
	s.conv.Messages = filtered
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return nil
}

// DeleteMessagesFrom removes the message with msgID and all messages that follow
// it (i.e. the edited message plus any subsequent turns) from both the in-memory
// session and storage. Used when a user edits a message — the old content and
// everything that came after it are discarded so the LLM can be re-prompted.
func (ss *SessionStore) DeleteMessagesFrom(convID, msgID string) error {
	s := ss.Get(convID)

	s.mu.Lock()
	defer s.mu.Unlock()

	found := false
	var trimmed []storage.Message
	for _, m := range s.conv.Messages {
		if m.ID == msgID {
			found = true
			break // drop this message and everything after it
		}
		trimmed = append(trimmed, m)
	}
	if !found {
		return storage.ErrNotFound
	}
	s.conv.Messages = trimmed
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return nil
}

// RenameTitle sets a new title for the conversation and persists it.
func (ss *SessionStore) RenameTitle(id, title string) error {
	s := ss.Get(id)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.conv.Title = title
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return nil
}

// TogglePin flips the pinned state of the conversation and persists it.
// Returns the new pinned value.
func (ss *SessionStore) TogglePin(id string) (bool, error) {
	s := ss.Get(id)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.conv.Pinned = !s.conv.Pinned
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return s.conv.Pinned, nil
}

// evictLoop periodically removes idle in-memory sessions (they can be reloaded
// from storage on next access).
func (ss *SessionStore) evictLoop() {
	ticker := time.NewTicker(sessionTTL / 2)
	defer ticker.Stop()
	for range ticker.C {
		ss.evict()
	}
}

func (ss *SessionStore) evict() {
	cutoff := time.Now().Add(-sessionTTL)
	ss.mu.Lock()
	defer ss.mu.Unlock()
	for id, s := range ss.sessions {
		s.mu.Lock()
		lu := s.conv.UpdatedAt
		s.mu.Unlock()
		if lu.Before(cutoff) {
			delete(ss.sessions, id)
		}
	}
}
