// BEGINNER FILE GUIDE
// Layer: Automated test layer
// Purpose: This file verifies production behavior and protects against regressions when code changes.
// Called by: Executed by XCTest during xcodebuild test or IDE test runs.
// Calls into: Calls production code and test fixtures with deterministic assertions.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import XCTest
@testable import macfuseGui

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class KeychainServiceTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This can throw an error: callers should use do/try/catch or propagate the error.
    func testSaveReadDeletePassword() throws {
        let serviceName = "com.visualweb.macfusegui.tests.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        let remoteID = UUID().uuidString

        try keychain.savePassword(remoteID: remoteID, password: "secret-password")
        let readBack = try keychain.readPassword(remoteID: remoteID)
        XCTAssertEqual(readBack, "secret-password")

        try keychain.deletePassword(remoteID: remoteID)
        let deleted = try keychain.readPassword(remoteID: remoteID)
        XCTAssertNil(deleted)
    }

    func testReadPasswordStripsLeadingTrailingWhitespace() throws {
        let serviceName = "com.visualweb.macfusegui.tests.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        let remoteID = UUID().uuidString

        // A password pasted with a trailing newline should be stored and returned trimmed
        // so that authentication does not silently fail with unexpected whitespace.
        try keychain.savePassword(remoteID: remoteID, password: " secret\n")
        let readBack = try keychain.readPassword(remoteID: remoteID)
        XCTAssertEqual(readBack, "secret")

        try keychain.deletePassword(remoteID: remoteID)
    }

    func testReadPasswordReturnsNilForWhitespaceOnlyPassword() throws {
        let serviceName = "com.visualweb.macfusegui.tests.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        let remoteID = UUID().uuidString

        try keychain.savePassword(remoteID: remoteID, password: "   ")
        let readBack = try keychain.readPassword(remoteID: remoteID)
        XCTAssertNil(readBack)

        try keychain.deletePassword(remoteID: remoteID)
    }
}
