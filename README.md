# Chatbot

A lightweight, extensible LLM chatbot server written in Go with a React frontend. Connects to any OpenAI-compatible API, persists conversation history to disk, and ships with MCP tool support.

---

## Features

- **Multi-provider** — works with any OpenAI-compatible API (OpenRouter, OpenAI, Gemini, Mistral, …)
- **Multi-model** — configure multiple models with random or round-robin selection; user can override per-conversation
- **Persistent conversation history** — all conversations stored as YAML files; survives server restarts
- **Conversation sidebar** — browse, continue, rename, pin, and delete past conversations
- **Session management** — each browser tab gets its own isolated conversation
- **Tool calling** — native LLM function-calling loop with built-in and MCP tools
- **MCP support** — connect to external MCP servers with optional auth
- **Health monitoring** — dead MCP servers are automatically removed and re-registered on recovery
- **File uploads** — attach files to messages; images previewed inline
- **Embedded chat UI** — zero-dependency browser interface served at `/`
- **System prompts** — load one or many prompts from external files and switch in the UI
- **Single binary** — statically compiled, no runtime dependencies

---

## Usage

```bash
# Build the UI first (requires Node.js / pnpm)
make ui

# Run the server
./chatbot -config ./config.yaml
```

---

## Configuration

Copy `config_template.yaml` to `config.yaml` and fill in the required fields.

```yaml
data:
  dir: "./data"           # Root for all data (default: ./data)
                          # Conversations → <dir>/conversations/
                          # Uploads       → <dir>/uploads/

server:
  port: "8080"

llm:
  api_key: "your-api-key"                    # Required
  base_url: "https://openrouter.ai/api/v1"   # Any OpenAI-compatible endpoint
  selection_method: "round_robin"            # random | round_robin
  models:
    - "anthropic/claude-sonnet-4-5"
    - id: "openai/gpt-4o"
      name: "GPT-4o"                         # Optional display name

log:
  level: "info"    # debug | info | warn | error

mcp:
  health_max_failures: 3    # Failures before unregistering (default: 3)
  health_interval: 15s      # Health check interval (default: 15s)
  servers:
    - name: "my-server"
      url: "http://localhost:8081/mcp"
      auth:
        token: "optional-token"
      headers:
        X-Custom: "value"
      disabled: false

tools:
  system_prompts:
    - name: "Code Reviewer"
      file: "/path/to/code-reviewer.txt"
    - name: "Customer Support"
      file: "/path/to/customer-support.txt"

ui:
  app_name: "My Assistant"
  app_icon: "🤖"
  welcome_title: "How can I help you today?"
  ai_disclaimer: "AI can make mistakes. Verify important info."
  prompt_suggestions:
    - "Explain how this works"
    - "Help me write code"
```

### Configuration reference

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `data.dir` | No | `./data` | Root directory; `conversations/` and `uploads/` are always fixed sub-dirs |
| `server.port` | No | `8080` | HTTP listen port |
| `llm.api_key` | Yes | — | API key for LLM provider |
| `llm.base_url` | No | OpenRouter | OpenAI-compatible endpoint |
| `llm.selection_method` | No | `round_robin` | `random` or `round_robin` |
| `llm.models` | Yes | — | Model IDs (string or `{id, name}` object) |
| `log.level` | No | `info` | Log verbosity |
| `mcp.health_max_failures` | No | `3` | Consecutive failures before unregistering |
| `mcp.health_interval` | No | `15s` | Health check interval |
| `mcp.servers[].name` | Yes | — | Server display name |
| `mcp.servers[].url` | Yes | — | MCP server URL |
| `mcp.servers[].auth.token` | No | — | Bearer token |
| `mcp.servers[].headers` | No | `{}` | Extra HTTP headers |
| `mcp.servers[].disabled` | No | `false` | Skip this server |
| `tools.system_prompts` | Yes | — | Selectable system prompts as `{name, file}`; the first one is selected by default |
| `ui.app_name` | No | `Chatbot` | App name shown in the header and browser title |
| `ui.app_icon` | No | built-in robot | App icon shown in the header; supports emoji/text or image URL/path |
| `ui.welcome_title` | No | — | Welcome screen heading |
| `ui.ai_disclaimer` | No | built-in | Disclaimer text under heading |
| `ui.prompt_suggestions` | No | built-in | Quick-send prompt chips |

---

## API Endpoints

### Chat

