# Remote Tool Specification

This document describes how to build a remote tool that integrates with the chatbot.
A remote tool is a standalone HTTP server. It can be written in **any language**.

---

## How It Works

```
Chatbot startup:
  1. Calls GET /describe  → learns the tool's name, description, and parameters
  2. Registers the tool into the LLM's tool list
  3. Starts polling GET /health every 15 seconds

At runtime (user sends a message):
  4. LLM decides to call the tool
  5. Chatbot calls POST /execute with the arguments
  6. Tool runs and returns the result
  7. Chatbot feeds the result back to the LLM
  8. LLM produces the final reply

On graceful shutdown:
  9. Tool calls DELETE /tools/unregister on the chatbot (optional but recommended)

If the tool crashes:
  10. Chatbot detects health check failure after 3 consecutive misses (~45s)
  11. Tool is automatically removed from the LLM's tool list
```

---

## Endpoints Your Tool Must Implement

### `GET /describe`

Called once by the chatbot at registration time.
Returns tool metadata: name, description, and the JSON Schema for its arguments.

**Response — `200 OK`**
```json
{
  "name": "tool_name",
  "description": "One sentence describing what this tool does.",
  "parameters": {
    "type": "object",
    "properties": {
      "param1": {
        "type": "string",
        "description": "Description of param1."
      },
      "param2": {
        "type": "integer",
        "description": "Description of param2."
      }
    },
    "required": ["param1"]
  }
}
```

**Rules:**
- `name` must be unique across all registered tools. Use `snake_case`.
- `description` is shown to the LLM — write it clearly so the model knows when to call your tool.
- `parameters` is a standard [JSON Schema](https://json-schema.org/) object. Use `"required"` to mark mandatory fields.

---

### `POST /execute`

Called by the chatbot every time the LLM wants to use your tool.

**Request body**
```json
{
  "args": {
    "param1": "some value",
    "param2": 42
  }
}
```

`args` contains exactly the fields described in your `/describe` parameters schema.

**Success response — `200 OK`**
```json
{
  "result": "The answer or output of your tool as a plain string."
}
```

**Error response — `200 OK`**
```json
{
  "error": "A human-readable error message."
}
```

> **Important:** Always return HTTP `200`. Never return 4xx/5xx for tool logic errors.
> The chatbot passes your `error` string back to the LLM as context so it can
> respond helpfully to the user. A non-200 response is treated as a transport failure.

---

### `GET /health`

Called by the chatbot every 15 seconds to verify your tool is alive.

**Response — `200 OK`** (no body required)

If this endpoint fails 3 times in a row, the chatbot automatically removes your tool
from the LLM's tool list. No restart of the chatbot is needed — the tool re-registers
itself next time it starts up.

---

## Dynamic Registration (Optional but Recommended)

Instead of listing your tool in `tools.yaml`, your binary can register and unregister
itself with the chatbot automatically.

### Register on startup

Call this after your HTTP server is ready to accept requests:

```
POST {chatbot_url}/tools/register
Content-Type: application/json

{"url": "http://your-tool-host:port"}
```

**Success — `200 OK`**
```json
{"name": "your_tool_name", "description": "…"}
```

**Failure — `400 Bad Request`**
```json
{"error": "could not reach tool server at …"}
```

### Unregister on graceful shutdown

Call this before your process exits (e.g. on SIGTERM/SIGINT):

```
DELETE {chatbot_url}/tools/unregister
Content-Type: application/json

{"url": "http://your-tool-host:port"}
```

**Success — `204 No Content`**

---

## Multiple Tools in One Binary

A single binary can serve any number of tools from one HTTP server.
The only protocol change is:

- `GET /describe` returns a **JSON array** instead of a single object
- `POST /execute` requires a `"name"` field to identify which tool to call

```json
// GET /describe — multi-tool response
[
  { "name": "tool_a", "description": "…", "parameters": { … } },
  { "name": "tool_b", "description": "…", "parameters": { … } }
]

// POST /execute — multi-tool request (name is required)
{ "name": "tool_a", "args": { "input": "hello" } }
```

The chatbot detects single vs multi automatically based on whether `/describe`
returns an object or array. No configuration needed.

### Go example with ServeMulti

```go
func main() {
    addr    := flag.String("addr",    ":9001",                 "listen address")
    self    := flag.String("self",    "http://localhost:9001", "this server's URL")
    chatbot := flag.String("chatbot", "http://localhost:8080", "chatbot URL")
    flag.Parse()

    log.Fatal(toolserver.ServeMultiWithConfig(toolserver.Config{
        Addr:       *addr,
        SelfURL:    *self,
        ChatbotURL: *chatbot,
    }, ToolA{}, ToolB{}, ToolC{}))
}
```

When the chatbot receives this registration, it registers all three tools at once.
When the server goes down, all three are unregistered together.

---

## Implementation Examples

### Go (using the toolserver helper)

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

func (MyTool) Name() string { return "my_tool" }

func (MyTool) Description() string {
    return "Does something useful with the provided input."
}

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
    addr    := flag.String("addr",    ":9001",                  "listen address")
    self    := flag.String("self",    "http://localhost:9001",   "this tool's URL")
    chatbot := flag.String("chatbot", "http://localhost:8080",   "chatbot URL")
    flag.Parse()

    log.Fatal(toolserver.ServeWithConfig(toolserver.Config{
        Addr:       *addr,
        SelfURL:    *self,
        ChatbotURL: *chatbot,
    }, MyTool{}))
}
```

---

### Python

```python
import signal
import sys
import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

