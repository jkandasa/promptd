// Package storage — YAML file-based implementation of Store.
//
// Each conversation is stored as a single YAML file:
//
//	<dir>/<conversation-id>.yaml
//
// This is intentionally simple. The directory acts as the "table"; listing
// conversations is a directory scan. Writes are atomic (write-then-rename).
package storage

import (
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"gopkg.in/yaml.v3"
)

// YAMLStore implements Store using one YAML file per conversation.
type YAMLStore struct {
	dir string
	mu  sync.RWMutex // coarse lock — fine for the expected load
}

// NewYAMLStore returns a YAMLStore that persists conversations under dir.
// The directory is created if it does not exist.
func NewYAMLStore(dir string) (*YAMLStore, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	return &YAMLStore{dir: dir}, nil
}

func (s *YAMLStore) path(id string) string {
	return filepath.Join(s.dir, id+".yaml")
}

// Save serialises the conversation atomically (tmp file → rename).
func (s *YAMLStore) Save(c *Conversation) error {
	data, err := yaml.Marshal(c)
	if err != nil {
		return err
	}

	tmp := s.path(c.ID) + ".tmp"

	s.mu.Lock()
	defer s.mu.Unlock()

	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, s.path(c.ID))
}

// Load reads and deserialises the conversation file.
func (s *YAMLStore) Load(id string) (*Conversation, error) {
	s.mu.RLock()
	data, err := os.ReadFile(s.path(id))
	s.mu.RUnlock()

	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, ErrNotFound
		}
		return nil, err
	}

	var c Conversation
	if err := yaml.Unmarshal(data, &c); err != nil {
		return nil, err
	}
	return &c, nil
}

// List returns metadata for all conversations (Messages omitted), newest first.
func (s *YAMLStore) List() ([]*Conversation, error) {
	s.mu.RLock()
	entries, err := os.ReadDir(s.dir)
	s.mu.RUnlock()

	if err != nil {
		return nil, err
	}

	var convs []*Conversation
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yaml") {
			continue
		}
		// Strip ".yaml" suffix to get the ID, then load header only.
		id := strings.TrimSuffix(e.Name(), ".yaml")
		c, err := s.Load(id)
		if err != nil {
			continue // skip corrupt files
		}
		// Return a lightweight copy without messages.
		convs = append(convs, &Conversation{
			ID:           c.ID,
			Title:        c.Title,
			Model:        c.Model,
			SystemPrompt: c.SystemPrompt,
			Pinned:       c.Pinned,
			CreatedAt:    c.CreatedAt,
			UpdatedAt:    c.UpdatedAt,
		})
	}

	// Sort newest-first by UpdatedAt.
	sort.Slice(convs, func(i, j int) bool {
		return convs[i].UpdatedAt.After(convs[j].UpdatedAt)
	})

	return convs, nil
}

// Delete removes the conversation file.
func (s *YAMLStore) Delete(id string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if err := os.Remove(s.path(id)); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return ErrNotFound
		}
		return err
	}
	return nil
}
