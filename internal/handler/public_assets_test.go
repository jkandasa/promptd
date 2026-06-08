package handler

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"go.uber.org/zap"

	"promptd/internal/storage"
)

func newTestStore(t *testing.T) (*PublicAssetStore, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "public-assets.yaml")
	s, err := NewPublicAssetStore(path, zap.NewNop())
	if err != nil {
		t.Fatalf("NewPublicAssetStore: %v", err)
	}
	return s, path
}

func TestPublicAssetStore_ShareGet(t *testing.T) {
	s, _ := newTestStore(t)

	token := s.Share("tenant", "user", "file-1", "cat.png", "image/png", time.Hour)
	if token == "" {
		t.Fatal("expected non-empty token")
	}

	rec, ok := s.Get(token)
	if !ok {
		t.Fatal("expected to resolve token")
	}
	if rec.FileID != "file-1" || rec.TenantID != "tenant" || rec.UserID != "user" {
		t.Fatalf("unexpected record: %+v", rec)
	}
	if rec.ContentType != "image/png" {
		t.Fatalf("unexpected content type: %q", rec.ContentType)
	}

	if _, ok := s.Get("does-not-exist"); ok {
		t.Fatal("expected miss for unknown token")
	}
}

func TestPublicAssetStore_ReusesTokenForSameFile(t *testing.T) {
	s, _ := newTestStore(t)
	a := s.Share("t", "u", "file-1", "a.png", "image/png", time.Hour)
	b := s.Share("t", "u", "file-1", "a.png", "image/png", time.Hour)
	if a != b {
		t.Fatalf("expected reuse, got %q and %q", a, b)
	}
	c := s.Share("t", "u", "file-2", "b.png", "image/png", time.Hour)
	if c == a {
		t.Fatal("different files must get different tokens")
	}
}

func TestPublicAssetStore_ExpiredTokenNotServed(t *testing.T) {
	s, _ := newTestStore(t)
	token := s.Share("t", "u", "file-1", "a.png", "image/png", time.Millisecond)
	time.Sleep(5 * time.Millisecond)
	if _, ok := s.Get(token); ok {
		t.Fatal("expected expired token to miss")
	}
}

func TestPublicAssetStore_PersistsAcrossReload(t *testing.T) {
	s, path := newTestStore(t)
	token := s.Share("t", "u", "file-1", "a.png", "image/png", time.Hour)

	reloaded, err := NewPublicAssetStore(path, zap.NewNop())
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if _, ok := reloaded.Get(token); !ok {
		t.Fatal("expected token to survive reload")
	}
}

func TestServePublicAsset(t *testing.T) {
	uploadRoot := t.TempDir()
	store, _ := newTestStore(t)
	h := &Handler{uploadRoot: uploadRoot, log: zap.NewNop(), publicAssets: PublicAssetConfig{Store: store}}

	scope := storage.Scope{TenantID: "t", UserID: "u"}
	uploadDir := h.uploadDir(scope)
	if err := os.MkdirAll(uploadDir, 0o755); err != nil {
		t.Fatalf("mkdir uploads: %v", err)
	}
	want := []byte("\x89PNG\r\n\x1a\nfake-image-bytes")
	fileID := "file-1"
	if err := os.WriteFile(filepath.Join(uploadDir, fileID), want, 0o600); err != nil {
		t.Fatalf("write upload: %v", err)
	}
	token := store.Share(scope.TenantID, scope.UserID, fileID, "cat.png", "image/png", time.Hour)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/assets/public/{token}/{filename}", h.ServePublicAsset)

	// Valid token serves the file with the recorded content type.
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/assets/public/"+token+"/cat.png", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := rec.Body.Bytes(); string(got) != string(want) {
		t.Fatalf("body mismatch: got %q", got)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "image/png" {
		t.Fatalf("content-type = %q, want image/png", ct)
	}

	// Unknown token returns 404.
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/assets/public/nope/cat.png", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
}

func TestPublicAssetStore_DropsExpiredOnReload(t *testing.T) {
	s, path := newTestStore(t)
	token := s.Share("t", "u", "file-1", "a.png", "image/png", time.Millisecond)
	time.Sleep(5 * time.Millisecond)

	reloaded, err := NewPublicAssetStore(path, zap.NewNop())
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	if _, ok := reloaded.Get(token); ok {
		t.Fatal("expected expired token to be dropped on reload")
	}
}
