// BEGINNER FILE GUIDE
// Layer: Automated test layer
// Purpose: This file verifies production behavior and protects against regressions when code changes.
// Called by: Executed by XCTest during xcodebuild test or IDE test runs.
// Calls into: Calls production code and test fixtures with deterministic assertions.
// Concurrency: Contains async functions; these can suspend and resume without blocking the calling thread.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import XCTest
@testable import macfuseGui

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class ProcessRunnerTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func testTimedOutNoisyProcessReturnsSafely() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "i=0; while [ $i -lt 2000 ]; do echo \"line-$i\"; i=$((i+1)); done; sleep 10"
            ],
            timeout: 1.0
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertTrue(result.duration < 6.5, "Timed-out process should not hang for a long duration.")
        XCTAssertTrue(result.stdout.contains("line-"), "Expected partial stdout to be captured before timeout.")
    }

    /// Detached descendants can keep stdio pipes open after the timed-out parent exits.
    /// Runner timeout teardown must remain bounded even when EOF is delayed by descendants.
    func testTimedOutProcessWithDetachedChildPipeDoesNotHang() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "/usr/bin/python3 -c 'import os,time; os.setsid(); time.sleep(20)' & echo child:$!; sleep 20"
            ],
            timeout: 1.0
        )

        if let childPID = childPIDFromOutput(result.stdout), childPID > 1 {
            _ = Darwin.kill(childPID, SIGKILL)
        }

        XCTAssertTrue(result.timedOut)
        XCTAssertTrue(result.duration < 6.5, "Timed-out process should not wait on detached descendants holding stdio.")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func testCapturesStdoutAndStderrWithoutTimeout() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "echo out-1; echo err-1 1>&2; echo out-2; echo err-2 1>&2"
            ],
            timeout: 5
        )

        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("out-1"))
        XCTAssertTrue(result.stdout.contains("out-2"))
        XCTAssertTrue(result.stderr.contains("err-1"))
        XCTAssertTrue(result.stderr.contains("err-2"))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func testTaskCancellationTerminatesUnderlyingProcessPromptly() async throws {
        let runner = ProcessRunner()
        let startedAt = Date()

        let task = Task {
            try await runner.run(
                executable: "/bin/sh",
                arguments: ["-c", "sleep 30"],
                timeout: 60
            )
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        task.cancel()

        let result = try await task.value
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 4.0, "Cancelled process should terminate promptly.")
        XCTAssertTrue(result.timedOut || result.exitCode != 0, "Cancelled process should not report a clean successful exit.")
    }

    private func childPIDFromOutput(_ output: String) -> Int32? {
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.hasPrefix("child:") else {
                continue
            }
            let pidText = String(text.dropFirst("child:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = Int32(pidText), pid > 0 {
                return pid
            }
        }
        return nil
    }
}

/// Beginner note: These tests cover askpass secret-handling helpers used by mount connect.
final class AskpassHelperTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func testMakeContextCreatesSecuredScriptAndEnvironment() throws {
        let helper = AskpassHelper()
        let context = try helper.makeContext(password: "topsecret")
        defer { helper.cleanup(context) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: context.scriptURL.path))
        XCTAssertEqual(context.environment["SSH_ASKPASS"], context.scriptURL.path)
        XCTAssertEqual(context.environment["SSH_ASKPASS_REQUIRE"], "force")
        XCTAssertEqual(context.environment["DISPLAY"], "1")

        guard let passwordKey = context.environment.keys.first(where: { $0.hasPrefix("MACFUSEGUI_ASKPASS_PASSWORD_") }) else {
            XCTFail("Expected generated askpass password environment key.")
            return
        }

        XCTAssertEqual(context.environment[passwordKey], "topsecret")
        XCTAssertNotNil(passwordKey.range(of: "^[A-Z0-9_]+$", options: .regularExpression))

        let scriptText = try String(contentsOf: context.scriptURL)
        XCTAssertTrue(scriptText.contains("${\(passwordKey)}"))

        let attributes = try FileManager.default.attributesOfItem(atPath: context.scriptURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
            ?? (attributes[.posixPermissions] as? Int)
        XCTAssertEqual(permissions, 0o700)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func testWithContextCleansUpTemporaryDirectory() async throws {
        let helper = AskpassHelper()
        var scriptURL: URL?
        var tempDirectoryURL: URL?

        try await helper.withContext(password: "secret") { context in
            scriptURL = context.scriptURL
            tempDirectoryURL = context.temporaryDirectoryURL
            XCTAssertTrue(FileManager.default.fileExists(atPath: context.scriptURL.path))
            return ()
        }

        guard let scriptURL, let tempDirectoryURL else {
            XCTFail("Expected context URLs to be captured.")
            return
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: scriptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectoryURL.path))
    }
}

