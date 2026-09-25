// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Contains async functions; these can suspend and resume without blocking the calling thread.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation
import Darwin

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct ProcessResult: Sendable {
    let executable: String
    let arguments: [String]
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let timedOut: Bool
    let duration: TimeInterval
}

/// Beginner note: Exit details for a process started with `launchDetached`.
struct DetachedProcessExit: Sendable {
    let exitCode: Int32
    /// Combined stdout + stderr captured while the process ran.
    let output: String
}

/// Beginner note: Handle for a long-running child that may outlive the app, such as a
/// foreground `sshfs -f` that keeps serving its mount after connect returns.
protocol DetachedProcess: AnyObject, Sendable {
    /// Returns nil while the process is still running. Never blocks.
    func pollExit() async -> DetachedProcessExit?
    /// Output captured so far, for diagnostics while the process is still running.
    func capturedOutput() async -> String
    /// Stops the process and its process group (SIGTERM, then SIGKILL) and reaps it.
    func terminate() async
    /// Stops tracking a process that should keep running. It is still reaped when it exits.
    func release() async
}

/// Beginner note: This protocol defines the minimum process execution behavior used by services.
/// Using a protocol lets tests inject a fake runner without launching real system processes.
protocol ProcessRunning {
    /// Environment merge semantics: implementation starts from the current process
    /// environment and then applies `environment` values as overrides by key.
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        standardInput: String?
    ) async throws -> ProcessResult

    /// Starts a process without waiting for it to exit. Same environment merge semantics as `run`.
    func launchDetached(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> DetachedProcess
}

extension ProcessRunning {
    /// Beginner note: This overload keeps call sites concise by providing common defaults.
    /// Implementers still only need to implement the full method signature above.
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval = 30,
        standardInput: String? = nil
    ) async throws -> ProcessResult {
        try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            standardInput: standardInput
        )
    }

    /// Beginner note: Fallback for runners that cannot detach (for example test fakes).
    /// The command runs to completion in a task and the handle reports its exit once `run` returns.
    func launchDetached(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> DetachedProcess {
        RunToCompletionDetachedProcess(
            runner: self,
            executable: executable,
            arguments: arguments,
            environment: environment
        )
    }
}

/// Beginner note: Adapts `ProcessRunning.run` to the `DetachedProcess` interface.
// @unchecked Sendable is safe here because mutable state is behind `lock`.
final class RunToCompletionDetachedProcess: DetachedProcess, @unchecked Sendable {
    // Long enough that the caller's own deadline always decides when to give up.
    private static let runTimeout: TimeInterval = 3_600

    private let lock = NSLock()
    private var outcome: Result<ProcessResult, Error>?
    private var task: Task<Void, Never>?

    init(runner: ProcessRunning, executable: String, arguments: [String], environment: [String: String]) {
        task = Task { [weak self] in
            let outcome: Result<ProcessResult, Error>
            do {
                outcome = .success(
                    try await runner.run(
                        executable: executable,
                        arguments: arguments,
                        environment: environment,
                        timeout: Self.runTimeout,
                        standardInput: nil
                    )
                )
            } catch {
                outcome = .failure(error)
            }
            self?.finish(outcome)
        }
    }

    private func finish(_ outcome: Result<ProcessResult, Error>) {
        lock.lock()
        self.outcome = outcome
        lock.unlock()
    }

    func pollExit() async -> DetachedProcessExit? {
        lock.lock()
        let outcome = self.outcome
        lock.unlock()

        switch outcome {
        case .none:
            return nil
        case .success(let result):
            let output = [result.stderr, result.stdout]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return DetachedProcessExit(exitCode: result.timedOut ? -1 : result.exitCode, output: output)
        case .failure(let error):
            return DetachedProcessExit(exitCode: -1, output: error.localizedDescription)
        }
    }

    func capturedOutput() async -> String {
        await pollExit()?.output ?? ""
    }

    func terminate() async {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
        await task?.value
    }

    func release() async {}
}

/// Beginner note: A child started with `posix_spawn` in its own session (`POSIX_SPAWN_SETSID`).
/// Like a self-daemonized sshfs, it keeps running after the app quits and is outside the app's
/// process group, so launchd's job cleanup does not kill it. stdout/stderr go to a private log file.
// @unchecked Sendable is safe here because mutable state is behind `lock`.
final class SpawnedDetachedProcess: DetachedProcess, @unchecked Sendable {
    private static let maxCapturedOutputBytes = 65_536

    let pid: pid_t
    private let logURL: URL
    private let lock = NSLock()
    private var exitCode: Int32?
    private var released = false
    private var logRemoved = false

