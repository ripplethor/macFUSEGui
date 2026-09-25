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
final class UnmountServiceTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    func testParseBlockingProcessesFromFieldModeOutput() {
        let service = makeService()
        let output = """
        p123
        cFinder
        n/Users/philip/MACFUSE-REMOTES/SouthAfrica
        p456
        ccode
        n/Users/philip/MACFUSE-REMOTES/SouthAfrica/index.js
        """

        let blockers = service.parseBlockingProcesses(from: output)
        XCTAssertEqual(blockers.count, 2)
        XCTAssertEqual(blockers[0], UnmountBlockingProcess(command: "Finder", pid: 123, path: "/Users/philip/MACFUSE-REMOTES/SouthAfrica"))
        XCTAssertEqual(blockers[1], UnmountBlockingProcess(command: "code", pid: 456, path: "/Users/philip/MACFUSE-REMOTES/SouthAfrica/index.js"))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testParseBlockingProcessesFromTableOutput() {
        let service = makeService()
        let output = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        Finder    321 philip cwd    DIR    1,4      96    2 /Users/philip/MACFUSE-REMOTES/SouthAfrica
        code      654 philip txt    REG    1,4    2048    3 /Users/philip/MACFUSE-REMOTES/SouthAfrica/app.js
        """

        let blockers = service.parseBlockingProcesses(from: output)
        XCTAssertEqual(blockers.count, 2)
        XCTAssertEqual(blockers[0], UnmountBlockingProcess(command: "Finder", pid: 321, path: "/Users/philip/MACFUSE-REMOTES/SouthAfrica"))
        XCTAssertEqual(blockers[1], UnmountBlockingProcess(command: "code", pid: 654, path: "/Users/philip/MACFUSE-REMOTES/SouthAfrica/app.js"))
    }

    /// Beginner note: df fallback parsing must preserve mount points containing spaces.
    /// This verifies unmount is attempted instead of being skipped as "already unmounted."
    func testUnmountUsesDFFallbackForMountPointWithSpaces() async throws {
        let mountPoint = "/tmp/macfusegui-tests/space mount"
        let runner = FakeDFFallbackUnmountRunner(mountedPoints: [mountPoint])
        let service = UnmountService(
            runner: runner,
            diagnostics: DiagnosticsService(),
            mountStateParser: MountStateParser()
        )

        try await service.unmount(mountPoint: mountPoint)

        let didAttemptUnmount = await runner.didAttemptUnmount(for: mountPoint)
        XCTAssertTrue(didAttemptUnmount)
    }

    /// Beginner note: Healthy targeted df probes should avoid waiting on slow global mount enumeration.
    func testUnmountPrefersFastDFProbeBeforeGlobalMountInspection() async throws {
        let mountPoint = "/tmp/macfusegui-tests/slow-mount-enumeration"
        let runner = FakeDFFallbackUnmountRunner(
            mountedPoints: [mountPoint],
            mountDelay: 3.2
        )
        let service = UnmountService(
            runner: runner,
            diagnostics: DiagnosticsService(),
            mountStateParser: MountStateParser()
        )

        let startedAt = Date()
        try await service.unmount(mountPoint: mountPoint)
        let elapsed = Date().timeIntervalSince(startedAt)

        let didAttemptUnmount = await runner.didAttemptUnmount(for: mountPoint)
        XCTAssertTrue(didAttemptUnmount)
        XCTAssertLessThan(elapsed, 1.0, "Unmount should stay on the targeted df path when it can confirm state.")
    }

    func testBusyBlockerProbeUsesNonRecursiveLsofOptions() async throws {
        let mountPoint = "/tmp/macfusegui-tests/busy-lsof-probe"
        let runner = BusyUnmountRunner(mountPoint: mountPoint)
        let service = UnmountService(
            runner: runner,
            diagnostics: DiagnosticsService(),
            mountStateParser: MountStateParser()
        )

        do {
            try await service.unmount(mountPoint: mountPoint)
            XCTFail("Expected busy unmount to fail.")
        } catch {
            let lsofInvocations = await runner.lsofInvocations()
            XCTAssertFalse(lsofInvocations.isEmpty)
            XCTAssertTrue(lsofInvocations.allSatisfy { $0.contains("-b") })
            XCTAssertTrue(lsofInvocations.allSatisfy { $0.contains("+d") })
            XCTAssertTrue(lsofInvocations.allSatisfy { !$0.contains("+D") })
        }
    }

    /// Beginner note: Regression for the red-team finding. Killing sshfs during a stuck unmount
    /// must only target this mount, not siblings whose paths merely start with the same text.
    func testStuckUnmountOnlyKillsThisMountsSSHFS() async throws {
        let mountPoint = "/tmp/macfusegui-tests/WPSites"
        let runner = StuckUnmountRunner(
            mountPoint: mountPoint,
            mountSource: "root@10.0.0.12:/home/",
            psListing: """
              301 /opt/homebrew/bin/sshfs -f -p 22 root@10.0.0.12:/home/ /tmp/macfusegui-tests/WPSites
              302 /opt/homebrew/bin/sshfs -f -p 22 root@10.0.0.12:/home/site/ /tmp/macfusegui-tests/Site
              303 /opt/homebrew/bin/sshfs -f -p 22 root@10.0.0.12:/home/copy/ /tmp/macfusegui-tests/WPSites2
            """
        )
        let service = UnmountService(
            runner: runner,
            diagnostics: DiagnosticsService(),
            mountStateParser: MountStateParser()
        )

        _ = try? await service.unmount(mountPoint: mountPoint)

        let killed = await runner.killedPIDs()
        XCTAssertEqual(killed, [301], "Only this mount's sshfs may be signalled; got \(killed)")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func makeService() -> UnmountService {
        UnmountService(
            runner: ProcessRunner(),
            diagnostics: DiagnosticsService(),
            mountStateParser: MountStateParser()
        )
    }
}

private actor FakeDFFallbackUnmountRunner: ProcessRunning {
    private var mountedPoints: Set<String>
    private var unmountAttempts: Set<String> = []
    private let mountDelay: TimeInterval

    init(mountedPoints: Set<String>, mountDelay: TimeInterval = 0) {
        self.mountedPoints = mountedPoints
        self.mountDelay = mountDelay
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        standardInput: String?
    ) async throws -> ProcessResult {
        let start = Date()

        if executable == "/sbin/mount" {
            if mountDelay > 0 {
                let boundedDelay = min(mountDelay, timeout + 0.05)
                try? await Task.sleep(nanoseconds: UInt64(boundedDelay * 1_000_000_000))
            }
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "mount command unavailable",
                exitCode: 1,
                timedOut: mountDelay > timeout,
                duration: Date().timeIntervalSince(start)
            )
        }

        if executable == "/bin/df", let mountPoint = arguments.last {
            let isMounted = mountedPoints.contains(mountPoint)
            let mountedField: String
            if isMounted {
                mountedField = escapeDFPath(mountPoint)
            } else {
                mountedField = escapeDFPath(URL(fileURLWithPath: mountPoint).deletingLastPathComponent().path)
            }
            let stdout = """
            Filesystem 512-blocks Used Available Capacity Mounted on
            mock@host:/remote 1024 128 896 13% \(mountedField)
            """

            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: stdout,
                stderr: "",
                exitCode: 0,
                timedOut: false,
                duration: Date().timeIntervalSince(start)
            )
        }

        if (executable == "/usr/sbin/diskutil" || executable == "/sbin/umount"),
           let mountPoint = arguments.last {
            unmountAttempts.insert(mountPoint)
            mountedPoints.remove(mountPoint)
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "",
                exitCode: 0,
                timedOut: false,
                duration: Date().timeIntervalSince(start)
            )
        }

        return ProcessResult(
            executable: executable,
            arguments: arguments,
            stdout: "",
            stderr: "",
            exitCode: 0,
            timedOut: false,
            duration: Date().timeIntervalSince(start)
        )
    }

    func didAttemptUnmount(for mountPoint: String) -> Bool {
        unmountAttempts.contains(mountPoint)
    }

    private func escapeDFPath(_ path: String) -> String {
        path.replacingOccurrences(of: " ", with: "\\040")
    }
}

private actor BusyUnmountRunner: ProcessRunning {
    private let mountPoint: String
    private var recordedLsofArguments: [[String]] = []

    init(mountPoint: String) {
        self.mountPoint = mountPoint
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        standardInput: String?
    ) async throws -> ProcessResult {
        let start = Date()

        if executable == "/bin/df" {
            let stdout = """
            Filesystem 512-blocks Used Available Capacity Mounted on
            mock@host:/remote 1024 128 896 13% \(mountPoint)
            """
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: stdout,
                stderr: "",
                exitCode: 0,
                timedOut: false,
                duration: Date().timeIntervalSince(start)
            )
        }

        if executable == "/usr/sbin/diskutil" || executable == "/sbin/umount" {
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "resource busy",
                exitCode: 1,
                timedOut: false,
                duration: Date().timeIntervalSince(start)
            )
        }

        if executable == "/usr/sbin/lsof" {
            recordedLsofArguments.append(arguments)
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "",
                exitCode: 0,
                timedOut: false,
                duration: Date().timeIntervalSince(start)
            )
        }

        if executable == "/bin/ps" || executable == "/bin/kill" {
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "",
                exitCode: 0,
                timedOut: false,
                duration: Date().timeIntervalSince(start)
            )
        }

        return ProcessResult(
            executable: executable,
            arguments: arguments,
            stdout: "",
            stderr: "",
            exitCode: 0,
            timedOut: false,
            duration: Date().timeIntervalSince(start)
        )
    }

    func lsofInvocations() -> [[String]] {
        recordedLsofArguments
    }
}

/// Beginner note: A mount that never unmounts (non-busy failure), with a fixed `ps` listing.
private actor StuckUnmountRunner: ProcessRunning {
    private let mountPoint: String
    private let mountSource: String
    private let psListing: String
    private var killed: [Int32] = []

    init(mountPoint: String, mountSource: String, psListing: String) {
        self.mountPoint = mountPoint
        self.mountSource = mountSource
        self.psListing = psListing
    }

    func killedPIDs() -> [Int32] {
        Array(Set(killed)).sorted()
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        standardInput: String?
    ) async throws -> ProcessResult {
        var stdout = ""
        var stderr = ""
        var exitCode: Int32 = 0
        switch executable {
        case "/bin/df":
            stdout = """
            Filesystem 512-blocks Used Available Capacity Mounted on
            \(mountSource) 1024 128 896 13% \(mountPoint)
            """
        case "/sbin/mount":
            stdout = "\(mountSource) on \(mountPoint) (macfuse, nodev, nosuid, synchronous)"
        case "/usr/sbin/diskutil", "/sbin/umount":
            stderr = "Unmount failed: Operation not permitted"
            exitCode = 1
        case "/bin/ps":
            stdout = psListing
        case "/bin/kill":
            if let pid = arguments.last.flatMap({ Int32($0) }) {
                killed.append(pid)
            }
        default:
            break
        }
        return ProcessResult(
            executable: executable,
            arguments: arguments,
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            timedOut: false,
            duration: 0
        )
    }
}
