// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

enum DependencyKind: String, Hashable, Sendable {
    case sshfs
    case macfuse
    case ssh
    case sftp

    var helpURL: URL? {
        switch self {
        case .sshfs:
            return URL(string: "https://github.com/macfuse/sshfs-mac")
        case .macfuse:
            return URL(string: "https://macfuse.github.io/")
        case .ssh, .sftp:
            return nil
        }
    }
}

struct DependencyIssue: Hashable, Sendable {
    let kind: DependencyKind
    let summary: String
    let detail: String
    let installCommand: String?

    var userFacingMessage: String {
        var parts = [summary]
        if !detail.isEmpty {
            parts.append(detail)
        }
        if let installCommand, !installCommand.isEmpty {
            parts.append(L10n.format("Install with: %@", installCommand))
        }
        return parts.joined(separator: " ")
    }
}

enum SSHFSBackendSource: String, Hashable, Sendable {
    case userOverride
    case homebrewAppleSilicon
    case homebrewIntel
    case macPorts
    case system
    case environmentPath
    case compatibility

    var displayName: String {
        switch self {
        case .userOverride:
            return L10n.tr("Custom override")
        case .homebrewAppleSilicon:
            return L10n.tr("Homebrew (Apple Silicon)")
        case .homebrewIntel:
            return L10n.tr("Homebrew (/usr/local)")
        case .macPorts:
            return L10n.tr("MacPorts")
        case .system:
            return L10n.tr("System path")
        case .environmentPath:
            return L10n.tr("PATH fallback")
        case .compatibility:
            return L10n.tr("Resolved path")
        }
    }
}

struct SSHFSBackendDescriptor: Hashable, Sendable {
    let path: String
    let source: SSHFSBackendSource
    let configuredOverridePath: String?

