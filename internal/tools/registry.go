package tools

import (
	"context"
	"encoding/json"
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

func (r *Registry) Register(t Tool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.tools[t.Name()] = t
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
