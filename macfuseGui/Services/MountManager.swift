// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Uses a Swift actor for data-race safety; methods can interleave at suspension points (await) without shared-memory locks.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

// MountManager is the low-level mount lifecycle engine.
// It does not present UI. It only returns structured status and errors.
// View models decide what to show to users.
//
// Why actor:
// - Connect/disconnect/refresh can overlap from menu actions, recovery, and startup.
// - Actor isolation keeps status cache updates race-safe.
// - Slow external operations are bounded by hard timeouts so one task does not wedge forever.
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
actor MountManager {
    private let runner: ProcessRunning
    private let dependencyChecker: DependencyChecking
    private let askpassHelper: AskpassHelper
    private let unmountService: UnmountService
    private let mountStateParser: MountStateParser
    private let diagnostics: DiagnosticsService
    private let commandBuilder: MountCommandBuilder
    private let mountInspectionAttempts = 1
    // Keep mount inspection probes short. These are "status checks", not full recovery work.
    private let mountInspectionCommandTimeout: TimeInterval = 1.5
    private let mountInspectionFallbackTimeout: TimeInterval = 1.5
    private let mountResponsivenessTimeout: TimeInterval = 1.5
    private let sshfsConnectCommandTimeout: TimeInterval = 20
    private let forceStopProcessListTimeout: TimeInterval = 3

    // Internal status cache so callers can ask current state without rerunning probes.
    private var statuses: [UUID: RemoteStatus] = [:]

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        runner: ProcessRunning,
        dependencyChecker: DependencyChecking,
        askpassHelper: AskpassHelper,
        unmountService: UnmountService,
        mountStateParser: MountStateParser,
        diagnostics: DiagnosticsService,
        commandBuilder: MountCommandBuilder
    ) {
        self.runner = runner
        self.dependencyChecker = dependencyChecker
        self.askpassHelper = askpassHelper
        self.unmountService = unmountService
        self.mountStateParser = mountStateParser
        self.diagnostics = diagnostics
        self.commandBuilder = commandBuilder
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func status(for remoteID: UUID) -> RemoteStatus {
        cachedStatus(for: remoteID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func refreshStatus(
        remote: RemoteConfig,
        queuedAt: Date = Date(),
        operationID: UUID? = nil
    ) async -> RemoteStatus {
        if Task.isCancelled {
            return cachedStatus(for: remote.id)
        }

        logActorQueueDelay(op: "refreshStatus", remote: remote, queuedAt: queuedAt, operationID: operationID)

        do {
            // Normalize path once so comparisons do not fail due to equivalent path formats.
            let normalizedMountPoint = URL(fileURLWithPath: remote.localMountPoint).standardizedFileURL.path
            let previousStatus = cachedStatus(for: remote.id)
            var mountedRecord = try await currentMountRecord(
                for: remote.localMountPoint,
                remoteID: remote.id,
                operationID: operationID
            )

            // Guard against single-pass probe misses: if we were connected, do a fast
            // confirmation pass before transitioning to disconnected/recovery states.
            if mountedRecord == nil, previousStatus.state == .connected {
                if await isMountPathResponsive(remote.localMountPoint, remoteID: remote.id, operationID: operationID) {
                    let preserved = RemoteStatus(
                        state: .connected,
                        mountedPath: previousStatus.mountedPath ?? normalizedMountPoint,
                        lastError: nil,
                        updatedAt: Date()
                    )
                    updateCachedStatus(preserved, for: remote.id)
                    diagnostics.append(
                        level: .debug,
                        category: "mount",
                        message: "Preserved connected state for \(remote.displayName) using responsive mount-path check."
                    )
                    return preserved
                }

                if let dfRecord = try await currentMountRecordViaDF(
                    for: normalizedMountPoint,
                    remoteID: remote.id,
                    operationID: operationID
                ) {
                    mountedRecord = dfRecord
                } else {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    mountedRecord = try await currentMountRecord(
                        for: remote.localMountPoint,
                        remoteID: remote.id,
                        operationID: operationID
                    )
                }
            }

            if let mountedRecord {
                // Extra health probe: a mount can exist but be stale/hung.
                let health = try await runner.run(
                    executable: "/usr/bin/stat",
                    arguments: ["-f", "%N", remote.localMountPoint],
                    timeout: mountResponsivenessTimeout
                )

                if health.timedOut || health.exitCode != 0 {
                    // Important: refreshStatus should stay lightweight.
                    // Do not run full unmount cleanup in this probe path, because that can
                    // take tens of seconds and block mount status refresh flow.
                    diagnostics.append(level: .warning, category: "mount", message: "Stale mount detected at \(remote.localMountPoint). Marking as error for reconnect flow.")
                    let staleStatus = RemoteStatus(
                        state: .error,
                        mountedPath: nil,
                        lastError: "Detected stale mount. Reconnect will perform cleanup.",
                        updatedAt: Date()
                    )
                    updateCachedStatus(staleStatus, for: remote.id)
                    return staleStatus
                }

                let connected = RemoteStatus(
                    state: .connected,
                    mountedPath: mountedRecord.mountPoint,
                    lastError: nil,
                    updatedAt: Date()
                )
                updateCachedStatus(connected, for: remote.id)
                return connected
            }

            let disconnected = RemoteStatus(state: .disconnected, updatedAt: Date())
            updateCachedStatus(disconnected, for: remote.id)
            return disconnected
        } catch {
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = message.lowercased()

            if normalized.contains("failed to inspect mounts") {
                diagnostics.append(
                    level: .warning,
                    category: "mount",
                    message: "Refresh status probe failed for \(remote.displayName): \(message.isEmpty ? "unknown mount inspection failure" : message)."
                )

                let previous = cachedStatus(for: remote.id)
                if previous.state == .connected {
                    // Only preserve connected when the mounted path is still immediately
                    // responsive. If it is not responsive, force recovery to reconnect.
                    if await isMountPathResponsive(remote.localMountPoint, remoteID: remote.id, operationID: operationID) {
                        let preserved = RemoteStatus(
                            state: .connected,
                            mountedPath: previous.mountedPath,
                            lastError: nil,
                            updatedAt: Date()
                        )
                        updateCachedStatus(preserved, for: remote.id)
                        return preserved
                    }

                    let staleStatus = RemoteStatus(
                        state: .error,
                        mountedPath: nil,
                        lastError: "Mount verification failed. Reconnect will perform cleanup.",
                        updatedAt: Date()
                    )
                    updateCachedStatus(staleStatus, for: remote.id)
                    return staleStatus
                }

                let disconnected = RemoteStatus(
                    state: .disconnected,
                    mountedPath: nil,
                    lastError: nil,
                    updatedAt: Date()
                )
                updateCachedStatus(disconnected, for: remote.id)
                return disconnected
            }

            let status = RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: error.localizedDescription,
                updatedAt: Date()
            )
            updateCachedStatus(status, for: remote.id)
            return status
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func connect(
        remote: RemoteConfig,
        password: String?,
        queuedAt: Date = Date(),
        operationID: UUID? = nil
    ) async -> RemoteStatus {
        if Task.isCancelled {
            return cachedStatus(for: remote.id)
        }

        logActorQueueDelay(op: "connect", remote: remote, queuedAt: queuedAt, operationID: operationID)

        let connectBeganAt = Date()
        // Set transitional state immediately so UI can show "connecting".
        setStatus(for: remote.id, state: .connecting, mountedPath: nil, lastError: nil)

        let dependency = dependencyChecker.check(sshfsOverride: nil)
        guard dependency.isReady, let sshfsPath = dependency.sshfsPath else {
            let status = RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: dependency.userFacingMessage,
                updatedAt: Date()
            )
            updateCachedStatus(status, for: remote.id)
            diagnostics.append(level: .error, category: "mount", message: dependency.userFacingMessage)
            return status
        }

        do {
            try throwIfCancelled()
            // If mount path is already mounted, clear stale/previous mount before reconnect.
            let existingMountRecord: MountRecord?
            do {
                existingMountRecord = try await currentMountRecord(
                    for: remote.localMountPoint,
                    remoteID: remote.id,
                    operationID: operationID
                )
            } catch {
                // Pre-connect inspection is best-effort. If probing mount state is flaky
                // right after wake, still attempt connect so recovery does not stall.
                existingMountRecord = nil
                diagnostics.append(
                    level: .warning,
                    category: "mount",
                    message: "Pre-connect mount inspection failed for \(remote.displayName) at \(remote.localMountPoint). Continuing with connect attempt: \(error.localizedDescription)"
                )
            }

            if existingMountRecord != nil {
                diagnostics.append(level: .info, category: "mount", message: "Pre-connect cleanup for \(remote.localMountPoint)")
                let mountResponsive = await isMountPathResponsive(
                    remote.localMountPoint,
                    remoteID: remote.id,
                    operationID: operationID
                )
                if !mountResponsive {
                    diagnostics.append(
                        level: .warning,
                        category: "mount",
                        message: "Pre-connect mount is unresponsive for \(remote.displayName). Using force-stop cleanup."
                    )
                }

                // Avoid deep unmount/lsof flows in reconnect path. A quick scoped kill+force-unmount
                // keeps wake/recovery responsive and prevents stale mounts from hanging Finder.
                await forceStopProcesses(for: remote, queuedAt: Date(), operationID: operationID)
            }

            try throwIfCancelled()
            try ensureLocalMountPointReady(remote.localMountPoint)

            let status = try await connectWithRetry(
                remote: remote,
                password: password,
                sshfsPath: sshfsPath,
                operationID: operationID
            )
            try await enforceMinimumTransitionVisibility(since: connectBeganAt, minimumSeconds: 0.8)
            updateCachedStatus(status, for: remote.id)
            return status
        } catch {
            try? await enforceMinimumTransitionVisibility(since: connectBeganAt, minimumSeconds: 0.8)
            let status = RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: error.localizedDescription,
                updatedAt: Date()
            )
            updateCachedStatus(status, for: remote.id)
            diagnostics.append(level: .error, category: "mount", message: "Connect failed for \(remote.displayName): \(error.localizedDescription)")
            return status
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func testConnection(
        remote: RemoteConfig,
        password: String?,
        queuedAt: Date = Date(),
        operationID: UUID? = nil
    ) async throws -> String {
        try throwIfCancelled()
        logActorQueueDelay(op: "testConnection", remote: remote, queuedAt: queuedAt, operationID: operationID)
        let dependency = dependencyChecker.check(sshfsOverride: nil)
        guard dependency.isReady, let sshfsPath = dependency.sshfsPath else {
            throw AppError.dependencyMissing(dependency.userFacingMessage)
        }

        if try await currentMountRecord(
            for: remote.localMountPoint,
            remoteID: remote.id,
            operationID: operationID
        ) != nil {
            // Test mode is intentionally non-destructive; never hijack an active mount.
            throw AppError.validationFailed([
                "Mount point is already mounted: \(remote.localMountPoint). Disconnect it first, then run Test Connection."
            ])
        }

        try ensureLocalMountPointReady(remote.localMountPoint)

        var mountedDuringTest = false
        do {
            // Reuse real connect path so test result matches production behavior.
            _ = try await connectAttempt(
                remote: remote,
                password: password,
                sshfsPath: sshfsPath,
                updateStoredStatus: false,
                operationID: operationID
            )
            mountedDuringTest = true

            try await unmountService.unmount(mountPoint: remote.localMountPoint)
            try await waitForUnmount(mountPoint: remote.localMountPoint, timeoutSeconds: 10)

            return "Connection test succeeded. Mount and unmount completed for \(remote.displayName)."
        } catch {
            let stillMounted: Bool
            if mountedDuringTest {
                stillMounted = true
            } else {
                stillMounted = (try? await currentMountRecord(
                    for: remote.localMountPoint,
                    remoteID: remote.id,
                    operationID: operationID
                )) != nil
            }

            if stillMounted {
                // Best-effort cleanup so failed tests do not leave mounted artifacts.
                try? await unmountService.unmount(mountPoint: remote.localMountPoint)
                try? await waitForUnmount(mountPoint: remote.localMountPoint, timeoutSeconds: 6)
            }
            throw error
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func disconnect(
        remote: RemoteConfig,
        queuedAt: Date = Date(),
        operationID: UUID? = nil
    ) async -> RemoteStatus {
        if Task.isCancelled {
            return cachedStatus(for: remote.id)
        }

        logActorQueueDelay(op: "disconnect", remote: remote, queuedAt: queuedAt, operationID: operationID)

        let disconnectBeganAt = Date()
        // Set transitional state immediately for responsive UI feedback.
        setStatus(for: remote.id, state: .disconnecting, mountedPath: nil, lastError: nil)

        do {
            try throwIfCancelled()
            if (try? await currentMountRecord(
                for: remote.localMountPoint,
                remoteID: remote.id,
                operationID: operationID
            )) != nil {
                try await unmountService.unmount(mountPoint: remote.localMountPoint)
            }

            try throwIfCancelled()
            if (try? await currentMountRecord(
                for: remote.localMountPoint,
                remoteID: remote.id,
                operationID: operationID
            )) != nil {
                throw AppError.processFailure("Unmount did not complete for \(remote.localMountPoint).")
            }

            // Keep the transitional state visible long enough for live UI updates.
            try await enforceMinimumTransitionVisibility(since: disconnectBeganAt, minimumSeconds: 0.7)

            let status = RemoteStatus(
                state: .disconnected,
                mountedPath: nil,
                lastError: nil,
                updatedAt: Date()
            )
            updateCachedStatus(status, for: remote.id)
            return status
        } catch {
            let status = RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: error.localizedDescription,
                updatedAt: Date()
            )
            updateCachedStatus(status, for: remote.id)
            diagnostics.append(level: .error, category: "mount", message: "Disconnect failed for \(remote.displayName): \(error.localizedDescription)")
            return status
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func forceStopProcesses(
        for remote: RemoteConfig,
        queuedAt: Date = Date(),
        operationID: UUID? = nil,
        aggressiveUnmount: Bool = false
    ) async {
        logActorQueueDelay(op: "forceStopProcesses", remote: remote, queuedAt: queuedAt, operationID: operationID)
        let normalizedMountPoint = URL(fileURLWithPath: remote.localMountPoint).standardizedFileURL.path
        let connectionNeedle = "\(remote.username)@\(remote.host):\(remote.remoteDirectory)"

        do {
            let result = try await runner.run(
                executable: "/bin/ps",
                arguments: ["-axo", "pid=,command="],
                timeout: forceStopProcessListTimeout
            )

            if result.exitCode == 0 {
                var candidatePIDs: [Int32] = []
                for rawLine in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
                    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else {
                        continue
                    }

                    let components = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
                    guard components.count == 2 else {
                        continue
                    }

                    guard let pid = Int32(String(components[0])), pid > 1 else {
                        continue
                    }

                    let command = String(components[1]).replacingOccurrences(of: "\\040", with: " ")
                    let lower = command.lowercased()
                    guard lower.contains("sshfs") else {
                        continue
                    }

                    // Scope kill list to this remote only (mount path or remote connection needle).
                    if command.contains(normalizedMountPoint) || command.contains(connectionNeedle) {
                        candidatePIDs.append(pid)
                    }
                }

                let pids = Array(Set(candidatePIDs)).sorted()
                if !pids.isEmpty {
                    diagnostics.append(
                        level: .warning,
                        category: "mount",
                        message: "Force-stopping sshfs pid(s) \(pids.map(String.init).joined(separator: ",")) for \(remote.displayName)."
                    )

                    for signal in ["-TERM", "-KILL"] {
                        for pid in pids {
                            _ = try? await runner.run(
                                executable: "/bin/kill",
                                arguments: [signal, String(pid)],
                                timeout: 3
                            )
                        }
                        if signal == "-TERM" {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                        }
                    }
                } else {
                    diagnostics.append(
                        level: .debug,
                        category: "mount",
                        message: "No sshfs pid match found for \(remote.displayName); attempting force-unmount anyway."
                    )
                }
            } else {
                diagnostics.append(
                    level: .warning,
                    category: "mount",
                    message: "Process listing failed while force-stopping \(remote.displayName) (exit \(result.exitCode)); attempting force-unmount anyway."
                )
            }
        } catch {
            diagnostics.append(
                level: .warning,
                category: "mount",
                message: "Force-stop sshfs failed for \(remote.displayName): \(error.localizedDescription)"
            )
        }

        await forceUnmountMountPoint(
            remote.localMountPoint,
            remoteName: remote.displayName,
            aggressive: aggressiveUnmount
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func waitForUnmount(mountPoint: String, timeoutSeconds: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if try await currentMountRecord(for: mountPoint) == nil {
                return
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw AppError.timeout("Unmount did not complete in time for \(mountPoint).")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func enforceMinimumTransitionVisibility(since start: Date, minimumSeconds: TimeInterval) async throws {
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed < minimumSeconds else {
            return
        }
        let remaining = minimumSeconds - elapsed
        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func connectWithRetry(
        remote: RemoteConfig,
        password: String?,
        sshfsPath: String,
        operationID: UUID?
    ) async throws -> RemoteStatus {
        var attempt = 0
        var lastError: Error?

        while attempt < 2 {
            try throwIfCancelled()
            attempt += 1

            do {
                let status = try await connectAttempt(
                    remote: remote,
                    password: password,
                    sshfsPath: sshfsPath,
                    updateStoredStatus: true,
                    operationID: operationID
                )
                return status
            } catch {
                lastError = error
                let message = error.localizedDescription.lowercased()
                let shouldRetry = message.contains("resource busy")
                    || message.contains("transport endpoint")
                    || message.contains("operation timed out")
                    || message.contains("connection reset")
                    || message.contains("connection closed")
                    || message.contains("broken pipe")
                    || message.contains("network is unreachable")
                    || message.contains("no route to host")
                    || message.contains("temporary failure")

                if shouldRetry && attempt < 2 {
                    // Retry once after cleanup for transient transport/mount handoff failures.
                    diagnostics.append(level: .warning, category: "mount", message: "Retrying mount for \(remote.displayName) after cleanup.")
                    try? await unmountService.unmount(mountPoint: remote.localMountPoint)
                    try? ensureLocalMountPointReady(remote.localMountPoint)
                    continue
                }

                throw error
            }
        }

        throw lastError ?? AppError.unknown("Mount failed")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    private func ensureLocalMountPointReady(_ mountPoint: String) throws {
        let normalized = URL(fileURLWithPath: mountPoint).standardizedFileURL.path
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: normalized, isDirectory: &isDir)

        if exists {
            guard isDir.boolValue else {
                throw AppError.validationFailed(["Local mount point is not a directory: \(normalized)"])
            }
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: normalized, isDirectory: true),
                withIntermediateDirectories: true
            )
            diagnostics.append(level: .info, category: "mount", message: "Created missing local mount point: \(normalized)")
        } catch {
            throw AppError.validationFailed(["Local mount point does not exist and could not be created: \(normalized). \(error.localizedDescription)"])
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func connectAttempt(
        remote: RemoteConfig,
        password: String?,
        sshfsPath: String,
        updateStoredStatus: Bool,
        operationID: UUID?
    ) async throws -> RemoteStatus {
        try throwIfCancelled()
        var askpassCleanup: (() -> Void)?
        var passwordEnvironment: [String: String] = [:]

        if remote.authMode == .password {
            guard let password, !password.isEmpty else {
                throw AppError.validationFailed(["Password is required for password authentication."])
            }
            let askpass = try askpassHelper.makeContext(password: password)
            passwordEnvironment = askpass.environment
            askpassCleanup = askpass.cleanup
        }

        // Always clean temporary askpass helper files/env no matter how this method exits.
        defer {
            askpassCleanup?()
        }

        let command = commandBuilder.build(
            sshfsPath: sshfsPath,
            remote: remote,
            passwordEnvironment: passwordEnvironment
        )

        diagnostics.append(level: .info, category: "mount", message: "Running \(command.redactedCommand)")
        let commandStartedAt = Date()
        diagnostics.append(
            level: .debug,
            category: "mount",
            message: "probe start op=sshfs-connect remoteID=\(remote.id.uuidString) operationID=\(operationID?.uuidString ?? "-") mountPoint=\(remote.localMountPoint)"
        )

        let result = try await runner.run(
            executable: command.executable,
            arguments: command.arguments,
            environment: command.environment,
            timeout: sshfsConnectCommandTimeout
        )
        let commandElapsedMs = Int(Date().timeIntervalSince(commandStartedAt) * 1_000)
        diagnostics.append(
            level: .debug,
            category: "mount",
            message: "probe end op=sshfs-connect remoteID=\(remote.id.uuidString) operationID=\(operationID?.uuidString ?? "-") mountPoint=\(remote.localMountPoint) elapsedMs=\(commandElapsedMs) timedOut=\(result.timedOut) exit=\(result.exitCode)"
        )

        try throwIfCancelled()

        if result.timedOut {
            throw AppError.timeout("sshfs connect timed out.")
        }

        if result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawMessage = stderr.isEmpty ? stdout : stderr
            let message = friendlyMountError(rawMessage, remote: remote)
            throw AppError.processFailure(message.isEmpty ? "sshfs failed with exit code \(result.exitCode)" : message)
        }

        // After sshfs exits successfully, the mount should show up quickly.
        // Keeping this short prevents "phantom hangs" when the system is unstable.
        let detectionDeadline = Date().addingTimeInterval(5)
        while Date() < detectionDeadline {
            if Task.isCancelled {
                throw AppError.timeout("Mount operation was cancelled.")
            }

            do {
                if let record = try await currentMountRecord(
                    for: remote.localMountPoint,
                    remoteID: remote.id,
                    operationID: operationID
                ) {
                    let status = RemoteStatus(
                        state: .connected,
                        mountedPath: record.mountPoint,
                        lastError: nil,
                        updatedAt: Date()
                    )
                    if updateStoredStatus {
                        // Skip status cache updates in "test connection" mode.
                        updateCachedStatus(status, for: remote.id)
                    }
                    return status
                }
            } catch {
                // Mount-table probes can be flaky immediately after wake.
                // Keep trying until detection deadline instead of failing connect immediately.
                diagnostics.append(
                    level: .debug,
                    category: "mount",
                    message: "Post-connect mount detection retry for \(remote.displayName): \(error.localizedDescription)"
                )
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw AppError.processFailure("sshfs reported success, but mount was not detected.")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    private func throwIfCancelled() throws {
        if Task.isCancelled {
            throw AppError.timeout("Operation was cancelled.")
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    private func isMountPathResponsive(
        _ mountPoint: String,
        remoteID: UUID? = nil,
        operationID: UUID? = nil
    ) async -> Bool {
        let startedAt = Date()
        let remoteText = remoteID?.uuidString ?? "-"
        let operationText = operationID?.uuidString ?? "-"
        diagnostics.append(
            level: .debug,
            category: "mount",
            message: "probe start op=mount-responsive-check remoteID=\(remoteText) operationID=\(operationText) path=\(mountPoint)"
        )

        do {
            let result = try await runner.run(
                executable: "/usr/bin/stat",
                arguments: ["-f", "%N", mountPoint],
                timeout: mountResponsivenessTimeout
            )
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            diagnostics.append(
                level: .debug,
                category: "mount",
                message: "probe end op=mount-responsive-check remoteID=\(remoteText) operationID=\(operationText) path=\(mountPoint) elapsedMs=\(elapsedMs) timedOut=\(result.timedOut) exit=\(result.exitCode)"
            )
            return !result.timedOut && result.exitCode == 0
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            diagnostics.append(
                level: .debug,
                category: "mount",
                message: "probe end op=mount-responsive-check remoteID=\(remoteText) operationID=\(operationText) path=\(mountPoint) elapsedMs=\(elapsedMs) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func currentMountRecord(
        for mountPoint: String,
        remoteID: UUID? = nil,
        operationID: UUID? = nil
    ) async throws -> MountRecord? {
        let normalizedMountPoint = URL(fileURLWithPath: mountPoint).standardizedFileURL.path
        let remoteText = remoteID?.uuidString ?? "-"
        let operationText = operationID?.uuidString ?? "-"
        var lastFailure = "unknown failure"

        for attempt in 1...mountInspectionAttempts {
            try throwIfCancelled()
            let attemptStartedAt = Date()
            diagnostics.append(
                level: .debug,
                category: "mount",
                message: "probe start op=mount-inspect remoteID=\(remoteText) operationID=\(operationText) path=\(normalizedMountPoint) attempt=\(attempt)"
            )
            let mountResult = try await runner.run(
                executable: "/sbin/mount",
                arguments: [],
                timeout: mountInspectionCommandTimeout
            )
            try throwIfCancelled()
            let elapsedMs = Int(Date().timeIntervalSince(attemptStartedAt) * 1_000)
            diagnostics.append(
                level: .debug,
                category: "mount",
                message: "probe end op=mount-inspect remoteID=\(remoteText) operationID=\(operationText) path=\(normalizedMountPoint) attempt=\(attempt) elapsedMs=\(elapsedMs) timedOut=\(mountResult.timedOut) exit=\(mountResult.exitCode)"
            )

            if !mountResult.timedOut && mountResult.exitCode == 0 {
                let records = mountStateParser.parseMountOutput(mountResult.stdout)
                return mountStateParser.record(forMountPoint: normalizedMountPoint, from: records)
            }

            lastFailure = mountInspectionFailureDetail(from: mountResult)
            diagnostics.append(
                level: .warning,
                category: "mount",
                message: "Mount inspection attempt \(attempt) failed for remoteID=\(remoteText) operationID=\(operationText) path=\(normalizedMountPoint): \(lastFailure)"
            )

            if attempt < mountInspectionAttempts {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        if let fallback = try await currentMountRecordViaDF(
            for: normalizedMountPoint,
            remoteID: remoteID,
            operationID: operationID
        ) {
            diagnostics.append(
                level: .warning,
                category: "mount",
                message: "Recovered mount inspection using df fallback for \(normalizedMountPoint)."
            )
            return fallback
        }

        throw AppError.processFailure("Failed to inspect mounts: \(lastFailure)")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func mountInspectionFailureDetail(from result: ProcessResult) -> String {
        var parts: [String] = []

        if result.timedOut {
            parts.append("timed out")
        }
        if result.exitCode != 0 {
            parts.append("exit \(result.exitCode)")
        }

        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            parts.append(stderr)
        } else if !stdout.isEmpty {
            parts.append(stdout)
        }

        return parts.isEmpty ? "unknown failure" : parts.joined(separator: " - ")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func currentMountRecordViaDF(
        for mountPoint: String,
        remoteID: UUID? = nil,
        operationID: UUID? = nil
    ) async throws -> MountRecord? {
        let startedAt = Date()
        let remoteText = remoteID?.uuidString ?? "-"
        let operationText = operationID?.uuidString ?? "-"
        diagnostics.append(
            level: .debug,
            category: "mount",
            message: "probe start op=df-inspect remoteID=\(remoteText) operationID=\(operationText) path=\(mountPoint)"
        )
        let result = try await runner.run(
            executable: "/bin/df",
            arguments: ["-P", mountPoint],
            timeout: mountInspectionFallbackTimeout
        )
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
        diagnostics.append(
            level: .debug,
            category: "mount",
            message: "probe end op=df-inspect remoteID=\(remoteText) operationID=\(operationText) path=\(mountPoint) elapsedMs=\(elapsedMs) timedOut=\(result.timedOut) exit=\(result.exitCode)"
        )

        guard !result.timedOut, result.exitCode == 0 else {
            return nil
        }

        let lines = result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard lines.count >= 2 else {
            return nil
        }

        let dataLine = lines.last ?? ""
        let fields = dataLine.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 6 else {
            return nil
        }

        guard let mountedField = fields.last else {
            return nil
        }
        let mountedOn = URL(fileURLWithPath: mountedField).standardizedFileURL.path
        guard mountedOn == mountPoint else {
            return nil
        }

        let source = fields[0]
        return MountRecord(source: source, mountPoint: mountedOn, filesystemType: "unknown")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func setStatus(
        for remoteID: UUID,
        state: RemoteConnectionState,
        mountedPath: String?,
        lastError: String?
    ) {
        updateCachedStatus(
            RemoteStatus(
            state: state,
            mountedPath: mountedPath,
            lastError: lastError,
            updatedAt: Date()
        ),
            for: remoteID
        )
    }

    private func cachedStatus(for remoteID: UUID) -> RemoteStatus {
        return statuses[remoteID] ?? .disconnected
    }

    private func updateCachedStatus(_ status: RemoteStatus, for remoteID: UUID) {
        statuses[remoteID] = status
    }

    private func logActorQueueDelay(op: String, remote: RemoteConfig, queuedAt: Date, operationID: UUID?) {
        let delayMs = max(0, Int(Date().timeIntervalSince(queuedAt) * 1_000))
        diagnostics.append(
            level: .debug,
            category: "mount",
            message: "actor enter op=\(op) remoteID=\(remote.id.uuidString) operationID=\(operationID?.uuidString ?? "-") queueDelayMs=\(delayMs)"
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func friendlyMountError(_ raw: String, remote: RemoteConfig) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        let lower = trimmed.lowercased()
        if lower.contains("permission denied"), remote.remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines) == "/" {
            return "Permission denied for remote path '/'. On Windows OpenSSH, select a path like /C:/Users/\(remote.username) and retry."
        }

        if lower.contains("permission denied"), remote.authMode == .password {
            return "Authentication failed. Verify password and Windows OpenSSH settings for PasswordAuthentication/keyboard-interactive."
        }

        return trimmed
    }

    /// Beginner note: This is a bounded, non-recursive emergency cleanup path.
    /// It avoids heavy probe loops and makes stale mount teardown deterministic.
    private func forceUnmountMountPoint(_ mountPoint: String, remoteName: String, aggressive: Bool = false) async {
        let normalized = URL(fileURLWithPath: mountPoint).standardizedFileURL.path
        let commands: [(label: String, executable: String, args: [String], timeout: TimeInterval)]
        if aggressive {
            commands = [
                ("diskutil unmount force", "/usr/sbin/diskutil", ["unmount", "force", normalized], 4),
                ("umount -f", "/sbin/umount", ["-f", normalized], 2)
            ]
        } else {
            commands = [
                ("diskutil unmount force", "/usr/sbin/diskutil", ["unmount", "force", normalized], 8),
                ("umount -f", "/sbin/umount", ["-f", normalized], 4)
            ]
        }

        for command in commands {
            do {
                let result = try await runner.run(
                    executable: command.executable,
                    arguments: command.args,
                    timeout: command.timeout
                )

                if result.exitCode == 0 {
                    diagnostics.append(
                        level: .info,
                        category: "mount",
                        message: "\(command.label) succeeded for \(normalized) (\(remoteName))."
                    )
                    return
                }

                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = stderr.isEmpty ? stdout : stderr
                let reason = result.timedOut ? "timed out" : (detail.isEmpty ? "exit \(result.exitCode)" : detail)
                diagnostics.append(
                    level: .warning,
                    category: "mount",
                    message: "\(command.label) failed for \(normalized) (\(remoteName)): \(reason)"
                )
            } catch {
                diagnostics.append(
                    level: .warning,
                    category: "mount",
                    message: "\(command.label) failed for \(normalized) (\(remoteName)): \(error.localizedDescription)"
                )
            }
        }
    }
}
