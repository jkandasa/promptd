package tools

import (
	"fmt"
	"os"

	"go.uber.org/zap"
	"gopkg.in/yaml.v3"
)

type toolsConfig struct {
	Tools []struct {
		URL string `yaml:"url"`
	} `yaml:"tools"`
}

// LoadFromConfig reads a YAML config file and registers each remote tool URL
// into the registry, also starting heartbeat monitoring for each one.
// Missing or empty config files are silently skipped.
func LoadFromConfig(path string, registry *Registry, monitor *Monitor, log *zap.Logger) error {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			log.Debug("no remote tools config found", zap.String("path", path))
			return nil
		}
		return fmt.Errorf("reading tools config %s: %w", path, err)
	}

	var cfg toolsConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return fmt.Errorf("parsing tools config %s: %w", path, err)
	}

	for _, entry := range cfg.Tools {
		if entry.URL == "" {
			continue
		}
		remoteTools, err := NewRemoteTools(entry.URL)
		if err != nil {
			log.Warn("skipping remote tool server", zap.String("url", entry.URL), zap.Error(err))
			continue
		}
		for _, t := range remoteTools {
			registry.Register(t)
			monitor.Track(t.Name(), entry.URL)
			log.Info("remote tool registered", zap.String("name", t.Name()), zap.String("url", entry.URL))
		}
	}

	return nil
}
