# promptd

`promptd` is a developer focused LLM experimentation and debugging server with an embedded React UI. It is built to help you understand how models behave with different system prompts, tools, MCP servers, and scheduled workflows.

It is not positioned as a traditional chatbot server. The main goal is to make model behavior visible and testable so developers can inspect conversations, compare providers, exercise tool calling, and build prompt-driven automations.

## Why promptd

- Debug model conversations instead of treating them as a black box.
- Compare providers, models, prompts, and tool behavior from one place.
- Test MCP integrations and inspect how tools are selected and called.
- Build scheduled AI flows where the model can observe, decide, and act through tools.
- Keep conversations, traces, schedules, and tool-driven workflows inspectable and persistent.

## Use Cases

- Explore how the same task behaves across different models and system prompts.
- Validate tool-calling flows with built-in tools and MCP servers.
- Debug agent-like behavior by inspecting traces, tool calls, and conversation state.
- Run scheduled decision workflows, such as checking an external status through MCP and triggering another tool only when a condition is met.

Example:

- Track a postal shipment on a schedule.
- Ask the model to check the current shipment status through an MCP tool.
- Let the model decide whether the package has reached your town or entered an unexpected return state.
- If the condition matches, trigger a notification service through another tool.

## Features

- Multi-provider model routing with static or auto-discovered models
- Per-provider selection method with backend-owned model resolution
- Required system prompt selection in chat and scheduler flows
- Persistent conversations with pin, rename, delete, and edit-resend flow
- File uploads with inline text extraction and image preview support
- Tool calling from built-in tools and MCP tools
- Detailed LLM trace capture and UI trace drawers for debugging model behavior
- Scheduler execution retention and per-execution trace/token details
- Manual and automatic rolling compaction summaries
- Dark mode and embedded single-binary UI delivery

## Architecture

### Backend

- `cmd/main.go`: Cobra CLI entrypoint and server startup
- `internal/config`: YAML config schema and loading
- `internal/app`: bootstrapping helpers, provider setup, TLS helpers, route registration
- `internal/auth`: auth service, JWT/session handling, RBAC policy compilation
- `internal/handler`: chat APIs, conversation APIs, model/tool APIs, upload APIs, compaction APIs, scheduler HTTP handlers
- `internal/chat`: in-memory session cache over persistent storage
- `internal/storage`: YAML persistence for conversations and uploads metadata
- `internal/scheduler`: schedule store, scheduler, runner, execution history
- `internal/mcp`: MCP client and manager
- `internal/tools`: built-in tool registry
- `internal/ui`: embedded built frontend assets

### Frontend

- `web/src/pages/index.tsx`: shell, navigation, route-state handling
- `web/src/pages/chat/ChatPage.tsx`: main chat experience
- `web/src/pages/scheduler/*`: schedule list, edit form, history/detail views
- `web/src/pages/tools/ToolsPage.tsx`: available tools page
- `web/src/components/*`: bubbles, markdown, trace drawer, params UI, tool drawers
- `web/src/api/*`: thin fetch wrappers around `/api/*`
- `web/src/types/*`: chat and scheduler types

## Data Layout

Data is stored under `data.dir` in tenant/user scoped directories:

```text
<data.dir>/
  tls/
    server.crt
    server.key
  tenants/<tenant>/users/<user>/
    conversations/
    uploads/
    schedules/
    schedules/executions/
```

Notes:

- Conversations are persisted as YAML files.
- Intermediate tool-loop messages are not persisted.
- Assistant trace payloads are persisted and later purged by TTL.
- Compaction stores a special persisted summary message plus cutoff metadata.

## CLI

```bash
promptd serve --config ./config.yaml
promptd hash-password
promptd version
```

Notes:

- Running `promptd` with no subcommand is equivalent to `promptd serve`.
- `hash-password` is used for both user passwords and service tokens because both use bcrypt.

## Development

### Requirements

- Go 1.26
- Node.js
- Yarn

### Build UI

```bash
make ui
```

### Run

```bash
make run-go
```

or

```bash
go run ./cmd serve --config ./config.yaml
```

### Full Build

```bash
make build
```

## Releases

- Git tags matching `v1.*` publish GitHub release assets and multi-arch Docker images.
- Pushes to `main` update the rolling `devel` release and matching Docker image tags.

### Verification

```bash
go test ./...
cd web && yarn build
```

## Configuration

Start from `config_template.yaml`.

### Core Areas

