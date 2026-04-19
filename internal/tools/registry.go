package tools

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"sync"

	openai "github.com/sashabaranov/go-openai"
)

// Tool is the interface every tool must implement.
type Tool interface {
	Name() string
	Description() string
	// Parameters returns a JSON Schema object describing the tool's arguments.
	Parameters() any
	Execute(ctx context.Context, args json.RawMessage) (string, error)
}

// Registry holds registered tools and converts them for the LLM.
// All methods are safe for concurrent use.
type Registry struct {
	mu    sync.RWMutex
	tools map[string]Tool
}

func NewRegistry() *Registry {
	return &Registry{tools: make(map[string]Tool)}
}

// Register adds a tool to the registry. Returns error if tool name already exists.
func (r *Registry) Register(t Tool) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, exists := r.tools[t.Name()]; exists {
		return fmt.Errorf("tool %q already registered", t.Name())
	}
	r.tools[t.Name()] = t
	return nil
}

// RegisterRaw registers a tool by its properties directly. Returns error if name conflicts.
func (r *Registry) RegisterRaw(name, description string, parameters any, execute func(ctx context.Context, args string) (string, error)) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, exists := r.tools[name]; exists {
		return fmt.Errorf("tool %q already registered", name)
	}
	r.tools[name] = &wrappedTool{
		name:        name,
		description: description,
		parameters:  parameters,
		execute:     execute,
	}
	return nil
}

type wrappedTool struct {
	name        string
	description string
	parameters  any
	execute     func(ctx context.Context, args string) (string, error)
}

func (w *wrappedTool) Name() string        { return w.name }
func (w *wrappedTool) Description() string { return w.description }
func (w *wrappedTool) Parameters() any     { return w.parameters }
func (w *wrappedTool) Execute(ctx context.Context, args json.RawMessage) (string, error) {
	return w.execute(ctx, string(args))
}

func (r *Registry) Remove(name string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.tools, name)
}

func (r *Registry) Get(name string) (Tool, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	t, ok := r.tools[name]
	return t, ok
}

func (r *Registry) Empty() bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.tools) == 0
}

// Names returns the names of all currently registered tools.
func (r *Registry) Names() []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	names := make([]string, 0, len(r.tools))
	for name := range r.tools {
		names = append(names, name)
	}
	return names
}

// ToolInfo is a slim summary of a registered tool for API responses.
type ToolInfo struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters,omitempty"`
}

// List returns name+description for every registered tool, sorted by name.
func (r *Registry) List() []ToolInfo {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]ToolInfo, 0, len(r.tools))
	for _, t := range r.tools {
		var params json.RawMessage
		if p := t.Parameters(); p != nil {
			b, err := json.Marshal(p)
			if err == nil && string(b) != "null" {
				params = json.RawMessage(b)
			}
		}
		out = append(out, ToolInfo{Name: t.Name(), Description: t.Description(), Parameters: params})
	}
	// Sort for stable ordering.
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func (r *Registry) ListByNames(names []string) []ToolInfo {
	allowed := make(map[string]bool, len(names))
	for _, name := range names {
		allowed[name] = true
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]ToolInfo, 0, len(allowed))
	for _, t := range r.tools {
		if !allowed[t.Name()] {
			continue
		}
		var params json.RawMessage
		if p := t.Parameters(); p != nil {
			b, err := json.Marshal(p)
			if err == nil && string(b) != "null" {
				params = json.RawMessage(b)
			}
		}
		out = append(out, ToolInfo{Name: t.Name(), Description: t.Description(), Parameters: params})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// OpenAITools converts all registered tools to the format expected by go-openai.
func (r *Registry) OpenAITools() []openai.Tool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]openai.Tool, 0, len(r.tools))
	for _, t := range r.tools {
		out = append(out, openai.Tool{
			Type: openai.ToolTypeFunction,
			Function: &openai.FunctionDefinition{
				Name:        t.Name(),
				Description: t.Description(),
				Parameters:  t.Parameters(),
			},
		})
	}
	return out
}

func (r *Registry) OpenAIToolsByNames(names []string) []openai.Tool {
	allowed := make(map[string]bool, len(names))
	for _, name := range names {
		allowed[name] = true
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]openai.Tool, 0, len(allowed))
	for _, t := range r.tools {
		if !allowed[t.Name()] {
			continue
		}
		out = append(out, openai.Tool{
			Type: openai.ToolTypeFunction,
			Function: &openai.FunctionDefinition{
				Name:        t.Name(),
				Description: t.Description(),
				Parameters:  t.Parameters(),
			},
		})
	}
	return out
}
