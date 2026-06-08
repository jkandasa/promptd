package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"promptd/internal/auth"
	"promptd/internal/handler"

	"go.uber.org/zap"
	"gopkg.in/yaml.v3"
)

// Duration is a time.Duration that also accepts "d" (days) as a unit when
// unmarshalling from YAML. For example "30d" is equivalent to "720h".
type Duration time.Duration

func (d *Duration) UnmarshalYAML(value *yaml.Node) error {
	s := strings.TrimSpace(value.Value)
	// Replace trailing 'd' with the equivalent number of hours so that
	// time.ParseDuration can handle it (e.g. "30d" -> "720h").
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

type ImageGenerationConfig struct {
	Enabled       *bool  `yaml:"enabled"`
	Strategy      string `yaml:"strategy,omitempty"`
	ResponseField string `yaml:"response_field,omitempty"`
}

type LLMProviderConfig struct {
	Name            string             `yaml:"name"`
	APIKey          string             `yaml:"api_key"`
	BaseURL         string             `yaml:"base_url"`
	SelectionMethod string             `yaml:"selection_method,omitempty"`
	Models          []LLMModel         `yaml:"models"`
	Params          LLMParams          `yaml:"params"`
	AutoDiscover    AutoDiscoverConfig `yaml:"auto_discover"`
	FileUploads     struct {
		Enabled            *bool  `yaml:"enabled"`
		Purpose            string `yaml:"purpose"`
		MaxInlineTextBytes int    `yaml:"max_inline_text_bytes"`
		PreferInlineImages bool   `yaml:"prefer_inline_images"`
		// ImageURLMode controls how images are sent to the provider as
		// image_url content parts: "base64" (default, inline data URL),
		// "url" (a temporary public promptd URL the provider fetches), or
		// "off" (skip image_url; use legacy file-upload/metadata handling).
		ImageURLMode string `yaml:"image_url_mode"`
		// PublicAssetTTL overrides server.public_asset_ttl for this provider.
		// It only bounds the shared image URL, never the stored upload.
		PublicAssetTTL Duration `yaml:"public_asset_ttl"`
	} `yaml:"file_uploads"`
	ImageGeneration ImageGenerationConfig `yaml:"image_generation"`
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

type LogConfig struct {
	Level            string `yaml:"level"`
	Encoding         string `yaml:"encoding"`
	EnableStacktrace bool   `yaml:"enable_stacktrace"`
}

type Config struct {
	Data struct {
		Dir string `yaml:"dir"`
	} `yaml:"data"`
	Server struct {
		Address string `yaml:"address"`
		// PublicBaseURL is the externally reachable base URL of this promptd
		// server (scheme + host [+ port]), e.g. "https://promptd.example.com".
		// It may be a domain, a public IPv4, or a bracketed IPv6 address.
		// Used to build temporary shareable image URLs for providers that
		// fetch images by URL (file_uploads.image_url_mode: url).
		PublicBaseURL string `yaml:"public_base_url"`
		// PublicAssetTTL is the global default lifetime of a shared image URL.
		// It applies only to the shared URL token, never to the stored upload.
		// Providers may override it via file_uploads.public_asset_ttl.
		PublicAssetTTL Duration `yaml:"public_asset_ttl"`
		TLS            struct {
			Enabled      bool     `yaml:"enabled"`
			CertFile     string   `yaml:"cert_file"`
			KeyFile      string   `yaml:"key_file"`
			AutoGenerate bool     `yaml:"auto_generate"`
			Hosts        []string `yaml:"hosts"`
		} `yaml:"tls"`
	} `yaml:"server"`
	LLM struct {
		SelectionMethod     string               `yaml:"selection_method"`
		AutoDiscover        AutoDiscoverConfig   `yaml:"auto_discover"`
		Providers           []LLMProviderConfig  `yaml:"providers"`
		SystemPrompts       []SystemPromptConfig `yaml:"system_prompts"`
		CompactConversation struct {
			Enabled       bool   `yaml:"enabled"`
			Provider      string `yaml:"provider"`
			Model         string `yaml:"model"`
			DefaultPrompt string `yaml:"default_prompt"`
			AfterMessages int    `yaml:"after_messages"`
			AfterTokens   int    `yaml:"after_tokens"`
		} `yaml:"compact_conversation"`
		Trace struct {
			TTL     Duration `yaml:"ttl"`
			Enabled *bool    `yaml:"enabled"`
		} `yaml:"trace"`
	} `yaml:"llm"`
	Log LogConfig `yaml:"log"`
	MCP struct {
		HealthMaxFailures       int               `yaml:"health_max_failures"`
		HealthInterval          time.Duration     `yaml:"health_interval"`
		ReconnectInterval       Duration          `yaml:"reconnect_interval"`
		Timeout                 Duration          `yaml:"timeout"`
		ToolRediscoveryInterval Duration          `yaml:"tool_rediscovery_interval"`
		Servers                 []MCPServerConfig `yaml:"servers"`
	} `yaml:"mcp"`
	Auth struct {
		JWT   auth.JWTConfig `yaml:"jwt"`
		Users []auth.User    `yaml:"users"`
	} `yaml:"auth"`
	Roles map[string]auth.Role `yaml:"roles"`
	UI    struct {
		WelcomeTitle      string   `yaml:"welcome_title"`
		AIDisclaimer      string   `yaml:"ai_disclaimer"`
		PromptSuggestions []string `yaml:"prompt_suggestions"`
	} `yaml:"ui"`
}

func LoadSystemPrompts(cfg *Config, logger *zap.Logger) (map[string]string, []handler.SystemPromptInfo, string) {
	prompts := make(map[string]string)
	infos := make([]handler.SystemPromptInfo, 0, len(cfg.LLM.SystemPrompts))
	firstPrompt := ""

	if len(cfg.LLM.SystemPrompts) == 0 {
		logger.Fatal("at least one system prompt is required under llm.system_prompts")
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

	for _, prompt := range cfg.LLM.SystemPrompts {
		loadPrompt(prompt.Name, prompt.File)
	}

	return prompts, infos, firstPrompt
}

func Load(path string) (*Config, error) {
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
	cfg.Server.PublicBaseURL = strings.TrimRight(strings.TrimSpace(cfg.Server.PublicBaseURL), "/")
	if cfg.Server.PublicAssetTTL <= 0 {
		cfg.Server.PublicAssetTTL = Duration(15 * time.Minute)
	}
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
		if p.FileUploads.Enabled == nil {
			enabled := false
			baseURL := strings.ToLower(strings.TrimSpace(p.BaseURL))
			name := strings.ToLower(strings.TrimSpace(p.Name))
			if strings.Contains(baseURL, "api.openai.com") || name == "openai" {
				enabled = true
			}
			p.FileUploads.Enabled = &enabled
		}
		if p.FileUploads.Purpose == "" {
			p.FileUploads.Purpose = "user_data"
		}
		if p.FileUploads.MaxInlineTextBytes <= 0 {
			p.FileUploads.MaxInlineTextBytes = 128 * 1024
		}
		switch strings.ToLower(strings.TrimSpace(p.FileUploads.ImageURLMode)) {
		case "url":
			p.FileUploads.ImageURLMode = "url"
		case "off", "none":
			p.FileUploads.ImageURLMode = "off"
		default:
			p.FileUploads.ImageURLMode = "base64"
		}
		if p.ImageGeneration.Enabled == nil {
			enabled := p.ImageGeneration.Strategy != "" || p.ImageGeneration.ResponseField != ""
			p.ImageGeneration.Enabled = &enabled
		}
		if p.ImageGeneration.Strategy == "" {
			p.ImageGeneration.Strategy = "chat_completions"
		}
		if p.ImageGeneration.ResponseField == "" {
			switch p.ImageGeneration.Strategy {
			case "images_api":
				p.ImageGeneration.ResponseField = "images_data"
			default:
				p.ImageGeneration.ResponseField = "message_images"
			}
		}
	}
	if cfg.Log.Level == "" {
		cfg.Log.Level = "info"
	}

	if cfg.Data.Dir == "" {
		cfg.Data.Dir = "./data"
	}
	if cfg.Server.TLS.AutoGenerate {
		if cfg.Server.TLS.CertFile == "" {
			cfg.Server.TLS.CertFile = filepath.Join(cfg.Data.Dir, "tls", "server.crt")
		}
		if cfg.Server.TLS.KeyFile == "" {
			cfg.Server.TLS.KeyFile = filepath.Join(cfg.Data.Dir, "tls", "server.key")
		}
	}

	if cfg.MCP.ReconnectInterval == 0 {
		cfg.MCP.ReconnectInterval = Duration(30 * time.Second)
	}
	if cfg.MCP.Timeout == 0 {
		cfg.MCP.Timeout = Duration(30 * time.Second)
	}

	if cfg.LLM.Trace.TTL == 0 {
		cfg.LLM.Trace.TTL = Duration(7 * 24 * time.Hour)
	}
	if cfg.LLM.Trace.TTL < Duration(time.Hour) {
		cfg.LLM.Trace.TTL = Duration(time.Hour)
	}
	if cfg.LLM.Trace.Enabled == nil {
		b := true
		cfg.LLM.Trace.Enabled = &b
	}

	return &cfg, nil
}
