# Execute API

`POST /api/execute` is a **stateless single-shot LLM call** designed for service accounts and programmatic integrations. Unlike `/api/chat`, it carries no conversation history — each call is independent.

## Authentication

Pass your service token as a Bearer token in every request:

```
Authorization: Bearer <your-service-token>
```

Service tokens are configured in `config.yaml` under `auth.users[].service_tokens`. The token must be bcrypt-hashed; use `promptd hash-password` to generate the hash.

```yaml
auth:
  users:
    - id: my-service
      tenant_id: default
      roles:
        - automation
      service_tokens:
        - id: prod-token-1
          token_hash: "$2a$10$..." # promptd hash-password
          expires_at: "2027-01-01T00:00:00Z" # optional
```

The account must have the `chat` permission in its role.

---

## Request

```
POST /api/execute
Content-Type: application/json
Authorization: Bearer <token>
```

```json
{
  "system_prompt": "You are a helpful assistant.",
  "system_prompt_name": "assistant-v1",
  "provider": "openrouter",
  "model": "openai/gpt-4o-mini",
  "message": "Summarise the following text: ...",
  "tools": ["*"],
  "no_history": false,
  "params": {
    "temperature": 0.3,
    "max_tokens": 512
  }
}
```

### Fields

| Field                | Type             | Required | Description                                                                              |
| -------------------- | ---------------- | -------- | ---------------------------------------------------------------------------------------- |
| `system_prompt`      | string           | one of   | Inline system prompt text.                                                               |
| `system_prompt_name` | string           | one of   | Name of a managed system prompt from the config (RBAC-checked against your role).        |
| `message`            | string           | yes      | The user message to send to the model.                                                   |
| `provider`           | string           | no       | Provider name (e.g. `openrouter`). Defaults to the first provider with an allowed model. |
| `model`              | string           | no       | Model ID (e.g. `openai/gpt-4o-mini`). Defaults to the role's first allowed model.        |
| `tools`              | array of strings | no       | Tool patterns to expose. See [Tools](#tools) below.                                      |
| `no_history`         | bool             | no       | When `true`, the call is not saved to conversation history. Default `false`.             |
| `params`             | object           | no       | LLM parameter overrides.                                                                 |
| `params.temperature` | float            | no       | Sampling temperature.                                                                    |
| `params.max_tokens`  | int              | no       | Maximum completion tokens.                                                               |
| `params.top_p`       | float            | no       | Top-p (nucleus sampling).                                                                |
| `params.top_k`       | int              | no       | Top-k sampling.                                                                          |

Exactly one of `system_prompt` or `system_prompt_name` must be set.

---

## Tools

The `tools` field controls which tools are made available to the model for this call. Tool access is always bounded by what your service account's role allows.

| Value                     | Meaning                                                   |
| ------------------------- | --------------------------------------------------------- |
| Absent or `null`          | No tools.                                                 |
| `["*"]`                   | All tools your role permits.                              |
| `["web_search", "calc"]`  | Exact names.                                              |
| `["web_*"]`               | Wildcard match — all tools whose names start with `web_`. |
| `["web_*", "calculator"]` | Multiple patterns, OR-ed together.                        |

Tools not permitted by your role are silently excluded regardless of what you request.

---

## Response

```json
{
  "reply":           "The text summarises to ...",
  "model":           "openai/gpt-4o-mini",
  "provider":        "openrouter",
  "conversation_id": "a1b2c3d4-...",
  "time_taken_ms":   1234,
  "llm_calls":       1,
  "tool_calls":      0,
  "used_params": {
    "temperature": 0.3,
    "max_tokens":  512
  },
  "trace": [ ... ]
}
```

### Fields

| Field             | Type   | Description                                                                       |
| ----------------- | ------ | --------------------------------------------------------------------------------- |
| `reply`           | string | The model's final text reply.                                                     |
| `model`           | string | Model that was used.                                                              |
| `provider`        | string | Provider that was used.                                                           |
| `conversation_id` | string | ID of the saved conversation. Absent when `no_history: true`.                     |
| `time_taken_ms`   | int    | Wall-clock time including all LLM calls and tool executions.                      |
| `llm_calls`       | int    | Number of LLM round-trips made (>1 when tools were called).                       |
| `tool_calls`      | int    | Number of tool executions.                                                        |
| `used_params`     | object | Effective generation parameters that were sent to the model.                      |
| `trace`           | array  | LLM round-trip trace. Only present when the account has `traces_read` permission. |

---

## Errors

| HTTP | `error`                                                      | Cause                                                                             |
| ---- | ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| 400  | `message is required`                                        | Empty or missing `message`.                                                       |
| 400  | `system_prompt or system_prompt_name is required`            | Neither field was set, or the resolved text is empty.                             |
| 400  | `only one of system_prompt or system_prompt_name may be set` | Both fields were set.                                                             |
| 400  | `invalid system prompt`                                      | `system_prompt_name` does not exist in the config.                                |
| 403  | `chat not allowed`                                           | The service account's role does not have the `chat` permission.                   |
| 403  | `system prompt not allowed`                                  | The role's `system_prompts` allow-list excludes the named prompt.                 |
| 500  | `no allowed model available`                                 | No model matches the role's `models` allow-list for the requested provider/model. |
| 500  | `model "X" is not allowed`                                   | The explicitly requested model is outside the role's allow-list.                  |

---

## Examples

### Inline system prompt, no tools, no history

```bash
curl -s -X POST https://promptd.example.com/api/execute \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "system_prompt": "You are a concise assistant. Reply in one sentence.",
    "message": "What is the capital of France?",
    "no_history": true
  }' | jq .reply
```

```
"The capital of France is Paris."
```

---

### Named prompt, specific model, no tools, save to history

```bash
curl -s -X POST https://promptd.example.com/api/execute \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "system_prompt_name": "summariser-v2",
    "provider": "openrouter",
    "model": "openai/gpt-4o-mini",
    "message": "Summarise: The quick brown fox jumps over the lazy dog."
  }' | jq '{reply, conversation_id}'
```

```json
{
  "reply": "A fox quickly leaps over a resting dog.",
  "conversation_id": "a1b2c3d4-5678-..."
}
```

---

### All allowed tools, with LLM trace

```bash
curl -s -X POST https://promptd.example.com/api/execute \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "system_prompt": "You have access to tools. Use them when helpful.",
    "message": "What time is it right now?",
    "tools": ["*"],
    "no_history": true
  }' | jq '{reply, llm_calls, tool_calls}'
```

```json
{
  "reply": "The current time is 14:32 UTC.",
  "llm_calls": 2,
  "tool_calls": 1
}
```

---

### Wildcard tool pattern

```bash
curl -s -X POST https://promptd.example.com/api/execute \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "system_prompt": "Search the web when needed.",
    "message": "Find the latest news about Go 1.25.",
    "tools": ["web_*"]
  }'
```

Only tools whose names start with `web_` (and permitted by your role) are exposed.

---

## Conversation history

By default (`no_history: false`) each execute call is saved as a single-turn conversation in the caller's history. The `conversation_id` in the response can be used with the standard conversation APIs to read back the stored exchange:

```
GET /api/conversations/{conversation_id}
```

Set `"no_history": true` for fire-and-forget calls where you don't need the exchange persisted.

---

## RBAC quick reference

| What you want                       | What to configure in the role                       |
| ----------------------------------- | --------------------------------------------------- |
| Allow calling `/api/execute`        | `permissions.chat: true`                            |
| Allow using a specific named prompt | Add the name (or pattern) to `system_prompts.allow` |
| Allow all named prompts             | `system_prompts.allow: ["*"]`                       |
| Allow a specific model              | `models.allow: ["openrouter:openai/gpt-4o-mini"]`   |
| Allow all models on a provider      | `models.allow: ["openrouter:*"]`                    |
| Allow all models everywhere         | `models.allow: ["*"]`                               |
| Allow specific tools                | `tools.allow: ["web_search", "calculator"]`         |
| Allow all tools                     | `tools.allow: ["*"]`                                |
| See LLM trace in the response       | `permissions.traces_read: true`                     |
