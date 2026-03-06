// BEGINNER FILE GUIDE
// Layer: Browser service layer
// Purpose: This file implements remote directory browsing sessions, transport, parsing, or path normalization.
// Called by: Called from RemoteDirectoryBrowserService and browser-facing view models.
// Calls into: Calls into libssh2 bridge, diagnostics, and browser state models.
// Concurrency: Contains async functions; these can suspend and resume without blocking the calling thread.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct BrowserTransportListResult: Sendable {
    var resolvedPath: String
    var entries: [RemoteDirectoryItem]
    var latencyMs: Int
    var reopenedSession: Bool
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
protocol BrowserTransport {
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func listDirectories(remote: RemoteConfig, path: String, password: String?) async throws -> BrowserTransportListResult
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func ping(remote: RemoteConfig, path: String, password: String?) async throws
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func invalidate(remoteID: UUID) async
}

extension BrowserTransport {
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func invalidate(remoteID: UUID) async {}
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
// @unchecked Sendable is safe here because the sessions map is only accessed on the private serial bridgeQueue.
final class LibSSH2SFTPTransport: BrowserTransport, @unchecked Sendable {
    private let diagnostics: DiagnosticsService
    private let bridgeQueue = DispatchQueue(label: "com.visualweb.macfusegui.browser.libssh2", qos: .userInitiated)
    private let bridgeQueueSpecificKey = DispatchSpecificKey<UInt8>()
    private let bridgeQueueSpecificValue: UInt8 = 1
    private let listTimeoutSeconds: TimeInterval
    private let pingTimeoutSeconds: TimeInterval
    private var sessions: [UUID: UnsafeMutablePointer<macfusegui_libssh2_session_handle>] = [:]

    private func assertOnBridgeQueue() {
        dispatchPrecondition(condition: .onQueue(bridgeQueue))
    }

    private func isOnBridgeQueue() -> Bool {
        DispatchQueue.getSpecific(key: bridgeQueueSpecificKey) == bridgeQueueSpecificValue
    }

    private func closeAllSessionsOnBridgeQueue() {
        assertOnBridgeQueue()
        for (_, handle) in sessions {
            macfusegui_libssh2_close_session(handle)
        }
        sessions.removeAll()
    }

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        diagnostics: DiagnosticsService,
        listTimeoutSeconds: TimeInterval = 8,
        pingTimeoutSeconds: TimeInterval = 2
    ) {
        self.diagnostics = diagnostics
        self.listTimeoutSeconds = listTimeoutSeconds
        self.pingTimeoutSeconds = pingTimeoutSeconds
        bridgeQueue.setSpecific(key: bridgeQueueSpecificKey, value: bridgeQueueSpecificValue)
    }

