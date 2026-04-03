// BEGINNER FILE GUIDE
// Layer: Automated test layer
// Purpose: This file verifies production behavior and protects against regressions when code changes.
// Called by: Executed by XCTest during xcodebuild test or IDE test runs.
// Calls into: Calls production code and test fixtures with deterministic assertions.
// Concurrency: Uses a Swift actor for data-race safety; actor methods execute in an isolated concurrency domain.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import XCTest
@testable import macfuseGui

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class RemotesViewModelHelpersTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    func testPathMemoryNormalizationDedupesCaseInsensitiveAndLimits() {
        let normalized = RemotesViewModel.normalizePathMemoryCollection(
            ["/D:/wwwroot/", "/d:/wwwroot", "\\D:\\wwwroot\\", "/C:/inetpub", "/c:/inetpub", "", "   "],
            limit: 2
        )

        XCTAssertEqual(normalized, ["/D:/wwwroot", "/C:/inetpub"])
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testPushRecentRemotePathMovesPathToFrontAndDedupes() {
        let updated = RemotesViewModel.pushRecentRemotePath(
            "/D:/wwwroot/",
            existing: ["/C:/Users/Administrator", "/d:/wwwroot", "/C:/inetpub"],
            limit: 3
        )

        XCTAssertEqual(updated, ["/D:/wwwroot", "/C:/Users/Administrator", "/C:/inetpub"])
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testStartupAutoConnectSelectionIncludesOnlyEnabledRemotes() {
        let remotes = [
            makeRemote(name: "One", autoConnect: true),
            makeRemote(name: "Two", autoConnect: false),
            makeRemote(name: "Three", autoConnect: true)
        ]

        let selectedIDs = RemotesViewModel.startupAutoConnectRemoteIDs(from: remotes)
        XCTAssertEqual(selectedIDs, [remotes[0].id, remotes[2].id])
    }

    func testSortedRemotesPlacesFavoritesFirstThenAlphabetical() {
        let remotes = [
            makeRemote(name: "Zulu", autoConnect: false, isFavorite: false),
            makeRemote(name: "Bravo", autoConnect: false, isFavorite: true),
            makeRemote(name: "Alpha", autoConnect: false, isFavorite: false),
            makeRemote(name: "Charlie", autoConnect: false, isFavorite: true)
        ]

        let sorted = RemotesViewModel.sortedRemotes(remotes)

        XCTAssertEqual(sorted.map(\.displayName), ["Bravo", "Charlie", "Alpha", "Zulu"])
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testNormalizeRemotePathFixesWindowsDoubleColonArtifacts() {
        XCTAssertEqual(RemotesViewModel.normalizeRemotePathForMemory("/D::"), "/D:/")
        XCTAssertEqual(RemotesViewModel.normalizeRemotePathForMemory("/D::/wwwroot"), "/D:/wwwroot")
        XCTAssertEqual(RemotesViewModel.normalizeRemotePathForMemory("D::\\sites"), "/D:/sites")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testBrowserPathNormalizerHandlesWindowsRootsAndParents() {
        XCTAssertEqual(BrowserPathNormalizer.normalize(path: "/D::"), "/D:/")
        XCTAssertEqual(BrowserPathNormalizer.normalize(path: "D:"), "/D:/")
        XCTAssertEqual(BrowserPathNormalizer.normalize(path: "/D"), "/D")
        XCTAssertEqual(BrowserPathNormalizer.normalize(path: "D::\\wwwroot"), "/D:/wwwroot")
        XCTAssertEqual(BrowserPathNormalizer.normalize(path: "D::\\x"), "/D:/x")
        XCTAssertEqual(BrowserPathNormalizer.parentPath(of: "/D:/wwwroot/site"), "/D:/wwwroot")
        XCTAssertEqual(BrowserPathNormalizer.join(base: "/D:/wwwroot", child: "site"), "/D:/wwwroot/site")
        XCTAssertEqual(BrowserPathNormalizer.join(base: "/home/philip", child: "/var/log"), "/var/log")
        XCTAssertEqual(BrowserPathNormalizer.join(base: "/home/philip", child: "D:/wwwroot"), "/D:/wwwroot")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func testBrowserSessionReturnsCachedEntriesOnTransientEmptyListing() async {
        let remote = makeRemote(name: "Windows", autoConnect: false)
        let initial = BrowserTransportListResult(
            resolvedPath: "/D:/wwwroot",
            entries: [
                RemoteDirectoryItem(name: "site-a", fullPath: "/D:/wwwroot/site-a", isDirectory: true, modifiedAt: nil, sizeBytes: nil)
            ],
            latencyMs: 10,
            reopenedSession: false
        )
        let empty = BrowserTransportListResult(
            resolvedPath: "/D:/wwwroot",
            entries: [],
            latencyMs: 10,
            reopenedSession: false
        )

        let transport = FakeBrowserTransport(results: [.success(initial), .success(empty)])
        let actor = LibSSH2SessionActor(
            id: UUID(),
            remote: remote,
            password: nil,
            transport: transport,
            diagnostics: DiagnosticsService()
        )

        let first = await actor.list(path: "/D:/wwwroot", requestID: 1)
        XCTAssertFalse(first.isStale)
        XCTAssertEqual(first.entries.count, 1)

        let second = await actor.list(path: "/D:/wwwroot", requestID: 2)
        XCTAssertTrue(second.isStale)
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.health.state, .reconnecting)
        XCTAssertTrue((second.message ?? "").localizedCaseInsensitiveContains("empty"))
        XCTAssertFalse(second.isConfirmedEmpty)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func testBrowserSessionConfirmsHealthyEmptyListingBeforeClearing() async {
        let remote = makeRemote(name: "Windows", autoConnect: false)
        let firstEmpty = BrowserTransportListResult(
            resolvedPath: "/D:/empty",
            entries: [],
            latencyMs: 9,
            reopenedSession: false
        )
        let confirmedEmpty = BrowserTransportListResult(
            resolvedPath: "/D:/empty",
            entries: [],
            latencyMs: 8,
            reopenedSession: false
        )

        let transport = FakeBrowserTransport(results: [.success(firstEmpty), .success(confirmedEmpty)])
        let actor = LibSSH2SessionActor(
            id: UUID(),
            remote: remote,
            password: nil,
            transport: transport,
            diagnostics: DiagnosticsService()
        )

        let snapshot = await actor.list(path: "/D:/empty", requestID: 1)
        XCTAssertEqual(snapshot.health.state, .healthy)
        XCTAssertFalse(snapshot.isStale)
        XCTAssertTrue(snapshot.isConfirmedEmpty)
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func testKeepaliveFailureSchedulesRecoveryAttempt() async {
        let remote = makeRemote(name: "Recovery", autoConnect: false)
        let initial = BrowserTransportListResult(
            resolvedPath: "/D:/wwwroot",
            entries: [
                RemoteDirectoryItem(name: "site-a", fullPath: "/D:/wwwroot/site-a", isDirectory: true, modifiedAt: nil, sizeBytes: nil)
            ],
            latencyMs: 6,
            reopenedSession: false
        )
        let recovered = BrowserTransportListResult(
            resolvedPath: "/D:/wwwroot",
            entries: [
                RemoteDirectoryItem(name: "site-a", fullPath: "/D:/wwwroot/site-a", isDirectory: true, modifiedAt: nil, sizeBytes: nil),
                RemoteDirectoryItem(name: "site-b", fullPath: "/D:/wwwroot/site-b", isDirectory: true, modifiedAt: nil, sizeBytes: nil)
            ],
            latencyMs: 7,
            reopenedSession: false
        )

        let transport = FakeBrowserTransport(
            results: [.success(initial), .success(recovered)],
            pingResults: [.failure(AppError.remoteBrowserError("simulated keepalive drop"))]
        )
        let actor = LibSSH2SessionActor(
            id: UUID(),
            remote: remote,
            password: nil,
            transport: transport,
            diagnostics: DiagnosticsService(),
            requestRetrySchedule: [10_000_000],
            recoveryRetrySchedule: [20_000_000, 40_000_000],
            keepAliveIntervalNanoseconds: 50_000_000
        )

        _ = await actor.list(path: "/D:/wwwroot", requestID: 1)
        try? await Task.sleep(nanoseconds: 350_000_000)

        let health = await actor.currentHealth()
        XCTAssertEqual(health.state, .healthy)
        XCTAssertGreaterThanOrEqual(transport.currentListCallCount, 2)
        XCTAssertGreaterThanOrEqual(transport.currentPingCallCount, 1)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testStalledBusyOperationReplacementRules() {
        XCTAssertTrue(
            RemotesViewModel.shouldReplaceBusyOperation(
                newIntent: .connect,
                newTrigger: .recovery,
                existingIntent: .connect,
                elapsedSeconds: 21,
                thresholdSeconds: 20
            )
        )

        XCTAssertTrue(
            RemotesViewModel.shouldReplaceBusyOperation(
                newIntent: .connect,
                newTrigger: .startup,
                existingIntent: .refresh,
                elapsedSeconds: 25,
                thresholdSeconds: 20
            )
        )

        XCTAssertFalse(
            RemotesViewModel.shouldReplaceBusyOperation(
                newIntent: .refresh,
                newTrigger: .recovery,
                existingIntent: .connect,
                elapsedSeconds: 30,
                thresholdSeconds: 20
            )
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testStalledBusyOperationReplacementThresholdEdge() {
        XCTAssertFalse(
            RemotesViewModel.shouldReplaceBusyOperation(
                newIntent: .connect,
                newTrigger: .recovery,
                existingIntent: .connect,
                elapsedSeconds: 19.99,
                thresholdSeconds: 20
            )
        )

        XCTAssertTrue(
            RemotesViewModel.shouldReplaceBusyOperation(
                newIntent: .connect,
                newTrigger: .recovery,
                existingIntent: .connect,
                elapsedSeconds: 20,
                thresholdSeconds: 20
            )
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testStalledBusyOperationReplacementRequiresRecoveryOrStartupTrigger() {
        XCTAssertFalse(
            RemotesViewModel.shouldReplaceBusyOperation(
                newIntent: .connect,
                newTrigger: .manual,
                existingIntent: .connect,
                elapsedSeconds: 30,
                thresholdSeconds: 20
            )
        )

        XCTAssertFalse(
            RemotesViewModel.shouldReplaceBusyOperation(
                newIntent: .disconnect,
                newTrigger: .recovery,
                existingIntent: .connect,
                elapsedSeconds: 30,
                thresholdSeconds: 20
            )
        )
    }

    func testExternalUnmountIsIgnoredDuringWakePreflightOrActiveConnectDisconnect() {
        XCTAssertFalse(
            RemotesViewModel.shouldHandleExternalUnmount(
                currentState: .connected,
                wakePreflightInProgress: true
            )
        )

        XCTAssertFalse(
            RemotesViewModel.shouldHandleExternalUnmount(
                currentState: .connecting,
                wakePreflightInProgress: false
            )
        )

        XCTAssertFalse(
            RemotesViewModel.shouldHandleExternalUnmount(
                currentState: .disconnecting,
                wakePreflightInProgress: false
            )
        )

        XCTAssertTrue(
            RemotesViewModel.shouldHandleExternalUnmount(
                currentState: .connected,
                wakePreflightInProgress: false
            )
        )
    }

    func testConnectOperationMayRestartFromConnectingState() {
        XCTAssertTrue(RemotesViewModel.shouldStartConnectOperation(from: .connecting))
        XCTAssertTrue(RemotesViewModel.shouldStartConnectOperation(from: .error))
        XCTAssertFalse(RemotesViewModel.shouldStartConnectOperation(from: .connected))
    }

    func testDisconnectOperationMayRestartFromDisconnectingState() {
        XCTAssertTrue(RemotesViewModel.shouldStartDisconnectOperation(from: .disconnecting))
        XCTAssertTrue(RemotesViewModel.shouldStartDisconnectOperation(from: .error))
        XCTAssertFalse(RemotesViewModel.shouldStartDisconnectOperation(from: .disconnected))
    }

    func testTimeoutCleanupStatusKeepsActualMountedStateWhenCleanupDidNotFinish() {
        let refreshed = RemoteStatus(
            state: .connected,
            mountedPath: "/tmp/live-mount",
            lastError: nil,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let status = RemotesViewModel.statusAfterTimeoutCleanup(
            refreshed,
            timedOutIntent: .connect
        )

        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.mountedPath, "/tmp/live-mount")
        XCTAssertNil(status.lastError)
        XCTAssertEqual(status.updatedAt, Date(timeIntervalSince1970: 100))
    }

    func testTimeoutCleanupStatusAnnotatesSuccessfulResetOnlyWhenUnmounted() {
        let refreshed = RemoteStatus(
            state: .disconnected,
            mountedPath: nil,
            lastError: nil,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let status = RemotesViewModel.statusAfterTimeoutCleanup(
            refreshed,
            timedOutIntent: .connect
        )

        XCTAssertEqual(status.state, .disconnected)
        XCTAssertEqual(status.lastError, "Connection reset after timeout.")
        XCTAssertNotEqual(status.updatedAt, Date(timeIntervalSince1970: 200))
    }

    func testDisconnectTimeoutCleanupClearsErrorWhenUnmountFinished() {
        let refreshed = RemoteStatus(
            state: .disconnected,
            mountedPath: nil,
            lastError: nil,
            updatedAt: Date(timeIntervalSince1970: 300)
        )

        let status = RemotesViewModel.statusAfterTimeoutCleanup(
            refreshed,
            timedOutIntent: .disconnect,
            timeoutMessage: "Disconnect timed out."
        )

        XCTAssertEqual(status.state, .disconnected)
        XCTAssertNil(status.lastError)
        XCTAssertNotEqual(status.updatedAt, Date(timeIntervalSince1970: 300))
    }

    func testDisconnectTimeoutCleanupPreservesFailureWhenMountStillPresent() {
        let refreshed = RemoteStatus(
            state: .connected,
            mountedPath: "/tmp/live-mount",
            lastError: nil,
            updatedAt: Date(timeIntervalSince1970: 400)
        )

        let status = RemotesViewModel.statusAfterTimeoutCleanup(
            refreshed,
            timedOutIntent: .disconnect,
            timeoutMessage: "Disconnect timed out after 10s."
        )

        XCTAssertEqual(status.state, .error)
        XCTAssertEqual(status.mountedPath, "/tmp/live-mount")
        XCTAssertEqual(status.lastError, "Disconnect timed out after 10s.")
        XCTAssertNotEqual(status.updatedAt, Date(timeIntervalSince1970: 400))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func makeRemote(name: String, autoConnect: Bool, isFavorite: Bool = false) -> RemoteConfig {
        RemoteConfig(
            displayName: name,
            host: "example.com",
            port: 22,
            username: "dev",
            authMode: .privateKey,
            privateKeyPath: "/Users/dev/.ssh/id_ed25519",
            remoteDirectory: "/srv",
            localMountPoint: "/tmp/\(name.lowercased())",
            isFavorite: isFavorite,
            autoConnectOnLaunch: autoConnect
        )
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
private final class FakeBrowserTransport: BrowserTransport {
    private let lock = NSLock()
    private var results: [Result<BrowserTransportListResult, Error>]
    private var pingResults: [Result<Void, Error>]
    private(set) var listCallCount: Int = 0
    private(set) var pingCallCount: Int = 0

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        results: [Result<BrowserTransportListResult, Error>],
        pingResults: [Result<Void, Error>] = []
    ) {
        self.results = results
        self.pingResults = pingResults
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func listDirectories(remote: RemoteConfig, path: String, password: String?) async throws -> BrowserTransportListResult {
        let next: Result<BrowserTransportListResult, Error>? = lock.withLock {
            listCallCount += 1
            return results.isEmpty ? nil : results.removeFirst()
        }

        if let next {
            switch next {
            case .success(let value):
                return value
            case .failure(let error):
                throw error
            }
        }

        return BrowserTransportListResult(
            resolvedPath: path,
            entries: [],
            latencyMs: 1,
            reopenedSession: false
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func ping(remote: RemoteConfig, path: String, password: String?) async throws {
        let next: Result<Void, Error>? = lock.withLock {
            pingCallCount += 1
            return pingResults.isEmpty ? nil : pingResults.removeFirst()
        }

        if let next {
            switch next {
            case .success:
                return
            case .failure(let error):
                throw error
            }
        }
    }

    var currentListCallCount: Int {
        lock.withLock { listCallCount }
    }

    var currentPingCallCount: Int {
        lock.withLock { pingCallCount }
    }
}