| Method | Path | Body / Params | Description |
|--------|------|---------------|-------------|
| `GET` | `/` | — | Serve chat UI |
| `POST` | `/chat` | `{session_id, message, model?, files?}` | Send a message; returns reply + message IDs |
| `POST` | `/reset` | `{session_id}` | Clear session history server-side |
| `GET` | `/ui-config` | — | UI configuration (title, suggestions, …) |
| `GET` | `/models` | — | List available models and selection method |

### Conversations

| Method | Path | Body | Description |
|--------|------|------|-------------|
| `GET` | `/conversations` | — | List all conversations (metadata only, newest first) |
| `GET` | `/conversations/{id}` | — | Get full conversation including messages |
| `DELETE` | `/conversations/{id}` | — | Delete a conversation |
| `PATCH` | `/conversations/{id}/title` | `{title}` | Rename a conversation |
| `PATCH` | `/conversations/{id}/pin` | — | Toggle pin state; returns `{pinned: bool}` |

### Messages

| Method | Path | Description |
|--------|------|-------------|
| `DELETE` | `/conversations/{id}/messages/{msgId}` | Delete a single message |
| `DELETE` | `/conversations/{id}/messages/{msgId}/after` | Delete a message and all subsequent messages (used on edit) |

### Files

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/upload` | Upload a file (multipart/form-data, max 10 MB) |
| `GET` | `/files/{id}` | Download an uploaded file |
| `DELETE` | `/files/{id}` | Delete an uploaded file |

### MCP

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/mcp` | List registered MCP servers and their tools |

---

## Chat response

`POST /chat` returns:

```json
{
  "reply": "...",
  "model": "openai/gpt-4o",
  "time_taken_ms": 1234,
  "llm_calls": 2,
  "tool_calls": 1,
  "user_msg_id": "<uuid>",
  "assistant_msg_id": "<uuid>"
}
```

`user_msg_id` and `assistant_msg_id` are the storage IDs of the persisted messages, used by the UI for per-message delete and edit operations.

---

## Conversation storage

Each conversation is a single YAML file at `<data.dir>/conversations/<id>.yaml`.

- Only `user` and `assistant` messages are persisted; tool/intermediate messages are kept in memory for LLM context only.
- The top-level `model` field records the user's explicit model selection (empty = auto). Per-message `model` records the actual model used for each assistant reply.
- `pinned` conversations sort to the top of the sidebar.
- Auto-title is generated from the first user message (truncated to 60 runes).

---

## Built-in tools

### `get_current_datetime`

Returns the current date and time. Accepts an optional IANA timezone parameter (e.g. `"America/New_York"`).

---

## MCP health monitoring

The MCP manager runs background health checks using the `ping` method (falling back to `tools/list`).

- First failure: increments counter, keeps server registered
- After `health_max_failures` consecutive failures: unregisters the server
- Continues pinging unregistered servers
- On recovery: automatically re-registers

---

## File uploads

- Max size: 10 MB per file, up to 10 files per message
- Images are previewed inline as thumbnails with click-to-expand
- Non-image files are shown as download links
- Files persist independently of conversations under `<data.dir>/uploads/`

---

## Multi-model support

Configure multiple models in `config.yaml`. The `selection_method` controls automatic selection:

- **`round_robin`** — cycles through models sequentially
- **`random`** — picks a model at random each request

The user can override the active model via the UI dropdown. The chosen model is persisted per-conversation and restored when the conversation is reopened.

---

## UI features

- **Sidebar** — conversation list with pin, rename (inline), and delete
- **Pinned conversations** — sorted above recent with a divider
- **Model selector** — per-conversation model; restored on load
- **Message actions** (hover to reveal):
  - Copy message text
  - Edit user messages — opens inline editor; on submit, all subsequent messages are discarded and the edited message is re-sent
  - Delete individual messages
- **File attachments** — attach multiple files per message with drag-or-click
- **Markdown rendering** — full GFM with syntax-highlighted code blocks
- **Dark / light mode** — respects OS preference, toggleable in header
- **Typing indicator** and smooth scroll-to-bottom

---

## Building

```bash
# Build UI + Go binary
make build

# UI only (outputs to internal/ui/dist/)
make ui

# Go binary only (after make ui)
go build -o chatbot .
```

> The `internal/ui/dist/` directory is gitignored. After cloning, run `make ui` before building the Go binary.

---

## Development

```bash
# Install frontend dependencies
cd web && pnpm install

# Start frontend dev server (proxies /api to localhost:8080)
cd web && pnpm dev

# Start backend
go run . -config ./config.yaml
```
