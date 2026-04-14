// Package storage — YAML file-based implementation of Store.
//
// Each conversation is stored as a single YAML file named:
//
//	<dir>/<YYYYMMDD-HHMMSS>-<uuid>.yaml
//
// The timestamp prefix is derived from the conversation's CreatedAt field,
// which makes the files sort chronologically in any file browser.
// Writes are atomic (write to a .tmp file then os.Rename).
package storage

import (
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"gopkg.in/yaml.v3"
)

const tsLayout = "20060102-150405" // matches the desired 20260414-131545 format

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

// filename builds the canonical filename stem for a conversation:
// <YYYYMMDD-HHMMSS>-<uuid>
func filename(c *Conversation) string {
	return c.CreatedAt.UTC().Format(tsLayout) + "-" + c.ID
}

// findFile scans the directory for the file whose name ends with "-<id>.yaml".
// Returns the full path, or "" if not found. Caller must hold at least s.mu.RLock.
func (s *YAMLStore) findFile(id string) string {
	suffix := "-" + id + ".yaml"
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return ""
	}
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), suffix) {
			return filepath.Join(s.dir, e.Name())
		}
	}
	return ""
}

// Save serialises the conversation atomically (tmp file → rename).
func (s *YAMLStore) Save(c *Conversation) error {
	data, err := yaml.Marshal(c)
	if err != nil {
		return err
	}

	target := filepath.Join(s.dir, filename(c)+".yaml")
	tmp := target + ".tmp"

	s.mu.Lock()
	defer s.mu.Unlock()

	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, target)
}

// Load reads and deserialises the conversation file for the given UUID.
func (s *YAMLStore) Load(id string) (*Conversation, error) {
	s.mu.RLock()
	path := s.findFile(id)
	if path == "" {
		s.mu.RUnlock()
		return nil, ErrNotFound
	}
	data, err := os.ReadFile(path)
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
		// Extract the UUID: everything after the timestamp prefix "YYYYMMDD-HHMMSS-".
		// The prefix is exactly len("20060102-150405-") = 16 characters.
		stem := strings.TrimSuffix(e.Name(), ".yaml")
		if len(stem) <= 16 {
			continue // malformed name — skip
		}
		ts, err := time.Parse(tsLayout, stem[:15])
		if err != nil {
			continue // not a recognised prefix — skip
		}
		_ = ts
		id := stem[16:]
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

	path := s.findFile(id)
	if path == "" {
		return ErrNotFound
	}
	if err := os.Remove(path); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return ErrNotFound
		}
		return err
	}
	return nil
}

// PurgeTraces removes the Trace field from all assistant messages whose SentAt
// is before cutoff. Only conversation files that actually contain stale traces
// are rewritten, so the common case (nothing to purge) is cheap.
func (s *YAMLStore) PurgeTraces(cutoff time.Time) error {
	s.mu.RLock()
	entries, err := os.ReadDir(s.dir)
	s.mu.RUnlock()
	if err != nil {
		return err
	}

	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yaml") {
			continue
		}
		stem := strings.TrimSuffix(e.Name(), ".yaml")
		if len(stem) <= 16 {
			continue
		}
		id := stem[16:]

		c, err := s.Load(id)
		if err != nil {
			continue // skip unreadable files
		}

		changed := false
		for i := range c.Messages {
			if len(c.Messages[i].Trace) > 0 && c.Messages[i].SentAt.Before(cutoff) {
				c.Messages[i].Trace = nil
				changed = true
			}
		}
		if changed {
			if err := s.Save(c); err != nil {
				return err
			}
		}
	}
	return nil
}