    init(pid: pid_t, logURL: URL) {
        self.pid = pid
        self.logURL = logURL
    }

    func pollExit() async -> DetachedProcessExit? {
        guard let exitCode = reapIfExited() else {
            return nil
        }
        let output = readLog()
        removeLog()
        return DetachedProcessExit(exitCode: exitCode, output: output)
    }

    func capturedOutput() async -> String {
        readLog()
    }

    func terminate() async {
        // Run detached so a cancelled caller still waits out the TERM grace period.
        await Task.detached(priority: .userInitiated) { [self] in
            if reapIfExited() == nil {
                sendSignal(SIGTERM)
                await waitForExit(seconds: 0.6)
            }
            if reapIfExited() == nil {
                sendSignal(SIGKILL)
                await waitForExit(seconds: 0.6)
            }
            removeLog()
        }.value
    }

    func release() async {
        lock.lock()
        let alreadyHandled = released || exitCode != nil
        released = true
        lock.unlock()

        // The child keeps its descriptor to the unlinked log, so nothing accumulates on disk.
        removeLog()
        if !alreadyHandled {
            DetachedProcessReaper.shared.watch(pid: pid)
        }
    }

    /// Returns the exit code once the child has exited, reaping it on first observation.
    private func reapIfExited() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        if let exitCode {
            return exitCode
        }

        switch Self.exitState(of: pid) {
        case .running:
            return nil
        case .alreadyReaped:
            exitCode = -1
            return exitCode
        case .exitedUnreaped:
            break
        }
        // A failed sshfs can leave its mount_macfuse helper behind, blocking the mount point
        // for the next attempt. Clear the group while the unreaped leader still pins its id.
        _ = kill(-pid, SIGKILL)

        var status: Int32 = 0
        var result: pid_t
        repeat {
            result = waitpid(pid, &status, 0)
        } while result == -1 && errno == EINTR
        exitCode = result == pid ? Self.decodedExitCode(status) : -1
        return exitCode
    }

    enum ExitState {
        case running
        /// Exited; still a zombie, so its pid and process-group id cannot be reused yet.
        case exitedUnreaped
        /// Reaped elsewhere; its ids may already belong to another process, so never signal it.
        case alreadyReaped
    }

    /// Checks for exit without reaping (`WNOWAIT`).
    static func exitState(of pid: pid_t) -> ExitState {
        var info = siginfo_t()
        var result: Int32
        repeat {
            result = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
        } while result == -1 && errno == EINTR
        if result == -1 {
            return errno == ECHILD ? .alreadyReaped : .running
        }
        return info.si_pid == pid ? .exitedUnreaped : .running
    }

    private func sendSignal(_ signal: Int32) {
        // Hold the lock so reaping cannot happen between the check and kill(): after reaping,
        // the pid could belong to an unrelated process.
        lock.lock()
        defer { lock.unlock() }
        guard exitCode == nil, pid > 1 else {
            return
        }
        // The child leads its own session and process group, so -pid also reaches its ssh child.
        _ = kill(-pid, signal)
        _ = kill(pid, signal)
    }

    private func waitForExit(seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if reapIfExited() != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func readLog() -> String {
        guard let data = try? Data(contentsOf: logURL) else {
            return ""
        }
        let tail = data.count > Self.maxCapturedOutputBytes ? data.suffix(Self.maxCapturedOutputBytes) : data
        return String(decoding: tail, as: UTF8.self)
    }

    private func removeLog() {
        lock.lock()
        let shouldRemove = !logRemoved
        logRemoved = true
        lock.unlock()
        if shouldRemove {
            try? FileManager.default.removeItem(at: logURL)
        }
    }

    static func decodedExitCode(_ status: Int32) -> Int32 {
        let signalNumber = status & 0x7f
        if signalNumber == 0 {
            return (status >> 8) & 0xff
        }
        return 128 + signalNumber
    }
}

/// Beginner note: Reaps released detached children when they exit so they never linger as zombies.
// @unchecked Sendable is safe here because mutable state is behind `lock`.
private final class DetachedProcessReaper: @unchecked Sendable {
    static let shared = DetachedProcessReaper()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.visualweb.macfusegui.processrunner.reaper", qos: .utility)
    private var sources: [pid_t: DispatchSourceProcess] = [:]

