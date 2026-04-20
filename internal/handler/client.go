package handler

import (
	"context"
	"fmt"
	"net/http"

	"promptd/internal/llm"
	"promptd/internal/llmlog"

	openai "github.com/openai/openai-go/v3"
	"github.com/openai/openai-go/v3/option"
	"go.uber.org/zap"
)

func NewLLMHTTPClient(log *zap.Logger) *http.Client {
	return &http.Client{Transport: llmlog.NewTransport(nil, log)}
}

// NewLLMClient builds an OpenAI-compatible client wired with the llmlog HTTP transport.
// Use this to create the shared client that is passed to both Handler and scheduler.Runner.
func NewLLMClient(apiKey, baseURL string, httpClient *http.Client) *openai.Client {
	options := []option.RequestOption{option.WithAPIKey(apiKey), option.WithBaseURL(baseURL)}
	if httpClient != nil {
		options = append(options, option.WithHTTPClient(httpClient))
	}
	client := openai.NewClient(options...)
	return &client
}

func createRawChatCompletion(ctx context.Context, entry *ProviderEntry, body any) (llm.ChatCompletionResponse, error) {
	var resp llm.ChatCompletionResponse
	if entry == nil || entry.Client == nil {
		return resp, fmt.Errorf("provider client not configured")
	}
	if err := entry.Client.Execute(ctx, http.MethodPost, "chat/completions", body, &resp); err != nil {
		return resp, err
	}
	return resp, nil
}
