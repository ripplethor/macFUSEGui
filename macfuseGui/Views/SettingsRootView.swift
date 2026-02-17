// BEGINNER FILE GUIDE
// Layer: SwiftUI view layer
// Purpose: This file defines visual layout and interaction controls shown to the user.
// Called by: Instantiated by parent views, window controllers, or app bootstrap code.
// Calls into: Reads observed state from view models and triggers callbacks for actions.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import SwiftUI

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct SettingsRootView: View {
    @ObservedObject var viewModel: RemotesViewModel
    let onOpenEditorPlugins: () -> Void

    @State private var activeEditorSession: EditorSession?

    var body: some View {
        VStack(spacing: 0) {
            if let message = viewModel.alertMessage, !message.isEmpty {
                HStack {
                    Text(message)
                        .font(.callout)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.alertMessage = nil
                    }
                    .buttonStyle(.link)
                }
                .padding(10)
                .background(Color.orange.opacity(0.18))
            }

            HStack(spacing: 12) {
                Toggle("Launch At Login", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                    .help("Open macfuseGui automatically when you log in.")

                if viewModel.launchAtLoginState.requiresApproval {
                    Text("Pending approval in System Settings -> General -> Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let detail = viewModel.launchAtLoginState.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onOpenEditorPlugins()
                } label: {
                    Label("Editor Plugins", systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Remotes")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Spacer()
                        Button("Add") {
                            openEditor(
                                with: RemoteDraft(
                                port: 22,
                                authMode: .privateKey,
                                remoteDirectory: "/"
                            )
                            )
                        }
                    }
                    .padding([.top, .horizontal], 12)

                    RemotesListView(
                        remotes: viewModel.remotes,
                        statuses: viewModel.statuses,
                        badgeStateForRemote: { remoteID in
                            viewModel.statusBadgeRawValue(for: remoteID)
                        },
                        selectedRemoteID: $viewModel.selectedRemoteID,
                        onConnect: { id in
                            Task { await viewModel.connect(remoteID: id) }
                        },
                        onDisconnect: { id in
                            Task { await viewModel.disconnect(remoteID: id) }
                        }
                    )
                }
                .frame(minWidth: 430)

                Divider()

                detailPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(18)
            }
        }
        .frame(minWidth: 960, minHeight: 620)
        .sheet(item: $activeEditorSession) { session in
            RemoteEditorView(initialDraft: session.draft, remotesViewModel: viewModel) { savedID in
                activeEditorSession = nil
                if let savedID {
                    viewModel.selectedRemoteID = savedID
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceQuitRequested)) { _ in
            activeEditorSession = nil
        }
        .onAppear {
            viewModel.refreshLaunchAtLoginState()
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let remote = selectedRemote {
            let status = viewModel.status(for: remote.id)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(remote.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    StatusBadgeView(stateRawValue: viewModel.statusBadgeRawValue(for: remote.id))
                    Spacer()
                }

                Group {
                    Text("Host: \(remote.host)")
                    Text("Port: \(remote.port)")
                    Text("Username: \(remote.username)")
                    Text("Auth: \(remote.authMode.displayName)")
                    Text("Auto-connect on launch: \(remote.autoConnectOnLaunch ? "On" : "Off")")
                    Text("Remote Directory: \(remote.remoteDirectory)")
                    Text("Local Mount Point: \(remote.localMountPoint)")
                }
                .font(.body)

                if let mounted = status.mountedPath {
                    Text("Mounted Path: \(mounted)")
                        .font(.callout)
                        .foregroundStyle(.green)
                }

                if let error = status.lastError, !error.isEmpty {
                    Text("Last Error: \(shortError(error))")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("Edit") {
                        let draft = RemoteDraft(remote: remote)
                        openEditor(with: draft)
                    }

                    Button("Duplicate") {
                        var draft = RemoteDraft(remote: remote)
                        draft.id = nil
                        draft.displayName = duplicateDisplayName(for: remote.displayName)
                        openEditor(with: draft)
                    }

                    Button("Delete") {
                        viewModel.deleteRemote(remote.id)
                    }
                    .foregroundStyle(.red)

                    Button("Refresh") {
                        Task { await viewModel.refreshStatus(remoteID: remote.id) }
                    }

                    Spacer()

                    Button("Connect") {
                        Task { await viewModel.connect(remoteID: remote.id) }
                    }
                    .disabled(!(status.state == .disconnected || status.state == .error || status.state == .disconnecting))

                    Button("Disconnect") {
                        Task { await viewModel.disconnect(remoteID: remote.id) }
                    }
                    .disabled(!(status.state == .connected || status.state == .connecting))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Select a remote")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Add a remote or select one from the list to edit connection settings.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
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
        let collapsed = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if collapsed.count <= 220 {
            return collapsed
        }

        let prefix = collapsed.prefix(220)
        return "\(prefix)…"
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func duplicateDisplayName(for original: String) -> String {
        let base = original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Remote"
            : original.trimmingCharacters(in: .whitespacesAndNewlines)
        let copyBase = "\(base) Copy"

        let existingNames = Set(viewModel.remotes.map { $0.displayName.lowercased() })
        if !existingNames.contains(copyBase.lowercased()) {
            return copyBase
        }

        var index = 2
        while true {
            let candidate = "\(copyBase) \(index)"
            if !existingNames.contains(candidate.lowercased()) {
                return candidate
            }
            index += 1
        }
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

    /// Beginner note: This type groups related state and behavior for one part of the app.
    /// Read stored properties first, then follow methods top-to-bottom to understand flow.
    private struct EditorSession: Identifiable {
        let id = UUID()
        let draft: RemoteDraft
    }
}

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
            Text("Delete '\(removal.displayName)' from the external plugin folder?")
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
                Text("Star sets preferred")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                subtitle: "Menu bar opens preferred editor first, then falls back across active plugins."
            ) {
                Picker("Preferred Editor", selection: preferredPluginBinding) {
                    if activeEditorPlugins.isEmpty {
                        Text("No active plugins")
                            .tag("")
                    } else {
                        ForEach(activeEditorPlugins) { plugin in
                            Text(plugin.displayName)
                                .tag(plugin.id)
                        }
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(activeEditorPlugins.isEmpty)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
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
                    ForEach(Array(editorPluginRegistry.loadIssues.enumerated()), id: \.offset) { _, issue in
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
                    if plugin.isPreferred {
                        pluginTag(text: "Preferred", tint: .blue)
                    }
                }

                Text(plugin.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Text("Attempts \(plugin.launchAttempts.count) · Priority \(plugin.priority)")
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

                    Button {
                        editorPluginRegistry.setPreferredPlugin(plugin.id)
                    } label: {
                        Image(systemName: plugin.isPreferred ? "star.fill" : "star")
                            .foregroundStyle(plugin.isPreferred ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!plugin.isActive)
                    .help(plugin.isActive ? "Set as preferred editor" : "Enable plugin to set as preferred")

                    Toggle("", isOn: pluginActiveBinding(pluginID: plugin.id))
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
            Text(title)
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
        Text(text)
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

    private func pluginActiveBinding(pluginID: String) -> Binding<Bool> {
        Binding(
            get: {
                editorPluginRegistry.plugin(id: pluginID)?.isActive ?? false
            },
            set: { active in
                editorPluginRegistry.setPluginActive(active, pluginID: pluginID)
            }
        )
    }

    private func openInFinder(_ path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func reloadCatalogAndRefreshSelection() {
        editorPluginRegistry.reloadCatalog()
        ensurePluginSelection()
        pluginActionError = nil
        pluginActionStatus = "Plugin catalog reloaded."
    }

    private func createNewPluginJSON() {
        do {
            let fileURL = try editorPluginRegistry.createExternalPluginTemplateFile()
            pluginActionError = nil
            pluginActionStatus = "Created \(fileURL.lastPathComponent)."
            editorPluginRegistry.reloadCatalog()
            selectPlugin(fileURL.deletingPathExtension().lastPathComponent)
        } catch {
            pluginActionError = "Failed to create plugin JSON: \(error.localizedDescription)"
            pluginActionStatus = nil
        }
    }

    private func requestExternalPluginRemoval(_ plugin: EditorPluginDefinition) {
        guard plugin.source == .external else {
            pluginActionError = "Built-in plugins cannot be removed."
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
            pluginActionStatus = "Removed external plugin '\(removedName)'."
            ensurePluginSelection()
        } catch {
            pendingPluginRemoval = nil
            pluginActionError = "Failed to remove plugin: \(error.localizedDescription)"
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
            pluginActionError = "Failed to load manifest: \(error.localizedDescription)"
        }
    }

    private func formatManifestEditorJSON() {
        do {
            let payload = manifestEditorText.trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonObject = try JSONSerialization.jsonObject(with: Data(payload.utf8), options: [])
            let formattedData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
            guard var formatted = String(data: formattedData, encoding: .utf8) else {
                throw AppError.validationFailed(["Unable to encode formatted JSON text."])
            }
            if !formatted.hasSuffix("\n") {
                formatted.append("\n")
            }
            manifestEditorText = formatted
            pluginActionError = nil
            pluginActionStatus = "JSON formatted."
        } catch {
            pluginActionError = "Failed to format JSON: \(error.localizedDescription)"
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
            pluginActionStatus = "Saved \(resolvedPluginID) plugin manifest."
        } catch {
            pluginActionError = "Failed to save plugin JSON: \(error.localizedDescription)"
            pluginActionStatus = nil
        }
    }
}
