# AGENTS.md

Purpose: give future AI agents an accurate mental model of `macfuseGui` so changes remain safe, predictable, and aligned with current UX and reliability guarantees.

## 1) Product in One Page

`macfuseGui` is a macOS menu-bar accessory app (`LSUIElement=true`) that manages SSHFS mounts through macFUSE.

Core user-facing capabilities:
- Multiple remotes with independent connect/disconnect.
- Passwords in Keychain; config in JSON.
- Per-remote startup intent (`Auto-connect on app launch`).
- Recovery after sleep/wake, network restore, and external unmount events.
- Finder-style remote folder browser (directories-only) with sticky data and auto-recovery.
- Diagnostics snapshot and copy-to-clipboard for support/debugging.

Primary targets:
- macOS 13+
- Apple Silicon first (`arm64`), Intel via `ARCH_OVERRIDE=x86_64`

## 2) Runtime Composition

Entry points:
- `macfuseGui/App/macfuseGuiApp.swift`
- `macfuseGui/App/AppDelegate.swift`
- `macfuseGui/App/AppEnvironment.swift`

Dependency wiring (`AppEnvironment`):
- Diagnostics, redaction, process runner, dependency checker
- Launch-at-login service
- Store + keychain + validation
- Mount stack (`MountCommandBuilder`, `UnmountService`, `MountManager`)
- Browser stack (`LibSSH2SFTPTransport` -> `RemoteBrowserSessionManager` -> `RemoteDirectoryBrowserService`)
- `RemotesViewModel`
- `SettingsWindowController`

Single orchestrator:
- `macfuseGui/ViewModels/RemotesViewModel.swift`
- All remote lifecycle state flows through this VM.

## 3) App Lifecycle and Quit Semantics

Startup (`AppDelegate.applicationDidFinishLaunching`):
1. App runs in accessory mode (no Dock icon).
2. Main menu is installed (for Cmd+Q handling).
3. `AppEnvironment` is created.
4. Menu bar controller is created.
5. Background startup sequence runs:
   - `refreshAllStatuses()`
   - `runStartupAutoConnect()`

Duplicate-instance protection (startup hardening):
- App acquires a singleton lock file at `/tmp/com.visualweb.macfusegui.instance.lock` using `flock`.
- App also checks already running apps by bundle ID, executable name, and localized app name.
- If another real instance is already alive, current process activates the existing instance and terminates.
- Xcode `DerivedData` test-host processes are excluded from duplicate-instance matching.

XCTest host guard:
- Startup returns early when running as XCTest host (`XCTestConfigurationFilePath`, `XCTestBundlePath`, `XCTestSessionIdentifier`, runtime XCTest class check, and process-name check).
- This prevents test-host launches from creating extra menu bar status items or starting recovery loops.

Reopen behavior:
- `applicationShouldHandleReopen` returns `false`.
- Settings never auto-open on launch or reopen.

Quit hardening (`forceQuit`):
- Posts `.forceQuitRequested` so SwiftUI sheets/panels close themselves.
- Tears down modal loops and attached sheets explicitly.
- Calls `RemotesViewModel.prepareForTermination()`.
- Calls `NSApp.terminate`.
- Hard fallback `_exit(0)` after timeout to avoid hung quit states.

This is intentionally aggressive because stale app/process state previously caused relaunch failures.

## 4) Data Model Contracts

`RemoteConfig` (`macfuseGui/Models/RemoteConfig.swift`):
- `id`, `displayName`, `host`, `port`, `username`
- `authMode` (`.password` / `.privateKey`), `privateKeyPath`
- `remoteDirectory`, `localMountPoint`
- `autoConnectOnLaunch`
- `favoriteRemoteDirectories`, `recentRemoteDirectories`

`RemoteDraft`:
- Editor-only mutable model.
- Includes plaintext draft password (never persisted to JSON).