/// Beginner note: These tests cover mount concurrency guarantees that protect recovery behavior.
final class MountManagerParallelOperationTests: XCTestCase {
    /// Beginner note: This is async and throwing: callers must await it and handle failures.
    func testSlowRemoteConnectDoesNotBlockAnotherRemoteConnect() async throws {
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [
                "/tmp/macfusegui-tests/remote-a": 2.8,
                "/tmp/macfusegui-tests/remote-b": 0.1
            ]
        )
        let manager = makeManager(runner: runner)

        let remoteA = makeRemote(name: "A", mountPoint: "/tmp/macfusegui-tests/remote-a")
        let remoteB = makeRemote(name: "B", mountPoint: "/tmp/macfusegui-tests/remote-b")

        async let connectA = manager.connect(remote: remoteA, password: nil)
        try? await Task.sleep(nanoseconds: 80_000_000)

        let connectBStartedAt = Date()
        async let connectB = manager.connect(remote: remoteB, password: nil)

        let statusB = await connectB
        let connectBElapsed = Date().timeIntervalSince(connectBStartedAt)
        let statusA = await connectA

        XCTAssertEqual(statusB.state, .connected, "Remote B should connect successfully even while A is slow.")
        XCTAssertLessThan(connectBElapsed, 1.8, "Remote B should not wait for Remote A's slower connect path.")
        XCTAssertEqual(statusA.state, .connected, "Remote A should eventually connect too.")
    }

    /// Beginner note: This is async and throwing: callers must await it and handle failures.
    func testMountInspectionTimeoutIsBounded() async throws {
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            mountInspectionDelay: 3.2
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "inspect", mountPoint: "/tmp/macfusegui-tests/inspect")

        let startedAt = Date()
        _ = await manager.refreshStatus(remote: remote)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 6.0, "Mount inspection should be bounded by hard timeouts.")
    }

    /// Beginner note: df fallback parsing must preserve mount points containing spaces.
    func testRefreshStatusUsesDFFallbackForMountPointWithSpaces() async throws {
        let mountPoint = "/tmp/macfusegui-tests/space mount"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            mountInspectionDelay: 3.2
        )
        await runner.simulateExternalMount(mountPoint: mountPoint)
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "DF Spaces", mountPoint: mountPoint)

        let status = await manager.refreshStatus(remote: remote)

        XCTAssertEqual(status.state, .connected, "df fallback should parse mount points with spaces.")
        XCTAssertEqual(status.mountedPath, mountPoint)
    }

    /// Beginner note: This method proves that a cancelled stale connect does not wedge future reconnect attempts.
    /// This is async and throwing: callers must await it and handle failures.
    func testCancelledStaleConnectAllowsFreshReconnect() async throws {
        let mountPoint = "/tmp/macfusegui-tests/reconnect-a"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            connectDelayScheduleByMountPoint: [
                mountPoint: [5.0, 0.05]
            ]
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Reconnect", mountPoint: mountPoint)

        let staleTask = Task { await manager.connect(remote: remote, password: nil) }
        try? await Task.sleep(nanoseconds: 180_000_000)
        staleTask.cancel()
        _ = await staleTask.value

        let restartedAt = Date()
        let freshStatus = await manager.connect(remote: remote, password: nil)
        let restartedElapsed = Date().timeIntervalSince(restartedAt)

        XCTAssertEqual(freshStatus.state, .connected, "Fresh reconnect should succeed after stale operation cancellation.")
        XCTAssertLessThan(restartedElapsed, 1.8, "Fresh reconnect should start and complete quickly after cancellation.")
    }

    /// Beginner note: Connect should not fail early just because pre-connect mount inspection timed out.
    /// Recovery should still attempt sshfs and succeed when fallback detection confirms mount.
    func testConnectContinuesWhenPreConnectInspectionTimesOut() async throws {
        let mountPoint = "/tmp/macfusegui-tests/reconnect-timeout"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            mountInspectionDelay: 3.2
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Inspection Timeout", mountPoint: mountPoint)

        let startedAt = Date()
        let status = await manager.connect(remote: remote, password: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status.state, .connected, "Connect should continue when pre-connect mount inspection is flaky.")
        XCTAssertLessThan(elapsed, 12.0, "Connect should remain bounded even when mount inspection initially times out.")
    }

    /// Beginner note: If `/sbin/mount` output shape changes and parser misses the mount line,
    /// connect should still succeed quickly by using df fallback during post-connect detection.
    func testConnectUsesDFFallbackWhenMountOutputIsUnparseable() async throws {
        let mountPoint = "/tmp/macfusegui-tests/connect-df-fallback"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            forceUnparseableMountOutput: true
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Connect DF Fallback", mountPoint: mountPoint)

        let startedAt = Date()
        let status = await manager.connect(remote: remote, password: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.mountedPath, mountPoint)
        XCTAssertLessThan(elapsed, 2.0, "DF fallback should avoid long connect detection waits.")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// It verifies we do not preserve "connected" forever when mount table checks keep missing.
    func testResponsivePathDoesNotPreserveConnectedForeverWithoutMountRecord() async throws {
        let mountPoint = "/tmp/macfusegui-tests/stale-preserve-limit"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            alwaysResponsivePaths: [mountPoint]
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Stale Preserve", mountPoint: mountPoint)

        let connected = await manager.connect(remote: remote, password: nil)
        XCTAssertEqual(connected.state, .connected)

        await runner.simulateExternalUnmount(mountPoint: mountPoint)

        let first = await manager.refreshStatus(remote: remote)
        let second = await manager.refreshStatus(remote: remote)
        let third = await manager.refreshStatus(remote: remote)

        XCTAssertEqual(first.state, .connected)
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(third.state, .error)
        XCTAssertTrue((third.lastError ?? "").localizedCaseInsensitiveContains("could not be verified"))
    }

    /// Beginner note: A stale FUSE mount can pass metadata stat probes but fail directory queries.
    /// Refresh should preserve connected briefly, then escalate to error for recovery.
    func testRefreshDetectsStaleMountWhenDirectoryQueryFails() async throws {
        let mountPoint = "/tmp/macfusegui-tests/stale-dir-query"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            alwaysResponsivePaths: [mountPoint],
            unreadableMountedPaths: [mountPoint]
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Stale Directory Query", mountPoint: mountPoint)

        let connected = await manager.connect(remote: remote, password: nil)
        XCTAssertEqual(connected.state, .connected)

        let first = await manager.refreshStatus(remote: remote)
        let second = await manager.refreshStatus(remote: remote)
        let third = await manager.refreshStatus(remote: remote)

        XCTAssertEqual(first.state, .connected)
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(third.state, .error)
        XCTAssertTrue((third.lastError ?? "").localizedCaseInsensitiveContains("stale mount"))
    }

    /// Beginner note: One-off directory query timeouts can be transient on healthy network mounts.
    /// Refresh should preserve connected briefly before escalating to stale recovery.
    func testRefreshPreservesConnectedBeforeEscalatingRepeatedDirectoryQueryTimeouts() async throws {
        let mountPoint = "/tmp/macfusegui-tests/stale-timeout-preserve"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            alwaysResponsivePaths: [mountPoint],
            timedOutDirectoryQueryPaths: [mountPoint]
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Stale Timeout Preserve", mountPoint: mountPoint)

        let connected = await manager.connect(remote: remote, password: nil)
        XCTAssertEqual(connected.state, .connected)

        let first = await manager.refreshStatus(remote: remote)
        let second = await manager.refreshStatus(remote: remote)
        let third = await manager.refreshStatus(remote: remote)
        let fourth = await manager.refreshStatus(remote: remote)

        XCTAssertEqual(first.state, .connected)
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(third.state, .error)
        XCTAssertEqual(fourth.state, .error)
        XCTAssertTrue((third.lastError ?? "").localizedCaseInsensitiveContains("stale mount"))
    }

    /// Beginner note: Startup refresh begins from uncached .initial/.disconnected state.
    /// If mount is present and metadata probe is healthy, treat initial directory-query
    /// timeouts as transient and preserve connected briefly before escalating.
    func testStartupRefreshPreservesConnectedWhenMountExistsAndDirectoryQueryTimesOut() async throws {
        let mountPoint = "/tmp/macfusegui-tests/startup-timeout-preserve"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            timedOutDirectoryQueryPaths: [mountPoint]
        )
        await runner.simulateExternalMount(mountPoint: mountPoint)

        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Startup Timeout Preserve", mountPoint: mountPoint)

        // Explicit startup precondition: no cached status yet for this remote.
        let initialStatus = await manager.status(for: remote.id)
        XCTAssertEqual(initialStatus.state, .disconnected)

        let first = await manager.refreshStatus(remote: remote)
        let second = await manager.refreshStatus(remote: remote)
        let third = await manager.refreshStatus(remote: remote)

        XCTAssertEqual(first.state, .connected)
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(third.state, .error)
        XCTAssertTrue((third.lastError ?? "").localizedCaseInsensitiveContains("stale mount"))
    }

    /// Beginner note: Startup refresh should apply the same short grace window for
    /// non-timeout directory query failures when mount table and metadata probes are healthy.
    func testStartupRefreshPreservesConnectedWhenMountExistsAndDirectoryQueryFails() async throws {
        let mountPoint = "/tmp/macfusegui-tests/startup-failed-query-preserve"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            alwaysResponsivePaths: [mountPoint],
            unreadableMountedPaths: [mountPoint]
        )
        await runner.simulateExternalMount(mountPoint: mountPoint)

        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Startup Failed Query Preserve", mountPoint: mountPoint)

        // Explicit startup precondition: no cached status yet for this remote.
        let initialStatus = await manager.status(for: remote.id)
        XCTAssertEqual(initialStatus.state, .disconnected)

        let first = await manager.refreshStatus(remote: remote)
        let second = await manager.refreshStatus(remote: remote)
        let third = await manager.refreshStatus(remote: remote)

        XCTAssertEqual(first.state, .connected)
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(third.state, .error)
        XCTAssertTrue((third.lastError ?? "").localizedCaseInsensitiveContains("stale mount"))
    }

    /// Beginner note: After cleanup-driven reconnect, directory query checks can fail briefly
    /// while the mount warms up. Keep a short cooldown so we do not re-trigger stale recovery
    /// immediately after a successful reconnect.
    func testRefreshAppliesShortCooldownAfterCleanupReconnectBeforeDirectoryEscalation() async throws {
        let mountPoint = "/tmp/macfusegui-tests/reconnect-dir-query-cooldown"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            alwaysResponsivePaths: [mountPoint],
            unreadableMountedPaths: [mountPoint]
        )
        let manager = makeManager(
            runner: runner,
            directoryQueryReconnectCooldownSeconds: 0.5
        )
        let remote = makeRemote(name: "Reconnect Cooldown", mountPoint: mountPoint)

        let initial = await manager.connect(remote: remote, password: nil)
        XCTAssertEqual(initial.state, .connected)

        // Second connect forces pre-connect cleanup because mount is already active.
        let reconnect = await manager.connect(remote: remote, password: nil)
        XCTAssertEqual(reconnect.state, .connected)

        // During cooldown, repeated dir-query failures should stay connected.
        let first = await manager.refreshStatus(remote: remote)
        let second = await manager.refreshStatus(remote: remote)
        let third = await manager.refreshStatus(remote: remote)
        XCTAssertEqual(first.state, .connected)
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(third.state, .connected)

        // After cooldown expires, normal strike escalation should resume.
        try? await Task.sleep(nanoseconds: 650_000_000)
        let fourth = await manager.refreshStatus(remote: remote)
        let fifth = await manager.refreshStatus(remote: remote)
        let sixth = await manager.refreshStatus(remote: remote)
        XCTAssertEqual(fourth.state, .connected)
        XCTAssertEqual(fifth.state, .connected)
        XCTAssertEqual(sixth.state, .error)
        XCTAssertTrue((sixth.lastError ?? "").localizedCaseInsensitiveContains("stale mount"))
    }

    /// Beginner note: Diagnostics should expose per-remote directory-query probe counters
    /// so intermittent stale patterns are obvious in support snapshots.
    func testRefreshProbeDiagnosticsSummaryReportsDirectoryQueryCounters() async throws {
        let mountPoint = "/tmp/macfusegui-tests/dir-query-diagnostics-summary"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            alwaysResponsivePaths: [mountPoint],
            unreadableMountedPaths: [mountPoint]
        )
        let manager = makeManager(
            runner: runner,
            directoryQueryReconnectCooldownSeconds: 0
        )
        let remote = makeRemote(name: "Diagnostics Summary", mountPoint: mountPoint)

        let connected = await manager.connect(remote: remote, password: nil)
        XCTAssertEqual(connected.state, .connected)

        _ = await manager.refreshStatus(remote: remote)
        _ = await manager.refreshStatus(remote: remote)
        _ = await manager.refreshStatus(remote: remote)

        let summary = await manager.refreshProbeDiagnosticsSummary(remotes: [remote])
        XCTAssertTrue(summary.contains("timeoutEvents=0"))
        XCTAssertTrue(summary.contains("deviceNotConfiguredEvents=3"))
        XCTAssertTrue(summary.contains("staleEscalations=1"))
        XCTAssertTrue(summary.contains("cooldownSuppressions=0"))
    }

    private func makeManager(
        runner: ProcessRunning,
        directoryQueryReconnectCooldownSeconds: TimeInterval = 30
    ) -> MountManager {
        let diagnostics = DiagnosticsService()
        let parser = MountStateParser()
        return MountManager(
            runner: runner,
            dependencyChecker: ReadyDependencyChecker(),
            askpassHelper: AskpassHelper(),
            unmountService: UnmountService(
                runner: runner,
                diagnostics: diagnostics,
                mountStateParser: parser
            ),
            mountStateParser: parser,
            diagnostics: diagnostics,
            commandBuilder: MountCommandBuilder(redactionService: RedactionService()),
            directoryQueryReconnectCooldownSeconds: directoryQueryReconnectCooldownSeconds
        )
    }

    private func makeRemote(name: String, mountPoint: String) -> RemoteConfig {
        RemoteConfig(
            displayName: "Remote \(name)",
            host: "10.0.0.2",
            port: 22,
            username: "Administrator",
            authMode: .privateKey,
            privateKeyPath: "/tmp/mock-id",
            remoteDirectory: "/D:/wwwroot",
            localMountPoint: mountPoint
        )
    }
}