- `data.dir`: storage root
- `server.address`: listen address
- `server.tls.*`: HTTPS settings
- `auth.jwt`: JWT cookie settings
- `auth.users`: users, password hashes, service tokens
- `roles`: permission and allow-list policy
- `llm.providers`: provider definitions
- `llm.auto_discover`: default provider auto-discovery settings
- `llm.trace`: trace retention and UI visibility
- `llm.compact_conversation`: rolling compaction settings
- `mcp.*`: MCP connection management
- `llm.system_prompts`: required selectable prompts
- `ui.*`: welcome copy and prompt suggestions

### HTTPS

External certificate example:

```yaml
server:
  address: "0.0.0.0:8443"
  tls:
    enabled: true
    cert_file: "/etc/ssl/private/promptd.crt"
    key_file: "/etc/ssl/private/promptd.key"
```

Autogenerated self-signed certificate example:

```yaml
server:
  address: "0.0.0.0:8443"
  tls:
    enabled: true
    auto_generate: true
    hosts:
      - "localhost"
      - "127.0.0.1"
```

When `auto_generate: true` and `cert_file` / `key_file` are omitted, promptd writes the generated certificate to `<data.dir>/tls/server.crt` and `<data.dir>/tls/server.key`.

### Compaction

```yaml
llm:
  compact_conversation:
    enabled: true
    provider: "openrouter"
    model: "openai/gpt-4o-mini"
    default_prompt: |
      Summarize the conversation into a minimal context.
      Keep key facts, intent, and constraints.
      Remove fluff, repetition, and filler.
      Write in compact bullet-style or short phrases.
    after_messages: 20
    after_tokens: 12000
```

Behavior:

- `after_messages` counts user messages since last compaction
- `after_tokens` estimates only new, un-compacted content
- manual compaction requires `compact_conversation_write`
- auto compaction does not require that permission

### RBAC

Permissions are boolean flags merged across user roles.

Current permissions:

- `chat`
- `upload`
- `conversations_read`
- `conversations_write`
- `compact_conversation_write`
- `schedules_read`
- `schedules_write`
- `traces_read`
- `admin`

Models, tools, and system prompts also use allow-list pattern matching. `super_admin: true` bypasses these restrictions inside the tenant.

## API Surface

All JSON APIs live under `/api`.

### Auth

- `POST /api/auth/login`
- `POST /api/auth/logout`
- `GET /api/auth/me`

### Chat and Conversations

- `POST /api/chat`
- `POST /api/reset`
- `GET /api/ui-config`
- `GET /api/models`
- `GET /api/tools`
- `GET /api/conversations`
- `GET /api/conversations/{id}`
- `DELETE /api/conversations/{id}`
- `PATCH /api/conversations/{id}/title`
- `PATCH /api/conversations/{id}/pin`
- `POST /api/conversations/{id}/compact`
- `DELETE /api/conversations/{id}/messages/{msgId}`
- `DELETE /api/conversations/{id}/messages/{msgId}/after`

### Files

- `POST /api/upload`
- `GET /api/files/{id}`
- `DELETE /api/files/{id}`

### MCP and Scheduler

- `GET /api/mcp`
- `GET /api/schedules`
- `POST /api/schedules`
- `GET /api/schedules/{id}`
- `PUT /api/schedules/{id}`
- `DELETE /api/schedules/{id}`
- `POST /api/schedules/{id}/trigger`
- `GET /api/schedules/{id}/executions`
- `DELETE /api/schedules/{id}/executions/{execId}`

## Important Behavior Notes

- System prompts are mandatory for chat and scheduler execution.
- Backend, not the frontend, decides fallback model selection when model is omitted.
- Traces are permission-gated. Users without `traces_read` still work normally but do not receive trace payloads.
- Scheduler re-validates RBAC at execution time, so later role/config changes can invalidate existing schedules.
- Compaction summaries replace older conversational context for future LLM calls.
- Session cookies are currently issued with `Secure: false` even when HTTPS is enabled.

## Security Notes

- Do not commit live API keys, service tokens, or JWT secrets.
- Rotate any credentials that were ever stored in a tracked config file.
- Prefer environment-specific configs outside version control for production.
- Self-signed certificates are useful for local/private deployments, not for public trusted browsers.

## Frontend Routing

The SPA uses path-driven state for the main views:

- `/chat/new`
- `/chat/:id`
- `/scheduler`
- `/scheduler/new`
- `/scheduler/:id`
- `/scheduler/:id/edit`
- `/tools`

## Status

The project currently includes the backend, embedded web app, RBAC, MCP support, scheduler, trace UI, file uploads, and rolling compaction described above.
