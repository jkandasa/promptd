package tools

import (
	"context"
	"fmt"
	"net/http"
	"sync"
	"time"

	"go.uber.org/zap"
)

const (
	defaultInterval = 15 * time.Second
	defaultMaxFails = 3
)

// Monitor periodically health-checks remote tool servers and unregisters any
// tools that stop responding after maxFails consecutive failures.
// When a server hosts multiple tools, all of them are removed together.
type Monitor struct {
	registry *Registry
	interval time.Duration
	maxFails int
	log      *zap.Logger
	client   *http.Client

	mu       sync.Mutex
	tracked  map[string]string // tool name → base URL
	failures map[string]int    // base URL → consecutive failure count
}

func NewMonitor(registry *Registry, log *zap.Logger) *Monitor {
	return &Monitor{
		registry: registry,
		interval: defaultInterval,
		maxFails: defaultMaxFails,
		log:      log,
		client:   &http.Client{Timeout: 5 * time.Second},
		tracked:  make(map[string]string),
		failures: make(map[string]int),
	}
}

// SetRegistry sets the registry after construction.
func (m *Monitor) SetRegistry(r *Registry) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.registry = r
}

// Track starts health-checking the tool server at baseURL for the given tool name.
// Multiple tool names can share the same baseURL (multi-tool server).
func (m *Monitor) Track(name, baseURL string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.tracked[name] = baseURL
	m.log.Debug("monitor tracking tool", zap.String("name", name), zap.String("url", baseURL))
}

// Untrack stops monitoring a tool by name.
func (m *Monitor) Untrack(name string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.tracked, name)
}

// UntrackByURL removes all tools hosted at the given base URL from monitoring.
func (m *Monitor) UntrackByURL(baseURL string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for name, url := range m.tracked {
		if url == baseURL {
			delete(m.tracked, name)
		}
	}
	delete(m.failures, baseURL)
}

// NamesByURL returns all tool names currently tracked at the given base URL.
func (m *Monitor) NamesByURL(baseURL string) []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	var names []string
	for name, url := range m.tracked {
		if url == baseURL {
			names = append(names, name)
		}
	}
	return names
}

// Run starts the health-check loop. It blocks until ctx is cancelled.
func (m *Monitor) Run(ctx context.Context) {
	ticker := time.NewTicker(m.interval)
	defer ticker.Stop()
	m.log.Info("heartbeat monitor started",
		zap.Duration("interval", m.interval),
		zap.Int("max_failures", m.maxFails),
	)
	for {
		select {
		case <-ctx.Done():
			m.log.Info("heartbeat monitor stopped")
			return
		case <-ticker.C:
			m.checkAll(ctx)
		}
	}
}

// checkAll pings each unique URL once, then updates all tools at that URL.
func (m *Monitor) checkAll(ctx context.Context) {
	// Snapshot: collect unique URLs and their associated tool names.
	m.mu.Lock()
	urlToNames := make(map[string][]string)
	for name, url := range m.tracked {
		urlToNames[url] = append(urlToNames[url], name)
	}
	m.mu.Unlock()

	for url, names := range urlToNames {
		if err := m.ping(ctx, url); err != nil {
			m.recordFailure(url, names, err)
		} else {
			m.recordSuccess(url, names)
		}
	}
}

func (m *Monitor) ping(ctx context.Context, baseURL string) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL+"/health", nil)
	if err != nil {
		return err
	}
	resp, err := m.client.Do(req)
	if err != nil {
		return err
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("health check returned status %d", resp.StatusCode)
	}
	return nil
}

func (m *Monitor) recordSuccess(url string, names []string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.failures[url] > 0 {
		m.log.Info("tool server recovered",
			zap.String("url", url),
			zap.Strings("tools", names),
		)
		m.failures[url] = 0
	}
}

func (m *Monitor) recordFailure(url string, names []string, err error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.failures[url]++
	count := m.failures[url]

	m.log.Warn("tool server health check failed",
		zap.String("url", url),
		zap.Strings("tools", names),
		zap.Int("consecutive_failures", count),
		zap.Int("max_failures", m.maxFails),
		zap.Error(err),
	)

	if count >= m.maxFails {
		m.log.Warn("unregistering unresponsive tool server",
			zap.String("url", url),
			zap.Strings("tools", names),
		)
		for _, name := range names {
			m.registry.Remove(name)
			delete(m.tracked, name)
		}
		delete(m.failures, url)
	}
}
