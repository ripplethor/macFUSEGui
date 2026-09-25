# AGENTS.md

Purpose: give future AI agents an accurate mental model of `macfuseGui` so changes remain safe, predictable, and aligned with current UX and reliability guarantees.

## 1) Product in One Page

`macfuseGui` is a macOS menu-bar accessory app (`LSUIElement=true`) that manages SSHFS mounts through macFUSE.

Core user-facing capabilities:
- Multiple remotes with independent connect/disconnect.
- Three auth modes (SSH private key, System SSH, password) and optional ProxyJump jump hosts.
- Passwords in Keychain; config in JSON.
- Per-remote cache mode (freshness vs speed) and favorite remotes pinned to the top of the menu.
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
2. Main menu is installed: app menu (Cmd+Q) plus a standard `Edit` menu (Undo/Redo/Cut/Copy/Paste/Delete/Select All). Accessory apps get no default menu, so without the `Edit` menu Cmd+C/V/X/A/Z do not work in text fields.
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
- `authMode` (`RemoteAuth`: `.privateKey` / `.systemSSH` / `.password`), `privateKeyPath`
- `proxyJumpEnabled`, `proxyJump` (OpenSSH ProxyJump spec; Finder mounts + Test Connection only)
- `remoteDirectory`, `localMountPoint`
- `isFavorite` (pins the remote to the top of lists; see §9)
- `autoConnectOnLaunch`
- `disableLocalCaches` (default `true`; see §6 cache modes)
- `favoriteRemoteDirectories`, `recentRemoteDirectories`

`RemoteAuth` (`macfuseGui/Models/RemoteAuth.swift`):
- Case order is the picker display order: `privateKey`, `systemSSH`, `password`.
- `.privateKey`: requires an absolute key path; appends `IdentityFile=...`.
- `.systemSSH`: no explicit key; OpenSSH resolves auth from agent, `~/.ssh/config`, Tailscale SSH, etc.
- `.password`: requires a stored or draft password; auth is pinned (see §6).

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
- Notable defaults: `authMode` → `.privateKey`, `proxyJumpEnabled` → `false`, `isFavorite` → `false`, `disableLocalCaches` → `true`, `remoteDirectory` → `/`.

## 5) Persistence and Security

Config store:
- `macfuseGui/Services/RemoteStore.swift`
- `~/Library/Application Support/macfuseGui/remotes.json`
- `RemoteStore` + `JSONRemoteStore` are `@MainActor` to enforce single-threaded persistence access.

Secrets:
- `macfuseGui/Services/KeychainService.swift`
- Keychain service: `com.visualweb.macfusegui.password`
- Account key: remote UUID string

Password read contract:
- `KeychainService.readPassword` trims leading/trailing whitespace before returning.
- Returns `nil` if the stored value is whitespace-only after trimming.
- Policy: SSH passwords with intentional surrounding whitespace are not a real-world case; trimming prevents silent auth failures from clipboard-pasted trailing newlines.

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
- Dependency gate (`sshfs`, macFUSE at `/Library/Filesystems/macfuse.fs`, `/usr/bin/ssh`, `/usr/bin/sftp`).
- sshfs backend resolution (`DependencyChecker`):
  1. User override path from Settings (`mount.backend.sshfs.override_path`)
  2. Previously pinned backend (`mount.backend.sshfs.pinned_path` / `pinned_source`)
  3. `/opt/homebrew/bin/sshfs`, `/usr/local/bin/sshfs`, `/opt/local/bin/sshfs` (MacPorts), `/usr/bin/sshfs`
  4. Absolute `$PATH` segments
  - The first executable hit is pinned in `UserDefaults` for later launches.
