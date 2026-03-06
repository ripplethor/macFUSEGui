// BEGINNER FILE GUIDE
// Layer: Browser service layer
// Purpose: This file implements remote directory browsing sessions, transport, parsing, or path normalization.
// Called by: Called from RemoteDirectoryBrowserService and browser-facing view models.
// Calls into: Calls into libssh2 bridge, diagnostics, and browser state models.
// Concurrency: Uses a Swift actor for data-race safety; actor methods execute in an isolated concurrency domain.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

// Session actor lifecycle:
// - Created when the browser sheet opens.
// - Serves list/goUp/retry requests for that sheet.
// - Runs keepalive while open.
// - Closes transport and tasks when sheet closes.
//
// Reliability contract in this file:
// - Never silently drop to blank list on transient failures.
// - Prefer cached data plus explicit health state and message.
// - Recover automatically with bounded backoff.
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
actor LibSSH2SessionActor {
    private static let recoveryRequestID: UInt64 = 0

    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    private struct LastSuccessfulListing {
        var path: String
        var entries: [RemoteDirectoryItem]
    }

    /// Beginner note: Cache lookup can fall back to a different path when the requested
    /// path has no cached data. Keep source metadata for diagnostics.
    private struct CachedEntrySource {
        var entries: [RemoteDirectoryItem]
        var fromCache: Bool
        var sourcePath: String?
    }

    private let id: RemoteBrowserSessionID
    private let remote: RemoteConfig
    private let password: String?
    private let transport: BrowserTransport
    private let diagnostics: DiagnosticsService

    // Health exposed to UI so users can see connecting/recovering/failed states.
    private var health: BrowserConnectionHealth = .connecting
    // Sticky cache by normalized path.
    private var cache: [String: [RemoteDirectoryItem]] = [:]
    // Last active path for retryCurrentPath and recovery loop.
    private var lastPath: String
    private var closed = false
    private var consecutiveFailures = 0
    private var breakerOpenedAt: Date?
    private var keepAliveTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var isRecoveryInFlight = false
    private var activeListRequests = 0
    // Tracks repeated empty responses before we treat a path as truly empty.
    private var emptyListingStrikeByPath: [String: Int] = [:]
    private var lastSuccessfulListAt: Date?
    private var lastSuccessfulListing: LastSuccessfulListing?

    // Nanosecond delays between immediate request retries.
    private let requestRetrySchedule: [UInt64]
    // Nanosecond delays for background recovery attempts.
    private let recoveryRetrySchedule: [UInt64]
    private let breakerThreshold: Int
    private let breakerWindow: TimeInterval
    private let keepAliveIntervalNanoseconds: UInt64

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        id: RemoteBrowserSessionID,
        remote: RemoteConfig,
        password: String?,
        transport: BrowserTransport,
        diagnostics: DiagnosticsService,
        requestRetrySchedule: [UInt64] = [300_000_000, 800_000_000],
        recoveryRetrySchedule: [UInt64] = [200_000_000, 800_000_000, 2_000_000_000, 5_000_000_000],
        keepAliveIntervalNanoseconds: UInt64 = 12_000_000_000,
        breakerThreshold: Int = 8,
        breakerWindow: TimeInterval = 30
    ) {
        self.id = id
        self.remote = remote
        self.password = password
        self.transport = transport
        self.diagnostics = diagnostics
        self.requestRetrySchedule = requestRetrySchedule
        self.recoveryRetrySchedule = recoveryRetrySchedule
        self.keepAliveIntervalNanoseconds = keepAliveIntervalNanoseconds
        self.breakerThreshold = breakerThreshold
        self.breakerWindow = breakerWindow
        self.lastPath = BrowserPathNormalizer.normalize(path: remote.remoteDirectory)
        self.health = BrowserConnectionHealth(
            state: .connecting,
            retryCount: 0,
            lastError: nil,
            lastSuccessAt: nil,
            lastLatencyMs: nil,
            updatedAt: Date()
        )

        Task {
            // Keepalive starts once and stays active for the session lifetime.
            await self.startKeepAlive()
        }
    }

    /// Beginner note: Callers should always invoke close() for deterministic shutdown.
    /// Deinit is only a best-effort safety net.
    deinit {
        keepAliveTask?.cancel()
        recoveryTask?.cancel()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func close() async {
        // close() is the primary lifecycle API for sessions; callers should not
        // rely on deinit timing for transport/task cleanup.
        closed = true
        keepAliveTask?.cancel()
        keepAliveTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        isRecoveryInFlight = false
        await transport.invalidate(remoteID: remote.id)
        health = BrowserConnectionHealth(
            state: .closed,
            retryCount: health.retryCount,
            lastError: health.lastError,
            lastSuccessAt: health.lastSuccessAt,
            lastLatencyMs: health.lastLatencyMs,
            updatedAt: Date()
        )
        diagnostics.append(level: .info, category: "remote-browser", message: "Closed browser session \(id.uuidString)")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func currentHealth() -> BrowserConnectionHealth {
        health
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func list(path: String, requestID: UInt64, forceRefresh: Bool = false) async -> RemoteBrowserSnapshot {
        let normalizedPath = BrowserPathNormalizer.normalize(path: path)
        lastPath = normalizedPath
        resetBreakerIfExpired()

        // Used by keepalive to avoid ping/list contention on the same session.
        activeListRequests += 1
        defer {
            assert(activeListRequests > 0, "activeListRequests underflow in list(path:requestID:forceRefresh:)")
            if activeListRequests > 0 {
                activeListRequests -= 1
            } else {
                activeListRequests = 0
            }
        }

        if closed {
            return makeSnapshot(
                path: normalizedPath,
                entries: cache[normalizedPath] ?? [],
                isStale: true,
                isConfirmedEmpty: false,
                fromCache: true,
                requestID: requestID,
                latencyMs: 0,
                message: L10n.tr("Browser session is closed."),
                stateOverride: .closed
            )
        }

        if isCircuitOpen(), !forceRefresh {
            // Circuit-open state means repeated failures in a short window.
            // We return cached content immediately and let recovery run in background.
            let cached = cachedEntries(preferredPath: normalizedPath)
            logOffPathCacheFallbackIfNeeded(
                cached: cached,
                preferredPath: normalizedPath,
                context: "circuit-open"
            )
            let snapshot = makeSnapshot(
                path: normalizedPath,
                entries: cached.entries,
                isStale: true,
                isConfirmedEmpty: false,
                fromCache: cached.fromCache,
                requestID: requestID,
                latencyMs: 0,
                message: L10n.tr("Connection is unstable. Retrying automatically."),
                stateOverride: .failed
            )
            logSnapshot(snapshot, requestID: requestID, pathIn: normalizedPath, resolvedPath: snapshot.path, reopenedSession: false)
            scheduleRecoveryIfNeeded(reason: "circuit-open", path: normalizedPath)
            return snapshot
        }

        let attempts = max(1, requestRetrySchedule.count + 1)
        var lastError: String?
        for index in 0..<attempts {
            if index > 0 {
                setHealth(state: .reconnecting, retryCount: index, lastError: lastError)
                if !requestRetrySchedule.isEmpty {
                    let delay = requestRetrySchedule[min(index - 1, requestRetrySchedule.count - 1)]
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                }
            } else {
                // First attempt state reflects whether we already have cached content.
                let initialState: BrowserConnectionState = cache[normalizedPath] == nil ? .connecting : .reconnecting
                setHealth(state: initialState, retryCount: 0, lastError: nil)
            }

            do {
                let result = try await transport.listDirectories(remote: remote, path: normalizedPath, password: password)
                let snapshot = await applyListResult(
                    result,
                    requestID: requestID,
                    recoveryContext: false
                )
                logSnapshot(
                    snapshot,
                    requestID: requestID,
                    pathIn: normalizedPath,
                    resolvedPath: result.resolvedPath,
                    reopenedSession: result.reopenedSession
                )
                return snapshot
            } catch {
                lastError = error.localizedDescription
                diagnostics.append(
                    level: .warning,
                    category: "remote-browser",
                    message: "list failed session=\(id.uuidString) requestID=\(requestID) pathIn=\(normalizedPath) attempt=\(index + 1)/\(attempts) health=\(health.state.rawValue) error=\(error.localizedDescription)"
                )
            }
        }

        let snapshot = applyListFailure(path: normalizedPath, requestID: requestID, lastError: lastError)
        logSnapshot(snapshot, requestID: requestID, pathIn: normalizedPath, resolvedPath: normalizedPath, reopenedSession: false)
        // Schedule autonomous recovery after direct list failure.
        scheduleRecoveryIfNeeded(reason: "list-failure", path: normalizedPath)
        return snapshot
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func retryCurrentPath(requestID: UInt64) async -> RemoteBrowserSnapshot {
        await list(path: lastPath, requestID: requestID, forceRefresh: true)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func goUp(currentPath: String, requestID: UInt64) async -> RemoteBrowserSnapshot {
        let parent = BrowserPathNormalizer.parentPath(of: currentPath)
        return await list(path: parent, requestID: requestID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func summaryLine() -> String {
        let sessionPath = lastPath
        let totalEmptyStrikes = emptyListingStrikeByPath.values.reduce(0, +)
        let lastSuccessText: String
        if let timestamp = lastSuccessfulListAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            lastSuccessText = formatter.string(from: timestamp)
        } else {
            lastSuccessText = "-"
        }

        return "- \(remote.displayName) session=\(id.uuidString) state=\(health.state.rawValue) retries=\(health.retryCount) path=\(sessionPath) failures=\(consecutiveFailures) emptyStrikes=\(totalEmptyStrikes) lastSuccessAt=\(lastSuccessText) lastLatencyMs=\(health.lastLatencyMs.map(String.init) ?? "-") error=\(health.lastError ?? "")"
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task {
            await self.keepAliveLoop()
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    private func keepAliveLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: keepAliveIntervalNanoseconds)
            if Task.isCancelled {
                break
            }
            // Keepalive is low-priority observability, not primary data path.
            await keepAliveTick()
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    private func keepAliveTick() async {
        guard !closed else {
            return
        }

        if activeListRequests > 0 || isRecoveryInFlight {
            // Skip ping if user-driven listing or recovery is active.
            diagnostics.append(
                level: .debug,
                category: "remote-browser",
                message: "keepalive skipped (active listing/recovery) session=\(id.uuidString) inFlight=\(activeListRequests) recovery=\(isRecoveryInFlight)"
            )
            return
        }

        do {
            try await transport.ping(remote: remote, path: lastPath, password: password)
            if consecutiveFailures > 0 || breakerOpenedAt != nil {
                consecutiveFailures = 0
                breakerOpenedAt = nil
                setHealth(
                    state: .healthy,
                    retryCount: 0,
                    lastError: nil,
                    preserveLastSuccess: true
                )
                diagnostics.append(
                    level: .info,
                    category: "remote-browser",
                    message: "keepalive recovered session=\(id.uuidString) path=\(lastPath)"
                )
            }
        } catch {
            setHealth(
                state: .reconnecting,
                retryCount: max(1, health.retryCount),
                lastError: error.localizedDescription,
                preserveLastSuccess: true
            )
            diagnostics.append(
                level: .warning,
                category: "remote-browser",
                message: "keepalive failed session=\(id.uuidString) path=\(lastPath) error=\(error.localizedDescription)"
            )
            // Ping failure does not wipe cache or force-close session.
            scheduleRecoveryIfNeeded(reason: "keepalive-failed", path: lastPath)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func applyListResult(
        _ result: BrowserTransportListResult,
        requestID: UInt64,
        recoveryContext: Bool
    ) async -> RemoteBrowserSnapshot {
        let effectivePath = BrowserPathNormalizer.normalize(path: result.resolvedPath)
        let pathKey = effectivePath
        let cachedForPath = cache[effectivePath] ?? []

        if result.entries.isEmpty {
            if !cachedForPath.isEmpty {
                // Empty listing while cache exists is treated as transient until confirmed.
                let strike = (emptyListingStrikeByPath[pathKey] ?? 0) + 1
                emptyListingStrikeByPath[pathKey] = strike
                let message = L10n.tr("Received an empty listing. Keeping previous data while reconnecting.")
                setHealth(
                    state: .degraded,
                    retryCount: strike,
                    lastError: L10n.tr("Received empty listing"),
                    preserveLastSuccess: true
                )
                let snapshot = makeSnapshot(
                    path: effectivePath,
                    entries: cachedForPath,
                    isStale: true,
                    isConfirmedEmpty: false,
                    fromCache: true,
                    requestID: requestID,
                    latencyMs: result.latencyMs,
                    message: message,
                    stateOverride: .reconnecting
                )
                scheduleRecoveryIfNeeded(reason: "empty-with-cache", path: effectivePath)
                return snapshot
            }

            // First-load empty listings are confirmed before being accepted as healthy-empty.
            do {
                let confirmation = try await transport.listDirectories(remote: remote, path: effectivePath, password: password)
                let confirmedPath = BrowserPathNormalizer.normalize(path: confirmation.resolvedPath)
                let confirmedKey = confirmedPath

                if !confirmation.entries.isEmpty {
                    // Confirmation disagreed with first response, so treat as non-empty success.
                    emptyListingStrikeByPath[confirmedKey] = 0
                    return recordSuccessfulListing(
                        path: confirmedPath,
                        entries: confirmation.entries,
                        requestID: requestID,
                        latencyMs: confirmation.latencyMs,
                        isConfirmedEmpty: false
                    )
                }

                emptyListingStrikeByPath[confirmedKey] = 0
                return recordSuccessfulListing(
                    path: confirmedPath,
                    entries: [],
                    requestID: requestID,
                    latencyMs: confirmation.latencyMs,
                    isConfirmedEmpty: true
                )
            } catch {
                // Could not confirm emptiness; stay on cached or degraded view and recover.
                let fallback = cachedEntries(preferredPath: effectivePath)
                logOffPathCacheFallbackIfNeeded(
                    cached: fallback,
                    preferredPath: effectivePath,
                    context: "empty-confirm-failed"
                )
                consecutiveFailures += 1
                if consecutiveFailures >= breakerThreshold {
                    breakerOpenedAt = Date()
                }
                setHealth(
                    state: consecutiveFailures >= breakerThreshold ? .failed : .degraded,
                    retryCount: consecutiveFailures,
                    lastError: error.localizedDescription,
                    preserveLastSuccess: true
                )
                let message = L10n.tr("Empty response could not be confirmed. Reconnecting…")
                let snapshot = makeSnapshot(
                    path: effectivePath,
                    entries: fallback.entries,
                    isStale: true,
                    isConfirmedEmpty: false,
                    fromCache: fallback.fromCache,
                    requestID: requestID,
                    latencyMs: result.latencyMs,
                    message: message,
                    stateOverride: .reconnecting
                )
                scheduleRecoveryIfNeeded(reason: "empty-confirm-failed", path: effectivePath)
                return snapshot
            }
        }

        emptyListingStrikeByPath[pathKey] = 0
        let snapshot = recordSuccessfulListing(
            path: effectivePath,
            entries: result.entries,
            requestID: requestID,
            latencyMs: result.latencyMs,
            isConfirmedEmpty: false
        )

        if recoveryContext {
            diagnostics.append(
                level: .info,
                category: "remote-browser",
                message: "recovery success session=\(id.uuidString) path=\(effectivePath) entries=\(result.entries.count)"
            )
        }

        return snapshot
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func recordSuccessfulListing(
        path: String,
        entries: [RemoteDirectoryItem],
        requestID: UInt64,
        latencyMs: Int,
        isConfirmedEmpty: Bool
    ) -> RemoteBrowserSnapshot {
        // Successful listing resets failure counters and breaker state.
        cache[path] = entries
        lastPath = path
        consecutiveFailures = 0
        breakerOpenedAt = nil

        let now = Date()
        lastSuccessfulListAt = now
        lastSuccessfulListing = LastSuccessfulListing(path: path, entries: entries)
        setHealth(
            state: .healthy,
            retryCount: 0,
            lastError: nil,
            lastSuccessAt: now,
            lastLatencyMs: latencyMs,
            preserveLastSuccess: false
        )

        return makeSnapshot(
            path: path,
            entries: entries,
            isStale: false,
            isConfirmedEmpty: isConfirmedEmpty,
            fromCache: false,
            requestID: requestID,
            latencyMs: latencyMs,
            message: nil,
            stateOverride: nil
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func applyListFailure(path: String, requestID: UInt64, lastError: String?) -> RemoteBrowserSnapshot {
        consecutiveFailures += 1
        if consecutiveFailures >= breakerThreshold {
            breakerOpenedAt = Date()
            setHealth(state: .failed, retryCount: consecutiveFailures, lastError: lastError, preserveLastSuccess: true)
        } else {
            setHealth(state: .degraded, retryCount: consecutiveFailures, lastError: lastError, preserveLastSuccess: true)
        }

        let cached = cachedEntries(preferredPath: path)
        logOffPathCacheFallbackIfNeeded(
            cached: cached,
            preferredPath: path,
            context: "list-failure"
        )
        if !cached.entries.isEmpty {
            // Primary UX rule: keep last good data visible while reconnecting.
            return makeSnapshot(
                path: path,
                entries: cached.entries,
                isStale: true,
                isConfirmedEmpty: false,
                fromCache: cached.fromCache,
                requestID: requestID,
                latencyMs: 0,
                message: L10n.format("Connection lost. Reconnecting… (attempt %lld)", Int64(consecutiveFailures)),
                stateOverride: .reconnecting
            )
        }

        return makeSnapshot(
            path: path,
            entries: [],
            isStale: true,
            isConfirmedEmpty: false,
            fromCache: false,
            requestID: requestID,
            latencyMs: 0,
            message: lastError ?? L10n.tr("Unable to load this path."),
            stateOverride: .failed
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func scheduleRecoveryIfNeeded(reason: String, path: String) {
        guard !closed else {
            return
        }

        guard !isRecoveryInFlight else {
            diagnostics.append(
                level: .debug,
                category: "remote-browser",
                message: "recovery already in flight session=\(id.uuidString) reason=\(reason)"
            )
            return
        }

        isRecoveryInFlight = true
        let normalizedPath = BrowserPathNormalizer.normalize(path: path)
        diagnostics.append(
            level: .info,
            category: "remote-browser",
            message: "recovery scheduled session=\(id.uuidString) reason=\(reason) path=\(normalizedPath)"
        )

        // Only one recovery loop is allowed at a time.
        recoveryTask = Task {
            await self.runRecoveryLoop(path: normalizedPath)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    private func runRecoveryLoop(path: String) async {
        var lastError = health.lastError

        // Bounded retry schedule prevents tight loops during outages.
        for (index, delay) in recoveryRetrySchedule.enumerated() {
            if Task.isCancelled || closed {
                isRecoveryInFlight = false
                recoveryTask = nil
                return
            }

            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }

            if Task.isCancelled || closed {
                isRecoveryInFlight = false
                recoveryTask = nil
                return
            }

            setHealth(
                state: .reconnecting,
                retryCount: index + 1,
                lastError: lastError,
                preserveLastSuccess: true
            )

            diagnostics.append(
                level: .info,
                category: "remote-browser",
                message: "recovery attempt session=\(id.uuidString) attempt=\(index + 1)/\(recoveryRetrySchedule.count) path=\(path)"
            )

            do {
                let result = try await transport.listDirectories(remote: remote, path: path, password: password)
                let snapshot = await applyListResult(
                    result,
                    requestID: Self.recoveryRequestID,
                    recoveryContext: true
                )

                if snapshot.health.state == .healthy {
                    // Stop recovery as soon as we have a healthy listing again.
                    isRecoveryInFlight = false
                    recoveryTask = nil
                    return
                }

                lastError = snapshot.health.lastError ?? snapshot.message
            } catch {
                lastError = error.localizedDescription
                diagnostics.append(
                    level: .warning,
                    category: "remote-browser",
                    message: "recovery failed session=\(id.uuidString) attempt=\(index + 1)/\(recoveryRetrySchedule.count) path=\(path) error=\(error.localizedDescription)"
                )
            }
        }

        setHealth(
            state: .failed,
            retryCount: recoveryRetrySchedule.count,
            lastError: lastError ?? "Automatic recovery exhausted.",
            preserveLastSuccess: true
        )
        diagnostics.append(
            level: .warning,
            category: "remote-browser",
            message: "recovery exhausted session=\(id.uuidString) path=\(path)"
        )
        isRecoveryInFlight = false
        recoveryTask = nil
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func cachedEntries(preferredPath: String) -> CachedEntrySource {
        // Cache lookup order:
        // 1) Exact requested path
        // 2) Last browsed path
        // 3) Last successful listing from any path
        if let exact = cache[preferredPath], !exact.isEmpty {
            return CachedEntrySource(entries: exact, fromCache: true, sourcePath: preferredPath)
        }

        if let lastPathEntries = cache[lastPath], !lastPathEntries.isEmpty {
            return CachedEntrySource(entries: lastPathEntries, fromCache: true, sourcePath: lastPath)
        }

        if let lastSuccessfulListing, !lastSuccessfulListing.entries.isEmpty {
            return CachedEntrySource(
                entries: lastSuccessfulListing.entries,
                fromCache: true,
                sourcePath: lastSuccessfulListing.path
            )
        }

        return CachedEntrySource(entries: [], fromCache: false, sourcePath: nil)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func isCircuitOpen() -> Bool {
        breakerOpenedAt != nil
    }

    /// Beginner note: Keep breaker mutation out of read-style predicates so callers
    /// can reason about when state changes happen.
    private func resetBreakerIfExpired() {
        guard let openedAt = breakerOpenedAt else {
            return
        }
        if Date().timeIntervalSince(openedAt) >= breakerWindow {
            breakerOpenedAt = nil
        }
    }

    /// Beginner note: Returning cached entries from a different path is intentional
    /// for resiliency, but we log it so diagnostics stay unambiguous.
    private func logOffPathCacheFallbackIfNeeded(
        cached: CachedEntrySource,
        preferredPath: String,
        context: String
    ) {
        guard cached.fromCache,
              !cached.entries.isEmpty,
              let sourcePath = cached.sourcePath,
              sourcePath != preferredPath else {
            return
        }

        diagnostics.append(
            level: .warning,
            category: "remote-browser",
            message: "Using cached entries from \(sourcePath) while serving \(preferredPath) context=\(context) session=\(id.uuidString)"
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func setHealth(
        state: BrowserConnectionState,
        retryCount: Int,
        lastError: String?,
        lastSuccessAt: Date? = nil,
        lastLatencyMs: Int? = nil,
        preserveLastSuccess: Bool = true
    ) {
        let successAt = preserveLastSuccess ? health.lastSuccessAt : lastSuccessAt
        let latency = preserveLastSuccess ? health.lastLatencyMs : lastLatencyMs

        health = BrowserConnectionHealth(
            state: state,
            retryCount: retryCount,
            lastError: lastError,
            lastSuccessAt: successAt,
            lastLatencyMs: latency,
            updatedAt: Date()
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func makeSnapshot(
        path: String,
        entries: [RemoteDirectoryItem],
        isStale: Bool,
        isConfirmedEmpty: Bool,
        fromCache: Bool,
        requestID: UInt64,
        latencyMs: Int,
        message: String?,
        stateOverride: BrowserConnectionState?
    ) -> RemoteBrowserSnapshot {
        let effectiveHealth: BrowserConnectionHealth
        if let stateOverride {
            effectiveHealth = BrowserConnectionHealth(
                state: stateOverride,
                retryCount: health.retryCount,
                lastError: message ?? health.lastError,
                lastSuccessAt: health.lastSuccessAt,
                lastLatencyMs: health.lastLatencyMs,
                updatedAt: Date()
            )
        } else {
            effectiveHealth = health
        }

        return RemoteBrowserSnapshot(
            path: path,
            entries: entries,
            isStale: isStale,
            isConfirmedEmpty: isConfirmedEmpty,
            health: effectiveHealth,
            message: message,
            generatedAt: Date(),
            fromCache: fromCache,
            requestID: requestID,
            latencyMs: latencyMs
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func logSnapshot(
        _ snapshot: RemoteBrowserSnapshot,
        requestID: UInt64,
        pathIn: String,
        resolvedPath: String,
        reopenedSession: Bool
    ) {
        diagnostics.append(
            level: .debug,
            category: "remote-browser",
            message: "snapshot session=\(id.uuidString) requestID=\(requestID) pathIn=\(pathIn) resolvedPath=\(resolvedPath) elapsedMs=\(snapshot.latencyMs) entryCount=\(snapshot.entries.count) reopenedSession=\(reopenedSession) healthState=\(snapshot.health.state.rawValue) fromCache=\(snapshot.fromCache) stale=\(snapshot.isStale) confirmedEmpty=\(snapshot.isConfirmedEmpty)"
        )
    }
}
