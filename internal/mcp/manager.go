package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"promptd/internal/tools"

	"github.com/mark3labs/mcp-go/mcp"
	"go.uber.org/zap"
)

const (
	defaultHealthInterval    = 15 * time.Second
	defaultHealthMaxFails    = 3
	defaultHealthTimeout     = 5 * time.Second
	defaultReconnectInterval = 30 * time.Second
	defaultCallTimeout       = 30 * time.Second
	defaultRediscoveryTimeout = 10 * time.Second
)

// Manager manages multiple MCP server connections and their tools.
type Manager struct {
	registry                *tools.Registry
	log                     *zap.Logger
	servers                 map[string]*MCPServer // url -> server
	mu                      sync.RWMutex
	healthCancel            context.CancelFunc
	pendingReconnect        map[string]pendingInfo // url -> reconnect state
	reregistering           map[string]bool        // url -> in-progress reconnect guard
	healthMaxFails          int
	healthInterval          time.Duration
	reconnectInterval       time.Duration
	toolRediscoveryInterval time.Duration // 0 = disabled
}

// pendingInfo tracks reconnect state for a server that is not currently connected.
type pendingInfo struct {
	auth                    map[string]string
	headers                 map[string]string
	reconnectInterval       time.Duration
	healthMaxFails          int
	healthInterval          time.Duration
	toolRediscoveryInterval time.Duration
	timeout                 time.Duration
	insecure                bool
	nextRetry               time.Time
}

// NewManager creates a new MCP manager.
func NewManager(registry *tools.Registry, log *zap.Logger, healthMaxFails int, healthInterval time.Duration, reconnectInterval time.Duration, toolRediscoveryInterval time.Duration) *Manager {
	if healthMaxFails <= 0 {
		healthMaxFails = defaultHealthMaxFails
	}
	if healthInterval <= 0 {
		healthInterval = defaultHealthInterval
	}
	if reconnectInterval <= 0 {
		reconnectInterval = defaultReconnectInterval
	}
	return &Manager{
		registry:                registry,
		log:                     log,
		servers:                 make(map[string]*MCPServer),
		pendingReconnect:        make(map[string]pendingInfo),
		reregistering:           make(map[string]bool),
		healthMaxFails:          healthMaxFails,
		healthInterval:          healthInterval,
		reconnectInterval:       reconnectInterval,
		toolRediscoveryInterval: toolRediscoveryInterval,
	}
}

// ServerConfig holds per-server overrides passed to Register and QueueRetry.
// Zero values mean "use the manager global default".
type ServerConfig struct {
	ReconnectInterval       time.Duration
	HealthMaxFails          int
	HealthInterval          time.Duration
	ToolRediscoveryInterval time.Duration
	Timeout                 time.Duration
	Insecure                bool
}

