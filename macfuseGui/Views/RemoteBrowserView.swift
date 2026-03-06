// BEGINNER FILE GUIDE
// Layer: SwiftUI view layer
// Purpose: This file defines visual layout and interaction controls shown to the user.
// Called by: Instantiated by parent views, window controllers, or app bootstrap code.
// Calls into: Reads observed state from view models and triggers callbacks for actions.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import SwiftUI

// Finder-style browser sheet for picking a remote directory.
// This view is intentionally directories-only to match mount target workflow.
enum BrowserColumnWidthKey: String {
    case name = "browser.column.name"
    case date = "browser.column.date"
    case kind = "browser.column.kind"
    case size = "browser.column.size"

    var defaultValue: CGFloat {
        switch self {
        case .name:
            return 280
        case .date:
            return 160
        case .kind:
            return 100
        case .size:
            return 90
        }
    }
}

// Keep persistence behind a tiny abstraction so view tests can inject an in-memory store.
protocol BrowserColumnWidthStoring {
    func width(for key: BrowserColumnWidthKey) -> CGFloat
    func setWidth(_ value: CGFloat, for key: BrowserColumnWidthKey)
}

struct UserDefaultsBrowserColumnWidthStore: BrowserColumnWidthStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func width(for key: BrowserColumnWidthKey) -> CGFloat {
        (defaults.object(forKey: key.rawValue) as? CGFloat) ?? key.defaultValue
    }

    func setWidth(_ value: CGFloat, for key: BrowserColumnWidthKey) {
        defaults.set(value, forKey: key.rawValue)
    }
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct RemoteBrowserView: View {
    @ObservedObject var viewModel: RemoteBrowserViewModel
    let onSelect: (String) -> Void
    let onCancel: () -> Void
    private let columnWidthStore: any BrowserColumnWidthStoring

    @State private var closeSessionTask: Task<Void, Never>?
    // Persisted table widths keep user layout preference across sessions.
    @State private var nameColumnWidth: CGFloat
    @State private var dateColumnWidth: CGFloat
    @State private var kindColumnWidth: CGFloat
    @State private var sizeColumnWidth: CGFloat

    init(
        viewModel: RemoteBrowserViewModel,
        onSelect: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        columnWidthStore: any BrowserColumnWidthStoring = UserDefaultsBrowserColumnWidthStore()
    ) {
        self.viewModel = viewModel
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.columnWidthStore = columnWidthStore
        _nameColumnWidth = State(initialValue: columnWidthStore.width(for: .name))
        _dateColumnWidth = State(initialValue: columnWidthStore.width(for: .date))
        _kindColumnWidth = State(initialValue: columnWidthStore.width(for: .kind))
        _sizeColumnWidth = State(initialValue: columnWidthStore.width(for: .size))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                topBar
                reconnectBanner
                tableArea
                bottomBar
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .task {
            // Initial data fetch is async; UI stays responsive while loading.
            await viewModel.loadInitial()
        }
        .onAppear {
            closeSessionTask?.cancel()
            closeSessionTask = nil
        }
        .onChange(of: nameColumnWidth) { value in
            columnWidthStore.setWidth(value, for: .name)
        }
        .onChange(of: dateColumnWidth) { value in
            columnWidthStore.setWidth(value, for: .date)
        }
        .onChange(of: kindColumnWidth) { value in
            columnWidthStore.setWidth(value, for: .kind)
        }
        .onChange(of: sizeColumnWidth) { value in
            columnWidthStore.setWidth(value, for: .size)
        }
        .onDisappear {
            // Close remote browser session on sheet close to release transport resources.
            closeSessionTask?.cancel()
            closeSessionTask = Task { await viewModel.closeSession() }
            persistColumnWidths()
        }
    }

    private var sidebar: some View {
        // Sidebar provides fast path navigation and path memory shortcuts.
        List {
            Section("Favorites") {
                ForEach(viewModel.favorites, id: \.self) { path in
                    Button(path) {
                        Task { await viewModel.goTo(path: path) }
                    }
                    .buttonStyle(.plain)
                }
                if viewModel.favorites.isEmpty {
                    Text(L10n.tr("No favorites"))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recents") {
                ForEach(viewModel.recents, id: \.self) { path in
                    Button(path) {
                        Task { await viewModel.goTo(path: path) }
                    }
                    .buttonStyle(.plain)
                }
                if viewModel.recents.isEmpty {
                    Text(L10n.tr("No recents"))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Roots") {
                ForEach(viewModel.roots, id: \.self) { path in
                    Button(path) {
                        Task { await viewModel.goTo(path: path) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Remote Browser")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    viewModel.toggleFavoriteForCurrentPath()
                } label: {
                    Image(systemName: viewModel.isCurrentPathFavorite ? "star.fill" : "star")
                }
                .help(viewModel.isCurrentPathFavorite ? L10n.tr("Remove favorite") : L10n.tr("Add favorite"))

                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            ScrollView(.horizontal, showsIndicators: false) {
                // Breadcrumbs reflect normalized path segments from view model.
                HStack(spacing: 6) {
                    ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                        Button(crumb.title) {
                            Task { await viewModel.goTo(path: crumb.fullPath) }
                        }
                        .buttonStyle(.link)

                        if index < viewModel.breadcrumbs.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search folders", text: $viewModel.searchText)
                Picker("Sort", selection: $viewModel.sortMode) {
                    Text("Name").tag(BrowserSortMode.name)
                    Text("Date").tag(BrowserSortMode.modified)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var reconnectBanner: some View {
        if !viewModel.shouldShowDegradedNoDataState && (viewModel.isRecovering || viewModel.viewState == .degradedWithCache) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                Text(viewModel.statusMessage ?? L10n.tr("Connection lost. Reconnecting…"))
                    .lineLimit(1)
                Spacer()
                if viewModel.health.retryCount > 0 {
                    Text(L10n.format("Attempt %lld", Int64(viewModel.health.retryCount)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Retry now") {
                    Task { await viewModel.retryNow() }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.yellow.opacity(0.2))
        }
    }

    @ViewBuilder
    private var tableArea: some View {
        if viewModel.shouldShowConfirmedEmptyState {
            // Healthy + confirmed empty: true empty folder state.
            VStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("This folder is empty")
                    .font(.headline)
                Text(L10n.format("No subfolders were found in %@.", viewModel.currentPath))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else if viewModel.shouldShowDegradedNoDataState {
            // No data to show and degraded/failure state: actionable retry panel.
            VStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
                Text("Connection is degraded")
                    .font(.headline)
                Text(viewModel.statusMessage ?? L10n.tr("Retry to reload this path."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button("Retry now") {
                    Task { await viewModel.retryNow() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            // Main directory table when data is available.
            Table(viewModel.visibleEntries, selection: $viewModel.selectedItemID) {
                TableColumn("Name") { item in
                    Text(item.name)
                        .onTapGesture(count: 2) {
                            Task { await viewModel.open(item) }
                        }
                }
                .width(min: 180, ideal: nameColumnWidth, max: 500)

                TableColumn("Date Modified") { item in
                    Text(Self.dateText(item.modifiedAt))
                        .foregroundStyle(.secondary)
                }
                .width(min: 130, ideal: dateColumnWidth, max: 260)

                TableColumn("Kind") { _ in
                    Text("Folder")
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: kindColumnWidth, max: 140)

                TableColumn("Size") { _ in
                    Text("-")
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: sizeColumnWidth, max: 120)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private var bottomBar: some View {
        let selected = selectedEntry
        return HStack(spacing: 10) {
            Text(viewModel.itemCountText)
                .foregroundStyle(.secondary)
            Divider()
                .frame(height: 14)
            Text(viewModel.healthText)
                .foregroundStyle(healthColor(viewModel.health.state))
            Divider()
                .frame(height: 14)
            Text(viewModel.lastSuccessText)
                .foregroundStyle(.secondary)
            Divider()
                .frame(height: 14)
            Text(viewModel.latencyText)
                .foregroundStyle(.secondary)

            Spacer()

            if viewModel.viewState == .fatal, let message = viewModel.statusMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Button("Up") {
                Task { await viewModel.goUp() }
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Open") {
                if let selected {
                    Task { await viewModel.open(selected) }
                }
            }
            .disabled(selected == nil)
            .keyboardShortcut(.return, modifiers: [])

            Button("Select") {
                // "Select" returns current path (not selected row) for mount target field.
                onSelect(viewModel.selectCurrentPath())
            }
            .keyboardShortcut(.defaultAction)

            Button("Cancel", action: onCancel)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.12))
    }

    private var selectedEntry: RemoteDirectoryItem? {
        guard let selectedItemID = viewModel.selectedItemID else {
            return nil
        }
        return viewModel.visibleEntries.first(where: { $0.id == selectedItemID })
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func healthColor(_ state: BrowserConnectionState) -> Color {
        switch state {
        case .healthy:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .degraded:
            return .yellow
        case .failed:
            return .red
        case .closed:
            return .secondary
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func persistColumnWidths() {
        columnWidthStore.setWidth(nameColumnWidth, for: .name)
        columnWidthStore.setWidth(dateColumnWidth, for: .date)
        columnWidthStore.setWidth(kindColumnWidth, for: .kind)
        columnWidthStore.setWidth(sizeColumnWidth, for: .size)
    }

    private static func dateText(_ value: Date?) -> String {
        guard let value else {
            return L10n.tr("-")
        }
        return dateFormatter.string(from: value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
