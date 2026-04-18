package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"promptd/internal/chat"
	"promptd/internal/handler"
	"promptd/internal/mcp"
	"promptd/internal/scheduler"
	"promptd/internal/storage"
	"promptd/internal/tools"
	"promptd/internal/ui"
	"promptd/internal/version"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"gopkg.in/yaml.v3"
)

// Duration is a time.Duration that also accepts "d" (days) as a unit when
// unmarshalling from YAML. For example "30d" is equivalent to "720h".
type Duration time.Duration

func (d *Duration) UnmarshalYAML(value *yaml.Node) error {
	s := strings.TrimSpace(value.Value)
	// Replace trailing 'd' with the equivalent number of hours so that
	// time.ParseDuration can handle it (e.g. "30d" → "720h").
	if strings.HasSuffix(s, "d") {
		n, err := fmt.Sscanf(s[:len(s)-1], "%f", new(float64))
		if err != nil || n == 0 {
			return fmt.Errorf("invalid duration %q", s)
		}
		var days float64
		fmt.Sscanf(s[:len(s)-1], "%f", &days)
		*d = Duration(time.Duration(days * float64(24*time.Hour)))
		return nil
	}
	td, err := time.ParseDuration(s)
	if err != nil {
		return fmt.Errorf("invalid duration %q: %w", s, err)
	}
	*d = Duration(td)
	return nil
}

// AsDuration returns the underlying time.Duration value.
func (d Duration) AsDuration() time.Duration { return time.Duration(d) }

type LLMParams struct {
	Temperature *float32 `yaml:"temperature,omitempty"`
	MaxTokens   int      `yaml:"max_tokens,omitempty"`
	TopP        *float32 `yaml:"top_p,omitempty"`
	TopK        int      `yaml:"top_k,omitempty"`
}

type LLMModel struct {
	ID     string    `yaml:"id"`
	Name   string    `yaml:"name,omitempty"`
	Params LLMParams `yaml:"params,omitempty"`
}

type AutoDiscoverConfig struct {
	Enabled         *bool         `yaml:"enabled"`
	RefreshInterval time.Duration `yaml:"refresh_interval"`
}

type LLMProviderConfig struct {
	Name            string             `yaml:"name"`
	APIKey          string             `yaml:"api_key"`
	BaseURL         string             `yaml:"base_url"`
	SelectionMethod string             `yaml:"selection_method,omitempty"`
	Models          []LLMModel         `yaml:"models"`
	Params          LLMParams          `yaml:"params"`
	AutoDiscover    AutoDiscoverConfig `yaml:"auto_discover"`
}

type SystemPromptConfig struct {
	Name string `yaml:"name"`
	File string `yaml:"file"`
}

func (m *LLMModel) UnmarshalYAML(value *yaml.Node) error {
	var str string
	if err := value.Decode(&str); err == nil {
		m.ID = str
		return nil
	}
	var obj struct {
		ID     string    `yaml:"id"`
		Name   string    `yaml:"name,omitempty"`
		Params LLMParams `yaml:"params,omitempty"`
	}
	if err := value.Decode(&obj); err != nil {
		return err
	}
	m.ID = obj.ID
	m.Name = obj.Name
	m.Params = obj.Params
	return nil
}

func buildModelInfos(models []LLMModel, globalParams LLMParams, providerName string) []handler.ModelInfo {
	infos := make([]handler.ModelInfo, len(models))
	for i, m := range models {
		p := handler.LLMParams{
			Temperature: globalParams.Temperature,
			MaxTokens:   globalParams.MaxTokens,
			TopP:        globalParams.TopP,
			TopK:        globalParams.TopK,
		}
		if m.Params.Temperature != nil {
			p.Temperature = m.Params.Temperature
		}
		if m.Params.MaxTokens != 0 {
			p.MaxTokens = m.Params.MaxTokens
		}
		if m.Params.TopP != nil {
			p.TopP = m.Params.TopP
		}
		if m.Params.TopK != 0 {
			p.TopK = m.Params.TopK
		}
		infos[i] = handler.ModelInfo{ID: m.ID, Name: m.Name, Provider: providerName, Params: p, IsManual: true}
	}
	return infos
}

