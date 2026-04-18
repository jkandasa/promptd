# promptd

A lightweight, extensible LLM prompt server written in Go with a React frontend. Connects to any OpenAI-compatible API, persists conversation history to disk, and ships with MCP tool support and a built-in scheduler.

---

## Features

- **Multi-provider** — configure multiple providers (OpenRouter, OpenAI, Gemini, Mistral, …); each with its own models, API key, and selection method
- **Multi-model** — configure multiple models with random or round-robin selection; user can override per-conversation
- **Auto-discover** — automatically fetch and refresh the model list from a provider's `/v1/models` endpoint
- **Persistent conversation history** — all conversations stored as YAML files; survives server restarts
- **Conversation sidebar** — browse, continue, rename, pin, and delete past conversations
- **Session management** — each browser tab gets its own isolated conversation
- **Scheduler** — create recurring (cron) or one-time prompt schedules; view execution history with responses, LLM traces, and token stats
- **Tool calling** — native LLM function-calling loop with built-in and MCP tools
- **MCP support** — connect to external MCP servers with optional auth; auto-reconnect and periodic tool rediscovery
- **Health monitoring** — dead MCP servers are automatically removed and re-registered on recovery
- **File uploads** — attach files to messages; images previewed inline
- **Embedded chat UI** — zero-dependency browser interface served at `/`
- **System prompts** — load one or many prompts from external files and switch in the UI
- **Trace drawer** — per-assistant-message LLM trace showing every round's messages sent, model response, tool executions, token counts (with reasoning and cached breakdowns), and latencies
- **Active tools drawer** — searchable list of all tools currently available to the LLM (built-in + MCP)
- **Single binary** — statically compiled, no runtime dependencies

---

## Usage

```bash
# Build the UI first (requires Node.js / pnpm)
make ui

# Run the server
./promptd -config ./config.yaml
```

---

## Configuration

Copy `config_template.yaml` to `config.yaml` and fill in the required fields.

