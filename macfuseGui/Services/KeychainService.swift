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
    static let currentService = "com.visualweb.macfusegui.password.v2"
    static let legacyService = "com.visualweb.macfusegui.password"
    // Prevent background connect flows from touching legacy items that may trigger macOS auth UI.
    private let allowLegacyFallbackForNonInteractiveReads = false

    private let service: String
    private let legacyServices: [String]

    /// Beginner note: Initializers create valid state before any other method is used.
    init(service: String = KeychainService.currentService, legacyServices: [String]? = nil) {
        self.service = service
        if let legacyServices {
            self.legacyServices = legacyServices.filter { $0 != service }
        } else if service == Self.currentService {
            self.legacyServices = [Self.legacyService]
        } else {
            self.legacyServices = []
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func savePassword(remoteID: String, password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw AppError.keychainError("Failed to convert password to data")
        }

        try upsertPassword(remoteID: remoteID, passwordData: passwordData, service: service)

        for legacyService in legacyServices {
            _ = deletePasswordStatus(remoteID: remoteID, service: legacyService)
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
        if let currentPassword = try readPasswordValue(
            remoteID: remoteID,
            service: service,
            allowUserInteraction: allowUserInteraction
        ) {
            return currentPassword
        }

        if !allowUserInteraction && !allowLegacyFallbackForNonInteractiveReads {
            return nil
        }

        for legacyService in legacyServices {
            if let legacyPassword = try readPasswordValue(
                remoteID: remoteID,
                service: legacyService,
                allowUserInteraction: allowUserInteraction
            ) {
                if let passwordData = legacyPassword.data(using: .utf8) {
                    _ = try? upsertPassword(remoteID: remoteID, passwordData: passwordData, service: service)
                }
                _ = deletePasswordStatus(remoteID: remoteID, service: legacyService)
                return legacyPassword
            }
        }

        return nil
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func deletePassword(remoteID: String) throws {
        var firstUnexpectedStatus: OSStatus?
        for targetService in [service] + legacyServices {
            let status = deletePasswordStatus(remoteID: remoteID, service: targetService)
            if status == errSecSuccess || status == errSecItemNotFound {
                continue
            }
            if firstUnexpectedStatus == nil {
                firstUnexpectedStatus = status
            }
        }
        if let status = firstUnexpectedStatus {
            throw AppError.keychainError("Failed to delete keychain item (\(status))")
        }
    }

    private func upsertPassword(remoteID: String, passwordData: Data, service: String) throws {
        let query = itemQuery(remoteID: remoteID, service: service)
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
            return
        }
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            let insertStatus = SecItemAdd(nonInteractive(insert) as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw AppError.keychainError("Failed to add keychain item (\(insertStatus))")
            }
            return
        }
        if status == errSecInteractionNotAllowed {
            let insertQuery = nonInteractive([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: remoteID,
                kSecValueData as String: passwordData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ])
            let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            if insertStatus == errSecSuccess {
                return
            }
            if insertStatus == errSecDuplicateItem {
                throw AppError.keychainError("Failed to update keychain item (\(status))")
            }
            throw AppError.keychainError("Failed to add keychain item (\(insertStatus))")
        }
        throw AppError.keychainError("Failed to query keychain (\(status))")
    }

    private func readPasswordValue(
        remoteID: String,
        service: String,
        allowUserInteraction: Bool
    ) throws -> String? {
        var query = itemQuery(remoteID: remoteID, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
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

    private func deletePasswordStatus(remoteID: String, service: String) -> OSStatus {
        SecItemDelete(nonInteractive(itemQuery(remoteID: remoteID, service: service)) as CFDictionary)
    }

    private func itemQuery(remoteID: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: remoteID
        ]
    }

    private func nonInteractive(_ query: [String: Any]) -> [String: Any] {
        var query = query
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        return query
    }
}
