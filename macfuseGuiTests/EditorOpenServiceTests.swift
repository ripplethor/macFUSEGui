// BEGINNER FILE GUIDE
// Layer: Automated test layer
// Purpose: This file verifies production behavior and protects against regressions when code changes.
// Called by: Executed by XCTest during xcodebuild test or IDE test runs.
// Calls into: Calls production code and test fixtures with deterministic assertions.
// Concurrency: Contains async functions; these can suspend and resume without blocking the calling thread.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import XCTest
@testable import macfuseGui

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class EditorOpenServiceTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    func testPreferredModeSucceedsWithDefaultVSCodePlugin() async throws {
        let context = try makeContext()
        let registry = makeRegistry(context: context)
        let runner = FakeEditorRunner(scriptedResults: [.success])
        let service = EditorOpenService(pluginRegistry: registry, runner: runner)

        let folderURL = URL(fileURLWithPath: "/tmp/editor-open-tests/project", isDirectory: true)
        let result = await service.open(
            folderURL: folderURL,
            remoteName: "Remote A",
            mode: .preferredWithFallback
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.launchedPluginID, "vscode")
        XCTAssertEqual(result.pluginResults.count, 1)
        XCTAssertEqual(result.pluginResults.first?.pluginID, "vscode")
        XCTAssertTrue(result.pluginResults.first?.success == true)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testPreferredModeFallsBackToNextActivePlugin() async throws {
        let context = try makeContext()
        let registry = makeRegistry(context: context)
        registry.setPluginActive(true, pluginID: "cursor")
        registry.setPreferredPlugin("cursor")

        // Cursor has 3 attempts; all fail. Then VS Code first attempt succeeds.
        let runner = FakeEditorRunner(scriptedResults: [.failure, .failure, .failure, .success])
        let service = EditorOpenService(pluginRegistry: registry, runner: runner)

        let folderURL = URL(fileURLWithPath: "/tmp/editor-open-tests/project", isDirectory: true)
        let result = await service.open(
            folderURL: folderURL,
            remoteName: "Remote B",
            mode: .preferredWithFallback
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.launchedPluginID, "vscode")
        XCTAssertEqual(result.pluginResults.count, 2)
        XCTAssertEqual(result.pluginResults[0].pluginID, "cursor")
        XCTAssertFalse(result.pluginResults[0].success)
        XCTAssertEqual(result.pluginResults[1].pluginID, "vscode")
        XCTAssertTrue(result.pluginResults[1].success)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testExplicitModeDoesNotFallbackToOtherPlugins() async throws {
        let context = try makeContext()
        let registry = makeRegistry(context: context)
        registry.setPluginActive(true, pluginID: "cursor")

        // Cursor has 3 attempts; all fail.
        let runner = FakeEditorRunner(scriptedResults: [.failure, .failure, .failure])
        let service = EditorOpenService(pluginRegistry: registry, runner: runner)

        let folderURL = URL(fileURLWithPath: "/tmp/editor-open-tests/project", isDirectory: true)
        let result = await service.open(
            folderURL: folderURL,
            remoteName: "Remote C",
            mode: .explicit(pluginID: "cursor")
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.pluginResults.count, 1)
        XCTAssertEqual(result.pluginResults.first?.pluginID, "cursor")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testFolderPlaceholderSubstitutionPreservesSpaces() async throws {
        let context = try makeContext()
        let registry = makeRegistry(context: context)
        let runner = FakeEditorRunner(scriptedResults: [.success])
        let service = EditorOpenService(pluginRegistry: registry, runner: runner)

        let folderPath = "/tmp/editor-open-tests/Project With Spaces"
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)

        _ = await service.open(
            folderURL: folderURL,
            remoteName: "Remote D",
            mode: .explicit(pluginID: "vscode")
        )

        let invocations = await runner.invocations()
        let firstInvocation = try XCTUnwrap(invocations.first)
        XCTAssertTrue(firstInvocation.arguments.contains(folderPath))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testStrictAllowlistRejectsDisallowedExecutableManifest() async throws {
        let context = try makeContext()
        let pluginsDirectory = try createPluginsDirectory(appSupportDirectory: context.appSupportDirectory)

        let invalidManifest = """
        {
          "id": "blocked",
          "displayName": "Blocked",
          "priority": 11,
          "defaultEnabled": true,
          "launchAttempts": [
            {
              "label": "blocked",
              "executable": "/bin/sh",
              "arguments": ["-c", "echo hi", "{folderPath}"],
              "timeoutSeconds": 3
            }
          ]
        }
        """
        try invalidManifest.write(
            to: pluginsDirectory.appendingPathComponent("blocked.json"),
            atomically: true,
            encoding: .utf8
        )

        let registry = makeRegistry(context: context)
        XCTAssertNil(registry.plugin(id: "blocked"))

        let runner = FakeEditorRunner(scriptedResults: [])
        let service = EditorOpenService(pluginRegistry: registry, runner: runner)
        let result = await service.open(
            folderURL: URL(fileURLWithPath: "/tmp/editor-open-tests/project", isDirectory: true),
            remoteName: "Remote E",
            mode: .explicit(pluginID: "blocked")
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.pluginResults.isEmpty)
    }

    private func makeRegistry(context: (appSupportDirectory: URL, defaults: UserDefaults)) -> EditorPluginRegistry {
        EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )
    }

    /// Beginner note: This helper centralizes temporary context setup for open-service tests.
    private func makeContext() throws -> (appSupportDirectory: URL, defaults: UserDefaults) {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("macfusegui-editor-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let suiteName = "com.visualweb.macfusegui.tests.editor-open-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        return (tempRoot, defaults)
    }

    private func createPluginsDirectory(appSupportDirectory: URL) throws -> URL {
        let directory = appSupportDirectory
            .appendingPathComponent("macfuseGui", isDirectory: true)
            .appendingPathComponent("editor-plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// Beginner note: Scripted process runner for deterministic editor-open tests.
private actor FakeEditorRunner: ProcessRunning {
    struct Invocation: Sendable {
        let executable: String
        let arguments: [String]
        let timeout: TimeInterval
    }

    enum ScriptedResult: Sendable {
        case success
        case failure
    }

    private var scriptedResults: [ScriptedResult]
    private var recordedInvocations: [Invocation] = []

    init(scriptedResults: [ScriptedResult]) {
        self.scriptedResults = scriptedResults
    }

    func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval,
        standardInput: String?
    ) async throws -> ProcessResult {
        recordedInvocations.append(
            Invocation(
                executable: executable,
                arguments: arguments,
                timeout: timeout
            )
        )

        let nextResult: ScriptedResult = scriptedResults.isEmpty ? .failure : scriptedResults.removeFirst()

        switch nextResult {
        case .success:
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "",
                exitCode: 0,
                timedOut: false,
                duration: 0.01
            )

        case .failure:
            return ProcessResult(
                executable: executable,
                arguments: arguments,
                stdout: "",
                stderr: "failed",
                exitCode: 1,
                timedOut: false,
                duration: 0.01
            )
        }
    }

    func invocations() -> [Invocation] {
        recordedInvocations
    }
}
