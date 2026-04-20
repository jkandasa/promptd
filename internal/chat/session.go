package chat

import (
	"sync"
	"time"
	"unicode/utf8"

	"promptd/internal/llm"
	"promptd/internal/storage"

	"github.com/google/uuid"
)

// Session holds the in-memory conversation state for a single chat session.
// It is backed by a storage.Store so every mutation is persisted.
type Session struct {
	mu    sync.Mutex
	scope storage.Scope
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

// Add appends a plain role/content message and persists. Optional file metadata is
// kept on the stored message for UI rendering and attachment replay.
func (s *Session) Add(role, content string, files []storage.UploadedFile) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	id := uuid.New().String()
	s.conv.Messages = append(s.conv.Messages, storage.Message{ID: id, Role: role, Content: content, Files: files, SentAt: time.Now()})
	s.conv.UpdatedAt = time.Now()
	// Auto-title from first user message (truncated to 60 runes).
	if s.conv.Title == "" && role == llm.RoleUser {
		s.conv.Title = truncate(content, 60)
	}
	s.persist()
	return id
}

// AddFinalMessage appends the final assistant reply with its associated
// performance metadata and LLM trace. Returns the new message ID.
func (s *Session) AddFinalMessage(msg llm.Message, model, provider string, timeTakenMs int64, llmCalls int, toolCalls int, trace []storage.LLMRound, usedParams *storage.UsedParams) string {
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
		Provider:    provider,
		TimeTakenMs: timeTakenMs,
		LLMCalls:    llmCalls,
		ToolCalls:   toolCalls,
		Trace:       trace,
		UsedParams:  usedParams,
	})
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return id
}

// AddErrorMessage appends a persisted UI-visible error message for the
// conversation. Error messages are intentionally excluded from future LLM
// context, but remain part of the stored conversation transcript.
func (s *Session) AddErrorMessage(content, model, provider string) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	id := uuid.New().String()
	s.conv.Messages = append(s.conv.Messages, storage.Message{
		ID:       id,
		Role:     storage.MessageRoleError,
		Content:  content,
		SentAt:   time.Now(),
		Model:    model,
		Provider: provider,
	})
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return id
}

// AddMessage appends an openai message to the in-memory history for LLM context
// but does NOT persist it to storage. Only user and assistant messages are stored.
func (s *Session) AddMessage(msg llm.Message) {
	s.mu.Lock()
	defer s.mu.Unlock()
	sm := storage.Message{
		ID:         uuid.New().String(),
		Role:       msg.Role,
		Content:    msg.Content,
		ToolCallID: msg.ToolCallID,
		Name:       msg.Name,
		SentAt:     time.Now(),
		Transient:  true,
	}
	for _, tc := range msg.ToolCalls {
		sm.InlineToolCalls = append(sm.InlineToolCalls, storage.MessageToolCall{
			ID:        tc.ID,
			Name:      tc.Function.Name,
			Arguments: tc.Function.Arguments,
		})
	}
	s.conv.Messages = append(s.conv.Messages, sm)
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

// SetProvider records the user's explicit provider choice for this conversation.
// Pass an empty string to clear it (i.e. revert to auto).
func (s *Session) SetProvider(provider string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.conv.Provider == provider {
		return
	}
	s.conv.Provider = provider
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

// SetParams records the user's current LLM parameter overrides for the conversation.
// Pass nil to clear stored params (revert to config defaults).
func (s *Session) SetParams(p *storage.UsedParams) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.conv.Params = p
	s.conv.UpdatedAt = time.Now()
	s.persist()
}

// UpdateMessageFiles replaces the stored file metadata for a single message.
// This is used to persist provider-side file references after lazy uploads.
func (s *Session) UpdateMessageFiles(msgID string, files []storage.UploadedFile) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	for i := range s.conv.Messages {
		if s.conv.Messages[i].ID != msgID {
			continue
		}
		s.conv.Messages[i].Files = files
		s.conv.UpdatedAt = time.Now()
		s.persist()
		return true
	}
	return false
}

// SystemPrompt returns the selected system prompt name for this conversation.
func (s *Session) SystemPrompt() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.conv.SystemPrompt
}

// History returns a copy of the message slice as openai messages.
func (s *Session) History() []llm.Message {
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
	s.conv.CompactSummaryMessageID = ""
	s.conv.CompactedThroughMessageID = ""
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

func (s *Session) CompactSummaryMessageID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.conv.CompactSummaryMessageID
}

func (s *Session) CompactedThroughMessageID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.conv.CompactedThroughMessageID
}

func (s *Session) SetCompactionSummary(content, compactPrompt, model, provider string, compactedThroughMessageID string, timeTakenMs int64, llmCalls int, trace []storage.LLMRound) string {
	s.mu.Lock()
	defer s.mu.Unlock()
	msgID := s.conv.CompactSummaryMessageID
	if msgID == "" {
		msgID = uuid.New().String()
	}
	msg := storage.Message{
		ID:             msgID,
		Role:           llm.RoleAssistant,
		Content:        content,
		SentAt:         time.Now(),
		Model:          model,
		Provider:       provider,
		TimeTakenMs:    timeTakenMs,
		LLMCalls:       llmCalls,
		Trace:          trace,
		CompactSummary: true,
	}
	filtered := s.conv.Messages[:0]
	for _, existing := range s.conv.Messages {
		if existing.ID == s.conv.CompactSummaryMessageID || existing.CompactSummary {
			continue
		}
		filtered = append(filtered, existing)
	}
	s.conv.Messages = append(filtered, msg)
	s.conv.CompactSummaryMessageID = msgID
	s.conv.CompactedThroughMessageID = compactedThroughMessageID
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return msgID
}

