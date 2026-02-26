# macfuseGui

`macfuseGui` is a macOS menu bar agent app for mounting remote directories with `sshfs` + macFUSE.

- macOS 13+
- Apple Silicon first (`arm64`), Intel supported (`ARCH_OVERRIDE=x86_64`)
- Release flow defaults to dual-arch artifacts (`ARCH_OVERRIDE=both`)
- `NSStatusItem` menu bar UX, no Dock icon (`LSUIElement=true`)
- SwiftUI settings + AppKit menu bar integration

## Key Features

- Multiple remotes with per-remote connect/disconnect.
- Startup duplicate-instance guard (singleton lock + running-app check) to avoid duplicate menu bar icons.
- Secure persistence:
  - Non-sensitive config in JSON.
  - Passwords in macOS Keychain.
- Test Connection in add/edit (real temporary mount + unmount validation).
- Per-remote startup toggle: `Auto-connect on app launch`.
- Recovery handling for sleep/wake and network restoration.
- Busy unmount diagnostics (shows blocking processes via `lsof`).
- Open-in-editor plugin system:
  - Built-in editor plugins (`VS Code`, `VSCodium`, `Cursor`, `Zed`)
  - Preferred editor + fallback across active plugins
  - Real-time enable/disable in Settings
  - External plugin manifests from disk
- Finder-style remote browser:
  - Sidebar (Favorites / Recents / Roots)
  - Breadcrumb navigation
  - Directories-only table view
  - Sticky cache with reconnect-state banners (no silent blank state)
- Diagnostics snapshot + `Copy Diagnostics` menu action.

## Dependency Install

```bash
brew install --cask macfuse
brew install gromgit/fuse/sshfs-mac
```

## Install via Homebrew (App)

```bash
brew tap ripplethor/macfusegui https://github.com/ripplethor/macfuseGUI
brew install --cask ripplethor/macfusegui/macfusegui
```

Expected `sshfs` search order:
1. `/opt/homebrew/bin/sshfs`
2. `/usr/local/bin/sshfs`
3. `sshfs` from `$PATH`

## Open-In-Editor Plugins

The menu popover provides:
- Primary one-click action: `Open in <Preferred Editor>`
- Explicit picker action: `Open In…`

Default behavior:
- Built-ins shipped: `vscode`, `vscodium`, `cursor`, `zed`
- Only `vscode` starts active by default
- Preferred editor auto-rehomes to the next active plugin if needed
- If all attempts fail, app falls back to Finder and records diagnostics
- Each built-in plugin manifest is editor-specific (no cross-editor mixed attempts inside one plugin)
- Built-in manifests live in codebase under:
  - `macfuseGui/Resources/EditorPlugins/vscode/plugin.json`
  - `macfuseGui/Resources/EditorPlugins/vscodium/plugin.json`
  - `macfuseGui/Resources/EditorPlugins/cursor/plugin.json`
  - `macfuseGui/Resources/EditorPlugins/zed/plugin.json`

Settings behavior:
- Toggle plugins on/off in real time (no restart)
- Select preferred editor from active plugins
- Reload plugin manifests manually with `Reload Plugins`
- Open dedicated `Editor Plugins…` window from Settings
- Reveal plugin directory in Finder
- Create a new plugin manifest from template (`New Plugin JSON`)
- Edit manifest JSON inline for any selected plugin (`Inline JSON Editor`)
- Remove external plugins directly from the plugin catalog (`Trash`)

External manifests:
- Directory: `~/Library/Application Support/macfuseGui/editor-plugins`
- File type: `*.json` (one plugin per file)
- The app auto-creates this folder on first load with:
  - `README.md` usage guide
  - `examples/custom-editor.json.template`
  - `builtin-reference/*.json` (reference definitions for shipped editors; not loaded as external plugins)
- Security rules:
  - only `/usr/bin/open` and `/usr/bin/env` executables
  - launch attempt must include `{folderPath}` placeholder
  - command arrays only; no shell interpolation

Example manifest:

```json
{
  "id": "windsurf",
  "displayName": "Windsurf",
  "priority": 50,
  "defaultEnabled": false,
  "launchAttempts": [
    {
      "label": "open app Windsurf",
      "executable": "/usr/bin/open",
      "arguments": ["-a", "Windsurf", "{folderPath}"],
      "timeoutSeconds": 3
    }
  ]
}
```

## Build / Run / Clean

From repo root:

```bash
./scripts/build.sh
./scripts/run.sh
./scripts/clean.sh
```

`build.sh` includes a pre-step:
- `ARCH_OVERRIDE=<arch> ./scripts/build_libssh2.sh`

Supported `ARCH_OVERRIDE` values:
- `arm64`
- `x86_64`
- `both`
- `universal`

Third-party output roots are arch-specific:
- `build/third_party/openssl-arm64`, `build/third_party/openssl-x86_64`, `build/third_party/openssl-universal`
- `build/third_party/libssh2-arm64`, `build/third_party/libssh2-x86_64`, `build/third_party/libssh2-universal`

App output paths:
- Single-arch (`arm64`, `x86_64`, `universal`): `build/macfuseGui.app`
- Dual-arch (`both`): `build/macfuseGui-arm64.app` and `build/macfuseGui-x86_64.app`

DerivedData roots:
- `build/DerivedData-arm64`
- `build/DerivedData-x86_64`
- `build/DerivedData-universal`

## Make Targets

```bash
make build
make run
make clean
```

## Common Build Overrides

