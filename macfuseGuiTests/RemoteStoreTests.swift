// BEGINNER FILE GUIDE
// Layer: Automated test layer
// Purpose: This file verifies production behavior and protects against regressions when code changes.
// Called by: Executed by XCTest during xcodebuild test or IDE test runs.
// Calls into: Calls production code and test fixtures with deterministic assertions.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import XCTest
@testable import macfuseGui

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class RemoteStoreTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func testSaveAndLoadRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macfusegui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("remotes.json")
        let store = JSONRemoteStore(storageURL: storeURL)

        let remote = RemoteConfig(
            displayName: "Test",
            host: "example.com",
            port: 22,
            username: "dev",
            authMode: .privateKey,
            privateKeyPath: "/Users/test/.ssh/id_ed25519",
            remoteDirectory: "/srv",
            localMountPoint: tempDir.path,
            isFavorite: true,
            autoConnectOnLaunch: true,
            disableLocalCaches: false,
            favoriteRemoteDirectories: ["/srv", "/srv/projects"],
            recentRemoteDirectories: ["/srv/projects", "/srv"]
        )

        try store.save([remote])
        let loaded = try store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.displayName, "Test")
        XCTAssertEqual(loaded.first?.host, "example.com")
        XCTAssertEqual(loaded.first?.isFavorite, true)
        XCTAssertEqual(loaded.first?.autoConnectOnLaunch, true)
        XCTAssertEqual(loaded.first?.disableLocalCaches, false)
        XCTAssertEqual(loaded.first?.favoriteRemoteDirectories, ["/srv", "/srv/projects"])
        XCTAssertEqual(loaded.first?.recentRemoteDirectories, ["/srv/projects", "/srv"])

        let rawJSON = try String(contentsOf: storeURL)
        XCTAssertFalse(rawJSON.localizedCaseInsensitiveContains("password"))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func testLoadLegacyJSONDefaultsNewFields() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macfusegui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("remotes.json")
        let store = JSONRemoteStore(storageURL: storeURL)
        let remoteID = UUID()

        let legacyJSON = """
        [
          {
            "id": "\(remoteID.uuidString)",
            "displayName": "Legacy Remote",
            "host": "legacy.example.com",
            "port": 22,
            "username": "legacy-user",
            "authMode": "privateKey",
            "privateKeyPath": "/Users/test/.ssh/id_ed25519",
            "remoteDirectory": "/legacy",
            "localMountPoint": "/tmp/legacy-mount"
          }
        ]
        """

        try legacyJSON.write(to: storeURL, atomically: true, encoding: .utf8)
        let loaded = try store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, remoteID)
        XCTAssertEqual(loaded[0].displayName, "Legacy Remote")
        XCTAssertFalse(loaded[0].isFavorite)
        XCTAssertFalse(loaded[0].autoConnectOnLaunch)
        XCTAssertTrue(loaded[0].disableLocalCaches)
        XCTAssertEqual(loaded[0].favoriteRemoteDirectories, [])
        XCTAssertEqual(loaded[0].recentRemoteDirectories, [])
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func testLoadCorruptJSONSurfacesCorruptFileError() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macfusegui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("remotes.json")
        let store = JSONRemoteStore(storageURL: storeURL)
        try "{ not valid json".write(to: storeURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.load()) { error in
            guard let appError = error as? AppError else {
                XCTFail("Expected AppError, got \(type(of: error))")
                return
            }
            switch appError {
            case .persistenceError(let message):
                XCTAssertTrue(message.contains("Corrupt remotes file"))
            default:
                XCTFail("Expected persistenceError, got \(appError)")
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func testDeleteMissingRemoteThrowsNotFound() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("macfusegui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("remotes.json")
        let store = JSONRemoteStore(storageURL: storeURL)
        try store.save([])

        XCTAssertThrowsError(try store.delete(id: UUID())) { error in
            guard let appError = error as? AppError else {
                XCTFail("Expected AppError, got \(type(of: error))")
                return
            }
            switch appError {
            case .persistenceError(let message):
                XCTAssertTrue(message.contains("was not found"))
            default:
                XCTFail("Expected persistenceError, got \(appError)")
            }
        }
    }
}