`RemoteStatus`:
- `state`: `disconnected`, `connecting`, `connected`, `disconnecting`, `error`
- `mountedPath`, `lastError`, `updatedAt`

Browser models:
- `BrowserConnectionHealth`: includes `state`, `retryCount`, `lastError`, `lastSuccessAt`, `lastLatencyMs`
- `RemoteBrowserSnapshot`: includes `isStale`, `isConfirmedEmpty`, `fromCache`, `requestID`, `latencyMs`

Backward compatibility:
- `RemoteConfig` decodes missing newer fields with defaults so legacy `remotes.json` files keep loading.

## 5) Persistence and Security

Config store:
- `macfuseGui/Services/RemoteStore.swift`
- `~/Library/Application Support/macfuseGui/remotes.json`
- `RemoteStore` + `JSONRemoteStore` are `@MainActor` to enforce single-threaded persistence access.

Secrets:
- `macfuseGui/Services/KeychainService.swift`
- Keychain service: `com.visualweb.macfusegui.password`
- Account key: remote UUID string

Security invariants:
- Never write passwords to JSON.
- Never log passwords/secrets.
- External commands always execute as argument arrays (`Process`), no shell interpolation.

Redaction:
- `RedactionService` masks askpass secrets in logged command strings.

## 6) Mount Subsystem (MountManager + UnmountService)

Main files:
- `macfuseGui/Services/MountManager.swift`
- `macfuseGui/Services/UnmountService.swift`
- `macfuseGui/Services/MountCommandBuilder.swift`
- `macfuseGui/Services/MountStateParser.swift`

Connect flow highlights:
- Dependency gate (`sshfs`, macFUSE, ssh, sftp).
- Pre-connect cleanup if mountpoint already mounted.
- Auto-create missing local mount folder.
- Retry once for transient failures (`resource busy`, reset/timeout/network-type failures).
- Minimum transition visibility (~0.8s) to keep UI from appearing frozen or skipping states.
- Verifies mount appears after sshfs exit before reporting success.

Disconnect flow highlights:
- Unmount via `UnmountService` with multiple command rounds (`diskutil`, `umount`, force variants).
- Minimum transition visibility (~0.7s).
- If outer disconnect times out, VM can trigger `forceStopProcesses` for scoped sshfs cleanup.

Busy unmount UX:
- On busy/resource-busy, `lsof` blockers are parsed and surfaced as user-facing process hints.
- No kill action for arbitrary user processes.

Mount inspection anti-flap logic (important):
- `refreshStatus` does not immediately downgrade a previously-connected mount on one probe miss.
- Uses responsive path check (`stat`) + `df` fallback + brief retry before declaring disconnect.
- This avoids false reconnect storms from transient mount table probe failures.

Command builder nuances:
- Windows path normalization for sshfs source path.
- Stable `volname` derivation from display name + remote path leaf.
- Password-specific ssh options that previously broke macFUSE are intentionally omitted.

## 7) Per-Remote Operation Supervisor (Critical)

`RemotesViewModel` replaced global serialization with per-remote supervision.

Key structures:
- `RemoteOperationIntent`: `connect`, `disconnect`, `refresh`, `testConnection`
- `RemoteOperationTrigger`: `manual`, `recovery`, `startup`, `termination`
- `RemoteOperationConflictPolicy`:
  - `latestIntentWins`
  - `skipIfBusy`
- `remoteOperations: [UUID: RemoteOperationState]`
- `OperationLimiter(maxConcurrent: 4)` for cross-remote cap

Behavior contract:
- At most one active operation per remote.
- Same-remote conflict:
  - Manual connect/disconnect uses `latestIntentWins` (new intent cancels old).
  - Recovery/status probes use `skipIfBusy` (don’t stomp manual work).
- Cross-remote operations run in parallel (up to 4).
- Operation watchdogs are keyed by operation ID; stale completions cannot overwrite newer intents.

