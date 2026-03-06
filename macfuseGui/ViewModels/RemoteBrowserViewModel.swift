// BEGINNER FILE GUIDE
// Layer: View model orchestration layer
// Purpose: This file transforms service-level behavior into UI-ready state and user actions.
// Called by: Called by SwiftUI views and menu controllers in response to user input.
// Calls into: Calls into services and publishes state changes back to the UI.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

// These view states are intentionally coarse UI states.
// Fine-grained transport details live in BrowserConnectionHealth + diagnostics.
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
enum BrowserViewState: String, Sendable {
    case idle
    case loadingFirstPage
    case ready
    case degradedWithCache
    case recovering
    case fatal
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
enum BrowserSortMode: String, CaseIterable, Sendable {
    case name
    case modified
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
struct RemotePathBreadcrumb: Identifiable, Equatable {
    let title: String
    let fullPath: String

    var id: String { fullPath }
}

@MainActor
// RemoteBrowserViewModel receives snapshots from browser sessions and turns them into
// UI state for table rows, banners, footer text, and retry behavior.
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class RemoteBrowserViewModel: ObservableObject {
    // Published values drive SwiftUI updates.
    @Published private(set) var viewState: BrowserViewState = .idle
    @Published private(set) var currentPath: String
    @Published private(set) var entries: [RemoteDirectoryItem] = [] {
        didSet { rebuildVisibleEntries() }
    }
    @Published private(set) var health: BrowserConnectionHealth = .connecting
    @Published private(set) var isStale: Bool = false
    @Published private(set) var isConfirmedEmpty: Bool = false
    @Published private(set) var statusMessage: String?
    @Published var searchText: String = "" {
        didSet { rebuildVisibleEntries() }
    }
    @Published var sortMode: BrowserSortMode = .name {
        didSet { rebuildVisibleEntries() }
    }
    @Published private(set) var visibleEntries: [RemoteDirectoryItem] = []
    @Published var selectedItemID: RemoteDirectoryItem.ID?
    @Published private(set) var favorites: [String]
    @Published private(set) var recents: [String]

    private let sessionID: RemoteBrowserSessionID
    private let remotesViewModel: RemotesViewModel
    private let username: String
    private let onPathMemoryChanged: (([String], [String]) -> Void)?
    // Monotonic request ID prevents stale responses from clobbering newer navigation.
    private var latestRequestID: UInt64 = 0
    private var healthTask: Task<Void, Never>?
    private var degradedRefreshTask: Task<Void, Never>?
    private var requestInFlight = false

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        sessionID: RemoteBrowserSessionID,
        initialPath: String,
        initialFavorites: [String],
        initialRecents: [String],
        username: String,
        remotesViewModel: RemotesViewModel,
        onPathMemoryChanged: (([String], [String]) -> Void)? = nil
    ) {
        self.sessionID = sessionID
        self.currentPath = BrowserPathNormalizer.normalize(path: initialPath)
        self.favorites = RemotesViewModel.normalizePathMemoryCollection(
            initialFavorites,
            limit: RemotesViewModel.favoritesLimit
        )
        self.recents = RemotesViewModel.normalizePathMemoryCollection(
            initialRecents,
            limit: RemotesViewModel.recentsLimit
        )
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = trimmedUsername.isEmpty ? "user" : trimmedUsername
        self.remotesViewModel = remotesViewModel
        self.onPathMemoryChanged = onPathMemoryChanged
        rebuildVisibleEntries()
    }

    /// Beginner note: Deinitializer runs during teardown to stop background work and free resources.
    deinit {
        healthTask?.cancel()
        degradedRefreshTask?.cancel()
    }

    var breadcrumbs: [RemotePathBreadcrumb] {
        let normalized = BrowserPathNormalizer.normalize(path: currentPath)
        if normalized == "/" {
            return [RemotePathBreadcrumb(title: "/", fullPath: "/")]
        }
        if normalized == "~" {
            return [RemotePathBreadcrumb(title: "~", fullPath: "~")]
        }

        if normalized.hasPrefix("~/") {
            let tail = String(normalized.dropFirst(2))
            let components = tail.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            var result: [RemotePathBreadcrumb] = [RemotePathBreadcrumb(title: "~", fullPath: "~")]
            var cursor = "~"
            for component in components {
                cursor += "/\(component)"
                result.append(RemotePathBreadcrumb(title: component, fullPath: cursor))
            }
            return result
        }

        let components = normalized.dropFirst().split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var result: [RemotePathBreadcrumb] = [RemotePathBreadcrumb(title: "/", fullPath: "/")]
        var cursor = ""
        for (index, component) in components.enumerated() {
            if index == 0, BrowserPathNormalizer.isWindowsDriveComponent(component) {
                cursor = "/\(component)/"
            } else {
                cursor += "/\(component)"
            }
            result.append(
                RemotePathBreadcrumb(
                    title: component,
                    fullPath: BrowserPathNormalizer.normalize(path: cursor)
                )
            )
        }
        return result
    }

