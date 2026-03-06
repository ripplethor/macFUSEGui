// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct DependencyStatus: Sendable {
    let isReady: Bool
    let sshfsPath: String?
    let issues: [String]

    // Convenience for single Text rendering. Callers can use `issues` directly for list UIs.
    var userFacingMessage: String {
        if issues.isEmpty {
            return L10n.tr("All dependencies are available.")
        }
        return issues.joined(separator: "\n")
    }
}

/// Beginner note: This protocol allows tests to stub dependency readiness without relying on host machine setup.
protocol DependencyChecking {
    /// Beginner note: This method is one step in the feature workflow for this file.
    func check(sshfsOverride: String?) -> DependencyStatus
}

extension DependencyChecking {
    /// Beginner note: This overload keeps production call sites simple.
    func check() -> DependencyStatus {
        check(sshfsOverride: nil)
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class DependencyChecker: DependencyChecking {
    private let fileManager: FileManager
    // For non-standard install locations, callers should pass `sshfsOverride`.
    // MacPorts commonly installs at /opt/local/bin/sshfs.
    private let fallbackSSHFSPaths = [
        "/opt/homebrew/bin/sshfs",
        "/usr/local/bin/sshfs",
        "/opt/local/bin/sshfs",
        "/usr/bin/sshfs"
    ]

    /// Beginner note: Initializers create valid state before any other method is used.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func check(sshfsOverride: String? = nil) -> DependencyStatus {
        var issues: [String] = []

        let sshfsPath = resolveSSHFSPath(override: sshfsOverride)
        if sshfsPath == nil {
            issues.append(
                L10n.tr("sshfs is not installed. Install with: brew install sshfs-mac")
            )
        }

        let macfusePath = "/Library/Filesystems/macfuse.fs"
        if !fileManager.fileExists(atPath: macfusePath) {
            issues.append(
                L10n.tr("macFUSE is not installed. Install with: brew install --cask macfuse")
            )
        }

        // Defensive checks for expected macOS base-system tools.
        if !fileManager.isExecutableFile(atPath: "/usr/bin/ssh") {
            issues.append(L10n.tr("ssh is missing at /usr/bin/ssh."))
        }

        if !fileManager.isExecutableFile(atPath: "/usr/bin/sftp") {
            issues.append(L10n.tr("sftp is missing at /usr/bin/sftp."))
        }

        return DependencyStatus(
            isReady: issues.isEmpty,
            sshfsPath: sshfsPath,
            issues: issues
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func resolveSSHFSPath(override: String?) -> String? {
        if let override {
            let normalizedOverride = URL(fileURLWithPath: override).standardizedFileURL.path
            // Note: isExecutableFile is a point-in-time check; path could still change before execution.
            if fileManager.isExecutableFile(atPath: normalizedOverride) {
                return normalizedOverride
            }
        }

        for path in fallbackSSHFSPaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }

        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for segment in envPath.split(separator: ":") {
                guard segment.hasPrefix("/") else {
                    continue
                }
                let candidate = String(segment) + "/sshfs"
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }
}