Timeout/watchdog defaults:
- Connect watchdog: `45s`
- Disconnect watchdog: `10s`
- Refresh watchdog: `18s`
- Connect inner timeout path: `35s`

Diagnostics logs every operation start/end/cancel/timeout with:
- `remoteID`, `operationID`, `intent`, `trigger`, elapsed ms, cancellation/supersession details.
- `limiterWaitMs` (time spent waiting for `OperationLimiter.acquire()`).
- `mount call` lines with `queuedAtMs`, `nowMs`, `preAwaitDelayMs`, and `opAgeMs` before entering `MountManager`.

Mount actor queueing instrumentation:
- `MountManager` logs `actor enter op=... remoteID=... operationID=... queueDelayMs=...`.
- Probe logs include `remoteID` and `operationID` for:
  - `mount-inspect`
  - `df-inspect`
  - `mount-responsive-check`
  - `sshfs-connect`
- This allows production log proof of true cross-remote overlap versus actor funneling.

## 8) Desired Connections and Recovery Engine

`desiredConnections` is the core intent set:
- Means “user wants this remote kept connected.”
- Recovery acts only on remotes in this set.

Where it is updated:
- Added on successful connect and startup auto-connect intent.
- Removed on manual disconnect, certain permanent failures, remote deletion, termination.

Recovery triggers:
- Timer pass every 15s (backup safety pass).
- Sleep/wake notifications.
- Network reachability changes (`NWPathMonitor`).
- External volume unmount (`NSWorkspace.didUnmountNotification`).

Recovery burst schedules:
- Wake: `[0s, 1s, 3s, 8s]`
- Network restored: `[0s, 2s, 6s]`

Periodic skip optimization:
- If all desired remotes are healthy, no in-flight reconnects, and last periodic full probe was recent, periodic deep probe is skipped.
- `healthyPeriodicProbeInterval = 60s`

Reconnect scheduling:
- Backoff matrix from `reconnectDelaySeconds(...)` with trigger-aware behavior.
- Current first reconnect delay commonly starts at `0s` for fast recovery.
- Permanent failure classifier halts auto-reconnect for non-recoverable cases (auth errors, shared mountpoint, macFUSE-on-macFUSE errors, missing deps).

Why polling still exists:
- macOS does not provide a single reliable push event for all “SSHFS became stale” cases.
- Design is event-first (wake/network/unmount) with periodic polling as a safety net.

## 9) Reconnect Visualization and Menu Semantics

`statusBadgeRawValue(for:)` can return synthetic `reconnecting`:
- computed from reconnect tasks/in-flight markers + desired intent + recovery indicator context
- not solely from `RemoteStatus.state`

Menu bar icon behavior (`MenuBarController`):
- Icon animates when:
  - active connect/disconnect operations exist, or
  - recovery indicator active, or
  - wake pulse active, or
  - reconnecting remotes > 0
- Connected count text color:
  - orange during sleep/recovery/reconnecting
  - green when stable

Tooltip includes:
- Active operations with elapsed durations
- Recovery reason/pending/queued
- Aggregate C/A/E/D counts

## 10) Settings, Editor, and UX Nuances

Settings window:
- Explicit open only from menu action.
- Shows launch-at-login state, including approval/fallback details.
- Includes entry point button that opens a dedicated `Editor Plugins` window.

Remote detail panel:
- Edit, Duplicate, Delete, Refresh, Connect, Disconnect.
- Connect/Disconnect buttons are state-aware and disabled appropriately.

Editor (`RemoteEditorView`):
- Add/Edit title, password eye toggle, auth mode switch.
- `Auto-connect on app launch` toggle.
- `Test Connection` button with in-place progress/result.
- Both Cancel button and top-right close icon are present.
- Remote browser opens in sheet; session closed on sheet dismiss.
- Responds to `.forceQuitRequested` to close cleanly during hard quit.

