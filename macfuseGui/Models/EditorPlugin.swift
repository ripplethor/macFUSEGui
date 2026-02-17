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
enum EditorPluginSource: String, Codable, Equatable, Sendable {
    case builtIn
    case external
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct EditorLaunchAttemptDefinition: Codable, Equatable, Sendable {
    var label: String
    var executable: String
    var arguments: [String]
    var timeoutSeconds: TimeInterval

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        label: String,
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) {
        self.label = label
        self.executable = executable
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct EditorPluginDefinition: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var priority: Int
    var defaultEnabled: Bool
    var launchAttempts: [EditorLaunchAttemptDefinition]
    var source: EditorPluginSource

    // Projected runtime state used by UI/menu.
    var isActive: Bool
    var isPreferred: Bool

    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case priority
        case defaultEnabled
        case launchAttempts
        case source
        case isActive
        case isPreferred
    }

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        id: String,
        displayName: String,
        priority: Int,
        defaultEnabled: Bool,
        launchAttempts: [EditorLaunchAttemptDefinition],
        source: EditorPluginSource,
        isActive: Bool = false,
        isPreferred: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.priority = priority
        self.defaultEnabled = defaultEnabled
        self.launchAttempts = launchAttempts
        self.source = source
        self.isActive = isActive
        self.isPreferred = isPreferred
    }

    /// Beginner note: Initializers create valid state before any other method is used.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        priority = try container.decode(Int.self, forKey: .priority)
        defaultEnabled = try container.decode(Bool.self, forKey: .defaultEnabled)
        launchAttempts = try container.decode([EditorLaunchAttemptDefinition].self, forKey: .launchAttempts)
        source = try container.decodeIfPresent(EditorPluginSource.self, forKey: .source) ?? .external
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isPreferred = try container.decodeIfPresent(Bool.self, forKey: .isPreferred) ?? false
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(priority, forKey: .priority)
        try container.encode(defaultEnabled, forKey: .defaultEnabled)
        try container.encode(launchAttempts, forKey: .launchAttempts)
        try container.encode(source, forKey: .source)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(isPreferred, forKey: .isPreferred)
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct EditorPluginLoadIssue: Codable, Equatable, Sendable {
    var file: String
    var reason: String

    /// Beginner note: Initializers create valid state before any other method is used.
    init(file: String, reason: String) {
        self.file = file
        self.reason = reason
    }
}