type Config struct {
	Data struct {
		Dir string `yaml:"dir"`
	} `yaml:"data"`
	Server struct {
		Address string `yaml:"address"`
	} `yaml:"server"`
	LLM struct {
		SelectionMethod string              `yaml:"selection_method"` // global default for providers
		AutoDiscover    AutoDiscoverConfig  `yaml:"auto_discover"`
		Providers       []LLMProviderConfig `yaml:"providers"`
		Trace           struct {
			TTL     Duration `yaml:"ttl"`
			Enabled *bool    `yaml:"enabled"`
		} `yaml:"trace"`
	} `yaml:"llm"`
	Log struct {
		Level string `yaml:"level"`
	} `yaml:"log"`
	MCP struct {
		HealthMaxFailures       int               `yaml:"health_max_failures"`
		HealthInterval          time.Duration     `yaml:"health_interval"`
		ReconnectInterval       Duration          `yaml:"reconnect_interval"`
		Timeout                 Duration          `yaml:"timeout"`
		ToolRediscoveryInterval Duration          `yaml:"tool_rediscovery_interval"`
		Servers                 []MCPServerConfig `yaml:"servers"`
	} `yaml:"mcp"`
	Tools struct {
		SystemPrompts []SystemPromptConfig `yaml:"system_prompts"`
	} `yaml:"tools"`
	UI struct {
		AppName           string   `yaml:"app_name"`
		AppIcon           string   `yaml:"app_icon"`
		WelcomeTitle      string   `yaml:"welcome_title"`
		AIDisclaimer      string   `yaml:"ai_disclaimer"`
		PromptSuggestions []string `yaml:"prompt_suggestions"`
	} `yaml:"ui"`
}

func loadSystemPrompts(cfg *Config, logger *zap.Logger) (map[string]string, []handler.SystemPromptInfo, string) {
	prompts := make(map[string]string)
	infos := make([]handler.SystemPromptInfo, 0, len(cfg.Tools.SystemPrompts))
	firstPrompt := ""

	if len(cfg.Tools.SystemPrompts) == 0 {
		logger.Fatal("at least one system prompt is required under tools.system_prompts")
	}

	loadPrompt := func(name, file string) {
		name = strings.TrimSpace(name)
		file = strings.TrimSpace(file)
		if name == "" {
			logger.Fatal("system prompt name is required")
		}
		if file == "" {
			logger.Fatal("system prompt file is required", zap.String("name", name))
		}
		if _, exists := prompts[name]; exists {
			logger.Fatal("duplicate system prompt name", zap.String("name", name))
		}
		data, err := os.ReadFile(file)
		if err != nil {
			logger.Fatal("failed to read system prompt file", zap.String("path", file), zap.Error(err))
		}
		if firstPrompt == "" {
			firstPrompt = name
		}
		prompts[name] = string(data)
		infos = append(infos, handler.SystemPromptInfo{Name: name})
		logger.Info("system prompt loaded", zap.String("name", name), zap.String("path", file))
	}

	for _, prompt := range cfg.Tools.SystemPrompts {
		loadPrompt(prompt.Name, prompt.File)
	}

	return prompts, infos, firstPrompt
}

type MCPServerConfig struct {
	Name                    string            `yaml:"name"`
	URL                     string            `yaml:"url"`
	Auth                    map[string]string `yaml:"auth"`
	Headers                 map[string]string `yaml:"headers"`
	Disabled                bool              `yaml:"disabled"`
	ReconnectInterval       Duration          `yaml:"reconnect_interval"`
	HealthMaxFails          int               `yaml:"health_max_failures"`
	HealthInterval          Duration          `yaml:"health_interval"`
	ToolRediscoveryInterval Duration          `yaml:"tool_rediscovery_interval"`
	Timeout                 Duration          `yaml:"timeout"`
	Insecure                bool              `yaml:"insecure"`
}

