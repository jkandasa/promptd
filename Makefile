PORT               ?= 8080
LOG_LEVEL          ?= info
SYSTEM_PROMPT_FILE ?=
TOOLS_CONFIG       ?= tools.yaml
LLM_BASE_URL       ?=
LLM_API_KEY        ?=

run:
	@export $(shell grep -v '^#' .env | xargs) && PORT=$(PORT) LOG_LEVEL=$(LOG_LEVEL) SYSTEM_PROMPT_FILE=$(SYSTEM_PROMPT_FILE) TOOLS_CONFIG=$(TOOLS_CONFIG) go run .

wordcount:
	go run ./examples/wordcount --addr :9001 --self http://localhost:9001 --chatbot http://localhost:8080

build:
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o chatbot .

clean:
	rm -f chatbot
