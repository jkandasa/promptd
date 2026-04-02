package tools

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

// RemoteTool implements Tool by calling a remote tool HTTP server.
// Metadata is fetched once at construction time and cached.
type RemoteTool struct {
	baseURL   string
	name      string
	desc      string
	params    any
	multiTool bool // true = server hosts multiple tools; include name in /execute
	client    *http.Client
}

type describeResponse struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"`
}

type executeResponse struct {
	Result string `json:"result"`
	Error  string `json:"error"`
}

// NewRemoteTool contacts baseURL/describe expecting a single-tool response object.
// Use NewRemoteTools when the server may host multiple tools.
func NewRemoteTool(baseURL string) (*RemoteTool, error) {
	tools, err := NewRemoteTools(baseURL)
	if err != nil {
		return nil, err
	}
	if len(tools) != 1 {
		return nil, fmt.Errorf("tool server %s returned %d tools; use NewRemoteTools", baseURL, len(tools))
	}
	return tools[0], nil
}

// NewRemoteTools contacts baseURL/describe and returns all tools advertised by
// the server. It handles both single-object and array responses automatically.
func NewRemoteTools(baseURL string) ([]*RemoteTool, error) {
	client := &http.Client{Timeout: 10 * time.Second}

	resp, err := client.Get(baseURL + "/describe")
	if err != nil {
		return nil, fmt.Errorf("could not reach tool server at %s: %w", baseURL, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("tool server %s returned status %d on /describe", baseURL, resp.StatusCode)
	}

	var body json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("invalid /describe response from %s: %w", baseURL, err)
	}

	// Detect single object vs array.
	var metas []describeResponse
	if len(body) > 0 && body[0] == '[' {
		if err := json.Unmarshal(body, &metas); err != nil {
			return nil, fmt.Errorf("invalid /describe array from %s: %w", baseURL, err)
		}
	} else {
		var single describeResponse
		if err := json.Unmarshal(body, &single); err != nil {
			return nil, fmt.Errorf("invalid /describe object from %s: %w", baseURL, err)
		}
		metas = []describeResponse{single}
	}

	if len(metas) == 0 {
		return nil, fmt.Errorf("tool server %s returned no tools", baseURL)
	}

	multiTool := len(metas) > 1
	out := make([]*RemoteTool, 0, len(metas))
	for _, meta := range metas {
		if meta.Name == "" {
			return nil, fmt.Errorf("tool server %s returned a tool with empty name", baseURL)
		}
		var params any
		if err := json.Unmarshal(meta.Parameters, &params); err != nil {
			return nil, fmt.Errorf("invalid parameters schema for %q from %s: %w", meta.Name, baseURL, err)
		}
		out = append(out, &RemoteTool{
			baseURL:   baseURL,
			name:      meta.Name,
			desc:      meta.Description,
			params:    params,
			multiTool: multiTool,
			client:    client,
		})
	}
	return out, nil
}

func (r *RemoteTool) Name() string        { return r.name }
func (r *RemoteTool) Description() string { return r.desc }
func (r *RemoteTool) Parameters() any     { return r.params }

func (r *RemoteTool) Execute(ctx context.Context, args json.RawMessage) (string, error) {
	var payload any
	if r.multiTool {
		payload = struct {
			Name string          `json:"name"`
			Args json.RawMessage `json:"args"`
		}{Name: r.name, Args: args}
	} else {
		payload = struct {
			Args json.RawMessage `json:"args"`
		}{Args: args}
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("failed to marshal args: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, r.baseURL+"/execute", bytes.NewReader(body))
	if err != nil {
		return "", fmt.Errorf("failed to build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := r.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("tool server %s /execute failed: %w", r.baseURL, err)
	}
	defer resp.Body.Close()

	var result executeResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("invalid /execute response from %s: %w", r.baseURL, err)
	}
	if result.Error != "" {
		return "", fmt.Errorf("%s", result.Error)
	}
	return result.Result, nil
}
