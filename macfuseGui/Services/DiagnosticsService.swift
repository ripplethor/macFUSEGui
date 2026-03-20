// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation
import os

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
enum DiagnosticLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct DiagnosticEntry: Sendable {
    let timestamp: Date
    let level: DiagnosticLevel
    let category: String
    let message: String
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class DiagnosticsService {
    private static let snapshotFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let snapshotFormatterLock = NSLock()

    private let logger = Logger(subsystem: "com.visualweb.macfusegui", category: "app")
    private let queue = DispatchQueue(label: "com.visualweb.macfusegui.diagnostics")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let maxEntries: Int
    private let redactionService: RedactionService
    private var entries: [DiagnosticEntry] = []

    /// Beginner note: Initializers create valid state before any other method is used.
    init(maxEntries: Int = 400, redactionService: RedactionService = RedactionService()) {
        self.maxEntries = maxEntries
        self.redactionService = redactionService
        queue.setSpecific(key: queueKey, value: 1)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func append(level: DiagnosticLevel, category: String, message: String, secrets: [String] = []) {
        let sanitized = sanitizeSingleLine(redactionService.redact(message, secrets: secrets))
        let entry = DiagnosticEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: sanitized
        )

        withEntriesLock {
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst()
            }
        }

        switch level {
        case .debug:
            logger.debug("[\(category, privacy: .public)] \(sanitized, privacy: .private(mask: .hash))")
        case .info:
            logger.info("[\(category, privacy: .public)] \(sanitized, privacy: .private(mask: .hash))")
        case .warning:
            logger.warning("[\(category, privacy: .public)] \(sanitized, privacy: .private(mask: .hash))")
        case .error:
            logger.error("[\(category, privacy: .public)] \(sanitized, privacy: .private(mask: .hash))")
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func snapshot(
        remotes: [RemoteConfig],
        statuses: [UUID: RemoteStatus],
        dependency: DependencyStatus?,
        browserSessions: String? = nil,
        operations: String? = nil,
        mountProbes: String? = nil,
        secrets: [String] = []
    ) -> String {
        var contextualSecrets = secrets
        contextualSecrets.append(contentsOf: remotes.map(\.username))
        contextualSecrets.append(contentsOf: remotes.compactMap(\.privateKeyPath))
        contextualSecrets = contextualSecrets.filter { !$0.isEmpty }

        let formatter = Self.snapshotFormatter
        var lines: [String] = []
        lines.append(redactedLine("macfuseGui diagnostics", secrets: contextualSecrets))
        lines.append(redactedLine("Generated: \(Self.withFormatterLock { formatter.string(from: Date()) })", secrets: contextualSecrets))
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        if let dependency {
            lines.append("Dependencies ready: \(dependency.isReady)")
            lines.append(redactedLine("sshfs path: \(dependency.sshfsPath ?? "not found")", secrets: contextualSecrets))
            if let backend = dependency.sshfsBackend {
                lines.append("sshfs backend source: \(backend.source.displayName)")
                if let overridePath = backend.configuredOverridePath, !overridePath.isEmpty {
                    lines.append(redactedLine("sshfs override path: \(overridePath)", secrets: contextualSecrets))
                }
            }
            if !dependency.issues.isEmpty {
                lines.append("Dependency issues:")
                dependency.issues.forEach { issue in
                    lines.append(redactedLine("- \(issue.userFacingMessage)", secrets: contextualSecrets))
                }
            }
        }

        lines.append("Remotes:")
        if remotes.isEmpty {
            lines.append("- none")
        } else {
            for remote in remotes {
                let status = statuses[remote.id] ?? .initial
                let errorText = redactionService.redact(status.lastError ?? "", secrets: contextualSecrets)
                lines.append(redactedLine("- \(remote.displayName) [\(remote.host):\(remote.port)] status=\(status.state.rawValue) mount=\(status.mountedPath ?? "-") error=\(errorText)", secrets: contextualSecrets))
            }
        }

        lines.append("Mount Probes:")
        if let mountProbes, !mountProbes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let redacted = redactionService.redact(mountProbes, secrets: contextualSecrets)
            lines.append(contentsOf: redacted.split(separator: "\n", omittingEmptySubsequences: false).map { redactedLine(String($0), secrets: contextualSecrets) })
        } else {
            lines.append("- none")
        }

        lines.append("Recent logs:")
        let captured = withEntriesLock { entries }
        if captured.isEmpty {
            lines.append("- none")
        } else {
            for entry in captured.suffix(200) {
                let timestamp = Self.withFormatterLock { formatter.string(from: entry.timestamp) }
                lines.append(redactedLine("- \(timestamp) [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)", secrets: contextualSecrets))
            }
        }

        lines.append("Operations:")
        if let operations, !operations.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let redacted = redactionService.redact(operations, secrets: contextualSecrets)
            lines.append(contentsOf: redacted.split(separator: "\n", omittingEmptySubsequences: false).map { redactedLine(String($0), secrets: contextualSecrets) })
        } else {
            lines.append("- none")
        }

        lines.append("Browser Sessions:")
        if let browserSessions, !browserSessions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let redacted = redactionService.redact(browserSessions, secrets: contextualSecrets)
            lines.append(contentsOf: redacted.split(separator: "\n", omittingEmptySubsequences: false).map { redactedLine(String($0), secrets: contextualSecrets) })
        } else {
            lines.append("- none")
        }

        return lines.joined(separator: "\n")
    }

    private func withEntriesLock<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return body()
        }
        return queue.sync(execute: body)
    }

    private static func withFormatterLock<T>(_ body: () -> T) -> T {
        snapshotFormatterLock.lock()
        defer { snapshotFormatterLock.unlock() }
        return body()
    }

    private func redactedLine(_ value: String, secrets: [String]) -> String {
        sanitizeSingleLine(redactionService.redact(value, secrets: secrets))
    }

    private func sanitizeSingleLine(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
    }
}