    var roots: [String] {
        BrowserPathNormalizer.rootCandidates(for: username)
    }

    var isRecovering: Bool {
        health.state == .reconnecting || health.state == .degraded || health.state == .connecting
    }

    var itemCountText: String {
        let count = visibleEntries.count
        return count == 1 ? L10n.tr("1 folder") : L10n.format("%lld folders", Int64(count))
    }

    var healthText: String {
        switch health.state {
        case .connecting:
            return L10n.tr("Connecting…")
        case .healthy:
            return L10n.tr("Connected")
        case .degraded:
            return L10n.tr("Degraded")
        case .reconnecting:
            return L10n.tr("Reconnecting…")
        case .failed:
            return L10n.tr("Connection Failed")
        case .closed:
            return L10n.tr("Closed")
        }
    }

    var lastSuccessText: String {
        guard let timestamp = health.lastSuccessAt else {
            return L10n.tr("Last success: -")
        }

        return L10n.format("Last success: %@", Self.statusDateFormatter.string(from: timestamp))
    }

    var latencyText: String {
        guard let latencyMs = health.lastLatencyMs else {
            return L10n.tr("Latency: -")
        }
        return L10n.format("Latency: %lld ms", Int64(latencyMs))
    }

    var hasVisibleData: Bool {
        !visibleEntries.isEmpty
    }

    var shouldShowConfirmedEmptyState: Bool {
        health.state == .healthy && isConfirmedEmpty && visibleEntries.isEmpty
    }

    var shouldShowDegradedNoDataState: Bool {
        (viewState == .recovering || viewState == .degradedWithCache || viewState == .fatal) && !hasVisibleData
    }

