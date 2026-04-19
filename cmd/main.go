package main

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	appcore "promptd/internal/app"
	"promptd/internal/auth"
	"promptd/internal/chat"
	appconfig "promptd/internal/config"
	"promptd/internal/handler"
	"promptd/internal/mcp"
	"promptd/internal/scheduler"
	"promptd/internal/storage"
	"promptd/internal/ui"
	"promptd/internal/version"

	"github.com/spf13/cobra"
	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/term"
)

func main() {
	if err := newRootCmd().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func newRootCmd() *cobra.Command {
	var configPath string

	rootCmd := &cobra.Command{
		Use:   "promptd",
		Short: "Promptd server and CLI tools",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runServe(configPath)
		},
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	rootCmd.PersistentFlags().StringVar(&configPath, "config", "./config.yaml", "Path to config file")

	serveCmd := &cobra.Command{
		Use:   "serve",
		Short: "Start the promptd server",
		RunE: func(cmd *cobra.Command, args []string) error {
			return runServe(configPath)
		},
	}

	hashPasswordCmd := &cobra.Command{
		Use:   "hash-password",
		Short: "Generate a bcrypt hash for a password or service token",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			return runHashCommand("Secret")
		},
	}

	versionCmd := &cobra.Command{
		Use:   "version",
		Short: "Show build and runtime version details",
		Args:  cobra.NoArgs,
		RunE: func(cmd *cobra.Command, args []string) error {
			fmt.Print(formatVersionDetails(version.Get()))
			return nil
		},
	}

	rootCmd.AddCommand(serveCmd, hashPasswordCmd, versionCmd)
	return rootCmd
}