Validation + uniqueness:
- Display name unique (case-insensitive).
- Local mountpoint unique (normalized, case-insensitive).
- Remote path supports UNIX and Windows drive forms.

## 11) Open-In-Editor Plugin Flow

Menu actions support opening connected remotes in a configurable editor plugin set.

Core behavior:
- Primary action uses preferred plugin with fallback across active plugins.
- Secondary `Open In…` picker allows explicit plugin selection.
- If all attempts fail, app opens the folder in Finder and emits alert + diagnostics warning.

Built-in plugins:
- `vscode` (default active)
- `vscodium`
- `cursor`
- `zed`
- Built-in manifest source-of-truth in repo:
  - `macfuseGui/Resources/EditorPlugins/vscode/plugin.json`
  - `macfuseGui/Resources/EditorPlugins/vscodium/plugin.json`
  - `macfuseGui/Resources/EditorPlugins/cursor/plugin.json`
  - `macfuseGui/Resources/EditorPlugins/zed/plugin.json`

Built-in `vscode` attempts are VS Code-only:
1. `open -b com.microsoft.VSCode`
2. `open -b com.microsoft.VSCodeInsiders`
3. `open -a Visual Studio Code` variants
4. `code --reuse-window`

Cross-editor fallback is handled by plugin ordering across active plugins, not mixed attempts inside one plugin manifest.

Plugin registry:
- Service: `macfuseGui/Services/EditorPluginRegistry.swift`
- Model: `macfuseGui/Models/EditorPlugin.swift`
- Persisted toggle overrides: `editor.plugins.activation_overrides`
- Persisted preferred plugin: `editor.plugins.preferred_id`
- External manifests path: `~/Library/Application Support/macfuseGui/editor-plugins/*.json`
- On first load, registry auto-creates scaffold files:
  - `README.md`
  - `examples/custom-editor.json.template`
  - `builtin-reference/*.json` (reference docs for shipped built-ins; non-recursive loader means these are not loaded as external manifests)

Manifest safety contract:
- Allowed executables: `/usr/bin/open`, `/usr/bin/env`
- Must include `{folderPath}` placeholder in arguments
- `/usr/bin/open` forms require `-a` or `-b`
- `/usr/bin/env` forms require a bare command token first arg

Settings UX:
- Real-time check/uncheck plugin toggles (no restart)
- Preferred editor picker from active plugins
- Manual `Reload Plugins` action to rescan manifest files
- Buttons to open plugin root, examples, and built-in reference folders in Finder
- `New Plugin JSON` action creates a template manifest directly in the external plugin folder
- Per-plugin inline JSON editor loads/saves manifests directly inside the plugin settings window

## 12) Browser Subsystem (libssh2 Session Model)

Main API (`RemoteDirectoryBrowserService`):
- `openSession(remote:password:)`
- `closeSession(sessionID)`
- `listDirectories(sessionID:path:requestID)`
- `goUp(sessionID:currentPath:requestID)`
- `retryCurrentPath(sessionID:requestID)`
- `health(sessionID:)`

Implementation chain:
- `RemoteDirectoryBrowserService`
- `RemoteBrowserSessionManager` (actor)
- `LibSSH2SessionActor` (actor per browser sheet)
- `LibSSH2SFTPTransport` (single bridge queue)
- `LibSSH2Bridge.c/.h` (native libssh2)

Transport details:
- Persistent per-remote libssh2 sessions cached in transport.
- List timeout: `8s`
- Ping timeout: `2s`
- On list failure, transport invalidates session and retries once by reopening.
- Swift transport calls remain serialized on one bridge queue, but each C call is deadline-bounded and returns on timeout.

