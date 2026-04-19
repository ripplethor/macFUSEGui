// BEGINNER FILE GUIDE
// Layer: Data model layer
// Purpose: This file defines value types and enums shared across services, view models, and views.
// Called by: Constructed and consumed throughout the app where typed state is needed.
// Calls into: Usually has no runtime side effects; mostly pure data definitions.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
// Case order determines display order in SwiftUI pickers; keep explicit key-file
// auth first, then system OpenSSH auth, then password.
enum RemoteAuth: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case privateKey
    case systemSSH
    case password

    // Stable identifier used by SwiftUI Picker/ForEach.
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .privateKey:
            return L10n.tr("SSH Private Key")
        case .systemSSH:
            return L10n.tr("System SSH")
        case .password:
            return L10n.tr("Password")
        }
    }

    var systemImageName: String {
        switch self {
        case .privateKey:
            return "key.fill"
        case .systemSSH:
            return "terminal"
        case .password:
            return "lock.fill"
        }
    }
}
