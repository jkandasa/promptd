# Developer Guide

## Overview

A multi-provider HTTP chatbot written in Go. Supports any OpenAI-compatible LLM endpoint
(Claude, Gemini, OpenRouter, etc.), conversation history per session, system prompts, and
an extensible tool system — including remote tools running as independent binaries.

---

## Project Structure

```
chatbot/
├── main.go                          # Server entry point
├── Makefile                         # Dev shortcuts
├── tools.yaml                       # Remote tool server discovery config
├── .env                             # Environment variables (not committed)
│
├── toolserver/                      # Helper package for building remote tool binaries
│   └── server.go
│
├── internal/
│   ├── chat/
│   │   └── session.go               # Per-session conversation history (thread-safe)
│   ├── handler/
│   │   ├── handler.go               # HTTP handlers + LLM tool-call loop
│   │   └── ui.go                    # Embedded chat UI (HTML/CSS/JS)
│   ├── llmlog/
│   │   └── transport.go             # HTTP transport that logs LLM wire traffic at DEBUG
│   └── tools/
│       ├── registry.go              # Tool interface + Registry
│       ├── remote.go                # RemoteTool — calls a tool HTTP server
│       ├── loader.go                # Loads remote tools from tools.yaml
│       ├── datetime.go              # Built-in: get_current_datetime
│       └── calculator.go            # Built-in: calculate
│
├── examples/
│   └── wordcount/
│       └── main.go                  # Example remote tool binary
│
├── resources/                       # Sample system prompts
│   ├── assistant.txt
│   ├── code_reviewer.txt
│   ├── customer_support.txt
│   ├── diagnostic_support.txt
│   └── socratic_tutor.txt
│
└── docs/
    └── DEVELOPMENT.md               # This file
```

---

## Prerequisites

