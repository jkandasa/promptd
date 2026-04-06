# Chatbot

A lightweight, extensible LLM chatbot server written in Go. Connects to any OpenAI-compatible API endpoint (OpenRouter, OpenAI, Google Gemini, etc.), maintains per-session conversation history, supports configurable system prompts, and ships with a built-in tool system — including remote tools that run as independent HTTP servers in any language.

---

## Features

- **Multi-provider** — works with any OpenAI-compatible API (OpenRouter, OpenAI, Gemini, Mistral, …)
- **Session management** — each browser tab gets its own isolated conversation history
- **Tool calling** — native LLM function-calling loop with built-in and remote tools
- **Remote tools** — extend the bot with standalone HTTP servers written in any language
- **Dynamic tool registration** — tools register/unregister themselves at runtime without restarts
- **Heartbeat monitoring** — dead tool servers are automatically removed after 3 health-check failures
- **Embedded chat UI** — zero-dependency browser interface served at `/`
- **System prompts** — swap persona/behaviour with a single environment variable
- **Structured logging** — coloured, levelled logs via `go.uber.org/zap`
- **Single binary** — statically compiled, no runtime dependencies

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Running the Server](#running-the-server)
- [HTTP API](#http-api)
- [Built-in Tools](#built-in-tools)
- [System Prompts](#system-prompts)
- [Remote Tools](#remote-tools)
  - [Static Configuration (tools.yaml)](#static-configuration-toolsyaml)
  - [Dynamic Registration](#dynamic-registration)
  - [Heartbeat Monitor](#heartbeat-monitor)
  - [Multi-Tool Servers](#multi-tool-servers)
- [Remote Tool Protocol](#remote-tool-protocol)
- [Building a Remote Tool (Go)](#building-a-remote-tool-go)
- [Example: Wordcount Tool](#example-wordcount-tool)
- [Logging](#logging)
- [Building a Production Binary](#building-a-production-binary)
- [Internal Design](#internal-design)

---

## Architecture Overview

```
Browser / API client
       │
       ▼
┌──────────────────────────────────────────┐
│               Chatbot Server             │
│  ┌─────────────┐   ┌──────────────────┐  │
│  │  HTTP Mux   │   │  Session Store   │  │
│  └──────┬──────┘   └──────────────────┘  │
│         │                                │
│  ┌──────▼──────┐   ┌──────────────────┐  │
│  │   Handler   │──▶│   LLM Client     │  │
│  │  (chat loop)│   │ (go-openai)      │  │
│  └──────┬──────┘   └──────────────────┘  │
│         │                                │
│  ┌──────▼──────┐   ┌──────────────────┐  │
│  │  Tool       │   │  Heartbeat       │  │
│  │  Registry   │◀──│  Monitor         │  │
│  └──────┬──────┘   └──────────────────┘  │
└─────────┼────────────────────────────────┘
          │  HTTP
  ┌───────┴────────────┐
  │  Remote Tool       │  ← any language
  │  Servers           │
  └────────────────────┘
```

**Request lifecycle:**
1. User sends a message via the UI or `POST /chat`
2. Handler appends the message to the session history
3. Full history (+ system prompt) is sent to the LLM
4. If the LLM responds with tool calls, each tool is executed and the results are appended to history
5. Steps 3–4 repeat until the LLM returns a plain text reply
6. The reply is returned to the caller and stored in session history

---

## Project Structure

```
chatbot/
├── main.go                       # Entry point — wires server, registry, monitor
├── Makefile                      # Dev shortcuts
├── tools.yaml                    # Remote tool discovery config
├── go.mod / go.sum               # Go module definition
│
├── toolserver/
│   └── server.go                 # Helper library for building remote tool binaries
│
├── internal/
│   ├── chat/
│   │   └── session.go            # Thread-safe per-session conversation history
│   ├── handler/
│   │   ├── handler.go            # Chat/Reset HTTP handlers + LLM tool-call loop
│   │   ├── tools_handler.go      # Register/Unregister/List tool HTTP handlers
│   │   └── ui.go                 # Embedded HTML/CSS/JS chat UI
│   ├── llmlog/
│   │   └── transport.go          # HTTP transport: logs LLM wire traffic at DEBUG
│   └── tools/
│       ├── registry.go           # Tool interface + thread-safe Registry
│       ├── remote.go             # RemoteTool — proxies calls to a tool HTTP server
│       ├── loader.go             # Loads remote tools from tools.yaml at startup
│       ├── monitor.go            # Background health-check loop
│       ├── calculator.go         # Built-in: calculate
│       └── datetime.go           # Built-in: get_current_datetime
│
├── examples/
│   └── wordcount/
│       └── main.go               # Reference remote tool implementation
│
├── resources/                    # Ready-to-use system prompt files
│   ├── assistant.txt             # General-purpose assistant
│   ├── code_reviewer.txt         # Expert code reviewer
│   ├── customer_support.txt      # Customer support agent
│   ├── diagnostic_support.txt    # Medical diagnostic report assistant
│   └── socratic_tutor.txt        # Socratic teaching method
│
└── docs/
    ├── DEVELOPMENT.md            # Developer guide
    └── REMOTE_TOOL_SPEC.md       # Full remote tool protocol reference
```

---

## Getting Started

### Prerequisites

- **Go 1.22+**
- An API key from [OpenRouter](https://openrouter.ai) or any OpenAI-compatible provider

### Install & run

```bash
# Clone the repo
git clone <repo-url>
cd chatbot

# Create your environment file
cp .env.example .env
# Edit .env and set LLM_API_KEY=<your key>

# Run
make run
```

Open [http://localhost:8080](http://localhost:8080) in your browser.

---

## Configuration

All configuration is through environment variables. The `Makefile` reads a `.env` file automatically.

| Variable             | Default                         | Required | Description                                              |
|----------------------|---------------------------------|----------|----------------------------------------------------------|
| `LLM_API_KEY`        | —                               | **Yes**  | API key for the LLM provider                             |
| `LLM_BASE_URL`       | `https://openrouter.ai/api/v1`  | No       | Base URL of any OpenAI-compatible API                    |
| `MODEL`              | `anthropic/claude-sonnet-4-6`   | No       | Model identifier string                                  |
| `PORT`               | `8080`                          | No       | HTTP port the chatbot listens on                         |
| `LOG_LEVEL`          | `info`                          | No       | Log verbosity: `debug`, `info`, `warn`, `error`          |
| `SYSTEM_PROMPT_FILE` | *(none)*                        | No       | Path to a `.txt` file used as the LLM system prompt      |
| `TOOLS_CONFIG`       | `tools.yaml`                    | No       | Path to the remote tools YAML config                     |

> **Note:** The model **must support tool/function calling** for the built-in and remote tools to work. The server will start regardless, but tool calls will silently fail or produce empty replies on models that don't support the feature.

### Recommended models

| Model | Notes |
|---|---|
| `anthropic/claude-sonnet-4-6` | Best tool-calling support (default) |
| `openai/gpt-4o` | Excellent tool support |
| `google/gemini-2.0-flash` | Fast, good tool support |
| `mistralai/mistral-small-3.1-24b-instruct` | Lightweight option |

---

## Running the Server

```bash
make run                                               # default settings
make run LOG_LEVEL=debug                               # verbose LLM wire traffic
make run SYSTEM_PROMPT_FILE=resources/assistant.txt    # with a system prompt
make run PORT=9090                                     # custom port
make run MODEL=openai/gpt-4o                           # different model
```

---

## HTTP API

### Chat endpoints

| Method   | Path      | Body                                            | Response                       |
|----------|-----------|-------------------------------------------------|--------------------------------|
| `GET`    | `/`       | —                                               | Chat UI (HTML)                 |
| `POST`   | `/chat`   | `{"session_id":"…","message":"…"}`              | `{"reply":"…"}` or error       |
| `POST`   | `/reset`  | `{"session_id":"…"}`                            | `204 No Content`               |

**Example — send a message:**
```bash
curl -X POST http://localhost:8080/chat \
  -H 'Content-Type: application/json' \
  -d '{"session_id":"my-session","message":"What is 12 * 37?"}'
# {"reply":"12 × 37 = 444"}
```

The `session_id` is any string you choose. The browser UI auto-generates a UUID per tab. Omitting it defaults to the session named `"default"`.

### Tool management endpoints

| Method    | Path                  | Body                    | Response                            |
|-----------|-----------------------|-------------------------|-------------------------------------|
| `POST`    | `/tools/register`     | `{"url":"http://…"}`    | `{"tools":[{"name":…,"description":…}]}` |
| `DELETE`  | `/tools/unregister`   | `{"url":"http://…"}`    | `204 No Content`                    |
| `GET`     | `/tools`              | —                       | `{"tools":[…]}`                     |

---

## Built-in Tools

Two tools are compiled into the binary and always available:

### `get_current_datetime`

Returns the current date and time. Accepts an optional IANA timezone name.

```
What time is it in Tokyo?
→ 2026-04-02 15:36:00 JST (timezone: Asia/Tokyo)
```

### `calculate`

Evaluates mathematical expressions. Supports `+`, `-`, `*`, `/`, `^` (exponentiation), parentheses, and the functions `sqrt`, `abs`, `floor`, `ceil`, `round`.

```
What is sqrt(144) + 2^8?
→ 12 + 256 = 268
```

The calculator is a hand-written recursive descent parser — no `eval`, no external dependencies.

---

## System Prompts

Point `SYSTEM_PROMPT_FILE` at any `.txt` file to give the bot a custom persona. The file content is injected as the first `system` message in every conversation.

Five ready-to-use prompts are included in `resources/`:

| File | Persona |
|---|---|
| `assistant.txt` | Friendly general-purpose assistant |
| `code_reviewer.txt` | Expert code reviewer (correctness, security, performance) |
| `customer_support.txt` | Polite customer support agent |
| `diagnostic_support.txt` | Medical diagnostic report interpreter |
| `socratic_tutor.txt` | Socratic tutor — guides students with questions, not answers |

```bash
make run SYSTEM_PROMPT_FILE=resources/code_reviewer.txt
```

---

## Remote Tools

Remote tools are standalone HTTP servers that the chatbot discovers and calls at runtime. They can be written in **any language**.

### Static Configuration (tools.yaml)

List tool server URLs in `tools.yaml`. The chatbot fetches metadata from each server at startup and registers the tools automatically.

```yaml
tools:
  - url: http://localhost:9001   # wordcount (Go example)
  - url: http://localhost:9002   # a Python tool
  - url: http://10.0.0.5:9003   # tool on another machine
```

Unreachable servers are **skipped with a warning** — they will not prevent the chatbot from starting.

To use a non-default config path:
```bash
make run TOOLS_CONFIG=/etc/chatbot/tools.yaml
```

### Dynamic Registration

Tools can register and unregister themselves at runtime **without restarting** the chatbot.

```
Tool starts  →  POST /tools/register   {"url": "http://localhost:9001"}
                chatbot calls /describe, registers all tools, starts heartbeat monitoring

Tool stops   →  DELETE /tools/unregister  {"url": "http://localhost:9001"}
                chatbot removes all tools at that URL immediately

Tool killed  →  chatbot polls GET /health every 15 seconds
                after 3 consecutive failures (~45 s) → auto-unregistered
```

Using the `toolserver.ServeWithConfig` helper in Go handles this lifecycle automatically (see [Building a Remote Tool](#building-a-remote-tool-go)).

### Heartbeat Monitor

The monitor runs as a background goroutine. It pings each unique tool server URL on a ticker.

| Parameter             | Default | Description                                             |
|-----------------------|---------|---------------------------------------------------------|
| Check interval        | 15 s    | How often `/health` is polled per unique URL            |
| Max consecutive fails | 3       | Failures before the tool is auto-unregistered           |
| Health check timeout  | 5 s     | Per-request timeout                                     |

When a server hosts multiple tools, **all tools at that URL are removed together** on failure, and **re-registration** of any one of them restores health tracking for all.

### Multi-Tool Servers

A single HTTP server can expose multiple tools. The protocol difference:

- `GET /describe` returns a **JSON array** (instead of a single object)
- `POST /execute` requires a `"name"` field to route to the correct tool

The chatbot auto-detects single vs. multi based on the `/describe` response shape.

---

## Remote Tool Protocol

Every remote tool server must implement three endpoints:

### `GET /describe`

Returns tool metadata. Called once at registration.

```json
{
  "name": "word_count",
  "description": "Counts the number of words, sentences, and characters in a given text.",
  "parameters": {
    "type": "object",
    "properties": {
      "text": { "type": "string", "description": "The text to analyse." }
    },
    "required": ["text"]
  }
}
```

- `name` — must be unique across all registered tools; use `snake_case`
- `description` — shown to the LLM to decide when to call the tool; write it clearly
- `parameters` — standard [JSON Schema](https://json-schema.org/) object

### `POST /execute`

Called by the chatbot every time the LLM invokes the tool.

**Request:**
```json
{ "args": { "text": "The quick brown fox jumps over the lazy dog." } }
```

**Success response (HTTP 200):**
```json
{ "result": "words: 9, sentences: 1, characters: 44" }
```

**Error response (HTTP 200 — always 200):**
```json
{ "error": "text is required" }
```

> Always return HTTP `200`. The chatbot passes `"error"` strings back to the LLM as context so it can respond helpfully. A non-200 status is treated as a transport failure.

### `GET /health`

Health check. Return `200 OK` with any body (or none).

---

## Building a Remote Tool (Go)

The `toolserver` package in this repo provides helpers that handle the HTTP server, signal handling, and auto-registration lifecycle.

```go
package main

import (
    "context"
    "encoding/json"
    "flag"
    "fmt"
    "log"

    "chatbot/toolserver"
)

type MyTool struct{}

func (MyTool) Name() string        { return "my_tool" }
func (MyTool) Description() string { return "Does something useful with the provided input." }
func (MyTool) Parameters() any {
    return map[string]any{
        "type": "object",
        "properties": map[string]any{
            "input": map[string]any{
                "type":        "string",
                "description": "The input to process.",
            },
        },
        "required": []string{"input"},
    }
}

func (MyTool) Execute(_ context.Context, args json.RawMessage) (string, error) {
    var p struct {
        Input string `json:"input"`
    }
    if err := json.Unmarshal(args, &p); err != nil {
        return "", err
    }
    return fmt.Sprintf("processed: %s", p.Input), nil
}

func main() {
    addr    := flag.String("addr",    ":9001",                 "listen address")
    self    := flag.String("self",    "http://localhost:9001", "this tool's public URL")
    chatbot := flag.String("chatbot", "http://localhost:8080", "chatbot base URL")
    flag.Parse()

    log.Fatal(toolserver.ServeWithConfig(toolserver.Config{
        Addr:       *addr,
        SelfURL:    *self,
        ChatbotURL: *chatbot,
    }, MyTool{}))
}
```

**`toolserver` API summary:**

| Function | Description |
|---|---|
| `Serve(addr, tool)` | Single-tool server, no auto-registration |
| `ServeWithConfig(cfg, tool)` | Single-tool server with optional auto-registration |
| `ServeMulti(addr, tools...)` | Multi-tool server, no auto-registration |
| `ServeMultiWithConfig(cfg, tools...)` | Multi-tool server with optional auto-registration |

For languages other than Go, implement the three endpoints directly. See `docs/REMOTE_TOOL_SPEC.md` for Python, Node.js, and JSON Schema examples.

---

## Example: Wordcount Tool

A complete reference implementation lives in `examples/wordcount/`. It counts words, sentences, and characters in a text string.

**Run with auto-registration (no `tools.yaml` changes needed):**

```bash
# Terminal 1 — start the chatbot
make run

# Terminal 2 — start the wordcount tool (auto-registers on startup)
make wordcount
# tool server word_count listening on :9001
# registered with chatbot at http://localhost:8080
```

Stop with `Ctrl+C` — it auto-unregisters on graceful shutdown. Kill it with `kill -9` and the heartbeat monitor removes it within ~45 seconds.

Then ask the bot: *"How many words are in 'The quick brown fox jumps over the lazy dog'?"*

**Run without auto-registration (static config):**

```yaml
# tools.yaml
tools:
  - url: http://localhost:9001
```

```bash
go run ./examples/wordcount --addr :9001
make run
```

---

## Logging

Logs are written to stdout in human-readable format with coloured level labels (powered by `go.uber.org/zap` in development mode).

| Level   | What is logged                                                            |
|---------|---------------------------------------------------------------------------|
| `error` | LLM call failures, server errors                                          |
| `warn`  | Tool servers skipped at startup, health-check failures, tool errors       |
| `info`  | Server start, registered tools, each chat turn, session resets, recovery  |
| `debug` | Full LLM HTTP request/response (URL, headers with auth redacted, body), per-tool execution details |

The `Authorization` header is always masked as `Bearer ****` in debug logs.

```bash
make run LOG_LEVEL=debug   # see every LLM API call in full
```

---

## Building a Production Binary

```bash
make build        # outputs ./chatbot
```

Compiled with `CGO_ENABLED=0`, `-trimpath`, and `-ldflags="-s -w"`. The resulting binary is fully static (~7 MB) with no libc dependency — suitable for scratch or distroless containers.

```bash
make clean        # removes ./chatbot
```

---

## Internal Design

### `internal/chat` — Session Store

`Session` is a mutex-protected slice of `openai.ChatCompletionMessage`. `SessionStore` maps arbitrary string IDs to sessions, creating new ones on first access. Sessions are never expired — this is an in-memory store suitable for development and single-instance deployments.

### `internal/handler` — HTTP Handlers

`Handler` owns the LLM client and the `runLLM` loop:

1. Build the message list (system prompt + session history)
2. Send to the LLM with the current tool definitions attached
3. If `finish_reason == "tool_calls"`: execute each tool, append results, go to step 1
4. Otherwise return the text content

Tool errors are never fatal — the error string is fed back to the LLM as the tool result so the model can handle it gracefully.

`ToolsHandler` provides the `/tools/*` management endpoints and coordinates between the registry and the monitor.

### `internal/tools` — Registry & Tool Interface

```go
type Tool interface {
    Name() string
    Description() string
    Parameters() any   // JSON Schema object
    Execute(ctx context.Context, args json.RawMessage) (string, error)
}
```

`Registry` is a `sync.RWMutex`-protected map. `OpenAITools()` converts the registry to the `[]openai.Tool` format expected by the go-openai SDK on every LLM request, so the tool list is always current.

`RemoteTool` fetches metadata once at construction (from `/describe`) and proxies `Execute` calls to `/execute` at runtime. For multi-tool servers, it includes `"name"` in the execute payload to route correctly.

### `internal/llmlog` — Debug Transport

A thin `http.RoundTripper` wrapper. When the log level is DEBUG, it reads and restores request/response bodies to log them, then masks the `Authorization` header. At INFO and above it is a no-op passthrough.

### `toolserver` — Remote Tool Helper

Handles the full lifecycle of a remote tool binary: HTTP server setup, SIGTERM/SIGINT handling, graceful shutdown with a 5-second timeout, and optional auto-registration/unregistration with the chatbot. Supports both single-tool and multi-tool modes transparently.

---

## Further Reading

- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — step-by-step guide for adding built-in and remote tools
- [`docs/REMOTE_TOOL_SPEC.md`](docs/REMOTE_TOOL_SPEC.md) — full remote tool HTTP protocol with Python, Node.js, and Go examples, plus a JSON Schema reference and pre-ship checklist
