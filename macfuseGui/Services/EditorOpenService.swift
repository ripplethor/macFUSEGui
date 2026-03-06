// BEGINNER FILE GUIDE
// Layer: Core service layer
// Purpose: This file performs non-UI work such as mount commands, process execution, validation, persistence, or diagnostics.
// Called by: Called by view models to execute user actions and background recovery work.
// Calls into: May call system APIs, external tools, Keychain, filesystem, and helper services.
// Concurrency: Contains async functions; these can suspend and resume without blocking the calling thread.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
enum EditorOpenMode: Equatable, Sendable {
    case preferredWithFallback
    case explicit(pluginID: String)
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct EditorLaunchAttemptResult: Sendable {
    let label: String
    let executable: String
    // Arguments are stored after {folderPath} placeholder substitution.
    let resolvedArguments: [String]
    let timeoutSeconds: TimeInterval
    let exitCode: Int32
    let timedOut: Bool
    let failedToStart: Bool
    let output: String

    var arguments: [String] {
        resolvedArguments
    }

    var success: Bool {
        !timedOut && exitCode == 0
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct EditorPluginOpenResult: Sendable {
    let pluginID: String
    let pluginDisplayName: String
    let attempts: [EditorLaunchAttemptResult]

    var success: Bool {
        attempts.contains(where: { $0.success })
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct EditorOpenResult: Sendable {
    let success: Bool
    let launchedPluginID: String?
    let launchedPluginDisplayName: String?
    let mode: EditorOpenMode
    let pluginResults: [EditorPluginOpenResult]
    let message: String?
}

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class EditorOpenService {
    private let pluginRegistry: EditorPluginRegistry
    private let runner: ProcessRunning
    private let folderPathPlaceholder = "{folderPath}"

    /// Beginner note: Initializers create valid state before any other method is used.
    init(pluginRegistry: EditorPluginRegistry, runner: ProcessRunning) {
        self.pluginRegistry = pluginRegistry
        self.runner = runner
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func open(folderURL: URL, remoteName: String, mode: EditorOpenMode) async -> EditorOpenResult {
        // Snapshot plugin ordering once per open request. This intentionally avoids
        // mid-flight catalog churn while attempts are in progress.
        let plugins = pluginOrder(for: mode)

        guard !plugins.isEmpty else {
            return EditorOpenResult(
                success: false,
                launchedPluginID: nil,
                launchedPluginDisplayName: nil,
                mode: mode,
                pluginResults: [],
                message: noPluginMessage(for: mode)
            )
        }

        // Use a decoded POSIX path for process arguments (not a percent-encoded URL path).
        var folderPath = folderURL.path(percentEncoded: false)
        if folderPath.count > 1 && folderPath.hasSuffix("/") {
            folderPath.removeLast()
        }
        return await Self.openWithPluginsSnapshot(
            plugins: plugins,
            runner: runner,
            folderPath: folderPath,
            remoteName: remoteName,
            mode: mode,
            folderPathPlaceholder: folderPathPlaceholder
        )
    }

    private nonisolated static func openWithPluginsSnapshot(
        plugins: [EditorPluginDefinition],
        runner: ProcessRunning,
        folderPath: String,
        remoteName: String,
        mode: EditorOpenMode,
        folderPathPlaceholder: String
    ) async -> EditorOpenResult {
        var pluginResults: [EditorPluginOpenResult] = []

        for plugin in plugins {
            var attempts: [EditorLaunchAttemptResult] = []

            for attempt in plugin.launchAttempts {
                let resolvedArguments = attempt.arguments.map {
                    $0.replacingOccurrences(of: folderPathPlaceholder, with: folderPath)
                }

                let result = await runProcess(
                    runner: runner,
                    executable: attempt.executable,
                    arguments: resolvedArguments,
                    timeout: attempt.timeoutSeconds
                )

                let launchAttemptResult = EditorLaunchAttemptResult(
                    label: attempt.label,
                    executable: attempt.executable,
                    resolvedArguments: resolvedArguments,
                    timeoutSeconds: attempt.timeoutSeconds,
                    exitCode: result.exitCode,
                    timedOut: result.timedOut,
                    failedToStart: result.failedToStart,
                    output: result.output
                )

                attempts.append(launchAttemptResult)

                // By design we continue trying all launch attempts, even after a timeout,
                // so each plugin can exhaust its fallback chain.
                if launchAttemptResult.success {
                    let pluginResult = EditorPluginOpenResult(
                        pluginID: plugin.id,
                        pluginDisplayName: plugin.displayName,
                        attempts: attempts
                    )
                    pluginResults.append(pluginResult)

                    return EditorOpenResult(
                        success: true,
                        launchedPluginID: plugin.id,
                        launchedPluginDisplayName: plugin.displayName,
                        mode: mode,
                        pluginResults: pluginResults,
                        message: L10n.format("Opened %@ in %@.", remoteName, plugin.displayName)
                    )
                }
            }

            pluginResults.append(
                EditorPluginOpenResult(
                    pluginID: plugin.id,
                    pluginDisplayName: plugin.displayName,
                    attempts: attempts
                )
            )
        }

        return EditorOpenResult(
            success: false,
            launchedPluginID: nil,
            launchedPluginDisplayName: nil,
            mode: mode,
            pluginResults: pluginResults,
            message: L10n.format("Unable to open %@ with active editor plugins.", remoteName)
        )
    }

    private func pluginOrder(for mode: EditorOpenMode) -> [EditorPluginDefinition] {
        switch mode {
        case .preferredWithFallback:
            let active = pluginRegistry.activePluginsInPriorityOrder()
            guard !active.isEmpty else {
                return []
            }

            if let preferred = pluginRegistry.preferredPlugin() {
                let others = active.filter { $0.id != preferred.id }
                return [preferred] + others
            }

            return active

        case .explicit(let pluginID):
            guard let plugin = pluginRegistry.plugin(id: pluginID), plugin.isActive else {
                return []
            }
            return [plugin]
        }
    }

    private func noPluginMessage(for mode: EditorOpenMode) -> String {
        switch mode {
        case .preferredWithFallback:
            return L10n.tr("No active editor plugins. Enable one in Settings > Editor Plugins.")
        case .explicit(let pluginID):
            let displayName = pluginRegistry.plugin(id: pluginID)?.displayName ?? pluginID
            return L10n.format("Editor plugin '%@' is not active.", displayName)
        }
    }

    private nonisolated static func runProcess(
        runner: ProcessRunning,
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> (exitCode: Int32, timedOut: Bool, failedToStart: Bool, output: String) {
        do {
            let result = try await runner.run(
                executable: executable,
                arguments: arguments,
                timeout: timeout
            )
            let combined = [result.stdout, result.stderr]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return (result.exitCode, result.timedOut, false, combined)
        } catch {
            return (-1, false, true, error.localizedDescription)
        }
    }
}
