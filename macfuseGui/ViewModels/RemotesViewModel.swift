// BEGINNER FILE GUIDE
// Layer: View model orchestration layer
// Purpose: This file transforms service-level behavior into UI-ready state and user actions.
// Called by: Called by SwiftUI views and menu controllers in response to user input.
// Calls into: Calls into services and publishes state changes back to the UI.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import Foundation
import Network
import ServiceManagement

// This actor is a lightweight semaphore for async work.
// Why it exists:
// - A user can trigger many operations quickly (connect/disconnect/refresh).
// - We want parallel work, but not unbounded parallelism that could overload the app.
// - The limiter allows up to N in-flight operations and queues the rest.
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
private actor OperationLimiter {
    private let maxConcurrent: Int
    private var inFlight: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Beginner note: Initializers create valid state before any other method is used.
    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func acquire() async {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func release() {
        if !waiters.isEmpty {
            let continuation = waiters.removeFirst()
            continuation.resume()
            return
        }
        inFlight = max(0, inFlight - 1)
    }
}

@MainActor
// RemotesViewModel is the main "brain" of the app.
// Practical reading order for beginners:
// 1) Public action methods (connect/disconnect/refresh/save/delete/test).
// 2) runOperation(...) which routes everything through one operation pipeline.
// 3) performConnect / performDisconnect / performRefreshStatus.
// 4) Recovery methods (periodic, wake, network restore).
// 5) Browser helpers and diagnostics helpers near the end.
//
// Design note:
// This file intentionally centralizes orchestration so key invariants do not drift:
// - desiredConnections remains the source of recovery intent
// - one active operation per remote, with explicit conflict policies
// - anti-flap status refresh and bounded timeouts
// Refactors should prefer extracting pure helpers while keeping state ownership and orchestration here.
//
// Why @MainActor:
// - @Published properties are read by SwiftUI/AppKit UI.
// - Running this type on the main actor avoids UI data races.
// - It does not mean all heavy work runs on the main thread; async service calls still suspend.
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class RemotesViewModel: ObservableObject {
    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    struct RecoveryIndicator: Equatable, Sendable {
        var reason: String
        var startedAt: Date
        var pendingRemoteCount: Int
        var scheduledReconnectCount: Int
    }

    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    enum RemoteOperationIntent: String, Sendable {
        case connect
        case disconnect
        case refresh
        case testConnection
    }

    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    enum RemoteOperationTrigger: String, Sendable {
        case manual
        case recovery
        case startup
        case termination
    }

    enum NetworkReachabilityTransition: Sendable, Equatable {
        case unchanged
        case becameReachable
        case becameUnreachable
    }

    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    enum RemoteOperationConflictPolicy: Sendable {
        case latestIntentWins
        case skipIfBusy
    }

    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    final class RemoteOperationState {
        let operationID: UUID
        let remoteID: UUID
        let intent: RemoteOperationIntent
        let trigger: RemoteOperationTrigger
        let startedAt: Date
        // When latest-intent-wins cancels an operation, we record who replaced it.
        var supersededBy: UUID?
        // cancelled=true means this operation should no longer update visible state.
        var cancelled: Bool = false
        // Task handle so we can cancel actively running work.
        var task: Task<Void, Never>?

        /// Beginner note: Initializers create valid state before any other method is used.
        init(
            operationID: UUID,
            remoteID: UUID,
            intent: RemoteOperationIntent,
            trigger: RemoteOperationTrigger,
            startedAt: Date
        ) {
            self.operationID = operationID
            self.remoteID = remoteID
            self.intent = intent
            self.trigger = trigger
            self.startedAt = startedAt
        }
    }

    /// Beginner note: This wrapper allows keychain reads on a background queue.
    /// It is marked unchecked-sendable so async closures can capture it safely.
    private final class BackgroundKeychainReader: @unchecked Sendable {
        private let keychainService: KeychainServiceProtocol

        init(keychainService: KeychainServiceProtocol) {
            self.keychainService = keychainService
        }

        func readPassword(remoteID: String, allowUserInteraction: Bool) throws -> String? {
            try keychainService.readPassword(
                remoteID: remoteID,
                allowUserInteraction: allowUserInteraction
            )
        }
    }

    // Source-of-truth remote list loaded from RemoteStore.
    @Published private(set) var remotes: [RemoteConfig] = []
    // Runtime per-remote status map used by both settings and menu UI.
    @Published private(set) var statuses: [UUID: RemoteStatus] = [:]
    // Current selection in settings list.
    @Published var selectedRemoteID: UUID?
    // General alert banner text shown in settings.
    @Published var alertMessage: String?
    // Result of dependency checks (sshfs/macFUSE readiness).
    @Published private(set) var dependencyStatus: DependencyStatus?
    // Current launch-at-login registration state.
    @Published private(set) var launchAtLoginState: LaunchAtLoginState = .unknown
    // Short-lived summary badge for recovery activity.
    @Published private(set) var recoveryIndicator: RecoveryIndicator?
    // True while macOS is sleeping (used to pause recovery passes).
    @Published private(set) var systemSleeping: Bool = false
    // Used by the menu icon for a brief wake animation window.
    @Published private(set) var wakeAnimationUntil: Date?

    private let remoteStore: RemoteStore
    private let keychainService: KeychainServiceProtocol
    private let backgroundKeychainReader: BackgroundKeychainReader
    private let validationService: ValidationService
    private let dependencyChecker: DependencyChecker
    private let mountManager: MountManager
    private let remoteDirectoryBrowserService: RemoteDirectoryBrowserService
    private let diagnostics: DiagnosticsService
    private let launchAtLoginService: LaunchAtLoginService
    private let networkMonitorQueue: DispatchQueue
    private let keychainReadQueue = DispatchQueue(label: "com.visualweb.macfusegui.keychain-read")
    // Product policy: do not trigger system Keychain auth popups during normal app flows.
    private let allowInteractiveKeychainReads = false

    // Core intent set: if a remote ID is here, user wants it kept connected.
    // Recovery logic only auto-reconnects remotes in this set.
    private var desiredConnections: Set<UUID> = []
    // Tracks reconnect attempt count per remote for backoff decisions.
    private var reconnectAttempts: [UUID: Int] = [:]
    // Guard to prevent duplicate reconnect scheduling for the same remote.
    private var reconnectInFlight: Set<UUID> = []
    // Task handles for reconnect timers so they can be cancelled cleanly.
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]
    // Used by periodic probes to avoid overreacting to single missed checks.
    private var recoveryNonConnectedStrikes: [UUID: Int] = [:]
    // Stores when each remote was last refreshed by recovery probing.
    // This avoids probing healthy connected remotes every 15s.
    private var lastRecoveryRefreshAt: [UUID: Date] = [:]
    private var recoveryTimer: Timer?
    private var lastPeriodicRecoveryProbeAt: Date = .distantPast
    private var lastSleepSkipLogAt: Date = .distantPast
    private var lastWakePreflightSkipLogAt: Date = .distantPast
    private var recoveryBurstTask: Task<Void, Never>?
    private var wakePreflightInProgress = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var networkMonitor: NWPathMonitor?
    private var networkReachable: Bool = false
    private var pendingStartupAutoConnectIDs: Set<UUID> = []
    private var startupAutoConnectInProgress = false
    private var startupAutoConnectRerunRequested = false
    private var networkRestoreDebounceTask: Task<Void, Never>?
    private var recoveryMonitoringStarted = false
    private var shutdownInProgress = false
    private var recoveryIndicatorReason: String?
    // Watchdogs make sure UI never sits in connecting/disconnecting forever.
    private let connectWatchdogTimeout: TimeInterval
    private let disconnectWatchdogTimeout: TimeInterval
    private let refreshWatchdogTimeout: TimeInterval
    // When everything looks healthy, periodic probes are intentionally less frequent.
    private let healthyPeriodicProbeInterval: TimeInterval
    private let periodicRecoveryPassInterval: TimeInterval
    private let networkRestoredDebounceSeconds: TimeInterval = 1.5
    private var operationWatchdogTasks: [UUID: Task<Void, Never>] = [:]
    // Hard timeout for actual connect operation body.
    private let connectTimeoutSeconds: TimeInterval = 35
    // Keep inner disconnect timeout below watchdog so fallback cleanup can run first.
    private let disconnectTimeoutSeconds: TimeInterval = 8
    private let stalledOperationReplacementSeconds: TimeInterval = 20
    private var activeBrowserSessions: Set<RemoteBrowserSessionID> = []
    private let operationLimiter = OperationLimiter(maxConcurrent: 4)
    private var remoteOperations: [UUID: RemoteOperationState] = [:]
    // In-memory password cache avoids repeated keychain reads/prompts during reconnect bursts.
    private var passwordCache: [UUID: String] = [:]

    // Browser path memory limits (kept here so UI and persistence use one rule).
    nonisolated static let favoritesLimit = 20
    nonisolated static let recentsLimit = 15

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        remoteStore: RemoteStore,
        keychainService: KeychainServiceProtocol,
        validationService: ValidationService,
        dependencyChecker: DependencyChecker,
        mountManager: MountManager,
        remoteDirectoryBrowserService: RemoteDirectoryBrowserService,
        diagnostics: DiagnosticsService,
        launchAtLoginService: LaunchAtLoginService,
        runtimeConfiguration: RuntimeConfiguration = RuntimeConfiguration()
    ) {
        self.remoteStore = remoteStore
        self.keychainService = keychainService
        self.backgroundKeychainReader = BackgroundKeychainReader(keychainService: keychainService)
        self.validationService = validationService
        self.dependencyChecker = dependencyChecker
        self.mountManager = mountManager
        self.remoteDirectoryBrowserService = remoteDirectoryBrowserService
        self.diagnostics = diagnostics
        self.launchAtLoginService = launchAtLoginService
        self.connectWatchdogTimeout = runtimeConfiguration.remotes.connectWatchdogTimeout
        self.disconnectWatchdogTimeout = runtimeConfiguration.remotes.disconnectWatchdogTimeout
        self.refreshWatchdogTimeout = runtimeConfiguration.remotes.refreshWatchdogTimeout
        self.healthyPeriodicProbeInterval = runtimeConfiguration.remotes.healthyPeriodicProbeInterval
        // Keep queue identity deterministic in logs/tests and configurable via runtime configuration.
        self.networkMonitorQueue = DispatchQueue(label: runtimeConfiguration.remotes.networkMonitorQueueLabel)
        self.periodicRecoveryPassInterval = runtimeConfiguration.remotes.periodicRecoveryPassInterval
    }

    /// Beginner note: Deinitializer runs during teardown to stop background work and free resources.
    deinit {
        recoveryTimer?.invalidate()
        recoveryTimer = nil

        networkMonitor?.cancel()
        networkMonitor = nil

        operationWatchdogTasks.values.forEach { $0.cancel() }
        operationWatchdogTasks.removeAll()

        remoteOperations.values.forEach { state in
            state.task?.cancel()
        }
        remoteOperations.removeAll()

        reconnectTasks.values.forEach { $0.cancel() }
        reconnectTasks.removeAll()
        recoveryBurstTask?.cancel()
        recoveryBurstTask = nil
        networkRestoreDebounceTask?.cancel()
        networkRestoreDebounceTask = nil

        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()

        let sessionsToClose = activeBrowserSessions
        if !sessionsToClose.isEmpty {
            let browserService = remoteDirectoryBrowserService
            Task {
                for sessionID in sessionsToClose {
                    await browserService.closeSession(sessionID)
                }
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func load() {
        do {
            // Load persisted remotes from disk, then keep UI list order stable.
            remotes = try remoteStore.load().sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            if selectedRemoteID == nil {
                selectedRemoteID = remotes.first?.id
            }

            // After loading from disk, remove stale runtime state for deleted remotes.
            reconcileConnectionTrackingState()
            // Recovery monitoring is started once and then kept alive for app lifetime.
            startRecoveryMonitoringIfNeeded()

            // These checks are safe to run often and drive visible status chips in settings.
            dependencyStatus = dependencyChecker.check()
            launchAtLoginState = launchAtLoginService.currentState()
            diagnostics.append(level: .info, category: "store", message: "Loaded \(remotes.count) remotes from \(remoteStore.storageURL.path)")
        } catch {
            alertMessage = error.localizedDescription
            diagnostics.append(level: .error, category: "store", message: error.localizedDescription)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func refreshLaunchAtLoginState() {
        launchAtLoginState = launchAtLoginService.currentState()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                self.launchAtLoginState = try await self.launchAtLoginService.setEnabled(enabled)

                if self.launchAtLoginState.requiresApproval {
                    self.alertMessage = "Launch at login requires approval in System Settings -> General -> Login Items."
                } else {
                    self.alertMessage = nil
                }

                self.diagnostics.append(
                    level: .info,
                    category: "startup",
                    message: "Launch at login set to \(enabled). Status: \(self.launchAtLoginState.description)"
                )
            } catch {
                self.launchAtLoginState = self.launchAtLoginService.currentState()
                self.alertMessage = "Could not update launch at login: \(error.localizedDescription)"
                self.diagnostics.append(level: .error, category: "startup", message: "Failed to set launch at login: \(error.localizedDescription)")
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func refreshDependencies() {
        dependencyStatus = dependencyChecker.check()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func status(for remoteID: UUID) -> RemoteStatus {
        statuses[remoteID] ?? .disconnected
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func statusBadgeRawValue(for remoteID: UUID) -> String {
        if isRemoteInRecoveryReconnect(remoteID) {
            return "reconnecting"
        }
        return status(for: remoteID).state.rawValue
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func isRemoteInRecoveryReconnect(_ remoteID: UUID) -> Bool {
        guard desiredConnections.contains(remoteID) else {
            return false
        }

        let state = status(for: remoteID).state
        guard state != .disconnecting else {
            return false
        }

        if reconnectInFlight.contains(remoteID) || reconnectTasks[remoteID] != nil {
            return true
        }

        if let reason = recoveryIndicatorReason?.lowercased() {
            let isWakeOrNetworkRecovery = reason.contains("wake") || reason.contains("network-restored")
            if isWakeOrNetworkRecovery,
               (recoveryBurstTask != nil || (wakeAnimationUntil ?? .distantPast) > Date()) {
                return true
            }
        }

        if state == .connected {
            return false
        }

        if let attempts = reconnectAttempts[remoteID], attempts > 0 {
            return true
        }

        if (recoveryNonConnectedStrikes[remoteID] ?? 0) > 0 {
            return true
        }

        return recoveryIndicator != nil && (state == .error || state == .disconnected)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func setStatus(_ status: RemoteStatus, for remoteID: UUID) {
        var updated = statuses
        updated[remoteID] = status
        statuses = updated
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func removeStatus(for remoteID: UUID) {
        var updated = statuses
        updated.removeValue(forKey: remoteID)
        statuses = updated
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func observeStatus(_ status: RemoteStatus, for remoteID: UUID) {
        setStatus(status, for: remoteID)

        if status.state == .connected {
            desiredConnections.insert(remoteID)
            reconnectAttempts[remoteID] = 0
            reconnectInFlight.remove(remoteID)
            recoveryNonConnectedStrikes[remoteID] = 0
            lastRecoveryRefreshAt[remoteID] = Date()
        } else if !desiredConnections.contains(remoteID) {
            reconnectAttempts.removeValue(forKey: remoteID)
            reconnectInFlight.remove(remoteID)
            recoveryNonConnectedStrikes.removeValue(forKey: remoteID)
            lastRecoveryRefreshAt.removeValue(forKey: remoteID)
        }

        refreshRecoveryIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func saveDraft(_ draft: RemoteDraft) -> [String] {
        let validationErrors = validationErrors(for: draft)
        if !validationErrors.isEmpty {
            return validationErrors
        }

        do {
            // Convert edit-form state to immutable stored config and persist JSON first.
            let previousRemote = remotes.first(where: { $0.id == draft.id })
            let remote = draft.asRemoteConfig()
            try remoteStore.upsert(remote)

            do {
                if remote.authMode == .password {
                    // Passwords are never written to remotes.json; only to Keychain.
                    if !draft.password.isEmpty {
                        try keychainService.savePassword(remoteID: remote.id.uuidString, password: draft.password)
                        cachePassword(draft.password, for: remote.id)
                    }
                } else {
                    // If auth mode switched away from password, remove old secret.
                    do {
                        try keychainService.deletePassword(remoteID: remote.id.uuidString)
                    } catch {
                        diagnostics.append(
                            level: .warning,
                            category: "store",
                            message: "Failed to delete keychain password for \(remote.displayName): \(error.localizedDescription)"
                        )
                    }
                    cachePassword(nil, for: remote.id)
                }
            } catch {
                try rollbackRemoteStoreAfterCredentialFailure(
                    failedRemoteID: remote.id,
                    previousRemote: previousRemote
                )
                throw error
            }

            // Reload to keep list sorting and selection logic centralized in one path.
            load()
            diagnostics.append(level: .info, category: "store", message: "Saved remote \(remote.displayName)")
            return []
        } catch {
            diagnostics.append(level: .error, category: "store", message: error.localizedDescription)
            return [error.localizedDescription]
        }
    }

    /// Beginner note: Reverts persisted remote config when credential update fails
    /// so config and keychain state do not drift out of sync.
    private func rollbackRemoteStoreAfterCredentialFailure(
        failedRemoteID: UUID,
        previousRemote: RemoteConfig?
    ) throws {
        do {
            if let previousRemote {
                try remoteStore.upsert(previousRemote)
            } else {
                try remoteStore.delete(id: failedRemoteID)
            }
        } catch {
            diagnostics.append(
                level: .error,
                category: "store",
                message: "Failed to rollback store after credential error for \(failedRemoteID.uuidString): \(error.localizedDescription)"
            )
            throw error
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func validationErrors(for draft: RemoteDraft) -> [String] {
        // Avoid keychain reads during Save validation so editing/saving does not
        // repeatedly trigger macOS keychain authorization prompts.
        //
        // For existing remotes that were already in password mode, treat
        // "stored password exists" as true and allow empty draft password to
        // mean "keep existing keychain secret unchanged".
        let hasStoredPassword: Bool
        if let id = draft.id,
           let existingRemote = remotes.first(where: { $0.id == id }) {
            hasStoredPassword = existingRemote.authMode == .password
        } else {
            hasStoredPassword = false
        }

        var errors = validationService.validateDraft(draft, hasStoredPassword: hasStoredPassword)
        errors.append(contentsOf: uniquenessValidationErrors(for: draft))
        return deduplicatedErrors(errors)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func uniquenessValidationErrors(for draft: RemoteDraft) -> [String] {
        var errors: [String] = []

        let editingID = draft.id
        let requestedName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let requestedMountPoint = normalizedMountPath(draft.localMountPoint)

        if !requestedName.isEmpty,
           let conflictingRemote = remotes.first(where: {
               $0.id != editingID &&
               $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == requestedName
           }) {
            errors.append("Display name must be unique. '\(conflictingRemote.displayName)' already exists.")
        }

        if !requestedMountPoint.isEmpty,
           let conflictingRemote = remotes.first(where: {
               $0.id != editingID &&
               normalizedMountPath($0.localMountPoint) == requestedMountPoint
           }) {
            errors.append("Local mount point is already used by '\(conflictingRemote.displayName)'. Choose a different folder.")
        }

        return errors
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func normalizedMountPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        var normalized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        if normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized.lowercased()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func mountPointConflict(for remote: RemoteConfig) -> RemoteConfig? {
        let targetPath = normalizedMountPath(remote.localMountPoint)
        guard !targetPath.isEmpty else {
            return nil
        }

        return remotes.first(where: {
            $0.id != remote.id && normalizedMountPath($0.localMountPoint) == targetPath
        })
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func deduplicatedErrors(_ errors: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for error in errors where !seen.contains(error) {
            seen.insert(error)
            ordered.append(error)
        }
        return ordered
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func deleteRemote(_ remoteID: UUID) {
        guard let remote = remotes.first(where: { $0.id == remoteID }) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            desiredConnections.remove(remoteID)
            reconnectAttempts.removeValue(forKey: remoteID)
            reconnectInFlight.remove(remoteID)
            recoveryNonConnectedStrikes.removeValue(forKey: remoteID)
            lastRecoveryRefreshAt.removeValue(forKey: remoteID)
            cancelScheduledReconnect(for: remoteID)

            await runOperation(
                remoteID: remoteID,
                intent: .disconnect,
                trigger: .manual,
                conflictPolicy: .latestIntentWins,
                timeout: disconnectWatchdogTimeout
            ) { [weak self] operationID in
                await self?.performDisconnect(
                    remoteID: remoteID,
                    operationID: operationID,
                    suppressUserAlerts: true
                )
            }

            let finalState = status(for: remoteID).state
            if finalState != .disconnected {
                alertMessage = "Could not delete '\(remote.displayName)' because it is still mounted or busy. Disconnect and retry."
                diagnostics.append(
                    level: .warning,
                    category: "store",
                    message: "Delete blocked for \(remote.displayName): remote did not reach disconnected state."
                )
                return
            }

            do {
                try remoteStore.delete(id: remoteID)
                do {
                    try keychainService.deletePassword(remoteID: remoteID.uuidString)
                } catch {
                    diagnostics.append(
                        level: .warning,
                        category: "store",
                        message: "Failed to delete keychain password for deleted remote \(remote.displayName): \(error.localizedDescription)"
                    )
                }
                cachePassword(nil, for: remoteID)
                remotes.removeAll { $0.id == remoteID }
                removeStatus(for: remoteID)
                if selectedRemoteID == remoteID {
                    selectedRemoteID = remotes.first?.id
                }
                diagnostics.append(level: .info, category: "store", message: "Deleted remote \(remote.displayName)")
            } catch {
                alertMessage = error.localizedDescription
                diagnostics.append(level: .error, category: "store", message: error.localizedDescription)
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func connect(remoteID: UUID) async {
        guard !shutdownInProgress else {
            return
        }
        await connect(remoteID: remoteID, trigger: .manual, suppressUserAlerts: false)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func disconnect(remoteID: UUID) async {
        guard !shutdownInProgress else {
            return
        }
        await runOperation(
            remoteID: remoteID,
            intent: .disconnect,
            trigger: .manual,
            conflictPolicy: .latestIntentWins,
            timeout: disconnectWatchdogTimeout
        ) { [weak self] operationID in
            await self?.performDisconnect(remoteID: remoteID, operationID: operationID, suppressUserAlerts: false)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func refreshStatus(remoteID: UUID) async {
        guard !shutdownInProgress else {
            return
        }
        await runOperation(
            remoteID: remoteID,
            intent: .refresh,
            trigger: .manual,
            conflictPolicy: .skipIfBusy,
            timeout: refreshWatchdogTimeout
        ) { [weak self] operationID in
            await self?.performRefreshStatus(remoteID: remoteID, operationID: operationID)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func refreshAllStatuses() async {
        guard !shutdownInProgress else {
            return
        }
        await withTaskGroup(of: Void.self) { group in
            for remote in remotes {
                group.addTask { @MainActor [weak self] in
                    await self?.refreshStatus(remoteID: remote.id)
                }
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func runStartupAutoConnect() async {
        guard !shutdownInProgress else {
            return
        }
        let launchTargetIDs = Self.startupAutoConnectRemoteIDs(from: remotes)
        let launchTargets = remotes.filter { launchTargetIDs.contains($0.id) }
        guard !launchTargets.isEmpty else {
            return
        }

        pendingStartupAutoConnectIDs.formUnion(launchTargets.map(\.id))
        desiredConnections.formUnion(launchTargets.map(\.id))

        diagnostics.append(
            level: .info,
            category: "startup",
            message: "Startup auto-connect queued for \(launchTargets.count) remote(s)."
        )

        guard networkReachable else {
            diagnostics.append(
                level: .info,
                category: "startup",
                message: "Deferring startup auto-connect for \(launchTargets.count) remote(s): network is not reachable yet."
            )
            return
        }

        await runPendingStartupAutoConnect(trigger: "startup")
    }

    /// Beginner note: Startup auto-connect can be deferred until network becomes reachable.
    /// This helper runs the pending set exactly once per remote.
    private func runPendingStartupAutoConnect(trigger: String) async {
        if startupAutoConnectInProgress {
            startupAutoConnectRerunRequested = true
            diagnostics.append(
                level: .debug,
                category: "startup",
                message: "Startup auto-connect already in progress. Scheduling follow-up pass (\(trigger))."
            )
            return
        }

        startupAutoConnectInProgress = true
        defer {
            startupAutoConnectInProgress = false
        }

        while true {
            startupAutoConnectRerunRequested = false
            let pendingIDs = pendingStartupAutoConnectIDs
            guard !pendingIDs.isEmpty else {
                return
            }

            let launchTargets = remotes.filter { pendingIDs.contains($0.id) }
            guard !launchTargets.isEmpty else {
                pendingStartupAutoConnectIDs.removeAll()
                return
            }

            if trigger != "startup" {
                diagnostics.append(
                    level: .info,
                    category: "startup",
                    message: "Running deferred startup auto-connect for \(launchTargets.count) remote(s) after \(trigger)."
                )
            }

            let connectTargets = launchTargets.filter { status(for: $0.id).state != .connected }
            await primeStartupPasswordCache(for: connectTargets)

            await withTaskGroup(of: Void.self) { group in
                for remote in launchTargets {
                    group.addTask { @MainActor [weak self] in
                        guard let self else {
                            return
                        }
                        guard self.remotes.contains(where: { $0.id == remote.id }) else {
                            return
                        }

                        if self.status(for: remote.id).state == .connected {
                            self.desiredConnections.insert(remote.id)
                            self.reconnectAttempts[remote.id] = 0
                            self.reconnectInFlight.remove(remote.id)
                            return
                        }

                        await self.connect(
                            remoteID: remote.id,
                            trigger: .startup,
                            suppressUserAlerts: true
                        )
                    }
                }
                await group.waitForAll()
            }

            pendingStartupAutoConnectIDs.subtract(launchTargets.map(\.id))

            guard startupAutoConnectRerunRequested else {
                return
            }
        }
    }

    /// Beginner note: Startup keychain access is primed sequentially to avoid concurrent auth prompts.
    /// After priming, connects run in parallel using cached passwords.
    private func primeStartupPasswordCache(for remotes: [RemoteConfig]) async {
        let passwordRemotes = remotes.filter { $0.authMode == .password }
        guard !passwordRemotes.isEmpty else {
            return
        }

        for remote in passwordRemotes {
            // Respect global policy for background flows: no keychain auth popups unless explicitly enabled.
            let allowInteraction = allowInteractiveKeychainReads

            _ = await resolvedPasswordForRemote(
                remote.id,
                allowUserInteraction: allowInteraction
            )
        }
    }

    /// Beginner note: Emergency user action that aggressively tears down all mount processes.
    /// This is used when stale mounts are degrading Finder/system responsiveness.
    /// This is async: it can suspend and resume later without blocking a thread.
    func forceResetAllMountsFromMenu() async {
        guard !shutdownInProgress else {
            return
        }

        diagnostics.append(level: .warning, category: "operations", message: "Manual force reset requested for all remotes.")

        for remoteID in Array(remoteOperations.keys) {
            cancelOperation(
                remoteID: remoteID,
                reason: "manual-force-reset",
                supersededBy: nil,
                removeFromTable: true
            )
        }
        remoteOperations.removeAll()

        cancelAllScheduledReconnects(reason: "manual-force-reset")
        reconnectInFlight.removeAll()
        reconnectAttempts.removeAll()
        recoveryNonConnectedStrikes.removeAll()
        lastRecoveryRefreshAt.removeAll()
        desiredConnections.removeAll()
        clearRecoveryIndicator()

        let sessionsToClose = Array(activeBrowserSessions)
        activeBrowserSessions.removeAll()
        if !sessionsToClose.isEmpty {
            for sessionID in sessionsToClose {
                await remoteDirectoryBrowserService.closeSession(sessionID)
            }
        }

        for remote in remotes {
            let forceStopQueuedAt = Date()
            logMountCall(op: "forceStopProcesses", remoteID: remote.id, operationID: nil, queuedAt: forceStopQueuedAt)
            await mountManager.forceStopProcesses(
                for: remote,
                queuedAt: forceStopQueuedAt,
                operationID: nil
            )
            let disconnected = RemoteStatus(
                state: .disconnected,
                mountedPath: nil,
                lastError: nil,
                updatedAt: Date()
            )
            setStatus(disconnected, for: remote.id)
        }

        alertMessage = "Force reset complete. Use Connect to reconnect remotes."
        diagnostics.append(level: .info, category: "operations", message: "Manual force reset completed.")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    private func connect(remoteID: UUID, trigger: RemoteOperationTrigger, suppressUserAlerts: Bool) async {
        let conflictPolicy: RemoteOperationConflictPolicy = trigger == .manual ? .latestIntentWins : .skipIfBusy
        await runOperation(
            remoteID: remoteID,
            intent: .connect,
            trigger: trigger,
            conflictPolicy: conflictPolicy,
            timeout: connectWatchdogTimeout
        ) { [weak self] operationID in
            await self?.performConnect(
                remoteID: remoteID,
                trigger: trigger,
                suppressUserAlerts: suppressUserAlerts,
                operationID: operationID
            )
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func runOperation(
        remoteID: UUID,
        intent: RemoteOperationIntent,
        trigger: RemoteOperationTrigger,
        conflictPolicy: RemoteOperationConflictPolicy,
        timeout: TimeInterval,
        execute: @escaping @MainActor (UUID) async -> Void
    ) async {
        guard remotes.contains(where: { $0.id == remoteID }) else {
            return
        }

        let operationID = UUID()
        // Conflict policy:
        // - skipIfBusy: ignore new request if this remote already has active work.
        // - latestIntentWins: cancel old work and prefer most recent user intent.
        if remoteOperations[remoteID] != nil {
            switch conflictPolicy {
            case .skipIfBusy:
                if let current = remoteOperations[remoteID] {
                    let elapsed = Date().timeIntervalSince(current.startedAt)
                    let shouldReplaceStalledOperation = Self.shouldReplaceBusyOperation(
                        newIntent: intent,
                        newTrigger: trigger,
                        existingIntent: current.intent,
                        elapsedSeconds: elapsed,
                        thresholdSeconds: stalledOperationReplacementSeconds
                    )

                    if shouldReplaceStalledOperation {
                        diagnostics.append(
                            level: .warning,
                            category: "operations",
                            message: "Replacing stalled \(current.intent.rawValue) for \(remoteID.uuidString) after \(Int(elapsed))s with \(intent.rawValue) (\(trigger.rawValue))."
                        )
                        cancelOperation(
                            remoteID: remoteID,
                            reason: "replaced-stalled-\(current.intent.rawValue)",
                            supersededBy: operationID
                        )
                        break
                    }
                }

                diagnostics.append(
                    level: .debug,
                    category: "operations",
                    message: "Skipped \(intent.rawValue) for \(remoteID.uuidString) (\(trigger.rawValue)) because another operation is active."
                )
                return
            case .latestIntentWins:
                cancelOperation(
                    remoteID: remoteID,
                    reason: "superseded-by-\(intent.rawValue)",
                    supersededBy: operationID
                )
            }
        }

        let operationState = RemoteOperationState(
            operationID: operationID,
            remoteID: remoteID,
            intent: intent,
            trigger: trigger,
            startedAt: Date()
        )
        remoteOperations[remoteID] = operationState
        refreshRecoveryIndicator()

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            // Cross-remote global limiter (max 4 in parallel) to prevent overload.
            let limiterQueuedAt = Date()
            await self.operationLimiter.acquire()
            let limiterWaitMs = max(0, Int(Date().timeIntervalSince(limiterQueuedAt) * 1_000))
            defer {
                Task {
                    await self.operationLimiter.release()
                }
            }

            // If operation was replaced before execution started, stop early.
            guard self.isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
                return
            }

            let startTime = Date()
            self.scheduleOperationWatchdog(
                remoteID: remoteID,
                operationID: operationID,
                intent: intent,
                timeout: timeout
            )

            let operationLogLevel: DiagnosticLevel = (intent == .refresh && trigger == .recovery) ? .debug : .info

            self.diagnostics.append(
                level: operationLogLevel,
                category: "operations",
                message: "Operation start remoteID=\(remoteID.uuidString) operationID=\(operationID.uuidString) intent=\(intent.rawValue) trigger=\(trigger.rawValue) limiterWaitMs=\(limiterWaitMs)"
            )

            await execute(operationID)

            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1_000)
            // cancelled=true also covers "superseded by newer intent" cases.
            let cancelled = Task.isCancelled || !(self.isOperationCurrent(remoteID: remoteID, operationID: operationID))
            let supersededBy = self.remoteOperations[remoteID]?.supersededBy?.uuidString ?? "-"

            self.diagnostics.append(
                level: operationLogLevel,
                category: "operations",
                message: "Operation end remoteID=\(remoteID.uuidString) operationID=\(operationID.uuidString) intent=\(intent.rawValue) trigger=\(trigger.rawValue) elapsedMs=\(elapsedMs) cancelled=\(cancelled) supersededBy=\(supersededBy)"
            )

            self.finishOperation(remoteID: remoteID, operationID: operationID)
        }

        operationState.task = task
        await task.value
    }

    /// Beginner note: This helper writes a correlation log right before a MountManager call.
    /// queuedAt is captured before awaiting the actor so queueDelayMs reflects true queueing time.
    private func logMountCall(
        op: String,
        remoteID: UUID,
        operationID: UUID?,
        queuedAt: Date
    ) {
        let queuedAtMs = Int(queuedAt.timeIntervalSince1970 * 1_000)
        let now = Date()
        let nowMs = Int(now.timeIntervalSince1970 * 1_000)
        let preAwaitDelayMs = max(0, Int(now.timeIntervalSince(queuedAt) * 1_000))
        let opAgeMsText: String
        if let operationID,
           let state = remoteOperations[remoteID],
           state.operationID == operationID {
            opAgeMsText = String(max(0, Int(now.timeIntervalSince(state.startedAt) * 1_000)))
        } else {
            opAgeMsText = "-"
        }
        diagnostics.append(
            level: .debug,
            category: "operations",
            message: "mount call op=\(op) remoteID=\(remoteID.uuidString) operationID=\(operationID?.uuidString ?? "-") queuedAtMs=\(queuedAtMs) nowMs=\(nowMs) preAwaitDelayMs=\(preAwaitDelayMs) opAgeMs=\(opAgeMsText)"
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func isOperationCurrent(remoteID: UUID, operationID: UUID) -> Bool {
        guard let current = remoteOperations[remoteID] else {
            return false
        }
        return current.operationID == operationID && !current.cancelled
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func finishOperation(remoteID: UUID, operationID: UUID) {
        cancelOperationWatchdog(operationID: operationID)
        guard let current = remoteOperations[remoteID], current.operationID == operationID else {
            return
        }
        remoteOperations.removeValue(forKey: remoteID)
        refreshRecoveryIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func cancelOperation(
        remoteID: UUID,
        reason: String,
        supersededBy: UUID?,
        removeFromTable: Bool = true
    ) {
        guard let current = remoteOperations[remoteID] else {
            return
        }

        current.cancelled = true
        current.supersededBy = supersededBy
        cancelOperationWatchdog(operationID: current.operationID)
        current.task?.cancel()

        if removeFromTable, remoteOperations[remoteID]?.operationID == current.operationID {
            remoteOperations.removeValue(forKey: remoteID)
        }

        let supersededByText = supersededBy?.uuidString ?? "-"
        diagnostics.append(
            level: .debug,
            category: "operations",
            message: "Operation cancelled remoteID=\(remoteID.uuidString) operationID=\(current.operationID.uuidString) reason=\(reason) supersededBy=\(supersededByText)"
        )
        refreshRecoveryIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func performConnect(
        remoteID: UUID,
        trigger: RemoteOperationTrigger,
        suppressUserAlerts: Bool,
        operationID: UUID
    ) async {
        guard !shutdownInProgress else {
            return
        }
        guard let remote = remotes.first(where: { $0.id == remoteID }) else {
            return
        }
        guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
            return
        }

        let existingState = status(for: remoteID).state
        if existingState == .connecting || existingState == .connected {
            return
        }

        if let conflictingRemote = mountPointConflict(for: remote) {
            guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
                return
            }
            let conflictStatus = RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: "Local mount point is shared with '\(conflictingRemote.displayName)'. Use a unique local mount folder.",
                updatedAt: Date()
            )
            observeStatus(conflictStatus, for: remote.id)
            if trigger == .manual && !suppressUserAlerts {
                alertMessage = conflictStatus.lastError
            }
            desiredConnections.remove(remote.id)
            diagnostics.append(
                level: .warning,
                category: "mount",
                message: "Blocked connect for \(remote.displayName): local mount point conflicts with \(conflictingRemote.displayName)"
            )
            return
        }

        if trigger != .recovery {
            // Manual/startup connect means "user wants this held connected".
            desiredConnections.insert(remote.id)
        }

        guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
            return
        }
        setStatus(
            RemoteStatus(
                state: .connecting,
                mountedPath: nil,
                lastError: nil,
                updatedAt: Date()
            ),
            for: remote.id
        )

        var password: String?
        if remote.authMode == .password {
            // Existing remotes reuse Keychain password; draft editor handles initial save.
            password = await resolvedPasswordForRemote(
                remote.id,
                allowUserInteraction: allowInteractiveKeychainReads
            )
            if password?.isEmpty != false {
                guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
                    return
                }
                let status = RemoteStatus(
                    state: .error,
                    mountedPath: nil,
                    lastError: "Password is missing or unavailable. Edit remote and save password again.",
                    updatedAt: Date()
                )
                observeStatus(status, for: remote.id)
                if trigger == .manual && !suppressUserAlerts {
                    alertMessage = status.lastError
                } else {
                    stopAutoReconnectIfPermanentFailure(for: remote.id, message: status.lastError)
                }
                diagnostics.append(level: .warning, category: "mount", message: "Password missing for remote \(remote.displayName)")
                return
            }
        }

        let queuedAt = Date()
        logMountCall(op: "connect", remoteID: remoteID, operationID: operationID, queuedAt: queuedAt)
        let (connectStatus, connectTimedOut) = await runRemoteOperationWithTimeout(
            timeoutSeconds: connectTimeoutSeconds
        ) { [mountManager, remote, password] in
            await mountManager.connect(
                remote: remote,
                password: password,
                queuedAt: queuedAt,
                operationID: operationID
            )
        }

        let stillCurrent = isOperationCurrent(remoteID: remoteID, operationID: operationID)
        if connectTimedOut || Task.isCancelled || !stillCurrent {
            if let active = remoteOperations[remoteID], active.operationID != operationID {
                // Superseded by a newer operation; do not tear down its in-flight work.
            } else {
                let forceStopQueuedAt = Date()
                logMountCall(op: "forceStopProcesses", remoteID: remoteID, operationID: operationID, queuedAt: forceStopQueuedAt)
                await mountManager.forceStopProcesses(
                    for: remote,
                    queuedAt: forceStopQueuedAt,
                    operationID: operationID
                )
            }
        }

        guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
            return
        }

        let status: RemoteStatus
        if connectTimedOut {
            // Keep desired connection intent so recovery can retry transient failures.
            status = RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: "Connect timed out. Check network/host and retry.",
                updatedAt: Date()
            )
        } else {
            status = connectStatus ?? RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: "Connect failed with unknown error.",
                updatedAt: Date()
            )
        }

        observeStatus(status, for: remote.id)

        if status.state == .error,
           let message = status.lastError,
           !message.isEmpty,
           trigger == .manual,
           !suppressUserAlerts {
            alertMessage = message
        } else if status.state == .error, trigger == .recovery {
            // Recovery failures increase backoff attempts instead of immediate alert spam.
            stopAutoReconnectIfPermanentFailure(for: remote.id, message: status.lastError)
            let attempts = min((reconnectAttempts[remote.id] ?? 0) + 1, 8)
            reconnectAttempts[remote.id] = attempts
        } else if status.state == .connected {
            reconnectAttempts[remote.id] = 0
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func performDisconnect(
        remoteID: UUID,
        operationID: UUID,
        suppressUserAlerts: Bool
    ) async {
        guard !shutdownInProgress else {
            return
        }
        guard let remote = remotes.first(where: { $0.id == remoteID }) else {
            return
        }
        guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
            return
        }

        let existingState = status(for: remoteID).state
        if existingState == .disconnected || existingState == .disconnecting {
            return
        }

        desiredConnections.remove(remote.id)
        reconnectAttempts.removeValue(forKey: remote.id)
        reconnectInFlight.remove(remote.id)
        cancelScheduledReconnect(for: remote.id)

        guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
            return
        }

        setStatus(
            RemoteStatus(
                state: .disconnecting,
                mountedPath: nil,
                lastError: nil,
                updatedAt: Date()
            ),
            for: remote.id
        )

        let queuedAt = Date()
        logMountCall(op: "disconnect", remoteID: remoteID, operationID: operationID, queuedAt: queuedAt)
        let (disconnectStatus, disconnectTimedOut) = await runRemoteOperationWithTimeout(
            timeoutSeconds: disconnectTimeoutSeconds
        ) { [mountManager, remote] in
            await mountManager.disconnect(
                remote: remote,
                queuedAt: queuedAt,
                operationID: operationID
            )
        }
        guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
            return
        }

        let status: RemoteStatus
        if disconnectTimedOut {
            // Fallback path: force-stop sshfs for this remote and re-check mount state.
            let forceStopQueuedAt = Date()
            logMountCall(op: "forceStopProcesses", remoteID: remoteID, operationID: operationID, queuedAt: forceStopQueuedAt)
            await mountManager.forceStopProcesses(
                for: remote,
                queuedAt: forceStopQueuedAt,
                operationID: operationID
            )
            guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
                return
            }
            let refreshQueuedAt = Date()
            logMountCall(op: "refreshStatus", remoteID: remoteID, operationID: operationID, queuedAt: refreshQueuedAt)
            let refreshed = await mountManager.refreshStatus(
                remote: remote,
                queuedAt: refreshQueuedAt,
                operationID: operationID
            )
            guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
                return
            }

            if refreshed.state == .disconnected {
                status = refreshed
            } else {
                status = RemoteStatus(
                    state: .error,
                    mountedPath: nil,
                    lastError: "Disconnect timed out after \(Int(disconnectWatchdogTimeout))s. Close any files using the mount, then retry.",
                    updatedAt: Date()
                )
            }
        } else {
            status = disconnectStatus ?? RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: "Disconnect failed with unknown error.",
                updatedAt: Date()
            )
        }

        observeStatus(status, for: remote.id)

        if status.state == .error,
           let message = status.lastError,
           !message.isEmpty,
           !suppressUserAlerts {
            alertMessage = message
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    private func performRefreshStatus(remoteID: UUID, operationID: UUID) async {
        guard !shutdownInProgress else {
            return
        }
        guard let remote = remotes.first(where: { $0.id == remoteID }) else {
            return
        }
        guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
            return
        }

        let state = status(for: remoteID).state
        if state == .connecting || state == .disconnecting {
            return
        }

        if let conflictingRemote = mountPointConflict(for: remote) {
            guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
                return
            }
            let conflictStatus = RemoteStatus(
                state: .error,
                mountedPath: nil,
                lastError: "Local mount point is shared with '\(conflictingRemote.displayName)'. Use a unique local mount folder.",
                updatedAt: Date()
            )
            observeStatus(conflictStatus, for: remote.id)
            return
        }

        let queuedAt = Date()
        logMountCall(op: "refreshStatus", remoteID: remoteID, operationID: operationID, queuedAt: queuedAt)
        let status = await mountManager.refreshStatus(
            remote: remote,
            queuedAt: queuedAt,
            operationID: operationID
        )
        guard isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
            return
        }
        observeStatus(status, for: remote.id)
        lastRecoveryRefreshAt[remote.id] = Date()
    }

    nonisolated static func startupAutoConnectRemoteIDs(from remotes: [RemoteConfig]) -> [UUID] {
        remotes.filter(\.autoConnectOnLaunch).map(\.id)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func reconcileConnectionTrackingState() {
        let validIDs = Set(remotes.map(\.id))
        desiredConnections = desiredConnections.intersection(validIDs)
        reconnectInFlight = reconnectInFlight.intersection(validIDs)
        reconnectAttempts = reconnectAttempts.filter { validIDs.contains($0.key) }
        recoveryNonConnectedStrikes = recoveryNonConnectedStrikes.filter { validIDs.contains($0.key) }
        lastRecoveryRefreshAt = lastRecoveryRefreshAt.filter { validIDs.contains($0.key) }
        passwordCache = passwordCache.filter { validIDs.contains($0.key) }
        pendingStartupAutoConnectIDs = pendingStartupAutoConnectIDs.intersection(validIDs)

        for remoteID in Array(reconnectTasks.keys) where !validIDs.contains(remoteID) {
            cancelScheduledReconnect(for: remoteID)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func startRecoveryMonitoringIfNeeded() {
        guard !recoveryMonitoringStarted else {
            return
        }
        recoveryMonitoringStarted = true

        registerWorkspaceObservers()
        startNetworkMonitor()
        startRecoveryTimer()

        diagnostics.append(level: .info, category: "recovery", message: "Connection recovery monitoring started.")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func registerWorkspaceObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        let willSleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWillSleep()
            }
        }

        let didWakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemDidWake()
            }
        }

        let didUnmountObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleVolumeDidUnmount(notification.userInfo)
            }
        }

        workspaceObservers.append(willSleepObserver)
        workspaceObservers.append(didWakeObserver)
        workspaceObservers.append(didUnmountObserver)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func startNetworkMonitor() {
        guard networkMonitor == nil else {
            return
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handleNetworkStatusChange(isReachable: path.status == .satisfied)
            }
        }
        monitor.start(queue: networkMonitorQueue)
        networkMonitor = monitor
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func startRecoveryTimer() {
        guard recoveryTimer == nil else {
            return
        }

        // By design this interval is shorter than healthyPeriodicProbeInterval.
        // The timer drives the "should we probe?" decision loop, while deeper probes are throttled separately.
        let timer = Timer(timeInterval: periodicRecoveryPassInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                await self.performRecoveryPass(trigger: "periodic")
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        recoveryTimer = timer
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func beginRecoveryIndicator(reason: String) {
        recoveryIndicatorReason = reason
        let startedAt = recoveryIndicator?.startedAt ?? Date()
        recoveryIndicator = RecoveryIndicator(
            reason: reason,
            startedAt: startedAt,
            pendingRemoteCount: 0,
            scheduledReconnectCount: reconnectTasks.count + reconnectInFlight.count
        )
        refreshRecoveryIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func clearRecoveryIndicator() {
        recoveryIndicatorReason = nil
        recoveryIndicator = nil
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func refreshRecoveryIndicator() {
        guard !systemSleeping else {
            clearRecoveryIndicator()
            return
        }

        guard let reason = recoveryIndicatorReason else {
            recoveryIndicator = nil
            return
        }

        let pendingRemoteCount = remotes.reduce(0) { partial, remote in
            guard desiredConnections.contains(remote.id) else {
                return partial
            }

            let state = status(for: remote.id).state
            return state == .connected ? partial : partial + 1
        }

        let scheduledReconnectCount = reconnectTasks.count + reconnectInFlight.count
        let burstActive = recoveryBurstTask != nil
        let normalizedReason = reason.lowercased()
        let isWakeOrNetworkRecovery = normalizedReason.contains("wake") || normalizedReason.contains("network-restored")
        let wakeWindowActive = (wakeAnimationUntil ?? .distantPast) > Date()
        let shouldShow = burstActive || pendingRemoteCount > 0 || scheduledReconnectCount > 0 || (isWakeOrNetworkRecovery && wakeWindowActive)

        if shouldShow {
            let startedAt = recoveryIndicator?.startedAt ?? Date()
            recoveryIndicator = RecoveryIndicator(
                reason: reason,
                startedAt: startedAt,
                pendingRemoteCount: pendingRemoteCount,
                scheduledReconnectCount: scheduledReconnectCount
            )
        } else {
            clearRecoveryIndicator()
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func handleSystemWillSleep() {
        systemSleeping = true
        wakePreflightInProgress = false
        wakeAnimationUntil = nil
        recoveryBurstTask?.cancel()
        recoveryBurstTask = nil
        for remoteID in Array(remoteOperations.keys) {
            cancelOperation(
                remoteID: remoteID,
                reason: "system-sleep",
                supersededBy: nil,
                removeFromTable: true
            )
        }
        cancelAllScheduledReconnects(reason: "system-sleep")
        clearRecoveryIndicator()
        diagnostics.append(level: .info, category: "recovery", message: "System is going to sleep.")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func handleSystemDidWake() {
        systemSleeping = false
        wakePreflightInProgress = true
        wakeAnimationUntil = Date().addingTimeInterval(20)
        beginRecoveryIndicator(reason: "wake")
        refreshRecoveryIndicator()
        diagnostics.append(level: .info, category: "recovery", message: "System woke up. Running staged recovery passes.")
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.wakePreflightInProgress = false
                self.lastWakePreflightSkipLogAt = .distantPast
                self.refreshRecoveryIndicator()
            }
            await self.performWakePreflightCleanup()
            self.scheduleRecoveryBurst(trigger: "wake", delaySeconds: Self.recoveryBurstDelays(for: "wake"))
        }
    }

    /// Beginner note: Wake preflight clears stale sshfs state for desired remotes
    /// before staged reconnect passes. This prevents stale mounts from wedging Finder/UI.
    private func performWakePreflightCleanup() async {
        guard !shutdownInProgress else {
            return
        }

        let targets = remotes.filter { desiredConnections.contains($0.id) }
        guard !targets.isEmpty else {
            return
        }

        let startedAt = Date()
        diagnostics.append(
            level: .info,
            category: "recovery",
            message: "Wake preflight cleanup for \(targets.count) desired remote(s) (parallel, aggressive unmount)."
        )

        // Cancel any in-flight per-remote operations before cleanup starts.
        for remote in targets {
            if remoteOperations[remote.id] != nil {
                cancelOperation(
                    remoteID: remote.id,
                    reason: "wake-preflight",
                    supersededBy: nil,
                    removeFromTable: true
                )
            }
        }

        let mountManager = self.mountManager
        var completedRemoteNames: [String] = []

        await withTaskGroup(of: (UUID, String).self) { group in
            for remote in targets {
                let forceStopQueuedAt = Date()
                logMountCall(op: "forceStopProcesses", remoteID: remote.id, operationID: nil, queuedAt: forceStopQueuedAt)

                group.addTask {
                    await mountManager.forceStopProcesses(
                        for: remote,
                        queuedAt: forceStopQueuedAt,
                        operationID: nil,
                        aggressiveUnmount: true
                    )
                    return (remote.id, remote.displayName)
                }
            }

            for await (remoteID, remoteName) in group {
                completedRemoteNames.append(remoteName)
                let disconnected = RemoteStatus(
                    state: .disconnected,
                    mountedPath: nil,
                    lastError: "Re-establishing connection after wake.",
                    updatedAt: Date()
                )
                observeStatus(disconnected, for: remoteID)
            }
        }

        let elapsedMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        let names = completedRemoteNames.sorted().joined(separator: ", ")
        diagnostics.append(
            level: .info,
            category: "recovery",
            message: "Wake preflight cleanup completed in \(elapsedMs)ms for: \(names)."
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func handleVolumeDidUnmount(_ userInfo: [AnyHashable: Any]?) {
        guard !shutdownInProgress else {
            return
        }
        guard let volumeURL = userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
            return
        }

        let unmountedPath = URL(fileURLWithPath: volumeURL.path).standardizedFileURL.path.lowercased()
        guard let remote = remotes.first(where: { normalizedMountPath($0.localMountPoint) == unmountedPath }) else {
            return
        }
        guard desiredConnections.contains(remote.id) else {
            return
        }
        guard !wakePreflightInProgress else {
            diagnostics.append(
                level: .debug,
                category: "recovery",
                message: "Ignoring external unmount for \(remote.displayName) during wake preflight cleanup."
            )
            return
        }

        let currentState = status(for: remote.id).state
        guard currentState != .disconnecting else {
            return
        }

        let message = "Mount was unmounted by macOS. Re-establishing connection."
        let status = RemoteStatus(
            state: .disconnected,
            mountedPath: nil,
            lastError: message,
            updatedAt: Date()
        )
        observeStatus(status, for: remote.id)

        diagnostics.append(
            level: .warning,
            category: "recovery",
            message: "Detected external unmount for \(remote.displayName) at \(volumeURL.path). Scheduling reconnect."
        )

        beginRecoveryIndicator(reason: "volume-unmounted")
        scheduleAutoReconnect(for: remote.id, trigger: "volume-unmounted")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func handleNetworkStatusChange(isReachable: Bool) {
        let previous = networkReachable
        networkReachable = isReachable

        let transition = Self.networkReachabilityTransition(
            previousReachable: previous,
            currentReachable: isReachable
        )
        if transition == .unchanged {
            return
        }

        if transition == .becameReachable {
            networkRestoreDebounceTask?.cancel()
            networkRestoreDebounceTask = Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                if self.networkRestoredDebounceSeconds > 0 {
                    try? await Task.sleep(
                        nanoseconds: UInt64(self.networkRestoredDebounceSeconds * 1_000_000_000)
                    )
                }
                guard !Task.isCancelled else {
                    return
                }
                guard self.networkReachable else {
                    return
                }
                self.beginRecoveryIndicator(reason: "network-restored")
                self.diagnostics.append(
                    level: .info,
                    category: "recovery",
                    message: "Network became reachable. Running staged recovery passes."
                )
                // Run deferred startup intent first so staged recovery refresh does
                // not immediately collide and skip startup connect operations.
                await self.runPendingStartupAutoConnect(trigger: "network-restored")
                self.scheduleRecoveryBurst(
                    trigger: "network-restored",
                    delaySeconds: Self.recoveryBurstDelays(for: "network-restored")
                )
            }
        } else {
            networkRestoreDebounceTask?.cancel()
            networkRestoreDebounceTask = nil
            diagnostics.append(level: .warning, category: "recovery", message: "Network became unreachable. Waiting before reconnect attempts.")
            cancelAllScheduledReconnects(reason: "network-unreachable")
            refreshRecoveryIndicator()
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    private func performRecoveryPass(trigger: String) async {
        refreshRecoveryIndicator()
        guard !systemSleeping else {
            if Date().timeIntervalSince(lastSleepSkipLogAt) >= 60 {
                diagnostics.append(level: .debug, category: "recovery", message: "Skipping recovery pass (\(trigger)) because system is sleeping.")
                lastSleepSkipLogAt = Date()
            }
            return
        }
        guard !wakePreflightInProgress else {
            if Date().timeIntervalSince(lastWakePreflightSkipLogAt) >= 60 {
                diagnostics.append(
                    level: .debug,
                    category: "recovery",
                    message: "Skipping recovery pass (\(trigger)) while wake preflight cleanup is in progress."
                )
                lastWakePreflightSkipLogAt = Date()
            }
            return
        }

        // While wake/network staged recovery bursts are active, avoid piling periodic
        // probes on top. This keeps wake recovery responsive instead of overloaded.
        if trigger.lowercased() == "periodic", recoveryBurstTask != nil {
            diagnostics.append(level: .debug, category: "recovery", message: "Skipping periodic recovery pass while staged recovery burst is active.")
            return
        }

        guard !desiredConnections.isEmpty else {
            return
        }

        guard networkReachable else {
            return
        }

        let dependency = dependencyChecker.check()
        dependencyStatus = dependency
        guard dependency.isReady else {
            diagnostics.append(level: .warning, category: "recovery", message: "Skipping reconnect (\(trigger)): dependencies are not ready.")
            return
        }

        let targetRemotes = remotes.filter { desiredConnections.contains($0.id) }
        guard !targetRemotes.isEmpty else {
            return
        }

        if trigger.lowercased() == "periodic" {
            // Periodic probe is conservative: skip expensive full checks when all healthy.
            if shouldSkipPeriodicRecoveryProbe(for: targetRemotes) {
                diagnostics.append(
                    level: .debug,
                    category: "recovery",
                    message: "Skipping periodic full probe: all desired remotes are healthy and stable."
                )
                return
            }
            lastPeriodicRecoveryProbeAt = Date()
        }

        await withTaskGroup(of: Void.self) { group in
            for remote in targetRemotes {
                group.addTask { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    let currentState = self.status(for: remote.id).state
                    if currentState == .connecting || currentState == .disconnecting {
                        return
                    }

                    if !self.shouldRunRecoveryRefresh(for: remote.id, trigger: trigger) {
                        return
                    }

                    await self.runOperation(
                        remoteID: remote.id,
                        intent: .refresh,
                        trigger: .recovery,
                        conflictPolicy: .skipIfBusy,
                        timeout: self.refreshWatchdogTimeout
                    ) { [weak self] operationID in
                        await self?.performRefreshStatus(remoteID: remote.id, operationID: operationID)
                    }

                    let refreshedState = self.status(for: remote.id).state
                    if refreshedState == .connected {
                        self.recoveryNonConnectedStrikes[remote.id] = 0
                    } else if self.desiredConnections.contains(remote.id) {
                        self.recoveryNonConnectedStrikes[remote.id] = (self.recoveryNonConnectedStrikes[remote.id] ?? 0) + 1
                    }
                }
            }
            await group.waitForAll()
        }

        let requiredStrikes = Self.requiredRecoveryStrikes(for: trigger)
        for remote in targetRemotes {
            guard desiredConnections.contains(remote.id) else {
                continue
            }

            let current = status(for: remote.id)
            if current.state == .connected {
                reconnectAttempts[remote.id] = 0
                reconnectInFlight.remove(remote.id)
                continue
            }

            guard current.state != .connecting, current.state != .disconnecting else {
                continue
            }

            let strikeCount = recoveryNonConnectedStrikes[remote.id] ?? 0
            if strikeCount < requiredStrikes {
                // Require multiple misses before reconnecting to avoid noisy false positives.
                diagnostics.append(
                    level: .debug,
                    category: "recovery",
                    message: "Deferring reconnect for \(remote.displayName) (\(trigger)): strike \(strikeCount)/\(requiredStrikes)."
                )
                continue
            }

            guard !reconnectInFlight.contains(remote.id) else {
                continue
            }

            guard shouldAttemptAutoReconnect(after: current) else {
                stopAutoReconnectIfPermanentFailure(for: remote.id, message: current.lastError)
                continue
            }

            scheduleAutoReconnect(for: remote.id, trigger: trigger)
        }

        refreshRecoveryIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func shouldSkipPeriodicRecoveryProbe(for remotes: [RemoteConfig]) -> Bool {
        guard reconnectTasks.isEmpty, reconnectInFlight.isEmpty, remoteOperations.isEmpty else {
            return false
        }

        let allConnected = remotes.allSatisfy { status(for: $0.id).state == .connected }
        guard allConnected else {
            return false
        }

        return Date().timeIntervalSince(lastPeriodicRecoveryProbeAt) < healthyPeriodicProbeInterval
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func shouldRunRecoveryRefresh(for remoteID: UUID, trigger: String) -> Bool {
        let normalizedTrigger = trigger.lowercased()
        guard normalizedTrigger == "periodic" else {
            return true
        }

        if reconnectInFlight.contains(remoteID) || reconnectTasks[remoteID] != nil {
            return true
        }

        if status(for: remoteID).state != .connected {
            return true
        }

        let lastRefreshAt = lastRecoveryRefreshAt[remoteID] ?? .distantPast
        return Date().timeIntervalSince(lastRefreshAt) >= healthyPeriodicProbeInterval
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func scheduleAutoReconnect(for remoteID: UUID, trigger: String) {
        cancelScheduledReconnect(for: remoteID)
        reconnectInFlight.insert(remoteID)

        let attempt = reconnectAttempts[remoteID] ?? 0
        let lastError = status(for: remoteID).lastError
        let delaySeconds = Self.reconnectDelaySeconds(
            attempt: attempt,
            trigger: trigger,
            lastError: lastError
        )

        diagnostics.append(
            level: .info,
            category: "recovery",
            message: "Scheduling reconnect for \(remoteID.uuidString) in \(delaySeconds)s (\(trigger), attempt \(attempt + 1))."
        )

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                reconnectTasks.removeValue(forKey: remoteID)
                reconnectInFlight.remove(remoteID)
                refreshRecoveryIndicator()
            }

            if delaySeconds > 0 {
                // Backoff delay computed from trigger + attempt + last error type.
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            }
            guard !Task.isCancelled else {
                return
            }

            guard !self.systemSleeping else {
                diagnostics.append(level: .debug, category: "recovery", message: "Reconnect deferred for \(remoteID.uuidString) because system is sleeping.")
                return
            }

            guard self.desiredConnections.contains(remoteID), self.networkReachable else {
                return
            }

            guard self.status(for: remoteID).state != .connected else {
                self.reconnectAttempts[remoteID] = 0
                return
            }

            guard !Task.isCancelled else {
                return
            }

            // Re-verify current mount state right before reconnect to avoid unnecessary
            // reconnect attempts when mount status recovered between scheduling and fire time.
            await self.runOperation(
                remoteID: remoteID,
                intent: .refresh,
                trigger: .recovery,
                conflictPolicy: .skipIfBusy,
                timeout: self.refreshWatchdogTimeout
            ) { [weak self] operationID in
                await self?.performRefreshStatus(remoteID: remoteID, operationID: operationID)
            }

            if self.status(for: remoteID).state == .connected {
                self.reconnectAttempts[remoteID] = 0
                self.recoveryNonConnectedStrikes[remoteID] = 0
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await self.connect(remoteID: remoteID, trigger: .recovery, suppressUserAlerts: true)
        }
        reconnectTasks[remoteID] = task
        refreshRecoveryIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func shouldAttemptAutoReconnect(after status: RemoteStatus) -> Bool {
        guard status.state == .error || status.state == .disconnected else {
            return false
        }

        if let message = status.lastError, isPermanentReconnectFailure(message) {
            return false
        }

        return true
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func stopAutoReconnectIfPermanentFailure(for remoteID: UUID, message: String?) {
        guard let message, isPermanentReconnectFailure(message) else {
            return
        }

        desiredConnections.remove(remoteID)
        reconnectAttempts.removeValue(forKey: remoteID)
        reconnectInFlight.remove(remoteID)
        recoveryNonConnectedStrikes.removeValue(forKey: remoteID)
        cancelScheduledReconnect(for: remoteID)

        diagnostics.append(
            level: .warning,
            category: "recovery",
            message: "Auto-reconnect stopped for \(remoteID.uuidString): \(message)"
        )
        refreshRecoveryIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func isPermanentReconnectFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("authentication failed")
            || lower.contains("password is missing")
            || lower.contains("keychain access needs approval")
            || lower.contains("permission denied")
            || lower.contains("private key")
            || lower.contains("local mount point is shared")
            || lower.contains("is itself on a macfuse volume")
            || lower.contains("dependencies are not ready")
            || lower.contains("sshfs is not installed")
            || lower.contains("macfuse is not installed")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func cancelOperationWatchdog(operationID: UUID) {
        operationWatchdogTasks[operationID]?.cancel()
        operationWatchdogTasks.removeValue(forKey: operationID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func cancelScheduledReconnect(for remoteID: UUID) {
        reconnectTasks[remoteID]?.cancel()
        reconnectTasks.removeValue(forKey: remoteID)
        reconnectInFlight.remove(remoteID)
        refreshRecoveryIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func cancelAllScheduledReconnects(reason: String) {
        guard !reconnectTasks.isEmpty else {
            return
        }

        let count = reconnectTasks.count
        for remoteID in Array(reconnectTasks.keys) {
            cancelScheduledReconnect(for: remoteID)
        }

        diagnostics.append(level: .info, category: "recovery", message: "Cancelled \(count) scheduled reconnect task(s): \(reason).")
        refreshRecoveryIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func scheduleRecoveryBurst(trigger: String, delaySeconds: [Int]) {
        recoveryBurstTask?.cancel()
        refreshRecoveryIndicator()
        recoveryBurstTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                recoveryBurstTask = nil
                refreshRecoveryIndicator()
            }

            for (index, delay) in delaySeconds.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                }
                guard !Task.isCancelled else {
                    return
                }

                let passTrigger = index == 0 ? trigger : "\(trigger)-stabilize-\(index)"
                await performRecoveryPass(trigger: passTrigger)
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func scheduleOperationWatchdog(
        remoteID: UUID,
        operationID: UUID,
        intent: RemoteOperationIntent,
        timeout: TimeInterval
    ) {
        guard timeout > 0 else {
            return
        }

        cancelOperationWatchdog(operationID: operationID)

        operationWatchdogTasks[operationID] = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }
            guard !self.systemSleeping else {
                return
            }
            guard self.isOperationCurrent(remoteID: remoteID, operationID: operationID) else {
                return
            }

            let remoteName = self.remotes.first(where: { $0.id == remoteID })?.displayName ?? remoteID.uuidString
            let timeoutMessage = Self.watchdogTimeoutMessage(
                intent: intent,
                currentState: self.status(for: remoteID).state,
                disconnectWatchdogTimeout: self.disconnectWatchdogTimeout
            )

            if let timeoutMessage, !timeoutMessage.isEmpty {
                if intent == .connect || intent == .disconnect || intent == .refresh {
                    let timeoutStatus = RemoteStatus(
                        state: .error,
                        mountedPath: nil,
                        lastError: timeoutMessage,
                        updatedAt: Date()
                    )
                    self.observeStatus(timeoutStatus, for: remoteID)
                    if intent != .refresh {
                        self.alertMessage = timeoutMessage
                    }
                }

                self.diagnostics.append(
                    level: .warning,
                    category: "operations",
                    message: "Operation watchdog triggered remoteID=\(remoteID.uuidString) operationID=\(operationID.uuidString) intent=\(intent.rawValue) remote=\(remoteName) message=\(timeoutMessage)"
                )
            }

            self.cancelOperation(
                remoteID: remoteID,
                reason: "watchdog-timeout",
                supersededBy: nil,
                removeFromTable: true
            )

            if intent == .connect || intent == .disconnect {
                self.scheduleTimeoutCleanup(remoteID: remoteID, timedOutOperationID: operationID)
            }
        }
    }

    /// Beginner note: Post-timeout cleanup runs only if no newer operation is active.
    /// It clears stale sshfs processes that commonly remain after timed-out operations.
    private func scheduleTimeoutCleanup(remoteID: UUID, timedOutOperationID: UUID) {
        guard let remote = remotes.first(where: { $0.id == remoteID }) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if let active = self.remoteOperations[remoteID],
               active.operationID != timedOutOperationID {
                return
            }

            let forceStopQueuedAt = Date()
            self.logMountCall(op: "forceStopProcesses", remoteID: remoteID, operationID: nil, queuedAt: forceStopQueuedAt)
            await self.mountManager.forceStopProcesses(
                for: remote,
                queuedAt: forceStopQueuedAt,
                operationID: nil
            )

            guard self.remoteOperations[remoteID] == nil else {
                return
            }

            let status = RemoteStatus(
                state: .disconnected,
                mountedPath: nil,
                lastError: "Connection reset after timeout.",
                updatedAt: Date()
            )
            self.setStatus(status, for: remoteID)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func runRemoteOperationWithTimeout(
        timeoutSeconds: TimeInterval,
        operation: @escaping @Sendable () async -> RemoteStatus
    ) async -> (RemoteStatus?, Bool) {
        guard timeoutSeconds > 0 else {
            return (await operation(), false)
        }

        let timeoutNanos = UInt64(timeoutSeconds * 1_000_000_000)
        return await withTaskGroup(of: (RemoteStatus?, Bool).self) { group in
            // Child tasks inherit caller cancellation so superseded operations are
            // cancelled instead of continuing detached in the background.
            group.addTask(priority: .userInitiated) {
                let status = await operation()
                return (status, false)
            }
            group.addTask(priority: .utility) {
                do {
                    try await Task.sleep(nanoseconds: timeoutNanos)
                    return (nil, true)
                } catch {
                    // Timeout watcher was cancelled (operation finished or caller cancelled).
                    return (nil, false)
                }
            }

            while let result = await group.next() {
                if result.1 || result.0 != nil {
                    group.cancelAll()
                    return result
                }
                if Task.isCancelled {
                    group.cancelAll()
                    return (nil, false)
                }
            }

            group.cancelAll()
            return (nil, Task.isCancelled)
        }
    }

    nonisolated static func reconnectDelaySeconds(attempt: Int, trigger: String, lastError: String?) -> Int {
        let safeAttempt = max(0, attempt)
        let normalizedTrigger = trigger.lowercased()
        let transient = isTransientReconnectFailureMessage(lastError)

        let matrix: [Int]
        if normalizedTrigger.contains("wake") || normalizedTrigger.contains("network-restored") {
            matrix = transient ? [0, 1, 2, 4, 8, 15, 30, 45, 60] : [0, 2, 5, 10, 20, 30, 45, 60]
        } else if normalizedTrigger.contains("volume-unmounted") || normalizedTrigger.contains("status-change") {
            matrix = transient ? [0, 1, 2, 4, 8, 15, 30] : [0, 2, 5, 10, 20, 30]
        } else {
            matrix = transient ? [0, 1, 2, 4, 8, 15, 30, 45, 60] : [0, 2, 5, 10, 20, 30, 45, 60]
        }

        let index = min(safeAttempt, matrix.count - 1)
        return matrix[index]
    }

    nonisolated static func recoveryBurstDelays(for trigger: String) -> [Int] {
        let normalized = trigger.lowercased()
        if normalized.contains("wake") {
            return [0, 1, 3, 8]
        }
        if normalized.contains("network-restored") {
            return [0, 2, 6]
        }
        return [0]
    }

    nonisolated static func networkReachabilityTransition(
        previousReachable: Bool,
        currentReachable: Bool
    ) -> NetworkReachabilityTransition {
        if previousReachable == currentReachable {
            return .unchanged
        }
        return currentReachable ? .becameReachable : .becameUnreachable
    }

    nonisolated static func requiredRecoveryStrikes(for trigger: String) -> Int {
        let normalized = trigger.lowercased()
        if normalized.contains("wake") || normalized.contains("network-restored") {
            return 1
        }
        if normalized.contains("periodic") {
            return 2
        }
        return 1
    }

    nonisolated static func isTransientReconnectFailureMessage(_ message: String?) -> Bool {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        let lower = message.lowercased()
        return lower.contains("connection reset")
            || lower.contains("connection closed")
            || lower.contains("broken pipe")
            || lower.contains("network is unreachable")
            || lower.contains("no route to host")
            || lower.contains("operation timed out")
            || lower.contains("timed out")
            || lower.contains("resource busy")
            || lower.contains("temporary failure")
            || lower.contains("transport endpoint")
            || lower.contains("connection dropped")
    }

    nonisolated static func shouldReplaceBusyOperation(
        newIntent: RemoteOperationIntent,
        newTrigger: RemoteOperationTrigger,
        existingIntent: RemoteOperationIntent,
        elapsedSeconds: TimeInterval,
        thresholdSeconds: TimeInterval
    ) -> Bool {
        newIntent == .connect
            && (newTrigger == .recovery || newTrigger == .startup)
            && (existingIntent == .connect || existingIntent == .refresh)
            && elapsedSeconds >= thresholdSeconds
    }

    nonisolated static func watchdogTimeoutMessage(
        intent: RemoteOperationIntent,
        currentState: RemoteConnectionState,
        disconnectWatchdogTimeout: TimeInterval
    ) -> String? {
        switch intent {
        case .connect:
            return currentState == .connecting ? "Connect timed out. Check network/credentials and retry." : nil
        case .disconnect:
            guard currentState == .disconnecting else {
                return nil
            }
            return "Disconnect timed out after \(Int(disconnectWatchdogTimeout))s. Close files using the mount, then retry."
        case .refresh:
            return "Status refresh timed out. Try Refresh again."
        case .testConnection:
            return "Test connection timed out. Check network/credentials and retry."
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func testConnection(for draft: RemoteDraft) async -> Result<String, Error> {
        let errors = validationErrors(for: draft)
        if !errors.isEmpty {
            return .failure(AppError.validationFailed(errors))
        }

        let remote = draft.asRemoteConfig()
        if let conflictingRemote = mountPointConflict(for: remote) {
            return .failure(
                AppError.validationFailed([
                    "Local mount point is already used by '\(conflictingRemote.displayName)'. Choose a different folder."
                ])
            )
        }

        var password: String?
        if remote.authMode == .password {
            if !draft.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                password = draft.password
                if let remoteID = draft.id {
                    cachePassword(draft.password, for: remoteID)
                }
            } else if let remoteID = draft.id {
                password = await resolvedPasswordForRemote(
                    remoteID,
                    allowUserInteraction: allowInteractiveKeychainReads
                )
            }

            if password?.isEmpty != false {
                return .failure(AppError.validationFailed(["Password is missing. Enter a password or save one to Keychain first."]))
            }
        }

        do {
            let queuedAt = Date()
            logMountCall(op: "testConnection", remoteID: remote.id, operationID: nil, queuedAt: queuedAt)
            let message = try await mountManager.testConnection(
                remote: remote,
                password: password,
                queuedAt: queuedAt,
                operationID: nil
            )
            diagnostics.append(level: .info, category: "mount-test", message: "Test connection passed for \(remote.displayName)")
            return .success(message)
        } catch {
            diagnostics.append(level: .warning, category: "mount-test", message: "Test connection failed for \(remote.displayName): \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func browserFavorites(for draft: RemoteDraft) -> [String] {
        if let id = draft.id, let remote = remotes.first(where: { $0.id == id }) {
            return Self.normalizePathMemoryCollection(remote.favoriteRemoteDirectories, limit: Self.favoritesLimit)
        }
        return Self.normalizePathMemoryCollection(draft.favoriteRemoteDirectories, limit: Self.favoritesLimit)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func browserRecents(for draft: RemoteDraft) -> [String] {
        if let id = draft.id, let remote = remotes.first(where: { $0.id == id }) {
            return Self.normalizePathMemoryCollection(remote.recentRemoteDirectories, limit: Self.recentsLimit)
        }
        return Self.normalizePathMemoryCollection(draft.recentRemoteDirectories, limit: Self.recentsLimit)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func persistBrowserPathMemory(remoteID: UUID?, favorites: [String], recents: [String]) {
        guard let remoteID, let index = remotes.firstIndex(where: { $0.id == remoteID }) else {
            return
        }

        let sanitizedFavorites = Self.normalizePathMemoryCollection(favorites, limit: Self.favoritesLimit)
        let sanitizedRecents = Self.normalizePathMemoryCollection(recents, limit: Self.recentsLimit)
        let existing = remotes[index]

        if existing.favoriteRemoteDirectories == sanitizedFavorites && existing.recentRemoteDirectories == sanitizedRecents {
            return
        }

        var updatedRemote = existing
        updatedRemote.favoriteRemoteDirectories = sanitizedFavorites
        updatedRemote.recentRemoteDirectories = sanitizedRecents

        do {
            try remoteStore.upsert(updatedRemote)
            remotes[index] = updatedRemote
        } catch {
            diagnostics.append(level: .warning, category: "store", message: "Failed to persist browser path memory for \(existing.displayName): \(error.localizedDescription)")
        }
    }

    nonisolated static func normalizePathMemoryCollection(_ paths: [String], limit: Int) -> [String] {
        guard limit > 0 else {
            return []
        }

        var output: [String] = []
        var seen: Set<String> = []

        for raw in paths {
            let normalized = normalizeRemotePathForMemory(raw)
            guard !normalized.isEmpty else {
                continue
            }

            let key = normalized.lowercased()
            if seen.contains(key) {
                continue
            }

            seen.insert(key)
            output.append(normalized)

            if output.count >= limit {
                break
            }
        }

        return output
    }

    nonisolated static func pushRecentRemotePath(_ path: String, existing: [String], limit: Int) -> [String] {
        let normalized = normalizeRemotePathForMemory(path)
        guard !normalized.isEmpty else {
            return normalizePathMemoryCollection(existing, limit: limit)
        }

        var combined = [normalized]
        combined.append(contentsOf: existing)
        return normalizePathMemoryCollection(combined, limit: limit)
    }

    nonisolated static func normalizeRemotePathForMemory(_ rawPath: String) -> String {
        var normalized = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return ""
        }

        normalized = normalized.replacingOccurrences(of: "\\", with: "/")
        while normalized.contains("//") {
            normalized = normalized.replacingOccurrences(of: "//", with: "/")
        }

        normalized = normalizeWindowsDriveArtifacts(normalized)

        if normalized == "." {
            return "/"
        }
        if normalized == "~" {
            return "~"
        }

        if isWindowsDrivePath(normalized), !normalized.hasPrefix("/") {
            normalized = "/\(normalized)"
        }

        normalized = normalizeWindowsDriveArtifacts(normalized)

        if normalized.hasPrefix("~/") {
            while normalized.count > 2 && normalized.hasSuffix("/") {
                normalized.removeLast()
            }
            return normalized
        }

        if !normalized.hasPrefix("/") {
            normalized = "/\(normalized)"
        }

        if isWindowsDriveRootPath(normalized) {
            return normalized
        }

        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        return normalized
    }

    nonisolated private static func isWindowsDrivePath(_ value: String) -> Bool {
        guard value.count >= 2 else {
            return false
        }

        let chars = Array(value)
        guard chars[0].isLetter, chars[1] == ":" else {
            return false
        }

        guard chars.count >= 3 else {
            return true
        }

        return chars[2] == "/" || chars[2] == "\\" || chars[2] == ":"
    }

    nonisolated private static func normalizeWindowsDriveArtifacts(_ value: String) -> String {
        guard !value.isEmpty else {
            return value
        }

        var working = value
        let hadLeadingSlash = working.hasPrefix("/")
        if hadLeadingSlash {
            working.removeFirst()
        }

        guard working.count >= 2 else {
            return value
        }

        let chars = Array(working)
        guard chars[0].isLetter, chars[1] == ":" else {
            return value
        }

        var tail = String(working.dropFirst(2))
        while tail.hasPrefix(":") {
            tail.removeFirst()
        }

        while tail.contains("//") {
            tail = tail.replacingOccurrences(of: "//", with: "/")
        }

        if tail.isEmpty {
            tail = "/"
        }

        if !tail.isEmpty && !tail.hasPrefix("/") {
            tail = "/\(tail)"
        }

        let rebuilt = "\(chars[0]):\(tail)"
        return hadLeadingSlash ? "/\(rebuilt)" : rebuilt
    }

    nonisolated private static func isWindowsDriveRootPath(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 4 else {
            return false
        }

        let chars = Array(trimmed)
        return chars[0] == "/" && chars[1].isLetter && chars[2] == ":" && chars[3] == "/"
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func startBrowserSession(for draft: RemoteDraft) async throws -> RemoteBrowserSessionID {
        guard !shutdownInProgress else {
            throw AppError.unknown("App is shutting down.")
        }
        let remote = draft.asRemoteConfig()
        let passwordToUse = try await browserPassword(for: draft)
        let sessionID = try await remoteDirectoryBrowserService.openSession(remote: remote, password: passwordToUse)
        activeBrowserSessions.insert(sessionID)
        diagnostics.append(level: .info, category: "remote-browser", message: "Started browser session \(sessionID.uuidString) for \(remote.displayName)")
        return sessionID
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func stopBrowserSession(id sessionID: RemoteBrowserSessionID) async {
        guard activeBrowserSessions.contains(sessionID) else {
            return
        }
        activeBrowserSessions.remove(sessionID)
        await remoteDirectoryBrowserService.closeSession(sessionID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func loadBrowserPath(sessionID: RemoteBrowserSessionID, path: String, requestID: UInt64) async -> RemoteBrowserSnapshot {
        await remoteDirectoryBrowserService.listDirectories(sessionID: sessionID, path: path, requestID: requestID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func goUpBrowserPath(sessionID: RemoteBrowserSessionID, currentPath: String, requestID: UInt64) async -> RemoteBrowserSnapshot {
        await remoteDirectoryBrowserService.goUp(sessionID: sessionID, currentPath: currentPath, requestID: requestID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func retryCurrentBrowserPath(sessionID: RemoteBrowserSessionID, requestID: UInt64) async -> RemoteBrowserSnapshot {
        await remoteDirectoryBrowserService.retryCurrentPath(sessionID: sessionID, requestID: requestID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func browserHealth(sessionID: RemoteBrowserSessionID) async -> BrowserConnectionHealth {
        await remoteDirectoryBrowserService.health(sessionID: sessionID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func browserSessionsSummary() async -> String {
        await remoteDirectoryBrowserService.browserSessionsSummary()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func operationsSummary() -> String {
        guard !remoteOperations.isEmpty else {
            return "- none"
        }

        let now = Date()
        let lines = remoteOperations.values
            .sorted { $0.startedAt < $1.startedAt }
            .map { state -> String in
                let remoteName = remotes.first(where: { $0.id == state.remoteID })?.displayName ?? state.remoteID.uuidString
                let elapsedMs = Int(now.timeIntervalSince(state.startedAt) * 1_000)
                let supersededBy = state.supersededBy?.uuidString ?? "-"
                return "- \(remoteName) remoteID=\(state.remoteID.uuidString) operationID=\(state.operationID.uuidString) intent=\(state.intent.rawValue) trigger=\(state.trigger.rawValue) elapsedMs=\(elapsedMs) cancelled=\(state.cancelled) supersededBy=\(supersededBy)"
            }

        return lines.joined(separator: "\n")
    }

    // Transitional compatibility for older browser UI callers.
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func listDirectories(for draft: RemoteDraft, path: String) async throws -> [RemoteDirectoryEntry] {
        let sessionID = try await startBrowserSession(for: draft)
        defer {
            Task {
                await stopBrowserSession(id: sessionID)
            }
        }
        let snapshot = await loadBrowserPath(sessionID: sessionID, path: path, requestID: 1)
        if snapshot.health.state == .failed && snapshot.entries.isEmpty {
            throw AppError.remoteBrowserError(snapshot.message ?? snapshot.health.lastError ?? "Failed to list remote directories.")
        }
        return snapshot.entries.map { RemoteDirectoryEntry(name: $0.name, fullPath: $0.fullPath) }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func copyDiagnosticsToPasteboard() {
        Task { @MainActor in
            let browserSessions = await remoteDirectoryBrowserService.browserSessionsSummary()
            let operations = operationsSummary()
            let snapshot = diagnostics.snapshot(
                remotes: remotes,
                statuses: statuses,
                dependency: dependencyStatus,
                browserSessions: browserSessions,
                operations: operations
            )
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(snapshot, forType: .string)
            alertMessage = "Diagnostics copied to clipboard."
            diagnostics.append(level: .info, category: "diagnostics", message: "Copied diagnostics snapshot")
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func browserPassword(for draft: RemoteDraft) async throws -> String? {
        if draft.authMode != .password {
            return nil
        }

        if !draft.password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let id = draft.id {
                cachePassword(draft.password, for: id)
            }
            return draft.password
        }

        if let id = draft.id {
            if let stored = await resolvedPasswordForRemote(
                id,
                allowUserInteraction: allowInteractiveKeychainReads
            ) {
                return stored
            }
        }

        throw AppError.validationFailed(["Password is missing. Enter a password before browsing remote directories."])
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func appendDiagnostic(level: DiagnosticLevel, category: String, message: String) {
        diagnostics.append(level: level, category: category, message: message)
    }

    /// Beginner note: This method resolves password in a safe order:
    /// draft value -> in-memory cache -> keychain.
    private func resolvedPasswordForRemote(
        _ remoteID: UUID,
        preferredDraftPassword: String? = nil,
        allowUserInteraction: Bool = false
    ) async -> String? {
        if let preferredDraftPassword {
            let trimmed = preferredDraftPassword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                passwordCache[remoteID] = preferredDraftPassword
                return preferredDraftPassword
            }
        }

        if let cached = passwordCache[remoteID],
           !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cached
        }

        let effectiveAllowUserInteraction = allowUserInteraction

        do {
            let stored = try await readPasswordFromKeychainOffMain(
                remoteID: remoteID,
                allowUserInteraction: effectiveAllowUserInteraction
            )
            if let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                passwordCache[remoteID] = stored
                return stored
            }
        } catch {
            diagnostics.append(
                level: .warning,
                category: "store",
                message: "Failed to read keychain password for \(remoteID.uuidString): \(error.localizedDescription)"
            )
        }

        return nil
    }

    /// Beginner note: Keychain reads are executed off the main actor to keep UI responsive.
    private func readPasswordFromKeychainOffMain(
        remoteID: UUID,
        allowUserInteraction: Bool
    ) async throws -> String? {
        let keychainReader = backgroundKeychainReader
        let queue = keychainReadQueue
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let password = try keychainReader.readPassword(
                        remoteID: remoteID.uuidString,
                        allowUserInteraction: allowUserInteraction
                    )
                    continuation.resume(returning: password)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Beginner note: This helper keeps cache add/remove rules consistent in one place.
    private func cachePassword(_ password: String?, for remoteID: UUID) {
        guard let password else {
            passwordCache.removeValue(forKey: remoteID)
            return
        }
        if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            passwordCache.removeValue(forKey: remoteID)
            return
        }
        passwordCache[remoteID] = password
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func prepareForTermination() async {
        guard !shutdownInProgress else {
            return
        }
        shutdownInProgress = true

        diagnostics.append(level: .info, category: "app", message: "Preparing for app termination.")

        alertMessage = nil
        wakeAnimationUntil = nil
        systemSleeping = false

        recoveryTimer?.invalidate()
        recoveryTimer = nil

        recoveryBurstTask?.cancel()
        recoveryBurstTask = nil
        networkRestoreDebounceTask?.cancel()
        networkRestoreDebounceTask = nil

        operationWatchdogTasks.values.forEach { $0.cancel() }
        operationWatchdogTasks.removeAll()

        for remoteID in Array(remoteOperations.keys) {
            cancelOperation(remoteID: remoteID, reason: "termination", supersededBy: nil)
        }
        remoteOperations.removeAll()

        reconnectTasks.values.forEach { $0.cancel() }
        reconnectTasks.removeAll()
        reconnectInFlight.removeAll()
        reconnectAttempts.removeAll()
        recoveryNonConnectedStrikes.removeAll()
        lastRecoveryRefreshAt.removeAll()
        desiredConnections.removeAll()
        pendingStartupAutoConnectIDs.removeAll()

        clearRecoveryIndicator()

        networkMonitor?.cancel()
        networkMonitor = nil

        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        recoveryMonitoringStarted = false

        let sessionsToClose = Array(activeBrowserSessions)
        activeBrowserSessions.removeAll()
        if !sessionsToClose.isEmpty {
            for sessionID in sessionsToClose {
                await remoteDirectoryBrowserService.closeSession(sessionID)
            }
        }

        let remotesForCleanup = remotes
        if !remotesForCleanup.isEmpty {
            diagnostics.append(
                level: .info,
                category: "app",
                message: "Termination cleanup: force-stopping mount processes for \(remotesForCleanup.count) remote(s)."
            )
        }
        for remote in remotesForCleanup {
            let forceStopQueuedAt = Date()
            logMountCall(op: "forceStopProcesses", remoteID: remote.id, operationID: nil, queuedAt: forceStopQueuedAt)
            // Termination should not trigger Files & Folders "network volume" prompts.
            // We stop sshfs pids only and skip force-unmount path access.
            await mountManager.forceStopProcesses(
                for: remote,
                queuedAt: forceStopQueuedAt,
                operationID: nil,
                skipForceUnmount: true
            )
            let disconnected = RemoteStatus(
                state: .disconnected,
                mountedPath: nil,
                lastError: nil,
                updatedAt: Date()
            )
            setStatus(disconnected, for: remote.id)
        }

        diagnostics.append(level: .info, category: "app", message: "Termination cleanup complete.")
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct LaunchAtLoginState: Equatable, Sendable {
    var enabled: Bool
    var requiresApproval: Bool
    var detail: String?

    static let unknown = LaunchAtLoginState(enabled: false, requiresApproval: false, detail: nil)

    var isOnForToggle: Bool {
        enabled || requiresApproval
    }

    var description: String {
        if enabled {
            return "enabled"
        }
        if requiresApproval {
            return "requires-approval"
        }
        return "disabled"
    }
}

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
protocol LaunchAtLoginAppService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
}

extension SMAppService: LaunchAtLoginAppService {}

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class LaunchAtLoginService {
    private let appService: any LaunchAtLoginAppService
    private let fileManager: FileManager
    private let runner: ProcessRunning
    private let launchAgentLabel = "com.visualweb.macfusegui.launchagent"
    private let launchctlTimeout: TimeInterval = 4

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        appService: any LaunchAtLoginAppService = SMAppService.mainApp,
        fileManager: FileManager = .default,
        runner: ProcessRunning = ProcessRunner()
    ) {
        self.appService = appService
        self.fileManager = fileManager
        self.runner = runner
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func currentState() -> LaunchAtLoginState {
        if appService.status == .enabled {
            return LaunchAtLoginState(enabled: true, requiresApproval: false, detail: nil)
        }

        if fileManager.fileExists(atPath: launchAgentPlistURL.path) {
            return LaunchAtLoginState(
                enabled: true,
                requiresApproval: false,
                detail: "Enabled via LaunchAgent fallback."
            )
        }

        let status = appService.status
        switch status {
        case .enabled:
            return LaunchAtLoginState(enabled: true, requiresApproval: false, detail: nil)
        case .requiresApproval:
            return LaunchAtLoginState(
                enabled: false,
                requiresApproval: true,
                detail: "Approval required in System Settings -> General -> Login Items."
            )
        case .notRegistered:
            return LaunchAtLoginState(enabled: false, requiresApproval: false, detail: nil)
        case .notFound:
            return LaunchAtLoginState(
                enabled: false,
                requiresApproval: false,
                detail: "App may need to be in /Applications for launch at login to register."
            )
        @unknown default:
            return LaunchAtLoginState(enabled: false, requiresApproval: false, detail: "Unknown status")
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func setEnabled(_ enabled: Bool) async throws -> LaunchAtLoginState {
        if enabled {
            var registered = false
            do {
                try appService.register()
                registered = true
            } catch {
                // SMAppService can fail for non-standard install contexts; fall back to LaunchAgent.
            }

            let postRegisterState = currentState()
            if postRegisterState.enabled {
                return postRegisterState
            }

            try await enableLaunchAgentFallback()
            let fallbackState = currentState()
            if fallbackState.enabled {
                return fallbackState
            }

            if !registered {
                throw AppError.unknown("Unable to enable launch at login.")
            }
        } else {
            do {
                try await appService.unregister()
            } catch {
                // Unregister can fail when not registered; we still proceed to disable fallback.
            }
            try await disableLaunchAgentFallback()
        }
        return currentState()
    }

    private var launchAgentsDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var launchAgentPlistURL: URL {
        launchAgentsDirectoryURL.appendingPathComponent("\(launchAgentLabel).plist")
    }

    private var currentBundlePath: String {
        Bundle.main.bundleURL.path
    }

    private var currentUserLaunchDomain: String {
        "gui/\(getuid())"
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    private func enableLaunchAgentFallback() async throws {
        let bundlePath = currentBundlePath
        guard fileManager.fileExists(atPath: bundlePath) else {
            throw AppError.unknown("Unable to enable launch at login because app bundle path was not found.")
        }

        try fileManager.createDirectory(
            at: launchAgentsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": ["/usr/bin/open", bundlePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua"
        ]

        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: launchAgentPlistURL, options: .atomic)

        // launchctl bootout may fail when the agent is not loaded yet. Treat as best-effort cleanup.
        _ = try? await runLaunchctl(arguments: ["bootout", currentUserLaunchDomain, launchAgentPlistURL.path])
        _ = try? await runLaunchctl(arguments: ["bootout", currentUserLaunchDomain, launchAgentLabel])

        // launchctl enable/bootstrap can fail due to policy/permissions; caller surfaces failure if state does not stick.
        _ = try? await runLaunchctl(arguments: ["bootstrap", currentUserLaunchDomain, launchAgentPlistURL.path])
        _ = try? await runLaunchctl(arguments: ["enable", "\(currentUserLaunchDomain)/\(launchAgentLabel)"])
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    private func disableLaunchAgentFallback() async throws {
        // All launchctl calls here are best-effort. Some variants fail depending on current load state.
        _ = try? await runLaunchctl(arguments: ["bootout", currentUserLaunchDomain, launchAgentLabel])
        _ = try? await runLaunchctl(arguments: ["bootout", currentUserLaunchDomain, launchAgentPlistURL.path])
        _ = try? await runLaunchctl(arguments: ["disable", "\(currentUserLaunchDomain)/\(launchAgentLabel)"])

        if fileManager.fileExists(atPath: launchAgentPlistURL.path) {
            try fileManager.removeItem(at: launchAgentPlistURL)
        }
    }

    @discardableResult
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    private func runLaunchctl(arguments: [String]) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let result = try await runner.run(
            executable: "/bin/launchctl",
            arguments: arguments,
            timeout: launchctlTimeout
        )

        if result.timedOut {
            throw AppError.timeout("launchctl \(arguments.joined(separator: " ")) timed out after \(Int(launchctlTimeout))s.")
        }

        if result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppError.unknown(
                "launchctl \(arguments.joined(separator: " ")) failed: \(stderr.isEmpty ? stdout : stderr)"
            )
        }

        return (result.exitCode, result.stdout, result.stderr)
    }
}