C bridge reliability details:
- Non-blocking connect with select-based timeout.
- Socket-level `SO_RCVTIMEO` + `SO_SNDTIMEO` are configured during session open; failure to configure is a hard open-session error.
- Socket is kept non-blocking for libssh2 session lifetime.
- Password auth with keyboard-interactive fallback.
- Private-key auth path.
- Deadline-driven EAGAIN loops are used for handshake/auth/sftp-init/realpath/opendir/readdir/stat.
- Timeout errors are stage-specific and user-visible (for example: `SSH handshake`, `password authentication`, `SFTP readdir`) and include timeout seconds.
- Session close path uses `shutdown(sock, SHUT_RDWR)` before libssh2 teardown to break pending waits quickly.
- Directory classification checks permission flags and Windows `<DIR>`/`[DIR]` markers.

## 13) Browser Session Actor Contracts

`LibSSH2SessionActor` guarantees:
- No silent failure states.
- Cached data preferred over blank UI during transient failures.
- Recovery loop is autonomous when needed.

Important internals:
- `cache[path]` sticky entries.
- `requestRetrySchedule = [0.3s, 0.8s]` for foreground list.
- `recoveryRetrySchedule = [0.2s, 0.8s, 2s, 5s]` for background recovery.
- Keepalive every `12s`, idle-only (`activeListRequests == 0` and no recovery in flight).
- Keepalive failure is non-destructive; schedules recovery.
- Circuit breaker threshold `8`, window `30s`.

Empty-list policy (critical):
- If list returns empty and cache exists: keep cached entries, mark stale/reconnecting.
- If first-load empty and no cache: do immediate confirm-list before declaring healthy-empty.
- `isConfirmedEmpty` differentiates true empty folder from uncertain empty response.

Health model usage:
- `healthy`, `degraded`, `reconnecting`, `failed`, `closed` states drive VM/UI.
- `lastSuccessAt` + `lastLatencyMs` shown in footer and diagnostics.

## 14) Browser ViewModel/UI Contracts

ViewModel (`RemoteBrowserViewModel`):
- State machine: `idle`, `loadingFirstPage`, `ready`, `degradedWithCache`, `recovering`, `fatal`
- Monotonic `requestID` prevents stale response overwrite.
- Degraded auto-retry loop every `2.5s` until healthy/closed.
- Health poll loop every `3s`.
- Unconfirmed empty snapshot must not wipe previously visible entries.

View (`RemoteBrowserView`):
- Finder-like `NavigationSplitView`
- Sidebar: Favorites, Recents, Roots
- Detail: breadcrumbs, search, sort, table columns (Name, Date, Kind, Size)
- Degraded reconnect banner with `Retry now`
- Confirmed-empty panel and degraded panel when no visible data
- Footer shows item count, health, last success, latency
- Keyboard actions: refresh (`Cmd+R`), open (`Return`), up (`Delete`)

Column width persistence:
- Stored in `UserDefaults` keys:
  - `browser.column.name`
  - `browser.column.date`
  - `browser.column.kind`
  - `browser.column.size`

## 15) Path Memory Rules

Per-remote path memory:
- Favorites limit: `20`
- Recents limit: `15`
- Case-insensitive dedupe
- Mandatory normalization before persistence

Normalization handles:
- Windows drive artifacts (`/D::`, `D::\\x`, etc.)
- slash normalization and canonical root handling

Persistence behavior:
- Saved remote (`id != nil`): persisted to `RemoteConfig` via store.
- Unsaved draft: lives in editor session until save.

## 16) Launch at Login Implementation

Service:
- `LaunchAtLoginService` in `RemotesViewModel.swift`

Primary path:
- `SMAppService.mainApp.register/unregister`

Fallback path:
- LaunchAgent plist at `~/Library/LaunchAgents/com.visualweb.macfusegui.launchagent.plist`
- `launchctl` bootstrap/enable/bootout flows
- Used when SMAppService registration is unavailable or not taking effect

UI state:
- `LaunchAtLoginState` includes `enabled`, `requiresApproval`, `detail`
- Toggle displays approval/fallback guidance text.

## 17) Diagnostics Contract

