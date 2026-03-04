import ServiceManagement
import XCTest
@testable import macfuseGui

@MainActor
final class RemotesViewModelRecoveryTests: XCTestCase {
    func testConnectivityLossCleanupTargetsOnlyDesiredNonDisconnectedRemotes() {
        let connected = makeRemote(name: "Connected", mountPoint: "/tmp/connected")
        let degraded = makeRemote(name: "Degraded", mountPoint: "/tmp/degraded")
        let alreadyDisconnected = makeRemote(name: "Disconnected", mountPoint: "/tmp/disconnected")
        let manualOnly = makeRemote(name: "Manual", mountPoint: "/tmp/manual")

        let targets = RemotesViewModel.connectivityLossCleanupTargets(
            remotes: [connected, degraded, alreadyDisconnected, manualOnly],
            statuses: [
                connected.id: RemoteStatus(state: .connected, mountedPath: connected.localMountPoint, lastError: nil, updatedAt: Date()),
                degraded.id: RemoteStatus(state: .error, mountedPath: nil, lastError: "Detected stale mount.", updatedAt: Date()),
                alreadyDisconnected.id: RemoteStatus(state: .disconnected, mountedPath: nil, lastError: nil, updatedAt: Date()),
                manualOnly.id: RemoteStatus(state: .connected, mountedPath: manualOnly.localMountPoint, lastError: nil, updatedAt: Date())
            ],
            desiredConnections: Set([connected.id, degraded.id, alreadyDisconnected.id])
        )

        XCTAssertEqual(targets.map(\.id), [connected.id, degraded.id])
    }

    func testPeriodicRecoveryCanBypassStaleReachabilityForDisconnectedDesiredRemotes() {
        XCTAssertTrue(
            RemotesViewModel.shouldAllowPeriodicRecoveryDespiteReachabilityFalse(
                networkReachable: false,
                trigger: "periodic",
                hasPendingStartup: false,
                desiredRemoteStates: [.disconnected, .connected],
                secondsSinceLastBypass: 61,
                interval: 60
            )
        )

        XCTAssertFalse(
            RemotesViewModel.shouldAllowPeriodicRecoveryDespiteReachabilityFalse(
                networkReachable: false,
                trigger: "periodic",
                hasPendingStartup: false,
                desiredRemoteStates: [.disconnected],
                secondsSinceLastBypass: 30,
                interval: 60
            )
        )

        XCTAssertFalse(
            RemotesViewModel.shouldAllowPeriodicRecoveryDespiteReachabilityFalse(
                networkReachable: false,
                trigger: "wake",
                hasPendingStartup: false,
                desiredRemoteStates: [.disconnected],
                secondsSinceLastBypass: 61,
                interval: 60
            )
        )
    }

    func testPerformFastRecoveryCleanupForceUnmountsAndMarksRemoteDisconnected() async {
        let runner = RecordingCleanupRunner()
        let diagnostics = DiagnosticsService()
        let parser = MountStateParser()
        let remote = makeRemote(name: "VisualGen", mountPoint: "/tmp/visualgen")

        let mountManager = MountManager(
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

        let viewModel = makeViewModel(
            diagnostics: diagnostics,
            mountManager: mountManager,
            runner: runner
        )

        await viewModel.performFastRecoveryCleanup(
            targets: [remote],
            cancellationReason: "unit-test",
            disconnectedMessage: "Network unavailable. Disconnected to avoid stale mount hangs. Will reconnect when network returns.",
            startMessage: "Test cleanup start",
            completionPrefix: "Test cleanup"
        )

        let status = viewModel.status(for: remote.id)
        XCTAssertEqual(status.state, .disconnected)
        XCTAssertEqual(
            status.lastError,
            "Network unavailable. Disconnected to avoid stale mount hangs. Will reconnect when network returns."
        )

        let commands = await runner.recordedCommands()
        XCTAssertTrue(
            commands.contains { $0.executable == "/bin/ps" && $0.arguments == ["-axo", "pid=,command="] }
        )
        XCTAssertTrue(
            commands.contains { $0.executable == "/usr/sbin/diskutil" && $0.arguments == ["unmount", "force", remote.localMountPoint] }
        )
    }

    private func makeViewModel(
        diagnostics: DiagnosticsService,
        mountManager: MountManager,
        runner: ProcessRunning
    ) -> RemotesViewModel {
        let browserService = RemoteDirectoryBrowserService(
            manager: RemoteBrowserSessionManager(
                transport: NoopBrowserTransport(),
                diagnostics: diagnostics
            ),
            diagnostics: diagnostics
        )

        let launchService = LaunchAtLoginService(
            appService: StubLaunchAtLoginAppService(),
            runner: runner
        )

        return RemotesViewModel(
            remoteStore: InMemoryRemoteStore(),
            keychainService: StubKeychainService(),
            validationService: ValidationService(),
            dependencyChecker: DependencyChecker(),
            mountManager: mountManager,
            remoteDirectoryBrowserService: browserService,
            diagnostics: diagnostics,
            launchAtLoginService: launchService
        )
    }

    private func makeRemote(name: String, mountPoint: String) -> RemoteConfig {
        RemoteConfig(
            displayName: name,
            host: "10.0.0.2",
            port: 22,
            username: "dev",
            authMode: .privateKey,
            privateKeyPath: "/tmp/mock-id",
            remoteDirectory: "/srv",
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

@MainActor
private final class InMemoryRemoteStore: RemoteStore {
    let storageURL = URL(fileURLWithPath: "/tmp/macfusegui-tests/remotes.json")

    func load() throws -> [RemoteConfig] { [] }
    func save(_ remotes: [RemoteConfig]) throws {}
    func upsert(_ remote: RemoteConfig) throws {}
    func delete(id: UUID) throws {}
}

private struct StubKeychainService: KeychainServiceProtocol {
    func savePassword(remoteID: String, password: String) throws {}
    func readPassword(remoteID: String, allowUserInteraction: Bool) throws -> String? { nil }
    func deletePassword(remoteID: String) throws {}
}

@MainActor
private final class StubLaunchAtLoginAppService: LaunchAtLoginAppService {
    var status: SMAppService.Status { .notRegistered }
    func register() throws {}
    func unregister() async throws {}
}

private struct NoopBrowserTransport: BrowserTransport {
    func listDirectories(remote: RemoteConfig, path: String, password: String?) async throws -> BrowserTransportListResult {
        BrowserTransportListResult(
            resolvedPath: path,
            entries: [],
            latencyMs: 1,
            reopenedSession: false
        )
    }

    func ping(remote: RemoteConfig, path: String, password: String?) async throws {}
}

private actor RecordingCleanupRunner: ProcessRunning {
    struct Command: Equatable {
        let executable: String
        let arguments: [String]
    }

    private var commands: [Command] = []

    func run(
        executable: String,
        arguments: [String],
        environment: [String : String],
        timeout: TimeInterval,
        standardInput: String?
    ) async throws -> ProcessResult {
        commands.append(Command(executable: executable, arguments: arguments))

        return ProcessResult(
            executable: executable,
            arguments: arguments,
            stdout: executable == "/bin/ps" ? "" : "",
            stderr: "",
            exitCode: 0,
            timedOut: false,
            duration: 0.01
        )
    }

    func recordedCommands() -> [Command] {
        commands
    }
}
