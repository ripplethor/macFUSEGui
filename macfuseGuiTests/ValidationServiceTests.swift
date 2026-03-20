// BEGINNER FILE GUIDE
// Layer: Automated test layer
// Purpose: This file verifies production behavior and protects against regressions when code changes.
// Called by: Executed by XCTest during xcodebuild test or IDE test runs.
// Calls into: Calls production code and test fixtures with deterministic assertions.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import XCTest
@testable import macfuseGui

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class ValidationServiceTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func testValidationRejectsInvalidFields() throws {
        let service = ValidationService()
        let invalid = RemoteDraft(
            displayName: "",
            host: "bad host with spaces",
            port: 70000,
            username: "",
            authMode: .privateKey,
            privateKeyPath: "/does/not/exist",
            password: "",
            remoteDirectory: "relative/path",
            localMountPoint: "/does/not/exist"
        )

        let errors = service.validateDraft(invalid, hasStoredPassword: false)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.contains(where: { $0.contains("Display name") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("Host/IP") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("Port") }))
        XCTAssertTrue(errors.contains(where: { $0.contains("Remote directory") }))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func testValidationAllowsPasswordModeWithStoredPassword() throws {
        let tmp = FileManager.default.temporaryDirectory
        let mountPath = tmp.path

        let draft = RemoteDraft(
            displayName: "Server",
            host: "example.com",
            port: 22,
            username: "dev",
            authMode: .password,
            privateKeyPath: "",
            password: "",
            remoteDirectory: "/home/dev",
            localMountPoint: mountPath
        )

        let service = ValidationService()
        let errors = service.validateDraft(draft, hasStoredPassword: true)
        XCTAssertTrue(errors.isEmpty)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testValidationAllowsWindowsStyleRemotePath() {
        let draft = RemoteDraft(
            displayName: "Windows Host",
            host: "win-host.local",
            port: 22,
            username: "dev",
            authMode: .password,
            privateKeyPath: "",
            password: "",
            remoteDirectory: "C:/Users/dev",
            localMountPoint: FileManager.default.temporaryDirectory.path
        )

        let service = ValidationService()
        let errors = service.validateDraft(draft, hasStoredPassword: true)
        XCTAssertTrue(errors.isEmpty)
    }

    /// Beginner note: Local mount-point normalization must stay lexical-only so stale
    /// FUSE mounts do not block MainActor validation and recovery conflict checks.
    func testLocalPathNormalizerCollapsesAbsolutePathsLexically() {
        XCTAssertEqual(
            LocalPathNormalizer.normalize("/Users/philip/MACFUSE-REMOTES//server/./share/../mount/"),
            "/Users/philip/MACFUSE-REMOTES/server/mount"
        )
        XCTAssertEqual(
            LocalPathNormalizer.normalize("/tmp/../"),
            "/"
        )
        XCTAssertEqual(
            LocalPathNormalizer.parentPath(of: "/Users/philip/MACFUSE-REMOTES/server/mount"),
            "/Users/philip/MACFUSE-REMOTES/server"
        )
    }

    /// Beginner note: Validation still rejects paths that lexically collapse to root.
    func testValidationRejectsLocalMountPointThatNormalizesToRootLexically() {
        let draft = RemoteDraft(
            displayName: "Rootish Mount",
            host: "example.com",
            port: 22,
            username: "dev",
            authMode: .password,
            privateKeyPath: "",
            password: "secret",
            remoteDirectory: "/home/dev",
            localMountPoint: "/tmp/../"
        )

        let service = ValidationService()
        let errors = service.validateDraft(draft, hasStoredPassword: false)
        XCTAssertTrue(errors.contains("Local mount point cannot be '/'. Choose a subfolder."))
    }

    func testValidationDoesNotProbePrivateKeyFilesystemOnMainActor() {
        let draft = RemoteDraft(
            displayName: "Private Key Remote",
            host: "example.com",
            port: 22,
            username: "dev",
            authMode: .privateKey,
            privateKeyPath: "/Volumes/stale-mount/.ssh/id_ed25519",
            password: "",
            remoteDirectory: "/home/dev",
            localMountPoint: FileManager.default.temporaryDirectory.path
        )

        let service = ValidationService()
        let errors = service.validateDraft(draft, hasStoredPassword: false)
        XCTAssertFalse(errors.contains("Private key file does not exist."))
        XCTAssertFalse(errors.contains("Private key file is not readable."))
        XCTAssertTrue(errors.isEmpty)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testValidationRejectsHostWithControlCharacter() {
        let draft = RemoteDraft(
            displayName: "Host With Control",
            host: "exa\nmple.com",
            port: 22,
            username: "dev",
            authMode: .password,
            privateKeyPath: "",
            password: "secret",
            remoteDirectory: "/home/dev",
            localMountPoint: FileManager.default.temporaryDirectory.path
        )

        let service = ValidationService()
        let errors = service.validateDraft(draft, hasStoredPassword: false)
        XCTAssertTrue(errors.contains("Host/IP contains invalid control characters."))
    }

    /// Beginner note: IPv6 literals must be bracketed because mount command building
    /// uses user@host:path and unbracketed IPv6 is ambiguous.
    func testValidationRejectsBareIPv6HostLiteral() {
        let draft = RemoteDraft(
            displayName: "IPv6 Host",
            host: "2001:db8::1",
            port: 22,
            username: "dev",
            authMode: .password,
            privateKeyPath: "",
            password: "secret",
            remoteDirectory: "/home/dev",
            localMountPoint: FileManager.default.temporaryDirectory.path
        )

        let service = ValidationService()
        let errors = service.validateDraft(draft, hasStoredPassword: false)
        XCTAssertTrue(errors.contains("IPv6 addresses must be wrapped in brackets, for example [::1]."))
    }

    /// Beginner note: Bracketed IPv6 hosts are accepted by validation.
    func testValidationAllowsBracketedIPv6HostLiteral() {
        let draft = RemoteDraft(
            displayName: "IPv6 Host",
            host: "[2001:db8::1]",
            port: 22,
            username: "dev",
            authMode: .password,
            privateKeyPath: "",
            password: "secret",
            remoteDirectory: "/home/dev",
            localMountPoint: FileManager.default.temporaryDirectory.path
        )

        let service = ValidationService()
        let errors = service.validateDraft(draft, hasStoredPassword: false)
        XCTAssertTrue(errors.isEmpty)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testValidationRejectsUnsupportedTildeRemotePathVariants() {
        let draft = RemoteDraft(
            displayName: "Tilde User Path",
            host: "example.com",
            port: 22,
            username: "dev",
            authMode: .password,
            privateKeyPath: "",
            password: "secret",
            remoteDirectory: "~root/projects",
            localMountPoint: FileManager.default.temporaryDirectory.path
        )

        let service = ValidationService()
        let errors = service.validateDraft(draft, hasStoredPassword: false)
        XCTAssertTrue(
            errors.contains("Remote directory must be absolute (for example /home/user or C:/Users/User).")
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRecoveryBackoffIsAggressiveAfterWakeForTransientFailure() {
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 0,
                trigger: "wake",
                lastError: "Connection reset by peer"
            ),
            0
        )
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 1,
                trigger: "wake",
                lastError: "Connection reset by peer"
            ),
            1
        )
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 4,
                trigger: "wake",
                lastError: "Connection reset by peer"
            ),
            8
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRecoveryBackoffIsConservativeForPeriodicNonTransientFailure() {
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 0,
                trigger: "periodic",
                lastError: "sshfs reported success, but mount was not detected."
            ),
            0
        )
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 1,
                trigger: "periodic",
                lastError: "sshfs reported success, but mount was not detected."
            ),
            2
        )
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 2,
                trigger: "periodic",
                lastError: "sshfs reported success, but mount was not detected."
            ),
            5
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRecoveryTransientFailureClassifier() {
        XCTAssertTrue(RemotesViewModel.isTransientReconnectFailureMessage("broken pipe"))
        XCTAssertTrue(RemotesViewModel.isTransientReconnectFailureMessage("operation timed out"))
        XCTAssertFalse(RemotesViewModel.isTransientReconnectFailureMessage("authentication failed"))
        XCTAssertFalse(RemotesViewModel.isTransientReconnectFailureMessage(nil))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRecoveryBackoffCapsAtOneMinute() {
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 999,
                trigger: "periodic",
                lastError: "network is unreachable"
            ),
            60
        )
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 999,
                trigger: "wake",
                lastError: "connection reset"
            ),
            60
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRequiredRecoveryStrikesByTriggerType() {
        XCTAssertEqual(RemotesViewModel.requiredRecoveryStrikes(for: "wake"), 1)
        XCTAssertEqual(RemotesViewModel.requiredRecoveryStrikes(for: "network-restored"), 1)
        XCTAssertEqual(RemotesViewModel.requiredRecoveryStrikes(for: "periodic"), 2)
        XCTAssertEqual(RemotesViewModel.requiredRecoveryStrikes(for: "status-change"), 1)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testNetworkRestoredBackoffStartsFastForTransientFailures() {
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 0,
                trigger: "network-restored",
                lastError: "broken pipe"
            ),
            0
        )
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 1,
                trigger: "network-restored",
                lastError: "broken pipe"
            ),
            1
        )
        XCTAssertEqual(
            RemotesViewModel.reconnectDelaySeconds(
                attempt: 2,
                trigger: "network-restored",
                lastError: "broken pipe"
            ),
            2
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRecoveryBurstDelaysForWakeAndNetworkRestore() {
        XCTAssertEqual(RemotesViewModel.recoveryBurstDelays(for: "wake"), [0, 1, 3, 8])
        XCTAssertEqual(RemotesViewModel.recoveryBurstDelays(for: "network-restored"), [0, 2, 6])
        XCTAssertEqual(RemotesViewModel.recoveryBurstDelays(for: "periodic"), [0])
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testNetworkReachabilityTransitionMapping() {
        XCTAssertEqual(
            RemotesViewModel.networkReachabilityTransition(previousReachable: false, currentReachable: false),
            .unchanged
        )
        XCTAssertEqual(
            RemotesViewModel.networkReachabilityTransition(previousReachable: false, currentReachable: true),
            .becameReachable
        )
        XCTAssertEqual(
            RemotesViewModel.networkReachabilityTransition(previousReachable: true, currentReachable: false),
            .becameUnreachable
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testWatchdogTimeoutMessageSelection() {
        XCTAssertEqual(
            RemotesViewModel.watchdogTimeoutMessage(
                intent: .connect,
                currentState: .connecting,
                disconnectWatchdogTimeout: 10
            ),
            "Connect timed out. Check network/credentials and retry. If the remote server was restarted, disconnect and reconnect to clear stale mount state."
        )
        XCTAssertNil(
            RemotesViewModel.watchdogTimeoutMessage(
                intent: .connect,
                currentState: .connected,
                disconnectWatchdogTimeout: 10
            )
        )
        XCTAssertEqual(
            RemotesViewModel.watchdogTimeoutMessage(
                intent: .disconnect,
                currentState: .disconnecting,
                disconnectWatchdogTimeout: 12
            ),
            "Disconnect timed out after 12s. Close Finder windows, Quick Look previews, or files using the mount, then retry."
        )
        XCTAssertEqual(
            RemotesViewModel.watchdogTimeoutMessage(
                intent: .refresh,
                currentState: .connected,
                disconnectWatchdogTimeout: 10
            ),
            "Status refresh timed out. The mount may be stale (common after server restart). Disconnect and reconnect this remote."
        )
    }

    func testDependencyCheckerPinsResolvedSSHFSBackendAcrossCandidateOrderChanges() throws {
        let fixture = try makeDependencyCheckerFixture()
        defer {
            fixture.cleanup()
        }

        let initial = DependencyChecker(
            userDefaults: fixture.userDefaults,
            fallbackSSHFSPaths: [fixture.firstSSHFS, fixture.secondSSHFS],
            macfuseInstallPath: fixture.macfusePath,
            sshExecutablePath: fixture.sshPath,
            sftpExecutablePath: fixture.sftpPath,
            environmentProvider: { [:] }
        )
        let initialStatus = initial.check()
        XCTAssertTrue(initialStatus.isReady)
        XCTAssertEqual(initialStatus.sshfsPath, fixture.firstSSHFS)

        let reordered = DependencyChecker(
            userDefaults: fixture.userDefaults,
            fallbackSSHFSPaths: [fixture.secondSSHFS, fixture.firstSSHFS],
            macfuseInstallPath: fixture.macfusePath,
            sshExecutablePath: fixture.sshPath,
            sftpExecutablePath: fixture.sftpPath,
            environmentProvider: { [:] }
        )
        let reorderedStatus = reordered.check()
        XCTAssertTrue(reorderedStatus.isReady)
        XCTAssertEqual(reorderedStatus.sshfsPath, fixture.firstSSHFS)
    }

    func testDependencyCheckerInvalidOverrideBlocksFallbackAndSurfacesActionableIssue() throws {
        let fixture = try makeDependencyCheckerFixture()
        defer {
            fixture.cleanup()
        }

        let checker = DependencyChecker(
            userDefaults: fixture.userDefaults,
            fallbackSSHFSPaths: [fixture.firstSSHFS],
            macfuseInstallPath: fixture.macfusePath,
            sshExecutablePath: fixture.sshPath,
            sftpExecutablePath: fixture.sftpPath,
            environmentProvider: { [:] }
        )
        checker.setConfiguredSSHFSOverridePath(fixture.root.appendingPathComponent("missing/sshfs").path)

        let status = checker.check()
        XCTAssertFalse(status.isReady)
        XCTAssertNil(status.sshfsBackend)
        XCTAssertEqual(status.issues.first?.kind, .sshfs)
        XCTAssertTrue(status.userFacingMessage.contains("Clear the override"))
    }

    func testDependencyCheckerClearPinnedBackendAllowsManagedRediscovery() throws {
        let fixture = try makeDependencyCheckerFixture()
        defer {
            fixture.cleanup()
        }

        let checker = DependencyChecker(
            userDefaults: fixture.userDefaults,
            fallbackSSHFSPaths: [fixture.firstSSHFS, fixture.secondSSHFS],
            macfuseInstallPath: fixture.macfusePath,
            sshExecutablePath: fixture.sshPath,
            sftpExecutablePath: fixture.sftpPath,
            environmentProvider: { [:] }
        )
        XCTAssertEqual(checker.check().sshfsPath, fixture.firstSSHFS)

        let reordered = DependencyChecker(
            userDefaults: fixture.userDefaults,
            fallbackSSHFSPaths: [fixture.secondSSHFS, fixture.firstSSHFS],
            macfuseInstallPath: fixture.macfusePath,
            sshExecutablePath: fixture.sshPath,
            sftpExecutablePath: fixture.sftpPath,
            environmentProvider: { [:] }
        )
        XCTAssertEqual(reordered.check().sshfsPath, fixture.firstSSHFS)

        reordered.clearPinnedSSHFSBackend()
        let rediscoveredStatus = reordered.check()
        XCTAssertTrue(rediscoveredStatus.isReady)
        XCTAssertEqual(rediscoveredStatus.sshfsPath, fixture.secondSSHFS)
    }

    private func makeDependencyCheckerFixture() throws -> DependencyCheckerFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macfusegui-tests-dependency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let firstSSHFS = root.appendingPathComponent("opt/homebrew/bin/sshfs").path
        let secondSSHFS = root.appendingPathComponent("usr/local/bin/sshfs").path
        let sshPath = root.appendingPathComponent("usr/bin/ssh").path
        let sftpPath = root.appendingPathComponent("usr/bin/sftp").path
        let macfusePath = root.appendingPathComponent("Library/Filesystems/macfuse.fs").path

        try makeExecutable(atPath: firstSSHFS)
        try makeExecutable(atPath: secondSSHFS)
        try makeExecutable(atPath: sshPath)
        try makeExecutable(atPath: sftpPath)
        try FileManager.default.createDirectory(atPath: macfusePath, withIntermediateDirectories: true)

        let suiteName = "macfuseGuiTests.DependencyChecker.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite for dependency checker tests.")
            throw NSError(domain: "ValidationServiceTests", code: 1)
        }
        userDefaults.removePersistentDomain(forName: suiteName)

        return DependencyCheckerFixture(
            root: root,
            firstSSHFS: firstSSHFS,
            secondSSHFS: secondSSHFS,
            sshPath: sshPath,
            sftpPath: sftpPath,
            macfusePath: macfusePath,
            userDefaults: userDefaults,
            suiteName: suiteName
        )
    }

    private func makeExecutable(atPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private struct DependencyCheckerFixture {
        let root: URL
        let firstSSHFS: String
        let secondSSHFS: String
        let sshPath: String
        let sftpPath: String
        let macfusePath: String
        let userDefaults: UserDefaults
        let suiteName: String

        func cleanup() {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
