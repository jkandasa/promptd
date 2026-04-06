package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"chatbot/internal/chat"
	"chatbot/internal/handler"
	"chatbot/internal/tools"
	"chatbot/internal/ui"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

func buildLogger() *zap.Logger {
	level := zapcore.InfoLevel
	if lvl := os.Getenv("LOG_LEVEL"); lvl != "" {
		if err := level.UnmarshalText([]byte(lvl)); err != nil {
			level = zapcore.InfoLevel
		}
	}

	cfg := zap.NewDevelopmentConfig()
	cfg.Level = zap.NewAtomicLevelAt(level)
	cfg.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder
	cfg.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder

	logger, _ := cfg.Build()
	return logger
}

func loadSystemPrompt(logger *zap.Logger) string {
	path := os.Getenv("SYSTEM_PROMPT_FILE")
	if path == "" {
		logger.Info("no system prompt configured")
		return ""
	}
	data, err := os.ReadFile(path)
	if err != nil {
		logger.Fatal("failed to read system prompt file", zap.String("path", path), zap.Error(err))
	}
	logger.Info("system prompt loaded", zap.String("path", path))
	return string(data)
}

func buildRegistry(monitor *tools.Monitor, logger *zap.Logger) *tools.Registry {
	registry := tools.NewRegistry()

	// Built-in tools — always available, not health-checked.
	registry.Register(tools.DateTimeTool{})
	registry.Register(tools.CalculatorTool{})
	logger.Info("built-in tools registered", zap.Strings("tools", []string{"get_current_datetime", "calculate"}))

	// Static remote tools from tools.yaml (also health-checked by the monitor).
	configPath := os.Getenv("TOOLS_CONFIG")
	if configPath == "" {
		configPath = "tools.yaml"
	}
	if err := tools.LoadFromConfig(configPath, registry, monitor, logger); err != nil {
		logger.Fatal("failed to load remote tools", zap.Error(err))
	}

	return registry
}

func main() {
	logger := buildLogger()
	defer logger.Sync()

	apiKey := os.Getenv("LLM_API_KEY")
	if apiKey == "" {
		logger.Fatal("LLM_API_KEY environment variable is required")
	}

	baseURL := os.Getenv("LLM_BASE_URL")
	if baseURL == "" {
		baseURL = "https://openrouter.ai/api/v1"
	}

	model := os.Getenv("MODEL")
	if model == "" {
		model = "anthropic/claude-sonnet-4-6"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	monitor := tools.NewMonitor(nil, logger) // registry set after creation below
	registry := buildRegistry(monitor, logger)
	monitor.SetRegistry(registry)

	go monitor.Run(ctx)

	systemPrompt := loadSystemPrompt(logger)
	store := chat.NewSessionStore()
	h := handler.New(apiKey, baseURL, model, systemPrompt, registry, store, logger, ui.FS())
	th := handler.NewToolsHandler(registry, monitor, logger)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", h.ServeUI)
	mux.HandleFunc("POST /chat", h.Chat)
	mux.HandleFunc("POST /reset", h.Reset)
	mux.HandleFunc("POST /tools/register", th.Register)
	mux.HandleFunc("DELETE /tools/unregister", th.Unregister)
	mux.HandleFunc("GET /tools", th.List)

	addr := ":" + port
	srv := &http.Server{Addr: addr, Handler: mux}

	go func() {
		logger.Info("server started", zap.String("addr", "http://localhost"+addr), zap.String("model", model), zap.String("baseUrl", baseURL))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("server error", zap.Error(err))
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down...")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown error", zap.Error(err))
	}
	logger.Info("server stopped")
}
