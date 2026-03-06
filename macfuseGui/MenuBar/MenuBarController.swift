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
    // By design: keep a single global status item to prevent duplicate menu bar icons when the app is
    // relaunched in unusual contexts (for example, rapid relaunches or test-host processes).
    private static var activeStatusItem: NSStatusItem?

    private let viewModel: RemotesViewModel
    private let settingsWindowController: SettingsWindowController
    private let editorPluginRegistry: EditorPluginRegistry
    private let editorOpenService: EditorOpenService
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var popoverHostingController: NSHostingController<MenuPopoverContentView>?

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
        popover.contentSize = NSSize(width: 484, height: 548)
        installPopoverContentIfNeeded()
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

        installPopoverContentIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Beginner note: Install one persistent hosting controller to avoid rebuilding the
    /// whole popover view hierarchy every open/close cycle.
    private func installPopoverContentIfNeeded() {
        guard popoverHostingController == nil else {
            return
        }
        let hosting = NSHostingController(rootView: makeMenuPopoverContentView())
        popover.contentViewController = hosting
        popoverHostingController = hosting
    }

    /// Beginner note: This method centralizes popover callback wiring.
    private func makeMenuPopoverContentView() -> MenuPopoverContentView {
        MenuPopoverContentView(
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
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func updateStatusItemIndicator() {
        guard let button = statusItem.button else {
            return
        }
        let appName = Self.appDisplayName()

        // These computed values drive both icon color and tooltip content.
        let summary = viewModel.connectionSummary()
        let activeOperations = currentActiveOperations()
        let recoveryIndicator = viewModel.recoveryIndicator
        let wakePulseActive = (viewModel.wakeAnimationUntil ?? .distantPast) > Date()
        let reconnectingCount = summary.reconnecting
        let hasActivityAnimation = wakePulseActive || !activeOperations.isEmpty || recoveryIndicator != nil || reconnectingCount > 0
        setActivityTimerEnabled(hasActivityAnimation)

        // Icon priority:
        // 1) activity animation
        // 2) warning icon if dependencies/errors
        // 3) normal icon
        let symbolCandidates: [String]
        if hasActivityAnimation, !activitySymbols.isEmpty {
            symbolCandidates = [activitySymbols[activityFrame % activitySymbols.count], "arrow.triangle.2.circlepath"] + defaultSymbols
        } else if hasActivityAnimation {
            symbolCandidates = ["arrow.triangle.2.circlepath"] + defaultSymbols
        } else if (viewModel.dependencyStatus?.isReady == false) || summary.errors > 0 {
            symbolCandidates = ["exclamationmark.triangle"] + defaultSymbols
        } else {
            symbolCandidates = defaultSymbols
        }

        let selectedSymbolName = symbolCandidates.first { symbolName in
            NSImage(systemSymbolName: symbolName, accessibilityDescription: appName) != nil
        }

        if let selectedSymbolName,
           let icon = NSImage(systemSymbolName: selectedSymbolName, accessibilityDescription: appName) {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            let configured = icon.withSymbolConfiguration(symbolConfig) ?? icon
            configured.isTemplate = true
            button.image = configured
            // Orange count means sleep/reconnect/recovery activity.
            // Green count means steady connected state.
            let countColor: NSColor = (viewModel.systemSleeping || reconnectingCount > 0 || recoveryIndicator != nil) ? .systemOrange : .systemGreen
            applyConnectedCountLabel(connectedCount: summary.connected, color: countColor, to: button)
        } else {
            button.image = nil
            button.attributedTitle = NSAttributedString(string: "")
            button.title = "FUSE"
        }

        button.toolTip = statusTooltip(
            summary: summary,
            activeOperations: activeOperations,
            recoveryIndicator: recoveryIndicator,
            reconnectingCount: reconnectingCount
        )
        button.setAccessibilityLabel(L10n.format("%@ — %lld connected", appName, Int64(summary.connected)))
        button.needsDisplay = true
        button.displayIfNeeded()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func setActivityTimerEnabled(_ enabled: Bool) {
        if enabled {
            guard activityTimer == nil else {
                return
            }

            // Closure timer keeps behavior identical while avoiding Objective-C selector wiring.
            let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleActivityTimerTick()
                }
            }
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

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func handleActivityTimerTick() {
        guard !activitySymbols.isEmpty else {
            updateStatusItemIndicator()
            return
        }
        activityFrame = (activityFrame + 1) % activitySymbols.count
        updateStatusItemIndicator()
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
        summary: RemotesViewModel.ConnectionSummary,
        activeOperations: [(name: String, state: RemoteConnectionState, startedAt: Date)],
        recoveryIndicator: RemotesViewModel.RecoveryIndicator?,
        reconnectingCount: Int
    ) -> String {
        var lines: [String] = [Self.appDisplayName()]
        if !activeOperations.isEmpty {
            let details = activeOperations
                .map { L10n.format("%@ %@ (%@)", humanLabel(for: $0.state), $0.name, elapsedText(since: $0.startedAt)) }
                .joined(separator: " • ")
            lines.append(details)
        }
        if reconnectingCount > 0 {
            lines.append(L10n.format("Reconnecting %lld remote(s)", Int64(reconnectingCount)))
        }
        if let recoveryIndicator {
            let reason = recoveryReasonLabel(recoveryIndicator.reason)
            lines.append(
                L10n.format(
                    "Recovery %@: pending %lld, queued %lld (%@)",
                    reason,
                    Int64(recoveryIndicator.pendingRemoteCount),
                    Int64(recoveryIndicator.scheduledReconnectCount),
                    elapsedText(since: recoveryIndicator.startedAt)
                )
            )
        }
        lines.append(
            L10n.format(
                "Connected %lld • Reconnecting %lld • Errors %lld • Disconnected %lld",
                Int64(summary.connected),
                Int64(summary.reconnecting),
                Int64(summary.errors),
                Int64(summary.disconnected)
            )
        )
        return lines.joined(separator: "\n")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func recoveryReasonLabel(_ reason: String) -> String {
        Self.recoveryReasonDisplayText(reason)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func humanLabel(for state: RemoteConnectionState) -> String {
        switch state {
        case .connecting:
            return L10n.tr("Connecting")
        case .disconnecting:
            return L10n.tr("Disconnecting")
        case .connected:
            return L10n.tr("Connected")
        case .disconnected:
            return L10n.tr("Disconnected")
        case .error:
            return L10n.tr("Error")
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func elapsedText(since date: Date) -> String {
        Self.formattedElapsedText(since: date, now: Date())
    }

    nonisolated static func recoveryReasonDisplayText(_ reason: String) -> String {
        switch reason {
        case "wake":
            return L10n.tr("after wake")
        case "network-restored":
            return L10n.tr("after network restore")
        default:
            return reason
        }
    }

    nonisolated static func formattedElapsedText(since date: Date, now: Date) -> String {
        let interval = max(0, now.timeIntervalSince(date))
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

    nonisolated static func appDisplayName() -> String {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        if let bundleName, !bundleName.isEmpty {
            return bundleName
        }
        return "macfuseGui"
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
                self.viewModel.alertMessage = L10n.format("Remote %@ is not connected yet.", remote.displayName)
                return
            }

            let targetPath: String
            if let mountedPath = status.mountedPath, !mountedPath.isEmpty {
                targetPath = mountedPath
            } else {
                targetPath = remote.localMountPoint
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
            self.viewModel.alertMessage = L10n.format(
                "%@ Opened mount folder in Finder instead.",
                result.message ?? L10n.tr("Could not open an editor.")
            )
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
                let message = "editor attempt pluginID=\(pluginResult.pluginID) plugin=\(pluginResult.pluginDisplayName) label=\(attempt.label) executable=\(attempt.executable) args=\(attempt.arguments.joined(separator: " ")) timeoutSec=\(String(format: "%.1f", attempt.timeoutSeconds)) status=\(statusText) exit=\(attempt.exitCode) timedOut=\(attempt.timedOut) failedToStart=\(attempt.failedToStart) output=\(output)"
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
        let normalized = value.collapsedAndTruncatedForDisplay(limit: limit)

        return normalized
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
    @AppStorage("menuPopover.usesCompactRemoteRows") private var usesCompactRemoteRows = false

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
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.remotes) { remote in
                            RemotePopoverRow(
                                remote: remote,
                                status: viewModel.status(for: remote.id),
                                badgeState: viewModel.statusBadgeState(for: remote.id),
                                showsConnectionDetails: !usesCompactRemoteRows,
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

            footerBar
        }
        .padding(14)
        .frame(width: 484, height: 548)
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color.blue.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MenuBarController.appDisplayName())
                        .font(.title3.weight(.bold))
                    Text(appVersionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        usesCompactRemoteRows.toggle()
                    } label: {
                        Image(systemName: usesCompactRemoteRows ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    }
                    .buttonStyle(MenuPopoverButtonStyle(kind: .neutral))
                    .help(usesCompactRemoteRows ? L10n.tr("Show remote path details") : L10n.tr("Hide remote path details"))

                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(MenuPopoverButtonStyle(kind: .neutral))
                    .help(L10n.tr("Refresh all remote statuses"))

                    Button {
                        onOpenSettings()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .buttonStyle(MenuPopoverButtonStyle(kind: .neutral))
                    .help(L10n.tr("Open Settings"))
                }
            }

            HStack(spacing: 8) {
                metricChip(title: "Connected", value: summary.connected, tint: .green)
                metricChip(title: "Reconnecting", value: summary.reconnecting, tint: .orange)
                metricChip(title: "Errors", value: summary.errors, tint: .red)
                metricChip(title: "Disconnected", value: summary.disconnected, tint: .secondary)
            }
        }
        .padding(14)
        .background(menuSurfaceFill(accent: .blue))
        .overlay(menuSurfaceStroke())
        .animation(.easeInOut(duration: 0.18), value: usesCompactRemoteRows)
    }

    @ViewBuilder
    private var dependencySection: some View {
        if let dependency = viewModel.dependencyStatus, !dependency.isReady {
            VStack(alignment: .leading, spacing: 6) {
                Label("Dependencies Missing", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)

                ForEach(dependency.issues, id: \.self) { issue in
                    Text(issue)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.82))
                }
            }
            .padding(12)
            .background(menuNoticeFill(tint: .red))
            .overlay(menuNoticeStroke(tint: .red))
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if let recovery = viewModel.recoveryIndicator {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recovery In Progress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(
                        L10n.format(
                            "After %@ · pending %lld · queued %lld",
                            recoveryReasonLabel(recovery.reason),
                            Int64(recovery.pendingRemoteCount),
                            Int64(recovery.scheduledReconnectCount)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.82))
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(menuNoticeFill(tint: .orange))
            .overlay(menuNoticeStroke(tint: .orange))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No remotes configured")
                .font(.headline)
            Text("Open Settings to add your first SSHFS profile.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(MenuPopoverButtonStyle(kind: .filled(.blue)))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(menuSurfaceFill(accent: .gray))
        .overlay(menuSurfaceStroke())
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            Button {
                onCopyDiagnostics()
            } label: {
                Label("Diagnostics", systemImage: "doc.on.doc")
            }
            .buttonStyle(MenuPopoverButtonStyle(kind: .neutral))

            Button {
                onForceResetMounts()
            } label: {
                Label("Reset Mounts", systemImage: "wrench.and.screwdriver")
            }
            .buttonStyle(MenuPopoverButtonStyle(kind: .soft(.orange)))

            Spacer(minLength: 0)

            Button {
                onQuit()
            } label: {
                Label("Quit", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(MenuPopoverButtonStyle(kind: .filled(.red)))
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var summary: RemotesViewModel.ConnectionSummary {
        viewModel.connectionSummary()
    }

    private var preferredPluginDisplayName: String {
        editorPluginRegistry.preferredPlugin()?.displayName ?? "Editor"
    }

    private var activeEditorPlugins: [EditorPluginDefinition] {
        editorPluginRegistry.activePluginsInPriorityOrder()
    }

    private var appVersionText: String {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        return "v\(version) (\(build))"
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func recoveryReasonLabel(_ reason: String) -> String {
        MenuBarController.recoveryReasonDisplayText(reason)
    }

    private func metricChip(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(L10n.tr(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func menuSurfaceFill(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(NSColor.controlBackgroundColor).opacity(0.92),
                        accent.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func menuSurfaceStroke() -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }

    private func menuNoticeFill(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(tint.opacity(0.10))
    }

    private func menuNoticeStroke(tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(tint.opacity(0.22), lineWidth: 1)
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
private struct RemotePopoverRow: View {
    private enum OpenEditorPresentationMode {
        case none
        case single
        case picker
    }

    let remote: RemoteConfig
    let status: RemoteStatus
    let badgeState: RemoteStatusBadgeState
    let showsConnectionDetails: Bool
    let preferredPluginDisplayName: String
    let activeEditorPlugins: [EditorPluginDefinition]
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onOpenInPreferredEditor: () -> Void
    let onOpenInEditorPlugin: (String) -> Void

    private var openEditorPresentationMode: OpenEditorPresentationMode {
        switch activeEditorPlugins.count {
        case 0:
            return .none
        case 1:
            return .single
        default:
            return .picker
        }
    }

    private var singleEditorDisplayName: String {
        activeEditorPlugins.first?.displayName ?? preferredPluginDisplayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsConnectionDetails ? 10 : 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(remote.displayName)
                        .font(.headline.weight(.semibold))

                    Text("\(remote.username)@\(remote.host):\(remote.port)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusBadgeView(state: badgeState)
            }

            if showsConnectionDetails {
                infoLine(title: "Remote", systemImage: "folder", value: remote.remoteDirectory)
                infoLine(title: "Local", systemImage: "internaldrive", value: remote.localMountPoint)

                if let mountedPath = status.mountedPath, !mountedPath.isEmpty {
                    infoLine(title: "Mounted", systemImage: "checkmark.circle.fill", value: mountedPath)
                }
            }

            if let lastError = status.lastError, !lastError.isEmpty {
                Text(lastError)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.10))
                )
            }

            HStack(spacing: 8) {
                primaryActionButton

                switch openEditorPresentationMode {
                case .none:
                    Button("Open In") {}
                        .disabled(true)
                        .buttonStyle(MenuPopoverButtonStyle(kind: .neutral))
                case .single:
                    Button {
                        onOpenInPreferredEditor()
                    } label: {
                        Label(L10n.format("Open in %@", singleEditorDisplayName), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(MenuPopoverButtonStyle(kind: .neutral))
                    .disabled(status.state != .connected)
                case .picker:
                    Menu {
                        ForEach(activeEditorPlugins) { plugin in
                            Button(plugin.displayName) {
                                onOpenInEditorPlugin(plugin.id)
                            }
                        }
                    } label: {
                        MenuPopoverButtonLabel(
                            title: "Open In",
                            systemImage: "square.and.arrow.up",
                            kind: .neutral
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(status.state != .connected)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(NSColor.controlBackgroundColor).opacity(0.92),
                            accentColor.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var accentColor: Color {
        switch badgeState {
        case .connected:
            return .green
        case .reconnecting, .connecting, .disconnecting:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .blue
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch status.state {
        case .connected:
            Button {
                onDisconnect()
            } label: {
                Label("Disconnect", systemImage: "bolt.slash.fill")
            }
            .buttonStyle(MenuPopoverButtonStyle(kind: .filled(.orange)))
        case .connecting:
            Label("Connecting", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                )
        case .disconnecting:
            Label("Disconnecting", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
        case .disconnected, .error:
            Button {
                onConnect()
            } label: {
                Label("Connect", systemImage: "bolt.fill")
            }
            .buttonStyle(MenuPopoverButtonStyle(kind: .filled(.blue)))
            .disabled(!status.canConnect)
        }
    }

    private func infoLine(title: String, systemImage: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(L10n.tr(title), systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private enum MenuPopoverButtonKind {
    case neutral
    case soft(Color)
    case filled(Color)
}

private struct MenuPopoverButtonLabel: View {
    let title: String
    let systemImage: String
    let kind: MenuPopoverButtonKind

    var body: some View {
        Label(L10n.tr(title), systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .foregroundStyle(foregroundColor)
    }

    private var backgroundColor: Color {
        switch kind {
        case .neutral:
            return Color(NSColor.controlBackgroundColor).opacity(0.96)
        case .soft(let tint):
            return tint.opacity(0.14)
        case .filled(let tint):
            return tint.opacity(0.92)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .neutral:
            return Color.primary.opacity(0.12)
        case .soft(let tint):
            return tint.opacity(0.24)
        case .filled(let tint):
            return tint.opacity(0.38)
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .neutral:
            return Color.primary.opacity(0.84)
        case .soft(let tint):
            return tint.opacity(0.96)
        case .filled:
            return .white
        }
    }
}

private struct MenuPopoverButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let kind: MenuPopoverButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .opacity(isEnabled ? 1 : 0.52)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .neutral:
            return Color(NSColor.controlBackgroundColor).opacity(isPressed ? 1 : 0.96)
        case .soft(let tint):
            return tint.opacity(isPressed ? 0.22 : 0.14)
        case .filled(let tint):
            return tint.opacity(isPressed ? 0.82 : 0.92)
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        switch kind {
        case .neutral:
            return Color.primary.opacity(isPressed ? 0.18 : 0.12)
        case .soft(let tint):
            return tint.opacity(isPressed ? 0.34 : 0.24)
        case .filled(let tint):
            return tint.opacity(isPressed ? 0.52 : 0.38)
        }
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .neutral:
            return Color.primary.opacity(isPressed ? 1 : 0.84)
        case .soft(let tint):
            return tint.opacity(isPressed ? 1 : 0.96)
        case .filled:
            return .white.opacity(isPressed ? 0.96 : 1)
        }
    }
}
