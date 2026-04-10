# Chatbot Web UI

React + Ant Design frontend for the Chatbot server.

## Stack

- **React 18** with TypeScript
- **Ant Design 5** — component library
- **Vite** — build tool
- **react-markdown** + **remark-gfm** — Markdown rendering
- **react-syntax-highlighter** — code block highlighting

## Setup

```bash
cd web
pnpm install
```

## Development

```bash
pnpm dev
```

Starts the Vite dev server. API requests are proxied to the Go backend (default `http://localhost:8080`).

## Build

```bash
pnpm build
```

Output goes to `dist/`. The parent `Makefile` copies this to `internal/ui/dist/` so the Go binary can embed it.

## Type check

```bash
pnpm tsc --noEmit
```
