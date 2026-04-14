package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"chatbot/internal/tools"

	"github.com/mark3labs/mcp-go/client"
	"github.com/mark3labs/mcp-go/client/transport"
	"github.com/mark3labs/mcp-go/mcp"
	"go.uber.org/zap"
)

const (
	defaultHealthInterval = 15 * time.Second
	defaultHealthMaxFails = 3
	defaultHealthTimeout  = 5 * time.Second
)

// Manager manages multiple MCP server connections and their tools.
type Manager struct {
	registry       *tools.Registry
	log            *zap.Logger
	servers        map[string]*MCPServer // url -> server
	mu             sync.RWMutex
	healthCancel   context.CancelFunc
	removedServers map[string]removedServerInfo // url -> server config for re-registration
	reregistering  map[string]bool              // url -> in-progress re-registration guard
	healthMaxFails int
	healthInterval time.Duration
}

type removedServerInfo struct {
	auth    map[string]string
	headers map[string]string
}

// NewManager creates a new MCP manager.
func NewManager(registry *tools.Registry, log *zap.Logger, healthMaxFails int, healthInterval time.Duration) *Manager {
	if healthMaxFails <= 0 {
		healthMaxFails = defaultHealthMaxFails
	}
	if healthInterval <= 0 {
		healthInterval = defaultHealthInterval
	}
	return &Manager{
		registry:       registry,
		log:            log,
		servers:        make(map[string]*MCPServer),
		removedServers: make(map[string]removedServerInfo),
		reregistering:  make(map[string]bool),
		healthMaxFails: healthMaxFails,
		healthInterval: healthInterval,
	}
}

// Register connects to an MCP server with optional auth, lists its tools, and registers them.
// The registration is performed under a single lock acquisition to avoid TOCTOU races.
func (m *Manager) Register(ctx context.Context, url string, auth map[string]string, headers map[string]string) ([]string, error) {
	// Connect outside the lock (network call — can be slow).
	server, err := ConnectMCPAuth(ctx, url, auth, headers)
	if err != nil {
		return nil, err
	}

	var registered []string
	for _, tool := range server.Tools {
		toolName := tool.Name
		toolDesc := tool.Description

		schemaBytes, err := json.Marshal(tool.InputSchema)
		schema := map[string]any{}
		if err == nil {
			if jsonErr := json.Unmarshal(schemaBytes, &schema); jsonErr != nil {
				m.log.Warn("failed to unmarshal tool schema, using empty schema",
					zap.String("tool", toolName), zap.Error(jsonErr))
				schema = map[string]any{}
			}
		}
		if len(schema) == 0 {
			schema = map[string]any{"type": "object"}
		}

		cName := toolName
		cClient := server.Client

		execute := func(ctx context.Context, args string) (string, error) {
			var parsed map[string]any
			if args != "" {
				if err := json.Unmarshal([]byte(args), &parsed); err != nil {
					return "", fmt.Errorf("invalid args for %q: %w", cName, err)
				}
			}

			result, err := CallTool(ctx, cClient, cName, parsed)
			if err != nil {
				return "", err
			}

			for _, content := range result.Content {
				if tc, ok := mcp.AsTextContent(content); ok {
					return tc.Text, nil
				}
			}
			return "", fmt.Errorf("tool %q returned no text content", cName)
		}

		if err := m.registry.RegisterRaw(toolName, toolDesc, schema, execute); err != nil {
			// Roll back any tools already registered from this server.
			for _, rn := range registered {
				m.registry.Remove(rn)
			}
			server.Close()
			return nil, fmt.Errorf("failed to register tool %q: %w", toolName, err)
		}
		registered = append(registered, toolName)
	}

	// Acquire the lock only to update the server map — after the slow network work is done.
	m.mu.Lock()
	if _, exists := m.servers[url]; exists {
		m.mu.Unlock()
		// Another goroutine registered the same URL while we were connecting; roll back.
		for _, rn := range registered {
			m.registry.Remove(rn)
		}
		server.Close()
		return nil, fmt.Errorf("MCP server already registered at %s", url)
	}
	m.servers[url] = server
	// Always store auth/headers so the health monitor can re-register if the server drops.
	m.removedServers[url] = removedServerInfo{auth: auth, headers: headers}
	m.mu.Unlock()

	m.log.Info("MCP server registered", zap.String("url", url), zap.Strings("tools", registered))
	return registered, nil
}

// Unregister disconnects from an MCP server and removes all its tools.
func (m *Manager) Unregister(url string) error {
	m.mu.Lock()
	server, exists := m.servers[url]
	if !exists {
		m.mu.Unlock()
		return fmt.Errorf("no MCP server registered at %s", url)
	}
	delete(m.servers, url)
	m.mu.Unlock()

	for _, name := range server.ToolNames() {
		m.registry.Remove(name)
	}

	if err := server.Close(); err != nil {
		m.log.Warn("error closing MCP server connection", zap.String("url", url), zap.Error(err))
	}

	m.log.Info("MCP server unregistered", zap.String("url", url))
	return nil
}

