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
final class EditorPluginRegistryTests: XCTestCase {
    /// Beginner note: This method is one step in the feature workflow for this file.
    func testBuiltinsLoadWithVSCodePreferredAndOnlyDefaultActive() throws {
        let context = try makeContext()

        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        let ids = Set(registry.plugins.map(\.id))
        XCTAssertTrue(ids.contains("vscode"))
        XCTAssertTrue(ids.contains("vscodium"))
        XCTAssertTrue(ids.contains("cursor"))
        XCTAssertTrue(ids.contains("zed"))

        XCTAssertEqual(registry.preferredPluginID, "vscode")

        let activeIDs = Set(registry.activePluginsInPriorityOrder().map(\.id))
        XCTAssertEqual(activeIDs, Set(["vscode"]))

        let vscode = try XCTUnwrap(registry.plugin(id: "vscode"))
        XCTAssertTrue(vscode.isActive)
        XCTAssertTrue(vscode.isPreferred)

        XCTAssertFalse(try XCTUnwrap(registry.plugin(id: "cursor")).isActive)
        XCTAssertFalse(try XCTUnwrap(registry.plugin(id: "zed")).isActive)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testPluginDirectoryScaffoldIsCreatedForDiscoverability() throws {
        let context = try makeContext()

        _ = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        let pluginsDir = context.appSupportDirectory
            .appendingPathComponent("macfuseGui", isDirectory: true)
            .appendingPathComponent("editor-plugins", isDirectory: true)
        let readmePath = pluginsDir.appendingPathComponent("README.md").path
        let examplesTemplatePath = pluginsDir
            .appendingPathComponent("examples", isDirectory: true)
            .appendingPathComponent("custom-editor.json.template")
            .path
        let builtinVSCodePath = pluginsDir
            .appendingPathComponent("builtin-reference", isDirectory: true)
            .appendingPathComponent("vscode.json")
            .path

        XCTAssertTrue(FileManager.default.fileExists(atPath: readmePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: examplesTemplatePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: builtinVSCodePath))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testBundledBuiltInPluginDirectoriesExist() throws {
        let bundledRoot = try XCTUnwrap(
            Bundle.main.url(forResource: "EditorPlugins", withExtension: nil),
            "Expected bundled EditorPlugins folder in app resources."
        )
        let expectedPluginIDs = ["vscode", "vscodium", "cursor", "zed"]

        for pluginID in expectedPluginIDs {
            let manifestURL = bundledRoot
                .appendingPathComponent(pluginID, isDirectory: true)
                .appendingPathComponent("plugin.json")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: manifestURL.path),
                "Missing bundled manifest for \(pluginID): \(manifestURL.path)"
            )
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testBundledVSCodeManifestDoesNotContainVSCodiumAttempts() throws {
        let bundledRoot = try XCTUnwrap(
            Bundle.main.url(forResource: "EditorPlugins", withExtension: nil),
            "Expected bundled EditorPlugins folder in app resources."
        )
        let manifestURL = bundledRoot
            .appendingPathComponent("vscode", isDirectory: true)
            .appendingPathComponent("plugin.json")
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)

        XCTAssertFalse(manifestText.contains("com.vscodium"))
        XCTAssertFalse(manifestText.contains("\"VSCodium\""))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testManifestFileURLResolvesBundledManifestForBuiltInPlugin() throws {
        let context = try makeContext()
        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        let manifestURL = try XCTUnwrap(registry.manifestFileURL(for: "vscode"))
        XCTAssertEqual(manifestURL.lastPathComponent, "plugin.json")
        XCTAssertTrue(manifestURL.path.contains("/EditorPlugins/vscode/"))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testCreateNewPluginTemplateAndResolveExternalManifestURL() throws {
        let context = try makeContext()
        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        let createdURL = try registry.createExternalPluginTemplateFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdURL.path))

        registry.reloadCatalog()

        let createdPluginID = createdURL.deletingPathExtension().lastPathComponent
        XCTAssertNotNil(registry.plugin(id: createdPluginID))

        let resolvedURL = try XCTUnwrap(registry.manifestFileURL(for: createdPluginID))
        XCTAssertEqual(
            resolvedURL.resolvingSymlinksInPath().path,
            createdURL.resolvingSymlinksInPath().path
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testActivationOverridesAndPreferredPersistAcrossReload() throws {
        let context = try makeContext()

        let first = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )
        first.setPluginActive(true, pluginID: "cursor")
        first.setPreferredPlugin("cursor")

        let second = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        XCTAssertTrue(try XCTUnwrap(second.plugin(id: "cursor")).isActive)
        XCTAssertEqual(second.preferredPluginID, "cursor")
        XCTAssertTrue(try XCTUnwrap(second.plugin(id: "cursor")).isPreferred)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testPreferredAutoRehomesWhenPreferredPluginDisabled() throws {
        let context = try makeContext()
        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        registry.setPluginActive(true, pluginID: "cursor")
        registry.setPreferredPlugin("cursor")
        XCTAssertEqual(registry.preferredPluginID, "cursor")

        registry.setPluginActive(false, pluginID: "cursor")
        XCTAssertEqual(registry.preferredPluginID, "vscode")
        XCTAssertTrue(try XCTUnwrap(registry.plugin(id: "vscode")).isPreferred)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testInvalidExternalManifestIsRejectedAndSurfaced() throws {
        let context = try makeContext()
        let pluginsDirectory = try createPluginsDirectory(appSupportDirectory: context.appSupportDirectory)

        let invalidManifest = """
        {
          "id": "unsafe-plugin",
          "displayName": "Unsafe",
          "priority": 50,
          "defaultEnabled": false,
          "launchAttempts": [
            {
              "label": "bad",
              "executable": "/bin/sh",
              "arguments": ["-c", "echo hi", "{folderPath}"],
              "timeoutSeconds": 3
            }
          ]
        }
        """
        try invalidManifest.write(
            to: pluginsDirectory.appendingPathComponent("unsafe.json"),
            atomically: true,
            encoding: .utf8
        )

        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        XCTAssertNil(registry.plugin(id: "unsafe-plugin"))
        XCTAssertTrue(registry.loadIssues.contains(where: { $0.file == "unsafe.json" }))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testEnvExecutableWithShellArgumentsIsRejected() throws {
        let context = try makeContext()
        let pluginsDirectory = try createPluginsDirectory(appSupportDirectory: context.appSupportDirectory)

        let maliciousManifest = """
        {
          "id": "env-exploit",
          "displayName": "Exploit",
          "priority": 50,
          "defaultEnabled": false,
          "launchAttempts": [
            {
              "label": "exploit",
              "executable": "/usr/bin/env",
              "arguments": ["sh", "-c", "rm -rf ~", "{folderPath}"],
              "timeoutSeconds": 3
            }
          ]
        }
        """
        try maliciousManifest.write(
            to: pluginsDirectory.appendingPathComponent("env-exploit.json"),
            atomically: true,
            encoding: .utf8
        )

        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        XCTAssertNil(registry.plugin(id: "env-exploit"))
        XCTAssertTrue(registry.loadIssues.contains(where: { issue in
            issue.file == "env-exploit.json" && issue.reason.contains("shell commands")
        }))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testEnvExecutableRejectsFolderPathWhenNotFinalArgument() throws {
        let context = try makeContext()
        let pluginsDirectory = try createPluginsDirectory(appSupportDirectory: context.appSupportDirectory)

        let invalidOrderManifest = """
        {
          "id": "env-bad-order",
          "displayName": "Bad Order",
          "priority": 50,
          "defaultEnabled": false,
          "launchAttempts": [
            {
              "label": "invalid",
              "executable": "/usr/bin/env",
              "arguments": ["code", "{folderPath}", "--reuse-window"],
              "timeoutSeconds": 3
            }
          ]
        }
        """
        try invalidOrderManifest.write(
            to: pluginsDirectory.appendingPathComponent("env-bad-order.json"),
            atomically: true,
            encoding: .utf8
        )

        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        XCTAssertNil(registry.plugin(id: "env-bad-order"))
        XCTAssertTrue(registry.loadIssues.contains(where: { issue in
            issue.file == "env-bad-order.json" && issue.reason.contains("final argument")
        }))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testEnvExecutableAllowsCustomBareCommandToken() throws {
        let context = try makeContext()
        let pluginsDirectory = try createPluginsDirectory(appSupportDirectory: context.appSupportDirectory)

        let customManifest = """
        {
          "id": "env-custom",
          "displayName": "Custom Env Command",
          "priority": 50,
          "defaultEnabled": false,
          "launchAttempts": [
            {
              "label": "open custom",
              "executable": "/usr/bin/env",
              "arguments": ["subl", "--new-window", "{folderPath}"],
              "timeoutSeconds": 3
            }
          ]
        }
        """
        try customManifest.write(
            to: pluginsDirectory.appendingPathComponent("env-custom.json"),
            atomically: true,
            encoding: .utf8
        )

        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        XCTAssertNotNil(registry.plugin(id: "env-custom"))
        XCTAssertFalse(registry.loadIssues.contains(where: { $0.file == "env-custom.json" }))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testDuplicateExternalIDDoesNotOverrideBuiltin() throws {
        let context = try makeContext()
        let pluginsDirectory = try createPluginsDirectory(appSupportDirectory: context.appSupportDirectory)

        let duplicateManifest = """
        {
          "id": "vscode",
          "displayName": "Hijacked",
          "priority": 1,
          "defaultEnabled": true,
          "launchAttempts": [
            {
              "label": "open app",
              "executable": "/usr/bin/open",
              "arguments": ["-a", "Fake App", "{folderPath}"],
              "timeoutSeconds": 3
            }
          ]
        }
        """
        try duplicateManifest.write(
            to: pluginsDirectory.appendingPathComponent("duplicate.json"),
            atomically: true,
            encoding: .utf8
        )

        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        XCTAssertEqual(try XCTUnwrap(registry.plugin(id: "vscode")).displayName, "VS Code")
        XCTAssertTrue(registry.loadIssues.contains(where: { $0.file == "duplicate.json" }))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testRemoveExternalPluginDeletesManifestAndReloadsCatalog() throws {
        let context = try makeContext()
        let pluginsDirectory = try createPluginsDirectory(appSupportDirectory: context.appSupportDirectory)

        let externalManifest = """
        {
          "id": "temp-editor",
          "displayName": "Temp Editor",
          "priority": 90,
          "defaultEnabled": false,
          "launchAttempts": [
            {
              "label": "open app",
              "executable": "/usr/bin/open",
              "arguments": ["-a", "Temp Editor", "{folderPath}"],
              "timeoutSeconds": 3
            }
          ]
        }
        """
        let externalPath = pluginsDirectory.appendingPathComponent("temp-editor.json")
        try externalManifest.write(to: externalPath, atomically: true, encoding: .utf8)

        let registry = EditorPluginRegistry(
            fileManager: .default,
            userDefaults: context.defaults,
            appSupportDirectoryURL: context.appSupportDirectory
        )

        XCTAssertNotNil(registry.plugin(id: "temp-editor"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalPath.path))

        _ = try registry.removeExternalPlugin(pluginID: "temp-editor")

        XCTAssertNil(registry.plugin(id: "temp-editor"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: externalPath.path))
    }

    /// Beginner note: This method ensures registry does not crash when Application Support
    /// lookup fails and surfaces a warning in load issues.
    func testApplicationSupportFallbackAddsLoadIssueWarning() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("macfusegui-editor-registry-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let suiteName = "com.visualweb.macfusegui.tests.editor-registry-fallback-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let fileManager = MissingAppSupportFileManager(fallbackTemporaryDirectoryURL: tempRoot)
        let registry = EditorPluginRegistry(
            fileManager: fileManager,
            userDefaults: defaults
        )

        XCTAssertTrue(registry.loadIssues.contains(where: {
            $0.reason.contains("Application Support directory lookup returned no user-domain path.")
        }))
        XCTAssertTrue(registry.pluginsDirectoryPath.contains("com.visualweb.macfusegui"))
    }

    /// Beginner note: This helper centralizes temporary context setup for registry tests.
    private func makeContext() throws -> (appSupportDirectory: URL, defaults: UserDefaults) {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("macfusegui-editor-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let suiteName = "com.visualweb.macfusegui.tests.editor-registry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        return (tempRoot, defaults)
    }

    /// Beginner note: This helper ensures plugin directory exists for external manifest tests.
    private func createPluginsDirectory(appSupportDirectory: URL) throws -> URL {
        let directory = appSupportDirectory
            .appendingPathComponent("macfuseGui", isDirectory: true)
            .appendingPathComponent("editor-plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class MissingAppSupportFileManager: FileManager {
    private let fallbackTemporaryDirectoryURL: URL

    init(fallbackTemporaryDirectoryURL: URL) {
        self.fallbackTemporaryDirectoryURL = fallbackTemporaryDirectoryURL
        super.init()
    }

    override var temporaryDirectory: URL {
        fallbackTemporaryDirectoryURL
    }

    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        if directory == .applicationSupportDirectory, domainMask == .userDomainMask {
            return []
        }
        return super.urls(for: directory, in: domainMask)
    }
}
