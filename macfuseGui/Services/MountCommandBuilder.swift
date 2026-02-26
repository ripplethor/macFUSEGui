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
struct MountCommand: Sendable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let redactedCommand: String
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class MountCommandBuilder {
    private let redactionService: RedactionService

    /// Beginner note: Initializers create valid state before any other method is used.
    init(redactionService: RedactionService) {
        self.redactionService = redactionService
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func build(
        sshfsPath: String,
        remote: RemoteConfig,
        passwordEnvironment: [String: String] = [:]
    ) -> MountCommand {
        let executable = sshfsPath.trimmingCharacters(in: .whitespacesAndNewlines)
        assert(!executable.isEmpty, "sshfsPath must not be empty.")
        let normalizedRemotePath = normalizedRemoteDirectory(remote.remoteDirectory)

        var options = [
            "reconnect",
            "ServerAliveInterval=15",
            "ServerAliveCountMax=3",
            "defer_permissions",
            "noappledouble",
            "nolocalcaches",
            "auto_cache",
            "StrictHostKeyChecking=accept-new",
            "ConnectTimeout=10",
            "volname=\(escapedOptionValue(volumeName(for: remote, normalizedRemotePath: normalizedRemotePath)))"
        ]

        if remote.authMode == .privateKey,
           let key = remote.privateKeyPath,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalizedKeyPath = URL(fileURLWithPath: key).standardizedFileURL.path
            options.append("IdentityFile=\(escapedOptionValue(normalizedKeyPath))")
        }

        var args: [String] = ["-p", "\(remote.port)"]
        for option in options {
            args.append("-o")
            args.append(option)
        }

        let source = "\(remote.username)@\(sshHostArgument(remote.host)):\(normalizedRemotePath)"
        args.append(source)
        args.append(remote.localMountPoint)

        let redacted = redactionService.redactedCommand(
            executable: executable,
            arguments: args,
            secrets: askpassSecrets(from: passwordEnvironment)
        )

        return MountCommand(
            executable: executable,
            arguments: args,
            environment: passwordEnvironment,
            redactedCommand: redacted
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func askpassSecrets(from environment: [String: String]) -> [String] {
        environment.compactMap { key, value in
            if key.hasPrefix("MACFUSEGUI_ASKPASS_PASSWORD") {
                return value
            }
            return nil
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func normalizedRemoteDirectory(_ rawValue: String) -> String {
        BrowserPathNormalizer.normalize(path: rawValue)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func volumeName(for remote: RemoteConfig, normalizedRemotePath: String) -> String {
        var parts: [String] = []

        let display = remote.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty {
            parts.append(display)
        }

        if let leaf = remotePathLeaf(normalizedRemotePath), !leaf.isEmpty {
            if parts.isEmpty || parts[0].caseInsensitiveCompare(leaf) != .orderedSame {
                parts.append(leaf)
            }
        }

        if parts.isEmpty {
            parts.append(remote.host)
        }

        return sanitizedVolumeName(
            parts.joined(separator: " - "),
            fallbackSeed: "\(remote.host)-\(remote.port)-\(remote.id.uuidString)"
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func remotePathLeaf(_ normalizedPath: String) -> String? {
        let trimmed = normalizedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed == "/" {
            return nil
        }

        if trimmed == "~" {
            return "home"
        }

        var path = trimmed
        if path.hasPrefix("~/") {
            path.removeFirst(2)
        } else if path.hasPrefix("~") {
            path.removeFirst()
            while path.hasPrefix("/") {
                path.removeFirst()
            }
        }

        if path.isEmpty {
            return "home"
        }

        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }

        let components = path.split(separator: "/")
        guard let leaf = components.last else {
            return nil
        }
        return String(leaf)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func sanitizedVolumeName(_ raw: String, fallbackSeed: String) -> String {
        let cleaned = raw
            .replacingOccurrences(
                of: "[^A-Za-z0-9 ._\\-\\(\\)\\[\\]]",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let cleanedFallbackSeed = fallbackSeed
            .replacingOccurrences(
                of: "[^A-Za-z0-9 ._\\-\\(\\)\\[\\]]",
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fallback = cleanedFallbackSeed.isEmpty ? "macfuseGui" : cleanedFallbackSeed
        let resolved = cleaned.isEmpty ? fallback : cleaned
        return String(resolved.prefix(63))
    }

    /// Beginner note: sshfs parses -o values, so commas and backslashes in values
    /// must be escaped to avoid option splitting or malformed paths.
    private func escapedOptionValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
    }
}

/// Returns the host wrapped in brackets for IPv6 addresses, which contain colons that
/// would otherwise be ambiguous in the `user@host:path` sshfs argument format.
/// Plain hostnames and already-bracketed addresses are returned unchanged.
func sshHostArgument(_ host: String) -> String {
    guard host.contains(":"), !host.hasPrefix("[") else {
        return host
    }
    return "[\(host)]"
}
