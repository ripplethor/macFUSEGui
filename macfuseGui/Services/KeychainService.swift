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
        cachePassword(password, for: remoteID)

        aggregateLock.lock()
        defer { aggregateLock.unlock() }
        var aggregate = try readAggregatePasswordMap(allowUserInteraction: false) ?? [:]
        if aggregate[remoteID] != password {
            aggregate[remoteID] = password
            try upsertAggregatePasswordMap(aggregate, allowUserInteraction: true)
        }
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
            return cached
        }
        if let aggregate = try readAggregatePasswordMap(allowUserInteraction: allowUserInteraction),
           let stored = aggregate[remoteID],
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cachePassword(stored, for: remoteID)
            return stored
        }

        return nil
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func deletePassword(remoteID: String) throws {
        clearCachedPassword(for: remoteID)

        aggregateLock.lock()
        defer { aggregateLock.unlock() }
        if var aggregate = try readAggregatePasswordMap(allowUserInteraction: false) {
            aggregate.removeValue(forKey: remoteID)
            if aggregate.isEmpty {
                _ = deleteAggregateStatus()
            } else {
                try upsertAggregatePasswordMap(aggregate, allowUserInteraction: false)
            }
        }
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
        let lookupQuery = authenticationScopedQuery(query, allowUserInteraction: allowUserInteraction)
        let updateQuery = authenticationScopedQuery(query, allowUserInteraction: allowUserInteraction)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let insertAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemCopyMatching(lookupQuery as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw AppError.keychainError("Failed to update keychain item (\(updateStatus))")
            }
            return
        }
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(insertAttributes) { current, _ in current }
            let insertQuery = authenticationScopedQuery(insert, allowUserInteraction: allowUserInteraction) as CFDictionary

            let insertStatus = SecItemAdd(insertQuery, nil)
            guard insertStatus == errSecSuccess else {
                if insertStatus == errSecDuplicateItem {
                    let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
                    guard updateStatus == errSecSuccess else {
                        throw AppError.keychainError("Failed to update keychain item (\(updateStatus))")
                    }
                    return
                }
                throw AppError.keychainError("Failed to add keychain item (\(insertStatus))")
            }
            return
        }
        if status == errSecInteractionNotAllowed {
            let insertQueryDictionary: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: aggregateServiceName,
                kSecAttrAccount as String: aggregateAccountName,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]
            let insertQuery = authenticationScopedQuery(
                insertQueryDictionary,
                allowUserInteraction: allowUserInteraction
            )
            let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
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
            throw AppError.keychainError("Failed to add keychain item (\(insertStatus))")
        }
        throw AppError.keychainError("Failed to query keychain (\(status))")
    }

    private func deleteAggregateStatus() -> OSStatus {
        SecItemDelete(authenticationScopedQuery(aggregateQuery(), allowUserInteraction: false) as CFDictionary)
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
