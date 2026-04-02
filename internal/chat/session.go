package chat

import (
	"sync"

	openai "github.com/sashabaranov/go-openai"
)

// Session holds the conversation history for a single user session.
type Session struct {
	mu       sync.Mutex
	Messages []openai.ChatCompletionMessage
}

func (s *Session) Add(role, content string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.Messages = append(s.Messages, openai.ChatCompletionMessage{
		Role:    role,
		Content: content,
	})
}

func (s *Session) AddMessage(msg openai.ChatCompletionMessage) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.Messages = append(s.Messages, msg)
}

func (s *Session) History() []openai.ChatCompletionMessage {
	s.mu.Lock()
	defer s.mu.Unlock()
	cp := make([]openai.ChatCompletionMessage, len(s.Messages))
	copy(cp, s.Messages)
	return cp
}

func (s *Session) Reset() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.Messages = nil
}

// SessionStore manages sessions keyed by session ID.
type SessionStore struct {
	mu       sync.Mutex
	sessions map[string]*Session
}

func NewSessionStore() *SessionStore {
	return &SessionStore{sessions: make(map[string]*Session)}
}

func (ss *SessionStore) Get(id string) *Session {
	ss.mu.Lock()
	defer ss.mu.Unlock()
	s, ok := ss.sessions[id]
	if !ok {
		s = &Session{}
		ss.sessions[id] = s
	}
	return s
}
