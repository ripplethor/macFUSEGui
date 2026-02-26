# Contributing Guide

This guide is for developers who are new to this codebase.

## License

Contributions are accepted under the GNU General Public License v3.0 (GPLv3). By contributing, you agree that your contributions are licensed under GPLv3, consistent with the rest of the project.
See [`LICENSE`](./LICENSE).

## 1) Read Before Editing

Start here, in this order:
1. `README.md` for build/run/test commands.
2. `ARCHITECTURE.md` for system flow.
3. `AGENTS.md` for safety contracts and invariants.
4. `COMMIT_WORKFLOW.md` before committing (message format, changelog prefix rules).

If your change touches connection logic, recovery, or browser sessions, read all three first.

## 2) Setup and Build

From repo root:

```bash
./scripts/build.sh
./scripts/run.sh
```

## 3) Reliability Gate (Required)

Before finishing a change, run:

```bash
scripts/audit_mount_calls.py && xcodebuild -project macfuseGui.xcodeproj -scheme macfuseGui -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' test CODE_SIGNING_ALLOWED=NO
```

Why:
- `audit_mount_calls.py` enforces explicit `operationID` forwarding into `MountManager` calls.
- Tests cover concurrency, timeout handling, recovery behavior, and browser/session invariants.

## 4) High-Risk Areas

Treat these as sensitive:
- `RemotesViewModel` operation supervision logic
- `MountManager` connect/disconnect/refresh behavior
- `UnmountService` timeout and cleanup behavior
- `KeychainService` password read/write behavior (trimming policy, cache coherence)
- Browser session actors and request-ordering logic
- App startup/quit lifecycle in `AppDelegate`

## 5) Safety Rules

Do not break these rules:
1. One active operation per remote ID.
2. Cross-remote operations can run in parallel (bounded by limiter).
3. `desiredConnections` remains the source of recovery intent.
4. No shell interpolation for user-controlled inputs.
5. No password or secret logging.
6. Preserve anti-flap refresh behavior.
7. Preserve browser sticky-cache and empty-confirm behavior.
8. Keep `KeychainService.readPassword` whitespace trimming — do not return the raw stored value.
9. Keep `sshHostArgument()` wrapping in `MountCommandBuilder` and `MountManager` — do not interpolate `remote.host` directly into `user@host:path` strings.
10. Keep `if !Task.isCancelled` guards in the defer blocks of `scheduleRecoveryBurst` and `scheduleAutoReconnect`.

## 6) Diagnostics for Bug Reports

If reporting a bug, include:
1. App menu -> `Copy Diagnostics` output.
2. Steps to reproduce.
3. Whether the issue happened after wake/sleep, network change, or manual action.
