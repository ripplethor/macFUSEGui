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
    private enum DirectoryQueryHealth {
        case healthy
        case timedOut
        case failed(reason: String)
    }

    private struct DirectoryQueryProbeStats {
        var timeoutEvents: Int = 0
        var deviceNotConfiguredEvents: Int = 0
        var otherFailureEvents: Int = 0
        var staleEscalations: Int = 0
        var cooldownSuppressions: Int = 0
        var lastFailureReason: String?
        var lastFailureAt: Date?
        var lastHealthyAt: Date?
    }

    private let runner: ProcessRunning
    private let dependencyChecker: DependencyChecking
    private let askpassHelper: AskpassHelper
    private let unmountService: UnmountService
    private let mountStateParser: MountStateParser
    private let diagnostics: DiagnosticsService
    private let commandBuilder: MountCommandBuilder
    // Keep mount inspection probes short. These are "status checks", not full recovery work.
    private let mountInspectionCommandTimeout: TimeInterval = 1.5
    private let mountInspectionFallbackTimeout: TimeInterval = 1.5
    private let mountResponsivenessTimeout: TimeInterval = 1.5
    // Directory queries can be slower than metadata probes on healthy network mounts.
    private let mountDirectoryQueryTimeout: TimeInterval = 3.5
    // Prevent indefinite "connected" false-positives when mount table parsing fails but local path still exists.
    private let maxConnectedPreserveMisses = 2
    // Treat one-off directory query timeouts as transient before forcing recovery.
    private let maxDirectoryQueryTimeoutPreserveMisses = 2
    // Directory-query exit failures can also be transient around wake/network restore.
    // Keep a short grace window before declaring stale and forcing reconnect.
    private let maxDirectoryQueryFailurePreserveMisses = 2
    // After a cleanup-driven reconnect, give directory queries a short warm-up window
    // before they are allowed to trigger stale recovery again.
    private let directoryQueryReconnectCooldownSeconds: TimeInterval
    private let sshfsConnectCommandTimeout: TimeInterval
    private let forceStopProcessListTimeout: TimeInterval = 3

    // Internal status cache so callers can ask current state without rerunning probes.
    private var statuses: [UUID: RemoteStatus] = [:]
    private var connectedPreserveMisses: [UUID: Int] = [:]
    private var directoryQueryTimeoutPreserveMisses: [UUID: Int] = [:]
    private var directoryQueryFailurePreserveMisses: [UUID: Int] = [:]
    private var reconnectDirectoryQueryCooldownUntil: [UUID: Date] = [:]
    private var directoryQueryProbeStatsByRemote: [UUID: DirectoryQueryProbeStats] = [:]

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        runner: ProcessRunning,
        dependencyChecker: DependencyChecking,
        askpassHelper: AskpassHelper,
        unmountService: UnmountService,
        mountStateParser: MountStateParser,
        diagnostics: DiagnosticsService,
        commandBuilder: MountCommandBuilder,
        sshfsConnectCommandTimeout: TimeInterval = 20,
        directoryQueryReconnectCooldownSeconds: TimeInterval = 30
    ) {
        self.runner = runner
        self.dependencyChecker = dependencyChecker
        self.askpassHelper = askpassHelper
        self.unmountService = unmountService
        self.mountStateParser = mountStateParser
        self.diagnostics = diagnostics
        self.commandBuilder = commandBuilder
        self.sshfsConnectCommandTimeout = sshfsConnectCommandTimeout
        self.directoryQueryReconnectCooldownSeconds = max(0, directoryQueryReconnectCooldownSeconds)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func status(for remoteID: UUID) -> RemoteStatus {
        cachedStatus(for: remoteID)
    }

    /// Beginner note: Snapshot-friendly summary of per-remote refresh probe counters.
    func refreshProbeDiagnosticsSummary(remotes: [RemoteConfig]) -> String {
        guard !remotes.isEmpty else {
            return "- none"
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()

        let lines = remotes
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { remote -> String in
                let timeoutStrike = directoryQueryTimeoutPreserveMisses[remote.id] ?? 0
                let failureStrike = directoryQueryFailurePreserveMisses[remote.id] ?? 0
                let cooldownRemaining = directoryQueryCooldownRemainingSeconds(for: remote.id, now: now)
                let stats = directoryQueryProbeStatsByRemote[remote.id] ?? DirectoryQueryProbeStats()
                let lastFailureAt = stats.lastFailureAt.map { formatter.string(from: $0) } ?? "-"
                let lastHealthyAt = stats.lastHealthyAt.map { formatter.string(from: $0) } ?? "-"
                let compactReason = (stats.lastFailureReason ?? "-")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                return "- \(remote.displayName) remoteID=\(remote.id.uuidString) " +
                    "timeoutStrike=\(timeoutStrike)/\(maxDirectoryQueryTimeoutPreserveMisses) " +
                    "failureStrike=\(failureStrike)/\(maxDirectoryQueryFailurePreserveMisses) " +
                    "cooldownRemainingSec=\(cooldownRemaining) " +
                    "timeoutEvents=\(stats.timeoutEvents) " +
                    "deviceNotConfiguredEvents=\(stats.deviceNotConfiguredEvents) " +
                    "otherFailureEvents=\(stats.otherFailureEvents) " +
                    "staleEscalations=\(stats.staleEscalations) " +
                    "cooldownSuppressions=\(stats.cooldownSuppressions) " +
                    "lastFailureAt=\(lastFailureAt) " +
                    "lastHealthyAt=\(lastHealthyAt) " +
                    "lastFailureReason=\(compactReason.isEmpty ? "-" : compactReason)"
            }

        return lines.joined(separator: "\n")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func refreshStatus(
        remote: RemoteConfig,
        queuedAt: Date = Date(),
        operationID: UUID? = nil
    ) async -> RemoteStatus {
        func cancelledStatus() -> RemoteStatus? {
            Task.isCancelled ? cachedStatus(for: remote.id) : nil
        }

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
            if let cancelled = cancelledStatus() {
                return cancelled
            }
            if mountedRecord == nil {
                directoryQueryTimeoutPreserveMisses[remote.id] = 0
                directoryQueryFailurePreserveMisses[remote.id] = 0
                reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remote.id)
            }

            // Guard against single-pass probe misses: if we were connected, do a fast
            // confirmation pass before transitioning to disconnected/recovery states.
            if mountedRecord == nil, previousStatus.state == .connected {
                if let dfRecord = try await currentMountRecordViaDF(
                    for: normalizedMountPoint,
                    remoteID: remote.id,
                    operationID: operationID
                ) {
                    mountedRecord = dfRecord
                    if let cancelled = cancelledStatus() {
                        return cancelled
                    }
                } else if await isMountPathResponsive(remote.localMountPoint, remoteID: remote.id, operationID: operationID) {
                    if let cancelled = cancelledStatus() {
                        return cancelled
                    }
                    let preserveMissCount = (connectedPreserveMisses[remote.id] ?? 0) + 1
                    connectedPreserveMisses[remote.id] = preserveMissCount

                    if preserveMissCount <= maxConnectedPreserveMisses {
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
                            message: "Preserved connected state for \(remote.displayName) using responsive mount-path check (miss \(preserveMissCount)/\(maxConnectedPreserveMisses))."
                        )
                        return preserved
                    }

                    connectedPreserveMisses[remote.id] = 0
                    diagnostics.append(
                        level: .warning,
                        category: "mount",
                        message: "Mount path remained responsive but mount was not detected for \(remote.displayName) after \(preserveMissCount) checks. Forcing recovery."
                    )
                    let staleStatus = RemoteStatus(
                        state: .error,
                        mountedPath: nil,
                        lastError: "Mount could not be verified. Reconnect will perform cleanup.",
                        updatedAt: Date()
                    )
                    updateCachedStatus(staleStatus, for: remote.id)
                    return staleStatus
                } else {
                    if let cancelled = cancelledStatus() {
                        return cancelled
                    }
                    connectedPreserveMisses[remote.id] = 0
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    mountedRecord = try await currentMountRecord(
                        for: remote.localMountPoint,
                        remoteID: remote.id,
                        operationID: operationID
                    )
                    if let cancelled = cancelledStatus() {
                        return cancelled
                    }
                }
            }

            if let mountedRecord {
                connectedPreserveMisses[remote.id] = 0
                // Extra health probe: a mount can exist but still be stale/hung.
                // Check both metadata responsiveness and the ability to query directory contents.
                let metadataHealthy = await isMountPathResponsive(
                    remote.localMountPoint,
                    remoteID: remote.id,
                    operationID: operationID
                )
                if let cancelled = cancelledStatus() {
                    return cancelled
                }
                guard metadataHealthy else {
                    directoryQueryTimeoutPreserveMisses[remote.id] = 0
                    directoryQueryFailurePreserveMisses[remote.id] = 0
                    reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remote.id)
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

                let directoryHealth = await mountDirectoryHealth(
                    remote.localMountPoint,
                    remoteID: remote.id,
                    operationID: operationID
                )
                if let cancelled = cancelledStatus() {
                    return cancelled
                }

                switch directoryHealth {
                case .healthy:
                    directoryQueryTimeoutPreserveMisses[remote.id] = 0
                    directoryQueryFailurePreserveMisses[remote.id] = 0
                    recordDirectoryQueryHealthy(for: remote.id)
                case .timedOut:
                    recordDirectoryQueryTimeout(for: remote.id)
                    let cooldownRemainingSeconds = directoryQueryCooldownRemainingSeconds(for: remote.id)
                    if cooldownRemainingSeconds > 0 {
                        directoryQueryTimeoutPreserveMisses[remote.id] = 0
                        directoryQueryFailurePreserveMisses[remote.id] = 0
                        recordDirectoryQueryCooldownSuppression(for: remote.id)
                        let preserved = RemoteStatus(
                            state: .connected,
                            mountedPath: mountedRecord.mountPoint,
                            lastError: nil,
                            updatedAt: Date()
                        )
                        updateCachedStatus(preserved, for: remote.id)
                        diagnostics.append(
                            level: .debug,
                            category: "mount",
                            message: "Suppressed stale escalation for \(remote.displayName) during post-reconnect cooldown (\(cooldownRemainingSeconds)s remaining) after directory query timeout."
                        )
                        return preserved
                    }

                    directoryQueryFailurePreserveMisses[remote.id] = 0
                    let timeoutMissCount = (directoryQueryTimeoutPreserveMisses[remote.id] ?? 0) + 1
                    directoryQueryTimeoutPreserveMisses[remote.id] = timeoutMissCount

                    // Preserve briefly when we have a confirmed mount record and healthy
                    // metadata probe, even if this is first refresh after launch.
                    if timeoutMissCount <= maxDirectoryQueryTimeoutPreserveMisses {
                        let preserved = RemoteStatus(
                            state: .connected,
                            mountedPath: mountedRecord.mountPoint,
                            lastError: nil,
                            updatedAt: Date()
                        )
                        updateCachedStatus(preserved, for: remote.id)
                        diagnostics.append(
                            level: .debug,
                            category: "mount",
                            message: "Preserved connected state for \(remote.displayName) after directory query timeout (\(timeoutMissCount)/\(maxDirectoryQueryTimeoutPreserveMisses))."
                        )
                        return preserved
                    }

                    diagnostics.append(
                        level: .warning,
                        category: "mount",
                        message: "Stale mount detected at \(remote.localMountPoint) after repeated directory query timeouts. Marking as error for reconnect flow."
                    )
                    recordDirectoryQueryStaleEscalation(for: remote.id)
                    let staleStatus = RemoteStatus(
                        state: .error,
                        mountedPath: nil,
                        lastError: "Detected stale mount. Reconnect will perform cleanup.",
                        updatedAt: Date()
                    )
                    updateCachedStatus(staleStatus, for: remote.id)
                    return staleStatus
                case .failed(let reason):
                    recordDirectoryQueryFailure(for: remote.id, reason: reason)
                    let cooldownRemainingSeconds = directoryQueryCooldownRemainingSeconds(for: remote.id)
                    if cooldownRemainingSeconds > 0 {
                        directoryQueryTimeoutPreserveMisses[remote.id] = 0
                        directoryQueryFailurePreserveMisses[remote.id] = 0
                        recordDirectoryQueryCooldownSuppression(for: remote.id)
                        let preserved = RemoteStatus(
                            state: .connected,
                            mountedPath: mountedRecord.mountPoint,
                            lastError: nil,
                            updatedAt: Date()
                        )
                        updateCachedStatus(preserved, for: remote.id)
                        diagnostics.append(
                            level: .debug,
                            category: "mount",
                            message: "Suppressed stale escalation for \(remote.displayName) during post-reconnect cooldown (\(cooldownRemainingSeconds)s remaining) after directory query failure: \(reason)"
                        )
                        return preserved
                    }

                    directoryQueryTimeoutPreserveMisses[remote.id] = 0
                    let failureMissCount = (directoryQueryFailurePreserveMisses[remote.id] ?? 0) + 1
                    directoryQueryFailurePreserveMisses[remote.id] = failureMissCount

                    // Preserve briefly when mount table and metadata probes are healthy.
                    // This avoids immediate reconnect flapping from transient directory query exits.
                    if failureMissCount <= maxDirectoryQueryFailurePreserveMisses {
                        let preserved = RemoteStatus(
                            state: .connected,
                            mountedPath: mountedRecord.mountPoint,
                            lastError: nil,
                            updatedAt: Date()
                        )
                        updateCachedStatus(preserved, for: remote.id)
                        diagnostics.append(
                            level: .debug,
                            category: "mount",
                            message: "Preserved connected state for \(remote.displayName) after directory query failure (\(failureMissCount)/\(maxDirectoryQueryFailurePreserveMisses)): \(reason)"
                        )
                        return preserved
                    }

                    diagnostics.append(
                        level: .warning,
                        category: "mount",
                        message: "Stale mount detected at \(remote.localMountPoint) after repeated directory query failures (\(reason)). Marking as error for reconnect flow."
                    )
                    recordDirectoryQueryStaleEscalation(for: remote.id)
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

            connectedPreserveMisses[remote.id] = 0
            directoryQueryTimeoutPreserveMisses[remote.id] = 0
            directoryQueryFailurePreserveMisses[remote.id] = 0
            reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remote.id)
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
                    if let cancelled = cancelledStatus() {
                        return cancelled
                    }
                    // Only preserve connected when the mounted path is still immediately
                    // responsive. If it is not responsive, force recovery to reconnect.
                    if await isMountPathResponsive(remote.localMountPoint, remoteID: remote.id, operationID: operationID) {
                        if let cancelled = cancelledStatus() {
                            return cancelled
                        }
                        let preserveMissCount = (connectedPreserveMisses[remote.id] ?? 0) + 1
                        connectedPreserveMisses[remote.id] = preserveMissCount
                        if preserveMissCount <= maxConnectedPreserveMisses {
                            let preserved = RemoteStatus(
                                state: .connected,
                                mountedPath: previous.mountedPath,
                                lastError: nil,
                                updatedAt: Date()
                            )
                            updateCachedStatus(preserved, for: remote.id)
                            return preserved
                        }
                    }

                    connectedPreserveMisses[remote.id] = 0
                    directoryQueryTimeoutPreserveMisses[remote.id] = 0
                    directoryQueryFailurePreserveMisses[remote.id] = 0
                    reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remote.id)
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
                connectedPreserveMisses[remote.id] = 0
                directoryQueryTimeoutPreserveMisses[remote.id] = 0
                directoryQueryFailurePreserveMisses[remote.id] = 0
                reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remote.id)
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
        clearRefreshProbeMisses(for: remote.id)

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
            var preConnectCleanupPerformed = false
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
                // Force-stop scoped sshfs pids and force-unmount so a fresh connect
                // can proceed deterministically on the next attempt.
                await forceStopProcesses(
                    for: remote,
                    queuedAt: Date(),
                    operationID: operationID
                )
                preConnectCleanupPerformed = true

                let stillMounted = try await currentMountRecord(
                    for: remote.localMountPoint,
                    remoteID: remote.id,
                    operationID: operationID
                ) != nil
                if stillMounted {
                    throw AppError.processFailure(
                        "Mount is still active at \(remote.localMountPoint). Wait a few seconds and retry Connect."
                    )
                }
            }

            try throwIfCancelled()
            do {
                try ensureLocalMountPointReady(remote.localMountPoint)
            } catch {
                let shouldRetryAfterCleanup = !preConnectCleanupPerformed
                    && shouldRetryConnectAfterMountPointPreparationFailure(error)
                if shouldRetryAfterCleanup {
                    diagnostics.append(
                        level: .warning,
                        category: "mount",
                        message: "Mount point preparation failed for \(remote.displayName) at \(remote.localMountPoint). Attempting one cleanup pass before retry: \(error.localizedDescription)"
                    )

                    await forceStopProcesses(
                        for: remote,
                        queuedAt: Date(),
                        operationID: operationID
                    )
                    preConnectCleanupPerformed = true

                    try throwIfCancelled()
                    try ensureLocalMountPointReady(remote.localMountPoint)
                } else {
                    throw error
                }
            }

            let status = try await connectWithRetry(
                remote: remote,
                password: password,
                sshfsPath: sshfsPath,
                operationID: operationID
            )
            try await enforceMinimumTransitionVisibility(since: connectBeganAt, minimumSeconds: 0.8)
            updateCachedStatus(status, for: remote.id)
            setReconnectDirectoryQueryCooldown(for: remote.id, enabled: preConnectCleanupPerformed)
            return status
        } catch {
            if !Task.isCancelled {
                try? await enforceMinimumTransitionVisibility(since: connectBeganAt, minimumSeconds: 0.8)
            }
            reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remote.id)
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
                // Cleanup can fail if macOS is mid-transition or the mount already disappeared.
                // We intentionally ignore cleanup errors here so the original failure is preserved.
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
        clearRefreshProbeMisses(for: remote.id)

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

            let status = RemoteStatus(
                state: .disconnected,
                mountedPath: nil,
                lastError: nil,
                updatedAt: Date()
            )
            updateCachedStatus(status, for: remote.id)
            reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remote.id)

            // Keep the transitional state visible long enough for live UI updates.
            // If cancelled during this sleep, keep the successful disconnected result.
            do {
                try await enforceMinimumTransitionVisibility(since: disconnectBeganAt, minimumSeconds: 0.7)
            } catch is CancellationError {
                return status
            }
            return status
        } catch {
            let status = RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: error.localizedDescription,
                updatedAt: Date()
            )
            updateCachedStatus(status, for: remote.id)
            reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remote.id)
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
        fastForceUnmount: Bool = false,
        skipForceUnmount: Bool = false
    ) async {
        logActorQueueDelay(op: "forceStopProcesses", remote: remote, queuedAt: queuedAt, operationID: operationID)
        let normalizedMountPoint = URL(fileURLWithPath: remote.localMountPoint).standardizedFileURL.path
        let connectionNeedle = "\(remote.username)@\(sshHostArgument(remote.host)):\(remote.remoteDirectory)"
        let postStopAction = skipForceUnmount ? "skipping force-unmount by request." : "attempting force-unmount anyway."

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
                            // Best-effort: sshfs may exit between ps and kill, or permissions may block the signal.
                            // We intentionally ignore kill failures and still attempt force-unmount next.
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
                        message: "No sshfs pid match found for \(remote.displayName); \(postStopAction)"
                    )
                }
            } else {
                diagnostics.append(
                    level: .warning,
                    category: "mount",
                    message: "Process listing failed while force-stopping \(remote.displayName) (exit \(result.exitCode)); \(postStopAction)"
                )
            }
        } catch {
            diagnostics.append(
                level: .warning,
                category: "mount",
                message: "Force-stop sshfs failed for \(remote.displayName): \(error.localizedDescription)"
            )
        }

        if skipForceUnmount {
            let autoUnmounted = await waitForUnmountAfterProcessStop(
                remote: remote,
                operationID: operationID
            )
            diagnostics.append(
                level: autoUnmounted ? .info : .warning,
                category: "mount",
                message: autoUnmounted
                    ? "Skipped force-unmount for \(remote.displayName) (requested by caller); mount cleared after process stop."
                    : "Skipped force-unmount for \(remote.displayName) (requested by caller); mount still present after process stop."
            )
            return
        }

        await forceUnmountMountPoint(
            remote.localMountPoint,
            remoteName: remote.displayName,
            fast: fastForceUnmount
        )
    }

    /// Beginner note: When force-unmount is intentionally skipped, poll mount-table state
    /// briefly so reconnect paths can avoid immediate "mount still active" failures.
    /// This path only inspects mount records and does not probe mounted file contents.
    private func waitForUnmountAfterProcessStop(
        remote: RemoteConfig,
        operationID: UUID?,
        timeoutSeconds: TimeInterval = 3
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if Task.isCancelled {
                return false
            }
            let mounted = (try? await currentMountRecord(
                for: remote.localMountPoint,
                remoteID: remote.id,
                operationID: operationID
            )) != nil
            if !mounted {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func waitForUnmount(mountPoint: String, timeoutSeconds: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            try throwIfCancelled()
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
                    || message.contains("temporary failure")

                if shouldRetry && attempt < 2 {
                    // Retry once after cleanup for transient transport/mount handoff failures.
                    diagnostics.append(level: .warning, category: "mount", message: "Retrying mount for \(remote.displayName) after cleanup.")
                    // Cleanup is best-effort. If it fails, the next attempt will still run and will likely
                    // return a clearer mount error. We do not fail the retry solely due to cleanup.
                    try? await unmountService.unmount(mountPoint: remote.localMountPoint)
                    try? ensureLocalMountPointReady(remote.localMountPoint)
                    continue
                }

                throw error
            }
        }

        throw lastError ?? AppError.unknown("Mount failed")
    }

    /// Beginner note: A stale FUSE mount can surface as local mount-point creation failures.
    /// Retry once after bounded cleanup when the message looks like a stale filesystem condition.
    private func shouldRetryConnectAfterMountPointPreparationFailure(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        let normalizedMessage = message.replacingOccurrences(of: "’", with: "'")
        let mountPointCreationFailure = message.contains("local mount point could not be created")
            || message.contains("local mount point does not exist and could not be created")
        guard mountPointCreationFailure else {
            return false
        }

        return normalizedMessage.contains("input/output")
            || normalizedMessage.contains("device not configured")
            || normalizedMessage.contains("resource busy")
            || normalizedMessage.contains("operation timed out")
            || normalizedMessage.contains("could not be saved")
            || normalizedMessage.contains("couldn't be saved")
            || normalizedMessage.contains("stale mount")
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
            throw AppError.validationFailed([
                "Local mount point could not be created: \(normalized). " +
                "This can happen after a server restart leaves a stale mount path, or when macOS blocks writes to that folder. " +
                "Disconnect the remote, wait a few seconds, then reconnect. " +
                "If it keeps failing, choose a different local mount folder. " +
                "Details: \(error.localizedDescription)"
            ])
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    @discardableResult
    private func connectAttempt(
        remote: RemoteConfig,
        password: String?,
        sshfsPath: String,
        updateStoredStatus: Bool,
        operationID: UUID?
    ) async throws -> RemoteStatus {
        try throwIfCancelled()
        func runConnectAttempt(passwordEnvironment: [String: String]) async throws -> RemoteStatus {
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
            let normalizedMountPoint = URL(fileURLWithPath: remote.localMountPoint).standardizedFileURL.path
            let detectionDeadline = Date().addingTimeInterval(5)
            while Date() < detectionDeadline {
                if Task.isCancelled {
                    throw AppError.timeout("Mount operation was cancelled.")
                }

                do {
                    if let record = try await currentMountRecord(
                        for: normalizedMountPoint,
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

                    // Some mount output variants can be syntactically valid but not match our
                    // parser shape. Use df fallback during connect detection to avoid false
                    // negatives when sshfs has already established the mount.
                    if let fallback = try await currentMountRecordViaDF(
                        for: normalizedMountPoint,
                        remoteID: remote.id,
                        operationID: operationID
                    ) {
                        diagnostics.append(
                            level: .warning,
                            category: "mount",
                            message: "Post-connect detection recovered via df fallback for \(remote.displayName) at \(normalizedMountPoint)."
                        )
                        let status = RemoteStatus(
                            state: .connected,
                            mountedPath: fallback.mountPoint,
                            lastError: nil,
                            updatedAt: Date()
                        )
                        if updateStoredStatus {
                            updateCachedStatus(status, for: remote.id)
                        }
                        return status
                    }
                } catch {
                    if Task.isCancelled {
                        throw AppError.timeout("Mount operation was cancelled.")
                    }
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

        if remote.authMode == .password {
            guard let password, !password.isEmpty else {
                throw AppError.validationFailed(["Password is required for password authentication."])
            }

            return try await askpassHelper.withContext(password: password) { context in
                try await runConnectAttempt(passwordEnvironment: context.environment)
            }
        }

        return try await runConnectAttempt(passwordEnvironment: [:])
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    private func throwIfCancelled() throws {
        if Task.isCancelled {
            throw CancellationError()
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

    /// Beginner note: Some broken FUSE mounts can still pass stat but fail directory reads
    /// with "Device not configured". This probe checks directory query health cheaply.
    private func mountDirectoryHealth(
        _ mountPoint: String,
        remoteID: UUID? = nil,
        operationID: UUID? = nil
    ) async -> DirectoryQueryHealth {
        let startedAt = Date()
        let remoteText = remoteID?.uuidString ?? "-"
        let operationText = operationID?.uuidString ?? "-"
        diagnostics.append(
            level: .debug,
            category: "mount",
            message: "probe start op=mount-dir-query remoteID=\(remoteText) operationID=\(operationText) path=\(mountPoint)"
        )

        do {
            let result = try await runner.run(
                executable: "/usr/bin/find",
                arguments: [mountPoint, "-mindepth", "1", "-maxdepth", "1", "-print", "-quit"],
                timeout: mountDirectoryQueryTimeout
            )
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = !stderr.isEmpty ? stderr : stdout
            let compactDetail = detail
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detailSuffix = compactDetail.isEmpty ? "" : " detail=\(compactDetail)"
            diagnostics.append(
                level: .debug,
                category: "mount",
                message: "probe end op=mount-dir-query remoteID=\(remoteText) operationID=\(operationText) path=\(mountPoint) elapsedMs=\(elapsedMs) timedOut=\(result.timedOut) exit=\(result.exitCode)\(detailSuffix)"
            )
            if result.timedOut {
                return .timedOut
            }
            if result.exitCode == 0 {
                return .healthy
            }
            let reason = compactDetail.isEmpty ? "exit \(result.exitCode)" : compactDetail
            return .failed(reason: reason)
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            diagnostics.append(
                level: .debug,
                category: "mount",
                message: "probe end op=mount-dir-query remoteID=\(remoteText) operationID=\(operationText) path=\(mountPoint) elapsedMs=\(elapsedMs) error=\(error.localizedDescription)"
            )
            return .failed(reason: error.localizedDescription)
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
        try throwIfCancelled()
        let attemptStartedAt = Date()
        diagnostics.append(
            level: .debug,
            category: "mount",
            message: "probe start op=mount-inspect remoteID=\(remoteText) operationID=\(operationText) path=\(normalizedMountPoint) attempt=1"
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
            message: "probe end op=mount-inspect remoteID=\(remoteText) operationID=\(operationText) path=\(normalizedMountPoint) attempt=1 elapsedMs=\(elapsedMs) timedOut=\(mountResult.timedOut) exit=\(mountResult.exitCode)"
        )

        if !mountResult.timedOut && mountResult.exitCode == 0 {
            let records = mountStateParser.parseMountOutput(mountResult.stdout)
            return mountStateParser.record(forMountPoint: normalizedMountPoint, from: records)
        }

        let lastFailure = mountInspectionFailureDetail(from: mountResult)
        diagnostics.append(
            level: .warning,
            category: "mount",
            message: "Mount inspection attempt 1 failed for remoteID=\(remoteText) operationID=\(operationText) path=\(normalizedMountPoint): \(lastFailure)"
        )

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
        guard let (source, mountedOn) = parsedDFLine(dataLine) else {
            return nil
        }
        guard mountedOn == mountPoint else {
            return nil
        }
        return MountRecord(source: source, mountPoint: mountedOn, filesystemType: "unknown")
    }

    private func parsedDFLine(_ line: String) -> (source: String, mountedOn: String)? {
        let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 6 else {
            return nil
        }

        let source = fields[0]
        let mountedField = fields.dropFirst(5).joined(separator: " ")
        let decodedMountedField = mountStateParser.decodeEscapedMountField(mountedField)
        let mountedOn = URL(fileURLWithPath: decodedMountedField).standardizedFileURL.path
        return (source, mountedOn)
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
        return statuses[remoteID] ?? .initial
    }

    private func updateCachedStatus(_ status: RemoteStatus, for remoteID: UUID) {
        statuses[remoteID] = status
    }

    private func clearRefreshProbeMisses(for remoteID: UUID) {
        connectedPreserveMisses[remoteID] = 0
        directoryQueryTimeoutPreserveMisses[remoteID] = 0
        directoryQueryFailurePreserveMisses[remoteID] = 0
    }

    private func setReconnectDirectoryQueryCooldown(for remoteID: UUID, enabled: Bool) {
        guard enabled, directoryQueryReconnectCooldownSeconds > 0 else {
            reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remoteID)
            return
        }
        reconnectDirectoryQueryCooldownUntil[remoteID] = Date().addingTimeInterval(directoryQueryReconnectCooldownSeconds)
    }

    private func directoryQueryCooldownRemainingSeconds(for remoteID: UUID, now: Date = Date()) -> Int {
        guard let until = reconnectDirectoryQueryCooldownUntil[remoteID] else {
            return 0
        }
        let remaining = until.timeIntervalSince(now)
        guard remaining > 0 else {
            reconnectDirectoryQueryCooldownUntil.removeValue(forKey: remoteID)
            return 0
        }
        return Int(remaining.rounded(.up))
    }

    private func recordDirectoryQueryHealthy(for remoteID: UUID) {
        updateDirectoryQueryProbeStats(for: remoteID) { stats in
            stats.lastHealthyAt = Date()
        }
    }

    private func recordDirectoryQueryTimeout(for remoteID: UUID) {
        updateDirectoryQueryProbeStats(for: remoteID) { stats in
            stats.timeoutEvents += 1
            stats.lastFailureAt = Date()
            stats.lastFailureReason = "timed out"
        }
    }

    private func recordDirectoryQueryFailure(for remoteID: UUID, reason: String) {
        let normalizedReason = reason.lowercased()
        updateDirectoryQueryProbeStats(for: remoteID) { stats in
            if normalizedReason.contains("device not configured") {
                stats.deviceNotConfiguredEvents += 1
            } else {
                stats.otherFailureEvents += 1
            }
            stats.lastFailureAt = Date()
            stats.lastFailureReason = reason
        }
    }

    private func recordDirectoryQueryStaleEscalation(for remoteID: UUID) {
        updateDirectoryQueryProbeStats(for: remoteID) { stats in
            stats.staleEscalations += 1
        }
    }

    private func recordDirectoryQueryCooldownSuppression(for remoteID: UUID) {
        updateDirectoryQueryProbeStats(for: remoteID) { stats in
            stats.cooldownSuppressions += 1
        }
    }

    private func updateDirectoryQueryProbeStats(
        for remoteID: UUID,
        _ update: (inout DirectoryQueryProbeStats) -> Void
    ) {
        var stats = directoryQueryProbeStatsByRemote[remoteID] ?? DirectoryQueryProbeStats()
        update(&stats)
        directoryQueryProbeStatsByRemote[remoteID] = stats
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
    /// When `fast` is true, per-command timeouts are shorter to reduce recovery stall time.
    private func forceUnmountMountPoint(_ mountPoint: String, remoteName: String, fast: Bool = false) async {
        let normalized = URL(fileURLWithPath: mountPoint).standardizedFileURL.path
        let commands: [(label: String, executable: String, args: [String], timeout: TimeInterval)]
        if fast {
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
