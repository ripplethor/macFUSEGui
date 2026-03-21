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

/// Beginner note: Captures which SSHFS-specific metadata cache options the installed binary supports.
/// Detect once per sshfs path and reuse across mount calls.
struct SSHFSCapabilities: Sendable, Equatable {
    /// Newer sshfs builds: dir_cache, dcache_timeout, dcache_stat_timeout, dcache_dir_timeout, dcache_link_timeout.
    let supportsDCacheFamily: Bool
    /// Older sshfs builds: cache_stat_timeout, cache_dir_timeout, cache_link_timeout.
    let supportsOlderCacheFamily: Bool

    static let none = SSHFSCapabilities(supportsDCacheFamily: false, supportsOlderCacheFamily: false)

    /// Runs `sshfs -h` and inspects the help output for supported option names.
    static func detect(runner: ProcessRunning, sshfsPath: String) async -> SSHFSCapabilities {
        do {
            let result = try await runner.run(
                executable: sshfsPath,
                arguments: ["-h"],
                timeout: 5
            )
            // sshfs prints help to stderr (some builds use stdout); check both.
            let output = result.stderr + " " + result.stdout
            let hasDCache = output.contains("dir_cache")
            let hasOlderCache = output.contains("cache_stat_timeout")
            return SSHFSCapabilities(
                supportsDCacheFamily: hasDCache,
                supportsOlderCacheFamily: hasOlderCache
            )
        } catch {
            return .none
        }
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class MountCommandBuilder {
    private static let cacheTimeoutSeconds = 120
    private static let cacheMaxEntries = 50000

    private let redactionService: RedactionService

    /// Beginner note: Initializers create valid state before any other method is used.
    init(redactionService: RedactionService) {
        self.redactionService = redactionService
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func build(
        sshfsPath: String,
        remote: RemoteConfig,
        passwordEnvironment: [String: String] = [:],
        capabilities: SSHFSCapabilities = .none
    ) -> MountCommand {
        let executable = sshfsPath.trimmingCharacters(in: .whitespacesAndNewlines)
        assert(!executable.isEmpty, "sshfsPath must not be empty.")
        let normalizedRemotePath = normalizedRemoteDirectory(remote.remoteDirectory)
        let t = Self.cacheTimeoutSeconds

        var options = [
            "reconnect",
            "ServerAliveInterval=15",
            "ServerAliveCountMax=3",
            "defer_permissions",
            "noappledouble",
            "noapplexattr"
        ]

        if remote.disableLocalCaches {
            options.append("nolocalcaches")
        } else {
            options.append("attr_timeout=\(t)")
            options.append("entry_timeout=\(t)")
            options.append("cache_timeout=\(t)")
            options.append("cache_max_size=\(Self.cacheMaxEntries)")

            if capabilities.supportsDCacheFamily {
                options.append("dir_cache=yes")
                options.append("dcache_timeout=\(t)")
                options.append("dcache_stat_timeout=\(t)")
                options.append("dcache_dir_timeout=\(t)")
                options.append("dcache_link_timeout=\(t)")
            } else if capabilities.supportsOlderCacheFamily {
                options.append("cache_stat_timeout=\(t)")
                options.append("cache_dir_timeout=\(t)")
                options.append("cache_link_timeout=\(t)")
            }
        }

        options.append(contentsOf: [
            "auto_cache",
            "StrictHostKeyChecking=accept-new",
            "ConnectTimeout=10",
            "volname=\(escapedOptionValue(volumeName(for: remote, normalizedRemotePath: normalizedRemotePath)))"
        ])

        if remote.authMode == .privateKey,
           let key = remote.privateKeyPath,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalizedKeyPath = LocalPathNormalizer.normalize(key)
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