// Register connects to an MCP server, lists its tools, and registers them.
// cfg carries optional per-server overrides; zero values fall back to the
// manager's global defaults.
func (m *Manager) Register(ctx context.Context, url string, auth map[string]string, headers map[string]string, cfg ServerConfig) ([]string, error) {
	if cfg.ReconnectInterval <= 0 {
		cfg.ReconnectInterval = m.reconnectInterval
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = defaultCallTimeout
	}
	if cfg.ToolRediscoveryInterval <= 0 {
		cfg.ToolRediscoveryInterval = m.toolRediscoveryInterval
	}

	// Connect outside the lock (network call — can be slow).
	server, err := ConnectMCPAuth(ctx, url, auth, headers, cfg.Insecure)
	if err != nil {
		return nil, err
	}
	server.ReconnectInterval = cfg.ReconnectInterval
	server.HealthMaxFails = cfg.HealthMaxFails
	server.HealthInterval = cfg.HealthInterval
	server.ToolRediscoveryInterval = cfg.ToolRediscoveryInterval
	server.Timeout = cfg.Timeout
	server.Insecure = cfg.Insecure

	var registered []string
	for _, tool := range server.Tools {
		name, err := m.registerToolOnServer(server, tool)
		if err != nil {
			// Roll back any tools already registered from this server.
			for _, rn := range registered {
				m.registry.Remove(rn)
			}
			server.Close()
			return nil, fmt.Errorf("failed to register tool %q: %w", tool.Name, err)
		}
		registered = append(registered, name)
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
	m.mu.Unlock()

	m.log.Info("MCP server registered",
		zap.String("url", url),
		zap.Strings("tools", registered),
		zap.Int("health_max_fails", server.HealthMaxFails),
		zap.Duration("health_interval", server.HealthInterval),
		zap.Duration("tool_rediscovery_interval", server.ToolRediscoveryInterval),
		zap.Duration("reconnect_interval", server.ReconnectInterval),
		zap.Duration("timeout", server.Timeout),
		zap.Bool("insecure", server.Insecure))
	return registered, nil
}

// registerToolOnServer builds and registers one tool from an MCPServer into the registry.
func (m *Manager) registerToolOnServer(server *MCPServer, tool mcp.Tool) (string, error) {
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

	cClient := server.Client
	cTimeout := server.Timeout

	execute := func(ctx context.Context, args string) (string, error) {
		var parsed map[string]any
		if args != "" {
			if err := json.Unmarshal([]byte(args), &parsed); err != nil {
				return "", fmt.Errorf("invalid args for %q: %w", toolName, err)
			}
		}
		callCtx, cancel := context.WithTimeout(ctx, cTimeout)
		defer cancel()
		result, err := CallTool(callCtx, cClient, toolName, parsed)
		if err != nil {
			return "", err
		}
		for _, content := range result.Content {
			if tc, ok := mcp.AsTextContent(content); ok {
				return tc.Text, nil
			}
		}
		return "", fmt.Errorf("tool %q returned no text content", toolName)
	}

	if err := m.registry.RegisterRaw(toolName, toolDesc, schema, execute); err != nil {
		return "", err
	}
	return toolName, nil
}

// toolEqual reports whether two MCP tool definitions are identical (name, description, schema).
func toolEqual(a, b mcp.Tool) bool {
	if a.Name != b.Name || a.Description != b.Description {
		return false
	}
	ba, err1 := json.Marshal(a.InputSchema)
	bb, err2 := json.Marshal(b.InputSchema)
	if err1 != nil || err2 != nil {
		return false
	}
	return string(ba) == string(bb)
}

// rediscoverTools fetches the current tool list from a connected server, diffs it
// against what is registered, and syncs additions, removals, and updates.
func (m *Manager) rediscoverTools(ctx context.Context, url string, server *MCPServer) {
	listCtx, cancel := context.WithTimeout(ctx, defaultRediscoveryTimeout)
	freshTools, err := ListTools(listCtx, server.Client)
	cancel()
	if err != nil {
		m.log.Warn("tool rediscovery: list tools failed", zap.String("url", url), zap.Error(err))
		return
	}

	freshByName := make(map[string]mcp.Tool, len(freshTools))
	for _, t := range freshTools {
		freshByName[t.Name] = t
	}

	// Snapshot the current tool list without holding the lock during network I/O.
	server.mu.RLock()
	currentTools := make([]mcp.Tool, len(server.Tools))
	copy(currentTools, server.Tools)
	server.mu.RUnlock()

	currentByName := make(map[string]mcp.Tool, len(currentTools))
	for _, t := range currentTools {
		currentByName[t.Name] = t
	}

	var added, removed, updated []string

	// Detect removed or updated tools.
	for name, old := range currentByName {
		fresh, stillPresent := freshByName[name]
		if !stillPresent {
			m.registry.Remove(name)
			removed = append(removed, name)
			continue
		}
		if !toolEqual(old, fresh) {
			m.registry.Remove(name)
			if _, err := m.registerToolOnServer(server, fresh); err != nil {
				m.log.Warn("tool rediscovery: failed to re-register updated tool",
					zap.String("url", url), zap.String("tool", name), zap.Error(err))
			} else {
				updated = append(updated, name)
			}
		}
	}

	// Detect newly added tools.
	for name, fresh := range freshByName {
		if _, exists := currentByName[name]; !exists {
			if _, err := m.registerToolOnServer(server, fresh); err != nil {
				m.log.Warn("tool rediscovery: failed to register new tool",
					zap.String("url", url), zap.String("tool", name), zap.Error(err))
			} else {
				added = append(added, name)
			}
		}
	}

	// Commit the fresh snapshot to the server.
	server.mu.Lock()
	server.Tools = freshTools
	server.mu.Unlock()

	if len(added)+len(removed)+len(updated) > 0 {
		m.log.Info("tool rediscovery: tools updated",
			zap.String("url", url),
			zap.Strings("added", added),
			zap.Strings("removed", removed),
			zap.Strings("updated", updated))
	} else {
		m.log.Debug("tool rediscovery: no changes", zap.String("url", url))
	}
}

// QueueRetry schedules a background reconnect for a server that failed to
// connect (e.g. at startup). The first attempt fires on the next health tick.
func (m *Manager) QueueRetry(url string, auth map[string]string, headers map[string]string, cfg ServerConfig) {
	if cfg.ReconnectInterval <= 0 {
		cfg.ReconnectInterval = m.reconnectInterval
	}
	if cfg.ToolRediscoveryInterval <= 0 {
		cfg.ToolRediscoveryInterval = m.toolRediscoveryInterval
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, exists := m.pendingReconnect[url]; !exists {
		m.pendingReconnect[url] = pendingInfo{
			auth:                    auth,
			headers:                 headers,
			reconnectInterval:       cfg.ReconnectInterval,
			healthMaxFails:          cfg.HealthMaxFails,
			healthInterval:          cfg.HealthInterval,
			toolRediscoveryInterval: cfg.ToolRediscoveryInterval,
			timeout:                 cfg.Timeout,
			insecure:                cfg.Insecure,
			nextRetry:               time.Now(), // attempt on the next health tick
		}
	}
}

// Unregister disconnects from an MCP server, removes all its tools, and
// schedules a background reconnect attempt.
func (m *Manager) Unregister(url string) error {
	m.mu.Lock()
	server, exists := m.servers[url]
	if !exists {
		m.mu.Unlock()
		return fmt.Errorf("no MCP server registered at %s", url)
	}
	delete(m.servers, url)
	// Schedule reconnect preserving the server's own per-server settings.
	ri := server.ReconnectInterval
	if ri <= 0 {
		ri = m.reconnectInterval
	}
	m.pendingReconnect[url] = pendingInfo{
		auth:                    server.Auth,
		headers:                 server.Headers,
		reconnectInterval:       ri,
		healthMaxFails:          server.HealthMaxFails,
		healthInterval:          server.HealthInterval,
		toolRediscoveryInterval: server.ToolRediscoveryInterval,
		timeout:                 server.Timeout,
		insecure:                server.Insecure,
		nextRetry:               time.Now().Add(ri),
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

// StartHealthMonitor starts the background health check and reconnect loop.
func (m *Manager) StartHealthMonitor(ctx context.Context) {
	globalInterval := m.healthInterval
	globalMaxFails := m.healthMaxFails

	healthCtx, cancel := context.WithCancel(ctx)
	m.mu.Lock()
	m.healthCancel = cancel
	m.mu.Unlock()

	go func() {
		// The ticker runs at the global interval (the shortest meaningful period).
		// Per-server intervals are enforced via nextCheck / nextRediscovery below.
		ticker := time.NewTicker(globalInterval)
		defer ticker.Stop()

		failCounts := make(map[string]int)
		nextCheck := make(map[string]time.Time) // per-server next health-check time
		nextRediscovery := make(map[string]time.Time) // per-server next tool-rediscovery time
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
				// Snapshot pending reconnects.
				pendingURLs := make([]string, 0, len(m.pendingReconnect))
				pendingInfos := make(map[string]pendingInfo)
				for url, info := range m.pendingReconnect {
					pendingURLs = append(pendingURLs, url)
					pendingInfos[url] = info
				}
				m.mu.RUnlock()

				// ── Health-check registered servers ──────────────────────────
				for _, url := range urls {
					server := servers[url]
					if server == nil {
						continue
					}

					// Honour per-server health_interval if set.
					si := server.HealthInterval
					if si <= 0 {
						si = globalInterval
					}
					if t, ok := nextCheck[url]; ok && time.Now().Before(t) {
						continue
					}
					nextCheck[url] = time.Now().Add(si)

					checkCtx, checkCancel := context.WithTimeout(healthCtx, defaultHealthTimeout)
					err := Ping(checkCtx, server.Client)
					if err != nil {
						_, err = ListTools(checkCtx, server.Client)
					}
					checkCancel()

					// Honour per-server health_max_failures if set.
					smf := server.HealthMaxFails
					if smf <= 0 {
						smf = globalMaxFails
					}

					failMu.Lock()
					if err != nil {
						failCounts[url]++
						m.log.Warn("MCP server health check failed",
							zap.String("url", url),
							zap.Int("fails", failCounts[url]),
							zap.Int("threshold", smf),
							zap.Error(err))
						if failCounts[url] >= smf {
							m.log.Warn("MCP server exceeded failure threshold, removing",
								zap.String("url", url), zap.Int("fails", failCounts[url]), zap.Int("threshold", smf))
							delete(failCounts, url)
							delete(nextCheck, url)
							delete(nextRediscovery, url)
							go func(u string) {
								if err := m.Unregister(u); err != nil {
									m.log.Error("failed to unregister unhealthy MCP server",
										zap.String("url", u), zap.Error(err))
								}
							}(url)
						}
					} else {
						failCounts[url] = 0
					}
					failMu.Unlock()
				}

				// ── Periodic tool rediscovery ─────────────────────────────────
				for _, url := range urls {
					server := servers[url]
					if server == nil {
						continue
					}
					ri := server.ToolRediscoveryInterval
					if ri <= 0 {
						continue // disabled for this server
					}
					if t, ok := nextRediscovery[url]; ok && time.Now().Before(t) {
						continue
					}
					nextRediscovery[url] = time.Now().Add(ri)
					go m.rediscoverTools(healthCtx, url, server)
				}

				// ── Reconnect pending servers ─────────────────────────────────
				for _, url := range pendingURLs {
					info := pendingInfos[url]

					// Skip if already registered (reconnected by another path).
					m.mu.RLock()
					_, alreadyRegistered := m.servers[url]
					m.mu.RUnlock()
					if alreadyRegistered {
						m.mu.Lock()
						delete(m.pendingReconnect, url)
						m.mu.Unlock()
						continue
					}

					// Not time yet — wait for the retry interval to elapse.
					if time.Now().Before(info.nextRetry) {
						continue
					}

					// Skip if a reconnect goroutine is already running for this URL.
					m.mu.Lock()
					if m.reregistering[url] {
						m.mu.Unlock()
						continue
					}
					m.reregistering[url] = true
					m.mu.Unlock()

					m.log.Info("attempting MCP server reconnect", zap.String("url", url))
					go func(u string, pi pendingInfo) {
						defer func() {
							m.mu.Lock()
							delete(m.reregistering, u)
							m.mu.Unlock()
						}()

						scfg := ServerConfig{
							ReconnectInterval:       pi.reconnectInterval,
							HealthMaxFails:          pi.healthMaxFails,
							HealthInterval:          pi.healthInterval,
							ToolRediscoveryInterval: pi.toolRediscoveryInterval,
							Timeout:                 pi.timeout,
							Insecure:                pi.insecure,
						}
						_, err := m.Register(healthCtx, u, pi.auth, pi.headers, scfg)
						if err != nil {
							m.log.Warn("MCP server reconnect failed, will retry",
								zap.String("url", u),
								zap.Duration("reconnect_in", pi.reconnectInterval),
								zap.Error(err))
							// Push nextRetry forward so we rate-limit attempts.
							m.mu.Lock()
							if existing, ok := m.pendingReconnect[u]; ok {
								existing.nextRetry = time.Now().Add(existing.reconnectInterval)
								m.pendingReconnect[u] = existing
							}
							m.mu.Unlock()
							return
						}
						m.log.Info("MCP server reconnected successfully", zap.String("url", u))
						m.mu.Lock()
						delete(m.pendingReconnect, u)
						m.mu.Unlock()
					}(url, info)
				}
			}
		}
	}()
}

// StopHealthMonitor stops the health check and reconnect loop.
func (m *Manager) StopHealthMonitor() {
	m.mu.Lock()
	if m.healthCancel != nil {
		m.healthCancel()
		m.healthCancel = nil
	}
	m.mu.Unlock()
}
