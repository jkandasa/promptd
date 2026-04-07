package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sync"
	"time"

	"chatbot/internal/tools"

	"github.com/mark3labs/mcp-go/client"
	"github.com/mark3labs/mcp-go/client/transport"
	"go.uber.org/zap"
	"gopkg.in/yaml.v3"
)

const (
	defaultHealthInterval = 15 * time.Second
	defaultHealthMaxFails = 3
	defaultHealthTimeout  = 5 * time.Second
)

// Config represents MCP server configuration.
type Config struct {
	URL               string            `yaml:"url"`
	Auth              map[string]string `yaml:"auth,omitempty"`
	Headers           map[string]string `yaml:"headers,omitempty"`
	Enabled           bool              `yaml:"enabled"`
	HealthMaxFailures *int              `yaml:"health_max_failures,omitempty"`
}

// GlobalConfig represents the global MCP configuration.
type GlobalConfig struct {
	HealthMaxFailures *int     `yaml:"health_max_failures,omitempty"`
	Servers           []Config `yaml:"servers"`
}

// LoadConfig loads MCP servers from a YAML file.
func LoadConfig(path string) ([]Config, GlobalConfig, error) {
	if path == "" {
		return nil, GlobalConfig{}, nil
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, GlobalConfig{}, nil
		}
		return nil, GlobalConfig{}, fmt.Errorf("failed to read MCP config: %w", err)
	}

	var cfg GlobalConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, GlobalConfig{}, fmt.Errorf("failed to parse MCP config: %w", err)
	}

	var servers []Config
	for _, s := range cfg.Servers {
		if s.Enabled {
			servers = append(servers, s)
		}
	}
	return servers, cfg, nil
}

// Manager manages multiple MCP server connections and their tools.
type Manager struct {
	registry       *tools.Registry
	log            *zap.Logger
	servers        map[string]*MCPServer // url -> server
	mu             sync.RWMutex
	healthCancel   context.CancelFunc
	removedServers map[string]removedServerInfo // url -> server config for re-registration
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
		healthMaxFails: healthMaxFails,
		healthInterval: healthInterval,
	}
}

// Register connects to an MCP server with optional auth, lists its tools, and registers them.
func (m *Manager) Register(ctx context.Context, url string, auth map[string]string, headers map[string]string) ([]string, error) {
	m.mu.Lock()
	if _, exists := m.servers[url]; exists {
		m.mu.Unlock()
		return nil, fmt.Errorf("MCP server already registered at %s", url)
	}
	m.mu.Unlock()

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
			json.Unmarshal(schemaBytes, &schema)
		}
		if schema == nil {
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
				if tc, ok := content.(interface{ GetText() string }); ok {
					return tc.GetText(), nil
				}
			}
			return "", fmt.Errorf("tool %q returned no text content", cName)
		}

		if err := m.registry.RegisterRaw(toolName, toolDesc, schema, execute); err != nil {
			for _, rn := range registered {
				m.registry.Remove(rn)
			}
			server.Close()
			return nil, fmt.Errorf("failed to register tool %q: %w", toolName, err)
		}
		registered = append(registered, toolName)
	}

	m.mu.Lock()
	m.servers[url] = server
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

	// Store auth/headers for potential re-registration
	if server.Auth != nil || server.Headers != nil {
		m.removedServers[url] = removedServerInfo{auth: server.Auth, headers: server.Headers}
	}

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
				// Also check removed servers
				removedURLs := make([]string, 0, len(m.removedServers))
				removedInfos := make(map[string]removedServerInfo)
				for url, info := range m.removedServers {
					removedURLs = append(removedURLs, url)
					removedInfos[url] = info
				}
				m.mu.RUnlock()

				for _, url := range urls {
					server := servers[url]
					if server == nil {
						continue
					}

					checkCtx, checkCancel := context.WithTimeout(healthCtx, defaultHealthTimeout)

					// Try ping first (lightweight), fall back to ListTools if not supported
					err := Ping(checkCtx, server.Client)
					if err != nil {
						// Fall back to tools/list if ping not supported
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

				// Check removed servers - try to re-register if they recover
				for _, url := range removedURLs {
					info := removedInfos[url]
					if info.auth == nil && info.headers == nil {
						// Was not stored - can't re-register
						continue
					}

					checkCtx, checkCancel := context.WithTimeout(healthCtx, defaultHealthTimeout)

					// Try ping first (lightweight), fall back to ListTools if not supported
					// We need to create a new client to test
					var testErr error
					testClient := func() error {
						opts := []transport.StreamableHTTPCOption{}
						if token, ok := info.auth["token"]; ok && token != "" {
							opts = append(opts, transport.WithHTTPHeaders(map[string]string{
								"Authorization": "Bearer " + token,
							}))
						}
						for k, v := range info.headers {
							opts = append(opts, transport.WithHTTPHeaders(map[string]string{k: v}))
						}
						trans, err := transport.NewStreamableHTTP(url, opts...)
						if err != nil {
							return fmt.Errorf("failed to create transport: %w", err)
						}
						c := client.NewClient(trans)
						defer c.Close()

						testErr = Ping(checkCtx, c)
						if testErr != nil {
							_, testErr = ListTools(checkCtx, c)
						}
						return nil
					}()
					_ = testClient
					checkCancel()

					failMu.Lock()
					if testErr == nil {
						m.log.Info("MCP server recovered, re-registering", zap.String("url", url))
						delete(failCounts, url)
						go func(u string, auth map[string]string, headers map[string]string) {
							_, err := m.Register(healthCtx, u, auth, headers)
							if err != nil {
								m.log.Error("failed to re-register MCP server", zap.String("url", u), zap.Error(err))
								return
							}
							m.mu.Lock()
							delete(m.removedServers, u)
							m.mu.Unlock()
						}(url, info.auth, info.headers)
					}
					failMu.Unlock()
				}
			}
		}
	}()
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
