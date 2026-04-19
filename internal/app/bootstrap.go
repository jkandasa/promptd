package app

import (
	"context"
	"net/http"
	"strings"

	"promptd/internal/auth"
	appconfig "promptd/internal/config"
	"promptd/internal/handler"
	"promptd/internal/mcp"

	"go.uber.org/zap"
)

func ValidateProviders(cfg *appconfig.Config, logger *zap.Logger) {
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
}

func RegisterMCPServers(ctx context.Context, manager *mcp.Manager, cfg *appconfig.Config, logger *zap.Logger) {
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
		_, err := manager.Register(ctx, sc.URL, sc.Auth, sc.Headers, scfg)
		if err != nil {
			logger.Warn("failed to connect MCP server, will retry in background",
				zap.String("name", sc.Name), zap.String("url", sc.URL),
				zap.Duration("reconnect_interval", ri), zap.Error(err))
			manager.QueueRetry(sc.URL, sc.Auth, sc.Headers, scfg)
		}
	}
}

func BuildUIConfig(cfg *appconfig.Config, systemPromptInfos []handler.SystemPromptInfo) handler.UIConfig {
	uiConfig := handler.UIConfig{
		AppName:           cfg.UI.AppName,
		AppIcon:           cfg.UI.AppIcon,
		WelcomeTitle:      cfg.UI.WelcomeTitle,
		AIDisclaimer:      cfg.UI.AIDisclaimer,
		PromptSuggestions: cfg.UI.PromptSuggestions,
		SystemPrompts:     systemPromptInfos,
		CompactConversation: handler.CompactConversationUIConfig{
			Enabled:       cfg.LLM.CompactConversation.Enabled,
			DefaultPrompt: cfg.LLM.CompactConversation.DefaultPrompt,
			AfterMessages: cfg.LLM.CompactConversation.AfterMessages,
			AfterTokens:   cfg.LLM.CompactConversation.AfterTokens,
		},
	}
	if uiConfig.AppName == "" {
		uiConfig.AppName = "Promptd"
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
	if uiConfig.CompactConversation.DefaultPrompt == "" {
		uiConfig.CompactConversation.DefaultPrompt = "Summarize the conversation so far. Preserve user goals, decisions, constraints, file references, and unresolved issues. Omit repetition and casual filler."
	}
	if uiConfig.CompactConversation.AfterMessages <= 0 {
		uiConfig.CompactConversation.AfterMessages = 20
	}
	return uiConfig
}

func BuildProviderRegistry(cfg *appconfig.Config, logger *zap.Logger) *handler.ProviderRegistry {
	providerEntries := make([]*handler.ProviderEntry, 0, len(cfg.LLM.Providers))
	for _, p := range cfg.LLM.Providers {
		globalParams := handler.LLMParams{
			Temperature: p.Params.Temperature,
			MaxTokens:   p.Params.MaxTokens,
			TopP:        p.Params.TopP,
			TopK:        p.Params.TopK,
		}
		staticModels := BuildModelInfos(p.Models, p.Params, p.Name)
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
	return handler.NewProviderRegistry(providerEntries, logger)
}

func StartAutoDiscover(ctx context.Context, h *handler.Handler, cfg *appconfig.Config, logger *zap.Logger) {
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
}

func RegisterRoutes(mux *http.ServeMux, authService *auth.Service, h *handler.Handler, mcpHandler *handler.MCPToolsHandler, schedHandler *handler.ScheduleHandler) {
	requireAuth := authService.Require
	mux.HandleFunc("GET /", h.ServeUI)
	mux.HandleFunc("POST /api/auth/login", h.Login)
	mux.HandleFunc("POST /api/auth/logout", h.Logout)
	mux.HandleFunc("GET /api/auth/me", h.Me)
	mux.Handle("POST /api/chat", requireAuth(http.HandlerFunc(h.Chat)))
	mux.Handle("POST /api/reset", requireAuth(http.HandlerFunc(h.Reset)))
	mux.Handle("GET /api/mcp", requireAuth(http.HandlerFunc(mcpHandler.List)))
	mux.Handle("GET /api/ui-config", requireAuth(http.HandlerFunc(h.UIConfig)))
	mux.Handle("GET /api/models", requireAuth(http.HandlerFunc(h.ListModels)))
	mux.Handle("GET /api/tools", requireAuth(http.HandlerFunc(h.ListTools)))
	mux.Handle("POST /api/upload", requireAuth(http.HandlerFunc(h.Upload)))
	mux.Handle("GET /api/files/", requireAuth(http.HandlerFunc(h.ServeFile)))
	mux.Handle("DELETE /api/files/", requireAuth(http.HandlerFunc(h.DeleteFile)))
	mux.Handle("GET /api/conversations", requireAuth(http.HandlerFunc(h.ListConversations)))
	mux.Handle("GET /api/conversations/{id}", requireAuth(http.HandlerFunc(h.GetConversation)))
	mux.Handle("DELETE /api/conversations/{id}", requireAuth(http.HandlerFunc(h.DeleteConversation)))
	mux.Handle("PATCH /api/conversations/{id}/title", requireAuth(http.HandlerFunc(h.RenameConversation)))
	mux.Handle("PATCH /api/conversations/{id}/pin", requireAuth(http.HandlerFunc(h.TogglePinConversation)))
	mux.Handle("POST /api/conversations/{id}/compact", requireAuth(http.HandlerFunc(h.CompactConversation)))
	mux.Handle("DELETE /api/conversations/{id}/messages/{msgId}", requireAuth(http.HandlerFunc(h.DeleteMessage)))
	mux.Handle("DELETE /api/conversations/{id}/messages/{msgId}/after", requireAuth(http.HandlerFunc(h.DeleteMessagesFrom)))
	mux.Handle("GET /api/schedules", requireAuth(http.HandlerFunc(schedHandler.List)))
	mux.Handle("POST /api/schedules", requireAuth(http.HandlerFunc(schedHandler.Create)))
	mux.Handle("GET /api/schedules/{id}", requireAuth(http.HandlerFunc(schedHandler.Get)))
	mux.Handle("PUT /api/schedules/{id}", requireAuth(http.HandlerFunc(schedHandler.Update)))
	mux.Handle("DELETE /api/schedules/{id}", requireAuth(http.HandlerFunc(schedHandler.Delete)))
	mux.Handle("POST /api/schedules/{id}/trigger", requireAuth(http.HandlerFunc(schedHandler.Trigger)))
	mux.Handle("GET /api/schedules/{id}/executions", requireAuth(http.HandlerFunc(schedHandler.ListExecutions)))
	mux.Handle("DELETE /api/schedules/{id}/executions/{execId}", requireAuth(http.HandlerFunc(schedHandler.DeleteExecution)))
}