SELF_URL    = "http://localhost:9001"
CHATBOT_URL = "http://localhost:8080"

# ── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/describe")
def describe():
    return jsonify({
        "name": "my_tool",
        "description": "Does something useful with the provided input.",
        "parameters": {
            "type": "object",
            "properties": {
                "input": {
                    "type": "string",
                    "description": "The input to process."
                }
            },
            "required": ["input"]
        }
    })

@app.post("/execute")
def execute():
    args = request.json.get("args", {})
    text = args.get("input", "").strip()
    if not text:
        return jsonify({"error": "input is required"})
    return jsonify({"result": f"processed: {text.upper()}"})

@app.get("/health")
def health():
    return "", 200

# ── Lifecycle ─────────────────────────────────────────────────────────────────

def register():
    try:
        requests.post(f"{CHATBOT_URL}/tools/register", json={"url": SELF_URL}, timeout=5)
        print(f"Registered with chatbot at {CHATBOT_URL}")
    except Exception as e:
        print(f"Warning: registration failed: {e}")

def unregister():
    try:
        requests.delete(f"{CHATBOT_URL}/tools/unregister", json={"url": SELF_URL}, timeout=5)
        print("Unregistered from chatbot")
    except Exception as e:
        print(f"Warning: unregistration failed: {e}")

def handle_shutdown(sig, frame):
    unregister()
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT,  handle_shutdown)

if __name__ == "__main__":
    register()
    app.run(port=9001)
```

---

### Node.js

```js
const express  = require('express')
const axios    = require('axios')
const process  = require('process')

const app        = express()
const SELF_URL   = 'http://localhost:9001'
const CHATBOT_URL = 'http://localhost:8080'

app.use(express.json())

// ── Endpoints ──────────────────────────────────────────────────────────────

app.get('/describe', (req, res) => res.json({
  name: 'my_tool',
  description: 'Does something useful with the provided input.',
  parameters: {
    type: 'object',
    properties: {
      input: { type: 'string', description: 'The input to process.' }
    },
    required: ['input']
  }
}))

app.post('/execute', (req, res) => {
  const { input } = req.body.args ?? {}
  if (!input) return res.json({ error: 'input is required' })
  res.json({ result: `processed: ${input.toUpperCase()}` })
})

app.get('/health', (req, res) => res.sendStatus(200))

// ── Lifecycle ──────────────────────────────────────────────────────────────

async function register() {
  try {
    await axios.post(`${CHATBOT_URL}/tools/register`, { url: SELF_URL })
    console.log(`Registered with chatbot at ${CHATBOT_URL}`)
  } catch (e) {
    console.warn(`Warning: registration failed: ${e.message}`)
  }
}

async function unregister() {
  try {
    await axios.delete(`${CHATBOT_URL}/tools/unregister`, { data: { url: SELF_URL } })
    console.log('Unregistered from chatbot')
  } catch (e) {
    console.warn(`Warning: unregistration failed: ${e.message}`)
  }
}

async function shutdown() {
  await unregister()
  process.exit(0)
}

process.on('SIGTERM', shutdown)
process.on('SIGINT',  shutdown)

app.listen(9001, async () => {
  await register()
  console.log('Tool server listening on :9001')
})
```

---

## Parameters — JSON Schema Reference

The `parameters` field in `/describe` follows JSON Schema. Common patterns:

### String parameter
```json
"city": {
  "type": "string",
  "description": "The city name, e.g. London."
}
```

### Integer parameter
```json
"count": {
  "type": "integer",
  "description": "Number of results to return.",
  "minimum": 1,
  "maximum": 100
}
```

### Enum (fixed set of values)
```json
"unit": {
  "type": "string",
  "enum": ["celsius", "fahrenheit"],
  "description": "Temperature unit."
}
```

### Optional parameter with default
Mark it optional by omitting it from `"required"` and describe the default in the description:
```json
"timezone": {
  "type": "string",
  "description": "IANA timezone name, e.g. Asia/Kolkata. Defaults to UTC."
}
```

### Array parameter
```json
"tags": {
  "type": "array",
  "items": { "type": "string" },
  "description": "List of tags to filter by."
}
```

---

## Checklist

Before shipping your remote tool, verify:

- [ ] `GET /describe` returns valid JSON with `name`, `description`, `parameters`
- [ ] `name` is unique — no other registered tool has the same name
- [ ] `description` clearly explains *when* to use the tool (the LLM reads this)
- [ ] `POST /execute` always returns HTTP `200`, even on errors
- [ ] `POST /execute` returns `{"error": "…"}` for failures, not an exception/stack trace
- [ ] `GET /health` returns HTTP `200` with no body
- [ ] Graceful shutdown calls `DELETE /tools/unregister` before exiting
- [ ] Tool starts and completes registration *before* announcing it is ready

---

## Quick Reference

| Endpoint                          | Method   | Called by  | Purpose                        |
|-----------------------------------|----------|------------|--------------------------------|
| `/describe`                       | GET      | Chatbot    | Fetch tool metadata once       |
| `/execute`                        | POST     | Chatbot    | Run the tool                   |
| `/health`                         | GET      | Chatbot    | Heartbeat every 15s            |
| `{chatbot}/tools/register`        | POST     | Your tool  | Self-register on startup       |
| `{chatbot}/tools/unregister`      | DELETE   | Your tool  | Self-unregister on shutdown    |
| `{chatbot}/tools`                 | GET      | Anyone     | List currently active tools    |