// List returns all registered MCP servers and their tools.
func (m *Manager) List() map[string][]string {
	m.mu.RLock()
	defer m.mu.RUnlock()

	result := make(map[string][]string, len(m.servers))
	for url, server := range m.servers {
		result[url] = server.ToolNames()
	}
	return result
}

// StartHealthMonitor starts the background health check loop.
func (m *Manager) StartHealthMonitor(ctx context.Context) {
	interval := m.healthInterval
	maxFails := m.healthMaxFails

	healthCtx, cancel := context.WithCancel(ctx)
	m.mu.Lock()
	m.healthCancel = cancel
	m.mu.Unlock()

	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		failCounts := make(map[string]int)
		var failMu sync.Mutex

		for {
			select {
			case <-healthCtx.Done():
				return
			case <-ticker.C:
				m.mu.RLock()
				urls := make([]string, 0, len(m.servers))
				servers := make(map[string]*MCPServer, len(m.servers))
				for url, server := range m.servers {
					urls = append(urls, url)
					servers[url] = server
				}
				// Snapshot removed servers for re-registration attempts.
				removedURLs := make([]string, 0, len(m.removedServers))
				removedInfos := make(map[string]removedServerInfo)
				for url, info := range m.removedServers {
					removedURLs = append(removedURLs, url)
					removedInfos[url] = info
				}
				m.mu.RUnlock()

				// ── Health-check registered servers ──────────────────────────
				for _, url := range urls {
					server := servers[url]
					if server == nil {
						continue
					}

					checkCtx, checkCancel := context.WithTimeout(healthCtx, defaultHealthTimeout)
					err := Ping(checkCtx, server.Client)
					if err != nil {
						_, err = ListTools(checkCtx, server.Client)
					}
					checkCancel()

					failMu.Lock()
					if err != nil {
						failCounts[url]++
						if failCounts[url] >= maxFails {
							m.log.Warn("MCP server health check failed, removing", zap.String("url", url), zap.Int("fails", failCounts[url]))
							delete(failCounts, url)
							go func(u string) {
								if err := m.Unregister(u); err != nil {
									m.log.Error("failed to unregister unhealthy MCP server", zap.String("url", u), zap.Error(err))
								}
							}(url)
						}
					} else {
						failCounts[url] = 0
					}
					failMu.Unlock()
				}

				// ── Try to re-register recovered servers ─────────────────────
				for _, url := range removedURLs {
					info := removedInfos[url]

					// Skip if a re-registration is already in progress for this URL.
					m.mu.Lock()
					if m.reregistering[url] {
						m.mu.Unlock()
						continue
					}
					m.mu.Unlock()

					checkCtx, checkCancel := context.WithTimeout(healthCtx, defaultHealthTimeout)
					testErr := pingURL(checkCtx, url, info.auth, info.headers)
					checkCancel()

					if testErr != nil {
						continue
					}

					// Server is reachable — attempt re-registration in a goroutine.
					// Set the in-progress flag before launching the goroutine so that
					// the next health tick doesn't spawn a duplicate.
					m.mu.Lock()
					if m.reregistering[url] {
						// Another tick raced us here.
						m.mu.Unlock()
						continue
					}
					m.reregistering[url] = true
					m.mu.Unlock()

					failMu.Lock()
					delete(failCounts, url)
					failMu.Unlock()

					m.log.Info("MCP server recovered, re-registering", zap.String("url", url))
					go func(u string, auth map[string]string, headers map[string]string) {
						defer func() {
							m.mu.Lock()
							delete(m.reregistering, u)
							m.mu.Unlock()
						}()

						_, err := m.Register(healthCtx, u, auth, headers)
						if err != nil {
							m.log.Error("failed to re-register MCP server", zap.String("url", u), zap.Error(err))
							return
						}
						// Remove from removedServers only after successful re-registration.
						m.mu.Lock()
						delete(m.removedServers, u)
						m.mu.Unlock()
					}(url, info.auth, info.headers)
				}
			}
		}
	}()
}

// pingURL creates a temporary client to test whether a URL is reachable.
func pingURL(ctx context.Context, url string, auth map[string]string, headers map[string]string) error {
	opts := []transport.StreamableHTTPCOption{}
	if token, ok := auth["token"]; ok && token != "" {
		opts = append(opts, transport.WithHTTPHeaders(map[string]string{
			"Authorization": "Bearer " + token,
		}))
	}
	for k, v := range headers {
		opts = append(opts, transport.WithHTTPHeaders(map[string]string{k: v}))
	}
	trans, err := transport.NewStreamableHTTP(url, opts...)
	if err != nil {
		return fmt.Errorf("failed to create transport: %w", err)
	}
	c := client.NewClient(trans)
	defer c.Close()

	if err := Ping(ctx, c); err != nil {
		_, err = ListTools(ctx, c)
		return err
	}
	return nil
}

// StopHealthMonitor stops the health check loop.
func (m *Manager) StopHealthMonitor() {
	m.mu.Lock()
	if m.healthCancel != nil {
		m.healthCancel()
		m.healthCancel = nil
	}
	m.mu.Unlock()
}
