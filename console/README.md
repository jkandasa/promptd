# Promptd Console

This directory contains a Flutter-based multi-platform console for Promptd.

**Requirements:** Flutter 3.41+ (Dart 3.11+)

Targets generated:

- Android
- iOS
- Linux
- macOS
- Windows
- Web

## Embedding in the binary

The Flutter web build can be embedded into the `promptd` binary instead of the default React web UI. Run from the repo root:

```bash
make build-with-console
# equivalent: make build WITH_CONSOLE=1
```

This builds the Flutter web release (`console/build/web/`) and copies it into `internal/ui/dist` before compiling the Go binary. The resulting `promptd` binary serves the Flutter console at `/`.

To build just the Flutter web assets without compiling Go:

```bash
make console-ui
```

## Running locally

```bash
cd console
make run-web
```

## Available targets

- `make pub`
- `make run-web`
- `make run-android`
- `make run-linux`
- `make build-web`
- `make build-android`
- `make build-linux`

The current UI mirrors the web app's visual system:

- Montserrat and Open Sans typography
- violet primary accent
- rounded card surfaces
- chat-first operator shell with scheduler and tools sections
- shared SVG logo asset from `console/promptd-logo.svg`

Authentication:

- The login screen asks for the Promptd server URL, user ID, and password.
- The server URL is persisted locally.
- The JWT returned by `/api/auth/login` is persisted and replayed as an `Authorization: Bearer` token for authenticated API calls.

Performance (Linux 4K/Wayland):

- `RepaintBoundary` isolation around markdown, images, and SVG assets to reduce rasterization overhead.
- Increased `ListView` cache extent for high-DPI displays.
- Scroll scheduling moved off the build path to avoid unnecessary rebuilds.
