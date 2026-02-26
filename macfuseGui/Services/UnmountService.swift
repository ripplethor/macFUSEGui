// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Contains async functions; these can suspend and resume without blocking the calling thread.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct UnmountBlockingProcess: Equatable, Sendable {
    let command: String
    let pid: Int32
    let path: String?
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class UnmountService {
    private let runner: ProcessRunning
    private let diagnostics: DiagnosticsService
    private let mountStateParser: MountStateParser
    // Hard cap for a single unmount attempt. We intentionally keep this low so
    // disconnect/connect flows never "hang" for long periods.
    private let totalUnmountTimeout: TimeInterval
    // Keep per-command timeout short so one hung tool cannot consume almost
    // the full unmount budget by itself.
    private let perCommandMaxTimeout: TimeInterval
    private let mountInspectionTimeout: TimeInterval = 1.5
    private let dfFallbackTimeout: TimeInterval = 1.5
    private let psTimeout: TimeInterval = 2
    private let lsofTimeout: TimeInterval = 3

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        runner: ProcessRunning,
        diagnostics: DiagnosticsService,
        mountStateParser: MountStateParser,
        totalUnmountTimeout: TimeInterval = 10,
        perCommandMaxTimeout: TimeInterval = 3
    ) {
        self.runner = runner
        self.diagnostics = diagnostics
        self.mountStateParser = mountStateParser
        self.totalUnmountTimeout = totalUnmountTimeout
        self.perCommandMaxTimeout = perCommandMaxTimeout
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func unmount(mountPoint: String) async throws {
        try throwIfCancelled()
        let normalizedMountPoint = normalizePath(mountPoint)
        let deadline = Date().addingTimeInterval(totalUnmountTimeout)

        guard try await isMounted(normalizedMountPoint, deadline: deadline) else {
            diagnostics.append(level: .info, category: "unmount", message: "Unmount skipped (already unmounted): \(normalizedMountPoint)")
            return
        }

        let mountSource = try await currentMountRecord(for: normalizedMountPoint, deadline: deadline)?.source
        var lastFailures: [String] = []

        for round in 1...4 {
            try throwIfCancelled()
            if Date() >= deadline {
                diagnostics.append(
                    level: .warning,
                    category: "unmount",
                    message: "Unmount attempts timed out for \(normalizedMountPoint) after \(Int(totalUnmountTimeout))s."
                )
                throw AppError.timeout("Unmount attempts timed out for \(normalizedMountPoint) after \(Int(totalUnmountTimeout))s.")
            }

            if try await runUnmountCommandSet(
                mountPoint: normalizedMountPoint,
                failures: &lastFailures,
                deadline: deadline
            ) {
                return
            }

            try await throwIfBusy(
                mountPoint: normalizedMountPoint,
                failures: lastFailures,
                includeGenericFallback: false
            )

            if round == 1 || round == 2 {
                let forceKill = round == 2
                try await terminateSSHFSProcesses(
                    mountPoint: normalizedMountPoint,
                    mountSource: mountSource,
                    forceKill: forceKill
                )
            }

            if Date() >= deadline {
                diagnostics.append(
                    level: .warning,
                    category: "unmount",
                    message: "Unmount attempts timed out for \(normalizedMountPoint) after \(Int(totalUnmountTimeout))s."
                )
                throw AppError.timeout("Unmount attempts timed out for \(normalizedMountPoint) after \(Int(totalUnmountTimeout))s.")
            }

            if try await !isMounted(normalizedMountPoint, deadline: deadline) {
                return
            }

            if round < 4 {
                // Only sleep if we still have time left in the overall unmount budget.
                let remaining = deadline.timeIntervalSinceNow
                if remaining > 0.6 {
                    // Best-effort delay only. Ignore CancellationError here to avoid
                    // surfacing the pause itself as an unmount failure.
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }

        if Date() >= deadline {
            throw AppError.timeout("Unmount attempts timed out for \(normalizedMountPoint) after \(Int(totalUnmountTimeout))s.")
        }

        if try await !isMounted(normalizedMountPoint, deadline: deadline) {
            return
        }

        try await throwIfBusy(
            mountPoint: normalizedMountPoint,
            failures: lastFailures,
            includeGenericFallback: true
        )

        throw AppError.processFailure("Failed to unmount \(normalizedMountPoint).")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// Kept internal for unit tests that validate parsing edge cases.
    internal func parseBlockingProcesses(from output: String) -> [UnmountBlockingProcess] {
        var results: [UnmountBlockingProcess] = []
        var seenPIDs: Set<Int32> = []
        var currentPID: Int32?
        var currentCommand: String?
        var currentPath: String?

        /// Beginner note: This method is one step in the feature workflow for this file.
        func flushCurrent() {
            guard let pid = currentPID,
                  !seenPIDs.contains(pid),
                  let command = currentCommand,
                  !command.isEmpty else {
                return
            }
            seenPIDs.insert(pid)
            results.append(UnmountBlockingProcess(command: command, pid: pid, path: currentPath))
        }

        let lines = output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let isFieldMode = lines.contains { $0.hasPrefix("p") } && lines.contains { $0.hasPrefix("c") }
        guard isFieldMode else {
            return parseBlockingProcessesFromTable(output: output)
        }

        for line in lines {
            if line.hasPrefix("p") {
                flushCurrent()
                let rawPID = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                currentPID = Int32(rawPID)
                currentCommand = nil
                currentPath = nil
                continue
            }

            if line.hasPrefix("c") {
                currentCommand = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if line.hasPrefix("n"), currentPath == nil {
                currentPath = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        flushCurrent()
        return results
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func runUnmountCommandSet(
        mountPoint: String,
        failures: inout [String],
        deadline: Date
    ) async throws -> Bool {
        let commands: [(label: String, executable: String, args: [String])] = [
            ("diskutil unmount", "/usr/sbin/diskutil", ["unmount", mountPoint]),
            ("umount", "/sbin/umount", [mountPoint]),
            ("diskutil unmount force", "/usr/sbin/diskutil", ["unmount", "force", mountPoint]),
            ("umount -f", "/sbin/umount", ["-f", mountPoint])
        ]

        for command in commands {
            try throwIfCancelled()
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                break
            }
            // Don't start another external command if we have no real time left.
            // This prevents a "deadline overrun" where the last command uses a minimum timeout
            // and pushes the whole unmount beyond the total cap.
            if remaining < 0.5 {
                break
            }

            let timeout = min(perCommandMaxTimeout, remaining)
            let result = try await runner.run(
                executable: command.executable,
                arguments: command.args,
                timeout: timeout
            )

            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let failureOutput = stderr.isEmpty ? stdout : stderr

            if result.exitCode == 0 {
                diagnostics.append(level: .info, category: "unmount", message: "\(command.label) succeeded for \(mountPoint)")
                if Date() >= deadline {
                    return false
                }
                if try await !isMounted(mountPoint, deadline: deadline) {
                    return true
                }
                continue
            }

            let detail: String
            if result.timedOut {
                detail = "timed out after \(Int(timeout))s"
            } else {
                detail = failureOutput.isEmpty ? "exit code \(result.exitCode)" : failureOutput
            }
            failures.append("\(command.label): \(detail)")
            diagnostics.append(level: .warning, category: "unmount", message: "\(command.label) failed for \(mountPoint): \(detail)")
        }

        if Date() >= deadline {
            return false
        }

        return try await !isMounted(mountPoint, deadline: deadline)
    }

    /// Beginner note: Centralize "busy" failure handling so in-loop and final-path
    /// behavior remain consistent as parsing/formatting evolves.
    private func throwIfBusy(
        mountPoint: String,
        failures: [String],
        includeGenericFallback: Bool
    ) async throws {
        let mergedFailures = failures.joined(separator: "; ").lowercased()
        guard mergedFailures.contains("resource busy") || mergedFailures.contains("busy") else {
            return
        }

        // Busy-process detection is best-effort. If lsof fails (permissions, timing, or
        // transient state), we may have no blockers and fall back to a generic busy error.
        let blockers = (try? await detectBlockingProcesses(mountPoint: mountPoint)) ?? []
        if !blockers.isEmpty {
            let nonSSHFSBlockers = blockers.filter { !$0.command.lowercased().contains("sshfs") }
            let targetBlockers = nonSSHFSBlockers.isEmpty ? blockers : nonSSHFSBlockers
            let summary = targetBlockers
                .prefix(5)
                .map { "\($0.command)(\($0.pid))" }
                .joined(separator: ", ")
            throw AppError.processFailure(
                "Mount point is busy: \(mountPoint). Blocking processes: \(summary). Close files/windows and retry."
            )
        }

        guard includeGenericFallback else {
            return
        }

        throw AppError.processFailure(
            "Mount point is busy: \(mountPoint). Close Finder windows or files using this mount and retry."
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func terminateSSHFSProcesses(mountPoint: String, mountSource: String?, forceKill: Bool) async throws {
        try throwIfCancelled()
        let signal = forceKill ? "-KILL" : "-TERM"
        let candidates = try await findSSHFSProcessIDs(mountPoint: mountPoint, mountSource: mountSource)
        guard !candidates.isEmpty else {
            return
        }

        diagnostics.append(
            level: .warning,
            category: "unmount",
            message: "Attempting \(signal) on sshfs pid(s) \(candidates.map(String.init).joined(separator: ",")) for \(mountPoint)"
        )

        for pid in candidates {
            try throwIfCancelled()
            _ = try await runner.run(
                executable: "/bin/kill",
                arguments: [signal, String(pid)],
                timeout: 3
            )
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func findSSHFSProcessIDs(mountPoint: String, mountSource: String?) async throws -> [Int32] {
        let result = try await runner.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,command="],
            timeout: psTimeout
        )

        guard result.exitCode == 0 else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = stderr.isEmpty ? stdout : stderr
            diagnostics.append(
                level: .warning,
                category: "unmount",
                message: "ps failed (exit \(result.exitCode)) while finding sshfs pids for \(mountPoint)\(detail.isEmpty ? "" : ": \(detail)")"
            )
            return []
        }

        var mountPointMatchedPIDs: [Int32] = []
        var sourceMatchedPIDs: [Int32] = []
        let expectedSource = mountSource?.trimmingCharacters(in: .whitespacesAndNewlines)

        for rawLine in result.stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let components = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard components.count == 2 else {
                continue
            }

            guard let pid = Int32(String(components[0])), pid > 1 else {
                continue
            }

            let command = String(components[1]).replacingOccurrences(of: "\\040", with: " ")
            let lowerCommand = command.lowercased()
            guard lowerCommand.contains("sshfs") else {
                continue
            }

            let matchesMountPoint = command.contains(mountPoint)
            let matchesSource = expectedSource.map { command.contains($0) } ?? false

            if matchesMountPoint {
                mountPointMatchedPIDs.append(pid)
            } else if matchesSource {
                sourceMatchedPIDs.append(pid)
            }
        }

        if !mountPointMatchedPIDs.isEmpty {
            return Array(Set(mountPointMatchedPIDs)).sorted()
        }
        return Array(Set(sourceMatchedPIDs)).sorted()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func currentMountRecord(for mountPoint: String, deadline: Date? = nil) async throws -> MountRecord? {
        let timeout = try effectiveTimeout(
            base: mountInspectionTimeout,
            deadline: deadline,
            operation: "mount inspection",
            mountPoint: mountPoint
        )
        let result = try await runner.run(
            executable: "/sbin/mount",
            arguments: [],
            timeout: timeout
        )

        guard result.exitCode == 0 else {
            return nil
        }

        let records = mountStateParser.parseMountOutput(result.stdout)
        return mountStateParser.record(forMountPoint: mountPoint, from: records)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func isMounted(_ mountPoint: String, deadline: Date? = nil) async throws -> Bool {
        let mountTimeout = try effectiveTimeout(
            base: mountInspectionTimeout,
            deadline: deadline,
            operation: "mount inspection",
            mountPoint: mountPoint
        )
        let result = try await runner.run(
            executable: "/sbin/mount",
            arguments: [],
            timeout: mountTimeout
        )

        if result.exitCode == 0 {
            let records = mountStateParser.parseMountOutput(result.stdout)
            return mountStateParser.record(forMountPoint: mountPoint, from: records) != nil
        }

        let dfTimeout = try effectiveTimeout(
            base: dfFallbackTimeout,
            deadline: deadline,
            operation: "df fallback inspection",
            mountPoint: mountPoint
        )
        let fallback = try await runner.run(
            executable: "/bin/df",
            arguments: ["-P", mountPoint],
            timeout: dfTimeout
        )

        guard fallback.exitCode == 0, !fallback.timedOut else {
            // Conservative fallback: assume still mounted if we cannot confirm otherwise.
            diagnostics.append(
                level: .warning,
                category: "unmount",
                message: "df fallback could not verify mount state for \(mountPoint) (exit=\(fallback.exitCode), timedOut=\(fallback.timedOut)); assuming mounted."
            )
            return true
        }

        let lines = fallback.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard lines.count >= 2 else {
            // Conservative fallback: assume still mounted if we cannot confirm otherwise.
            diagnostics.append(
                level: .warning,
                category: "unmount",
                message: "df fallback returned incomplete output for \(mountPoint); assuming mounted."
            )
            return true
        }

        let dataLine = lines.last ?? ""
        guard let normalizedMountedField = normalizedDFMountedPath(from: dataLine) else {
            // Conservative fallback: assume still mounted if we cannot confirm otherwise.
            diagnostics.append(
                level: .warning,
                category: "unmount",
                message: "df fallback could not parse mounted path for \(mountPoint); assuming mounted."
            )
            return true
        }

        return normalizedMountedField == mountPoint
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func normalizedDFMountedPath(from line: String) -> String? {
        let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count >= 6 else {
            return nil
        }

        let mountedField = fields.dropFirst(5).joined(separator: " ")
        let decodedMountedField = decodeDFEscapedPath(mountedField)
        return URL(fileURLWithPath: decodedMountedField).standardizedFileURL.path
    }

    private func decodeDFEscapedPath(_ value: String) -> String {
        value.replacingOccurrences(of: "\\040", with: " ")
    }

    /// Beginner note: This method clamps per-command timeouts to the remaining
    /// time in the overall unmount deadline, so nested probes cannot overrun.
    private func effectiveTimeout(
        base: TimeInterval,
        deadline: Date?,
        operation: String,
        mountPoint: String
    ) throws -> TimeInterval {
        guard let deadline else {
            return base
        }

        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            throw AppError.timeout("\(operation.capitalized) timed out for \(mountPoint).")
        }

        return min(base, remaining)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    private func throwIfCancelled() throws {
        if Task.isCancelled {
            throw AppError.timeout("Unmount operation cancelled.")
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    private func detectBlockingProcesses(mountPoint: String) async throws -> [UnmountBlockingProcess] {
        let result = try await runner.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-n", "-w", "-Fpcn", "+D", mountPoint],
            timeout: lsofTimeout
        )

        if result.timedOut {
            diagnostics.append(level: .warning, category: "unmount", message: "lsof timed out while checking busy blockers for \(mountPoint)")
            return []
        }

        let combined = [result.stdout, result.stderr]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")

        if result.exitCode != 0 {
            let detail = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            if !detail.isEmpty {
                diagnostics.append(level: .warning, category: "unmount", message: "lsof failed for \(mountPoint): \(detail)")
            }
            return []
        }

        let blockers = parseBlockingProcesses(from: combined)
        if !blockers.isEmpty {
            let detail = blockers.map { "\($0.command)(\($0.pid)) \($0.path ?? "")" }.joined(separator: " | ")
            diagnostics.append(level: .info, category: "unmount", message: "Busy blockers for \(mountPoint): \(detail)")
        }
        return blockers
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func parseBlockingProcessesFromTable(output: String) -> [UnmountBlockingProcess] {
        var blockers: [UnmountBlockingProcess] = []
        var seen: Set<Int32> = []

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.lowercased().hasPrefix("command ") {
                continue
            }

            let columns = line.split(whereSeparator: { $0.isWhitespace })
            guard columns.count >= 2 else {
                continue
            }

            let command = String(columns[0])
            guard let pid = Int32(columns[1]), !seen.contains(pid) else {
                continue
            }

            seen.insert(pid)
            // Table mode usually includes a trailing path column; field mode can be nil.
            let path = columns.last.map(String.init)
            blockers.append(UnmountBlockingProcess(command: command, pid: pid, path: path))
        }

        return blockers
    }
}
