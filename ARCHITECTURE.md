# Architecture Guide

This file explains how `macfuseGui` is wired today, using the current code paths.

## 1) Runtime Map

`macfuseGui` is a menu-bar-only macOS app (`LSUIElement=true`).

Main entry points:
- `macfuseGui/App/macfuseGuiApp.swift`
- `macfuseGui/App/AppDelegate.swift`
- `macfuseGui/App/AppEnvironment.swift`

Main orchestration layer:
- `macfuseGui/ViewModels/RemotesViewModel.swift`

Main service layers:
- Mount stack:
  - `macfuseGui/Services/MountManager.swift`
  - `macfuseGui/Services/UnmountService.swift`
  - `macfuseGui/Services/ProcessRunner.swift`
- Browser stack:
  - `macfuseGui/Services/RemoteDirectoryBrowserService.swift`
  - `macfuseGui/Services/Browser/RemoteBrowserSessionManager.swift`
  - `macfuseGui/Services/Browser/LibSSH2SessionActor.swift`
  - `macfuseGui/Services/Browser/LibSSH2SFTPTransport.swift`
  - `macfuseGui/Services/Browser/LibSSH2Bridge.c`

## 2) Startup and Single-Instance Guarantees

`AppDelegate.applicationDidFinishLaunching` does four critical things before normal app setup:
1. Skips full startup when running under XCTest host.
2. Acquires singleton lock file (`/tmp/com.visualweb.macfusegui.instance.lock`) with `flock`.
3. Detects duplicate app instances (bundle ID, executable name, localized name) and activates old instance.
4. Terminates duplicate current process when needed.

Why this exists:
- Prevent duplicate status bar icons.
- Prevent test-host processes from creating real menu UI or recovery timers.

## 3) State Ownership

`RemotesViewModel` owns user-facing runtime state:
- `remotes` (saved configs)
- `statuses` (live connection state)
- `desiredConnections` (user intent for recovery)
- recovery timers/tasks
- operation supervision table (`remoteOperations`)

Rule:
- All remote lifecycle decisions flow through `RemotesViewModel`.

## 4) Operation Supervisor Model

The app uses per-remote supervision.

One active operation per remote ID:
- `connect`
- `disconnect`
- `refresh`
- `testConnection`

Cross-remote concurrency:
- Allowed in parallel.
- Bounded by `OperationLimiter(maxConcurrent: 4)`.
- Waiting in the limiter is cancellation-aware: a superseded operation leaves the queue immediately instead of delaying the ones behind it.

Conflict policy:
- Manual actions use `latestIntentWins`.
- Recovery refresh paths use `skipIfBusy`.

Watchdogs:
- Each operation has watchdog timeout handling.
- Timed-out operations are cancelled and logged with operation ID.

## 5) Mount Pipeline

### Connect
`RemotesViewModel.performConnect`:
1. Validates mount-point uniqueness.
2. Sets status `connecting`.
3. Resolves password from Keychain (password mode).
4. Calls `MountManager.connect` with timeout guard.
5. Applies final state (`connected` or `error`).

`MountCommandBuilder` turns a `RemoteConfig` into sshfs arguments:
- Auth mode:
  - `SSH Private Key` → `IdentityFile=...`
  - `System SSH` → no key; OpenSSH agent/config decides
  - `Password` → auth pinned inside `ssh_command=/usr/bin/ssh -o ...`
- Optional `ProxyJump`.
- Cache mode:
  - `nolocalcaches` by default
  - timed metadata caches when freshness is turned off, using `sshfs -h` capability detection
- The source path always ends in `/`, so symlinked remote directories mount their target.

### Disconnect
`RemotesViewModel.performDisconnect`:
1. Removes remote from `desiredConnections`.
2. Sets status `disconnecting`.
3. Calls `MountManager.disconnect`.
4. On timeout, calls `forceStopProcesses` then `refreshStatus`.
5. Applies final state (`disconnected` or `error`).

### Refresh
`MountManager.refreshStatus` performs anti-flap checks:
- mount table probe (`mount` parsing)
- responsiveness probe (`stat`)
- fallback `df` probe
- brief retry before downgrade