    var isUsingOverride: Bool {
        source == .userOverride
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct DependencyStatus: Sendable {
    let isReady: Bool
    let sshfsBackend: SSHFSBackendDescriptor?
    let issues: [DependencyIssue]

    init(isReady: Bool, sshfsBackend: SSHFSBackendDescriptor?, issues: [DependencyIssue]) {
        self.isReady = isReady
        self.sshfsBackend = sshfsBackend
        self.issues = issues
    }

    init(
        isReady: Bool,
        sshfsPath: String?,
        issues: [DependencyIssue]
    ) {
        self.init(
            isReady: isReady,
            sshfsBackend: sshfsPath.map {
                SSHFSBackendDescriptor(
                    path: $0,
                    source: .compatibility,
                    configuredOverridePath: nil
                )
            },
            issues: issues
        )
    }

    var sshfsPath: String? {
        sshfsBackend?.path
    }

    // Convenience for single Text rendering. Callers can use `issues` directly for list UIs.
    var userFacingMessage: String {
        if issues.isEmpty {
            return L10n.tr("All dependencies are available.")
        }
        return issues.map(\.userFacingMessage).joined(separator: "\n")
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
    private let userDefaults: UserDefaults
    private let environmentProvider: @Sendable () -> [String: String]
    // For non-standard install locations, callers should pass `sshfsOverride`.
    // MacPorts commonly installs at /opt/local/bin/sshfs.
    private let fallbackSSHFSPaths: [String]
    private let macfuseInstallPath: String
    private let sshExecutablePath: String
    private let sftpExecutablePath: String
    private let sshfsOverridePathKey = "mount.backend.sshfs.override_path"
    private let sshfsPinnedPathKey = "mount.backend.sshfs.pinned_path"
    private let sshfsPinnedSourceKey = "mount.backend.sshfs.pinned_source"

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        fallbackSSHFSPaths: [String] = [
            "/opt/homebrew/bin/sshfs",
            "/usr/local/bin/sshfs",
            "/opt/local/bin/sshfs",
            "/usr/bin/sshfs"
        ],
        macfuseInstallPath: String = "/Library/Filesystems/macfuse.fs",
        sshExecutablePath: String = "/usr/bin/ssh",
        sftpExecutablePath: String = "/usr/bin/sftp",
        environmentProvider: @escaping @Sendable () -> [String: String] = { ProcessInfo.processInfo.environment }
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.fallbackSSHFSPaths = fallbackSSHFSPaths
        self.macfuseInstallPath = macfuseInstallPath
        self.sshExecutablePath = sshExecutablePath
        self.sftpExecutablePath = sftpExecutablePath
        self.environmentProvider = environmentProvider
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func check(sshfsOverride: String? = nil) -> DependencyStatus {
        var issues: [DependencyIssue] = []

        let backendResolution = resolveSSHFSBackend(override: sshfsOverride)
        if let issue = backendResolution.issue {
            issues.append(issue)
        }

        if !fileManager.fileExists(atPath: macfuseInstallPath) {
            issues.append(
                DependencyIssue(
                    kind: .macfuse,
                    summary: L10n.tr("macFUSE is not installed."),
                    detail: L10n.tr("Install macFUSE before connecting any remotes. You can use Homebrew or the official installer."),
                    installCommand: "brew install --cask macfuse"
                )
            )
        }

        // Defensive checks for expected macOS base-system tools.
        if !fileManager.isExecutableFile(atPath: sshExecutablePath) {
            issues.append(
                DependencyIssue(
                    kind: .ssh,
                    summary: L10n.format("ssh is missing at %@.", sshExecutablePath),
                    detail: L10n.tr("macfuseGui expects the macOS system OpenSSH client. Repair or reinstall the OS components that provide /usr/bin/ssh."),
                    installCommand: nil
                )
            )
        }

        if !fileManager.isExecutableFile(atPath: sftpExecutablePath) {
            issues.append(
                DependencyIssue(
                    kind: .sftp,
                    summary: L10n.format("sftp is missing at %@.", sftpExecutablePath),
                    detail: L10n.tr("macfuseGui expects the macOS system SFTP client. Repair or reinstall the OS components that provide /usr/bin/sftp."),
                    installCommand: nil
                )
            )
        }

        return DependencyStatus(
            isReady: issues.isEmpty,
            sshfsBackend: backendResolution.backend,
            issues: issues
        )
    }

    var configuredSSHFSOverridePath: String? {
        normalizedStoredPath(userDefaults.string(forKey: sshfsOverridePathKey))
    }

    func setConfiguredSSHFSOverridePath(_ rawPath: String?) {
        if let normalized = normalizedStoredPath(rawPath) {
            userDefaults.set(normalized, forKey: sshfsOverridePathKey)
        } else {
            userDefaults.removeObject(forKey: sshfsOverridePathKey)
        }
        clearPinnedSSHFSBackend()
    }

    func clearPinnedSSHFSBackend() {
        userDefaults.removeObject(forKey: sshfsPinnedPathKey)
        userDefaults.removeObject(forKey: sshfsPinnedSourceKey)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func resolveSSHFSBackend(override: String?) -> (backend: SSHFSBackendDescriptor?, issue: DependencyIssue?) {
        let effectiveOverride = normalizedStoredPath(override) ?? configuredSSHFSOverridePath
        if let effectiveOverride {
            if fileManager.isExecutableFile(atPath: effectiveOverride) {
                let backend = SSHFSBackendDescriptor(
                    path: effectiveOverride,
                    source: .userOverride,
                    configuredOverridePath: configuredSSHFSOverridePath
                )
                persistPinnedSSHFSBackend(backend)
                return (backend, nil)
            }
            clearPinnedSSHFSBackend()
            return (
                nil,
                DependencyIssue(
                    kind: .sshfs,
                    summary: L10n.tr("sshfs backend is unavailable."),
                    detail: L10n.format(
                        "The configured sshfs backend override is not executable: %@. Clear the override or point it at a local sshfs binary.",
                        effectiveOverride
                    ),
                    installCommand: "brew install sshfs-mac"
                )
            )
        }

        if let pinned = pinnedSSHFSBackend(), fileManager.isExecutableFile(atPath: pinned.path) {
            return (pinned, nil)
        }

        clearPinnedSSHFSBackend()
        for candidate in sshfsDiscoveryCandidates() where fileManager.isExecutableFile(atPath: candidate.path) {
            persistPinnedSSHFSBackend(candidate)
            return (candidate, nil)
        }

        return (
            nil,
            DependencyIssue(
                kind: .sshfs,
                summary: L10n.tr("sshfs backend is unavailable."),
                detail: L10n.tr("Install sshfs-mac or set a custom sshfs path in Settings so the app can pin a validated backend."),
                installCommand: "brew install sshfs-mac"
            )
        )
    }

    private func pinnedSSHFSBackend() -> SSHFSBackendDescriptor? {
        guard let pinnedPath = normalizedStoredPath(userDefaults.string(forKey: sshfsPinnedPathKey)),
              let rawSource = userDefaults.string(forKey: sshfsPinnedSourceKey),
              let source = SSHFSBackendSource(rawValue: rawSource) else {
            return nil
        }
        return SSHFSBackendDescriptor(
            path: pinnedPath,
            source: source,
            configuredOverridePath: configuredSSHFSOverridePath
        )
    }

    private func persistPinnedSSHFSBackend(_ backend: SSHFSBackendDescriptor) {
        userDefaults.set(backend.path, forKey: sshfsPinnedPathKey)
        userDefaults.set(backend.source.rawValue, forKey: sshfsPinnedSourceKey)
    }

    private func sshfsDiscoveryCandidates() -> [SSHFSBackendDescriptor] {
        var seen: Set<String> = []
        var candidates: [SSHFSBackendDescriptor] = []

        for path in fallbackSSHFSPaths {
            guard let normalized = normalizedStoredPath(path), seen.insert(normalized).inserted else {
                continue
            }
            candidates.append(
                SSHFSBackendDescriptor(
                    path: normalized,
                    source: sourceForBuiltInSSHFSPath(normalized),
                    configuredOverridePath: configuredSSHFSOverridePath
                )
            )
        }

        if let envPath = environmentProvider()["PATH"] {
            for segment in envPath.split(separator: ":") {
                guard segment.hasPrefix("/") else {
                    continue
                }
                let candidate = LocalPathNormalizer.normalize(String(segment) + "/sshfs")
                guard !candidate.isEmpty, seen.insert(candidate).inserted else {
                    continue
                }
                candidates.append(
                    SSHFSBackendDescriptor(
                        path: candidate,
                        source: .environmentPath,
                        configuredOverridePath: configuredSSHFSOverridePath
                    )
                )
            }
        }

        return candidates
    }

    private func sourceForBuiltInSSHFSPath(_ path: String) -> SSHFSBackendSource {
        switch path {
        case "/opt/homebrew/bin/sshfs":
            return .homebrewAppleSilicon
        case "/usr/local/bin/sshfs":
            return .homebrewIntel
        case "/opt/local/bin/sshfs":
            return .macPorts
        case "/usr/bin/sshfs":
            return .system
        default:
            return .environmentPath
        }
    }

    private func normalizedStoredPath(_ rawPath: String?) -> String? {
        guard let rawPath else {
            return nil
        }
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return LocalPathNormalizer.normalize(trimmed)
    }
}
