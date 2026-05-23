# Makefile for promptd

BIN     := promptd
CMD     := ./cmd
CONFIG  ?= ./config.yaml
IMAGE   ?= ghcr.io/jkandasa/promptd:local

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

# Pass WITH_CONSOLE=1 (or use build-with-console) to embed the Flutter console
# instead of the default React/Yarn web UI.
WITH_CONSOLE ?= 0

.PHONY: ui
ui:
ifeq ($(WITH_CONSOLE),1)
	$(MAKE) console-ui
else
	$(MAKE) web-ui
endif

.PHONY: web-ui
web-ui:
	cd web && yarn install --immutable && yarn build
	rm -rf internal/ui/dist
	cp -r web/dist internal/ui/dist

.PHONY: console-ui
console-ui:
	cd console && flutter build web --release -O4 --no-source-maps
	rm -rf internal/ui/dist
	cp -r console/build/web internal/ui/dist

# ── Dev ───────────────────────────────────────────────────────────────────────

.PHONY: run
run: ui
	go run $(CMD) serve --config $(CONFIG)

# Run without rebuilding the UI (faster for backend-only changes).
.PHONY: run-go
run-go:
	go run $(CMD) serve --config $(CONFIG)

# ── Build ─────────────────────────────────────────────────────────────────────

.PHONY: build
build: ui
	CGO_ENABLED=0 go build -trimpath -ldflags="$(LDFLAGS)" -o $(BIN) $(CMD)

# Build with the Flutter console UI embedded instead of the default web UI.
.PHONY: build-with-console
build-with-console:
	$(MAKE) build WITH_CONSOLE=1

.PHONY: docker-build
docker-build: build
	docker build --build-arg BINARY_PATH=./$(BIN) -t $(IMAGE) .

.PHONY: clean
clean:
	rm -f $(BIN)
	rm -rf internal/ui/dist
	rm -rf web/dist
	rm -rf console/build/web

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
