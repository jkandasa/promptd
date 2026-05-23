package handler

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"

	"gopkg.in/yaml.v3"
)

type ManagedSystemPrompt struct {
	Name    string `yaml:"name" json:"name"`
	Content string `yaml:"content" json:"content"`
}

type SystemPromptStore struct {
	path string
	mu   sync.Mutex
}

func NewSystemPromptStore(path string) *SystemPromptStore {
	return &SystemPromptStore{path: path}
}

func (s *SystemPromptStore) LoadOrBootstrap(prompts map[string]string) ([]ManagedSystemPrompt, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	loaded, err := s.loadLocked()
	if err == nil {
		return loaded, nil
	}
	if !os.IsNotExist(err) {
		return nil, err
	}
	items := make([]ManagedSystemPrompt, 0, len(prompts))
	for name, content := range prompts {
		items = append(items, ManagedSystemPrompt{Name: name, Content: content})
	}
	sortPrompts(items)
	if err := s.saveLocked(items); err != nil {
		return nil, err
	}
	return items, nil
}

func (s *SystemPromptStore) Save(items []ManagedSystemPrompt) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.saveLocked(items)
}

func (s *SystemPromptStore) loadLocked() ([]ManagedSystemPrompt, error) {
	content, err := os.ReadFile(s.path)
	if err != nil {
		return nil, err
	}
	var items []ManagedSystemPrompt
	if err := yaml.Unmarshal(content, &items); err != nil {
		return nil, err
	}
	sortPrompts(items)
	return items, nil
}

func (s *SystemPromptStore) saveLocked(items []ManagedSystemPrompt) error {
	seen := map[string]bool{}
	for i := range items {
		items[i].Name = strings.TrimSpace(items[i].Name)
		if items[i].Name == "" {
			return fmt.Errorf("system prompt name is required")
		}
		if seen[items[i].Name] {
			return fmt.Errorf("duplicate system prompt %q", items[i].Name)
		}
		seen[items[i].Name] = true
	}
	sortPrompts(items)
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	content, err := yaml.Marshal(items)
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, content, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

func sortPrompts(items []ManagedSystemPrompt) {
	sort.Slice(items, func(i, j int) bool { return items[i].Name < items[j].Name })
}

func SystemPromptMap(items []ManagedSystemPrompt) (map[string]string, []SystemPromptInfo) {
	prompts := make(map[string]string, len(items))
	infos := make([]SystemPromptInfo, 0, len(items))
	for _, item := range items {
		prompts[item.Name] = item.Content
		infos = append(infos, SystemPromptInfo{Name: item.Name})
	}
	return prompts, infos
}
