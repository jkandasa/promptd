package app

import (
	"context"
	"fmt"
	"os"
	"time"

	appconfig "promptd/internal/config"
	"promptd/internal/handler"
	"promptd/internal/storage"
	"promptd/internal/tools"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

func BuildModelInfos(models []appconfig.LLMModel, globalParams appconfig.LLMParams, providerName string) []handler.ModelInfo {
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

func BuildLogger(level string) *zap.Logger {
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

func BuildRegistry(logger *zap.Logger) *tools.Registry {
	registry := tools.NewRegistry()
	if err := registry.Register(tools.DateTimeTool{}); err != nil {
		logger.Fatal("failed to register built-in tool", zap.Error(err))
	}
	logger.Info("built-in tools registered", zap.Strings("tools", []string{"get_current_datetime"}))
	return registry
}

func StartTraceCleanup(ctx context.Context, st *storage.YAMLStore, ttl time.Duration, logger *zap.Logger) {
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

func traceCleanupInterval(ttl time.Duration) time.Duration {
	const maxInterval = 12 * time.Hour
	if ttl <= maxInterval {
		return ttl
	}
	return maxInterval
}
