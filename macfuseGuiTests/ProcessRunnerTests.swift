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
    func testEnvTestResolvesSystemTestBinaryOnMacOS() async throws {
        let runner = ProcessRunner()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("process-runner-test-\(UUID().uuidString)")
        try Data("secret".utf8).write(to: fileURL, options: [.atomic])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let result = try await runner.run(
            executable: "/usr/bin/env",
            arguments: ["test", "-f", fileURL.path],
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            timeout: 1.5
        )

        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.executable, "/usr/bin/env")
        XCTAssertEqual(result.arguments, ["test", "-f", fileURL.path])
    }

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

    func testConcurrentShortLivedProcessesCaptureOutputReliably() async throws {
        let runner = ProcessRunner()
        let processCount = 24

        try await withThrowingTaskGroup(of: ProcessResult.self) { group in
            for index in 0..<processCount {
                group.addTask {
                    try await runner.run(
                        executable: "/bin/sh",
                        arguments: [
                            "-c",
                            "i=0; while [ $i -lt 40 ]; do echo out-\(index)-$i; echo err-\(index)-$i 1>&2; i=$((i+1)); done"
                        ],
                        timeout: 5
                    )
                }
            }

            var completed = 0
            for try await result in group {
                XCTAssertFalse(result.timedOut)
                XCTAssertEqual(result.exitCode, 0)
                XCTAssertTrue(result.stdout.contains("out-"))
                XCTAssertTrue(result.stderr.contains("err-"))
                completed += 1
            }

            XCTAssertEqual(completed, processCount)
        }
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

        let startedAt = Date()
        let status = await manager.refreshStatus(remote: remote)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status.state, .connected, "df fallback should parse mount points with spaces.")
        XCTAssertEqual(status.mountedPath, mountPoint)
        XCTAssertLessThan(elapsed, 1.0, "Targeted df inspection should avoid waiting on a slow global mount probe.")
    }

    /// Cancellation during refreshStatus must preserve the cached state instead of
    /// synthesizing a `.error` chip with a `Swift.CancellationError` description.
    /// Supersession of a recovery refresh by a newer intent is routine, and the raw
    /// CancellationError description is not a user-meaningful message.
    func testCancelledRefreshStatusPreservesCachedStatusInsteadOfReportingError() async throws {
        let mountPoint = "/tmp/macfusegui-tests/cancelled-refresh"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            mountInspectionDelay: 2.0,
            dfDelayByMountPoint: [mountPoint: 2.0]
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Cancelled Refresh", mountPoint: mountPoint)

        let task = Task { await manager.refreshStatus(remote: remote) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        let status = await task.value

        XCTAssertNotEqual(
            status.state,
            .error,
            "Cancellation must not transition status to .error."
        )
        if let lastError = status.lastError {
            XCTAssertFalse(
                lastError.lowercased().contains("cancellationerror"),
                "Refresh status must not publish a CancellationError to the UI. Got: \(lastError)"
            )
            XCTAssertFalse(
                lastError.contains("couldn't be completed"),
                "Refresh status must not publish a CancellationError to the UI. Got: \(lastError)"
            )
        }
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

    func testConnectFailsWhenPrivateKeyFileProbeReportsMissingPath() async throws {
        let mountPoint = "/tmp/macfusegui-tests/private-key-missing"
        let runner = FakeMountRunner(connectDelayByMountPoint: [:])
        let manager = makeManager(runner: runner)
        let remote = RemoteConfig(
            displayName: "Remote Missing Key",
            host: "10.0.0.2",
            port: 22,
            username: "Administrator",
            authMode: .privateKey,
            privateKeyPath: "/tmp/nonexistent-private-key-\(UUID())",
            remoteDirectory: "/D:/wwwroot",
            localMountPoint: mountPoint
        )

        let status = await manager.connect(remote: remote, password: nil)

        XCTAssertEqual(status.state, .error)
        XCTAssertEqual(status.lastError, "Private key file does not exist.")
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

    /// Beginner note: `df -P <mountPoint>` can briefly resolve to the parent filesystem even
    /// after sshfs has mounted successfully. Connect detection should fall back to `/sbin/mount`
    /// in that narrow window instead of declaring the mount missing.
    func testConnectFallsBackToMountInspectionWhenDFStillShowsParentFilesystem() async throws {
        let mountPoint = "/tmp/macfusegui-tests/connect-mount-fallback"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            dfVisibilityDelayByMountPoint: [mountPoint: 10]
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Connect Mount Fallback", mountPoint: mountPoint)

        let startedAt = Date()
        let status = await manager.connect(remote: remote, password: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.mountedPath, mountPoint)
        XCTAssertLessThan(elapsed, 2.0, "Mount-table fallback should recover connect quickly when df still shows the parent filesystem.")
    }

    /// Beginner note: Some wake/recovery windows leave both `df` and `/sbin/mount`
    /// temporarily unreliable even though the mount point has already switched to a
    /// new filesystem. Connect should use that distinct-filesystem signal and finish.
    func testConnectUsesDistinctFilesystemFallbackWhenDFShowsParentAndMountInspectionTimesOut() async throws {
        let mountPoint = "/tmp/macfusegui-tests/connect-device-fallback"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            mountInspectionDelay: 1.8,
            dfVisibilityDelayByMountPoint: [mountPoint: 10]
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Connect Device Fallback", mountPoint: mountPoint)

        let startedAt = Date()
        let status = await manager.connect(remote: remote, password: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.mountedPath, mountPoint)
        XCTAssertLessThan(elapsed, 6.0, "Distinct-filesystem fallback should keep connect bounded when df and mount inspection are both flaky.")
    }

    /// Beginner note: Some sshfs builds return exit 0 before the mount becomes visible
    /// to either `df` or `/sbin/mount`. Connect should wait within a bounded grace window
    /// instead of declaring failure and triggering duplicate recovery reconnects.
    func testConnectWaitsForDelayedMountAppearanceAfterSSHFSExitsSuccessfully() async throws {
        let mountPoint = "/tmp/macfusegui-tests/connect-delayed-appearance"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            mountAppearanceDelayByMountPoint: [mountPoint: 2.6]
        )
        let manager = makeManager(
            runner: runner,
            postConnectMountDetectionTimeout: 4.5
        )
        let remote = makeRemote(name: "Delayed Appearance", mountPoint: mountPoint)

        let startedAt = Date()
        let status = await manager.connect(remote: remote, password: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.mountedPath, mountPoint)
        XCTAssertGreaterThan(elapsed, 2.4, "Connect should keep waiting until the delayed mount becomes visible.")
        XCTAssertLessThan(elapsed, 5.8, "Delayed visibility grace window should remain bounded.")
    }

    /// Beginner note: `diskutil unmount force` can report success slightly before the mount
    /// fully disappears from subsequent probes. Connect should wait briefly for cleanup to settle
    /// instead of failing immediately with "Mount is still active".
    func testConnectWaitsForCleanupDrivenUnmountToDisappearBeforeRetrying() async throws {
        let mountPoint = "/tmp/macfusegui-tests/connect-unmount-settle"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            unmountVisibilityDelayByMountPoint: [mountPoint: 0.6]
        )
        await runner.simulateExternalMount(mountPoint: mountPoint)
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Connect Unmount Settle", mountPoint: mountPoint)

        let startedAt = Date()
        let status = await manager.connect(remote: remote, password: nil)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.mountedPath, mountPoint)
        XCTAssertGreaterThan(elapsed, 0.5, "Connect should wait for forced unmount cleanup to settle before retrying.")
        XCTAssertLessThan(elapsed, 3.5, "Cleanup settle wait should remain bounded.")
    }

    /// Beginner note: Recovery reconnects often start from a stale mount where `df -P <mount>`
    /// itself can hang. Pre-connect cleanup should switch to mount-table-only checks so one
    /// broken mount does not drag recovery out for the entire menu.
    func testRecoveryConnectUsesMountTableCleanupWhenDFOnStaleMountIsSlow() async throws {
        let mountPoint = "/tmp/macfusegui-tests/recovery-stale-precleanup"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            dfDelayByMountPoint: [mountPoint: 3.2],
            unmountVisibilityDelayByMountPoint: [mountPoint: 0.35]
        )
        await runner.simulateExternalMount(mountPoint: mountPoint)
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Recovery Stale Cleanup", mountPoint: mountPoint)

        let startedAt = Date()
        let status = await manager.connect(
            remote: remote,
            password: nil,
            fastPreConnectCleanup: true
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.mountedPath, mountPoint)
        XCTAssertLessThan(elapsed, 2.8, "Recovery cleanup should avoid waiting on slow stale df probes.")
    }

    /// Beginner note: If mount-table inspection times out during recovery cleanup but the
    /// path is still a mounted filesystem, pre-connect cleanup should still clear it before
    /// the next sshfs attempt instead of hitting the nested-macFUSE error.
    func testRecoveryConnectUsesDistinctFilesystemFallbackWhenMountInspectionTimesOut() async throws {
        let mountPoint = "/tmp/macfusegui-tests/recovery-device-fallback"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            mountInspectionDelay: 1.8
        )
        await runner.simulateExternalMount(mountPoint: mountPoint)
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Recovery Device Fallback", mountPoint: mountPoint)

        let startedAt = Date()
        let status = await manager.connect(
            remote: remote,
            password: nil,
            fastPreConnectCleanup: true
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.mountedPath, mountPoint)
        XCTAssertLessThan(elapsed, 6.0, "Distinct-filesystem fallback should keep recovery cleanup bounded when mount inspection times out.")
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
        let fourth = await manager.refreshStatus(remote: remote)
        let fifth = await manager.refreshStatus(remote: remote)

        XCTAssertEqual(first.state, .connected)
        XCTAssertEqual(second.state, .connected)
        XCTAssertEqual(third.state, .connected)
        XCTAssertEqual(fourth.state, .connected)
        XCTAssertEqual(fifth.state, .error)
        XCTAssertTrue((fifth.lastError ?? "").localizedCaseInsensitiveContains("could not be verified"))
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

    /// Beginner note: Periodic/startup refresh can begin from a disconnected cached state
    /// even when the volume is already mounted. If `df -P` still resolves to the parent
    /// filesystem in that window, refresh should fall back to mount-table inspection instead
    /// of declaring the mount disconnected and triggering a redundant reconnect.
    func testStartupRefreshFallsBackToMountInspectionWhenDFStillShowsParentFilesystem() async throws {
        let mountPoint = "/tmp/macfusegui-tests/startup-refresh-mount-fallback"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            dfVisibilityDelayByMountPoint: [mountPoint: 10]
        )
        await runner.simulateExternalMount(mountPoint: mountPoint)

        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Startup Refresh Mount Fallback", mountPoint: mountPoint)

        let initialStatus = await manager.status(for: remote.id)
        XCTAssertEqual(initialStatus.state, .disconnected)

        let startedAt = Date()
        let refreshed = await manager.refreshStatus(remote: remote)
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertEqual(refreshed.state, .connected)
        XCTAssertEqual(refreshed.mountedPath, mountPoint)
        XCTAssertLessThan(elapsed, 2.0, "Refresh should recover via mount-table fallback instead of reconnecting a healthy mount.")
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

    // MARK: - Detached (foreground sshfs) processes

    func testLaunchDetachedStartsChildInItsOwnSessionAndTerminateStopsIt() async throws {
        let runner = ProcessRunner()
        let process = try await runner.launchDetached(
            executable: "/bin/sleep",
            arguments: ["30"],
            environment: [:]
        )
        let spawned = try XCTUnwrap(process as? SpawnedDetachedProcess)

        XCTAssertEqual(getsid(spawned.pid), spawned.pid, "Child must lead its own session so it outlives the app.")
        XCTAssertNotEqual(getpgid(spawned.pid), getpgrp(), "Child must not share the app's process group.")
        let stillRunning = await process.pollExit()
        XCTAssertNil(stillRunning)

        await process.terminate()

        let exit = await process.pollExit()
        XCTAssertEqual(exit?.exitCode, 128 + SIGTERM)
    }

    func testLaunchDetachedCapturesOutputAndExitCode() async throws {
        let runner = ProcessRunner()
        let process = try await runner.launchDetached(
            executable: "/bin/sh",
            arguments: ["-c", "echo out-line; echo err-line 1>&2; echo \"value=$MACFUSEGUI_DETACHED_TEST\"; exit 3"],
            environment: ["MACFUSEGUI_DETACHED_TEST": "42"]
        )

        let exit = try await waitForDetachedExit(process)

        XCTAssertEqual(exit.exitCode, 3)
        XCTAssertTrue(exit.output.contains("out-line"))
        XCTAssertTrue(exit.output.contains("err-line"))
        XCTAssertTrue(exit.output.contains("value=42"))
    }

    func testReleasedDetachedChildKeepsRunningAndIsReapedOnExit() async throws {
        let runner = ProcessRunner()
        let process = try await runner.launchDetached(
            executable: "/bin/sleep",
            arguments: ["30"],
            environment: [:]
        )
        let pid = try XCTUnwrap(process as? SpawnedDetachedProcess).pid

        await process.release()
        XCTAssertEqual(kill(pid, 0), 0, "Released child should keep running.")

        _ = kill(pid, SIGKILL)
        // A zombie still accepts kill(pid, 0); ESRCH means the reaper collected it.
        let deadline = Date().addingTimeInterval(3)
        var reaped = false
        while Date() < deadline {
            if kill(pid, 0) == -1 && errno == ESRCH {
                reaped = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(reaped, "Released child should be reaped after it exits.")
    }

    /// Beginner note: A failed sshfs can leave its mount_macfuse helper running, which blocks the
    /// mount point for the next attempt. Leftover members of the child's process group are cleared.
    func testDetachedExitClearsLeftoverChildrenInItsProcessGroup() async throws {
        let runner = ProcessRunner()
        let process = try await runner.launchDetached(
            executable: "/bin/sh",
            arguments: ["-c", "/bin/sleep 30 & echo \"leftover=$!\"; exit 1"],
            environment: [:]
        )

        let exit = try await waitForDetachedExit(process)
        XCTAssertEqual(exit.exitCode, 1)
        let leftoverText = try XCTUnwrap(
            exit.output.split(separator: "\n").first { $0.hasPrefix("leftover=") }
        )
        let leftoverPID = try XCTUnwrap(pid_t(leftoverText.dropFirst("leftover=".count)))

        let deadline = Date().addingTimeInterval(3)
        var cleared = false
        while Date() < deadline {
            if kill(leftoverPID, 0) == -1 && errno == ESRCH {
                cleared = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(cleared, "Leftover child in the detached process group should be killed.")
    }

    func testDecodedExitCodeHandlesNormalAndSignalExits() {
        XCTAssertEqual(SpawnedDetachedProcess.decodedExitCode(3 << 8), 3)
        XCTAssertEqual(SpawnedDetachedProcess.decodedExitCode(SIGTERM), 128 + SIGTERM)
    }

    /// Beginner note: macFUSE 5.4+ keeps sshfs in the foreground after mounting. Connect must succeed
    /// once the mount appears and leave the process running instead of waiting for it to exit.
    func testConnectSucceedsWhenForegroundSSHFSMountsWhileStillRunning() async throws {
        let mountPoint = "/tmp/macfusegui-tests/foreground-mounts"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            foregroundSSHFS: .mountsAfter(0.3)
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Foreground", mountPoint: mountPoint)

        let status = await manager.connect(remote: remote, password: nil)

        XCTAssertEqual(status.state, .connected)
        let launched = await runner.launchedForegroundSSHFS
        XCTAssertEqual(launched.count, 1)
        XCTAssertEqual(launched.first?.arguments.first, "-f")
        XCTAssertEqual(launched.first?.wasReleased, true, "Mounted sshfs must be left running.")
        XCTAssertEqual(launched.first?.wasTerminated, false)
    }

    /// Beginner note: Regression for issue #8. The real ssh error must reach the user instead of
    /// macFUSE's fork warning, so permanent failures (auth) stop the reconnect loop.
    func testForegroundSSHFSFailureReportsSSHErrorWithoutMacFUSEForkWarnings() async throws {
        let mountPoint = "/tmp/macfusegui-tests/foreground-auth-failure"
        let output = """
        fuse: forking a threaded process is unsafe, the child may crash or deadlock
        Warning: Permanently added 'pi.local' (ED25519) to the list of known hosts.
        dev@pi.local: Permission denied (publickey).
        remote host has disconnected
        """
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            foregroundSSHFS: .exits(code: 1, output: output)
        )
        let manager = makeManager(runner: runner)
        let remote = makeRemote(name: "Auth Failure", mountPoint: mountPoint)

        let status = await manager.connect(remote: remote, password: nil)

        XCTAssertEqual(status.state, .error)
        let lastError = try XCTUnwrap(status.lastError)
        XCTAssertTrue(lastError.contains("Permission denied (publickey)"), lastError)
        XCTAssertFalse(lastError.contains("forking"), lastError)
        XCTAssertFalse(lastError.contains("Permanently added"), lastError)
    }

    func testForegroundSSHFSIsTerminatedWhenMountNeverAppears() async throws {
        let mountPoint = "/tmp/macfusegui-tests/foreground-hangs"
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            foregroundSSHFS: .hangs
        )
        let manager = makeManager(runner: runner, sshfsConnectCommandTimeout: 1)
        let remote = makeRemote(name: "Hangs", mountPoint: mountPoint)

        let status = await manager.connect(remote: remote, password: nil)

        XCTAssertEqual(status.state, .error)
        XCTAssertTrue(status.lastError?.lowercased().contains("timed out") == true, status.lastError ?? "-")
        let launched = await runner.launchedForegroundSSHFS
        XCTAssertEqual(launched.first?.wasTerminated, true, "A sshfs that never mounted must not be left running.")
    }

    /// Beginner note: While polling a foreground sshfs, the mount often finishes during the slow
    /// `/sbin/mount` read, so df first shows the parent filesystem and then the mount. That is
    /// routine and must not be logged as a detection warning.
    func testMountAppearingDuringProbingIsNotLoggedAsDFFallbackWarning() async throws {
        let mountPoint = "/tmp/macfusegui-tests/foreground-race"
        let diagnostics = DiagnosticsService()
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            mountInspectionDelay: 0.3,
            dfVisibilityDelayByMountPoint: [mountPoint: 0.2],
            forceUnparseableMountOutput: true,
            foregroundSSHFS: .mountsAfter(0)
        )
        let manager = makeManager(runner: runner, diagnostics: diagnostics)
        let remote = makeRemote(name: "Race", mountPoint: mountPoint)

        let status = await manager.connect(remote: remote, password: nil)

        XCTAssertEqual(status.state, .connected)
        let log = diagnostics.snapshot(remotes: [], statuses: [:], dependency: nil)
        XCTAssertTrue(log.contains("became visible during post-connect probing"), log)
        XCTAssertFalse(log.contains("recovered via df fallback"), log)
    }

    /// Beginner note: When df was inconclusive and the mount table did not match, finding the
    /// mount only through df is still worth a warning (possible mount-output parser mismatch).
    func testDFFallbackAfterInconclusiveDFStillLogsWarning() async throws {
        let mountPoint = "/tmp/macfusegui-tests/foreground-df-inconclusive"
        let diagnostics = DiagnosticsService()
        let runner = FakeMountRunner(
            connectDelayByMountPoint: [:],
            mountInspectionDelay: 0.3,
            forceUnparseableMountOutput: true,
            foregroundSSHFS: .mountsAfter(0.15)
        )
        let manager = makeManager(runner: runner, diagnostics: diagnostics)
        let remote = makeRemote(name: "Inconclusive", mountPoint: mountPoint)

        let status = await manager.connect(remote: remote, password: nil)

        XCTAssertEqual(status.state, .connected)
        let log = diagnostics.snapshot(remotes: [], statuses: [:], dependency: nil)
        XCTAssertTrue(log.contains("[warning] [mount] Post-connect detection recovered via df fallback"), log)
        XCTAssertFalse(log.contains("became visible during post-connect probing"), log)
    }

    func testRemovingBenignSSHFSOutputKeepsOutputWhenOnlyNoiseRemains() {
        let onlyNoise = "fuse: forking after mount is not supported"
        XCTAssertEqual(MountManager.removingBenignSSHFSOutput(onlyNoise), onlyNoise)
        XCTAssertEqual(
            MountManager.removingBenignSSHFSOutput("fuse: forking after mount is not supported\nread: Connection reset by peer"),
            "read: Connection reset by peer"
        )
    }

    private func waitForDetachedExit(
        _ process: DetachedProcess,
        timeout: TimeInterval = 5
    ) async throws -> DetachedProcessExit {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let exit = await process.pollExit() {
                return exit
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        await process.terminate()
        return try XCTUnwrap(nil as DetachedProcessExit?, "Detached process did not exit within \(timeout)s")
    }

    private func makeManager(
        runner: ProcessRunning,
        diagnostics: DiagnosticsService = DiagnosticsService(),
        sshfsConnectCommandTimeout: TimeInterval = 20,
        postConnectMountDetectionTimeout: TimeInterval = 15,
        directoryQueryReconnectCooldownSeconds: TimeInterval = 30
    ) -> MountManager {
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
            sshfsConnectCommandTimeout: sshfsConnectCommandTimeout,
            postConnectMountDetectionTimeout: postConnectMountDetectionTimeout,
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
            privateKeyPath: "/etc/hosts",
            remoteDirectory: "/D:/wwwroot",
            localMountPoint: mountPoint
        )
    }
}

