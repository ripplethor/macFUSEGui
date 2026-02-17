// BEGINNER FILE GUIDE
// Layer: Menu bar presentation layer
// Purpose: This file builds and updates the status bar UI and popover menu interactions.
// Called by: Called by app bootstrap and user interactions from the menu bar icon.
// Calls into: Calls into RemotesViewModel and AppKit controls.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

@MainActor
// MenuBarController is the bridge between AppKit status-item UI and SwiftUI content.
// It keeps the menu icon/count in sync with view-model state and routes menu actions.
//
// Why MainActor:
// - AppKit UI APIs must be used from main thread/actor.
// - Combine sinks here update UI directly.
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class MenuBarController: NSObject {
    private static var activeStatusItem: NSStatusItem?

    private let viewModel: RemotesViewModel
    private let settingsWindowController: SettingsWindowController
    private let editorPluginRegistry: EditorPluginRegistry
    private let editorOpenService: EditorOpenService
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    private var cancellables: Set<AnyCancellable> = []
    private var activityTimer: Timer?
    private var activityFrame: Int = 0

    // Preferred icon symbol chain. We pick first one available on current macOS.
    private let defaultSymbols = [
        "powerplug",
        "externaldrive.fill.badge.wifi",
        "externaldrive.badge.wifi",
        "externaldrive"
    ]

    // Activity frames for simple "work in progress" animation.
    private let activitySymbols = [
        "arrow.triangle.2.circlepath",
        "ellipsis.circle",
        "ellipsis.circle.fill"
    ]

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        viewModel: RemotesViewModel,
        settingsWindowController: SettingsWindowController,
        editorPluginRegistry: EditorPluginRegistry,
        editorOpenService: EditorOpenService
    ) {
        self.viewModel = viewModel
        self.settingsWindowController = settingsWindowController
        self.editorPluginRegistry = editorPluginRegistry
        self.editorOpenService = editorOpenService

        if let existingStatusItem = Self.activeStatusItem {
            NSStatusBar.system.removeStatusItem(existingStatusItem)
            Self.activeStatusItem = nil
        }

        let newStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = newStatusItem
        Self.activeStatusItem = newStatusItem
        self.popover = NSPopover()

        super.init()

        configureStatusButton()
        configurePopover()
        bindViewModel()
        updateStatusItemIndicator()
    }

    /// Beginner note: Deinitializer runs during teardown to stop background work and free resources.
    deinit {
        activityTimer?.invalidate()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 460, height: 520)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func bindViewModel() {
        // Re-render icon whenever core runtime state changes.
        viewModel.$remotes
            .combineLatest(viewModel.$statuses)
            .sink { [weak self] _, _ in
                self?.updateStatusItemIndicator()
            }
            .store(in: &cancellables)

        viewModel.$dependencyStatus
            .sink { [weak self] _ in
                self?.updateStatusItemIndicator()
            }
            .store(in: &cancellables)

        viewModel.$recoveryIndicator
            .sink { [weak self] _ in
                self?.updateStatusItemIndicator()
            }
            .store(in: &cancellables)

        viewModel.$systemSleeping
            .sink { [weak self] _ in
                self?.updateStatusItemIndicator()
            }
            .store(in: &cancellables)

        viewModel.$wakeAnimationUntil
            .sink { [weak self] _ in
                self?.updateStatusItemIndicator()
            }
            .store(in: &cancellables)
    }

    @objc
    /// Beginner note: This method is one step in the feature workflow for this file.
    private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        let content = MenuPopoverContentView(
            viewModel: viewModel,
            editorPluginRegistry: editorPluginRegistry,
            // Menu actions intentionally route back into view model/service flows.
            onOpenSettings: { [weak self] in self?.openSettings() },
            onRefresh: { [weak self] in self?.refreshStatus() },
            onCopyDiagnostics: { [weak self] in self?.copyDiagnostics() },
            onConnect: { [weak self] remoteID in self?.connectRemote(remoteID) },
            onDisconnect: { [weak self] remoteID in self?.disconnectRemote(remoteID) },
            onOpenInPreferredEditor: { [weak self] remoteID in self?.openRemoteMountInPreferredEditor(remoteID) },
            onOpenInEditorPlugin: { [weak self] remoteID, pluginID in self?.openRemoteMountInEditor(remoteID, pluginID: pluginID) },
            onForceResetMounts: { [weak self] in self?.forceResetAllMounts() },
            onQuit: { [weak self] in self?.quitApp() }
        )

        let hosting = NSHostingController(rootView: content)
        popover.contentViewController = hosting
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func updateStatusItemIndicator() {
        guard let button = statusItem.button else {
            return
        }

        // These computed values drive both icon color and tooltip content.
        let counts = statusCounts()
        let activeOperations = currentActiveOperations()
        let recoveryIndicator = viewModel.recoveryIndicator
        let wakePulseActive = (viewModel.wakeAnimationUntil ?? .distantPast) > Date()
        let reconnectingCount = viewModel.remotes.reduce(0) { partial, remote in
            partial + (viewModel.isRemoteInRecoveryReconnect(remote.id) ? 1 : 0)
        }
        let hasActivityAnimation = wakePulseActive || !activeOperations.isEmpty || recoveryIndicator != nil || reconnectingCount > 0
        setActivityTimerEnabled(hasActivityAnimation)

        // Icon priority:
        // 1) activity animation
        // 2) warning icon if dependencies/errors
        // 3) normal icon
        let symbolCandidates: [String]
        if hasActivityAnimation {
            symbolCandidates = [activitySymbols[activityFrame % activitySymbols.count], "arrow.triangle.2.circlepath"] + defaultSymbols
        } else if (viewModel.dependencyStatus?.isReady == false) || counts.errors > 0 {
            symbolCandidates = ["exclamationmark.triangle"] + defaultSymbols
        } else {
            symbolCandidates = defaultSymbols
        }

        let selectedSymbolName = symbolCandidates.first { symbolName in
            NSImage(systemSymbolName: symbolName, accessibilityDescription: "macfuseGui") != nil
        }

        if let selectedSymbolName,
           let icon = NSImage(systemSymbolName: selectedSymbolName, accessibilityDescription: "macfuseGui") {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            let configured = icon.withSymbolConfiguration(symbolConfig) ?? icon
            configured.isTemplate = true
            button.image = configured
            // Orange count means sleep/reconnect/recovery activity.
            // Green count means steady connected state.
            let countColor: NSColor = (viewModel.systemSleeping || reconnectingCount > 0 || recoveryIndicator != nil) ? .systemOrange : .systemGreen
            applyConnectedCountLabel(connectedCount: counts.connected, color: countColor, to: button)
        } else {
            button.image = nil
            button.attributedTitle = NSAttributedString(string: "")
            button.title = "FUSE"
        }

        button.toolTip = statusTooltip(
            counts: counts,
            activeOperations: activeOperations,
            recoveryIndicator: recoveryIndicator,
            reconnectingCount: reconnectingCount
        )
        button.needsDisplay = true
        button.displayIfNeeded()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func setActivityTimerEnabled(_ enabled: Bool) {
        if enabled {
            guard activityTimer == nil else {
                return
            }

            let timer = Timer(
                timeInterval: 0.3,
                target: self,
                selector: #selector(handleActivityTimerTick),
                userInfo: nil,
                repeats: true
            )
            timer.tolerance = 0.03
            RunLoop.main.add(timer, forMode: .common)
            activityTimer = timer
        } else {
            // Reset frame so next animation starts from a predictable frame.
            activityTimer?.invalidate()
            activityTimer = nil
            activityFrame = 0
        }
    }

    @objc
    /// Beginner note: This method is one step in the feature workflow for this file.
    private func handleActivityTimerTick() {
        activityFrame = (activityFrame + 1) % activitySymbols.count
        updateStatusItemIndicator()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func statusCounts() -> (connected: Int, active: Int, errors: Int, disconnected: Int) {
        var counts = (connected: 0, active: 0, errors: 0, disconnected: 0)

        for remote in viewModel.remotes {
            switch viewModel.status(for: remote.id).state {
            case .connected:
                counts.connected += 1
                counts.active += 1
            case .connecting, .disconnecting:
                counts.active += 1
            case .error:
                counts.errors += 1
            case .disconnected:
                counts.disconnected += 1
            }
        }

        return counts
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func currentActiveOperations() -> [(name: String, state: RemoteConnectionState, startedAt: Date)] {
        viewModel.remotes.compactMap { remote in
            let status = viewModel.status(for: remote.id)
            switch status.state {
            case .connecting, .disconnecting:
                return (remote.displayName, status.state, status.updatedAt)
            case .connected, .disconnected, .error:
                return nil
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func statusTooltip(
        counts: (connected: Int, active: Int, errors: Int, disconnected: Int),
        activeOperations: [(name: String, state: RemoteConnectionState, startedAt: Date)],
        recoveryIndicator: RemotesViewModel.RecoveryIndicator?,
        reconnectingCount: Int
    ) -> String {
        var lines: [String] = ["macfuseGui"]
        if !activeOperations.isEmpty {
            let details = activeOperations
                .map { "\(humanLabel(for: $0.state)) \($0.name) (\(elapsedText(since: $0.startedAt)))" }
                .joined(separator: " • ")
            lines.append(details)
        }
        if reconnectingCount > 0 {
            lines.append("Reconnecting \(reconnectingCount) remote(s)")
        }
        if let recoveryIndicator {
            let reason = recoveryReasonLabel(recoveryIndicator.reason)
            lines.append(
                "Recovery \(reason): pending \(recoveryIndicator.pendingRemoteCount), queued \(recoveryIndicator.scheduledReconnectCount) (\(elapsedText(since: recoveryIndicator.startedAt)))"
            )
        }
        lines.append("Connected \(counts.connected) • Active \(counts.active) • Errors \(counts.errors) • Disconnected \(counts.disconnected)")
        return lines.joined(separator: "\n")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func recoveryReasonLabel(_ reason: String) -> String {
        switch reason {
        case "wake":
            return "after wake"
        case "network-restored":
            return "after network restore"
        default:
            return reason
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func humanLabel(for state: RemoteConnectionState) -> String {
        switch state {
        case .connecting:
            return "Connecting"
        case .disconnecting:
            return "Disconnecting"
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Error"
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func elapsedText(since date: Date) -> String {
        let interval = max(0, Date().timeIntervalSince(date))
        if interval < 10 {
            return String(format: "%.1fs", interval)
        }
        let elapsed = Int(interval)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func applyConnectedCountLabel(connectedCount: Int, color: NSColor, to button: NSStatusBarButton) {
        let countText = connectedCount > 99 ? "99+" : "\(connectedCount)"
        let titleText = " \(countText)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: color
        ]
        button.attributedTitle = NSAttributedString(string: titleText, attributes: attributes)
        button.imagePosition = .imageLeading

        let countWidth = (titleText as NSString).size(withAttributes: attributes).width
        statusItem.length = max(44, NSStatusItem.squareLength + countWidth + 8)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func openSettings() {
        settingsWindowController.showWindow(nil)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func refreshStatus() {
        Task {
            viewModel.refreshDependencies()
            await viewModel.refreshAllStatuses()
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func copyDiagnostics() {
        viewModel.copyDiagnosticsToPasteboard()
    }

    /// Beginner note: Emergency reset runs asynchronously so menu UI remains responsive.
    private func forceResetAllMounts() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.viewModel.forceResetAllMountsFromMenu()
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func connectRemote(_ remoteID: UUID) {
        Task { await viewModel.connect(remoteID: remoteID) }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func disconnectRemote(_ remoteID: UUID) {
        Task { await viewModel.disconnect(remoteID: remoteID) }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func openRemoteMountInPreferredEditor(_ remoteID: UUID) {
        openRemoteMountInEditor(remoteID, mode: .preferredWithFallback)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func openRemoteMountInEditor(_ remoteID: UUID, pluginID: String) {
        openRemoteMountInEditor(remoteID, mode: .explicit(pluginID: pluginID))
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func openRemoteMountInEditor(_ remoteID: UUID, mode: EditorOpenMode) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            guard let remote = self.viewModel.remotes.first(where: { $0.id == remoteID }) else {
                return
            }

            let status = self.viewModel.status(for: remote.id)
            guard status.state == .connected else {
                self.viewModel.alertMessage = "Remote \(remote.displayName) is not connected yet."
                return
            }

            let targetPath: String
            if let mountedPath = status.mountedPath, !mountedPath.isEmpty {
                targetPath = mountedPath
            } else {
                targetPath = remote.localMountPoint
            }

            guard self.directoryExists(targetPath) else {
                self.viewModel.alertMessage = "Mounted path not found: \(targetPath)"
                return
            }

            let folderURL = URL(fileURLWithPath: targetPath, isDirectory: true)
            let result = await self.editorOpenService.open(
                folderURL: folderURL,
                remoteName: remote.displayName,
                mode: mode
            )
            self.logEditorOpenResult(
                result,
                remoteName: remote.displayName,
                folderPath: folderURL.path
            )

            guard !result.success else {
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            self.viewModel.alertMessage = "\(result.message ?? "Could not open an editor.") Opened mount folder in Finder instead."
        }
    }

    /// Beginner note: Write a compact and consistent diagnostics stream for plugin attempts/results.
    private func logEditorOpenResult(
        _ result: EditorOpenResult,
        remoteName: String,
        folderPath: String
    ) {
        if result.pluginResults.isEmpty {
            viewModel.appendDiagnostic(
                level: .warning,
                category: "editor",
                message: "No editor plugin attempts for \(remoteName) (\(folderPath)). \(result.message ?? "No detail")"
            )
            return
        }

        var failureNotes: [String] = []
        var sawVSCodePlugin = false

        for pluginResult in result.pluginResults {
            let category = diagnosticCategory(for: pluginResult.pluginID)
            sawVSCodePlugin = sawVSCodePlugin || category == "vscode"

            for attempt in pluginResult.attempts {
                let output = compactDiagnosticText(attempt.output.isEmpty ? "exit \(attempt.exitCode)" : attempt.output)
                let statusText = attempt.success ? "success" : "failure"
                let message = "editor attempt pluginID=\(pluginResult.pluginID) plugin=\(pluginResult.pluginDisplayName) label=\(attempt.label) executable=\(attempt.executable) args=\(attempt.arguments.joined(separator: " ")) timeoutSec=\(String(format: "%.1f", attempt.timeoutSeconds)) status=\(statusText) exit=\(attempt.exitCode) timedOut=\(attempt.timedOut) output=\(output)"
                viewModel.appendDiagnostic(
                    level: attempt.success ? .info : .debug,
                    category: category,
                    message: message
                )

                if !attempt.success {
                    failureNotes.append("\(pluginResult.pluginDisplayName):\(attempt.label)->\(output)")
                }
            }
        }

        if result.success, let pluginName = result.launchedPluginDisplayName {
            let pluginID = result.launchedPluginID ?? "-"
            let category = diagnosticCategory(for: pluginID)
            let successMessage = "Opened \(remoteName) in \(pluginName) (\(folderPath))."
            viewModel.appendDiagnostic(level: .info, category: "editor", message: successMessage)
            if category != "editor" {
                viewModel.appendDiagnostic(level: .info, category: category, message: successMessage)
            }
            return
        }

        let joinedFailures = failureNotes.joined(separator: " | ")
        let failureMessage = "Unable to open \(remoteName) in editor (\(folderPath)). Attempts: \(joinedFailures)"
        viewModel.appendDiagnostic(level: .warning, category: "editor", message: failureMessage)
        if sawVSCodePlugin {
            viewModel.appendDiagnostic(level: .warning, category: "vscode", message: failureMessage)
        }
    }

    private func diagnosticCategory(for pluginID: String) -> String {
        pluginID == "vscode" ? "vscode" : "editor"
    }

    private func compactDiagnosticText(_ value: String, limit: Int = 180) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.count <= limit {
            return normalized
        }
        return String(normalized.prefix(limit)) + "…"
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func directoryExists(_ path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func quitApp() {
        if popover.isShown {
            popover.performClose(nil)
        }
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.forceQuit()
            return
        }
        NSApp.terminate(nil)
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
private struct MenuPopoverContentView: View {
    @ObservedObject var viewModel: RemotesViewModel
    @ObservedObject var editorPluginRegistry: EditorPluginRegistry

    let onOpenSettings: () -> Void
    let onRefresh: () -> Void
    let onCopyDiagnostics: () -> Void
    let onConnect: (UUID) -> Void
    let onDisconnect: (UUID) -> Void
    let onOpenInPreferredEditor: (UUID) -> Void
    let onOpenInEditorPlugin: (UUID, String) -> Void
    let onForceResetMounts: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dependencySection
            recoverySection

            if viewModel.remotes.isEmpty {
                Text("No remotes configured")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.remotes) { remote in
                            RemotePopoverRow(
                                remote: remote,
                                status: viewModel.status(for: remote.id),
                                badgeStateRawValue: viewModel.statusBadgeRawValue(for: remote.id),
                                preferredPluginDisplayName: preferredPluginDisplayName,
                                activeEditorPlugins: activeEditorPlugins,
                                onConnect: { onConnect(remote.id) },
                                onDisconnect: { onDisconnect(remote.id) },
                                onOpenInPreferredEditor: { onOpenInPreferredEditor(remote.id) },
                                onOpenInEditorPlugin: { pluginID in
                                    onOpenInEditorPlugin(remote.id, pluginID)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button("Refresh", action: onRefresh)
                Button("Copy Diagnostics", action: onCopyDiagnostics)
                Button("Force Reset Mounts", action: onForceResetMounts)
                Spacer()
                Button("Settings…", action: onOpenSettings)
                Button("Quit", action: onQuit)
                    .keyboardShortcut("q", modifiers: [.command])
            }
        }
        .padding(12)
        .frame(width: 460, height: 520)
    }

    private var header: some View {
        HStack {
            Text("macfuseGui")
                .font(.headline)
            Spacer()
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dependencySection: some View {
        if let dependency = viewModel.dependencyStatus, !dependency.isReady {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dependencies missing")
                    .font(.caption)
                    .foregroundStyle(.red)
                ForEach(dependency.issues, id: \.self) { issue in
                    Text("• \(issue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if let recovery = viewModel.recoveryIndicator {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(
                    "Re-establishing after \(recoveryReasonLabel(recovery.reason)) • pending \(recovery.pendingRemoteCount), queued \(recovery.scheduledReconnectCount)"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                Spacer()
            }
            Divider()
        }
    }

    private var summaryText: String {
        var connected = 0
        var active = 0
        var errors = 0
        var disconnected = 0
        var reconnecting = 0

        for remote in viewModel.remotes {
            if viewModel.isRemoteInRecoveryReconnect(remote.id) {
                reconnecting += 1
                active += 1
                continue
            }

            switch viewModel.status(for: remote.id).state {
            case .connected:
                connected += 1
                active += 1
            case .connecting, .disconnecting:
                active += 1
            case .error:
                errors += 1
            case .disconnected:
                disconnected += 1
            }
        }

        return "C \(connected) • R \(reconnecting) • A \(active) • E \(errors) • D \(disconnected)"
    }

    private var preferredPluginDisplayName: String {
        editorPluginRegistry.preferredPlugin()?.displayName ?? "Editor"
    }

    private var activeEditorPlugins: [EditorPluginDefinition] {
        editorPluginRegistry.activePluginsInPriorityOrder()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func recoveryReasonLabel(_ reason: String) -> String {
        switch reason {
        case "wake":
            return "wake"
        case "network-restored":
            return "network restore"
        default:
            return reason
        }
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
private struct RemotePopoverRow: View {
    let remote: RemoteConfig
    let status: RemoteStatus
    let badgeStateRawValue: String
    let preferredPluginDisplayName: String
    let activeEditorPlugins: [EditorPluginDefinition]
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onOpenInPreferredEditor: () -> Void
    let onOpenInEditorPlugin: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(remote.displayName)
                    .font(.headline)
                Spacer()
                StatusBadgeView(stateRawValue: badgeStateRawValue)
            }

            Text("\(remote.username)@\(remote.host):\(remote.port)  \(remote.remoteDirectory)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let mountedPath = status.mountedPath, !mountedPath.isEmpty {
                Text("Mounted: \(mountedPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastError = status.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            HStack(spacing: 8) {
                let canConnect = status.state == .disconnected || status.state == .error || status.state == .disconnecting
                let canDisconnect = status.state == .connected || status.state == .connecting

                Button("Connect", action: onConnect)
                    .disabled(!canConnect)
                Button("Disconnect", action: onDisconnect)
                    .disabled(!canDisconnect)
                Button("Open in \(preferredPluginDisplayName)", action: onOpenInPreferredEditor)
                    .disabled(status.state != .connected || activeEditorPlugins.isEmpty)
                Menu("Open In…") {
                    if activeEditorPlugins.isEmpty {
                        Text("No active editor plugins")
                    } else {
                        ForEach(activeEditorPlugins) { plugin in
                            Button(plugin.displayName) {
                                onOpenInEditorPlugin(plugin.id)
                            }
                        }
                    }
                }
                .disabled(status.state != .connected || activeEditorPlugins.isEmpty)
                Spacer()
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