func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}

	if cfg.Server.Address == "" {
		cfg.Server.Address = "localhost:8080"
	}
	// Apply per-provider defaults.
	globalSelectionMethod := cfg.LLM.SelectionMethod
	if globalSelectionMethod == "" {
		globalSelectionMethod = "round_robin"
	}
	for i := range cfg.LLM.Providers {
		p := &cfg.LLM.Providers[i]
		if p.BaseURL == "" {
			p.BaseURL = "https://openrouter.ai/api/v1"
		}
		if p.SelectionMethod == "" {
			p.SelectionMethod = globalSelectionMethod
		}
		// Inherit global auto_discover settings when not explicitly set on the provider.
		if p.AutoDiscover.Enabled == nil && cfg.LLM.AutoDiscover.Enabled != nil {
			p.AutoDiscover.Enabled = cfg.LLM.AutoDiscover.Enabled
		}
		if p.AutoDiscover.RefreshInterval == 0 && cfg.LLM.AutoDiscover.RefreshInterval != 0 {
			p.AutoDiscover.RefreshInterval = cfg.LLM.AutoDiscover.RefreshInterval
		}
		autoDiscoverOn := p.AutoDiscover.Enabled != nil && *p.AutoDiscover.Enabled
		if autoDiscoverOn {
			if p.AutoDiscover.RefreshInterval == 0 {
				p.AutoDiscover.RefreshInterval = 60 * time.Minute
			}
			if p.AutoDiscover.RefreshInterval < time.Minute {
				p.AutoDiscover.RefreshInterval = time.Minute
			}
		}
	}
	if cfg.Log.Level == "" {
		cfg.Log.Level = "info"
	}

	// Resolve data root directory (default: ./data).
	if cfg.Data.Dir == "" {
		cfg.Data.Dir = "./data"
	}

	// MCP reconnect interval: default 30s.
	if cfg.MCP.ReconnectInterval == 0 {
		cfg.MCP.ReconnectInterval = Duration(30 * time.Second)
	}
	// MCP tool call timeout: default 30s.
	if cfg.MCP.Timeout == 0 {
		cfg.MCP.Timeout = Duration(30 * time.Second)
	}

	// Trace TTL: default 7 days, minimum 1 hour.
	if cfg.LLM.Trace.TTL == 0 {
		cfg.LLM.Trace.TTL = Duration(7 * 24 * time.Hour)
	}
	if cfg.LLM.Trace.TTL < Duration(time.Hour) {
		cfg.LLM.Trace.TTL = Duration(time.Hour)
	}
	// Trace enabled: default true if not set.
	if cfg.LLM.Trace.Enabled == nil {
		b := true
		cfg.LLM.Trace.Enabled = &b
	}

	return &cfg, nil
}

func buildLogger(level string) *zap.Logger {
	lvl := zapcore.InfoLevel
	if err := lvl.UnmarshalText([]byte(level)); err != nil {
		lvl = zapcore.InfoLevel
	}

	cfg := zap.NewDevelopmentConfig()
	cfg.Level = zap.NewAtomicLevelAt(lvl)
	cfg.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
	cfg.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder

	logger, err := cfg.Build()
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to build logger: %v\n", err)
		os.Exit(1)
	}
	return logger
}

func buildRegistry(logger *zap.Logger) *tools.Registry {
	registry := tools.NewRegistry()
	if err := registry.Register(tools.DateTimeTool{}); err != nil {
		logger.Fatal("failed to register built-in tool", zap.Error(err))
	}
	logger.Info("built-in tools registered", zap.Strings("tools", []string{"get_current_datetime"}))
	return registry
}

// traceCleanupInterval returns how often the trace purge job should run.
// If the TTL is ≤ 12 hours the job runs every TTL; otherwise it runs every 12 hours.
func traceCleanupInterval(ttl time.Duration) time.Duration {
	const maxInterval = 12 * time.Hour
	if ttl <= maxInterval {
		return ttl
	}
	return maxInterval
}

// runTraceCleanup is a long-running goroutine that periodically purges stale
// LLM trace data from the conversation store.
func runTraceCleanup(ctx context.Context, st *storage.YAMLStore, ttl time.Duration, logger *zap.Logger) {
	interval := traceCleanupInterval(ttl)
	logger.Info("trace cleanup job started", zap.Duration("ttl", ttl), zap.Duration("interval", interval))
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			cutoff := time.Now().Add(-ttl)
			if err := st.PurgeTraces(cutoff); err != nil {
				logger.Error("trace cleanup failed", zap.Error(err))
			} else {
				logger.Info("trace cleanup done", zap.Duration("ttl", ttl), zap.Time("cutoff", cutoff))
			}
		}
	}
}

