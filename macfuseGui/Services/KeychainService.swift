// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation
import LocalAuthentication
import Security

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
protocol KeychainServiceProtocol {
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func savePassword(remoteID: String, password: String) throws
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func readPassword(remoteID: String) throws -> String?
    /// Beginner note: Use allowUserInteraction=false for background reads to avoid system auth popups.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func readPassword(remoteID: String, allowUserInteraction: Bool) throws -> String?
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func deletePassword(remoteID: String) throws
}

extension KeychainServiceProtocol {
    /// Beginner note: Default read is non-interactive to prevent runtime auth popups.
    func readPassword(remoteID: String) throws -> String? {
        try readPassword(remoteID: remoteID, allowUserInteraction: false)
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class KeychainService: KeychainServiceProtocol {
    static let aggregateService = "com.visualweb.macfusegui.passwords.v2"
    static let aggregateAccount = "macfuseGui.passwords.v2"
    // Product policy: reads in app flows should stay non-interactive.
    private let allowInteractiveReads = false

    private let aggregateServiceName: String
    private let aggregateAccountName: String
    private let passwordCacheLock = NSLock()
    private var passwordCache: [String: String] = [:]
    private let aggregateLock = NSLock()

    /// Beginner note: Initializers create valid state before any other method is used.
    init(service: String = KeychainService.aggregateService, legacyServices: [String]? = nil) {
        self.aggregateServiceName = service
        self.aggregateAccountName = Self.aggregateAccount
        _ = legacyServices // Legacy keychain entries are intentionally ignored for new installs.
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func savePassword(remoteID: String, password: String) throws {
        guard password.data(using: .utf8) != nil else {
            throw AppError.keychainError("Failed to convert password to data")
        }

        try withAggregateLock {
            var aggregate = try readAggregatePasswordMap(allowUserInteraction: false) ?? [:]
            if aggregate[remoteID] != password {
                aggregate[remoteID] = password
                try upsertAggregatePasswordMap(aggregate, allowUserInteraction: true)
            }
        }
        cachePassword(password, for: remoteID)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func readPassword(remoteID: String) throws -> String? {
        try readPassword(remoteID: remoteID, allowUserInteraction: false)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func readPassword(remoteID: String, allowUserInteraction: Bool) throws -> String? {
        let allowUserInteraction = allowUserInteraction && allowInteractiveReads
        if let cached = cachedPassword(for: remoteID) {
            let trimmed = cached.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        let stored: String? = try withAggregateLock { () throws -> String? in
            guard let aggregate = try readAggregatePasswordMap(allowUserInteraction: allowUserInteraction),
                  let stored = aggregate[remoteID] else {
                return nil
            }
            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let stored {
            cachePassword(stored, for: remoteID)
            return stored
        }

        return nil
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func deletePassword(remoteID: String) throws {
        try withAggregateLock {
            if var aggregate = try readAggregatePasswordMap(allowUserInteraction: false) {
                aggregate.removeValue(forKey: remoteID)
                if aggregate.isEmpty {
                    try deleteAggregate()
                } else {
                    try upsertAggregatePasswordMap(aggregate, allowUserInteraction: false)
                }
            }
        }
        clearCachedPassword(for: remoteID)
    }

    private func readAggregatePasswordMap(allowUserInteraction: Bool) throws -> [String: String]? {
        var query = aggregateQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query = authenticationScopedQuery(query, allowUserInteraction: allowUserInteraction)

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        if status == errSecInteractionNotAllowed && !allowUserInteraction {
            return nil
        }
        guard status == errSecSuccess else {
            throw AppError.keychainError("Failed to read keychain item (\(status))")
        }
        guard let data = result as? Data else {
            throw AppError.keychainError("Invalid password data in keychain")
        }
        if data.isEmpty {
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw AppError.keychainError("Failed to decode keychain password map")
        }
    }

    private func upsertAggregatePasswordMap(_ map: [String: String], allowUserInteraction: Bool = false) throws {
        let data = try JSONEncoder().encode(map)
        try upsertAggregateData(data, allowUserInteraction: allowUserInteraction)
    }

    private func upsertAggregateData(_ data: Data, allowUserInteraction: Bool) throws {
        let query = aggregateQuery()
        let updateQuery = authenticationScopedQuery(query, allowUserInteraction: allowUserInteraction)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let insertAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        var insert = query
        insert.merge(insertAttributes) { current, _ in current }
        let insertQuery = authenticationScopedQuery(insert, allowUserInteraction: allowUserInteraction) as CFDictionary

        let insertStatus = SecItemAdd(insertQuery, nil)
        if insertStatus == errSecSuccess {
            return
        }
        if insertStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw AppError.keychainError("Failed to update keychain item (\(updateStatus))")
            }
            return
        }
        if insertStatus == errSecInteractionNotAllowed {
            throw AppError.keychainError("Keychain is locked. Unlock macOS and retry.")
        }
        throw AppError.keychainError("Failed to add keychain item (\(insertStatus))")
    }

    private func deleteAggregate() throws {
        let status = SecItemDelete(authenticationScopedQuery(aggregateQuery(), allowUserInteraction: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychainError("Failed to delete keychain item (\(status))")
        }
    }

    private func aggregateQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: aggregateServiceName,
            kSecAttrAccount as String: aggregateAccountName
        ]
    }

    private func authenticationScopedQuery(
        _ query: [String: Any],
        allowUserInteraction: Bool
    ) -> [String: Any] {
        var query = query
        let context = LAContext()
        context.interactionNotAllowed = !allowUserInteraction
        query[kSecUseAuthenticationContext as String] = context
        return query
    }

    private func withAggregateLock<T>(_ body: () throws -> T) throws -> T {
        aggregateLock.lock()
        defer { aggregateLock.unlock() }
        return try body()
    }

    private func cachedPassword(for remoteID: String) -> String? {
        passwordCacheLock.lock()
        defer { passwordCacheLock.unlock() }
        return passwordCache[remoteID]
    }

    private func cachePassword(_ password: String, for remoteID: String) {
        passwordCacheLock.lock()
        passwordCache[remoteID] = password
        passwordCacheLock.unlock()
    }

    private func clearCachedPassword(for remoteID: String) {
        passwordCacheLock.lock()
        passwordCache.removeValue(forKey: remoteID)
        passwordCacheLock.unlock()
    }
}