```yaml
data:
  dir: "./data"           # Root for all data (default: ./data)
                          # Conversations → <dir>/conversations/
                          # Uploads       → <dir>/uploads/
                          # Schedules     → <dir>/schedules/

server:
  address: "localhost:8080"   # Listen address (default: localhost:8080)

llm:
  selection_method: "round_robin"   # Global default: random | round_robin

  # Global auto-discover defaults (can be overridden per-provider)
  auto_discover:
    enabled: false
    refresh_interval: 60m

  trace:
    enabled: true    # Show LLM trace drawer in UI (default: true)
    ttl: 7d          # How long trace data is retained (default: 7d, min 1h)

  providers:
    - name: "openrouter"
      api_key: "your-api-key"
      base_url: "https://openrouter.ai/api/v1"

      # Optional: override global selection_method for this provider
      # selection_method: "round_robin"

      # Optional: global LLM params for this provider's models
      # params:
      #   temperature: 0.7
      #   top_p: 0.95
      #   max_tokens: 4096
      #   top_k: 40

      models:
        - "anthropic/claude-sonnet-4-6"
        - id: "openai/gpt-4o"
          name: "GPT-4o"            # Optional display name
          params:
            temperature: 0.3        # Per-model params override provider params

      # Override per-provider auto-discover
      auto_discover:
        enabled: false
        refresh_interval: 60m

    # Add more providers as needed:
    # - name: "groq"
    #   api_key: ""
    #   base_url: "https://api.groq.com/openai/v1/"
    #   models:
    #     - "llama-3.3-70b-versatile"

log:
  level: "info"    # debug | info | warn | error

mcp:
  health_max_failures: 3              # Failures before unregistering (default: 3)
  health_interval: 15s                # Health check interval (default: 15s)
  reconnect_interval: 30s             # Retry interval for failed servers (default: 30s)
  timeout: 30s                        # Tool call timeout (default: 30s)
  tool_rediscovery_interval: 0        # Periodic tool re-list interval (default: 0 = disabled)
  servers:
    - name: "my-server"
      url: "http://localhost:8081/mcp"
      auth:
        token: "optional-token"
      headers:
        X-Custom: "value"
      disabled: false
      insecure: false                           # Skip TLS certificate verification
      reconnect_interval: 30s                   # Override global reconnect_interval
      health_max_failures: 3                    # Override global health_max_failures
      health_interval: 15s                      # Override global health_interval
      timeout: 30s                              # Override global timeout
      tool_rediscovery_interval: 5m             # Override global tool_rediscovery_interval

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

#### `data`

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `data.dir` | No | `./data` | Root directory; `conversations/`, `uploads/`, and `schedules/` are always fixed sub-dirs |

#### `server`

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `server.address` | No | `localhost:8080` | HTTP listen address |

#### `llm`

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `llm.selection_method` | No | `round_robin` | Global model selection default: `random` or `round_robin` |
| `llm.auto_discover.enabled` | No | `false` | Enable model auto-discovery for all providers by default |
| `llm.auto_discover.refresh_interval` | No | `60m` | How often to refresh discovered models (min `1m`) |
| `llm.trace.enabled` | No | `true` | Show trace drawer in the UI |
| `llm.trace.ttl` | No | `7d` | How long LLM trace data is retained per assistant message (min `1h`) |
| `llm.providers` | Yes | — | List of LLM providers (see below) |

#### `llm.providers[]`

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `name` | Yes | — | Unique provider display name |
| `api_key` | Yes | — | API key for this provider |
| `base_url` | No | OpenRouter | OpenAI-compatible base URL |
| `selection_method` | No | global | `random` or `round_robin` for this provider |
| `params` | No | — | Provider-level LLM generation defaults (`temperature`, `max_tokens`, `top_p`, `top_k`) |
| `models` | No | — | Static model list; string or `{id, name, params}` object |
| `models[].params` | No | — | Per-model param overrides (override provider-level params) |
| `auto_discover.enabled` | No | global | Enable auto-discovery for this provider |
| `auto_discover.refresh_interval` | No | `60m` | Refresh interval for this provider (min `1m`) |

#### `mcp`

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `health_max_failures` | No | `3` | Consecutive failures before unregistering a server |
| `health_interval` | No | `15s` | Health check interval |
| `reconnect_interval` | No | `30s` | Retry interval for servers that fail to connect |
| `timeout` | No | `30s` | Tool call timeout |
| `tool_rediscovery_interval` | No | `0` | How often to re-list tools from each server (`0` = disabled) |
| `servers[].name` | Yes | — | Server display name |
| `servers[].url` | Yes | — | MCP server URL |
| `servers[].auth.token` | No | — | Bearer token |
| `servers[].headers` | No | `{}` | Extra HTTP headers |
| `servers[].disabled` | No | `false` | Skip this server at startup |
| `servers[].insecure` | No | `false` | Skip TLS certificate verification |
| `servers[].reconnect_interval` | No | global | Override global reconnect interval |
| `servers[].health_max_failures` | No | global | Override global health max failures |
| `servers[].health_interval` | No | global | Override global health interval |
| `servers[].timeout` | No | global | Override global tool call timeout |
| `servers[].tool_rediscovery_interval` | No | global | Override global tool rediscovery interval |

#### `tools`

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `tools.system_prompts` | Yes | — | Selectable system prompts as `{name, file}`; the first is selected by default |

#### `ui`

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `ui.app_name` | No | `promptd` | App name shown in the header and browser title |
| `ui.app_icon` | No | built-in robot | App icon; supports emoji/text or image URL/path |
| `ui.welcome_title` | No | — | Welcome screen heading |
| `ui.ai_disclaimer` | No | built-in | Disclaimer text shown below the input |
| `ui.prompt_suggestions` | No | built-in | Quick-send prompt chips on the welcome screen |

---

## API Endpoints

### Chat

| Method | Path | Body / Params | Description |
|--------|------|---------------|-------------|
| `GET` | `/` | — | Serve chat UI |
| `POST` | `/chat` | `{session_id, message, model?, provider?, system_prompt?, files?, params?}` | Send a message; returns reply + message IDs |
| `POST` | `/reset` | `{session_id}` | Clear session history server-side |
| `GET` | `/ui-config` | — | UI configuration (title, suggestions, …) |
| `GET` | `/models` | — | List available models, providers, and selection method |
| `GET` | `/tools` | — | List all tools currently available to the LLM (built-in + MCP) |

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

### Schedules

| Method | Path | Body | Description |
|--------|------|------|-------------|
| `GET` | `/schedules` | — | List all schedules |
| `POST` | `/schedules` | Schedule object | Create a new schedule |
| `GET` | `/schedules/{id}` | — | Get a single schedule |
| `PUT` | `/schedules/{id}` | Schedule object | Replace a schedule |
| `DELETE` | `/schedules/{id}` | — | Delete a schedule |
| `POST` | `/schedules/{id}/trigger` | — | Run a schedule immediately (non-blocking) |
| `GET` | `/schedules/{id}/executions` | — | List execution history for a schedule |
| `DELETE` | `/schedules/{id}/executions/{execId}` | — | Delete a single execution record |

---

## Chat response

`POST /chat` returns:

```json
{
  "reply": "...",
  "model": "openai/gpt-4o",
  "provider": "openrouter",
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
- The top-level `model` and `provider` fields record the user's explicit selection (empty = auto). Per-message fields record the actual model/provider used for each assistant reply.
- `pinned` conversations sort to the top of the sidebar.
- Auto-title is generated from the first user message (truncated to 60 runes).

---

## Scheduler

The scheduler runs prompts on a recurring or one-time basis without user interaction.

### Schedule types

- **`cron`** — fires on a 6-field cron expression: `seconds minutes hours day month weekday`
- **`once`** — fires once at an absolute timestamp

### Schedule fields

| Field | Description |
|-------|-------------|
| `name` | Display name |
| `enabled` | Whether the schedule is active |
| `type` | `cron` or `once` |
| `cronExpr` | 6-field cron expression (e.g. `0 0 8 * * *` = daily 08:00) |
| `runAt` | ISO 8601 timestamp for one-time schedules |
| `prompt` | Prompt sent to the model on each execution |
| `modelId` | Model override (blank = server default) |
| `provider` | Provider override (blank = server default) |
| `systemPrompt` | System prompt name override |
| `allowedTools` | Restrict which tools the LLM may call (empty = all tools) |
| `params` | LLM parameter overrides (`temperature`, `max_tokens`, `top_p`, `top_k`) |
| `traceEnabled` | `true` / `false` / `null` (null = follow global config) |
| `retainHistory` | How many past executions to keep (0 = keep all) |

### Execution records

Each run produces an `Execution` record with status (`running` / `success` / `error`), the model response, full LLM trace, token usage, and timing data. Executions are browsable in the Scheduler page of the UI.

Schedules and executions are stored as YAML files in `<data.dir>/schedules/`.

---

## Trace data

Each assistant message optionally carries a `trace` field containing the full LLM round-trip data for that reply:

- **What is captured per round**: the exact messages sent, the model's raw response (including reasoning from thinking models), tool definitions available, tool results, token usage (prompt / completion / reasoning / cached), and LLM + tool latencies.
- **Reasoning content** — OpenRouter models that return a `"reasoning"` field (e.g. `nvidia/nemotron`, `liquid/lfm-thinking`) have it transparently mapped to `reasoning_content` before the SDK parses the response. No extra configuration needed.
- **Retention** — trace data is purged after `llm.trace.ttl` (default 7 days) by a background job. Only the `trace` field is removed; the conversation and messages are unaffected.
- Trace data is stored inline in the conversation YAML under each assistant message's `trace:` key.

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

A configurable `reconnect_interval` controls how often the manager retries servers that failed to connect at startup.

If `tool_rediscovery_interval` is set (globally or per-server), the manager periodically re-lists tools from connected servers to pick up any additions, removals, or schema changes.

---

## File uploads

- Max size: 10 MB per file, up to 10 files per message
- Images are previewed inline as thumbnails with click-to-expand
- Non-image files are shown as download links
- Files persist independently of conversations under `<data.dir>/uploads/`

---

## Multi-model and multi-provider support

Configure multiple providers in `config.yaml`, each with their own models. The `selection_method` controls automatic model selection within a provider:

- **`round_robin`** — cycles through models sequentially
- **`random`** — picks a model at random each request

When multiple providers are configured, the UI shows a provider selector. The user can also enable auto-discover to pull the live model list from a provider's `/v1/models` endpoint.

The user's chosen model and provider are persisted per-conversation and restored when the conversation is reopened.

---

## UI features

- **Chat page** — conversation sidebar, model/provider selector, file attachments, and message actions
- **Scheduler page** — full schedule management: create/edit/delete, enable/disable, manual trigger, execution history with responses and LLM traces
- **Sidebar** — conversation list with pin, rename (inline), and delete
- **Pinned conversations** — sorted above recent with a divider
- **Model selector** — per-conversation model; restored on load; shows provider tag when multiple providers are configured
- **Message actions** (hover to reveal):
  - Copy message text
  - Edit user messages — opens inline editor; on submit, all subsequent messages are discarded and the edited message is re-sent
  - Delete individual messages
- **File attachments** — attach multiple files per message with drag-or-click
- **Markdown rendering** — full GFM with syntax-highlighted code blocks
- **Dark / light mode** — respects OS preference, toggleable in header
- **Typing indicator** and smooth scroll-to-bottom
- **Trace drawer** — click the token-count badge on any assistant message to open a per-message LLM trace:
  - One collapsible panel per LLM round showing: Available Tools → Messages Sent → LLM Decision/Response → Tool Execution
  - Reasoning content shown as a collapsed block (for thinking models)
  - Token counts per round: `↑ prompt  ↓ completion  (N reasoning, N cached)`
  - Round summary with LLM and tool latencies
- **Active tools drawer** — header button lists all tools the LLM can call; searchable by name or description

---

## Building

```bash
# Build UI + Go binary
make build

# UI only (outputs to internal/ui/dist/)
make ui

# Go binary only (after make ui)
go build -o promptd .
```

> The `internal/ui/dist/` directory is gitignored. After cloning, run `make ui` before building the Go binary.

---

## Development

```bash
# Install frontend dependencies
cd web && pnpm install

# Start frontend dev server (proxies API calls to localhost:8080)
cd web && pnpm dev

# Start backend
go run . -config ./config.yaml
```
