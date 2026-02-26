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

    init(mountedPoints: Set<String>) {
        self.mountedPoints = mountedPoints
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
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "mount command unavailable",
                exitCode: 1,
                timedOut: false,
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