- `SSHFSCapabilities.detect` runs `sshfs -h` once per binary path (cached in `MountManager`) to pick supported cache options.
- Pre-connect cleanup if mountpoint already mounted.
- Auto-create missing local mount folder.
- Retry once for transient failures (`resource busy`, reset/timeout/network-type failures).
- Minimum transition visibility (~0.8s) to keep UI from appearing frozen or skipping states.
- sshfs runs in the foreground (`-f`) as a detached child from `ProcessRunner.launchDetached`: `posix_spawn` with `POSIX_SPAWN_SETSID` (own session and process group), stdin `/dev/null`, stdout/stderr to a private temp log.
  - Why: macFUSE 5.4+ libfuse no longer forks after the mount has started, and sshfs starts the mount before it daemonizes, so a non-`-f` sshfs never returns control (issue #8).
  - Success means the mount appears while sshfs is still running. The handle is then released, the process is reaped when it exits (on unmount), and the mount outlives the app like a self-daemonized sshfs did.
  - A non-zero exit before the mount appears fails the connect with the sshfs/ssh output. Foreground mode keeps ssh's stderr, so errors like `Permission denied (publickey)` reach the user and are classified as permanent. `MountManager.removingBenignSSHFSOutput` strips macFUSE fork warnings and ssh "Permanently added" notices.
  - A clean exit before the mount appears (sshfs builds that still detach) falls back to the post-exit `waitForMountAppearance` verification.
  - On timeout (sshfs connect command timeout, 20s) or cancellation the whole process group is terminated.
  - When the sshfs leader exits, leftover members of its process group are killed before it is reaped. This clears an orphaned `mount_macfuse` helper that would otherwise block the mount point for about a minute.

Disconnect flow highlights:
- Unmount via `UnmountService` with multiple command rounds (`diskutil`, `umount`, force variants).
- Minimum transition visibility (~0.7s).
- If outer disconnect times out, VM can trigger `forceStopProcesses` for scoped sshfs cleanup.

Busy unmount UX:
- On busy/resource-busy, `lsof` blockers are parsed and surfaced as user-facing process hints.
- No kill action for arbitrary user processes.

Mount inspection anti-flap logic (important):
- `refreshStatus` does not immediately downgrade a previously-connected mount on one probe miss.
- Uses `df` fallback + responsive path check (`stat`) + brief (250ms) retry before declaring disconnect.
- If the mount is missing from the mount table but the path is still responsive, connected state is preserved for up to `maxConnectedPreserveMisses = 4` consecutive checks, then status becomes `error` ("Mount could not be verified") so reconnect performs cleanup.
- If the refresh task is cancelled (routine supersession during recovery bursts), `refreshStatus` returns the cached status instead of synthesizing an error from `CancellationError`.
- This avoids false reconnect storms from transient mount table probe failures.

Command builder nuances:
- Base options: `reconnect`, `ServerAliveInterval=15`, `ServerAliveCountMax=3`, `defer_permissions`, `auto_cache`, `StrictHostKeyChecking=accept-new`, `ConnectTimeout=10`, `volname=...`.
- Do not add `noappledouble` / `noapplexattr`. They were removed in v0.1.36 because they broke Finder and `cp` copies that need the AppleDouble/xattr fallback.
- Cache modes (per remote `disableLocalCaches`, editor label `Prioritize freshness over speed`):
  - `true` (default): `nolocalcaches`.
  - `false` (fast mode): `attr_timeout`/`entry_timeout`/`cache_timeout=120`, `cache_max_size=50000`, plus `dir_cache=yes` + `dcache_*` (newer sshfs) or `cache_stat/dir/link_timeout` (older sshfs), depending on detected `SSHFSCapabilities`.
- The sshfs source path always ends in `/` (`user@host:/path/`) so a remote directory that is a symlink mounts its target directory rather than the link itself.
- ProxyJump (when `proxyJumpEnabled` and non-empty):
  - `.privateKey` / `.systemSSH`: added as `-o ProxyJump=...`.
  - `.password`: appended inside the pinned `ssh_command=...` string.
  - `ValidationService` rejects empty values, control characters, and whitespace (multi-hop uses commas).
- Windows path normalization for sshfs source path.
- Stable `volname` derivation from display name + remote path leaf.
- Password mode now disables public-key fallback and prefers password-style auth
  (`keyboard-interactive,password`) with a single prompt so a wrong password
  cannot silently succeed through agent/config-driven auth.
- On the current Homebrew macOS sshfs build, these password-mode auth controls
  are injected through `ssh_command=/usr/bin/ssh -o ...`, not as raw
  `-o PubkeyAuthentication=...` mount options, because that binary rejects the
  latter at the FUSE parser layer.
- Keep `keyboard-interactive` enabled unless you are intentionally dropping
  support for servers that expose password prompts through that path.
- IPv6 host addresses are bracketed (`[::1]`) via `sshHostArgument()` in both the sshfs source arg (`MountCommandBuilder`) and the process-search connection needle (`MountManager.forceStopProcesses`). `ValidationService` enforces pre-bracketed input at the save boundary; `sshHostArgument()` is defence-in-depth for any path that bypasses validation.

df path decoding:
- `MountStateParser.decodeEscapedMountField` is the canonical decoder for macOS `mount` and `df` escape sequences.
- Handles the full octal range `\001`–`\377`. Do not replace with ad-hoc single-character substitution (`\040` → space only).
- Used by both `MountManager` (df-path comparison in `currentMountRecordViaDF`) and `UnmountService` (df-based mount confirmation).

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
  - `acquire()` is `async throws` and cancellation-aware: a task cancelled while queued is removed from the FIFO and resumed with `CancellationError`, so superseded operations do not delay the ones behind them.
  - `runOperation` bails out on that error without registering a `release()` for a slot it never held.

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
- Disconnect inner timeout path: `8s`
- sshfs connect command timeout: `20s`
- Unmount total / per-command cap: `10s` / `3s`

Most of these live in `RuntimeConfiguration` (`macfuseGui/App/AppEnvironment.swift`), which also holds the 15s periodic recovery interval, the 60s healthy-probe interval, and the browser circuit-breaker threshold and window. The inner connect/disconnect timeouts are constants in `RemotesViewModel`.

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

Event handling details:
- Wake: `handleSystemDidWake` stores a single `wakePreflightTask`, cancelling any earlier one first. It runs a parallel fast force-unmount of desired remotes (`performWakePreflightCleanup`), then schedules the wake burst.
  - While `wakePreflightInProgress` is set, external-unmount notifications are ignored.
- Network lost: debounce `0.5s`, cancel scheduled reconnects and any recovery burst, then run fast cleanup in `networkLossCleanupTask`.
- Network restored: debounce `1.5s`, cancel pending network-loss cleanup, run deferred startup auto-connect first, then schedule the network-restored burst.
- External unmount: ignored for remotes not in `desiredConnections`, during wake preflight, or while a connect/disconnect is active. Otherwise the remote is marked disconnected and `scheduleAutoReconnect` runs.
- Sleep, termination, and deinit cancel `wakePreflightTask`, `networkLossCleanupTask`, and bursts.

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

Favorite remotes:
- Each remote row in the menu popover has a star toggle (`RemotesViewModel.toggleFavorite`) that persists `RemoteConfig.isFavorite`.
- `RemotesViewModel.sortedRemotes` orders favorites first, then by display name (case-insensitive), then by UUID for stability.
- Not to be confused with `favoriteRemoteDirectories`, which are per-remote browser path favorites (§15).

## 10) Settings, Editor, and UX Nuances

Settings window:
- Explicit open only from menu action.
- Shows launch-at-login state, including approval/fallback details.
- Optional custom sshfs path override field (see §6 backend resolution).
- Includes entry point button that opens a dedicated `Editor Plugins` window.
- `BaseSettingsWindowController` uses `NSHostingController.sizingOptions = [.minSize, .maxSize]`.
  - Do not add `.preferredContentSize`. Binding SwiftUI's preferred size back into AppKit constraints caused the settings window sizing bug on macOS betas.
  - Size windows from SwiftUI `.frame(min…/ideal…/max…)`, not hardcoded pixel sizes.

Remote detail panel:
- Edit, Duplicate, Delete, Refresh, Connect, Disconnect.
- Connect/Disconnect buttons are state-aware and disabled appropriately.

Editor (`RemoteEditorView`):
- Add/Edit title, password eye toggle, auth mode picker (SSH Private Key / System SSH / Password).
- `Auto-connect on app launch` toggle.
- `Prioritize freshness over speed` toggle (`disableLocalCaches`; on by default, turn off for faster dev/code mounts).
- `Use jump host (ProxyJump)` toggle + value field.
- `Browse Remote…` is disabled for `System SSH` and when ProxyJump is active, with an inline callout explaining why (see §12 auth support).
- `Test Connection` button with in-place progress/result.
- Both Cancel button and top-right close icon are present.
- Remote browser opens in sheet; session closed on sheet dismiss.
- Responds to `.forceQuitRequested` to close cleanly during hard quit.

Validation + uniqueness:
- Display name unique (case-insensitive).
- Local mountpoint unique (normalized, case-insensitive).
- Remote path supports UNIX and Windows drive forms.
- Validation is lexical only. Do not add `fileExists` / `isReadableFile` probes, because they can block the main actor on stale FUSE paths. `MountManager` does bounded filesystem checks during connect/test.

Localization:
- User-facing strings go through `L10n.tr` / `L10n.format` (`macfuseGui/App/L10n.swift`) backed by `macfuseGui/Resources/Localizable.xcstrings`.
- Development region `en`. Shipped locales: `de`, `es`, `fr`, `ja`, `ko`, `pt-BR`, `zh-Hans`.
- Diagnostics log messages and raw external command output stay unlocalized so support data is stable.
- Translation rules: `docs/LOCALIZATION_GLOSSARY.md`. `LocalizationTests` checks declared locales and core translated keys.

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
- Per-plugin external remove action (`trash`) deletes external manifest files (built-ins are non-removable)

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

Auth support:
- Browser supports `.password` and `.privateKey` only.
- `.systemSSH` is rejected in `LibSSH2SFTPTransport` because libssh2 cannot use the OpenSSH agent/config resolution.
- ProxyJump is not tunnelled by libssh2. The editor disables `Browse Remote…` when ProxyJump is active.

Host-key verification (`macfusegui_verify_host_key` in `LibSSH2Bridge.c`):
- Runs after the SSH handshake and before any authentication.
- Checks the server key against `~/.ssh/known_hosts` (`[host]:port` form for non-22 ports).
- Match: proceed.
- Mismatch: hard failure with the offered key's SHA256 fingerprint and a possible-MITM warning.
- Not found: trust on first use. The key is added and written back to `~/.ssh/known_hosts`, creating `~/.ssh` if needed. This matches the `StrictHostKeyChecking=accept-new` policy used by sshfs mounts.
- A missing `known_hosts` file is treated as empty (trust on first use). Any other read failure, a write failure, or an unsupported key type is a hard error. It never silently skips verification.

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
- `store`, `mount`, `mount-test`, `unmount`, `recovery`, `operations`, `remote-browser`, `startup`, `editor`, `vscode`, `diagnostics`, `app`

No secrets in diagnostics:
- Askpass and passwords are redacted or omitted.

## 18) Build, Run, Clean, and Third-Party Prep

Primary scripts:
- `scripts/build.sh`
- `scripts/run.sh`
- `scripts/clean.sh`
- `scripts/build_libssh2.sh`
- `scripts/release.sh`

Build arch modes:
- `ARCH_OVERRIDE=arm64|x86_64|both|universal`
- `scripts/build.sh` defaults to `arm64`
- `scripts/release.sh` defaults to `both` (publishes separate arm64 and x86_64 DMGs)

libssh2 prep:
- Output roots:
  - `build/third_party/libssh2-arm64`
  - `build/third_party/libssh2-x86_64`
  - `build/third_party/libssh2-universal`
- OpenSSL output roots:
  - `build/third_party/openssl-arm64`
  - `build/third_party/openssl-x86_64`
  - `build/third_party/openssl-universal`
- `scripts/build_libssh2.sh` builds OpenSSL and libssh2 from source for the active arch/deployment target
- Single-arch `x86_64` third-party builds run under Rosetta on Apple Silicon (`arch -x86_64`)
- Source tarballs are cached under `third_party/src` (`openssl-<version>.tar.gz`, `libssh2-<version>.tar.gz`) and auto-downloaded if missing
- Tarballs are pinned by SHA256 (`OPENSSL_SHA256` / `LIBSSH2_SHA256` in `scripts/build_libssh2.sh`, overridable via env).
  - Both cached and freshly downloaded tarballs are verified.
  - On mismatch the tarball is deleted and the build aborts.
  - When bumping `OPENSSL_VERSION` or `LIBSSH2_VERSION`, update the matching hash in the same change.
- Build artifacts are cached by a fingerprint (`version`, `arch`, `min target`) so repeated builds are fast
- `scripts/build.sh` also updates compatibility symlinks:
  - `build/third_party/openssl` -> selected `openssl-<arch>`
  - `build/third_party/libssh2` -> selected `libssh2-<arch>`

App output:
- Single-arch modes (`arm64`, `x86_64`, `universal`): `build/macfuseGui.app`
- Dual-arch mode (`both`):
  - `build/macfuseGui-arm64.app`
  - `build/macfuseGui-x86_64.app`
- DerivedData roots are arch-specific:
  - `build/DerivedData-arm64`
  - `build/DerivedData-x86_64`
  - `build/DerivedData-universal`

Release automation:
- `scripts/release.sh` is the single source of truth for versioning, DMG creation, Homebrew cask update, release notes, tags, and GitHub Release publishing.
- `.github/workflows/release-macos.yml` (`workflow_dispatch`, `macos-26` runner) runs `scripts/release.sh`, passing arch, configuration, version, dry-run, and packaging options as env/args.
- Windows entry point: `scripts\release.cmd` → `scripts/release.ps1`. It requires a clean work tree and a non-detached branch, checks origin reachability and `gh auth status`, pushes the current branch, then dispatches `release-macos.yml` on that ref.
  - Supports `-Arch`, `-ReleaseVersion`, `-DryRun`, `-SkipBuild`, `-NoHomebrewCask`, and related options.
- Neither the workflow nor `scripts/release.sh` runs `audit_mount_calls.py` or the XCTest suite, and `xcodebuild` is not available on Windows. Run the reliability gate on a Mac before dispatching a release.

Tests:
- `ARCH_OVERRIDE=arm64 ./scripts/build.sh` then `xcodebuild ... test CODE_SIGNING_ALLOWED=NO`
- Reliability gate: `ARCH_OVERRIDE=arm64 ./scripts/build.sh && scripts/audit_mount_calls.py && xcodebuild -project macfuseGui.xcodeproj -scheme macfuseGui -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO`
- After tests complete, remove temporary DerivedData roots under `build/` (for example: `build/DerivedData*`) to keep the workspace clean.
- Key tests cover:
  - Remote store legacy defaults/new fields
  - Path normalization and memory limits
  - Browser empty confirmation + recovery behavior
  - Keepalive-triggered recovery
  - Unmount blocker parsing
  - Mount arg safety and Windows path normalization
  - Auth-mode and ProxyJump arg building, trailing-slash source path, capability-based cache options (`MountArgBuilderTests`)
  - ProxyJump, IPv6, and auth validation rules (`ValidationServiceTests`)
  - `OperationLimiter` cancellation and wake-preflight dedup (`RemotesViewModelHelpersTests`)
  - Recovery flows (`RemotesViewModelRecoveryTests`)
  - Cancelled refresh preserving cached status and mount-detection edge cases (`ProcessRunnerTests`)
  - LaunchAgent fallback bootstrap/verification failures (`LaunchAtLoginServiceTests`)
  - Localization catalog locales and core keys (`LocalizationTests`)

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
13. `KeychainService.readPassword` trims whitespace before returning — prevents silent auth failures from clipboard-pasted trailing newlines without changing the stored credential.
14. `sshHostArgument()` brackets IPv6 host addresses in both the sshfs source arg and the connection-needle process search — prevents ambiguous `user@::1:/path` colons from breaking sshfs and process matching.
15. `if !Task.isCancelled` guards in the defer blocks of `scheduleRecoveryBurst`, `scheduleAutoReconnect`, `wakePreflightTask`, and `networkLossCleanupTask` — prevents a cancelled task's cleanup from clobbering the replacement task's reference on the next main-actor turn.
16. Cancellation-aware `OperationLimiter.acquire()` — cancelled waiters leave the FIFO immediately instead of delaying later operations.
17. Cancelled `refreshStatus` returns the cached status — superseded recovery refreshes never flash a synthetic error chip.
18. Password-mode auth pinning inside `ssh_command=/usr/bin/ssh -o ...` — a wrong password cannot silently succeed via key/agent fallback.
19. Trailing `/` on the sshfs source path — directory symlinks mount their target, not the link.
20. Browser host-key verification against `~/.ssh/known_hosts` before authentication (trust-on-first-use, hard fail on mismatch).
21. SHA256-pinned OpenSSL/libssh2 source tarballs — builds refuse unexpected inputs.
22. Foreground `sshfs -f` launched in its own session with process-group cleanup — works with macFUSE 5.4+ (no fork after mount), keeps mounts alive after the app quits, and never leaves orphaned mount helpers.

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
18. Keep `KeychainService.readPassword` trimming — do not return the raw stored value with surrounding whitespace intact.
19. Keep `sshHostArgument()` wrapping in `MountCommandBuilder.build` and `MountManager.forceStopProcesses` — do not interpolate `remote.host` directly into `user@host:path` strings.
20. Keep `if !Task.isCancelled` guards in the defer blocks of `scheduleRecoveryBurst`, `scheduleAutoReconnect`, `wakePreflightTask`, and `networkLossCleanupTask` — removing them reintroduces the stale-defer clobber of replacement task references.
21. When taking fixes from an external PR, preserve contributor attribution in commit bodies, release notes, and PR comments. Do not call Xcode-generated `.xcstrings` or `.pbxproj` changes "churn"; Xcode 15+ can rewrite those files as normal project metadata.
22. Keep password-mode auth controls inside `ssh_command=...`; do not move them to raw `-o PubkeyAuthentication=...` mount options (the Homebrew sshfs build rejects them).
23. Do not re-add `noappledouble` / `noapplexattr` to base mount options; they break Finder/`cp` copies.
24. Keep the trailing `/` on the sshfs source path.
25. Keep browser host-key verification before authentication; never skip it on read/write errors.
26. Keep SHA256 pinning in `scripts/build_libssh2.sh`; update the hash whenever the OpenSSL or libssh2 version changes.
27. Keep `OperationLimiter.acquire()` cancellation-aware and do not `release()` a slot that was never acquired.
28. Keep `ValidationService` lexical-only; no synchronous filesystem probes on the main actor.
29. Route new user-facing strings through `L10n`; keep diagnostics log messages unlocalized.
30. Keep `-f` in `MountCommandBuilder` and launch sshfs through `ProcessRunning.launchDetached`. Do not go back to waiting for sshfs to exit, and do not run the mount through Foundation `Process`: the child would share the app's process group, where launchd's job cleanup can kill it.
31. Only signal a detached process group while its leader is unreaped (`SpawnedDetachedProcess.exitState` uses `WNOWAIT`), so a reused PID is never signalled.
