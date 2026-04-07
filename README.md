# Chatbot

A lightweight, extensible LLM chatbot server written in Go. Connects to any OpenAI-compatible API endpoint, maintains per-session conversation history, supports configurable system prompts, and ships with MCP support.

---

## Features

- **Multi-provider** — works with any OpenAI-compatible API (OpenRouter, OpenAI, Gemini, Mistral, …)
- **Session management** — each browser tab gets its own isolated conversation history
- **Tool calling** — native LLM function-calling loop with built-in and MCP tools
- **MCP support** — connect to external MCP servers with optional auth
- **Health monitoring** — dead MCP servers are automatically removed after failures, and re-registered when they recover
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

llm:
  api_key: "your-api-key"  # Required
  base_url: "https://openrouter.ai/api/v1"
  model: "anthropic/claude-sonnet-4-6"

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
| `llm.api_key` | Yes | - | API key for LLM provider |
| `llm.base_url` | No | OpenRouter | OpenAI-compatible endpoint |
| `llm.model` | No | claude-sonnet-4-6 | Model identifier |
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
| `POST` | `/chat` | `{"session_id":"...","message":"..."}` | Send message |
| `POST` | `/reset` | `{"session_id":"..."}` | Reset session |
| `GET` | `/mcp` | - | List MCP servers and tools |

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

**Configuration:**
```yaml
mcp:
  health_max_failures: 3   # failures before unregistering (default: 3)
  health_interval: 15s    # health check interval (default: 15s)
```

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
