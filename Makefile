# Makefile for promptd

BIN     := promptd
CMD     := ./cmd
CONFIG  ?= ./config.yaml

# ---------------------------------------------------------------------------
# Version stamping — override any of these on the command line or let them
# be derived automatically from git.
# ---------------------------------------------------------------------------
VERSION    ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
GIT_COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

PKG        := promptd/internal/version
LDFLAGS    := -s -w \
              -X $(PKG).version=$(VERSION) \
              -X $(PKG).gitCommit=$(GIT_COMMIT) \
              -X $(PKG).buildDate=$(BUILD_DATE)

# ── UI ────────────────────────────────────────────────────────────────────────

.PHONY: ui
ui:
	cd web && pnpm install --frozen-lockfile && pnpm build
	rm -rf internal/ui/dist
	cp -r web/dist internal/ui/dist

# ── Dev ───────────────────────────────────────────────────────────────────────

.PHONY: run
run: ui
	go run $(CMD) -config $(CONFIG)

# Run without rebuilding the UI (faster for backend-only changes).
.PHONY: run-go
run-go:
	go run $(CMD) -config $(CONFIG)

# ── Build ─────────────────────────────────────────────────────────────────────

.PHONY: build
build: ui
	CGO_ENABLED=0 go build -trimpath -ldflags="$(LDFLAGS)" -o $(BIN) $(CMD)

.PHONY: clean
clean:
	rm -f $(BIN)
	rm -rf internal/ui/dist
	rm -rf web/dist

# ── Quality ───────────────────────────────────────────────────────────────────

.PHONY: vet
vet:
	go vet ./...

.PHONY: fmt
fmt:
	gofmt -w .

.PHONY: tidy
tidy:
	go mod tidy
