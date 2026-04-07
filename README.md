# Chatbot

A lightweight, extensible LLM chatbot server written in Go. Connects to any OpenAI-compatible API endpoint, maintains per-session conversation history, supports configurable system prompts, and ships with MCP support.

---

## Features

- **Multi-provider** — works with any OpenAI-compatible API (OpenRouter, OpenAI, Gemini, Mistral, …)
- **Multi-model** — configure multiple models with random or round-robin selection
- **Session management** — each browser tab gets its own isolated conversation history
- **Tool calling** — native LLM function-calling loop with built-in and MCP tools
- **MCP support** — connect to external MCP servers with optional auth
- **Health monitoring** — dead MCP servers are automatically removed after failures, and re-registered when they recover
- **File uploads** — attach files to conversations, download generated files
- **Embedded chat UI** — zero-dependency browser interface served at `/`
- **System prompts** — load from external file
- **Single binary** — statically compiled, no runtime dependencies

---

## Usage

```bash
# Build the UI first (requires Node.js/pnpm)
make ui

# Run the server
./chatbot -config ./config.yaml
```

---

## Configuration

All configuration via `config.yaml`:

```yaml
server:
  port: "8080"

upload:
  dir: "./uploads"  # Optional: directory for uploaded files

llm:
  api_key: "your-api-key"  # Required
  base_url: "https://openrouter.ai/api/v1"
  selection_method: "round_robin"  # random or round_robin
  models:
    - "anthropic/claude-sonnet-4-6"
    - "openai/gpt-4o"

log:
  level: "info"  # debug, info, warn, error

mcp:
  health_max_failures: 3   # failures before unregistering (default: 3)
  health_interval: 15s    # health check interval (default: 15s)
  servers:
    - name: "my-server"
      url: "http://localhost:8081/mcp"
      auth:
        token: "optional-token"
      headers:
        X-Custom: "value"
      disabled: false  # default: false

tools:
  system_prompt_file: "/path/to/prompt.txt"  # Optional
```

### Options

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `server.port` | No | 8080 | HTTP port |
| `upload.dir` | No | ./uploads | Directory for uploaded files |
| `llm.api_key` | Yes | - | API key for LLM provider |
| `llm.base_url` | No | OpenRouter | OpenAI-compatible endpoint |
| `llm.selection_method` | No | round_robin | Model selection: random or round_robin |
| `llm.models` | Yes | - | List of model identifiers |
| `log.level` | No | info | Log verbosity |
| `mcp.health_max_failures` | No | 3 | Consecutive failures before unregistering |
| `mcp.health_interval` | No | 15s | Health check interval |
| `mcp.servers` | No | [] | List of MCP servers |
| `mcp.servers[].name` | Yes | - | Server name |
| `mcp.servers[].url` | Yes | - | MCP server URL |
| `mcp.servers[].auth` | No | {} | Auth credentials (token) |
| `mcp.servers[].headers` | No | {} | Custom HTTP headers |
| `mcp.servers[].disabled` | No | false | Skip this server |
| `tools.system_prompt_file` | No | - | Path to .txt file |

---

## API Endpoints

| Method | Path | Body | Description |
|--------|------|------|-------------|
| `GET` | `/` | - | Chat UI |
| `POST` | `/chat` | `{"session_id":"...","message":"...","model":"...","files":[...]}` | Send message |
| `POST` | `/reset` | `{"session_id":"..."}` | Reset session |
| `GET` | `/mcp` | - | List MCP servers and tools |
| `GET` | `/models` | - | List available models |
| `POST` | `/upload` | multipart/form-data | Upload file |
| `GET` | `/files/{id}` | - | Download uploaded file |
| `DELETE` | `/files/{id}` | - | Delete uploaded file |

---

## Built-in Tools

### `get_current_datetime`

Returns current date and time. Optional timezone parameter.

---

## MCP Health Monitoring

The MCP manager runs background health checks using the `ping` method (with fallback to `tools/list`). 

**Behavior:**
- On first ping failure: increments failure counter but keeps server registered
- After 3 consecutive failures (configurable via `health_max_failures`): unregisters the server
- Continues pinging removed servers on each health check interval
- When a removed server recovers (ping succeeds): automatically re-registers it

---

## File Uploads

Users can attach files to messages. The backend stores files in the configured directory and serves them via `/files/{id}`.

- Max upload size: 10MB
- Files can be downloaded from chat bubbles
- Images are previewed as thumbnails in the chat

---

## Multi-Model Support

Configure multiple models in `config.yaml`. The server will:

- **random**: Randomly select a model for each request
- **round_robin**: Cycle through models sequentially

Users can override the selection by choosing a specific model in the UI dropdown.

---

## Building

```bash
# Build both UI and binary
make build

# Or build just the UI (requires Node.js/pnpm)
make ui

# Then build the Go binary
go build -o chatbot .
```

**Note:** The `internal/ui/dist/` directory is gitignored. After cloning, run `make ui` to generate the frontend assets before building.

---

## Development

```bash
# Install dependencies
cd web && pnpm install

# Run frontend dev server
cd web && pnpm dev

# Run backend
go run . -config ./config.yaml
```
