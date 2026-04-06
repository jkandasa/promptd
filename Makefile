# Makefile for chatbot

CONFIG ?= ./config.yaml

# ── UI ────────────────────────────────────────────────────────────────────────

.PHONY: ui
ui:
	cd web && pnpm install --frozen-lockfile && pnpm build
	rm -rf internal/ui/dist
	cp -r web/dist internal/ui/dist

# ── Dev ───────────────────────────────────────────────────────────────────────

.PHONY: run
run: ui
	go run . -config $(CONFIG)

# ── Build ─────────────────────────────────────────────────────────────────────

.PHONY: build
build: ui
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o chatbot .

.PHONY: clean
clean:
	rm -f chatbot
	rm -rf internal/ui/dist
	rm -rf web/dist