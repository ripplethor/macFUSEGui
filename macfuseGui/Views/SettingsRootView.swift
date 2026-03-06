// BEGINNER FILE GUIDE
// Layer: SwiftUI view layer
// Purpose: This file defines visual layout and interaction controls shown to the user.
// Called by: Instantiated by parent views, window controllers, or app bootstrap code.
// Calls into: Reads observed state from view models and triggers callbacks for actions.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import SwiftUI

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct SettingsRootView: View {
    static let minimumWindowSize = NSSize(width: 980, height: 720)

    @ObservedObject var viewModel: RemotesViewModel
    let onOpenEditorPlugins: () -> Void

    @State private var activeEditorSession: EditorSession?
    @State private var pendingRemoteDeletion: PendingRemoteDeletion?

    var body: some View {
        VStack(spacing: 16) {
            if let message = viewModel.alertMessage, !message.isEmpty {
                settingsAlertBanner(message: message)
            }

            settingsHeader

            GeometryReader { geometry in
                let paneHeight = max(0, geometry.size.height)

                HStack(alignment: .top, spacing: 16) {
                    remotesPane
                        .frame(minWidth: 410, idealWidth: 426, maxWidth: 440, alignment: .topLeading)
                        .frame(height: paneHeight, alignment: .topLeading)

                    detailPanel
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .frame(height: paneHeight, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(18)
        .frame(
            minWidth: Self.minimumWindowSize.width,
            minHeight: Self.minimumWindowSize.height
        )
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(item: $activeEditorSession) { session in
            RemoteEditorView(initialDraft: session.draft, remotesViewModel: viewModel) { savedID in
                activeEditorSession = nil
                if let savedID {
                    viewModel.selectedRemoteID = savedID
                }
            }
        }
        .alert(
            "Delete Remote?",
            isPresented: pendingRemoteDeletionPresentedBinding,
            presenting: pendingRemoteDeletion
        ) { deletion in
            Button("Delete", role: .destructive) {
                viewModel.deleteRemote(deletion.id)
                if viewModel.selectedRemoteID == deletion.id {
                    viewModel.selectedRemoteID = nil
                }
                pendingRemoteDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoteDeletion = nil
            }
        } message: { deletion in
            Text(L10n.format("Delete '%@'? This removes saved settings and stored credentials.", deletion.displayName))
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceQuitRequested)) { _ in
            activeEditorSession = nil
            pendingRemoteDeletion = nil
        }
        .onAppear {
            viewModel.refreshLaunchAtLoginState()
        }
    }

    private var settingsHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.22), Color.teal.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Settings")
                        .font(.title2.weight(.bold))

                    Text("Manage saved remotes, login behavior, and editor integration from one place.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        settingsMetricChip(
                            text: L10n.format("%lld Remotes", Int64(viewModel.remotes.count)),
                            systemImage: "server.rack",
                            tint: .blue
                        )
                        settingsMetricChip(
                            text: launchStateSummaryText,
                            systemImage: launchStateSymbolName,
                            tint: launchStateTint
                        )
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 10) {
                Text("Startup")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Toggle("Launch At Login", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                    .help("Open macfuseGui automatically when you log in.")

                Text(launchStateDetailText)
                    .font(.caption)
                    .foregroundStyle(launchStateTint)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    onOpenEditorPlugins()
                } label: {
                    Label("Editor Plugins", systemImage: "puzzlepiece.extension")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 290, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .padding(18)
        .background(settingsSurfaceFill(accent: .blue))
        .overlay(settingsSurfaceStroke())
    }

    private func settingsAlertBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Dismiss") {
                viewModel.alertMessage = nil
            }
            .buttonStyle(.link)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.30), lineWidth: 1)
        )
    }

    private var remotesPane: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Remotes")
                            .font(.title3.weight(.bold))
                        settingsMetricChip(
                            text: "\(viewModel.remotes.count)",
                            systemImage: "line.3.horizontal.decrease.circle",
                            tint: .indigo
                        )
                    }

                    Text("Select a profile on the left, then manage details and actions on the right.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    openEditor(
                        with: RemoteDraft(
                            port: 22,
                            authMode: .privateKey,
                            remoteDirectory: "/"
                        )
                    )
                } label: {
                    Label("Add Remote", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(18)

            Divider()
                .padding(.horizontal, 18)

            RemotesListView(
                remotes: viewModel.remotes,
                statuses: viewModel.statuses,
                badgeStateForRemote: { remoteID in
                    viewModel.statusBadgeState(for: remoteID)
                },
                selectedRemoteID: $viewModel.selectedRemoteID,
                onConnect: { id in
                    Task { await viewModel.connect(remoteID: id) }
                },
                onDisconnect: { id in
                    Task { await viewModel.disconnect(remoteID: id) }
                }
            )
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(settingsSurfaceFill(accent: .indigo))
        .overlay(settingsSurfaceStroke())
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let remote = selectedRemote {
            let status = viewModel.status(for: remote.id)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text(remote.displayName)
                                .font(.title2.weight(.bold))
                            if remote.autoConnectOnLaunch {
                                settingsMetricChip(
                                    text: L10n.tr("Auto Connect"),
                                    systemImage: "bolt.fill",
                                    tint: .orange
                                )
                            }
                        }

                        Text("\(remote.username)@\(remote.host):\(remote.port)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    StatusBadgeView(state: viewModel.statusBadgeState(for: remote.id))
                }

                detailSection(title: "Connection", accent: .blue) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 140), spacing: 16),
                            GridItem(.flexible(minimum: 140), spacing: 16)
                        ],
                        alignment: .leading,
                        spacing: 14
                    ) {
                        detailField(title: "Host", value: remote.host)
                        detailField(title: "Port", value: "\(remote.port)")
                        detailField(title: "Username", value: remote.username)
                        detailField(title: "Authentication", value: remote.authMode.displayName)
                    }
                }

                detailSection(title: "Mount", accent: .teal) {
                    VStack(alignment: .leading, spacing: 14) {
                        detailField(title: "Remote Directory", value: remote.remoteDirectory, monospaced: true)
                        detailField(title: "Local Mount Point", value: remote.localMountPoint, monospaced: true)
                        detailField(
                            title: "Startup Behavior",
                            value: remote.autoConnectOnLaunch
                                ? L10n.tr("Connect automatically when the app launches.")
                                : L10n.tr("Connect manually when you choose.")
                        )
                    }
                }

                if let mounted = status.mountedPath {
                    statusCallout(
                        title: "Mounted",
                        message: mounted,
                        tint: .green
                    )
                }

                if let error = status.lastError, !error.isEmpty {
                    statusCallout(
                        title: "Last Error",
                        message: shortError(error),
                        tint: .red
                    )
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button {
                        let draft = RemoteDraft(remote: remote)
                        openEditor(with: draft)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        var draft = RemoteDraft(remote: remote)
                        draft.id = nil
                        draft.displayName = duplicateDisplayName(for: remote.displayName)
                        openEditor(with: draft)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        pendingRemoteDeletion = PendingRemoteDeletion(
                            id: remote.id,
                            displayName: remote.displayName
                        )
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .foregroundStyle(.red)

                    Spacer()

                    Button {
                        Task { await viewModel.refreshStatus(remoteID: remote.id) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    connectionActionButton(remoteID: remote.id, status: status)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.74))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(settingsSurfaceFill(accent: detailAccent(for: status)))
            .overlay(settingsSurfaceStroke())
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.gray.opacity(0.18), Color.blue.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .frame(width: 56, height: 56)

                Text("Select a remote")
                    .font(.title3.weight(.bold))

                Text("Choose a saved profile on the left, or add a new one to start managing mounts.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    openEditor(
                        with: RemoteDraft(
                            port: 22,
                            authMode: .privateKey,
                            remoteDirectory: "/"
                        )
                    )
                } label: {
                    Label("Add Remote", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(settingsSurfaceFill(accent: .gray))
            .overlay(settingsSurfaceStroke())
        }
    }

    private var launchStateSummaryText: String {
        if viewModel.launchAtLoginState.requiresApproval {
            return L10n.tr("Approval Needed")
        }
        return viewModel.launchAtLoginState.enabled ? L10n.tr("Launch Enabled") : L10n.tr("Launch Disabled")
    }

    private var launchStateDetailText: String {
        if viewModel.launchAtLoginState.requiresApproval {
            return L10n.tr("Pending approval in System Settings -> General -> Login Items.")
        }
        if let detail = viewModel.launchAtLoginState.detail, !detail.isEmpty {
            return detail
        }
        return viewModel.launchAtLoginState.enabled
            ? L10n.tr("The app opens automatically when you log in.")
            : L10n.tr("The app launches manually until you enable startup.")
    }

    private var launchStateTint: Color {
        if viewModel.launchAtLoginState.requiresApproval {
            return .orange
        }
        return viewModel.launchAtLoginState.enabled ? .green : .secondary
    }

    private var launchStateSymbolName: String {
        if viewModel.launchAtLoginState.requiresApproval {
            return "exclamationmark.circle.fill"
        }
        return viewModel.launchAtLoginState.enabled ? "checkmark.circle.fill" : "minus.circle.fill"
    }

    private func settingsMetricChip(text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }

    private func settingsSurfaceFill(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(NSColor.controlBackgroundColor).opacity(0.90),
                        accent.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func settingsSurfaceStroke() -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
    }

    private func detailSection<Content: View>(
        title: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)

                Text(L10n.tr(title))
                    .font(.headline)
            }

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func detailField(title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func statusCallout(title: String, message: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func connectionActionButton(remoteID: UUID, status: RemoteStatus) -> some View {
        switch status.state {
        case .connected:
            Button {
                Task { await viewModel.disconnect(remoteID: remoteID) }
            } label: {
                Label("Disconnect", systemImage: "bolt.slash.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        case .connecting:
            Label("Connecting", systemImage: "arrow.triangle.2.circlepath")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                )
        case .disconnecting:
            Label("Disconnecting", systemImage: "arrow.triangle.2.circlepath")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
        case .disconnected, .error:
            Button {
                Task { await viewModel.connect(remoteID: remoteID) }
            } label: {
                Label("Connect", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(!status.canConnect)
        }
    }

    private func detailAccent(for status: RemoteStatus) -> Color {
        switch status.state {
        case .connected:
            return .green
        case .connecting, .disconnecting:
            return .orange
        case .error:
            return .red
        case .disconnected:
            return .blue
        }
    }

    private var selectedRemote: RemoteConfig? {
        guard let selectedRemoteID = viewModel.selectedRemoteID else {
            return nil
        }
        return viewModel.remotes.first(where: { $0.id == selectedRemoteID })
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func shortError(_ message: String) -> String {
        message.collapsedAndTruncatedForDisplay(limit: 220)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func duplicateDisplayName(for original: String) -> String {
        let base = original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.tr("Remote")
            : original.trimmingCharacters(in: .whitespacesAndNewlines)
        let copyBase = L10n.format("%@ %@", base, L10n.tr("Copy"))

        let existingNames = Set(viewModel.remotes.map { $0.displayName.lowercased() })
        if !existingNames.contains(copyBase.lowercased()) {
            return copyBase
        }

        var index = 2
        let maxIndex = max(existingNames.count + 100, 500)
        while index <= maxIndex {
            let candidate = "\(copyBase) \(index)"
            if !existingNames.contains(candidate.lowercased()) {
                return candidate
            }
            index += 1
        }

        let fallbackSuffix = String(UUID().uuidString.prefix(8)).lowercased()
        return "\(copyBase) \(fallbackSuffix)"
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func openEditor(with draft: RemoteDraft) {
        activeEditorSession = EditorSession(draft: draft)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.launchAtLoginState.isOnForToggle
            },
            set: { newValue in
                viewModel.setLaunchAtLoginEnabled(newValue)
            }
        )
    }

    private var pendingRemoteDeletionPresentedBinding: Binding<Bool> {
        Binding(
            get: { pendingRemoteDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRemoteDeletion = nil
                }
            }
        )
    }

    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    private struct EditorSession: Identifiable {
        let id = UUID()
        let draft: RemoteDraft
    }

    /// Beginner note: This type tracks destructive-delete confirmation context.
    private struct PendingRemoteDeletion: Identifiable {
        let id: UUID
        let displayName: String
    }
}

@MainActor
/// Beginner note: Dedicated window content for managing editor plugins.
struct EditorPluginSettingsView: View {
    @ObservedObject var editorPluginRegistry: EditorPluginRegistry
    @State private var pluginActionError: String?
    @State private var pluginActionStatus: String?
    @State private var selectedPluginID: String?
    @State private var manifestEditorText: String = ""
    @State private var manifestEditorOriginalText: String = ""
    @State private var pendingPluginRemoval: PendingPluginRemoval?

    private struct PendingPluginRemoval: Identifiable {
        let id: String
        let displayName: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let pluginActionError, !pluginActionError.isEmpty {
                    HStack {
                        Text(pluginActionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Dismiss") {
                            self.pluginActionError = nil
                        }
                        .buttonStyle(.link)
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let pluginActionStatus, !pluginActionStatus.isEmpty {
                    HStack {
                        Text(pluginActionStatus)
                            .font(.caption)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Dismiss") {
                            self.pluginActionStatus = nil
                        }
                        .buttonStyle(.link)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                pluginHeader

                HStack(alignment: .top, spacing: 12) {
                    pluginCatalogPane
                        .frame(maxWidth: .infinity)

                    pluginControlsPane
                        .frame(width: 330)
                }

                pluginInlineEditorPane

                if !editorPluginRegistry.loadIssues.isEmpty {
                    pluginIssuesPane
                }
            }
            .padding(16)
        }
        .frame(minWidth: 900, minHeight: 540)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            ensurePluginSelection()
        }
        .onChange(of: editorPluginRegistry.plugins.map(\.id)) { _ in
            ensurePluginSelection()
        }
        .alert(
            "Remove External Plugin?",
            isPresented: pendingRemovalPresentedBinding,
            presenting: pendingPluginRemoval
        ) { removal in
            Button("Remove", role: .destructive) {
                confirmExternalPluginRemoval(pluginID: removal.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { removal in
            Text(L10n.format("Delete '%@' from the external plugin folder?", removal.displayName))
        }
    }

    private var pluginHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.26), Color.teal.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text("Editor Plugins")
                    .font(.headline)
                Text("Choose a primary editor and switch plugins on/off instantly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            pluginMetricChip(title: "Installed", value: "\(editorPluginRegistry.plugins.count)", tint: .blue)
            pluginMetricChip(title: "Active", value: "\(activeEditorPlugins.count)", tint: .green)
            pluginMetricChip(title: "Issues", value: "\(editorPluginRegistry.loadIssues.count)", tint: .orange)

            Button {
                reloadCatalogAndRefreshSelection()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }

    private var pluginCatalogPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Installed Plugins")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if activeEditorPlugins.count > 1 {
                    Text("Star sets preferred")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if editorPluginRegistry.plugins.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No editor plugins are available.")
                        .font(.callout.weight(.medium))
                    Text("Add a JSON manifest, then use Reload Plugins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.textBackgroundColor).opacity(0.56))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(editorPluginRegistry.plugins) { plugin in
                            pluginRow(plugin)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 380)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var pluginControlsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            pluginControlCard(
                title: "Primary Action",
                subtitle: primaryActionSubtitle
            ) {
                if activeEditorPlugins.isEmpty {
                    Button("No active plugins") {}
                        .buttonStyle(.bordered)
                        .disabled(true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if activeEditorPlugins.count == 1, let plugin = activeEditorPlugins.first {
                    Button(L10n.format("Preferred: %@", plugin.displayName)) {}
                        .buttonStyle(.bordered)
                        .disabled(true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker("Preferred Editor", selection: preferredPluginBinding) {
                        ForEach(activeEditorPlugins) { plugin in
                            Text(plugin.displayName)
                                .tag(plugin.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            pluginControlCard(
                title: "External Manifest Folder",
                subtitle: "Place JSON files here to register custom editors."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(editorPluginRegistry.pluginsDirectoryPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(3)

                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            openInFinder(editorPluginRegistry.pluginsDirectoryPath)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            createNewPluginJSON()
                        } label: {
                            Label("New Plugin JSON", systemImage: "plus.rectangle.on.rectangle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)

                        Button {
                            openInFinder(editorPluginRegistry.pluginExamplesDirectoryPath)
                        } label: {
                            Label("Open Examples", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            openInFinder(editorPluginRegistry.builtInReferenceDirectoryPath)
                        } label: {
                            Label("Built-ins", systemImage: "shippingbox")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var pluginInlineEditorPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Inline JSON Editor")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let selectedPlugin {
                    pluginTag(
                        text: selectedPlugin.source == .builtIn ? "Built-in" : "External",
                        tint: selectedPlugin.source == .builtIn ? .gray : .teal
                    )
                }
            }

            if let selectedPlugin {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedPlugin.displayName)
                        .font(.callout.weight(.semibold))

                    if let manifestURL = editorPluginRegistry.manifestFileURL(for: selectedPlugin.id) {
                        Text(manifestURL.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }

                    if selectedPlugin.source == .builtIn {
                        Text("Built-in manifests may be read-only when the app is installed in /Applications.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    TextEditor(text: $manifestEditorText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )

                    HStack(spacing: 8) {
                        Button("Reload File") {
                            loadSelectedPluginManifest()
                        }
                        .buttonStyle(.bordered)

                        Button("Format JSON") {
                            formatManifestEditorJSON()
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Save JSON") {
                            saveSelectedPluginManifest()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(!manifestEditorHasChanges)
                    }
                }
            } else {
                Text("Select a plugin above to edit its manifest inline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func pluginControlCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.tr(title))
                .font(.subheadline.weight(.semibold))
            Text(L10n.tr(subtitle))
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var pluginIssuesPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Plugin Load Issues")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(editorPluginRegistry.loadIssues, id: \.self) { issue in
                        Text("• [\(issue.file)] \(issue.reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 110)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func pluginRow(_ plugin: EditorPluginDefinition) -> some View {
        let isSelected = selectedPluginID == plugin.id
        let canChoosePreferred = activeEditorPlugins.count > 1

        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(plugin.isActive ? Color.green.opacity(0.18) : Color.gray.opacity(0.16))
                Image(systemName: plugin.source == .builtIn ? "hammer.fill" : "shippingbox.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(plugin.isActive ? .green : .secondary)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plugin.displayName)
                        .font(.callout.weight(.semibold))
                    pluginSourceBadge(plugin.source)
                    if canChoosePreferred, plugin.isPreferred {
                        pluginTag(text: "Preferred", tint: .blue)
                    }
                }

                Text(plugin.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Text(L10n.format("Attempts %lld · Priority %lld", Int64(plugin.launchAttempts.count), Int64(plugin.priority)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                pluginTag(
                    text: plugin.isActive ? "Active" : "Inactive",
                    tint: plugin.isActive ? .green : .gray
                )

                HStack(spacing: 6) {
                    Button {
                        selectPlugin(plugin.id)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(isSelected ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit plugin JSON inline")

                    if plugin.source == .external {
                        Button {
                            requestExternalPluginRemoval(plugin)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Remove external plugin")
                    }

                    if canChoosePreferred {
                        Button {
                            editorPluginRegistry.setPreferredPlugin(plugin.id)
                        } label: {
                            Image(systemName: plugin.isPreferred ? "star.fill" : "star")
                                .foregroundStyle(plugin.isPreferred ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!plugin.isActive)
                        .help(plugin.isActive ? "Set as preferred editor" : "Enable plugin to set as preferred")
                    }

                    Toggle("", isOn: pluginActiveBinding(for: plugin))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            selectPlugin(plugin.id)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? Color.blue.opacity(0.12)
                        : (plugin.isActive
                            ? Color.green.opacity(0.10)
                            : Color(NSColor.textBackgroundColor).opacity(0.50))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected
                        ? Color.blue.opacity(0.45)
                        : (plugin.isActive ? Color.green.opacity(0.30) : Color.primary.opacity(0.07)),
                    lineWidth: 1
                )
        )
    }

    private func pluginSourceBadge(_ source: EditorPluginSource) -> some View {
        pluginTag(
            text: source == .builtIn ? "Built-in" : "External",
            tint: source == .builtIn ? .gray : .teal
        )
    }

    private func pluginMetricChip(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(L10n.tr(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.14))
        )
    }

    private func pluginTag(text: String, tint: Color) -> some View {
        Text(L10n.tr(text))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }

    private var activeEditorPlugins: [EditorPluginDefinition] {
        editorPluginRegistry.activePluginsInPriorityOrder()
    }

    private var primaryActionSubtitle: String {
        switch activeEditorPlugins.count {
        case 0:
            return L10n.tr("Enable at least one plugin to use Open In.")
        case 1:
            return L10n.tr("A single active plugin is used directly.")
        default:
            return L10n.tr("Menu bar opens preferred editor first, then falls back across active plugins.")
        }
    }

    private var selectedPlugin: EditorPluginDefinition? {
        guard let selectedPluginID else {
            return nil
        }
        return editorPluginRegistry.plugin(id: selectedPluginID)
    }

    private var manifestEditorHasChanges: Bool {
        manifestEditorText != manifestEditorOriginalText
    }

    private var pendingRemovalPresentedBinding: Binding<Bool> {
        Binding(
            get: { pendingPluginRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    pendingPluginRemoval = nil
                }
            }
        )
    }

    private var preferredPluginBinding: Binding<String> {
        Binding(
            get: {
                editorPluginRegistry.preferredPluginID ?? ""
            },
            set: { newValue in
                let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                editorPluginRegistry.setPreferredPlugin(value.isEmpty ? nil : value)
            }
        )
    }

    private func pluginActiveBinding(for plugin: EditorPluginDefinition) -> Binding<Bool> {
        Binding(
            get: {
                plugin.isActive
            },
            set: { active in
                editorPluginRegistry.setPluginActive(active, pluginID: plugin.id)
            }
        )
    }

    private func openInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func reloadCatalogAndRefreshSelection() {
        let hadUnsavedChanges = manifestEditorHasChanges
        editorPluginRegistry.reloadCatalog()
        ensurePluginSelection()
        pluginActionError = nil
        pluginActionStatus = hadUnsavedChanges
            ? L10n.tr("Plugin catalog reloaded. Unsaved JSON edits were kept.")
            : L10n.tr("Plugin catalog reloaded.")
    }

    private func createNewPluginJSON() {
        do {
            let fileURL = try editorPluginRegistry.createExternalPluginTemplateFile()
            pluginActionError = nil
            pluginActionStatus = L10n.format("Created %@.", fileURL.lastPathComponent)
            editorPluginRegistry.reloadCatalog()
            if let createdPluginID = pluginIDForManifestURL(fileURL) {
                selectPlugin(createdPluginID)
            } else {
                ensurePluginSelection()
                pluginActionError = L10n.tr("Created plugin file but could not auto-select it. Choose it from the list.")
            }
        } catch {
            pluginActionError = L10n.format("Failed to create plugin JSON: %@", error.localizedDescription)
            pluginActionStatus = nil
        }
    }

    private func requestExternalPluginRemoval(_ plugin: EditorPluginDefinition) {
        guard plugin.source == .external else {
            pluginActionError = L10n.tr("Built-in plugins cannot be removed.")
            pluginActionStatus = nil
            return
        }

        pendingPluginRemoval = PendingPluginRemoval(
            id: plugin.id,
            displayName: plugin.displayName
        )
    }

    private func confirmExternalPluginRemoval(pluginID: String) {
        do {
            let removedName = try editorPluginRegistry.removeExternalPlugin(pluginID: pluginID)
            pendingPluginRemoval = nil
            pluginActionError = nil
            pluginActionStatus = L10n.format("Removed external plugin '%@'.", removedName)
            ensurePluginSelection()
        } catch {
            pendingPluginRemoval = nil
            pluginActionError = L10n.format("Failed to remove plugin: %@", error.localizedDescription)
            pluginActionStatus = nil
        }
    }

    private func ensurePluginSelection() {
        guard !editorPluginRegistry.plugins.isEmpty else {
            selectedPluginID = nil
            manifestEditorText = ""
            manifestEditorOriginalText = ""
            return
        }

        if let selectedPluginID, editorPluginRegistry.plugin(id: selectedPluginID) != nil {
            if manifestEditorHasChanges {
                pluginActionStatus = L10n.tr("Unsaved JSON edits were kept. Use Reload File to discard changes.")
                return
            }
            loadSelectedPluginManifest()
            return
        }

        if let preferredID = editorPluginRegistry.preferredPluginID,
           editorPluginRegistry.plugin(id: preferredID) != nil {
            selectPlugin(preferredID)
            return
        }

        if let firstID = editorPluginRegistry.plugins.first?.id {
            selectPlugin(firstID)
        }
    }

    private func pluginIDForManifestURL(_ manifestURL: URL) -> String? {
        let targetPath = manifestURL.standardizedFileURL.path
        for plugin in editorPluginRegistry.plugins where plugin.source == .external {
            guard let candidateURL = editorPluginRegistry.manifestFileURL(for: plugin.id) else {
                continue
            }
            if candidateURL.standardizedFileURL.path == targetPath {
                return plugin.id
            }
        }
        return nil
    }

    private func selectPlugin(_ pluginID: String) {
        selectedPluginID = pluginID
        loadSelectedPluginManifest()
    }

    private func loadSelectedPluginManifest() {
        guard let selectedPluginID else {
            return
        }

        do {
            let text = try editorPluginRegistry.manifestText(for: selectedPluginID)
            manifestEditorText = text
            manifestEditorOriginalText = text
            pluginActionError = nil
        } catch {
            pluginActionError = L10n.format("Failed to load manifest: %@", error.localizedDescription)
        }
    }

    private func formatManifestEditorJSON() {
        do {
            let payload = manifestEditorText.trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonObject = try JSONSerialization.jsonObject(with: Data(payload.utf8), options: [])
            let formattedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            guard var formatted = String(data: formattedData, encoding: .utf8) else {
                throw AppError.validationFailed([L10n.tr("Unable to encode formatted JSON text.")])
            }
            if !formatted.hasSuffix("\n") {
                formatted.append("\n")
            }
            manifestEditorText = formatted
            pluginActionError = nil
            pluginActionStatus = L10n.tr("JSON formatted.")
        } catch {
            pluginActionError = L10n.format("Failed to format JSON: %@", error.localizedDescription)
            pluginActionStatus = nil
        }
    }

    private func saveSelectedPluginManifest() {
        guard let selectedPluginID else {
            return
        }

        do {
            let resolvedPluginID = try editorPluginRegistry.saveManifestText(
                manifestEditorText,
                for: selectedPluginID
            )
            selectPlugin(resolvedPluginID)
            pluginActionError = nil
            pluginActionStatus = L10n.format("Saved %@ plugin manifest.", resolvedPluginID)
        } catch {
            pluginActionError = L10n.format("Failed to save plugin JSON: %@", error.localizedDescription)
            pluginActionStatus = nil
        }
    }
}
