// BEGINNER FILE GUIDE
// Layer: SwiftUI view layer
// Purpose: This file defines visual layout and interaction controls shown to the user.
// Called by: Instantiated by parent views, window controllers, or app bootstrap code.
// Calls into: Reads observed state from view models and triggers callbacks for actions.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import SwiftUI

// RemoteEditorView is used for both "Add" and "Edit" flows.
// It edits a draft model first, then commits to persistent store only on Save.
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct RemoteEditorView: View {
    @StateObject private var viewModel: RemoteEditorViewModel
    @ObservedObject private var remotesViewModel: RemotesViewModel
    private let onComplete: (UUID?) -> Void

    // Remote-browser sheet state.
    @State private var showRemoteBrowser = false
    @State private var browserSessionID: RemoteBrowserSessionID?
    @State private var browserViewModel: RemoteBrowserViewModel?
    @State private var preparingRemoteBrowser = false
    @State private var showPassword = false

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        initialDraft: RemoteDraft,
        remotesViewModel: RemotesViewModel,
        onComplete: @escaping (UUID?) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: RemoteEditorViewModel(draft: initialDraft))
        _remotesViewModel = ObservedObject(wrappedValue: remotesViewModel)
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            editorHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionCard
                    pathsCard

                    if hasInlineFeedback {
                        feedbackCard
                    }
                }
                .padding(.bottom, 4)
            }

            actionBar
        }
        .padding(18)
        .frame(minWidth: 800, minHeight: 620)
        .overlay(alignment: .topTrailing) {
            Button(action: closeEditor) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Close without saving"))
            .help(L10n.tr("Close without saving"))
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .sheet(isPresented: $showRemoteBrowser) {
            Group {
                if let browserViewModel {
                    RemoteBrowserView(
                        viewModel: browserViewModel,
                        onSelect: { selectedPath in
                            viewModel.draft.remoteDirectory = selectedPath
                            showRemoteBrowser = false
                        },
                        onCancel: {
                            showRemoteBrowser = false
                        }
                    )
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.tr("Preparing browser session…"))
                    }
                }
            }
            .onDisappear {
                // Close browser session whenever sheet closes to avoid leaked transport sessions.
                guard let browserSessionID else {
                    return
                }
                Task { @MainActor in
                    await remotesViewModel.stopBrowserSession(id: browserSessionID)
                    if self.browserSessionID == browserSessionID {
                        self.browserSessionID = nil
                    }
                    self.browserViewModel = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forceQuitRequested)) { _ in
            showRemoteBrowser = false
        }
    }

    private var editorHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.26), Color.teal.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: viewModel.isEditingExistingRemote ? "slider.horizontal.3" : "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(editorTitle)
                        .font(.title2.weight(.bold))

                    editorChip(
                        text: viewModel.draft.authMode.displayName,
                        systemImage: viewModel.draft.authMode == .privateKey ? "key.fill" : "lock.fill",
                        tint: viewModel.draft.authMode == .privateKey ? .teal : .blue
                    )
                }

                Text(editorSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    editorChip(
                        text: canBrowseRemote ? L10n.tr("Browser Ready") : L10n.tr("Needs Host + User"),
                        systemImage: canBrowseRemote ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                        tint: canBrowseRemote ? .green : .orange
                    )
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Text("Destination")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(connectionIdentitySummary)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                Text(remoteDirectorySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(NSColor.controlBackgroundColor).opacity(0.92),
                            Color.blue.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var connectionCard: some View {
        editorSectionCard(
            sectionLabel: "Section 1",
            title: "Connection Profile",
            subtitle: "Define how this remote appears in the app and how SSHFS reaches it.",
            systemImage: "server.rack",
            accent: .blue
        ) {
            HStack(alignment: .top, spacing: 12) {
                editorField(title: "Display Name", detail: "Menu bar label and saved profile name.") {
                    TextField("Production Files", text: $viewModel.draft.displayName)
                        .textFieldStyle(.roundedBorder)
                }

                editorField(title: "Host / IP", detail: "DNS name or IP address.") {
                    TextField("server.example.com", text: $viewModel.draft.host)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                editorField(title: "Port", detail: "Default SSH port is 22.") {
                    TextField("22", value: $viewModel.draft.port, formatter: Self.portFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 120, alignment: .leading)
                }

                editorField(title: "Username", detail: "Remote account name used for SSH.") {
                    TextField("deploy", text: $viewModel.draft.username)
                        .textFieldStyle(.roundedBorder)
                }
            }

            editorField(title: "Authentication", detail: "Switch between password and key-based access.") {
                Picker("Authentication", selection: $viewModel.draft.authMode) {
                    ForEach(RemoteAuth.allCases) { auth in
                        Text(auth.displayName).tag(auth)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if viewModel.draft.authMode == .privateKey {
                editorField(title: "Private Key", detail: "Choose the SSH identity file for this remote.") {
                    HStack(spacing: 8) {
                        TextField("~/.ssh/id_ed25519", text: $viewModel.draft.privateKeyPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…", action: pickPrivateKey)
                            .buttonStyle(.bordered)
                    }
                }

                infoCallout(
                    title: "Key-based auth is preferred",
                    message: "It avoids clipboard mistakes, keeps the profile cleaner, and is usually the most reliable SSHFS path.",
                    tint: .teal
                )
            } else {
                editorField(title: "Password", detail: "Stored securely in the macOS Keychain after save.") {
                    HStack(spacing: 8) {
                        Group {
                            if showPassword {
                                TextField("Password", text: $viewModel.draft.password)
                            } else {
                                SecureField("Password", text: $viewModel.draft.password)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .frame(width: 18)
                        }
                        .buttonStyle(.borderless)
                        .help(showPassword ? "Hide password" : "Show password")
                    }
                }

                infoCallout(
                    title: "Keychain-backed password mode",
                    message: "Use this when you cannot deploy keys yet. The draft keeps plaintext only while this window is open.",
                    tint: .blue
                )
            }

            Toggle(isOn: $viewModel.draft.autoConnectOnLaunch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-connect on app launch")
                        .font(.callout.weight(.semibold))
                    Text("Reconnect this mount automatically when the app starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Toggle(isOn: $viewModel.draft.disableLocalCaches) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prioritize freshness over speed")
                        .font(.callout.weight(.semibold))
                    Text("Slower, but better for shared or live-changing mounts. Turn this off for faster dev or code mounts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var pathsCard: some View {
        editorSectionCard(
            sectionLabel: "Section 2",
            title: "Mount Paths",
            subtitle: "Choose the remote folder you want in Finder and the local mount point that will expose it.",
            systemImage: "point.3.connected.trianglepath.dotted",
            accent: .indigo
        ) {
            editorField(title: "Remote Directory", detail: "The remote folder that SSHFS mounts into Finder.") {
                HStack(spacing: 8) {
                    TextField("/var/www", text: $viewModel.draft.remoteDirectory)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        openRemoteBrowser()
                    } label: {
                        Label("Browse Remote…", systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!canBrowseRemote || preparingRemoteBrowser)
                }
            }

            if preparingRemoteBrowser {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing browser session…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
            } else if !canBrowseRemote {
                infoCallout(
                    title: "Remote browser locked",
                    message: "Enter both host and username first. The browser opens a real SSH session and needs enough information to authenticate.",
                    tint: .orange
                )
            }

            editorField(title: "Local Mount Point", detail: "A local folder where the mounted remote will appear.") {
                HStack(spacing: 8) {
                    TextField("~/Mounts/production", text: $viewModel.draft.localMountPoint)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        pickLocalFolder()
                    } label: {
                        Label("Browse Folder…", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                infoCallout(
                    title: "Remote target",
                    message: remoteDirectorySummary,
                    tint: .indigo
                )

                infoCallout(
                    title: "Local mount",
                    message: localMountPointSummary,
                    tint: .green
                )
            }
        }
    }

    private var feedbackCard: some View {
        editorSectionCard(
            sectionLabel: "Status",
            title: "Live Feedback",
            subtitle: "Validation and test output stay visible here so you can iterate without hunting for alerts.",
            systemImage: "waveform.badge.magnifyingglass",
            accent: feedbackAccent
        ) {
            if !viewModel.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Please fix the following", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)

                    ForEach(viewModel.validationErrors, id: \.self) { error in
                        Text("• \(error)")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.red.opacity(0.22), lineWidth: 1)
                )
            }

            if viewModel.isTestingConnection {
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Testing connection…")
                            .font(.callout.weight(.semibold))
                        Text("This checks auth and transport before you commit the profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
            } else if let testMessage = viewModel.testResultMessage, !testMessage.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        viewModel.testResultIsSuccess ? "Connection test passed" : "Connection test failed",
                        systemImage: viewModel.testResultIsSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(viewModel.testResultIsSuccess ? .green : .red)

                    Text(testMessage)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((viewModel.testResultIsSuccess ? Color.green : Color.red).opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke((viewModel.testResultIsSuccess ? Color.green : Color.red).opacity(0.22), lineWidth: 1)
                )
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(actionSummaryTitle)
                    .font(.callout.weight(.semibold))
                Text(actionSummaryMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            Button("Cancel", action: closeEditor)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isSaving || viewModel.isTestingConnection)

            Button {
                Task { await viewModel.runConnectionTest(using: remotesViewModel) }
            } label: {
                Label("Test Connection", systemImage: "bolt.badge.checkmark")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isSaving || viewModel.isTestingConnection)

            Button {
                Task { @MainActor in
                    switch await viewModel.save(using: remotesViewModel) {
                    case .success(let id):
                        onComplete(id)
                    case .failure:
                        break
                    }
                }
            } label: {
                Label(saveButtonTitle, systemImage: viewModel.isEditingExistingRemote ? "checkmark.circle.fill" : "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isSaving || viewModel.isTestingConnection)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var canBrowseRemote: Bool {
        !viewModel.draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !viewModel.draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasInlineFeedback: Bool {
        !viewModel.validationErrors.isEmpty ||
        viewModel.isTestingConnection ||
        (!(viewModel.testResultMessage ?? "").isEmpty)
    }

    private var editorTitle: String {
        viewModel.isEditingExistingRemote ? L10n.tr("Edit Remote") : L10n.tr("Add Remote")
    }

    private var editorSubtitle: String {
        if viewModel.isEditingExistingRemote {
            return L10n.tr("Refine the connection details, mount paths, and launch behavior for an existing SSHFS profile.")
        }
        return L10n.tr("Create a polished remote profile with the right auth flow, Finder mount target, and startup behavior from the start.")
    }

    private var connectionIdentitySummary: String {
        let host = viewModel.draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = viewModel.draft.username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty || !username.isEmpty else {
            return L10n.tr("Endpoint not configured")
        }

        if !host.isEmpty, !username.isEmpty {
            return "\(username)@\(host):\(viewModel.draft.port)"
        }

        return [username, host].filter { !$0.isEmpty }.joined(separator: "@")
    }

    private var remoteDirectorySummary: String {
        let trimmed = viewModel.draft.remoteDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.tr("Remote directory not set") : trimmed
    }

    private var localMountPointSummary: String {
        let trimmed = viewModel.draft.localMountPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.tr("Local mount point not set") : trimmed
    }

    private var actionSummaryTitle: String {
        if viewModel.isTestingConnection {
            return L10n.tr("Connection test in progress")
        }
        if viewModel.isSaving {
            return L10n.tr("Saving remote profile…")
        }
        if !viewModel.validationErrors.isEmpty {
            return L10n.tr("Validation needs attention")
        }
        if viewModel.testResultIsSuccess {
            return L10n.tr("Ready to save")
        }
        return L10n.tr("Review and save")
    }

    private var actionSummaryMessage: String {
        if viewModel.isTestingConnection {
            return L10n.tr("Wait for the auth and transport checks to finish before changing the draft again.")
        }
        if viewModel.isSaving {
            return L10n.tr("Persisting the remote and any credential updates now.")
        }
        if !viewModel.validationErrors.isEmpty {
            return L10n.tr("Resolve the highlighted issues above so this profile saves cleanly.")
        }
        if let testMessage = viewModel.testResultMessage, !testMessage.isEmpty {
            return testMessage
        }
        return L10n.tr("Use Test Connection if you want a dry run first, or save immediately when the profile looks correct.")
    }

    private var saveButtonTitle: String {
        viewModel.isEditingExistingRemote ? L10n.tr("Save Changes") : L10n.tr("Add Remote")
    }

    private func editorSectionCard<Content: View>(
        sectionLabel: String,
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.9), accent.opacity(0.4)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 3)

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))

                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr(sectionLabel).uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(accent)

                    Text(L10n.tr(title))
                        .font(.headline.weight(.semibold))

                    Text(L10n.tr(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(NSColor.controlBackgroundColor).opacity(0.88),
                            accent.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 6)
    }

    private func editorField<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.tr(title))
                .font(.callout.weight(.semibold))
            content()
            Text(L10n.tr(detail))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorChip(text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func infoCallout(title: String, message: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.tr(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(L10n.tr(message))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private var feedbackAccent: Color {
        if !viewModel.validationErrors.isEmpty {
            return .red
        }
        if viewModel.testResultIsSuccess {
            return .green
        }
        if viewModel.isTestingConnection {
            return .blue
        }
        return .orange
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func closeEditor() {
        onComplete(nil)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func openRemoteBrowser() {
        preparingRemoteBrowser = true
        Task { @MainActor in
            defer { preparingRemoteBrowser = false }
            do {
                // Start dedicated browser session for this editor sheet.
                let sessionID = try await remotesViewModel.startBrowserSession(for: viewModel.draft)
                let browserModel = RemoteBrowserViewModel(
                    sessionID: sessionID,
                    initialPath: viewModel.draft.remoteDirectory,
                    initialFavorites: remotesViewModel.browserFavorites(for: viewModel.draft),
                    initialRecents: remotesViewModel.browserRecents(for: viewModel.draft),
                    username: viewModel.draft.username,
                    remotesViewModel: remotesViewModel,
                    onPathMemoryChanged: { favorites, recents in
                        // Keep draft memory in sync live; saved remotes persist on Save.
                        viewModel.draft.favoriteRemoteDirectories = favorites
                        viewModel.draft.recentRemoteDirectories = recents
                    }
                )
                self.browserViewModel = browserModel
                self.browserSessionID = sessionID
                showRemoteBrowser = true
            } catch {
                remotesViewModel.alertMessage = error.localizedDescription
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func pickPrivateKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = L10n.tr("Select SSH Private Key")
        presentOpenPanel(panel) { url in
            viewModel.draft.privateKeyPath = url.path
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func pickLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        // Avoid resolving potentially stale alias targets on network/removable volumes.
        panel.resolvesAliases = false
        panel.title = L10n.tr("Select Local Mount Point")
        panel.prompt = L10n.tr("Select Folder")
        panel.message = L10n.tr("Choose or create a folder to use as the local SSHFS mount point.")
        // Force a safe local start location. Relying on panel's remembered last
        // folder can hang when that location is stale/unreachable.
        panel.directoryURL = preferredLocalFolderPickerStartURL()
        presentOpenPanel(panel) { url in
            viewModel.draft.localMountPoint = url.path
        }
    }

    /// Beginner note: Present picker panels asynchronously so reconnect/status
    /// work does not deadlock with a synchronous modal loop.
    private func presentOpenPanel(_ panel: NSOpenPanel, onSelect: @escaping (URL) -> Void) {
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            onSelect(url)
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    /// Beginner note: This method picks a local folder picker start location that
    /// avoids stale/unreachable paths while still being useful for mount selection.
    private func preferredLocalFolderPickerStartURL() -> URL {
        let homePath = LocalPathNormalizer.normalize(NSHomeDirectory())
        let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
        let rawMountPoint = viewModel.draft.localMountPoint.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !rawMountPoint.isEmpty, rawMountPoint.hasPrefix("/") else {
            return homeURL
        }

        let parentPath = LocalPathNormalizer.parentPath(of: rawMountPoint)
        guard !parentPath.isEmpty else {
            return homeURL
        }
        let parent = URL(fileURLWithPath: parentPath, isDirectory: true)

        // Stay within the user's home directory for predictable local performance.
        if parentPath == homePath || parentPath.hasPrefix(homePath + "/") {
            return parent
        }

        return homeURL
    }

    private static let portFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 65535
        return formatter
    }()
}