- Go 1.22+
- An [OpenRouter](https://openrouter.ai) API key (or any OpenAI-compatible provider)

---

## Configuration

All configuration is via environment variables. Copy `.env.example` to `.env`:

| Variable            | Default                          | Description                                               |
|---------------------|----------------------------------|-----------------------------------------------------------|
| `OPENROUTER_API_KEY` | *(required)*                    | API key for OpenRouter (or other provider)                |
| `MODEL`             | `anthropic/claude-sonnet-4-6`   | LLM model identifier                                      |
| `PORT`              | `8080`                          | HTTP port the chatbot listens on                          |
| `LOG_LEVEL`         | `info`                          | Log level: `debug`, `info`, `warn`, `error`               |
| `SYSTEM_PROMPT_FILE`| *(none)*                        | Path to a `.txt` file used as the system prompt           |
| `TOOLS_CONFIG`      | `tools.yaml`                    | Path to the remote tools config file                      |

---

## Running

```bash
# Copy and fill in your API key
cp .env.example .env

make run                                              # default settings
make run LOG_LEVEL=debug                              # verbose LLM wire logging
make run SYSTEM_PROMPT_FILE=resources/assistant.txt  # with a system prompt
make run PORT=9090                                    # custom port
```

### Choosing a model

Any OpenRouter model string works. Models **must support tool/function calling**
for the built-in and remote tools to work.

Recommended models:
```
anthropic/claude-sonnet-4-6          # best tool support
openai/gpt-4o
google/gemini-2.0-flash
mistralai/mistral-small-3.1-24b-instruct
```

---

## HTTP API

| Method | Path      | Body                                        | Description              |
|--------|-----------|---------------------------------------------|--------------------------|
| `GET`  | `/`       | —                                           | Chat UI                  |
| `POST` | `/chat`   | `{"session_id":"…","message":"…"}`          | Send a message           |
| `POST` | `/reset`  | `{"session_id":"…"}`                        | Clear conversation history |

### Chat request / response

```json
// POST /chat
{ "session_id": "abc-123", "message": "What time is it?" }

// 200 OK
{ "reply": "The current time is 2026-04-01 17:30:00 IST." }

// 500 on LLM error
{ "error": "model returned an empty response …" }
```

`session_id` is any string. The browser UI generates a UUID per tab automatically.

---

## Adding a Built-in Tool

Built-in tools live in `internal/tools/` and are compiled into the main binary.

**1. Create the file** `internal/tools/mytool.go`:

```go
package tools

import (
    "context"
    "encoding/json"
    "fmt"
)

type MyTool struct{}

func (MyTool) Name() string { return "my_tool" }

func (MyTool) Description() string {
    return "One-line description the LLM uses to decide when to call this tool."
}

func (MyTool) Parameters() any {
    return map[string]any{
        "type": "object",
        "properties": map[string]any{
            "input": map[string]any{
                "type":        "string",
                "description": "The input value.",
            },
        },
        "required": []string{"input"},
    }
}

func (MyTool) Execute(_ context.Context, args json.RawMessage) (string, error) {
    var params struct {
        Input string `json:"input"`
    }
    if err := json.Unmarshal(args, &params); err != nil {
        return "", fmt.Errorf("invalid arguments: %w", err)
    }
    return "result: " + params.Input, nil
}
```

**2. Register it** in `main.go` inside `buildRegistry`:

```go
registry.Register(tools.MyTool{})
```

That's it. The tool-call loop in the handler picks it up automatically.

---

## Remote Tool Protocol

A remote tool is a standalone HTTP server (any language) that implements two endpoints:

### `GET /describe`

Returns tool metadata. Called once at chatbot startup.

```json
{
  "name": "my_tool",
  "description": "What this tool does.",
  "parameters": {
    "type": "object",
    "properties": {
      "input": { "type": "string", "description": "The input." }
    },
    "required": ["input"]
  }
}
```

### `POST /execute`

Executes the tool. Called at runtime for every tool invocation.

Request:
```json
{ "args": { "input": "hello" } }
```

Success response (HTTP 200):
```json
{ "result": "processed: hello" }
```

Error response (HTTP 200 — always 200 so the LLM receives the error as context):
```json
{ "error": "input is required" }
```

---

## Building a Remote Tool Binary (Go)

Use the `toolserver` package from this module:

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
func (MyTool) Description() string { return "Does something useful." }
func (MyTool) Parameters() any {
    return map[string]any{
        "type": "object",
        "properties": map[string]any{
            "input": map[string]any{"type": "string"},
        },
        "required": []string{"input"},
    }
}

func (MyTool) Execute(_ context.Context, args json.RawMessage) (string, error) {
    var p struct{ Input string `json:"input"` }
    if err := json.Unmarshal(args, &p); err != nil {
        return "", err
    }
    return fmt.Sprintf("you said: %s", p.Input), nil
}

func main() {
    addr := flag.String("addr", ":9001", "listen address")
    flag.Parse()
    log.Fatal(toolserver.Serve(*addr, MyTool{}))
}
```

See `examples/wordcount/main.go` for a complete working example.

---

## Building a Remote Tool Binary (any language)

Implement the two endpoints described in the protocol section above using any HTTP framework.

Example in Python (Flask):

```python
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.get("/describe")
def describe():
    return jsonify({
        "name": "my_python_tool",
        "description": "A tool written in Python.",
        "parameters": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Input text."}
            },
            "required": ["text"]
        }
    })

@app.post("/execute")
def execute():
    args = request.json.get("args", {})
    text = args.get("text", "")
    if not text:
        return jsonify({"error": "text is required"})
    return jsonify({"result": f"processed: {text.upper()}"})

if __name__ == "__main__":
    app.run(port=9002)
```

---

## Registering Remote Tools

Edit `tools.yaml` to point at running tool servers:

```yaml
tools:
  - url: http://localhost:9001   # wordcount (Go example)
  - url: http://localhost:9002   # my Python tool
  - url: http://10.0.0.5:9003   # tool on another machine
