PORT               ?= 8080
LOG_LEVEL          ?= info
SYSTEM_PROMPT_FILE ?=
TOOLS_CONFIG       ?= tools.yaml
LLM_BASE_URL       ?=
LLM_API_KEY        ?=

# ── UI ────────────────────────────────────────────────────────────────────────

.PHONY: ui
ui:
	cd web && pnpm install --frozen-lockfile && pnpm build
	rm -rf internal/ui/dist
	cp -r web/dist internal/ui/dist

# ── Dev ───────────────────────────────────────────────────────────────────────

.PHONY: run
run: ui
	@export $(shell grep -v '^#' .env | xargs) && \
	PORT=$(PORT) LOG_LEVEL=$(LOG_LEVEL) \
	SYSTEM_PROMPT_FILE=$(SYSTEM_PROMPT_FILE) \
	TOOLS_CONFIG=$(TOOLS_CONFIG) \
	go run .

.PHONY: wordcount
wordcount:
	go run ./examples/wordcount --addr :9001 --self http://localhost:9001 --chatbot http://localhost:8080

# ── Build ─────────────────────────────────────────────────────────────────────

.PHONY: build
build: ui
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o chatbot .

.PHONY: clean
clean:
	rm -f chatbot
	rm -rf internal/ui/dist
	rm -rf web/dist