    /// Beginner note: Deinitializer runs during teardown to stop background work and free resources.
    deinit {
        if isOnBridgeQueue() {
            assertionFailure("LibSSH2SFTPTransport deinit called on bridge queue; closing sessions inline to avoid deadlock.")
            closeAllSessionsOnBridgeQueue()
            return
        }

        bridgeQueue.sync {
            closeAllSessionsOnBridgeQueue()
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func listDirectories(remote: RemoteConfig, path: String, password: String?) async throws -> BrowserTransportListResult {
        let normalizedPath = BrowserPathNormalizer.normalize(path: path)

        diagnostics.append(
            level: .info,
            category: "remote-browser",
            message: "libssh2 list start host=\(remote.host) port=\(remote.port) user=\(remote.username) path=\(normalizedPath) auth=\(remote.authMode.rawValue)"
        )

        return try await withCheckedThrowingContinuation { continuation in
            bridgeQueue.async { [self] in
                do {
                    let result = try listDirectoriesSync(remote: remote, path: normalizedPath, password: password)
                    let directoryCount = result.entries.reduce(into: 0) { partial, item in
                        if item.isDirectory {
                            partial += 1
                        }
                    }
                    diagnostics.append(
                        level: .info,
                        category: "remote-browser",
                        message: "libssh2 list success path=\(result.resolvedPath) entries=\(result.entries.count) dirs=\(directoryCount) latencyMs=\(result.latencyMs) reopenedSession=\(result.reopenedSession)"
                    )
                    continuation.resume(returning: result)
                } catch {
                    diagnostics.append(
                        level: .warning,
                        category: "remote-browser",
                        message: "libssh2 list failed host=\(remote.host) path=\(normalizedPath): \(error.localizedDescription)"
                    )
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async and throwing: callers must await it and handle failures.
    func ping(remote: RemoteConfig, path: String, password: String?) async throws {
        let normalizedPath = BrowserPathNormalizer.normalize(path: path)
        try await withCheckedThrowingContinuation { continuation in
            bridgeQueue.async { [self] in
                do {
                    try pingSync(remote: remote, path: normalizedPath, password: password)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func invalidate(remoteID: UUID) async {
        await withCheckedContinuation { continuation in
            bridgeQueue.async { [self] in
                closeSessionSync(for: remoteID)
                continuation.resume()
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    private func listDirectoriesSync(remote: RemoteConfig, path: String, password: String?) throws -> BrowserTransportListResult {
        let timeout = Int32(max(1, Int(listTimeoutSeconds.rounded())))
        let credentials = try resolveCredentials(for: remote, password: password)

        do {
            let handle = try ensureSessionSync(
                remote: remote,
                password: credentials.password,
                privateKeyPath: credentials.privateKeyPath,
                timeout: timeout
            )
            return try listWithSessionSync(
                handle: handle,
                remoteID: remote.id,
                path: path,
                timeout: timeout,
                reopenedSession: false
            )
        } catch {
            closeSessionSync(for: remote.id)
            let handle = try ensureSessionSync(
                remote: remote,
                password: credentials.password,
                privateKeyPath: credentials.privateKeyPath,
                timeout: timeout
            )
            return try listWithSessionSync(
                handle: handle,
                remoteID: remote.id,
                path: path,
                timeout: timeout,
                reopenedSession: true
            )
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    private func pingSync(remote: RemoteConfig, path: String, password: String?) throws {
        let timeout = Int32(max(1, Int(pingTimeoutSeconds.rounded())))
        let credentials = try resolveCredentials(for: remote, password: password)

        do {
            let handle = try ensureSessionSync(
                remote: remote,
                password: credentials.password,
                privateKeyPath: credentials.privateKeyPath,
                timeout: timeout
            )
            try pingWithSessionSync(handle: handle, path: path, timeout: timeout)
        } catch {
            closeSessionSync(for: remote.id)
            let handle = try ensureSessionSync(
                remote: remote,
                password: credentials.password,
                privateKeyPath: credentials.privateKeyPath,
                timeout: timeout
            )
            do {
                try pingWithSessionSync(handle: handle, path: path, timeout: timeout)
            } catch {
                closeSessionSync(for: remote.id)
                throw error
            }
        }
    }

    private func pingWithSessionSync(
        handle: UnsafeMutablePointer<macfusegui_libssh2_session_handle>,
        path: String,
        timeout: Int32
    ) throws {
        assertOnBridgeQueue()
        var errorPtr: UnsafeMutablePointer<CChar>?
        let status = path.withCString { pathPtr in
            macfusegui_libssh2_ping_session(handle, pathPtr, timeout, &errorPtr)
        }
        defer {
            if let errorPtr {
                macfusegui_libssh2_free_error(errorPtr)
            }
        }

        if status != 0 {
            let timeoutSeconds = Int(timeout)
            let message = errorPtr.map { String(cString: $0) } ?? L10n.format("libssh2 keepalive failed with status %lld after %llds.", Int64(status), Int64(timeoutSeconds))
            throw AppError.remoteBrowserError(message)
        }
    }

    private func resolveCredentials(
        for remote: RemoteConfig,
        password: String?
    ) throws -> (password: String?, privateKeyPath: String?) {
        switch remote.authMode {
        case .password:
            guard let password, !password.isEmpty else {
                throw AppError.remoteBrowserError(L10n.tr("Password is required for remote browsing."))
            }
            return (password, nil)
        case .privateKey:
            guard let key = remote.privateKeyPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty else {
                throw AppError.remoteBrowserError(L10n.tr("Private key path is required for key-based remote browsing."))
            }
            return (nil, key)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func ensureSessionSync(
        remote: RemoteConfig,
        password: String?,
        privateKeyPath: String?,
        timeout: Int32
    ) throws -> UnsafeMutablePointer<macfusegui_libssh2_session_handle> {
        assertOnBridgeQueue()
        if let existing = sessions[remote.id] {
            return existing
        }

        var handle: UnsafeMutablePointer<macfusegui_libssh2_session_handle>?
        var errorPtr: UnsafeMutablePointer<CChar>?
        let status = remote.host.withCString { hostPtr in
            remote.username.withCString { usernamePtr in
                withOptionalCString(password) { passwordPtr in
                    withOptionalCString(privateKeyPath) { keyPtr in
                        macfusegui_libssh2_open_session(
                            hostPtr,
                            Int32(remote.port),
                            usernamePtr,
                            passwordPtr,
                            keyPtr,
                            timeout,
                            &handle,
                            &errorPtr
                        )
                    }
                }
            }
        }
        defer {
            if let errorPtr {
                macfusegui_libssh2_free_error(errorPtr)
            }
        }

        guard status == 0, let resolved = handle else {
            let timeoutSeconds = Int(timeout)
            let message = errorPtr.map { String(cString: $0) } ?? L10n.format("Failed to open libssh2 browser session within %llds.", Int64(timeoutSeconds))
            throw AppError.remoteBrowserError(message)
        }

        sessions[remote.id] = resolved
        diagnostics.append(
            level: .debug,
            category: "remote-browser",
            message: "Opened persistent libssh2 session for \(remote.displayName) (\(remote.id.uuidString))"
        )
        return resolved
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func listWithSessionSync(
        handle: UnsafeMutablePointer<macfusegui_libssh2_session_handle>,
        remoteID: UUID,
        path: String,
        timeout: Int32,
        reopenedSession: Bool
    ) throws -> BrowserTransportListResult {
        assertOnBridgeQueue()
        var cResult = macfusegui_libssh2_list_result()
        let status = path.withCString { pathPtr in
            macfusegui_libssh2_list_directories_with_session(
                handle,
                pathPtr,
                timeout,
                &cResult
            )
        }

        defer {
            macfusegui_libssh2_free_list_result(&cResult)
        }

        guard status == 0 else {
            closeSessionSync(for: remoteID)
            let message: String
            if let errorPtr = cResult.error_message {
                message = String(cString: errorPtr)
            } else {
                let timeoutSeconds = Int(timeout)
                message = L10n.format("libssh2 browse failed with status %lld on path %@ after %llds.", Int64(status), path, Int64(timeoutSeconds))
            }
            throw AppError.remoteBrowserError(message)
        }

        let resolvedPath: String
        if let resolvedPtr = cResult.resolved_path {
            resolvedPath = BrowserPathNormalizer.normalize(path: String(cString: resolvedPtr))
        } else {
            resolvedPath = path
        }

        let entries = convertEntries(from: cResult, resolvedPath: resolvedPath)

        return BrowserTransportListResult(
            resolvedPath: resolvedPath,
            entries: entries,
            latencyMs: clampedLatencyMs(cResult.latency_ms),
            reopenedSession: reopenedSession
        )
    }

    private func clampedLatencyMs(_ value: Int32) -> Int {
        max(0, min(Int(value), 60_000))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func closeSessionSync(for remoteID: UUID) {
        assertOnBridgeQueue()
        guard let handle = sessions.removeValue(forKey: remoteID) else {
            return
        }
        macfusegui_libssh2_close_session(handle)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func convertEntries(from cResult: macfusegui_libssh2_list_result, resolvedPath: String) -> [RemoteDirectoryItem] {
        let count = Int(cResult.entry_count)
        guard count > 0, let cEntries = cResult.entries else {
            return []
        }

        var output: [RemoteDirectoryItem] = []
        output.reserveCapacity(count)

        for index in 0..<count {
            let cEntry = cEntries[index]
            guard let namePtr = cEntry.name else {
                continue
            }

            let name = String(cString: namePtr).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != ".", name != ".." else {
                continue
            }

            let modifiedAt: Date?
            if cEntry.has_modified_at != 0 {
                modifiedAt = Date(timeIntervalSince1970: TimeInterval(cEntry.modified_at_unix))
            } else {
                modifiedAt = nil
            }

            let sizeBytes: Int64?
            if cEntry.has_size != 0, cEntry.size_bytes <= UInt64(Int64.max) {
                sizeBytes = Int64(cEntry.size_bytes)
            } else {
                sizeBytes = nil
            }

            output.append(
                RemoteDirectoryItem(
                    name: name,
                    fullPath: BrowserPathNormalizer.join(base: resolvedPath, child: name),
                    isDirectory: cEntry.is_directory != 0,
                    modifiedAt: modifiedAt,
                    sizeBytes: sizeBytes
                )
            )
        }

        return output
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func withOptionalCString<R>(_ value: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
        guard let value else {
            return body(nil)
        }
        return value.withCString { ptr in
            body(ptr)
        }
    }
}