```

The chatbot calls `/describe` on each URL at startup. Unreachable servers are
**skipped with a warning** — they will not prevent the chatbot from starting.
The tool simply won't be available until the server comes online and the chatbot restarts.

To use a different config file:
```bash
make run TOOLS_CONFIG=/etc/chatbot/tools.yaml
```

---

## Dynamic Tool Registration

Tools can register and unregister themselves at runtime without restarting the chatbot.

### How it works

```
Tool starts  →  POST /tools/register   {"url": "http://localhost:9001"}
                chatbot fetches /describe, adds to registry, starts heartbeat monitoring

Tool stops   →  DELETE /tools/unregister  {"url": "http://localhost:9001"}
                chatbot removes from registry immediately

Tool killed  →  chatbot polls GET /health every 15s
                after 3 consecutive failures (~45s) → auto-unregistered
```

### Chatbot endpoints

| Method     | Path                  | Body                        | Description                  |
|------------|-----------------------|-----------------------------|------------------------------|
| `POST`     | `/tools/register`     | `{"url":"http://…"}`        | Register a remote tool       |
| `DELETE`   | `/tools/unregister`   | `{"url":"http://…"}`        | Unregister a remote tool     |
| `GET`      | `/tools`              | —                           | List all registered tools    |

### Tool binary endpoints (required for dynamic registration)

| Method | Path        | Description                                          |
|--------|-------------|------------------------------------------------------|
| `GET`  | `/describe` | Returns tool metadata (name, description, parameters)|
| `POST` | `/execute`  | Executes the tool                                    |
| `GET`  | `/health`   | Health check — must return HTTP 200                  |

### Using ServeWithConfig for auto-registration

```go
log.Fatal(toolserver.ServeWithConfig(toolserver.Config{
    Addr:       ":9001",
    SelfURL:    "http://localhost:9001",  // URL chatbot uses to reach this tool
    ChatbotURL: "http://localhost:8080",  // chatbot base URL
}, MyTool{}))
```

On startup: registers itself with the chatbot.
On SIGTERM/SIGINT: unregisters itself, then shuts down cleanly.
If killed (SIGKILL): chatbot heartbeat monitor auto-unregisters after ~45 seconds.

---

## Running the Example Remote Tool

**With auto-registration** (no `tools.yaml` changes needed):

```bash
# Terminal 1 — start chatbot
make run

# Terminal 2 — start wordcount (auto-registers on startup)
make wordcount
# → "registered with chatbot at http://localhost:8080"

# Stop wordcount with Ctrl+C (auto-unregisters on shutdown)
# Or kill -9 it and the chatbot will detect it within ~45s
```

**Without auto-registration** (static config):

```bash
# Add to tools.yaml:
tools:
  - url: http://localhost:9001

# Then run both:
go run ./examples/wordcount --addr :9001
make run
```

Now ask the chatbot: *"How many words are in 'The quick brown fox jumps over the lazy dog'?"*

---

## Heartbeat Monitor

The monitor runs as a background goroutine in the chatbot.

| Parameter           | Default | Description                                      |
|---------------------|---------|--------------------------------------------------|
| Check interval      | 15s     | How often `/health` is polled per tool           |
| Max failures        | 3       | Consecutive failures before auto-unregistering   |
| Health check timeout| 5s      | Per-request timeout for `/health` calls          |

Only remote tools are monitored. Built-in tools (compiled in) are never health-checked.

---

## Logging

Logs are printed to stdout in human-readable format with colored level labels.

| Level   | What is logged                                                          |
|---------|-------------------------------------------------------------------------|
| `error` | LLM call failures                                                       |
| `warn`  | Skipped remote tools (unreachable at startup)                           |
| `info`  | Server start, registered tools, each chat turn, session resets          |
| `debug` | Full LLM HTTP request/response (URL, headers, body), tool executions    |

The `Authorization` header is always masked as `Bearer ****` in debug logs.

---

## Building a Production Binary

```bash
make build        # outputs ./chatbot (~7MB, fully static, no libc dependency)
```

Flags used: `-trimpath -ldflags="-s -w"` with `CGO_ENABLED=0`.
