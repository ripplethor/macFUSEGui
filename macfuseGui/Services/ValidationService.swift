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
final class ValidationService {
    /// Beginner note: Initializers create valid state before any other method is used.
    init() {}

    /// Beginner note: This method is one step in the feature workflow for this file.
    func validateDraft(
        _ draft: RemoteDraft,
        hasStoredPassword: Bool
    ) -> [String] {
        var errors: [String] = []
        // Validation checks trimmed field views; persistence normalization occurs when
        // RemoteDraft is converted to RemoteConfig in the save path.

        let displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if displayName.isEmpty {
            errors.append(L10n.tr("Display name is required."))
        }

        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty {
            errors.append(L10n.tr("Host/IP is required."))
        } else {
            if containsUnsafeControlCharacters(host) {
                errors.append(L10n.tr("Host/IP contains invalid control characters."))
            } else if isBareIPv6HostLiteral(host) {
                errors.append(L10n.tr("IPv6 addresses must be wrapped in brackets, for example [::1]."))
            } else if !isSupportedHost(host) {
                // Host syntax allows standard DNS-like names and bracketed IPv6 literals.
                errors.append(L10n.tr("Host/IP contains unsupported characters."))
            }
        }

        if !(1...65535).contains(draft.port) {
            errors.append(L10n.tr("Port must be between 1 and 65535."))
        }

        let username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if username.isEmpty {
            errors.append(L10n.tr("Username is required."))
        } else if username.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            errors.append(L10n.tr("Username cannot contain whitespace characters."))
        }

        let remoteDirectory = draft.remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isSupportedRemotePath(remoteDirectory) {
            errors.append(L10n.tr("Remote directory must be absolute (for example /home/user or C:/Users/User)."))
        } else if containsUnsafeControlCharacters(remoteDirectory) {
            errors.append(L10n.tr("Remote directory contains invalid control characters."))
        }

        let localMount = draft.localMountPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if localMount.isEmpty {
            errors.append(L10n.tr("Local mount point is required."))
        } else if !localMount.hasPrefix("/") {
            errors.append(L10n.tr("Local mount point must be an absolute path."))
        } else if containsUnsafeControlCharacters(localMount) {
            errors.append(L10n.tr("Local mount point contains invalid control characters."))
        } else {
            // Keep mount-point normalization purely lexical here. Resolving a stale
            // FUSE path via `standardizedFileURL` can synchronously touch the
            // filesystem and wedge UI-driven validation/recovery flows.
            let normalizedMount = LocalPathNormalizer.normalize(localMount)
            if normalizedMount == "/" {
                errors.append(L10n.tr("Local mount point cannot be '/'. Choose a subfolder."))
            }
            // Important: avoid synchronous file-system probes here.
            // Save/Test validation runs on MainActor, and stale FUSE mount paths can
            // block `fileExists`/`isWritableFile` long enough to beachball the UI.
            // MountManager performs bounded mount-point checks during connect.
        }

        switch draft.authMode {
        case .privateKey:
            let keyPath = draft.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if keyPath.isEmpty {
                errors.append(L10n.tr("Private key path is required for key authentication."))
            } else if !keyPath.hasPrefix("/") {
                errors.append(L10n.tr("Private key path must be an absolute path."))
            } else if containsUnsafeControlCharacters(keyPath) {
                errors.append(L10n.tr("Private key path contains invalid control characters."))
            } else {
                // Keep key-path validation lexical-only on MainActor. A user can point
                // the key at a stale network/FUSE path, and synchronous `fileExists` /
                // `isReadableFile` checks here would beachball save/test flows.
                // MountManager performs bounded readiness probes during connect/test.
            }
        case .password:
            if !hasStoredPassword && draft.password.isEmpty {
                errors.append(L10n.tr("Password is required for password authentication."))
            }
        }

        return errors
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func containsUnsafeControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func isSupportedRemotePath(_ value: String) -> Bool {
        if value.hasPrefix("/") || value == "~" || value.hasPrefix("~/") {
            return true
        }

        return isWindowsDrivePath(value)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func isSupportedHost(_ value: String) -> Bool {
        value.range(of: #"^(?:\[[A-Fa-f0-9:.]+\]|[A-Za-z0-9._-]+)$"#, options: .regularExpression) != nil
    }

    private func isBareIPv6HostLiteral(_ value: String) -> Bool {
        value.contains(":") && !(value.hasPrefix("[") && value.hasSuffix("]"))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func isWindowsDrivePath(_ value: String) -> Bool {
        guard value.count >= 3 else {
            return false
        }

        let chars = Array(value)
        return chars[0].isLetter
            && chars[1] == ":"
            && (chars[2] == "/" || chars[2] == "\\")
    }
}

/// Main-actor callers must not resolve mount-point symlinks or filesystem state while
/// comparing paths. A dead/stale FUSE mount can block those lookups long enough to
/// beachball the app. This helper keeps normalization purely lexical.
enum LocalPathNormalizer {
    static func normalize(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let isAbsolute = trimmed.hasPrefix("/")
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        var normalizedSegments: [Substring] = []

        for segment in segments {
            switch segment {
            case ".":
                continue
            case "..":
                if isAbsolute {
                    if !normalizedSegments.isEmpty {
                        normalizedSegments.removeLast()
                    }
                } else if let last = normalizedSegments.last, last != ".." {
                    normalizedSegments.removeLast()
                } else {
                    normalizedSegments.append(segment)
                }
            default:
                normalizedSegments.append(segment)
            }
        }

        let normalizedBody = normalizedSegments.map(String.init).joined(separator: "/")
        if isAbsolute {
            return normalizedBody.isEmpty ? "/" : "/\(normalizedBody)"
        }
        return normalizedBody
    }

    static func parentPath(of rawPath: String) -> String {
        let normalized = normalize(rawPath)
        guard !normalized.isEmpty else {
            return ""
        }

        guard normalized != "/" else {
            return "/"
        }

        guard let slashIndex = normalized.lastIndex(of: "/") else {
            return ""
        }

        if slashIndex == normalized.startIndex {
            return "/"
        }

        return String(normalized[..<slashIndex])
    }
}
