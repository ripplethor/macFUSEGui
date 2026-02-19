// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class EditorPluginRegistry: ObservableObject {
    @Published private(set) var plugins: [EditorPluginDefinition] = []
    @Published private(set) var loadIssues: [EditorPluginLoadIssue] = []
    @Published private(set) var preferredPluginID: String?

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private var catalog: [EditorPluginDefinition] = []

    private let activationOverridesKey = "editor.plugins.activation_overrides"
    private let preferredPluginIDKey = "editor.plugins.preferred_id"
    private let folderPathPlaceholder = "{folderPath}"
    private let pluginDirectoryReadmeFileName = "README.md"
    private let pluginExamplesDirectoryName = "examples"
    private let builtInReferenceDirectoryName = "builtin-reference"
    private let exampleTemplateFileName = "custom-editor.json.template"
    private let bundledBuiltInPluginsFolderName = "EditorPlugins"
    private let bundledPluginManifestFileName = "plugin.json"

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        appSupportDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults

        if let appSupportDirectoryURL {
            self.appSupportDirectoryURL = appSupportDirectoryURL
        } else {
            self.appSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }

        reloadCatalog()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func reloadCatalog() {
        var issues: [EditorPluginLoadIssue] = []
        let builtIns = builtInCatalog(issues: &issues)
        preparePluginsDirectoryScaffold(builtIns: builtIns, issues: &issues)
        var mergedByID: [String: EditorPluginDefinition] = Dictionary(
            uniqueKeysWithValues: builtIns.map { ($0.id, $0) }
        )

        for loaded in loadExternalPlugins(issues: &issues) {
            if mergedByID[loaded.plugin.id] != nil {
                issues.append(
                    EditorPluginLoadIssue(
                        file: loaded.file,
                        reason: "Plugin ID '\(loaded.plugin.id)' is already defined by a built-in plugin. External manifest was ignored."
                    )
                )
                continue
            }
            mergedByID[loaded.plugin.id] = loaded.plugin
        }

        catalog = mergedByID.values.sorted(by: pluginSort)
        loadIssues = issues
        rebuildPublishedState()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func setPluginActive(_ active: Bool, pluginID: String) {
        guard let plugin = catalog.first(where: { $0.id == pluginID }) else {
            return
        }

        var overrides = activationOverrides()
        if active == plugin.defaultEnabled {
            overrides.removeValue(forKey: pluginID)
        } else {
            overrides[pluginID] = active
        }
        userDefaults.set(overrides, forKey: activationOverridesKey)

        rebuildPublishedState()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func setPreferredPlugin(_ pluginID: String?) {
        let normalized = pluginID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            userDefaults.set(normalized, forKey: preferredPluginIDKey)
        } else {
            userDefaults.removeObject(forKey: preferredPluginIDKey)
        }

        rebuildPublishedState()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func activePluginsInPriorityOrder() -> [EditorPluginDefinition] {
        plugins
            .filter { $0.isActive }
            .sorted(by: pluginSort)
    }

    /// Beginner note: Convenience helper for call sites that need a current preferred plugin definition.
    func preferredPlugin() -> EditorPluginDefinition? {
        guard let preferredPluginID else {
            return nil
        }
        return plugins.first(where: { $0.id == preferredPluginID && $0.isActive })
    }

    /// Beginner note: This helper lets callers resolve plugin metadata by ID.
    func plugin(id: String) -> EditorPluginDefinition? {
        plugins.first(where: { $0.id == id })
    }

    /// Beginner note: Resolve plugin manifest file URL for edit/reveal actions.
    func manifestFileURL(for pluginID: String) -> URL? {
        guard let definition = plugin(id: pluginID) else {
            return nil
        }

        switch definition.source {
        case .builtIn:
            return bundledManifestURL(for: definition.id)
        case .external:
            return externalManifestURL(for: definition.id)
        }
    }

    /// Beginner note: Loads manifest file contents so UI can edit JSON inline.
    func manifestText(for pluginID: String) throws -> String {
        guard let manifestURL = manifestFileURL(for: pluginID) else {
            throw AppError.validationFailed(["Manifest file not found for plugin '\(pluginID)'."])
        }

        do {
            return try String(contentsOf: manifestURL, encoding: .utf8)
        } catch {
            throw AppError.validationFailed([
                "Unable to read manifest '\(manifestURL.path)': \(error.localizedDescription)"
            ])
        }
    }

    /// Beginner note: Saves edited JSON and reloads plugin catalog immediately.
    @discardableResult
    func saveManifestText(_ text: String, for pluginID: String) throws -> String {
        guard let definition = plugin(id: pluginID) else {
            throw AppError.validationFailed(["Plugin '\(pluginID)' is not available."])
        }
        guard let manifestURL = manifestFileURL(for: pluginID) else {
            throw AppError.validationFailed(["Manifest file not found for plugin '\(pluginID)'."])
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.validationFailed(["Manifest cannot be empty."])
        }

        let manifestData = Data(trimmed.utf8)
        let manifest: ExternalPluginManifest
        do {
            manifest = try decoder.decode(ExternalPluginManifest.self, from: manifestData)
        } catch {
            throw AppError.validationFailed([
                "\(manifestURL.lastPathComponent): Invalid JSON schema. \(error.localizedDescription)"
            ])
        }

        let validated = try validate(
            manifest: manifest,
            fileName: manifestURL.lastPathComponent,
            source: definition.source
        )

        if definition.source == .external {
            let builtInIDs = Set(catalog.filter { $0.source == .builtIn }.map(\.id))
            if builtInIDs.contains(validated.id) {
                throw AppError.validationFailed([
                    "\(manifestURL.lastPathComponent): '\(validated.id)' is reserved by a built-in plugin."
                ])
            }

            if validated.id != pluginID,
               let existing = plugin(id: validated.id),
               existing.source == .external {
                throw AppError.validationFailed([
                    "\(manifestURL.lastPathComponent): External plugin ID '\(validated.id)' already exists."
                ])
            }
        } else if validated.id != pluginID {
            throw AppError.validationFailed([
                "\(manifestURL.lastPathComponent): Built-in plugin ID cannot be changed."
            ])
        }

        var persistedText = trimmed
        if !persistedText.hasSuffix("\n") {
            persistedText.append("\n")
        }

        do {
            try persistedText.write(to: manifestURL, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.validationFailed([
                "Unable to write manifest '\(manifestURL.path)': \(error.localizedDescription)"
            ])
        }

        reloadCatalog()
        return validated.id
    }

    /// Beginner note: Removes an external plugin manifest and reloads plugin catalog.
    @discardableResult
    func removeExternalPlugin(pluginID: String) throws -> String {
        guard let definition = plugin(id: pluginID) else {
            throw AppError.validationFailed(["Plugin '\(pluginID)' is not available."])
        }
        guard definition.source == .external else {
            throw AppError.validationFailed(["Built-in plugin '\(pluginID)' cannot be removed."])
        }
        guard let manifestURL = externalManifestURL(for: definition.id) else {
            throw AppError.validationFailed([
                "Manifest file for external plugin '\(pluginID)' was not found."
            ])
        }

        do {
            try fileManager.removeItem(at: manifestURL)
        } catch {
            throw AppError.validationFailed([
                "Unable to remove manifest '\(manifestURL.path)': \(error.localizedDescription)"
            ])
        }

        reloadCatalog()
        return definition.displayName
    }

    /// Beginner note: Create a starter external plugin manifest in the live plugin directory.
    func createExternalPluginTemplateFile() throws -> URL {
        var issues: [EditorPluginLoadIssue] = []
        let builtIns = builtInCatalog(issues: &issues)
        preparePluginsDirectoryScaffold(builtIns: builtIns, issues: &issues)

        let existingPluginIDs = Set(plugins.map(\.id))
        var sequence = 1
        var candidateID = "new-editor-\(sequence)"
        var candidateFileURL = pluginsDirectoryURL.appendingPathComponent("\(candidateID).json")

        while existingPluginIDs.contains(candidateID) || fileManager.fileExists(atPath: candidateFileURL.path) {
            sequence += 1
            candidateID = "new-editor-\(sequence)"
            candidateFileURL = pluginsDirectoryURL.appendingPathComponent("\(candidateID).json")
        }

        let templateManifest = ExternalPluginManifest(
            id: candidateID,
            displayName: "New Editor",
            priority: 100,
            defaultEnabled: false,
            launchAttempts: [
                ExternalLaunchAttemptManifest(
                    label: "open app New Editor",
                    executable: "/usr/bin/open",
                    arguments: ["-a", "New Editor", folderPathPlaceholder],
                    timeoutSeconds: 3
                )
            ]
        )

        let data = try encoder.encode(templateManifest)
        try data.write(to: candidateFileURL, options: [.atomic])
        return candidateFileURL
    }

    /// Beginner note: Exposed for settings/help text.
    var pluginsDirectoryPath: String {
        pluginsDirectoryURL.path
    }

    /// Beginner note: Exposed for discoverability of built-in plugin references.
    var builtInReferenceDirectoryPath: String {
        builtInReferenceDirectoryURL.path
    }

    /// Beginner note: Exposed for discoverability of starter manifest templates.
    var pluginExamplesDirectoryPath: String {
        pluginExamplesDirectoryURL.path
    }

    private let appSupportDirectoryURL: URL

    private var pluginsDirectoryURL: URL {
        appSupportDirectoryURL
            .appendingPathComponent("macfuseGui", isDirectory: true)
            .appendingPathComponent("editor-plugins", isDirectory: true)
    }

    private var pluginExamplesDirectoryURL: URL {
        pluginsDirectoryURL.appendingPathComponent(pluginExamplesDirectoryName, isDirectory: true)
    }

    private var builtInReferenceDirectoryURL: URL {
        pluginsDirectoryURL.appendingPathComponent(builtInReferenceDirectoryName, isDirectory: true)
    }

    private func bundledManifestURL(for pluginID: String) -> URL? {
        Bundle.main.url(
            forResource: "plugin",
            withExtension: "json",
            subdirectory: "\(bundledBuiltInPluginsFolderName)/\(pluginID)"
        )
    }

    private func externalManifestURL(for pluginID: String) -> URL? {
        guard fileManager.fileExists(atPath: pluginsDirectoryURL.path) else {
            return nil
        }

        let candidateFiles: [URL]
        do {
            candidateFiles = try fileManager
                .contentsOfDirectory(
                    at: pluginsDirectoryURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                .filter { $0.pathExtension.lowercased() == "json" }
        } catch {
            return nil
        }

        for fileURL in candidateFiles {
            guard let data = try? Data(contentsOf: fileURL),
                  let manifest = try? decoder.decode(ExternalPluginManifest.self, from: data) else {
                continue
            }

            let manifestID = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if manifestID == pluginID {
                return fileURL
            }
        }

        return nil
    }

    private func preparePluginsDirectoryScaffold(
        builtIns: [EditorPluginDefinition],
        issues: inout [EditorPluginLoadIssue]
    ) {
        do {
            try fileManager.createDirectory(at: pluginsDirectoryURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: pluginExamplesDirectoryURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: builtInReferenceDirectoryURL, withIntermediateDirectories: true)
        } catch {
            issues.append(
                EditorPluginLoadIssue(
                    file: pluginsDirectoryURL.path,
                    reason: "Failed to create plugin directories: \(error.localizedDescription)"
                )
            )
            return
        }

        writeTextFileIfMissing(
            url: pluginsDirectoryURL.appendingPathComponent(pluginDirectoryReadmeFileName),
            contents: pluginDirectoryReadmeContents(),
            issues: &issues
        )
        writeTextFileIfMissing(
            url: pluginExamplesDirectoryURL.appendingPathComponent(exampleTemplateFileName),
            contents: exampleTemplateContents(),
            issues: &issues
        )

        writeBuiltInReferenceFiles(builtIns: builtIns, issues: &issues)
    }

    private func writeBuiltInReferenceFiles(
        builtIns: [EditorPluginDefinition],
        issues: inout [EditorPluginLoadIssue]
    ) {
        for plugin in builtIns {
            let manifest = ExternalPluginManifest(
                id: plugin.id,
                displayName: plugin.displayName,
                priority: plugin.priority,
                defaultEnabled: plugin.defaultEnabled,
                launchAttempts: plugin.launchAttempts.map { attempt in
                    ExternalLaunchAttemptManifest(
                        label: attempt.label,
                        executable: attempt.executable,
                        arguments: attempt.arguments,
                        timeoutSeconds: attempt.timeoutSeconds
                    )
                }
            )

            do {
                let data = try encoder.encode(manifest)
                let fileURL = builtInReferenceDirectoryURL.appendingPathComponent("\(plugin.id).json")
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                issues.append(
                    EditorPluginLoadIssue(
                        file: "\(builtInReferenceDirectoryName)/\(plugin.id).json",
                        reason: "Failed to write built-in reference manifest: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    private func writeTextFileIfMissing(
        url: URL,
        contents: String,
        issues: inout [EditorPluginLoadIssue]
    ) {
        guard !fileManager.fileExists(atPath: url.path) else {
            return
        }

        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            issues.append(
                EditorPluginLoadIssue(
                    file: url.lastPathComponent,
                    reason: "Failed to write scaffold file: \(error.localizedDescription)"
                )
            )
        }
    }

    private func pluginDirectoryReadmeContents() -> String {
        """
        # macfuseGui Editor Plugins

        Files in this top-level folder with `.json` extension are loaded as external editor plugins.

        ## Quick Start
        1. Copy `examples/custom-editor.json.template` to this folder.
        2. Rename it to something like `windsurf.json`.
        3. Edit `id`, `displayName`, and launch attempts.
        4. In the app, click `Reload` in the Editor Plugins window.

        ## Built-in Editors
        Built-in plugins are shipped by the app and cannot be overridden by external manifests.
        Reference manifests are generated under:
        - `builtin-reference/`

        ## Safety Rules
        - Allowed executables: `/usr/bin/open`, `/usr/bin/env`
        - `launchAttempts.arguments` must include `{folderPath}`
        - Use argument arrays only (no shell strings)

        """
    }

    private func exampleTemplateContents() -> String {
        """
        {
          "id": "windsurf",
          "displayName": "Windsurf",
          "priority": 50,
          "defaultEnabled": false,
          "launchAttempts": [
            {
              "label": "open app Windsurf",
              "executable": "/usr/bin/open",
              "arguments": ["-a", "Windsurf", "{folderPath}"],
              "timeoutSeconds": 3
            }
          ]
        }
        """
    }

    /// Beginner note: Recomputes effective active/preferred projection after reload or setting change.
    private func rebuildPublishedState() {
        let overrides = activationOverrides()

        var projected = catalog.map { plugin -> EditorPluginDefinition in
            var runtime = plugin
            runtime.isActive = overrides[plugin.id] ?? plugin.defaultEnabled
            runtime.isPreferred = false
            return runtime
        }
        projected.sort(by: pluginSort)

        let activeIDs = projected.filter { $0.isActive }.map(\.id)
        let storedPreferred = userDefaults.string(forKey: preferredPluginIDKey)
        let resolvedPreferred = resolvePreferredID(storedPreferred: storedPreferred, activeIDs: activeIDs)

        preferredPluginID = resolvedPreferred
        if let resolvedPreferred {
            userDefaults.set(resolvedPreferred, forKey: preferredPluginIDKey)
        } else {
            userDefaults.removeObject(forKey: preferredPluginIDKey)
        }

        if let resolvedPreferred {
            projected = projected.map { plugin in
                var updated = plugin
                updated.isPreferred = plugin.id == resolvedPreferred
                return updated
            }
        }

        plugins = projected
    }

    private func resolvePreferredID(storedPreferred: String?, activeIDs: [String]) -> String? {
        if let storedPreferred,
           activeIDs.contains(storedPreferred) {
            return storedPreferred
        }
        return activeIDs.first
    }

    private func activationOverrides() -> [String: Bool] {
        if let dictionary = userDefaults.dictionary(forKey: activationOverridesKey) as? [String: Bool] {
            return dictionary
        }
        return [:]
    }

    private func pluginSort(_ lhs: EditorPluginDefinition, _ rhs: EditorPluginDefinition) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func loadExternalPlugins(issues: inout [EditorPluginLoadIssue]) -> [(file: String, plugin: EditorPluginDefinition)] {
        guard fileManager.fileExists(atPath: pluginsDirectoryURL.path) else {
            return []
        }

        let candidateFiles: [URL]
        do {
            candidateFiles = try fileManager
                .contentsOfDirectory(
                    at: pluginsDirectoryURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            issues.append(
                EditorPluginLoadIssue(
                    file: pluginsDirectoryURL.path,
                    reason: "Failed to read plugins directory: \(error.localizedDescription)"
                )
            )
            return []
        }

        var plugins: [(file: String, plugin: EditorPluginDefinition)] = []
        var seenIDs: Set<String> = []

        for fileURL in candidateFiles {
            do {
                let data = try Data(contentsOf: fileURL)
                let manifest = try decoder.decode(ExternalPluginManifest.self, from: data)
                let validated = try validate(manifest: manifest, fileName: fileURL.lastPathComponent)

                if seenIDs.contains(validated.id) {
                    issues.append(
                        EditorPluginLoadIssue(
                            file: fileURL.lastPathComponent,
                            reason: "Plugin ID '\(validated.id)' is duplicated in external manifests."
                        )
                    )
                    continue
                }

                seenIDs.insert(validated.id)
                plugins.append((fileURL.lastPathComponent, validated))
            } catch {
                issues.append(
                    EditorPluginLoadIssue(
                        file: fileURL.lastPathComponent,
                        reason: error.localizedDescription
                    )
                )
            }
        }

        return plugins
    }

    private func validate(
        manifest: ExternalPluginManifest,
        fileName: String,
        source: EditorPluginSource = .external
    ) throws -> EditorPluginDefinition {
        let id = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty else {
            throw AppError.validationFailed(["\(fileName): Plugin id is required."])
        }
        guard id.range(of: "^[a-z0-9._-]+$", options: .regularExpression) != nil else {
            throw AppError.validationFailed(["\(fileName): Plugin id '\(id)' contains invalid characters."])
        }

        let displayName = manifest.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            throw AppError.validationFailed(["\(fileName): displayName is required."])
        }

        guard !manifest.launchAttempts.isEmpty else {
            throw AppError.validationFailed(["\(fileName): At least one launch attempt is required."])
        }

        let priority = max(0, manifest.priority)

        let attempts = try manifest.launchAttempts.enumerated().map { index, candidate in
            try validate(attempt: candidate, index: index, fileName: fileName)
        }

        return EditorPluginDefinition(
            id: id,
            displayName: displayName,
            priority: priority,
            defaultEnabled: manifest.defaultEnabled,
            launchAttempts: attempts,
            source: source,
            isActive: false,
            isPreferred: false
        )
    }

    private func validate(
        attempt candidate: ExternalLaunchAttemptManifest,
        index: Int,
        fileName: String
    ) throws -> EditorLaunchAttemptDefinition {
        let label = candidate.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            throw AppError.validationFailed(["\(fileName): launchAttempts[\(index)] label is required."])
        }

        let executable = candidate.executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard executable == "/usr/bin/open" || executable == "/usr/bin/env" else {
            throw AppError.validationFailed([
                "\(fileName): launchAttempts[\(index)] executable must be /usr/bin/open or /usr/bin/env."
            ])
        }

        guard !candidate.arguments.isEmpty else {
            throw AppError.validationFailed(["\(fileName): launchAttempts[\(index)] arguments cannot be empty."])
        }

        guard candidate.arguments.contains(where: { $0.contains(folderPathPlaceholder) }) else {
            throw AppError.validationFailed([
                "\(fileName): launchAttempts[\(index)] must include {folderPath} placeholder."
            ])
        }

        for argument in candidate.arguments {
            let hasBrace = argument.contains("{") || argument.contains("}")
            if hasBrace && !argument.contains(folderPathPlaceholder) {
                throw AppError.validationFailed([
                    "\(fileName): launchAttempts[\(index)] contains unsupported placeholder in argument '\(argument)'."
                ])
            }
        }

        if executable == "/usr/bin/open" {
            // Keep plugin manifests aligned to safe app-launch forms only.
            guard candidate.arguments.contains("-a") || candidate.arguments.contains("-b") else {
                throw AppError.validationFailed([
                    "\(fileName): launchAttempts[\(index)] /usr/bin/open form must use -a or -b."
                ])
            }
        }

        if executable == "/usr/bin/env" {
            guard let command = candidate.arguments.first,
                  !command.isEmpty,
                  !command.hasPrefix("-"),
                  !command.contains("/"),
                  command.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
                throw AppError.validationFailed([
                    "\(fileName): launchAttempts[\(index)] /usr/bin/env form must start with a bare command token."
                ])
            }
        }

        let timeout = clampedTimeout(candidate.timeoutSeconds)

        return EditorLaunchAttemptDefinition(
            label: label,
            executable: executable,
            arguments: candidate.arguments,
            timeoutSeconds: timeout
        )
    }

    private func clampedTimeout(_ timeout: TimeInterval?) -> TimeInterval {
        let raw = timeout ?? 3
        return min(10, max(1, raw))
    }

    private func builtInCatalog(issues: inout [EditorPluginLoadIssue]) -> [EditorPluginDefinition] {
        let bundled = loadBundledBuiltInCatalog(issues: &issues)
        if !bundled.isEmpty {
            return bundled
        }
        return hardcodedBuiltInCatalog()
    }

    private func loadBundledBuiltInCatalog(issues: inout [EditorPluginLoadIssue]) -> [EditorPluginDefinition] {
        guard let bundledRootURL = Bundle.main.url(forResource: bundledBuiltInPluginsFolderName, withExtension: nil) else {
            return []
        }

        let pluginDirectories: [URL]
        do {
            pluginDirectories = try fileManager
                .contentsOfDirectory(
                    at: bundledRootURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                .filter { url in
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                    return values?.isDirectory == true
                }
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            issues.append(
                EditorPluginLoadIssue(
                    file: bundledBuiltInPluginsFolderName,
                    reason: "Failed to read bundled built-in plugin directory: \(error.localizedDescription)"
                )
            )
            return []
        }

        var loadedPlugins: [EditorPluginDefinition] = []
        var seenIDs: Set<String> = []

        for directoryURL in pluginDirectories {
            let manifestURL = directoryURL.appendingPathComponent(bundledPluginManifestFileName)
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                issues.append(
                    EditorPluginLoadIssue(
                        file: "\(directoryURL.lastPathComponent)/\(bundledPluginManifestFileName)",
                        reason: "Bundled plugin directory is missing \(bundledPluginManifestFileName)."
                    )
                )
                continue
            }

            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try decoder.decode(ExternalPluginManifest.self, from: data)
                let fileLabel = "\(directoryURL.lastPathComponent)/\(bundledPluginManifestFileName)"
                let validated = try validate(manifest: manifest, fileName: fileLabel, source: .builtIn)

                if seenIDs.contains(validated.id) {
                    issues.append(
                        EditorPluginLoadIssue(
                            file: fileLabel,
                            reason: "Duplicate bundled built-in plugin ID '\(validated.id)'."
                        )
                    )
                    continue
                }

                seenIDs.insert(validated.id)
                loadedPlugins.append(validated)
            } catch {
                issues.append(
                    EditorPluginLoadIssue(
                        file: "\(directoryURL.lastPathComponent)/\(bundledPluginManifestFileName)",
                        reason: "Failed to decode bundled built-in plugin: \(error.localizedDescription)"
                    )
                )
            }
        }

        return loadedPlugins.sorted(by: pluginSort)
    }

    private func hardcodedBuiltInCatalog() -> [EditorPluginDefinition] {
        [
            EditorPluginDefinition(
                id: "vscode",
                displayName: "VS Code",
                priority: 10,
                defaultEnabled: true,
                launchAttempts: [
                    EditorLaunchAttemptDefinition(
                        label: "open bundle com.microsoft.VSCode",
                        executable: "/usr/bin/open",
                        arguments: ["-b", "com.microsoft.VSCode", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "open bundle com.microsoft.VSCodeInsiders",
                        executable: "/usr/bin/open",
                        arguments: ["-b", "com.microsoft.VSCodeInsiders", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "open app Visual Studio Code",
                        executable: "/usr/bin/open",
                        arguments: ["-a", "Visual Studio Code", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "open app Visual Studio Code - Insiders",
                        executable: "/usr/bin/open",
                        arguments: ["-a", "Visual Studio Code - Insiders", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "code --reuse-window",
                        executable: "/usr/bin/env",
                        arguments: ["code", "--reuse-window", folderPathPlaceholder],
                        timeoutSeconds: 3
                    )
                ],
                source: .builtIn
            ),
            EditorPluginDefinition(
                id: "vscodium",
                displayName: "VSCodium",
                priority: 20,
                defaultEnabled: false,
                launchAttempts: [
                    EditorLaunchAttemptDefinition(
                        label: "open bundle com.vscodium",
                        executable: "/usr/bin/open",
                        arguments: ["-b", "com.vscodium", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "open app VSCodium",
                        executable: "/usr/bin/open",
                        arguments: ["-a", "VSCodium", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "codium --reuse-window",
                        executable: "/usr/bin/env",
                        arguments: ["codium", "--reuse-window", folderPathPlaceholder],
                        timeoutSeconds: 3
                    )
                ],
                source: .builtIn
            ),
            EditorPluginDefinition(
                id: "cursor",
                displayName: "Cursor",
                priority: 30,
                defaultEnabled: false,
                launchAttempts: [
                    EditorLaunchAttemptDefinition(
                        label: "open bundle com.todesktop.230313mzl4w4u92",
                        executable: "/usr/bin/open",
                        arguments: ["-b", "com.todesktop.230313mzl4w4u92", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "open app Cursor",
                        executable: "/usr/bin/open",
                        arguments: ["-a", "Cursor", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "cursor --reuse-window",
                        executable: "/usr/bin/env",
                        arguments: ["cursor", "--reuse-window", folderPathPlaceholder],
                        timeoutSeconds: 3
                    )
                ],
                source: .builtIn
            ),
            EditorPluginDefinition(
                id: "zed",
                displayName: "Zed",
                priority: 40,
                defaultEnabled: false,
                launchAttempts: [
                    EditorLaunchAttemptDefinition(
                        label: "open bundle dev.zed.Zed",
                        executable: "/usr/bin/open",
                        arguments: ["-b", "dev.zed.Zed", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "open app Zed",
                        executable: "/usr/bin/open",
                        arguments: ["-a", "Zed", folderPathPlaceholder],
                        timeoutSeconds: 3
                    ),
                    EditorLaunchAttemptDefinition(
                        label: "zed --reuse-window",
                        executable: "/usr/bin/env",
                        arguments: ["zed", "--reuse-window", folderPathPlaceholder],
                        timeoutSeconds: 3
                    )
                ],
                source: .builtIn
            )
        ]
    }
}

/// Beginner note: External plugin manifest schema loaded from JSON files.
private struct ExternalPluginManifest: Codable {
    let id: String
    let displayName: String
    let priority: Int
    let defaultEnabled: Bool
    let launchAttempts: [ExternalLaunchAttemptManifest]

    init(
        id: String,
        displayName: String,
        priority: Int,
        defaultEnabled: Bool,
        launchAttempts: [ExternalLaunchAttemptManifest]
    ) {
        self.id = id
        self.displayName = displayName
        self.priority = priority
        self.defaultEnabled = defaultEnabled
        self.launchAttempts = launchAttempts
    }
}

/// Beginner note: External launch-attempt manifest schema loaded from JSON files.
private struct ExternalLaunchAttemptManifest: Codable {
    let label: String
    let executable: String
    let arguments: [String]
    let timeoutSeconds: TimeInterval?

    init(
        label: String,
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?
    ) {
        self.label = label
        self.executable = executable
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }
}
