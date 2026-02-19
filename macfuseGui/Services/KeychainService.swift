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
    private let service: String

    /// Beginner note: Initializers create valid state before any other method is used.
    init(service: String = "com.visualweb.macfusegui.password") {
        self.service = service
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func savePassword(remoteID: String, password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw AppError.keychainError("Failed to convert password to data")
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: remoteID
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemCopyMatching(nonInteractive(query) as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(nonInteractive(query) as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw AppError.keychainError("Failed to update keychain item (\(updateStatus))")
            }
        } else if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            let insertStatus = SecItemAdd(nonInteractive(insert) as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw AppError.keychainError("Failed to add keychain item (\(insertStatus))")
            }
        } else {
            throw AppError.keychainError("Failed to query keychain (\(status))")
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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: remoteID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowUserInteraction {
            query = nonInteractive(query)
        }

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

        guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            throw AppError.keychainError("Invalid password data in keychain")
        }

        return password
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func deletePassword(remoteID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: remoteID
        ]

        let status = SecItemDelete(nonInteractive(query) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.keychainError("Failed to delete keychain item (\(status))")
        }
    }

    private func nonInteractive(_ query: [String: Any]) -> [String: Any] {
        var query = query
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        return query
    }
}