    var canRetryNow: Bool {
        health.state == .degraded || health.state == .reconnecting || health.state == .failed || viewState == .degradedWithCache || viewState == .recovering
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func loadInitial() async {
        // First load also starts background health polling + degraded auto-retry loop.
        viewState = .loadingFirstPage
        await loadPath(currentPath, reason: "initial")
        startHealthLoop()
        startDegradedRefreshLoop()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func refresh() async {
        await loadPath(currentPath, reason: "refresh")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func retryNow() async {
        await retryCurrentPath(reason: "manual-retry")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func goTo(path: String) async {
        await loadPath(path, reason: "navigate")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func goRoot() async {
        await loadPath("/", reason: "root")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func goUp() async {
        guard !requestInFlight else {
            return
        }

        // Parent-path navigation goes through dedicated service API.
        latestRequestID += 1
        let requestID = latestRequestID
        requestInFlight = true
        let snapshot = await remotesViewModel.goUpBrowserPath(
            sessionID: sessionID,
            currentPath: currentPath,
            requestID: requestID
        )
        apply(snapshot: snapshot, reason: "up")
        requestInFlight = false
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func open(_ item: RemoteDirectoryItem) async {
        await loadPath(item.fullPath, reason: "open")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func toggleFavoriteForCurrentPath() {
        let normalized = BrowserPathNormalizer.normalize(path: currentPath)
        if let idx = favorites.firstIndex(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            favorites.remove(at: idx)
        } else {
            favorites.insert(normalized, at: 0)
            favorites = RemotesViewModel.normalizePathMemoryCollection(
                favorites,
                limit: RemotesViewModel.favoritesLimit
            )
        }
        // Persist favorites/recents immediately so editor/session state stays in sync.
        persistPathMemory()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func selectCurrentPath() -> String {
        addRecentPath(currentPath)
        return currentPath
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func select(_ item: RemoteDirectoryItem) -> String {
        let normalized = BrowserPathNormalizer.normalize(path: item.fullPath)
        addRecentPath(normalized)
        return normalized
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    func closeSession() async {
        healthTask?.cancel()
        healthTask = nil
        degradedRefreshTask?.cancel()
        degradedRefreshTask = nil
        await remotesViewModel.stopBrowserSession(id: sessionID)
    }

    var isCurrentPathFavorite: Bool {
        favorites.contains { $0.caseInsensitiveCompare(currentPath) == .orderedSame }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    private func loadPath(_ path: String, reason: String) async {
        guard !requestInFlight else {
            return
        }

        latestRequestID += 1
        let requestID = latestRequestID
        let normalized = BrowserPathNormalizer.normalize(path: path)

        if entries.isEmpty {
            viewState = .loadingFirstPage
        } else {
            viewState = .recovering
        }

        requestInFlight = true
        let snapshot = await remotesViewModel.loadBrowserPath(
            sessionID: sessionID,
            path: normalized,
            requestID: requestID
        )
        // apply(...) enforces request-ordering and state transitions in one place.
        apply(snapshot: snapshot, reason: reason)
        requestInFlight = false
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    /// This is async: it can suspend and resume later without blocking a thread.
    private func retryCurrentPath(reason: String) async {
        guard !requestInFlight else {
            return
        }

        latestRequestID += 1
        let requestID = latestRequestID
        requestInFlight = true
        let snapshot = await remotesViewModel.retryCurrentBrowserPath(
            sessionID: sessionID,
            lastKnownPath: currentPath,
            requestID: requestID
        )
        apply(snapshot: snapshot, reason: reason)
        requestInFlight = false
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func apply(snapshot: RemoteBrowserSnapshot, reason: String) {
        // Only accept the exact in-flight request response.
        guard snapshot.requestID == latestRequestID else {
            return
        }

        currentPath = BrowserPathNormalizer.normalize(path: snapshot.path)
        health = snapshot.health
        isStale = snapshot.isStale
        isConfirmedEmpty = snapshot.isConfirmedEmpty
        statusMessage = snapshot.message

        assert(snapshot.entries.allSatisfy(\.isDirectory), "Browser snapshots are expected to be directories-only.")
        let directoryEntries = snapshot.entries
        if !directoryEntries.isEmpty {
            entries = directoryEntries
        } else if snapshot.isConfirmedEmpty && !snapshot.isStale {
            // Only clear list on confirmed healthy empty folder.
            entries = []
        } else if entries.isEmpty {
            entries = []
        }

        if snapshot.health.state == .failed && entries.isEmpty {
            viewState = .fatal
        } else if snapshot.isStale {
            // Stale data means show cache while recovery continues.
            viewState = entries.isEmpty ? .recovering : .degradedWithCache
        } else if snapshot.health.state == .degraded {
            viewState = entries.isEmpty ? .recovering : .degradedWithCache
        } else if snapshot.health.state == .reconnecting || snapshot.health.state == .connecting {
            viewState = .recovering
        } else {
            viewState = .ready
            // Browsed paths become recents only on healthy ready state.
            addRecentPath(currentPath)
        }

        if reason == "open" || reason == "navigate" || reason == "root" || reason == "up" {
            selectedItemID = nil
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func persistPathMemory() {
        onPathMemoryChanged?(favorites, recents)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func addRecentPath(_ path: String) {
        let updated = RemotesViewModel.pushRecentRemotePath(
            path,
            existing: recents,
            limit: RemotesViewModel.recentsLimit
        )
        guard updated != recents else {
            return
        }
        recents = updated
        persistPathMemory()
    }

    private func rebuildVisibleEntries() {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = entries.filter { entry in
            trimmedSearch.isEmpty || entry.name.localizedCaseInsensitiveContains(trimmedSearch)
        }

        switch sortMode {
        case .name:
            visibleEntries = filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .modified:
            visibleEntries = filtered.sorted { lhs, rhs in
                switch (lhs.modifiedAt, rhs.modifiedAt) {
                case let (l?, r?):
                    if l == r {
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    return l > r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func startHealthLoop() {
        healthTask?.cancel()
        healthTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if Task.isCancelled {
                    break
                }
                let latest = await remotesViewModel.browserHealth(sessionID: sessionID)
                health = latest
                let projection = Self.projectPolledHealth(
                    latest,
                    currentViewState: viewState,
                    hasEntries: !entries.isEmpty,
                    isConfirmedEmpty: isConfirmedEmpty,
                    isStale: isStale,
                    statusMessage: statusMessage
                )
                viewState = projection.viewState
                isStale = projection.isStale
                statusMessage = projection.statusMessage
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func startDegradedRefreshLoop() {
        degradedRefreshTask?.cancel()
        degradedRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if Task.isCancelled {
                    break
                }

                let shouldRetry = health.state != .healthy && health.state != .closed
                guard shouldRetry else {
                    continue
                }

                // Automatic retry while degraded avoids requiring constant user refresh clicks.
                await retryCurrentPath(reason: "auto-retry")
            }
        }
    }

    private static let statusDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    nonisolated static func projectPolledHealth(
        _ latest: BrowserConnectionHealth,
        currentViewState: BrowserViewState,
        hasEntries: Bool,
        isConfirmedEmpty: Bool,
        isStale: Bool,
        statusMessage: String?
    ) -> (viewState: BrowserViewState, isStale: Bool, statusMessage: String?) {
        switch latest.state {
        case .healthy:
            let resolvedViewState = (hasEntries || isConfirmedEmpty) ? BrowserViewState.ready : currentViewState
            return (resolvedViewState, false, nil)
        case .degraded:
            return (hasEntries ? .degradedWithCache : .recovering, true, statusMessage)
        case .reconnecting, .connecting:
            return (.recovering, true, statusMessage)
        case .failed:
            return (hasEntries ? .degradedWithCache : .fatal, true, statusMessage)
        case .closed:
            return (currentViewState, isStale, statusMessage)
        }
    }
}
