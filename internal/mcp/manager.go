package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"sync"
	"time"

	"chatbot/internal/tools"

	"go.uber.org/zap"
)

const (
	defaultHealthInterval = 15 * time.Second
	defaultHealthMaxFails = 3
	defaultHealthTimeout  = 5 * time.Second
)

// Config represents MCP server configuration.
type Config struct {
	URL     string            `yaml:"url"`
	Auth    map[string]string `yaml:"auth,omitempty"`
	Headers map[string]string `yaml:"headers,omitempty"`
	Enabled bool              `yaml:"enabled"`
}

// LoadConfig loads MCP servers from a YAML file.
func LoadConfig(path string) ([]Config, error) {
	if path == "" {
		return nil, nil
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("failed to read MCP config: %w", err)
	}

	var cfg struct {
		MCPServers []Config `yaml:"mcp_servers"`
	}
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse MCP config: %w", err)
	}

	var servers []Config
	for _, s := range cfg.MCPServers {
		if s.Enabled {
			servers = append(servers, s)
		}
	}
	return servers, nil
}

// Manager manages multiple MCP server connections and their tools.
type Manager struct {
	registry     *tools.Registry
	log          *zap.Logger
	servers      map[string]*MCPServer // url -> server
	mu           sync.RWMutex
	healthCancel context.CancelFunc
}

// NewManager creates a new MCP manager.
func NewManager(registry *tools.Registry, log *zap.Logger) *Manager {
	return &Manager{
		registry: registry,
		log:      log,
		servers:  make(map[string]*MCPServer),
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
	interval := parseDuration(os.Getenv("MCP_HEALTH_INTERVAL"), defaultHealthInterval)
	maxFails := parseInt(os.Getenv("MCP_HEALTH_MAX_FAILURES"), defaultHealthMaxFails)

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

func parseDuration(s string, def time.Duration) time.Duration {
	if s == "" {
		return def
	}
	d, err := time.ParseDuration(s)
	if err != nil {
		return def
	}
	return d
}

func parseInt(s string, def int) int {
	if s == "" {
		return def
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	return v
}