```bash
# Intel build
ARCH_OVERRIDE=x86_64 ./scripts/build.sh

# Build separate arm64 + x86_64 apps
ARCH_OVERRIDE=both ./scripts/build.sh

# Universal app build
ARCH_OVERRIDE=universal ./scripts/build.sh

# Release build
CONFIGURATION=Release ./scripts/build.sh

# Allow signing if needed
CODE_SIGNING_ALLOWED=YES ./scripts/build.sh
```

## Release

```bash
# Default release mode is dual-arch (both)
./scripts/release.sh

# Verify dual-arch release actions without publishing
ARCH_OVERRIDE=both ./scripts/release.sh --dry-run

# Force a single-arch release if needed
ARCH_OVERRIDE=arm64 ./scripts/release.sh
ARCH_OVERRIDE=x86_64 ./scripts/release.sh
```

## Xcode CLI Fallback

```bash
xcodebuild -project macfuseGui.xcodeproj -scheme macfuseGui -configuration Debug -derivedDataPath build/DerivedData build
```

## Run Tests

```bash
xcodebuild -project macfuseGui.xcodeproj -scheme macfuseGui -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO
```

## Reliability Gate

```bash
scripts/audit_mount_calls.py && xcodebuild -project macfuseGui.xcodeproj -scheme macfuseGui -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO
```

## VS Code

Included:
- `.vscode/tasks.json`
- `.vscode/launch.json`
- `.vscode/settings.json`

Tasks:
- `build` -> `scripts/build.sh`
- `run` -> build + launch app
- `clean` -> `scripts/clean.sh`
- `sourcekit-reset-cache` -> `scripts/reset_sourcekit_cache.sh`

Debug launch:
- Program: `build/macfuseGui.app/Contents/MacOS/macfuseGui`
- Pre-launch task: `build`

## Documentation

- **[New Contributor Guide](CONTRIBUTING.md)**: Start here if you want to modify the app.
- **[Architecture & Jargon Buster](ARCHITECTURE.md)**: Visual diagrams and plain-English explanations.
- **[Safe Change Rules (AGENTS.md)](AGENTS.md)**: Critical rules for AI agents and developers.
- **[Commit & Push Workflow (COMMIT_WORKFLOW.md)](COMMIT_WORKFLOW.md)**: Commit format, changelog prefix rules, and release notes guidance.

## Security Notes

- All external command execution uses `Process` with argument arrays.
- No shell interpolation for user input.
- Password mode uses temporary `SSH_ASKPASS` helper (`0700`) and ephemeral env vars.
- Passwords are never stored in JSON or logs.
- `KeychainService.readPassword` trims leading/trailing whitespace on read — prevents silent auth failures from clipboard-pasted trailing newlines without altering the stored credential.
- IPv6 host addresses are automatically bracketed (`[::1]`) in sshfs arguments; bare IPv6 input is also rejected at the validation layer.
- Diagnostics redact sensitive content.

## Browser Subsystem Notes

Browser internals are session-based (`openSession` / `listDirectories` / `health` / `closeSession`) with per-session health and sticky-cache behavior.

Current transport implementation uses native libssh2 SFTP through a C bridge (`LibSSH2Bridge.c/.h`) behind an internal transport abstraction.

Recovery contract:
- Keepalive runs every 12s only while the browser session is idle.
- Keepalive failures do not hard-close sessions; they schedule list-based recovery.
- Recovery backoff: `0.2s`, `0.8s`, `2s`, `5s`.
- Empty listings are confirmation-checked before being treated as truly empty.
- Browser keeps last-good entries visible during transient failures.

## Troubleshooting

### Missing dependencies

```bash
brew install --cask macfuse
brew install gromgit/fuse/sshfs-mac
```

### xcodebuild first-launch issues

```bash
sudo xcodebuild -runFirstLaunch
```

### VS Code SourceKit stale errors

```bash
./scripts/reset_sourcekit_cache.sh
```

Then in VS Code:
1. Reload window
2. Restart Swift LSP
3. Re-index project

### Mount/unmount issues

- Use `Copy Diagnostics` from the app menu.
- For busy unmount, diagnostics now include blocking process hints.

### Duplicate menu icon or stale second app process

```bash
pkill -x macfuseGui
open -a /Applications/macfuseGui.app
```

If this still happens, check for multiple running processes:

```bash
pgrep -lf macfuseGui
```

### Browser diagnostics interpretation

- `state=healthy` with `isConfirmedEmpty=true`: path is reachable and truly has no subfolders.
- `state=reconnecting` or `state=degraded` with `fromCache=true`: browser is showing last-good cached data while retrying.
- `lastSuccessAt` and `lastLatencyMs` in `Browser Sessions` show the last confirmed successful list.
- Repeated `keepalive failed` followed by `recovery attempt` means auto-recovery is active; use `Retry now` in the browser UI to force an immediate list call.

### Mount concurrency proof logs (actor funnel check)

Use this during wake/reconnect testing:

```bash
log stream --style compact --predicate 'process == "macfuseGui"' \
  | rg 'Operation start remoteID=|Operation end remoteID=|mount call op=|actor enter op=|probe start op=sshfs-connect|probe end op=sshfs-connect'
```

Interpretation:
- Healthy parallelism: different remotes show overlapping `probe start/end op=sshfs-connect` windows.
- Funnel warning: one remote repeatedly waits with high `queueDelayMs` before `actor enter`.

## License

This project is licensed under the GNU General Public License v3.0.

If you distribute a modified version, you must also provide the source under GPLv3.

See [`LICENSE`](./LICENSE).
