package auth

import (
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"go.uber.org/zap"
	"golang.org/x/crypto/bcrypt"
	"gopkg.in/yaml.v3"
)

type StoreData struct {
	Users []User          `yaml:"users" json:"users"`
	Roles map[string]Role `yaml:"roles" json:"roles"`
}

type Store struct {
	path string
	mu   sync.Mutex
}

func NewStore(path string) *Store {
	return &Store{path: path}
}

func (s *Store) LoadOrBootstrap(users []User, roles map[string]Role, logger *zap.Logger) (StoreData, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := s.loadLocked()
	if err == nil {
		return data, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return StoreData{}, err
	}

	data = StoreData{Users: append([]User(nil), users...), Roles: copyRoles(roles)}
	if data.Roles == nil {
		data.Roles = map[string]Role{}
	}
	if _, ok := data.Roles["admin"]; !ok {
		data.Roles["admin"] = Role{SuperAdmin: true}
	}
	if len(data.Users) == 0 {
		password, err := randomPassword()
		if err != nil {
			return StoreData{}, err
		}
		hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
		if err != nil {
			return StoreData{}, err
		}
		data.Users = []User{{
			ID:                 "admin",
			TenantID:           "default",
			PasswordHash:       string(hash),
			Roles:              []string{"admin"},
			MustChangePassword: true,
		}}
		logger.Warn("bootstrap admin user created", zap.String("user", "admin"), zap.String("password", password), zap.String("message", "change this password on first login"))
	}
	if err := s.saveLocked(data); err != nil {
		return StoreData{}, err
	}
	return data, nil
}

func (s *Store) Save(data StoreData) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.saveLocked(data)
}

func (s *Store) loadLocked() (StoreData, error) {
	content, err := os.ReadFile(s.path)
	if err != nil {
		return StoreData{}, err
	}
	var data StoreData
	if err := yaml.Unmarshal(content, &data); err != nil {
		return StoreData{}, err
	}
	if data.Roles == nil {
		data.Roles = map[string]Role{}
	}
	return data, nil
}

func (s *Store) saveLocked(data StoreData) error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	content, err := yaml.Marshal(data)
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, content, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

func copyRoles(in map[string]Role) map[string]Role {
	out := make(map[string]Role, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}

func randomPassword() (string, error) {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate admin password: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