If the mount is missing from the mount table but the path still responds, `connected` is kept for up to 4 consecutive misses before the remote is marked `error` for cleanup and reconnect. A cancelled refresh returns the last cached status rather than an error.

This prevents false dropouts and reconnect storms from single probe misses.

Mount path escape decoding:
- `MountStateParser.decodeEscapedMountField` is the canonical decoder for macOS `mount` and `df -P` escape sequences.
- Handles full octal range `\001`–`\377`. Both `MountManager` and `UnmountService` use it for df-based path comparisons.

## 6) Why MountManager Is Instrumented

`MountManager` is an actor. Actor safety alone does not prove there is no practical bottleneck.

To make behavior measurable, logs include:
- `mount call ... queuedAtMs ... opAgeMs ...` (from `RemotesViewModel` before await)
- `actor enter op=... queueDelayMs=...` (inside `MountManager`)
- probe windows with `remoteID` and `operationID`:
  - `mount-inspect`
  - `df-inspect`
  - `mount-responsive-check`
  - `sshfs-connect`

This lets you prove overlap versus serialization from one log stream.

## 7) Recovery Engine

Recovery acts on `desiredConnections` only.

Triggers:
- periodic timer (15s)
- wake notifications
- network restored notifications
- external unmount notifications

Burst retries:
- wake: `0s, 1s, 3s, 8s`
- network restore: `0s, 2s, 6s`

Before the bursts:
- Wake runs one deduplicated preflight cleanup (parallel fast force-unmount of desired remotes). External-unmount events are ignored while it runs.
- Network loss cancels pending reconnects and runs a fast cleanup after a 0.5s debounce.
- Network restore waits 1.5s, then runs any deferred startup auto-connect before its burst.

Periodic deep checks are skipped when all desired remotes are stable.

Timing thresholds (watchdogs, periodic intervals, unmount caps, browser circuit breaker) are centralized in `RuntimeConfiguration` in `macfuseGui/App/AppEnvironment.swift`.

## 8) Browser Architecture

Browser sessions are separate from mount lifecycle.

Flow:
1. UI opens browser sheet.
2. `RemoteBrowserViewModel` opens a session via `RemoteDirectoryBrowserService`.
3. `LibSSH2SessionActor` handles retries, health, sticky cache.
4. `LibSSH2SFTPTransport` talks to native C bridge (`LibSSH2Bridge.c`).

Reliability contract:
- stale cache is shown during reconnect windows
- empty folder is confirmation-checked before treated as true empty
- stale request responses are dropped by monotonic request ID

Security and auth:
- After the SSH handshake and before authentication, the C bridge checks the host key against `~/.ssh/known_hosts`. Unknown hosts are trusted on first use and recorded; a mismatch is a hard failure.
- Only `Password` and `SSH Private Key` auth are supported. `System SSH` and `ProxyJump` remotes cannot use the browser yet.

## 9) Persistence and Security

Config store:
- `~/Library/Application Support/macfuseGui/remotes.json`
- `RemoteStore` is `@MainActor`

Secrets:
- Keychain only (`com.visualweb.macfusegui.password`)
- `KeychainService.readPassword` trims leading/trailing whitespace before returning and returns `nil` for whitespace-only values. This prevents silent SSH auth failures from clipboard-pasted trailing newlines without modifying what is stored in Keychain.

Security rules:
- no plaintext password persistence
- no shell interpolation
- command execution via `Process` argument arrays
- diagnostics are redacted

## 10) Quit Semantics

Quit path is intentionally forceful to avoid hung app states:
1. Post `.forceQuitRequested`.
2. Close sheets/modals/windows aggressively.
3. Await `prepareForTermination` in `RemotesViewModel`.
4. Call `NSApp.terminate`.
5. Fallback `_exit(0)` timer if app does not exit.

## 11) Developer Reliability Gate

Run from repo root:

```bash
ARCH_OVERRIDE=arm64 ./scripts/build.sh
scripts/audit_mount_calls.py && xcodebuild -project macfuseGui.xcodeproj -scheme macfuseGui -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO
```

Purpose:
- Ensures `MountManager` callsites explicitly forward `operationID`.
- Runs test suite for concurrency, timeout, and recovery regressions.

See `COMMIT_WORKFLOW.md` for commit message format and changelog rules before pushing.
