// Package storage provides YAML-backed conversation persistence.
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

const tsLayout = "20060102-150405"

type YAMLStore struct {
	root string
	mu   sync.RWMutex
}

func NewYAMLStore(root string) (*YAMLStore, error) {
	if err := os.MkdirAll(root, 0o755); err != nil {
		return nil, err
	}
	return &YAMLStore{root: root}, nil
}

func (s *YAMLStore) scopeDir(scope Scope) string {
	return filepath.Join(s.root, "tenants", scope.TenantID, "users", scope.UserID, "conversations")
}

func (s *YAMLStore) ensureScopeDir(scope Scope) error {
	return os.MkdirAll(s.scopeDir(scope), 0o755)
}

func filename(c *Conversation) string {
	return c.CreatedAt.UTC().Format(tsLayout) + "-" + c.ID
}

func (s *YAMLStore) findFile(dir, id string) string {
	matches := s.findFiles(dir, id)
	if len(matches) == 0 {
		return ""
	}
	return matches[0]
}

func (s *YAMLStore) findFiles(dir, id string) []string {
	suffix := "-" + id + ".yaml"
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var matches []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), suffix) {
			matches = append(matches, filepath.Join(dir, e.Name()))
		}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(matches)))
	return matches
}

func (s *YAMLStore) Save(scope Scope, c *Conversation) error {
	if err := s.ensureScopeDir(scope); err != nil {
		return err
	}
	c.TenantID = scope.TenantID
	c.UserID = scope.UserID
	data, err := yaml.Marshal(c)
	if err != nil {
		return err
	}
	dir := s.scopeDir(scope)
	target := filepath.Join(dir, filename(c)+".yaml")
	tmp := target + ".tmp"

	s.mu.Lock()
	defer s.mu.Unlock()
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return err
	}
	if err := os.Rename(tmp, target); err != nil {
		return err
	}
	for _, existing := range s.findFiles(dir, c.ID) {
		if existing == target {
			continue
		}
		if err := os.Remove(existing); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	return nil
}

func (s *YAMLStore) Load(scope Scope, id string) (*Conversation, error) {
	dir := s.scopeDir(scope)
	s.mu.RLock()
	paths := s.findFiles(dir, id)
	s.mu.RUnlock()
	if len(paths) == 0 {
		return nil, ErrNotFound
	}
	var firstErr error
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		var c Conversation
		if err := yaml.Unmarshal(data, &c); err != nil {
			if firstErr == nil {
				firstErr = errors.New(path + ": " + err.Error())
			}
			continue
		}
		if c.TenantID != "" && c.TenantID != scope.TenantID {
			continue
		}
		if c.UserID != "" && c.UserID != scope.UserID {
			continue
		}
		return &c, nil
	}
	if firstErr != nil {
		return nil, firstErr
	}
	return nil, ErrNotFound
}

func (s *YAMLStore) List(scope Scope) ([]*Conversation, error) {
	dir := s.scopeDir(scope)
	if err := s.ensureScopeDir(scope); err != nil {
		return nil, err
	}
	s.mu.RLock()
	entries, err := os.ReadDir(dir)
	s.mu.RUnlock()
	if err != nil {
		return nil, err
	}
	var convs []*Conversation
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yaml") {
			continue
		}
		stem := strings.TrimSuffix(e.Name(), ".yaml")
		if len(stem) <= 16 {
			continue
		}
		id := stem[16:]
		c, err := s.Load(scope, id)
		if err != nil {
			return nil, err
		}
		convs = append(convs, &Conversation{
			TenantID:                  c.TenantID,
			UserID:                    c.UserID,
			ID:                        c.ID,
			Title:                     c.Title,
			Model:                     c.Model,
			Provider:                  c.Provider,
			SystemPrompt:              c.SystemPrompt,
			Params:                    c.Params,
			Pinned:                    c.Pinned,
			CompactedThroughMessageID: c.CompactedThroughMessageID,
			CompactSummaryMessageID:   c.CompactSummaryMessageID,
			CreatedAt:                 c.CreatedAt,
			UpdatedAt:                 c.UpdatedAt,
		})
	}
	sort.Slice(convs, func(i, j int) bool {
		return convs[i].UpdatedAt.After(convs[j].UpdatedAt)
	})
	return convs, nil
}

func (s *YAMLStore) Delete(scope Scope, id string) error {
	dir := s.scopeDir(scope)
	s.mu.Lock()
	defer s.mu.Unlock()
	path := s.findFile(dir, id)
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

func (s *YAMLStore) PurgeTraces(cutoff time.Time) error {
	root := filepath.Join(s.root, "tenants")
	return filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() || !strings.HasSuffix(d.Name(), ".yaml") {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return nil
		}
		var c Conversation
		if err := yaml.Unmarshal(data, &c); err != nil {
			return nil
		}
		changed := false
		for i := range c.Messages {
			if len(c.Messages[i].Trace) > 0 && c.Messages[i].SentAt.Before(cutoff) {
				c.Messages[i].Trace = nil
				changed = true
			}
		}
		if !changed {
			return nil
		}
		updated, err := yaml.Marshal(&c)
		if err != nil {
			return nil
		}
		tmp := path + ".tmp"
		if err := os.WriteFile(tmp, updated, 0o644); err != nil {
			return nil
		}
		return os.Rename(tmp, path)
	})
}