func main() {
	configPath := flag.String("config", "./config.yaml", "Path to config file")
	flag.Parse()

	cfg, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load config: %v\n", err)
		os.Exit(1)
	}

	logger := buildLogger(cfg.Log.Level)
	defer func() { _ = logger.Sync() }()

	logger.Info("application details", zap.String("version", version.Get().String()))

	dataDir := cfg.Data.Dir
	storageDir := dataDir + "/conversations"
	uploadDir := dataDir + "/uploads"
	schedulerDir := dataDir
	logger.Info("data root", zap.String("dir", dataDir), zap.String("conversations", storageDir), zap.String("uploads", uploadDir))

	if len(cfg.LLM.Providers) == 0 {
		logger.Fatal("at least one LLM provider is required under llm.providers")
	}
	seenProviders := make(map[string]bool, len(cfg.LLM.Providers))
	for _, p := range cfg.LLM.Providers {
		if p.Name == "" {
			logger.Fatal("each LLM provider must have a name")
		}
		if seenProviders[p.Name] {
			logger.Fatal("duplicate LLM provider name", zap.String("provider", p.Name))
		}
		seenProviders[p.Name] = true
		if strings.TrimSpace(p.APIKey) == "" {
			logger.Fatal("LLM provider api_key is required", zap.String("provider", p.Name))
		}
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	registry := buildRegistry(logger)

	mcpManager := mcp.NewManager(registry, logger, cfg.MCP.HealthMaxFailures, cfg.MCP.HealthInterval, cfg.MCP.ReconnectInterval.AsDuration(), cfg.MCP.ToolRediscoveryInterval.AsDuration())

	for _, sc := range cfg.MCP.Servers {
		if sc.Disabled {
			logger.Info("MCP server skipped (disabled)", zap.String("name", sc.Name))
			continue
		}
		ri := sc.ReconnectInterval.AsDuration()
		if ri <= 0 {
			ri = cfg.MCP.ReconnectInterval.AsDuration()
		}
		to := sc.Timeout.AsDuration()
		if to <= 0 {
			to = cfg.MCP.Timeout.AsDuration()
		}
		scfg := mcp.ServerConfig{
			ReconnectInterval:       ri,
			HealthMaxFails:          sc.HealthMaxFails,
			HealthInterval:          sc.HealthInterval.AsDuration(),
			ToolRediscoveryInterval: sc.ToolRediscoveryInterval.AsDuration(),
			Timeout:                 to,
			Insecure:                sc.Insecure,
		}
		_, err := mcpManager.Register(ctx, sc.URL, sc.Auth, sc.Headers, scfg)
		if err != nil {
			logger.Warn("failed to connect MCP server, will retry in background",
				zap.String("name", sc.Name), zap.String("url", sc.URL),
				zap.Duration("reconnect_interval", ri), zap.Error(err))
			mcpManager.QueueRetry(sc.URL, sc.Auth, sc.Headers, scfg)
		}
	}

	go mcpManager.StartHealthMonitor(ctx) // StartHealthMonitor spawns its own goroutine internally

	systemPrompts, systemPromptInfos, defaultSystemPrompt := loadSystemPrompts(cfg, logger)

	st, err := storage.NewYAMLStore(storageDir)
	if err != nil {
		logger.Fatal("failed to create storage", zap.String("dir", storageDir), zap.Error(err))
	}
	store := chat.NewSessionStore(st)

	go runTraceCleanup(ctx, st, cfg.LLM.Trace.TTL.AsDuration(), logger)
	uiConfig := handler.UIConfig{
		AppName:           cfg.UI.AppName,
		AppIcon:           cfg.UI.AppIcon,
		WelcomeTitle:      cfg.UI.WelcomeTitle,
		AIDisclaimer:      cfg.UI.AIDisclaimer,
		PromptSuggestions: cfg.UI.PromptSuggestions,
		SystemPrompts:     systemPromptInfos,
	}
	if uiConfig.AppName == "" {
		uiConfig.AppName = "promptd"
	}
	if uiConfig.WelcomeTitle == "" {
		uiConfig.WelcomeTitle = "How can I help you today?"
	}
	if uiConfig.AIDisclaimer == "" {
		uiConfig.AIDisclaimer = "AI can make mistakes. Verify important info."
	}
	if len(uiConfig.PromptSuggestions) == 0 {
		uiConfig.PromptSuggestions = []string{
			"Explain how this works",
			"Help me write code",
			"Summarize the key points",
			"What are best practices?",
		}
	}

	traceEnabled := cfg.LLM.Trace.Enabled != nil && *cfg.LLM.Trace.Enabled

	providerEntries := make([]*handler.ProviderEntry, 0, len(cfg.LLM.Providers))
	for _, p := range cfg.LLM.Providers {
		globalParams := handler.LLMParams{
			Temperature: p.Params.Temperature,
			MaxTokens:   p.Params.MaxTokens,
			TopP:        p.Params.TopP,
			TopK:        p.Params.TopK,
		}
		staticModels := buildModelInfos(p.Models, p.Params, p.Name)
		client := handler.NewLLMClient(p.APIKey, p.BaseURL, logger)
		sel := handler.NewModelSelector(staticModels, p.SelectionMethod)
		autoDiscoverOn := p.AutoDiscover.Enabled != nil && *p.AutoDiscover.Enabled
		if autoDiscoverOn {
			sel.SetRefreshInterval(p.AutoDiscover.RefreshInterval)
		}
		providerEntries = append(providerEntries, &handler.ProviderEntry{
			Name:          p.Name,
			Client:        client,
			ModelSelector: sel,
			GlobalParams:  globalParams,
			StaticModels:  staticModels,
			AutoDiscover:  autoDiscoverOn,
		})
		logger.Info("provider registered",
			zap.String("name", p.Name),
			zap.String("base_url", p.BaseURL),
			zap.Int("models", len(staticModels)),
			zap.Bool("auto_discover", autoDiscoverOn))
	}
	providerRegistry := handler.NewProviderRegistry(providerEntries, logger)
	h := handler.New(providerRegistry, systemPrompts, defaultSystemPrompt, registry, store, st, logger, ui.FS(), uiConfig, uploadDir, traceEnabled)

	for _, p := range cfg.LLM.Providers {
		if p.AutoDiscover.Enabled != nil && *p.AutoDiscover.Enabled {
			if err := h.DiscoverAndUpdateModels(ctx, p.Name); err != nil {
				logger.Warn("initial auto discover failed", zap.String("provider", p.Name), zap.Error(err))
			} else {
				logger.Info("initial auto discover complete", zap.String("provider", p.Name))
			}
			go h.StartAutoDiscover(ctx, p.Name, p.AutoDiscover.RefreshInterval)
		}
	}
	mcpHandler := handler.NewMCPToolsHandler(mcpManager, logger)

	// Scheduler
	schedStore, err := scheduler.NewStore(schedulerDir)
	if err != nil {
		logger.Fatal("failed to create scheduler store", zap.Error(err))
	}
	schedRunner := scheduler.NewRunner(providerRegistry, registry, logger, traceEnabled)
	sched := scheduler.New(schedStore, schedRunner, systemPrompts, logger)
	if err := sched.Start(ctx); err != nil {
		logger.Fatal("failed to start scheduler", zap.Error(err))
	}
	schedHandler := handler.NewScheduleHandler(sched, logger)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", h.ServeUI)
	mux.HandleFunc("POST /api/chat", h.Chat)
	mux.HandleFunc("POST /api/reset", h.Reset)
	mux.HandleFunc("GET /api/mcp", mcpHandler.List)
	mux.HandleFunc("GET /api/ui-config", h.UIConfig)
	mux.HandleFunc("GET /api/models", h.ListModels)
	mux.HandleFunc("GET /api/tools", h.ListTools)
	mux.HandleFunc("POST /api/upload", h.Upload)
	mux.HandleFunc("GET /api/files/", h.ServeFile)
	mux.HandleFunc("DELETE /api/files/", h.DeleteFile)
	mux.HandleFunc("GET /api/conversations", h.ListConversations)
	mux.HandleFunc("GET /api/conversations/{id}", h.GetConversation)
	mux.HandleFunc("DELETE /api/conversations/{id}", h.DeleteConversation)
	mux.HandleFunc("PATCH /api/conversations/{id}/title", h.RenameConversation)
	mux.HandleFunc("PATCH /api/conversations/{id}/pin", h.TogglePinConversation)
	mux.HandleFunc("DELETE /api/conversations/{id}/messages/{msgId}", h.DeleteMessage)
	mux.HandleFunc("DELETE /api/conversations/{id}/messages/{msgId}/after", h.DeleteMessagesFrom)
	mux.HandleFunc("GET /api/schedules", schedHandler.List)
	mux.HandleFunc("POST /api/schedules", schedHandler.Create)
	mux.HandleFunc("GET /api/schedules/{id}", schedHandler.Get)
	mux.HandleFunc("PUT /api/schedules/{id}", schedHandler.Update)
	mux.HandleFunc("DELETE /api/schedules/{id}", schedHandler.Delete)
	mux.HandleFunc("POST /api/schedules/{id}/trigger", schedHandler.Trigger)
	mux.HandleFunc("GET /api/schedules/{id}/executions", schedHandler.ListExecutions)
	mux.HandleFunc("DELETE /api/schedules/{id}/executions/{execId}", schedHandler.DeleteExecution)

	srv := &http.Server{
		Addr:         cfg.Server.Address,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 120 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		logger.Info("server started",
			zap.String("address", cfg.Server.Address),
			zap.Int("providers", len(cfg.LLM.Providers)),
			zap.Int("models", len(providerRegistry.AllModels())))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("server error", zap.Error(err))
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down...")

	sched.Stop()
	mcpManager.StopHealthMonitor()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown error", zap.Error(err))
	}
	logger.Info("server stopped")
}
