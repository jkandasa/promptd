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

	"chatbot/internal/chat"
	"chatbot/internal/handler"
	"chatbot/internal/mcp"
	"chatbot/internal/storage"
	"chatbot/internal/tools"
	"chatbot/internal/ui"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
	"gopkg.in/yaml.v3"
)

type LLMModel struct {
	ID   string `yaml:"id"`
	Name string `yaml:"name,omitempty"`
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
		ID   string `yaml:"id"`
		Name string `yaml:"name,omitempty"`
	}
	if err := value.Decode(&obj); err != nil {
		return err
	}
	m.ID = obj.ID
	m.Name = obj.Name
	return nil
}

func getModelIDs(models []LLMModel) []string {
	ids := make([]string, len(models))
	for i, m := range models {
		ids[i] = m.ID
	}
	return ids
}

type Config struct {
	Data struct {
		Dir string `yaml:"dir"`
	} `yaml:"data"`
	Server struct {
		Port string `yaml:"port"`
	} `yaml:"server"`
	LLM struct {
		APIKey          string     `yaml:"api_key"`
		BaseURL         string     `yaml:"base_url"`
		SelectionMethod string     `yaml:"selection_method"`
		Models          []LLMModel `yaml:"models"`
	} `yaml:"llm"`
	Log struct {
		Level string `yaml:"level"`
	} `yaml:"log"`
	MCP struct {
		HealthMaxFailures int               `yaml:"health_max_failures"`
		HealthInterval    time.Duration     `yaml:"health_interval"`
		Servers           []MCPServerConfig `yaml:"servers"`
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
	Trace struct {
		// TTL controls how long raw LLM trace data is retained on assistant messages.
		// Default: 168h (7 days). Minimum: 1h.
		TTL time.Duration `yaml:"ttl"`
	} `yaml:"trace"`
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
	Name     string            `yaml:"name"`
	URL      string            `yaml:"url"`
	Auth     map[string]string `yaml:"auth"`
	Headers  map[string]string `yaml:"headers"`
	Disabled bool              `yaml:"disabled"`
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

	if cfg.Server.Port == "" {
		cfg.Server.Port = "8080"
	}
	if cfg.LLM.BaseURL == "" {
		cfg.LLM.BaseURL = "https://openrouter.ai/api/v1"
	}
	if cfg.LLM.SelectionMethod == "" {
		cfg.LLM.SelectionMethod = "auto"
	}
	if len(cfg.LLM.Models) == 0 {
		cfg.LLM.Models = []LLMModel{{ID: "anthropic/claude-sonnet-4-6"}}
	}
	if cfg.Log.Level == "" {
		cfg.Log.Level = "info"
	}

	// Resolve data root directory (default: ./data).
	if cfg.Data.Dir == "" {
		cfg.Data.Dir = "./data"
	}

	// Trace TTL: default 7 days, minimum 1 hour.
	if cfg.Trace.TTL == 0 {
		cfg.Trace.TTL = 7 * 24 * time.Hour
	}
	if cfg.Trace.TTL < time.Hour {
		cfg.Trace.TTL = time.Hour
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

	dataDir := cfg.Data.Dir
	storageDir := dataDir + "/conversations"
	uploadDir := dataDir + "/uploads"
	logger.Info("data root", zap.String("dir", dataDir), zap.String("conversations", storageDir), zap.String("uploads", uploadDir))

	if strings.TrimSpace(cfg.LLM.APIKey) == "" {
		logger.Fatal("LLM API key is required in config")
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	registry := buildRegistry(logger)

	mcpManager := mcp.NewManager(registry, logger, cfg.MCP.HealthMaxFailures, cfg.MCP.HealthInterval)

	for _, sc := range cfg.MCP.Servers {
		if sc.Disabled {
			logger.Info("MCP server skipped (disabled)", zap.String("name", sc.Name), zap.String("url", sc.URL))
			continue
		}
		_, err := mcpManager.Register(ctx, sc.URL, sc.Auth, sc.Headers)
		if err != nil {
			logger.Warn("failed to register MCP server", zap.String("name", sc.Name), zap.String("url", sc.URL), zap.Error(err))
		} else {
			logger.Info("MCP server registered", zap.String("name", sc.Name), zap.String("url", sc.URL))
		}
	}

	go mcpManager.StartHealthMonitor(ctx) // StartHealthMonitor spawns its own goroutine internally

	systemPrompts, systemPromptInfos, defaultSystemPrompt := loadSystemPrompts(cfg, logger)

	st, err := storage.NewYAMLStore(storageDir)
	if err != nil {
		logger.Fatal("failed to create storage", zap.String("dir", storageDir), zap.Error(err))
	}
	store := chat.NewSessionStore(st)

	go runTraceCleanup(ctx, st, cfg.Trace.TTL, logger)
	uiConfig := handler.UIConfig{
		AppName:           cfg.UI.AppName,
		AppIcon:           cfg.UI.AppIcon,
		WelcomeTitle:      cfg.UI.WelcomeTitle,
		AIDisclaimer:      cfg.UI.AIDisclaimer,
		PromptSuggestions: cfg.UI.PromptSuggestions,
		SystemPrompts:     systemPromptInfos,
	}
	if uiConfig.AppName == "" {
		uiConfig.AppName = "Chatbot"
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

	modelSelector := handler.NewModelSelector(getModelIDs(cfg.LLM.Models), cfg.LLM.SelectionMethod)
	h := handler.New(cfg.LLM.APIKey, cfg.LLM.BaseURL, systemPrompts, defaultSystemPrompt, modelSelector, registry, store, st, logger, ui.FS(), uiConfig, uploadDir)
	mcpHandler := handler.NewMCPToolsHandler(mcpManager, logger)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", h.ServeUI)
	mux.HandleFunc("POST /chat", h.Chat)
	mux.HandleFunc("POST /reset", h.Reset)
	mux.HandleFunc("GET /mcp", mcpHandler.List)
	mux.HandleFunc("GET /ui-config", h.UIConfig)
	mux.HandleFunc("GET /models", h.ListModels)
	mux.HandleFunc("GET /tools", h.ListTools)
	mux.HandleFunc("POST /upload", h.Upload)
	mux.HandleFunc("GET /files/", h.ServeFile)
	mux.HandleFunc("DELETE /files/", h.DeleteFile)
	mux.HandleFunc("GET /conversations", h.ListConversations)
	mux.HandleFunc("GET /conversations/{id}", h.GetConversation)
	mux.HandleFunc("DELETE /conversations/{id}", h.DeleteConversation)
	mux.HandleFunc("PATCH /conversations/{id}/title", h.RenameConversation)
	mux.HandleFunc("PATCH /conversations/{id}/pin", h.TogglePinConversation)
	mux.HandleFunc("DELETE /conversations/{id}/messages/{msgId}", h.DeleteMessage)
	mux.HandleFunc("DELETE /conversations/{id}/messages/{msgId}/after", h.DeleteMessagesFrom)

	addr := ":" + cfg.Server.Port
	srv := &http.Server{
		Addr:         addr,
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 120 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		logger.Info("server started", zap.String("addr", "http://localhost"+addr), zap.Strings("models", getModelIDs(cfg.LLM.Models)), zap.String("selection_method", cfg.LLM.SelectionMethod), zap.String("baseUrl", cfg.LLM.BaseURL))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("server error", zap.Error(err))
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down...")

	mcpManager.StopHealthMonitor()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown error", zap.Error(err))
	}
	logger.Info("server stopped")
}
