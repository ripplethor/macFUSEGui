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
struct RemoteConfig: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var displayName: String
    var host: String
    var port: Int
    var username: String
    var authMode: RemoteAuth
    var privateKeyPath: String?
    var remoteDirectory: String
    var localMountPoint: String
    var isFavorite: Bool
    var autoConnectOnLaunch: Bool
    var disableLocalCaches: Bool
    // Persisted per-remote path memory; normalization and limits are enforced by RemotesViewModel.
    var favoriteRemoteDirectories: [String]
    var recentRemoteDirectories: [String]

    // Hard caps prevent unbounded persisted growth if callers bypass view-model normalization.
    static let favoriteDirectoryLimit = 20
    static let recentDirectoryLimit = 15

    static func cappedPathMemory(_ paths: [String], limit: Int) -> [String] {
        guard limit > 0 else {
            return []
        }
        guard paths.count > limit else {
            return paths
        }
        return Array(paths.prefix(limit))
    }

    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case host
        case port
        case username
        case authMode
        case privateKeyPath
        case remoteDirectory
        case localMountPoint
        case isFavorite
        case autoConnectOnLaunch
        case disableLocalCaches
        case favoriteRemoteDirectories
        case recentRemoteDirectories
    }

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        port: Int = 22,
        username: String,
        authMode: RemoteAuth,
        privateKeyPath: String? = nil,
        remoteDirectory: String,
        localMountPoint: String,
        isFavorite: Bool = false,
        autoConnectOnLaunch: Bool = false,
        disableLocalCaches: Bool = true,
        favoriteRemoteDirectories: [String] = [],
        recentRemoteDirectories: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.host = host
        self.port = port
        self.username = username
        self.authMode = authMode
        self.privateKeyPath = privateKeyPath
        self.remoteDirectory = remoteDirectory
        self.localMountPoint = localMountPoint
        self.isFavorite = isFavorite
        self.autoConnectOnLaunch = autoConnectOnLaunch
        self.disableLocalCaches = disableLocalCaches
        self.favoriteRemoteDirectories = Self.cappedPathMemory(
            favoriteRemoteDirectories,
            limit: Self.favoriteDirectoryLimit
        )
        self.recentRemoteDirectories = Self.cappedPathMemory(
            recentRemoteDirectories,
            limit: Self.recentDirectoryLimit
        )
    }

    /// Beginner note: Initializers create valid state before any other method is used.
    /// Decoder defaults keep older remotes.json files loadable when fields were added later.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        authMode = try container.decodeIfPresent(RemoteAuth.self, forKey: .authMode) ?? .privateKey
        privateKeyPath = try container.decodeIfPresent(String.self, forKey: .privateKeyPath)
        remoteDirectory = try container.decodeIfPresent(String.self, forKey: .remoteDirectory) ?? "/"
        localMountPoint = try container.decodeIfPresent(String.self, forKey: .localMountPoint) ?? ""
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        autoConnectOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoConnectOnLaunch) ?? false
        disableLocalCaches = try container.decodeIfPresent(Bool.self, forKey: .disableLocalCaches) ?? true
        let decodedFavorites = try container.decodeIfPresent([String].self, forKey: .favoriteRemoteDirectories) ?? []
        let decodedRecents = try container.decodeIfPresent([String].self, forKey: .recentRemoteDirectories) ?? []
        favoriteRemoteDirectories = Self.cappedPathMemory(decodedFavorites, limit: Self.favoriteDirectoryLimit)
        recentRemoteDirectories = Self.cappedPathMemory(decodedRecents, limit: Self.recentDirectoryLimit)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(authMode, forKey: .authMode)
        try container.encodeIfPresent(privateKeyPath, forKey: .privateKeyPath)
        try container.encode(remoteDirectory, forKey: .remoteDirectory)
        try container.encode(localMountPoint, forKey: .localMountPoint)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(autoConnectOnLaunch, forKey: .autoConnectOnLaunch)
        try container.encode(disableLocalCaches, forKey: .disableLocalCaches)
        try container.encode(favoriteRemoteDirectories, forKey: .favoriteRemoteDirectories)
        try container.encode(recentRemoteDirectories, forKey: .recentRemoteDirectories)
    }

    static let sample = RemoteConfig(
        displayName: "Example Server",
        host: "example.com",
        username: "dev",
        authMode: .privateKey,
        privateKeyPath: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh/id_ed25519")
            .path,
        remoteDirectory: "/srv/data",
        localMountPoint: "/Volumes/example",
        isFavorite: false,
        autoConnectOnLaunch: false,
        disableLocalCaches: true,
        favoriteRemoteDirectories: [],
        recentRemoteDirectories: []
    )
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct RemoteDraft: Equatable, Sendable {
    var id: UUID?
    var displayName: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var authMode: RemoteAuth = .privateKey
    var privateKeyPath: String = ""
    // Transient in-memory value used by editor/test flows. Never persisted to remotes.json.
    var password: String = ""
    var remoteDirectory: String = "/"
    var localMountPoint: String = ""
    var isFavorite: Bool = false
    var autoConnectOnLaunch: Bool = false
    var disableLocalCaches: Bool = true
    var favoriteRemoteDirectories: [String] = []
    var recentRemoteDirectories: [String] = []

    static let empty = RemoteDraft()

    var isValid: Bool {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrivateKeyPath = privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDisplayName.isEmpty,
              !trimmedHost.isEmpty,
              !trimmedUsername.isEmpty,
              (1...65_535).contains(port) else {
            return false
        }

        if authMode == .privateKey {
            return !trimmedPrivateKeyPath.isEmpty
        }

        return true
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func asRemoteConfig() -> RemoteConfig {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrivateKeyPath = privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRemoteDirectory = remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocalMountPoint = localMountPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let validatedPort = (1...65_535).contains(port) ? port : 22
        let cappedFavorites = RemoteConfig.cappedPathMemory(
            favoriteRemoteDirectories,
            limit: RemoteConfig.favoriteDirectoryLimit
        )
        let cappedRecents = RemoteConfig.cappedPathMemory(
            recentRemoteDirectories,
            limit: RemoteConfig.recentDirectoryLimit
        )

        return RemoteConfig(
            id: id ?? UUID(),
            displayName: trimmedDisplayName,
            host: trimmedHost,
            port: validatedPort,
            username: trimmedUsername,
            authMode: authMode,
            privateKeyPath: trimmedPrivateKeyPath.isEmpty ? nil : trimmedPrivateKeyPath,
            remoteDirectory: trimmedRemoteDirectory,
            localMountPoint: trimmedLocalMountPoint,
            isFavorite: isFavorite,
            autoConnectOnLaunch: autoConnectOnLaunch,
            disableLocalCaches: disableLocalCaches,
            favoriteRemoteDirectories: cappedFavorites,
            recentRemoteDirectories: cappedRecents
        )
    }
}

extension RemoteDraft {
    /// Beginner note: Initializers create valid state before any other method is used.
    init(remote: RemoteConfig, password: String = "") {
        self.id = remote.id
        self.displayName = remote.displayName
        self.host = remote.host
        self.port = remote.port
        self.username = remote.username
        self.authMode = remote.authMode
        self.privateKeyPath = remote.privateKeyPath ?? ""
        self.password = password
        self.remoteDirectory = remote.remoteDirectory
        self.localMountPoint = remote.localMountPoint
        self.isFavorite = remote.isFavorite
        self.autoConnectOnLaunch = remote.autoConnectOnLaunch
        self.disableLocalCaches = remote.disableLocalCaches
        self.favoriteRemoteDirectories = remote.favoriteRemoteDirectories
        self.recentRemoteDirectories = remote.recentRemoteDirectories
    }
}
