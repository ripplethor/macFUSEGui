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
    /// Refresh should mark this as error so recovery can reconnect instead of showing false-connected.
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

        let refreshed = await manager.refreshStatus(remote: remote)
        XCTAssertEqual(refreshed.state, .error)
        XCTAssertTrue((refreshed.lastError ?? "").localizedCaseInsensitiveContains("stale mount"))
    }

    private func makeManager(runner: ProcessRunning) -> MountManager {
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
            commandBuilder: MountCommandBuilder(redactionService: RedactionService())
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
    private let connectDelayByMountPoint: [String: TimeInterval]
    private var connectDelayScheduleByMountPoint: [String: [TimeInterval]]
    private let mountInspectionDelay: TimeInterval

    init(
        connectDelayByMountPoint: [String: TimeInterval],
        connectDelayScheduleByMountPoint: [String: [TimeInterval]] = [:],
        mountInspectionDelay: TimeInterval = 0,
        alwaysResponsivePaths: Set<String> = [],
        unreadableMountedPaths: Set<String> = []
    ) {
        self.connectDelayByMountPoint = connectDelayByMountPoint
        self.connectDelayScheduleByMountPoint = connectDelayScheduleByMountPoint
        self.mountInspectionDelay = mountInspectionDelay
        self.alwaysResponsivePaths = alwaysResponsivePaths
        self.unreadableMountedPaths = unreadableMountedPaths
    }

    func simulateExternalUnmount(mountPoint: String) {
        mountedPoints.remove(mountPoint)
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
            let output = points
                .map { "mock@host:/remote on \($0) (fusefs, nodev, nosuid, synchronous)" }
                .joined(separator: "\n")

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
                mock@host:/remote 1024 128 896 13% \(mountPoint)
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
            let isUnreadable = unreadableMountedPaths.contains(path)
            let success = isMounted && !isUnreadable
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: success ? path : "",
                stderr: success ? "" : (isMounted ? "Device not configured" : "No such file or directory"),
                exitCode: success ? 0 : 1,
                timedOut: false,
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
}
