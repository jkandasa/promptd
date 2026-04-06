package mcp

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/mark3labs/mcp-go/client"
	"github.com/mark3labs/mcp-go/client/transport"
	"github.com/mark3labs/mcp-go/mcp"
)

// MCPServer represents a single connected MCP server.
type MCPServer struct {
	URL    string
	Client *client.Client
	Tools  []mcp.Tool
	mu     sync.RWMutex
}

// ToolNames returns the names of all tools from this server.
func (s *MCPServer) ToolNames() []string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	names := make([]string, 0, len(s.Tools))
	for _, t := range s.Tools {
		names = append(names, t.Name)
	}
	return names
}

// ConnectMCP connects to an MCP server at the given URL with optional auth/headers.
func ConnectMCP(ctx context.Context, url string) (*MCPServer, error) {
	return ConnectMCPAuth(ctx, url, nil, nil)
}

// ConnectMCPAuth connects to an MCP server with optional auth tokens and headers.
func ConnectMCPAuth(ctx context.Context, url string, auth map[string]string, headers map[string]string) (*MCPServer, error) {
	opts := []transport.StreamableHTTPCOption{}

	// Add auth headers
	if token, ok := auth["token"]; ok && token != "" {
		opts = append(opts, transport.WithHTTPHeaders(map[string]string{
			"Authorization": "Bearer " + token,
		}))
	}

	// Add custom headers
	for k, v := range headers {
		opts = append(opts, transport.WithHTTPHeaders(map[string]string{k: v}))
	}

	trans, err := transport.NewStreamableHTTP(url, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to create transport: %w", err)
	}

	c := client.NewClient(trans)

	initCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	initRequest := mcp.InitializeRequest{}
	initRequest.Params.ProtocolVersion = mcp.LATEST_PROTOCOL_VERSION
	initRequest.Params.ClientInfo = mcp.Implementation{
		Name:    "chatbot",
		Version: "1.0.0",
	}
	initRequest.Params.Capabilities = mcp.ClientCapabilities{}

	_, err = c.Initialize(initCtx, initRequest)
	if err != nil {
		trans.Close()
		return nil, fmt.Errorf("failed to initialize MCP server at %s: %w", url, err)
	}

	tools, err := ListTools(ctx, c)
	if err != nil {
		trans.Close()
		return nil, fmt.Errorf("failed to list tools from %s: %w", url, err)
	}

	return &MCPServer{
		URL:    url,
		Client: c,
		Tools:  tools,
	}, nil
}

// ListTools fetches all available tools from the MCP server.
func ListTools(ctx context.Context, c *client.Client) ([]mcp.Tool, error) {
	listCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	request := mcp.ListToolsRequest{}
	resp, err := c.ListTools(listCtx, request)
	if err != nil {
		return nil, fmt.Errorf("failed to list tools: %w", err)
	}

	return resp.Tools, nil
}

// Ping sends a ping to the MCP server to check connectivity.
func Ping(ctx context.Context, c *client.Client) error {
	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	err := c.Ping(pingCtx)
	if err != nil {
		return fmt.Errorf("ping failed: %w", err)
	}
	return nil
}

// CallTool executes a tool on the MCP server.
func CallTool(ctx context.Context, c *client.Client, name string, args map[string]any) (*mcp.CallToolResult, error) {
	callCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	request := mcp.CallToolRequest{}
	request.Params.Name = name
	request.Params.Arguments = args

	result, err := c.CallTool(callCtx, request)
	if err != nil {
		return nil, fmt.Errorf("tool call failed for %q: %w", name, err)
	}

	return result, nil
}

// Close closes the MCP server connection.
func (s *MCPServer) Close() error {
	if s.Client != nil {
		return s.Client.Close()
	}
	return nil
}
