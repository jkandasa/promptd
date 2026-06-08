package handler

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"
	"gopkg.in/yaml.v3"
)

// PublicAssetRecord maps a random share token to a previously uploaded file so
// the file can be fetched over an unauthenticated public URL until it expires.
//
// The random token doubles as an auth token: without the exact URL nobody can
// reach the file. The TTL applies ONLY to this shared URL — the underlying
// uploaded file under <data>/.../uploads is never touched by expiry.
type PublicAssetRecord struct {
	Token       string `yaml:"token"`
	TenantID    string `yaml:"tenant_id"`
	UserID      string `yaml:"user_id"`
	FileID      string `yaml:"file_id"`
	Filename    string `yaml:"filename,omitempty"`
	ContentType string `yaml:"content_type,omitempty"`
	CreatedAt   int64  `yaml:"created_at"`
	ExpiresAt   int64  `yaml:"expires_at"`
}

// PublicAssetStore persists share-token → file mappings to a YAML file so
// shared URLs keep working across restarts (within their TTL). All access is
// guarded by a mutex and the file is rewritten atomically.
type PublicAssetStore struct {
	path    string
	log     *zap.Logger
	mu      sync.Mutex
	byToken map[string]PublicAssetRecord
	byFile  map[string]string // tenant|user|fileID → token (for reuse)
}

// reuseSafetyMargin avoids handing back a token that is about to expire before
// the provider has a chance to fetch it.
const reuseSafetyMargin = 30 * time.Second

// NewPublicAssetStore loads any existing records from disk, dropping expired
// entries. A missing file is not an error.
func NewPublicAssetStore(path string, log *zap.Logger) (*PublicAssetStore, error) {
	s := &PublicAssetStore{
		path:    path,
		log:     log,
		byToken: make(map[string]PublicAssetRecord),
		byFile:  make(map[string]string),
	}
	if err := s.load(); err != nil {
		return nil, err
	}
	return s, nil
}

func fileKey(tenantID, userID, fileID string) string {
	return tenantID + "|" + userID + "|" + fileID
}

func (s *PublicAssetStore) load() error {
	content, err := os.ReadFile(s.path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	var records []PublicAssetRecord
	if err := yaml.Unmarshal(content, &records); err != nil {
		return err
	}
	now := time.Now().UnixMilli()
	for _, r := range records {
		if r.Token == "" || r.ExpiresAt <= now {
			continue
		}
		s.byToken[r.Token] = r
		s.byFile[fileKey(r.TenantID, r.UserID, r.FileID)] = r.Token
	}
	return nil
}

// saveLocked rewrites the store atomically. Callers must hold s.mu.
func (s *PublicAssetStore) saveLocked() error {
	records := make([]PublicAssetRecord, 0, len(s.byToken))
	for _, r := range s.byToken {
		records = append(records, r)
	}
	content, err := yaml.Marshal(records)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, content, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

// Share returns a public share token for the given file, reusing an existing
// non-expiring token when possible. ttl applies to the shared URL only.
func (s *PublicAssetStore) Share(tenantID, userID, fileID, filename, contentType string, ttl time.Duration) string {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	key := fileKey(tenantID, userID, fileID)
	if token, ok := s.byFile[key]; ok {
		if rec, ok := s.byToken[token]; ok {
			if time.UnixMilli(rec.ExpiresAt).After(now.Add(reuseSafetyMargin)) {
				return token
			}
			delete(s.byToken, token)
		}
	}

	rec := PublicAssetRecord{
		Token:       uuid.NewString(),
		TenantID:    tenantID,
		UserID:      userID,
		FileID:      fileID,
		Filename:    filename,
		ContentType: contentType,
		CreatedAt:   now.UnixMilli(),
		ExpiresAt:   now.Add(ttl).UnixMilli(),
	}
	s.byToken[rec.Token] = rec
	s.byFile[key] = rec.Token
	if err := s.saveLocked(); err != nil && s.log != nil {
		s.log.Warn("failed to persist public asset record", zap.String("file_id", fileID), zap.Error(err))
	}
	return rec.Token
}

// Get returns the record for a token if it exists and has not expired.
func (s *PublicAssetStore) Get(token string) (PublicAssetRecord, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.byToken[token]
	if !ok {
		return PublicAssetRecord{}, false
	}
	if rec.ExpiresAt <= time.Now().UnixMilli() {
		return PublicAssetRecord{}, false
	}
	return rec, true
}

// cleanup drops expired records and persists the store when anything changed.
func (s *PublicAssetStore) cleanup() {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now().UnixMilli()
	removed := false
	for token, rec := range s.byToken {
		if rec.ExpiresAt <= now {
			delete(s.byToken, token)
			delete(s.byFile, fileKey(rec.TenantID, rec.UserID, rec.FileID))
			removed = true
		}
	}
	if removed {
		if err := s.saveLocked(); err != nil && s.log != nil {
			s.log.Warn("failed to persist public asset store after cleanup", zap.Error(err))
		}
	}
}

// StartCleanup runs a background sweep that removes expired share tokens until
// the context is cancelled.
func (s *PublicAssetStore) StartCleanup(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.cleanup()
		}
	}
}
