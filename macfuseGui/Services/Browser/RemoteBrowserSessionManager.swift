// BEGINNER FILE GUIDE
// Layer: Browser service layer
// Purpose: This file implements remote directory browsing sessions, transport, parsing, or path normalization.
// Called by: Called from RemoteDirectoryBrowserService and browser-facing view models.
// Calls into: Calls into libssh2 bridge, diagnostics, and browser state models.
// Concurrency: Uses a Swift actor for data-race safety; actor methods execute in an isolated concurrency domain.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
actor RemoteBrowserSessionManager {
    private let transport: BrowserTransport
    private let diagnostics: DiagnosticsService
    private let breakerThreshold: Int
    private let breakerWindow: TimeInterval
    private var sessions: [RemoteBrowserSessionID: LibSSH2SessionActor] = [:]
    private var sessionRemoteIDs: [RemoteBrowserSessionID: UUID] = [:]

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        transport: BrowserTransport,
        diagnostics: DiagnosticsService,
        breakerThreshold: Int = 8,
        breakerWindow: TimeInterval = 30
    ) {
        self.transport = transport
        self.diagnostics = diagnostics
        self.breakerThreshold = breakerThreshold
        self.breakerWindow = breakerWindow
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func openSession(remote: RemoteConfig, password: String?) async -> RemoteBrowserSessionID {
        let existingSessionIDs = sessionRemoteIDs.compactMap { sessionID, remoteID in
            remoteID == remote.id ? sessionID : nil
        }

        for existingSessionID in existingSessionIDs {
            sessionRemoteIDs.removeValue(forKey: existingSessionID)
            guard let existingSession = sessions.removeValue(forKey: existingSessionID) else {
                continue
            }
            // Ensure one browser session per remote so actor/session state cannot diverge.
            await existingSession.close()
            diagnostics.append(
                level: .info,
                category: "remote-browser",
                message: "Replaced browser session \(existingSessionID.uuidString) for \(remote.displayName)"
            )
        }

        let sessionID = UUID()
        let session = LibSSH2SessionActor(
            id: sessionID,
            remote: remote,
            password: password,
            transport: transport,
            diagnostics: diagnostics,
            breakerThreshold: breakerThreshold,
            breakerWindow: breakerWindow
        )
        sessions[sessionID] = session
        sessionRemoteIDs[sessionID] = remote.id
        diagnostics.append(
            level: .info,
            category: "remote-browser",
            message: "Opened browser session \(sessionID.uuidString) for \(remote.displayName)"
        )
        return sessionID
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func closeSession(_ sessionID: RemoteBrowserSessionID) async {
        sessionRemoteIDs.removeValue(forKey: sessionID)
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }
        diagnostics.append(
            level: .debug,
            category: "remote-browser",
            message: "Closing browser session \(sessionID.uuidString)"
        )
        // Remove first so concurrent callers immediately observe this session as closed.
        await session.close()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func listDirectories(sessionID: RemoteBrowserSessionID, path: String, requestID: UInt64) async -> RemoteBrowserSnapshot {
        guard let session = sessions[sessionID] else {
            return missingSessionSnapshot(path: path, requestID: requestID)
        }
        return await session.list(path: path, requestID: requestID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func goUp(sessionID: RemoteBrowserSessionID, currentPath: String, requestID: UInt64) async -> RemoteBrowserSnapshot {
        guard let session = sessions[sessionID] else {
            return missingSessionSnapshot(path: currentPath, requestID: requestID)
        }
        return await session.goUp(currentPath: currentPath, requestID: requestID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func retryCurrentPath(
        sessionID: RemoteBrowserSessionID,
        lastKnownPath: String,
        requestID: UInt64
    ) async -> RemoteBrowserSnapshot {
        guard let session = sessions[sessionID] else {
            return missingSessionSnapshot(path: lastKnownPath, requestID: requestID)
        }
        return await session.retryCurrentPath(requestID: requestID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func health(sessionID: RemoteBrowserSessionID) async -> BrowserConnectionHealth {
        guard let session = sessions[sessionID] else {
            return missingSessionHealth()
        }
        return await session.currentHealth()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func sessionsSummary() async -> String {
        let sessionPairs = sessions.map { ($0.key, $0.value) }
        if sessionPairs.isEmpty {
            return "- none"
        }

        let lines = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for (id, session) in sessionPairs {
                group.addTask {
                    let line = await session.summaryLine()
                    return line.isEmpty ? "- session=\(id.uuidString)" : line
                }
            }

            var collected: [String] = []
            for await line in group {
                collected.append(line)
            }
            return collected
        }

        return lines.sorted().joined(separator: "\n")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func missingSessionSnapshot(path: String, requestID: UInt64) -> RemoteBrowserSnapshot {
        let normalized = BrowserPathNormalizer.normalize(path: path)
        return RemoteBrowserSnapshot(
            path: normalized,
            entries: [],
            // Missing session means current data is non-fresh.
            isStale: true,
            isConfirmedEmpty: false,
            health: missingSessionHealth(),
            message: L10n.tr("Browser session closed. Re-open the browser."),
            generatedAt: Date(),
            // No cached entries are returned for missing-session snapshots.
            fromCache: false,
            requestID: requestID,
            latencyMs: 0
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func missingSessionHealth() -> BrowserConnectionHealth {
        BrowserConnectionHealth(
            state: .closed,
            retryCount: 0,
            lastError: L10n.tr("Browser session closed"),
            lastSuccessAt: nil,
            lastLatencyMs: nil,
            updatedAt: Date()
        )
    }
}
