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

For air-gapped environments (no internet access at runtime), bundle CanvasKit and Montserrat fonts locally:

```bash
make build-with-console-airgap
# equivalent: make build WITH_CONSOLE=1 AIRGAP=1
```

The standard CDN build is ~5 MB; the airgap build is ~37 MB (CanvasKit included).

To build just the Flutter web assets without compiling Go:

```bash
make console-ui          # CDN mode (~5 MB)
make console-ui AIRGAP=1 # Airgap mode (~37 MB)
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

## Android release signing

The CI workflows require a release keystore to build signed APK and AAB artifacts. Signing is mandatory — the build fails if the secrets are not configured.

### Generate a keystore (one-time)

```bash
keytool -genkey -v \
  -keystore ~/promptd-release.jks \
  -alias promptd \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

Keep `promptd-release.jks` safe. Losing it means you can no longer publish updates to an existing Play Store listing.

If `keytool` did not prompt for a separate key password, the key password equals the keystore password.

### Configure GitHub secrets

Add these four secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w 0 ~/promptd-release.jks` |
| `KEY_ALIAS` | `promptd` |
| `KEY_PASSWORD` | key password (same as store password if not prompted separately) |
| `STORE_PASSWORD` | keystore password |

### Local signing

To sign locally, create `console/android/key.properties` (gitignored — never commit it):

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=promptd
storeFile=/absolute/path/to/promptd-release.jks
```

The `build.gradle.kts` detects this file automatically and uses the release signing config. Without it, the debug key is used.

### Play Store

Upload the `.aab` from the release artifacts. On first upload, enable **Play App Signing** in the Play Console — Google re-signs the final APK for distribution using their own key. The upload key only needs to be kept secure on your end.

The current UI mirrors the web app's visual system:

- Montserrat and Open Sans typography (Montserrat is bundled locally; no CDN fetch needed)
- violet primary accent
- rounded card surfaces
- chat-first operator shell with scheduler, tools, and admin sections
- shared SVG logo asset from `console/promptd-logo.svg`

Authentication:

- The login screen asks for the Promptd server URL, user ID, and password.
- The server URL is persisted locally.
- The JWT returned by `/api/auth/login` is persisted and replayed as an `Authorization: Bearer` token for authenticated API calls.
- Users who must change their password are redirected to a change-password screen before accessing the console.

User features:

- Any authenticated user can generate and manage their own API keys from the avatar menu → API Keys.
- API keys support optional description, expiry date/time, and can be enabled/disabled without deletion.
- Generated tokens are shown once and never stored server-side; users must copy them at creation time.

Admin features (requires `admin` permission or `super_admin`):

- Manage users: create, edit roles, set/reset passwords, enable/disable.
- Manage API keys per user: generate, enable/disable, delete, set expiry.
- Manage roles: create and edit RBAC role definitions.
- Manage system prompts: create, edit, and delete managed system prompts from the UI.

Performance (Linux 4K/Wayland):

- `RepaintBoundary` isolation around markdown, images, and SVG assets to reduce rasterization overhead.
- Increased `ListView` cache extent for high-DPI displays.
- Scroll scheduling moved off the build path to avoid unnecessary rebuilds.
