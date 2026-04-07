package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"chatbot/internal/chat"
	"chatbot/internal/handler"
	"chatbot/internal/mcp"
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
	Server struct {
		Port string `yaml:"port"`
	} `yaml:"server"`
	Upload struct {
		Dir string `yaml:"dir"`
	} `yaml:"upload"`
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
		SystemPromptFile string `yaml:"system_prompt_file"`
	} `yaml:"tools"`
	UI struct {
		WelcomeTitle      string   `yaml:"welcome_title"`
		AIDisclaimer      string   `yaml:"ai_disclaimer"`
		PromptSuggestions []string `yaml:"prompt_suggestions"`
	} `yaml:"ui"`
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

	logger, _ := cfg.Build()
	return logger
}

func buildRegistry(logger *zap.Logger) *tools.Registry {
	registry := tools.NewRegistry()
	registry.Register(tools.DateTimeTool{})
	logger.Info("built-in tools registered", zap.Strings("tools", []string{"get_current_datetime"}))
	return registry
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
	defer logger.Sync()

	if cfg.LLM.APIKey == "" {
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

	go mcpManager.StartHealthMonitor(ctx)

	var systemPrompt string
	if cfg.Tools.SystemPromptFile != "" {
		data, err := os.ReadFile(cfg.Tools.SystemPromptFile)
		if err != nil {
			logger.Fatal("failed to read system prompt file", zap.String("path", cfg.Tools.SystemPromptFile), zap.Error(err))
		}
		systemPrompt = string(data)
		logger.Info("system prompt loaded", zap.String("path", cfg.Tools.SystemPromptFile))
	}

	store := chat.NewSessionStore()
	uiConfig := handler.UIConfig{
		WelcomeTitle:      cfg.UI.WelcomeTitle,
		AIDisclaimer:      cfg.UI.AIDisclaimer,
		PromptSuggestions: cfg.UI.PromptSuggestions,
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
	uploadDir := cfg.Upload.Dir
	if uploadDir == "" {
		uploadDir = "./uploads"
	}

	modelSelector := handler.NewModelSelector(getModelIDs(cfg.LLM.Models), cfg.LLM.SelectionMethod)
	h := handler.New(cfg.LLM.APIKey, cfg.LLM.BaseURL, systemPrompt, modelSelector, registry, store, logger, ui.FS(), uiConfig, uploadDir)
	mcpHandler := handler.NewMCPToolsHandler(mcpManager, logger)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", h.ServeUI)
	mux.HandleFunc("POST /chat", h.Chat)
	mux.HandleFunc("POST /reset", h.Reset)
	mux.HandleFunc("GET /mcp", mcpHandler.List)
	mux.HandleFunc("GET /ui-config", h.UIConfig)
	mux.HandleFunc("GET /models", h.ListModels)
	mux.HandleFunc("POST /upload", h.Upload)
	mux.HandleFunc("GET /files/", h.ServeFile)
	mux.HandleFunc("DELETE /files/", h.DeleteFile)

	addr := ":" + cfg.Server.Port
	srv := &http.Server{Addr: addr, Handler: mux}

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