/// Beginner note: Stands in for `sshfs -f`: it keeps "running" after the mount appears, like
/// sshfs under macFUSE 5.4+, until the caller releases or terminates it.
private final class FakeForegroundSSHFS: DetachedProcess, @unchecked Sendable {
    enum Behavior: Sendable {
        case mountsAfter(TimeInterval)
        case exits(code: Int32, output: String)
        case hangs
    }

    let arguments: [String]
    private let behavior: Behavior
    private let lock = NSLock()
    private var terminated = false
    private var released = false

    init(behavior: Behavior, arguments: [String]) {
        self.behavior = behavior
        self.arguments = arguments
    }

    var wasTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }

    var wasReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        return released
    }

    func pollExit() async -> DetachedProcessExit? {
        lock.lock()
        defer { lock.unlock() }
        if terminated {
            return DetachedProcessExit(exitCode: 143, output: "")
        }
        if case .exits(let code, let output) = behavior {
            return DetachedProcessExit(exitCode: code, output: output)
        }
        return nil
    }

    func capturedOutput() async -> String {
        ""
    }

    func terminate() async {
        lock.lock()
        terminated = true
        lock.unlock()
    }

    func release() async {
        lock.lock()
        released = true
        lock.unlock()
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
    private var mountActivatedAtByMountPoint: [String: Date] = [:]
    private var pendingMountActivationAtByMountPoint: [String: Date] = [:]
    private var unmountPendingUntilByMountPoint: [String: Date] = [:]
    private let alwaysResponsivePaths: Set<String>
    private let unreadableMountedPaths: Set<String>
    private let timedOutDirectoryQueryPaths: Set<String>
    private let connectDelayByMountPoint: [String: TimeInterval]
    private var connectDelayScheduleByMountPoint: [String: [TimeInterval]]
    private let mountAppearanceDelayByMountPoint: [String: TimeInterval]
    private let mountInspectionDelay: TimeInterval
    private let dfDelayByMountPoint: [String: TimeInterval]
    private let dfVisibilityDelayByMountPoint: [String: TimeInterval]
    private let unmountVisibilityDelayByMountPoint: [String: TimeInterval]
    private let forceUnparseableMountOutput: Bool
    private let foregroundSSHFS: FakeForegroundSSHFS.Behavior?
    private(set) var launchedForegroundSSHFS: [FakeForegroundSSHFS] = []

    init(
        connectDelayByMountPoint: [String: TimeInterval],
        connectDelayScheduleByMountPoint: [String: [TimeInterval]] = [:],
        mountAppearanceDelayByMountPoint: [String: TimeInterval] = [:],
        mountInspectionDelay: TimeInterval = 0,
        alwaysResponsivePaths: Set<String> = [],
        unreadableMountedPaths: Set<String> = [],
        timedOutDirectoryQueryPaths: Set<String> = [],
        dfDelayByMountPoint: [String: TimeInterval] = [:],
        dfVisibilityDelayByMountPoint: [String: TimeInterval] = [:],
        unmountVisibilityDelayByMountPoint: [String: TimeInterval] = [:],
        forceUnparseableMountOutput: Bool = false,
        foregroundSSHFS: FakeForegroundSSHFS.Behavior? = nil
    ) {
        self.connectDelayByMountPoint = connectDelayByMountPoint
        self.connectDelayScheduleByMountPoint = connectDelayScheduleByMountPoint
        self.mountAppearanceDelayByMountPoint = mountAppearanceDelayByMountPoint
        self.mountInspectionDelay = mountInspectionDelay
        self.alwaysResponsivePaths = alwaysResponsivePaths
        self.unreadableMountedPaths = unreadableMountedPaths
        self.timedOutDirectoryQueryPaths = timedOutDirectoryQueryPaths
        self.dfDelayByMountPoint = dfDelayByMountPoint
        self.dfVisibilityDelayByMountPoint = dfVisibilityDelayByMountPoint
        self.unmountVisibilityDelayByMountPoint = unmountVisibilityDelayByMountPoint
        self.forceUnparseableMountOutput = forceUnparseableMountOutput
        self.foregroundSSHFS = foregroundSSHFS
    }

    /// Without `foregroundSSHFS`, sshfs keeps the legacy "exit 0, then mount appears" shape via `run`.
    func launchDetached(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> DetachedProcess {
        guard executable.hasSuffix("sshfs"),
              let behavior = foregroundSSHFS,
              let mountPoint = arguments.last else {
            return RunToCompletionDetachedProcess(
                runner: self,
                executable: executable,
                arguments: arguments,
                environment: environment
            )
        }

        if case .mountsAfter(let delay) = behavior {
            pendingMountActivationAtByMountPoint[mountPoint] = Date().addingTimeInterval(delay)
            unmountPendingUntilByMountPoint.removeValue(forKey: mountPoint)
        }
        let process = FakeForegroundSSHFS(behavior: behavior, arguments: arguments)
        launchedForegroundSSHFS.append(process)
        return process
    }

    func simulateExternalUnmount(mountPoint: String) {
        mountedPoints.remove(mountPoint)
        mountActivatedAtByMountPoint.removeValue(forKey: mountPoint)
        pendingMountActivationAtByMountPoint.removeValue(forKey: mountPoint)
        unmountPendingUntilByMountPoint.removeValue(forKey: mountPoint)
    }

    func simulateExternalMount(mountPoint: String) {
        mountedPoints.insert(mountPoint)
        mountActivatedAtByMountPoint[mountPoint] = Date()
        pendingMountActivationAtByMountPoint.removeValue(forKey: mountPoint)
        unmountPendingUntilByMountPoint.removeValue(forKey: mountPoint)
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

            if let appearanceDelay = mountAppearanceDelayByMountPoint[mountPoint], appearanceDelay > 0 {
                pendingMountActivationAtByMountPoint[mountPoint] = Date().addingTimeInterval(appearanceDelay)
                mountedPoints.remove(mountPoint)
                mountActivatedAtByMountPoint.removeValue(forKey: mountPoint)
            } else {
                mountedPoints.insert(mountPoint)
                mountActivatedAtByMountPoint[mountPoint] = Date()
            }
            unmountPendingUntilByMountPoint.removeValue(forKey: mountPoint)

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
            materializePendingMounts()
            materializePendingUnmounts()
            if mountInspectionDelay > 0 {
                let boundedDelay = min(mountInspectionDelay, timeout + 0.05)
                try? await Task.sleep(nanoseconds: UInt64(boundedDelay * 1_000_000_000))
            }
            materializePendingMounts()

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
            let dfDelay = dfDelayByMountPoint[mountPoint] ?? 0
            if dfDelay > 0 {
                let boundedDelay = min(dfDelay, timeout + 0.05)
                try? await Task.sleep(nanoseconds: UInt64(boundedDelay * 1_000_000_000))
            }
            materializePendingMounts()
            materializePendingUnmounts()
            let timedOut = dfDelay > timeout
            if timedOut {
                return ProcessResult(
                    executable: executable,
                    arguments: arguments,
                    stdout: "",
                    stderr: "timed out",
                    exitCode: 15,
                    timedOut: true,
                    duration: Date().timeIntervalSince(startedAt)
                )
            }
            let isMounted = mountedPoints.contains(mountPoint)
            let stdout: String
            if isMounted, isDFVisible(for: mountPoint) {
                stdout = """
                Filesystem 512-blocks Used Available Capacity Mounted on
                mock@host:/remote 1024 128 896 13% \(escapeDFPath(mountPoint))
                """
            } else if isMounted, dfVisibilityDelayByMountPoint[mountPoint] != nil {
                stdout = """
                Filesystem 512-blocks Used Available Capacity Mounted on
                /dev/disk3s1 1024 128 896 13% /
                """
            } else {
                stdout = ""
            }
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: stdout,
                stderr: "",
                exitCode: (!stdout.isEmpty || isMounted) ? 0 : 1,
                timedOut: false,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        if executable == "/usr/bin/stat", let path = arguments.last {
            materializePendingMounts()
            materializePendingUnmounts()
            if arguments.count >= 2, arguments[0] == "-f", arguments[1] == "%d" {
                let deviceID = filesystemDeviceID(for: path)
                let exists = mountedPoints.contains(path)
                    || alwaysResponsivePaths.contains(path)
                    || FileManager.default.fileExists(atPath: path)
                    || deviceID != "1000"
                return ProcessResult(
                    executable: executable,
                    arguments: arguments,
                    stdout: exists ? deviceID : "",
                    stderr: exists ? "" : "No such file or directory",
                    exitCode: exists ? 0 : 1,
                    timedOut: false,
                    duration: Date().timeIntervalSince(startedAt)
                )
            }
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
            materializePendingMounts()
            materializePendingUnmounts()
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

        if let simulatedTestResult = simulatedTestResult(
            executable: executable,
            arguments: arguments,
            startedAt: startedAt
        ) {
            return simulatedTestResult
        }

        if executable == "/usr/sbin/diskutil" || executable == "/sbin/umount" {
            if let mountPoint = arguments.last {
                pendingMountActivationAtByMountPoint.removeValue(forKey: mountPoint)
                if let settleDelay = unmountVisibilityDelayByMountPoint[mountPoint], settleDelay > 0 {
                    unmountPendingUntilByMountPoint[mountPoint] = Date().addingTimeInterval(settleDelay)
                } else {
                    mountedPoints.remove(mountPoint)
                    mountActivatedAtByMountPoint.removeValue(forKey: mountPoint)
                }
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

    private func simulatedTestResult(
        executable: String,
        arguments: [String],
        startedAt: Date
    ) -> ProcessResult? {
        let probeArguments: [String]
        if executable == "/usr/bin/test" {
            probeArguments = arguments
        } else if executable == "/usr/bin/env", arguments.first == "test" {
            probeArguments = Array(arguments.dropFirst())
        } else {
            return nil
        }

        guard let flag = probeArguments.first,
              let path = probeArguments.last,
              flag != path else {
            return nil
        }

        let exists: Bool
        if flag == "-f" {
            var isDir: ObjCBool = false
            exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
        } else if flag == "-r" {
            exists = FileManager.default.isReadableFile(atPath: path)
        } else {
            exists = FileManager.default.fileExists(atPath: path)
        }
        return ProcessResult(
            executable: executable,
            arguments: arguments,
            stdout: "",
            stderr: exists ? "" : "test: \(path): No such file or directory",
            exitCode: exists ? 0 : 1,
            timedOut: false,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private func escapeDFPath(_ path: String) -> String {
        path.replacingOccurrences(of: " ", with: "\\040")
    }

    private func isDFVisible(for mountPoint: String) -> Bool {
        let requiredDelay = dfVisibilityDelayByMountPoint[mountPoint] ?? 0
        guard requiredDelay > 0 else {
            return true
        }
        let activatedAt = mountActivatedAtByMountPoint[mountPoint] ?? .distantPast
        return Date().timeIntervalSince(activatedAt) >= requiredDelay
    }

    private func filesystemDeviceID(for path: String) -> String {
        if let mountedIndex = mountedPoints.sorted().firstIndex(of: path) {
            return String(2_000 + mountedIndex)
        }
        return "1000"
    }

    private func materializePendingMounts() {
        let now = Date()
        for (mountPoint, deadline) in pendingMountActivationAtByMountPoint where now >= deadline {
            mountedPoints.insert(mountPoint)
            mountActivatedAtByMountPoint[mountPoint] = deadline
            pendingMountActivationAtByMountPoint.removeValue(forKey: mountPoint)
        }
    }

    private func materializePendingUnmounts() {
        let now = Date()
        for (mountPoint, deadline) in unmountPendingUntilByMountPoint where now >= deadline {
            mountedPoints.remove(mountPoint)
            mountActivatedAtByMountPoint.removeValue(forKey: mountPoint)
            unmountPendingUntilByMountPoint.removeValue(forKey: mountPoint)
        }
    }
}
