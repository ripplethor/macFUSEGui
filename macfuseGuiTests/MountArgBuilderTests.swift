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
final class MountArgBuilderTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    func testBuildsPrivateKeyArguments() {
        let builder = MountCommandBuilder(redactionService: RedactionService())
        let remote = RemoteConfig(
            displayName: "Server",
            host: "example.com",
            port: 2202,
            username: "dev",
            authMode: .privateKey,
            privateKeyPath: "/Users/dev/.ssh/id_ed25519",
            remoteDirectory: "/srv",
            localMountPoint: "/Volumes/server"
        )

        let command = builder.build(sshfsPath: "/opt/homebrew/bin/sshfs", remote: remote)

        XCTAssertEqual(command.executable, "/opt/homebrew/bin/sshfs")
        XCTAssertTrue(command.arguments.contains("-p"))
        XCTAssertTrue(command.arguments.contains("2202"))
        XCTAssertTrue(command.arguments.contains("dev@example.com:/srv"))
        XCTAssertTrue(command.arguments.contains("/Volumes/server"))
        XCTAssertTrue(command.arguments.joined(separator: " ").contains("IdentityFile=/Users/dev/.ssh/id_ed25519"))
        XCTAssertTrue(command.arguments.joined(separator: " ").contains("volname=Server - srv"))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRedactsPasswordEnvironmentValues() {
        let builder = MountCommandBuilder(redactionService: RedactionService())
        let remote = RemoteConfig(
            displayName: "Server",
            host: "example.com",
            port: 22,
            username: "dev",
            authMode: .password,
            privateKeyPath: nil,
            remoteDirectory: "/srv",
            localMountPoint: "/Volumes/server"
        )

        let command = builder.build(
            sshfsPath: "/opt/homebrew/bin/sshfs",
            remote: remote,
            passwordEnvironment: ["MACFUSEGUI_ASKPASS_PASSWORD": "super-secret"]
        )

        XCTAssertFalse(command.redactedCommand.contains("super-secret"))
        XCTAssertTrue(command.redactedCommand.contains("<redacted>") || !command.redactedCommand.contains("super-secret"))
        XCTAssertTrue(command.redactedCommand.contains("ServerAliveInterval=15"))
        XCTAssertTrue(command.redactedCommand.contains("dev@example.com:/srv"))
        XCTAssertTrue(command.arguments.joined(separator: " ").contains("volname=Server - srv"))
        XCTAssertFalse(command.arguments.joined(separator: " ").contains("PreferredAuthentications="))
        XCTAssertFalse(command.arguments.joined(separator: " ").contains("KbdInteractiveAuthentication="))
        XCTAssertFalse(command.arguments.joined(separator: " ").contains("PasswordAuthentication="))
        XCTAssertFalse(command.arguments.joined(separator: " ").contains("PubkeyAuthentication="))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testNormalizesWindowsRemotePathForSSHFS() {
        let builder = MountCommandBuilder(redactionService: RedactionService())
        let remote = RemoteConfig(
            displayName: "Windows Host",
            host: "192.168.1.55",
            port: 22,
            username: "philip",
            authMode: .password,
            privateKeyPath: nil,
            remoteDirectory: "C:\\Users\\philip",
            localMountPoint: "/Volumes/windows-home"
        )

        let command = builder.build(sshfsPath: "/opt/homebrew/bin/sshfs", remote: remote)
        XCTAssertTrue(command.arguments.contains("philip@192.168.1.55:/C:/Users/philip"))
        XCTAssertTrue(command.arguments.joined(separator: " ").contains("volname=Windows Host - philip"))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testBuildEscapesCommaInIdentityFileAndUsesPerOptionFlags() {
        let builder = MountCommandBuilder(redactionService: RedactionService())
        let remote = RemoteConfig(
            displayName: "Server",
            host: "example.com",
            port: 22,
            username: "dev",
            authMode: .privateKey,
            privateKeyPath: "/Users/dev/.ssh/id,ed25519",
            remoteDirectory: "/srv",
            localMountPoint: "/Volumes/server"
        )

        let command = builder.build(sshfsPath: "/opt/homebrew/bin/sshfs", remote: remote)
        let optionFlagCount = command.arguments.filter { $0 == "-o" }.count

        XCTAssertEqual(optionFlagCount, 11)
        XCTAssertTrue(command.arguments.contains("IdentityFile=/Users/dev/.ssh/id\\,ed25519"))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testBracketedIPv6HostPassesThroughUnchangedInSourceArgument() {
        let builder = MountCommandBuilder(redactionService: RedactionService())
        // Validation requires IPv6 addresses to be pre-bracketed ([::1]).
        // The builder must preserve that format so sshfs can parse host:path correctly.
        let remote = RemoteConfig(
            displayName: "IPv6 Server",
            host: "[::1]",
            port: 22,
            username: "dev",
            authMode: .privateKey,
            privateKeyPath: "/Users/dev/.ssh/id_ed25519",
            remoteDirectory: "/srv",
            localMountPoint: "/Volumes/ipv6-server"
        )

        let command = builder.build(sshfsPath: "/opt/homebrew/bin/sshfs", remote: remote)
        XCTAssertTrue(command.arguments.contains("dev@[::1]:/srv"))
    }

    func testBracketedIPv6FullAddressPassesThroughUnchanged() {
        let builder = MountCommandBuilder(redactionService: RedactionService())
        let remote = RemoteConfig(
            displayName: "IPv6 Server",
            host: "[2001:db8::1]",
            port: 22,
            username: "alice",
            authMode: .password,
            privateKeyPath: nil,
            remoteDirectory: "/home/alice",
            localMountPoint: "/Volumes/ipv6-remote"
        )

        let command = builder.build(sshfsPath: "/opt/homebrew/bin/sshfs", remote: remote)
        XCTAssertTrue(command.arguments.contains("alice@[2001:db8::1]:/home/alice"))
    }

    func testPlainHostnameIsNotBracketed() {
        let builder = MountCommandBuilder(redactionService: RedactionService())
        let remote = RemoteConfig(
            displayName: "Server",
            host: "example.com",
            port: 22,
            username: "dev",
            authMode: .password,
            privateKeyPath: nil,
            remoteDirectory: "/srv",
            localMountPoint: "/Volumes/server"
        )

        let command = builder.build(sshfsPath: "/opt/homebrew/bin/sshfs", remote: remote)
        XCTAssertTrue(command.arguments.contains("dev@example.com:/srv"))
        XCTAssertFalse(command.arguments.contains("[example.com]"))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testFallbackVolumeNameIncludesUniqueSeedWhenDisplayAndHostAreNonAscii() {
        let builder = MountCommandBuilder(redactionService: RedactionService())
        let remote = RemoteConfig(
            displayName: "",
            host: "服务器",
            port: 2222,
            username: "dev",
            authMode: .password,
            privateKeyPath: nil,
            remoteDirectory: "/",
            localMountPoint: "/Volumes/server"
        )

        let command = builder.build(sshfsPath: "/opt/homebrew/bin/sshfs", remote: remote)
        let volumeOption = command.arguments.first { $0.hasPrefix("volname=") }

        XCTAssertNotNil(volumeOption)
        XCTAssertNotEqual(volumeOption, "volname=macfuseGui")
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class RedactionServiceTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRedactPrefersLongerSecretsBeforeSubstrings() {
        let service = RedactionService()

        let result = service.redact("token=mypassword", secrets: ["pass", "mypassword"])

        XCTAssertEqual(result, "token=<redacted>")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRedactDoesNotCorruptReplacementWhenOtherSecretsMatchTokenText() {
        let service = RedactionService()

        let result = service.redact("token=abc", secrets: ["abc", "redact"])

        XCTAssertEqual(result, "token=<redacted>")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRedactedCommandRedactsBeforeDisplayQuoting() {
        let service = RedactionService()

        let command = service.redactedCommand(
            executable: "/bin/echo",
            arguments: ["pa\"ss", "ok"],
            secrets: ["pa\"ss"]
        )

        XCTAssertTrue(command.contains("<redacted>"))
        XCTAssertFalse(command.contains("pa\\\"ss"))
        XCTAssertFalse(command.contains("pa\"ss"))
    }

    /// Beginner note: Redaction is literal and case-sensitive by design.
    func testRedactionRemainsCaseSensitive() {
        let service = RedactionService()

        let result = service.redact("token=MyPass123", secrets: ["mypass123"])

        XCTAssertEqual(result, "token=MyPass123")
    }
}
