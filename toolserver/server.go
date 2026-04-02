// Package toolserver provides helpers for building remote tool binaries.
//
// A remote tool is a standalone HTTP server that implements:
//
//	GET  /describe   — returns tool metadata (name, description, parameters)
//	POST /execute    — executes the tool with given arguments
//	GET  /health     — health check, returns 200 OK
//
// Use [Serve] for a simple setup without auto-registration.
// Use [ServeWithConfig] to enable auto-registration with the chatbot.
package toolserver

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// Tool is the interface a remote tool binary must implement.
type Tool interface {
	Name() string
	Description() string
	Parameters() any
	Execute(ctx context.Context, args json.RawMessage) (string, error)
}

// Config holds options for ServeWithConfig.
type Config struct {
	// Addr is the address to listen on, e.g. ":9001".
	Addr string
	// SelfURL is the URL the chatbot should use to reach this tool,
	// e.g. "http://localhost:9001". Required for auto-registration.
	SelfURL string
	// ChatbotURL is the chatbot base URL for auto-registration,
	// e.g. "http://localhost:8080". If empty, auto-registration is disabled.
	ChatbotURL string
}

// DescribeResponse is returned by GET /describe.
type DescribeResponse struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	Parameters  any    `json:"parameters"`
}

// ExecuteRequest is accepted by POST /execute.
type ExecuteRequest struct {
	Args json.RawMessage `json:"args"`
}

// ExecuteResponse is returned by POST /execute.
type ExecuteResponse struct {
	Result string `json:"result,omitempty"`
	Error  string `json:"error,omitempty"`
}

// Serve starts a single-tool server on addr without auto-registration.
// It blocks until the process receives SIGTERM or SIGINT.
func Serve(addr string, tool Tool) error {
	return ServeWithConfig(Config{Addr: addr}, tool)
}

// ServeWithConfig starts a single-tool server with optional auto-registration.
// If ChatbotURL and SelfURL are set, the tool registers itself with the
// chatbot on startup and unregisters itself on graceful shutdown.
func ServeWithConfig(cfg Config, tool Tool) error {
	return serveInternal(cfg, tool)
}

// ServeMulti starts a multi-tool server on addr without auto-registration.
// All tools are served from a single HTTP server.
// /describe returns an array; /execute requires a "name" field to dispatch.
func ServeMulti(addr string, tools ...Tool) error {
	return ServeMultiWithConfig(Config{Addr: addr}, tools...)
}

// ServeMultiWithConfig starts a multi-tool server with optional auto-registration.
func ServeMultiWithConfig(cfg Config, tools ...Tool) error {
	if len(tools) == 0 {
		return fmt.Errorf("at least one tool is required")
	}
	if len(tools) == 1 {
		return serveInternal(cfg, tools[0])
	}
	return serveMultiInternal(cfg, tools)
}

func serveInternal(cfg Config, tool Tool) error {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /describe", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, DescribeResponse{
			Name:        tool.Name(),
			Description: tool.Description(),
			Parameters:  tool.Parameters(),
		})
	})

	mux.HandleFunc("POST /execute", func(w http.ResponseWriter, r *http.Request) {
		var req ExecuteRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusOK, ExecuteResponse{Error: "invalid request: " + err.Error()})
			return
		}
		result, err := tool.Execute(r.Context(), req.Args)
		if err != nil {
			writeJSON(w, http.StatusOK, ExecuteResponse{Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, ExecuteResponse{Result: result})
	})

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	srv := &http.Server{Addr: cfg.Addr, Handler: mux}
	return startServer(srv, cfg, tool.Name())
}

func serveMultiInternal(cfg Config, tools []Tool) error {
	index := make(map[string]Tool, len(tools))
	for _, t := range tools {
		index[t.Name()] = t
	}

	mux := http.NewServeMux()

	// Describe returns an array of all tools.
	mux.HandleFunc("GET /describe", func(w http.ResponseWriter, r *http.Request) {
		descs := make([]DescribeResponse, 0, len(tools))
		for _, t := range tools {
			descs = append(descs, DescribeResponse{
				Name:        t.Name(),
				Description: t.Description(),
				Parameters:  t.Parameters(),
			})
		}
		writeJSON(w, http.StatusOK, descs)
	})

	// Execute dispatches to the named tool.
	mux.HandleFunc("POST /execute", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Name string          `json:"name"`
			Args json.RawMessage `json:"args"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusOK, ExecuteResponse{Error: "invalid request: " + err.Error()})
			return
		}
		t, ok := index[req.Name]
		if !ok {
			writeJSON(w, http.StatusOK, ExecuteResponse{Error: fmt.Sprintf("unknown tool %q", req.Name)})
			return
		}
		result, err := t.Execute(r.Context(), req.Args)
		if err != nil {
			writeJSON(w, http.StatusOK, ExecuteResponse{Error: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, ExecuteResponse{Result: result})
	})

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	srv := &http.Server{Addr: cfg.Addr, Handler: mux}
	names := make([]string, 0, len(tools))
	for _, t := range tools {
		names = append(names, t.Name())
	}
	return startServer(srv, cfg, fmt.Sprintf("[%s]", join(names)))
}

// startServer starts srv and handles lifecycle (auto-register, graceful shutdown).
// label is used only for log messages (tool name or comma-separated list).
func startServer(srv *http.Server, cfg Config, label string) error {
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)

	go func() {
		log.Printf("tool server %s listening on %s", label, cfg.Addr)
		if cfg.ChatbotURL != "" && cfg.SelfURL != "" {
			time.Sleep(200 * time.Millisecond)
			if err := register(cfg.ChatbotURL, cfg.SelfURL); err != nil {
				log.Printf("warning: auto-registration failed: %v", err)
			} else {
				log.Printf("registered with chatbot at %s", cfg.ChatbotURL)
			}
		}
	}()

	go func() {
		<-quit
		log.Printf("shutting down tool server %s ...", label)
		if cfg.ChatbotURL != "" && cfg.SelfURL != "" {
			if err := unregister(cfg.ChatbotURL, cfg.SelfURL); err != nil {
				log.Printf("warning: auto-unregistration failed: %v", err)
			} else {
				log.Printf("unregistered from chatbot at %s", cfg.ChatbotURL)
			}
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(ctx)
	}()

	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}

func join(ss []string) string {
	result := ""
	for i, s := range ss {
		if i > 0 {
			result += ", "
		}
		result += s
	}
	return result
}

func register(chatbotURL, selfURL string) error {
	return callChatbot(http.MethodPost, chatbotURL+"/tools/register", selfURL)
}

func unregister(chatbotURL, selfURL string) error {
	return callChatbot(http.MethodDelete, chatbotURL+"/tools/unregister", selfURL)
}

func callChatbot(method, url, selfURL string) error {
	body, _ := json.Marshal(map[string]string{"url": selfURL})
	req, err := http.NewRequest(method, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("chatbot returned status %d", resp.StatusCode)
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