Diagnostics snapshot includes:
- Environment + dependency readiness
- Per-remote status summary
- Recent logs (redacted)
- `Operations` section (active operation table)
- `Browser Sessions` section (health, retries, path, latency, last success)

Expected categories:
- `store`, `mount`, `unmount`, `recovery`, `operations`, `remote-browser`, `startup`, `editor`, `vscode`, `diagnostics`, `app`

No secrets in diagnostics:
- Askpass and passwords are redacted or omitted.

## 18) Build, Run, Clean, and Third-Party Prep

Primary scripts:
- `scripts/build.sh`
- `scripts/run.sh`
- `scripts/clean.sh`
- `scripts/build_libssh2.sh`

libssh2 prep:
- Output: `build/third_party/libssh2`
- OpenSSL output: `build/third_party/openssl`
- `scripts/build_libssh2.sh` now builds both OpenSSL and libssh2 from source for the active arch/deployment target
- Source tarballs are cached under `third_party/src` (`openssl-<version>.tar.gz`, `libssh2-<version>.tar.gz`) and auto-downloaded if missing
- Build artifacts are cached by a fingerprint (`version`, `arch`, `min target`) so repeated builds are fast

App output:
- `build/macfuseGui.app`

Tests:
- `xcodebuild ... test CODE_SIGNING_ALLOWED=NO`
- Reliability gate: `scripts/audit_mount_calls.py && xcodebuild -project macfuseGui.xcodeproj -scheme macfuseGui -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO`
- Key tests cover:
  - Remote store legacy defaults/new fields
  - Path normalization and memory limits
  - Browser empty confirmation + recovery behavior
  - Keepalive-triggered recovery
  - Unmount blocker parsing
  - Mount arg safety and Windows path normalization

## 19) Clever/Non-Obvious Safeguards to Preserve

1. Force-quit path with modal/sheet teardown + `_exit(0)` fallback.
2. Per-remote operation supervision with cross-remote parallel cap.
3. Operation-instance watchdogs and stale-completion suppression.
4. Anti-flap mount refresh (responsive-path + `df` fallback + retry).
5. Transitional visibility delays for connect/disconnect UI fidelity.
6. Browser request ordering via monotonic request IDs.
7. Sticky cache with explicit degraded/reconnecting states (never silent blank).
8. Empty-list confirmation before clearing data.
9. Idle-only keepalive and non-destructive ping failures.
10. Deadline-bounded libssh2 bridge calls (no indefinite C-level browser waits).
11. Launch-at-login dual-path support (SMAppService + LaunchAgent fallback).
12. ProcessRunner capture shutdown before terminate/SIGKILL to avoid post-timeout stdout/stderr races.

## 20) Safe-Change Rules for Future Agents

1. Keep `desiredConnections` semantics as the source of recovery intent.
2. Do not reintroduce global serialized mount operation bottlenecks.
3. Preserve one-active-operation-per-remote invariant.
4. Preserve `latestIntentWins` for manual conflicts and `skipIfBusy` for recovery refresh.
5. Keep operation limiter cap behavior unless explicitly changing concurrency policy.
6. Preserve connect/disconnect watchdog behavior and explicit timeout messaging.
7. Preserve uniqueness checks for display name + local mountpoint.
8. Preserve anti-flap status refresh behavior in `MountManager.refreshStatus`.
9. Preserve browser requestID stale-write protection.
10. Preserve sticky-cache + empty-confirmation browser contracts.
11. Keep keepalive idle-only and non-destructive.
12. Keep deadline-driven libssh2 timeout stages and bounded list/ping behavior.
13. Keep path-memory normalization and limits.
14. Keep command execution as argument arrays only.
15. Never log secrets.
16. Preserve plugin registry safety rules (`/usr/bin/open`/`/usr/bin/env`, `{folderPath}` placeholder requirement).
17. Preserve preferred-plugin + fallback semantics and Finder fallback on complete editor-open failure.