func runServe(configPath string) error {
	cfg, err := appconfig.Load(configPath)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	logger := appcore.BuildLogger(cfg.Log.Level)
	defer func() { _ = logger.Sync() }()

	v := version.Get()
	logger.Info("application version",
		zap.String("version", v.Version),
		zap.String("git_commit", emptyVersionValue(v.GitCommit)),
		zap.String("build_date", emptyVersionValue(v.BuildDate)),
		zap.String("go_version", v.GoVersion),
		zap.String("compiler", v.Compiler),
		zap.String("platform", v.Platform),
		zap.String("arch", v.Arch),
	)

	dataDir := cfg.Data.Dir
	schedulerDir := dataDir
	uploadRoot := dataDir
	logger.Info("data root", zap.String("dir", dataDir))

	appcore.ValidateProviders(cfg, logger)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	registry := appcore.BuildRegistry(logger)

	mcpManager := mcp.NewManager(registry, logger, cfg.MCP.HealthMaxFailures, cfg.MCP.HealthInterval, cfg.MCP.ReconnectInterval.AsDuration(), cfg.MCP.ToolRediscoveryInterval.AsDuration())
	appcore.RegisterMCPServers(ctx, mcpManager, cfg, logger)

	go mcpManager.StartHealthMonitor(ctx) // StartHealthMonitor spawns its own goroutine internally

	systemPrompts, systemPromptInfos, defaultSystemPrompt := appconfig.LoadSystemPrompts(cfg, logger)

	st, err := storage.NewYAMLStore(dataDir)
	if err != nil {
		logger.Fatal("failed to create storage", zap.String("dir", dataDir), zap.Error(err))
	}
	store := chat.NewSessionStore(st)
	authService, err := auth.NewService(auth.Config{JWT: cfg.Auth.JWT, Users: cfg.Auth.Users}, cfg.Roles)
	if err != nil {
		logger.Fatal("failed to initialize auth service", zap.Error(err))
	}

	go appcore.StartTraceCleanup(ctx, st, cfg.LLM.Trace.TTL.AsDuration(), logger)
	uiConfig := appcore.BuildUIConfig(cfg, systemPromptInfos)

	traceEnabled := cfg.LLM.Trace.Enabled != nil && *cfg.LLM.Trace.Enabled
	providerRegistry := appcore.BuildProviderRegistry(cfg, logger)
	compactConfig := handler.CompactConversationConfig{
		Enabled:       cfg.LLM.CompactConversation.Enabled,
		Provider:      cfg.LLM.CompactConversation.Provider,
		Model:         cfg.LLM.CompactConversation.Model,
		DefaultPrompt: uiConfig.CompactConversation.DefaultPrompt,
		AfterMessages: uiConfig.CompactConversation.AfterMessages,
		AfterTokens:   uiConfig.CompactConversation.AfterTokens,
	}
	h := handler.New(providerRegistry, systemPrompts, defaultSystemPrompt, compactConfig, registry, store, st, authService, logger, ui.FS(), uiConfig, uploadRoot, traceEnabled)
	appcore.StartAutoDiscover(ctx, h, cfg, logger)
	mcpHandler := handler.NewMCPToolsHandler(mcpManager, logger)

	// Scheduler
	schedStore, err := scheduler.NewStore(schedulerDir)
	if err != nil {
		logger.Fatal("failed to create scheduler store", zap.Error(err))
	}
	schedRunner := scheduler.NewRunner(providerRegistry, registry, logger, traceEnabled)
	sched := scheduler.New(schedStore, schedRunner, authService, systemPrompts, logger)
	if err := sched.Start(ctx); err != nil {
		logger.Fatal("failed to start scheduler", zap.Error(err))
	}
	schedHandler := handler.NewScheduleHandler(sched, logger)

	mux := http.NewServeMux()
	appcore.RegisterRoutes(mux, authService, h, mcpHandler, schedHandler)

	tlsConfig, certFile, keyFile, err := appcore.PrepareTLSConfig(cfg, logger)
	if err != nil {
		return fmt.Errorf("prepare TLS: %w", err)
	}
	srv := &http.Server{
		Addr:         cfg.Server.Address,
		Handler:      mux,
		ErrorLog:     log.New(&filteredHTTPErrorLogWriter{logger: logger.Named("http")}, "", 0),
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 120 * time.Second,
		IdleTimeout:  120 * time.Second,
		TLSConfig:    tlsConfig,
	}

	go func() {
		fields := []zap.Field{
			zap.String("address", cfg.Server.Address),
			zap.Int("providers", len(cfg.LLM.Providers)),
			zap.Int("models", len(providerRegistry.AllModels())),
			zap.Bool("tls_enabled", tlsConfig != nil),
		}
		if tlsConfig != nil {
			fields = append(fields,
				zap.String("scheme", "https"),
				zap.String("tls_cert_file", certFile),
				zap.String("tls_key_file", keyFile),
			)
		} else {
			fields = append(fields, zap.String("scheme", "http"))
		}
		logger.Info("server started", fields...)
		var serveErr error
		if tlsConfig != nil {
			serveErr = srv.ListenAndServeTLS("", "")
		} else {
			serveErr = srv.ListenAndServe()
		}
		if serveErr != nil && serveErr != http.ErrServerClosed {
			logger.Fatal("server error", zap.Error(serveErr))
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
	return nil
}

func runHashCommand(promptLabel string) error {
	value, err := readSecretFromPrompt(promptLabel)
	if err != nil {
		return fmt.Errorf("failed to read %s: %w", strings.ToLower(promptLabel), err)
	}
	if strings.TrimSpace(value) == "" {
		return errors.New(promptLabel + " cannot be empty")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(value), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("failed to generate hash: %w", err)
	}
	fmt.Println(string(hash))
	return nil
}

func formatVersionDetails(v version.Version) string {
	return fmt.Sprintf(
		"Version:   %s\nGitCommit: %s\nBuildDate: %s\nGoVersion: %s\nCompiler:  %s\nPlatform:  %s\nArch:      %s\n",
		v.Version,
		emptyVersionValue(v.GitCommit),
		emptyVersionValue(v.BuildDate),
		v.GoVersion,
		v.Compiler,
		v.Platform,
		v.Arch,
	)
}

func emptyVersionValue(value string) string {
	if strings.TrimSpace(value) == "" {
		return "unknown"
	}
	return value
}

type filteredHTTPErrorLogWriter struct {
	logger *zap.Logger
}

func (w *filteredHTTPErrorLogWriter) Write(p []byte) (int, error) {
	message := strings.TrimSpace(string(p))
	if shouldSuppressHTTPErrorLog(message) {
		return len(p), nil
	}
	w.logger.Error(message)
	return len(p), nil
}

func shouldSuppressHTTPErrorLog(message string) bool {
	return strings.Contains(message, "http: TLS handshake error") &&
		strings.Contains(message, "remote error: tls: unknown certificate")
}

func readSecretFromPrompt(label string) (string, error) {
	if term.IsTerminal(int(os.Stdin.Fd())) {
		fmt.Fprintf(os.Stderr, "%s: ", label)
		secret, err := term.ReadPassword(int(syscall.Stdin))
		fmt.Fprintln(os.Stderr)
		if err != nil {
			return "", err
		}
		return strings.TrimSpace(string(secret)), nil
	}
	fmt.Fprintf(os.Stderr, "%s: ", label)
	reader := bufio.NewReader(os.Stdin)
	line, err := reader.ReadString('\n')
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(line), nil
}
