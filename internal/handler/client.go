package handler

import (
	"net/http"

	"promptd/internal/llmlog"

	openai "github.com/sashabaranov/go-openai"
	"go.uber.org/zap"
)

// NewLLMClient builds an OpenAI-compatible client wired with the llmlog HTTP transport.
// Use this to create the shared client that is passed to both Handler and scheduler.Runner.
func NewLLMClient(apiKey, baseURL string, log *zap.Logger) *openai.Client {
	cfg := openai.DefaultConfig(apiKey)
	cfg.BaseURL = baseURL
	cfg.HTTPClient = &http.Client{Transport: llmlog.NewTransport(nil, log)}
	return openai.NewClientWithConfig(cfg)
}