func (s *Session) ClearCompaction() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.conv.CompactSummaryMessageID == "" && s.conv.CompactedThroughMessageID == "" {
		return false
	}
	filtered := s.conv.Messages[:0]
	for _, m := range s.conv.Messages {
		if m.ID == s.conv.CompactSummaryMessageID || m.CompactSummary {
			continue
		}
		filtered = append(filtered, m)
	}
	s.conv.Messages = filtered
	s.conv.CompactSummaryMessageID = ""
	s.conv.CompactedThroughMessageID = ""
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return true
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
		if !m.Transient && (m.Role == llm.RoleUser || m.Role == llm.RoleAssistant || m.Role == storage.MessageRoleError) {
			msgs = append(msgs, m)
		}
	}
	c.Messages = msgs
	_ = s.store.Save(s.scope, &c) // best-effort; errors are silent to avoid blocking callers
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
func sessionKey(scope storage.Scope, id string) string {
	return scope.Key() + ":" + id
}

func (ss *SessionStore) Get(scope storage.Scope, id string) *Session {
	ss.mu.Lock()
	defer ss.mu.Unlock()
	key := sessionKey(scope, id)

	if s, ok := ss.sessions[key]; ok {
		return s
	}

	// Try to restore from storage.
	var conv storage.Conversation
	if ss.store != nil {
		if c, err := ss.store.Load(scope, id); err == nil {
			conv = *c
		}
	}

	// If storage had nothing, initialise a fresh record.
	if conv.ID == "" {
		conv = storage.Conversation{
			TenantID:  scope.TenantID,
			UserID:    scope.UserID,
			ID:        id,
			CreatedAt: time.Now(),
			UpdatedAt: time.Now(),
		}
	}

	s := &Session{scope: scope, conv: conv, store: ss.store}
	ss.sessions[key] = s
	return s
}

// Delete removes the session from cache and from storage.
func (ss *SessionStore) Delete(scope storage.Scope, id string) error {
	ss.mu.Lock()
	delete(ss.sessions, sessionKey(scope, id))
	ss.mu.Unlock()

	if ss.store != nil {
		if err := ss.store.Delete(scope, id); err != nil && err != storage.ErrNotFound {
			return err
		}
	}
	return nil
}

// DeleteMessage removes a single message (by msgID) from the in-memory session
// and persists the updated conversation. If the session is not in the cache it
// is loaded from storage, mutated, and saved back.
func (ss *SessionStore) DeleteMessage(scope storage.Scope, convID, msgID string) error {
	// Obtain the in-memory session (loads from storage if not cached).
	s := ss.Get(scope, convID)

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.conv.CompactSummaryMessageID == msgID {
		filtered := s.conv.Messages[:0]
		for _, m := range s.conv.Messages {
			if m.ID == s.conv.CompactSummaryMessageID || m.CompactSummary {
				continue
			}
			filtered = append(filtered, m)
		}
		s.conv.Messages = filtered
		s.conv.CompactSummaryMessageID = ""
		s.conv.CompactedThroughMessageID = ""
		s.conv.UpdatedAt = time.Now()
		s.persist()
		return nil
	}

	found := false
	filtered := s.conv.Messages[:0]
	for _, m := range s.conv.Messages {
		if (s.conv.CompactSummaryMessageID != "" || s.conv.CompactedThroughMessageID != "") && (m.ID == s.conv.CompactSummaryMessageID || m.CompactSummary) {
			continue
		}
		if m.ID == msgID {
			found = true
			continue
		}
		filtered = append(filtered, m)
	}
	if !found {
		return storage.ErrNotFound
	}
	if s.conv.CompactSummaryMessageID != "" || s.conv.CompactedThroughMessageID != "" {
		s.conv.CompactSummaryMessageID = ""
		s.conv.CompactedThroughMessageID = ""
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
func (ss *SessionStore) DeleteMessagesFrom(scope storage.Scope, convID, msgID string) error {
	s := ss.Get(scope, convID)

	s.mu.Lock()
	defer s.mu.Unlock()

	found := false
	var trimmed []storage.Message
	for _, m := range s.conv.Messages {
		if m.ID == s.conv.CompactSummaryMessageID || m.CompactSummary {
			continue
		}
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
	s.conv.CompactSummaryMessageID = ""
	s.conv.CompactedThroughMessageID = ""
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return nil
}

// RenameTitle sets a new title for the conversation and persists it.
func (ss *SessionStore) RenameTitle(scope storage.Scope, id, title string) error {
	s := ss.Get(scope, id)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.conv.Title = title
	s.conv.UpdatedAt = time.Now()
	s.persist()
	return nil
}

// TogglePin flips the pinned state of the conversation and persists it.
// Returns the new pinned value.
func (ss *SessionStore) TogglePin(scope storage.Scope, id string) (bool, error) {
	s := ss.Get(scope, id)
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