private struct ReadyDependencyChecker: DependencyChecking {
    func check(sshfsOverride: String?) -> DependencyStatus {
        DependencyStatus(
            isReady: true,
            sshfsPath: sshfsOverride ?? "/usr/bin/sshfs",
            issues: []
        )
    }
}

private actor FakeMountRunner: ProcessRunning {
    private var mountedPoints: Set<String> = []
    private let alwaysResponsivePaths: Set<String>
    private let unreadableMountedPaths: Set<String>
    private let timedOutDirectoryQueryPaths: Set<String>
    private let connectDelayByMountPoint: [String: TimeInterval]
    private var connectDelayScheduleByMountPoint: [String: [TimeInterval]]
    private let mountInspectionDelay: TimeInterval
    private let forceUnparseableMountOutput: Bool

    init(
        connectDelayByMountPoint: [String: TimeInterval],
        connectDelayScheduleByMountPoint: [String: [TimeInterval]] = [:],
        mountInspectionDelay: TimeInterval = 0,
        alwaysResponsivePaths: Set<String> = [],
        unreadableMountedPaths: Set<String> = [],
        timedOutDirectoryQueryPaths: Set<String> = [],
        forceUnparseableMountOutput: Bool = false
    ) {
        self.connectDelayByMountPoint = connectDelayByMountPoint
        self.connectDelayScheduleByMountPoint = connectDelayScheduleByMountPoint
        self.mountInspectionDelay = mountInspectionDelay
        self.alwaysResponsivePaths = alwaysResponsivePaths
        self.unreadableMountedPaths = unreadableMountedPaths
        self.timedOutDirectoryQueryPaths = timedOutDirectoryQueryPaths
        self.forceUnparseableMountOutput = forceUnparseableMountOutput
    }

    func simulateExternalUnmount(mountPoint: String) {
        mountedPoints.remove(mountPoint)
    }

    func simulateExternalMount(mountPoint: String) {
        mountedPoints.insert(mountPoint)
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        standardInput: String?
    ) async throws -> ProcessResult {
        let startedAt = Date()

        if executable.hasSuffix("sshfs"), let mountPoint = arguments.last {
            let delay: TimeInterval
            if var scheduled = connectDelayScheduleByMountPoint[mountPoint], !scheduled.isEmpty {
                delay = scheduled.removeFirst()
                connectDelayScheduleByMountPoint[mountPoint] = scheduled
            } else {
                delay = connectDelayByMountPoint[mountPoint] ?? 0
            }

            if delay > 0 {
                let deadline = Date().addingTimeInterval(delay)
                while Date() < deadline {
                    if Task.isCancelled {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 25_000_000)
                }
            }
            if Task.isCancelled {
                return ProcessResult(
                    executable: executable,
                    arguments: arguments,
                    stdout: "",
                    stderr: "cancelled",
                    exitCode: -1,
                    timedOut: true,
                    duration: Date().timeIntervalSince(startedAt)
                )
            }

            mountedPoints.insert(mountPoint)

            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "",
                exitCode: 0,
                timedOut: false,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        if executable == "/sbin/mount" {
            if mountInspectionDelay > 0 {
                let boundedDelay = min(mountInspectionDelay, timeout + 0.05)
                try? await Task.sleep(nanoseconds: UInt64(boundedDelay * 1_000_000_000))
            }

            let points = mountedPoints.sorted()
            let output: String
            if forceUnparseableMountOutput {
                output = points
                    .map { "mock@host:/remote mounted at \($0) type fusefs" }
                    .joined(separator: "\n")
            } else {
                output = points
                    .map { "mock@host:/remote on \($0) (fusefs, nodev, nosuid, synchronous)" }
                    .joined(separator: "\n")
            }

            let timedOut = mountInspectionDelay > timeout
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: timedOut ? "" : output,
                stderr: timedOut ? "timed out" : "",
                exitCode: timedOut ? 1 : 0,
                timedOut: timedOut,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        if executable == "/bin/df", let mountPoint = arguments.last {
            let isMounted = mountedPoints.contains(mountPoint)
            let stdout: String
            if isMounted {
                stdout = """
                Filesystem 512-blocks Used Available Capacity Mounted on
                mock@host:/remote 1024 128 896 13% \(escapeDFPath(mountPoint))
                """
            } else {
                stdout = ""
            }
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: stdout,
                stderr: "",
                exitCode: isMounted ? 0 : 1,
                timedOut: false,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        if executable == "/usr/bin/stat", let path = arguments.last {
            let isMounted = mountedPoints.contains(path) || alwaysResponsivePaths.contains(path)
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: isMounted ? path : "",
                stderr: isMounted ? "" : "No such file or directory",
                exitCode: isMounted ? 0 : 1,
                timedOut: false,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        if executable == "/usr/bin/find", let path = arguments.first {
            let isMounted = mountedPoints.contains(path)
            let shouldTimeout = timedOutDirectoryQueryPaths.contains(path)
            let isUnreadable = unreadableMountedPaths.contains(path)
            let success = isMounted && !isUnreadable && !shouldTimeout
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: success ? path : "",
                stderr: shouldTimeout ? "timed out" : (success ? "" : (isMounted ? "Device not configured" : "No such file or directory")),
                exitCode: shouldTimeout ? 15 : (success ? 0 : 1),
                timedOut: shouldTimeout,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        if executable == "/usr/sbin/diskutil" || executable == "/sbin/umount" {
            if let mountPoint = arguments.last {
                mountedPoints.remove(mountPoint)
            }
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "",
                exitCode: 0,
                timedOut: false,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        return ProcessResult(
            executable: executable,
            arguments: arguments,
            stdout: "",
            stderr: "",
            exitCode: 0,
            timedOut: false,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private func escapeDFPath(_ path: String) -> String {
        path.replacingOccurrences(of: " ", with: "\\040")
    }
}
