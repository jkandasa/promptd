# RBAC Implementation Details

## What Was Implemented

- Cookie-based browser login with JWT session cookies.
- Bearer-token authentication for API keys tied to users.
- Role-based authorization with union semantics across multiple roles.
- Tenant-aware `super_admin` bypass.
- Wildcard allow rules for models, tools, and system prompts.
- Scoped ownership for conversations, schedules, executions, and uploaded files.
- Backend filtering and validation for chat and scheduler selections.
- Minimal login flow in the web UI.

## Auth Flow

- `POST /api/auth/login`
  - accepts `{ "user_id": "...", "password": "..." }`
  - verifies configured password hash
  - issues JWT in an `HttpOnly` cookie
- `GET /api/auth/me`
  - returns current authenticated user, tenant, roles, and permissions
- `POST /api/auth/logout`
  - clears the session cookie
- Service callers authenticate with `Authorization: Bearer <token>` using an API key

## Hash Support

- Password and API key verification use bcrypt hashes.
- Plaintext API key tokens are shown exactly once at generation time and never stored.
- Config examples in `config_template.yaml` were updated accordingly.

## API Key Management

Users can generate and manage API keys through the UI (avatar menu → API Keys) or programmatically:

- Admins manage keys for any user via `POST /api/admin/users/{id}/api-keys`.
- Any authenticated user manages their own keys via `POST /api/user/api-keys`.
- Keys support an optional description, expiry date/time, and can be disabled without deletion.
- The `api_keys` field in `auth.users` supersedes the legacy `service_tokens` field; existing configs using `service_tokens` are migrated transparently on load.

## Wildcard Policy Rules

- Model allow rules support:
  - `*`
  - `<provider-pattern>:<model-pattern>`
- Tool and system prompt allow rules support glob-style patterns.
- Supported wildcards:
  - `*` for any sequence
  - `?` for a single character

Examples:

```yaml
models:
  allow:
    - "*"
    - "openrouter:*"
    - "groq:model_oss*-20b*"

tools:
  allow:
    - "get_current_*"

system_prompts:
  allow:
    - "Code*"
```

## Scope And Ownership Model

- Resources are now tied to `(tenant_id, user_id)`.
- Conversations and schedules persist ownership fields in their stored records.
- Files remain filesystem-backed, but are stored under tenant/user-specific directories.

Current on-disk layout:

```text
<data>/tenants/<tenant>/users/<user>/conversations/
<data>/tenants/<tenant>/users/<user>/uploads/
<data>/tenants/<tenant>/users/<user>/schedules/
<data>/tenants/<tenant>/users/<user>/schedules/executions/
```

This keeps the code ready for future DB-backed conversation/schedule storage while leaving file storage separate.

## Selection Rules

- Allowed models/providers/system prompts remain selectable in both:
  - conversations
  - schedules
- The backend validates selections again when requests are made or schedules run.
- If provider selection is left on auto, authorization is evaluated against the resolved provider/model pair.

## Trace Access

- Trace data is filtered by permission.
- Users without `traces_read` can still use chat and schedules, but trace payloads are omitted from responses.

## Main Backend Files Changed

- `cmd/main.go`
- `internal/auth/policy.go`
- `internal/auth/service.go`
- `internal/chat/session.go`
- `internal/handler/handler.go`
- `internal/handler/schedule_handler.go`
- `internal/scheduler/scheduler.go`
- `internal/scheduler/store.go`
- `internal/scheduler/types.go`
- `internal/storage/storage.go`
- `internal/storage/yaml_store.go`
- `internal/tools/registry.go`

## Main Frontend Files Changed

- `web/src/App.tsx`
- `web/src/api/client.ts`
- `web/src/pages/index.tsx`

## Verification

- `go build ./...`
- `yarn build` in `web/`

## Follow-Ups Worth Doing

- Add automated tests for auth, wildcard matching, and scoped storage.
- Add a helper script or doc for generating bcrypt hashes for users.
- Consider `Secure` cookies behind TLS-aware deployment settings.