    func watch(pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in
            self?.reapIfExited(pid)
        }
        lock.lock()
        sources[pid] = source
        lock.unlock()
        source.resume()
        // The child may have exited before the source was registered; reap it now in that case.
        queue.async { [weak self] in
            self?.reapIfExited(pid)
        }
    }

    private func reapIfExited(_ pid: pid_t) {
        switch SpawnedDetachedProcess.exitState(of: pid) {
        case .running:
            return
        case .exitedUnreaped:
            // Same leftover-helper cleanup as SpawnedDetachedProcess, before the id is released.
            _ = kill(-pid, SIGKILL)
            var status: Int32 = 0
            var result: pid_t
            repeat {
                result = waitpid(pid, &status, 0)
            } while result == -1 && errno == EINTR
        case .alreadyReaped:
            break
        }

        lock.lock()
        let source = sources.removeValue(forKey: pid)
        lock.unlock()
        source?.cancel()
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
// @unchecked Sendable is safe here because all mutable shared state is behind processRegistryLock.
final class ProcessRunner: ProcessRunning, @unchecked Sendable {
    private struct ProcessHandle {
        let pid: Int32
        let processGroupID: Int32?
    }

    private let processRegistryLock = NSLock()
    private let terminationQueue = DispatchQueue(
        label: "com.visualweb.macfusegui.processrunner.termination",
        qos: .userInitiated
    )
    private var runningPIDs: [UUID: ProcessHandle] = [:]
    private var pendingCancellations: Set<UUID> = []
    private var terminatingCommands: Set<UUID> = []

    /// Beginner note: This method is one step in the feature workflow for this file.
    func run(
        executable: String,
        arguments: [String],
        environment: [String: String] = [:],
        timeout: TimeInterval = 30,
        standardInput: String? = nil
    ) async throws -> ProcessResult {
        let commandID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let start = Date()
                        let process = Process()
                        let stdoutPipe = Pipe()
                        let stderrPipe = Pipe()
                        var stdinPipe: Pipe?
                        process.executableURL = URL(fileURLWithPath: executable)
                        process.arguments = arguments
                        var mergedEnvironment = ProcessInfo.processInfo.environment
                        environment.forEach { mergedEnvironment[$0.key] = $0.value }
                        process.environment = mergedEnvironment
                        process.standardOutput = stdoutPipe
                        process.standardError = stderrPipe
                        if standardInput != nil {
                            let pipe = Pipe()
                            stdinPipe = pipe
                            process.standardInput = pipe
                        }

                        var didTimeout = false
                        let terminationSemaphore = DispatchSemaphore(value: 0)

                        var stdoutData = Data()
                        var stderrData = Data()
                        let captureLock = NSLock()
                        var captureHandlersStopped = false
                        var drained = false

                        let stdoutReadHandle = stdoutPipe.fileHandleForReading
                        let stderrReadHandle = stderrPipe.fileHandleForReading

                        /// Beginner note: This method is one step in the feature workflow for this file.
                        func appendBytes(_ chunk: Data, toStdout: Bool) {
                            guard !chunk.isEmpty else { return }
                            if toStdout {
                                stdoutData.append(chunk)
                            } else {
                                stderrData.append(chunk)
                            }
                        }

                        /// Beginner note: This method is one step in the feature workflow for this file.
                        func configureNonBlockingRead(_ handle: FileHandle) {
                            let fd = handle.fileDescriptor
                            let currentFlags = fcntl(fd, F_GETFL)
                            guard currentFlags >= 0, (currentFlags & O_NONBLOCK) == 0 else {
                                return
                            }
                            _ = fcntl(fd, F_SETFL, currentFlags | O_NONBLOCK)
                        }

                        /// Beginner note: This method is one step in the feature workflow for this file.
                        /// It drains currently available bytes without ever calling NSFileHandle.availableData,
                        /// which can raise an Objective-C exception from the fd monitoring queue during teardown.
                        @discardableResult
                        func drainReadableHandle(_ handle: FileHandle, toStdout: Bool) -> Bool {
                            captureLock.lock()
                            defer { captureLock.unlock() }

                            var buffer = [UInt8](repeating: 0, count: 16_384)
                            while true {
                                errno = 0
                                let bytesRead = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
                                if bytesRead > 0 {
                                    let chunk = Data(buffer[0..<Int(bytesRead)])
                                    appendBytes(chunk, toStdout: toStdout)
                                    continue
                                }
                                if bytesRead == 0 {
                                    return true
                                }
                                if errno == EINTR {
                                    continue
                                }
                                if errno == EAGAIN || errno == EWOULDBLOCK {
                                    return false
                                }
                                if errno == EBADF {
                                    return true
                                }
                                return false
                            }
                        }

                        /// Beginner note: This method is one step in the feature workflow for this file.
                        func stopCaptureHandlers() {
                            captureLock.lock()
                            if captureHandlersStopped {
                                captureLock.unlock()
                                return
                            }
                            captureHandlersStopped = true
                            captureLock.unlock()

                            stdoutReadHandle.readabilityHandler = nil
                            stderrReadHandle.readabilityHandler = nil
                        }

                        /// Beginner note: This method is one step in the feature workflow for this file.
                        func drainRemainingOutputOnceNonBlocking() {
                            captureLock.lock()
                            if drained {
                                captureLock.unlock()
                                return
                            }
                            drained = true
                            captureLock.unlock()

                            drainReadableHandle(stdoutReadHandle, toStdout: true)
                            drainReadableHandle(stderrReadHandle, toStdout: false)
                        }

                        configureNonBlockingRead(stdoutReadHandle)
                        configureNonBlockingRead(stderrReadHandle)

                        stdoutReadHandle.readabilityHandler = { handle in
                            if drainReadableHandle(handle, toStdout: true) {
                                handle.readabilityHandler = nil
                            }
                        }

                        stderrReadHandle.readabilityHandler = { handle in
                            if drainReadableHandle(handle, toStdout: false) {
                                handle.readabilityHandler = nil
                            }
                        }

                        process.terminationHandler = { _ in
                            terminationSemaphore.signal()
                        }

                        try process.run()
                        let pid = process.processIdentifier
                        // Best effort only: Process does not provide pre-exec hooks to set process group
                        // before exec, so group assignment can race for very short-lived children.
                        var processGroupID: Int32?
                        if setpgid(pid, pid) == 0 {
                            processGroupID = pid
                        }
                        self.registerRunningProcess(
                            commandID: commandID,
                            pid: pid,
                            processGroupID: processGroupID
                        )

                        if let standardInput,
                           let inputData = standardInput.data(using: .utf8),
                           let stdinPipe {
                            stdinPipe.fileHandleForWriting.write(inputData)
                            try? stdinPipe.fileHandleForWriting.close()
                        }

                        let waitResult = terminationSemaphore.wait(timeout: .now() + timeout)
                        if waitResult == .timedOut {
                            didTimeout = true

                            // Shut down async monitoring before terminate/SIGKILL so teardown only uses
                            // explicit non-blocking reads and never races through NSFileHandle monitoring.
                            stopCaptureHandlers()
                            let timeoutHandle = self.beginTermination(
                                commandID: commandID,
                                fallback: ProcessHandle(pid: pid, processGroupID: processGroupID)
                            )

                            if process.isRunning, let timeoutHandle {
                                self.sendTerminateSignal(to: timeoutHandle)
                                if timeoutHandle.pid == process.processIdentifier {
                                    process.terminate()
                                }
                            }

                            // Keep timeout teardown short so caller-level watchdog budgets stay meaningful.
                            let graceResult = terminationSemaphore.wait(timeout: .now() + 0.6)
                            if graceResult == .timedOut, process.isRunning, let timeoutHandle {
                                self.sendKillSignal(to: timeoutHandle)
                                if timeoutHandle.pid == process.processIdentifier {
                                    _ = kill(process.processIdentifier, SIGKILL)
                                }
                                _ = terminationSemaphore.wait(timeout: .now() + 0.6)
                            }
                        }

                        stopCaptureHandlers()
                        drainRemainingOutputOnceNonBlocking()

                        captureLock.lock()
                        let finalStdout = stdoutData
                        let finalStderr = stderrData
                        captureLock.unlock()

                        let stdout = String(data: finalStdout, encoding: .utf8) ?? ""
                        let stderr = String(data: finalStderr, encoding: .utf8) ?? ""
                        let stillRunning = process.isRunning

                        let result = ProcessResult(
                            executable: executable,
                            arguments: arguments,
                            stdout: stdout,
                            stderr: stderr,
                            exitCode: stillRunning ? -1 : process.terminationStatus,
                            timedOut: didTimeout || stillRunning,
                            duration: Date().timeIntervalSince(start)
                        )
                        self.unregisterRunningProcess(commandID: commandID)
                        continuation.resume(returning: result)
                    } catch {
                        self.unregisterRunningProcess(commandID: commandID)
                        continuation.resume(
                            throwing: AppError.processFailure(
                                L10n.format("Failed to start process: %@", error.localizedDescription)
                            )
                        )
                    }
                }
            }
        } onCancel: {
            self.cancelRunningProcess(commandID: commandID)
        }
    }

    /// Beginner note: Starts a long-running child in its own session with stdin on /dev/null and
    /// stdout/stderr captured to a private log file. The caller owns the returned handle.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func launchDetached(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) async throws -> DetachedProcess {
        let logDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macfuseGui-detached", isDirectory: true)
        try FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let logURL = logDirectory.appendingPathComponent("\(UUID().uuidString).log")

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, logURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&fileActions, STDOUT_FILENO, STDERR_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // SETSID: own session and process group, so the child outlives the app.
        // CLOEXEC_DEFAULT: do not leak app descriptors (for example the singleton lock file).
        // SETSIGDEF/SETSIGMASK: start from default signal handling, as Process does.
        let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        var emptySignalMask = sigset_t()
        sigemptyset(&emptySignalMask)
        posix_spawnattr_setsigmask(&attributes, &emptySignalMask)
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        for signalNumber in Int32(1)..<Int32(32) where signalNumber != SIGKILL && signalNumber != SIGSTOP {
            sigaddset(&defaultSignals, signalNumber)
        }
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)

        var mergedEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { mergedEnvironment[$0.key] = $0.value }
        let argumentStrings: [String] = [executable] + arguments
        let environmentStrings: [String] = mergedEnvironment.map { "\($0.key)=\($0.value)" }
        let argv: [UnsafeMutablePointer<CChar>?] = argumentStrings.map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environmentStrings.map { strdup($0) } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let spawnResult = posix_spawn(&pid, executable, &fileActions, &attributes, argv, envp)
        guard spawnResult == 0 else {
            try? FileManager.default.removeItem(at: logURL)
            throw AppError.processFailure(
                L10n.format("Failed to start process: %@", String(cString: strerror(spawnResult)))
            )
        }
        return SpawnedDetachedProcess(pid: pid, logURL: logURL)
    }

    private func registerRunningProcess(commandID: UUID, pid: Int32, processGroupID: Int32?) {
        processRegistryLock.lock()
        runningPIDs[commandID] = ProcessHandle(pid: pid, processGroupID: processGroupID)
        let cancelImmediately = pendingCancellations.remove(commandID) != nil
        if cancelImmediately {
            terminatingCommands.insert(commandID)
        }
        processRegistryLock.unlock()

        if cancelImmediately {
            let handle = ProcessHandle(pid: pid, processGroupID: processGroupID)
            terminationQueue.async { [weak self] in
                self?.terminateProcess(handle)
            }
        }
    }

    private func unregisterRunningProcess(commandID: UUID) {
        processRegistryLock.lock()
        runningPIDs.removeValue(forKey: commandID)
        pendingCancellations.remove(commandID)
        terminatingCommands.remove(commandID)
        processRegistryLock.unlock()
    }

    private func cancelRunningProcess(commandID: UUID) {
        let handleToTerminate: ProcessHandle?
        processRegistryLock.lock()
        if let processHandle = runningPIDs[commandID] {
            if terminatingCommands.contains(commandID) {
                handleToTerminate = nil
            } else {
                terminatingCommands.insert(commandID)
                handleToTerminate = processHandle
            }
        } else {
            pendingCancellations.insert(commandID)
            handleToTerminate = nil
        }
        processRegistryLock.unlock()

        if let handleToTerminate {
            terminationQueue.async { [weak self] in
                self?.terminateProcess(handleToTerminate)
            }
        }
    }

    private func beginTermination(commandID: UUID, fallback: ProcessHandle? = nil) -> ProcessHandle? {
        processRegistryLock.lock()
        defer { processRegistryLock.unlock() }
        if terminatingCommands.contains(commandID) {
            return nil
        }
        terminatingCommands.insert(commandID)
        if let active = runningPIDs[commandID] {
            return active
        }
        return fallback
    }

    private func sendTerminateSignal(to handle: ProcessHandle) {
        guard handle.pid > 1 else {
            return
        }
        if let processGroupID = handle.processGroupID, processGroupID > 1 {
            _ = kill(-processGroupID, SIGTERM)
        }
        _ = kill(handle.pid, SIGTERM)
    }

    private func sendKillSignal(to handle: ProcessHandle) {
        guard handle.pid > 1 else {
            return
        }
        if let processGroupID = handle.processGroupID, processGroupID > 1 {
            _ = kill(-processGroupID, SIGKILL)
        }
        _ = kill(handle.pid, SIGKILL)
    }

    private func terminateProcess(_ handle: ProcessHandle) {
        sendTerminateSignal(to: handle)
        // By design this is a short blocking grace period in a termination-only path.
        // It gives child processes a chance to exit cleanly before escalating to SIGKILL.
        // This runs on a dedicated queue so cancellation handlers never block cooperative threads.
        usleep(250_000)
        sendKillSignal(to: handle)
    }
}
