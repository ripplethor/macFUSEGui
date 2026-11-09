// BEGINNER FILE GUIDE
// Layer: App lifecycle layer
// Purpose: This file controls macOS app startup, window/bootstrap wiring, or application delegate behavior.
// Called by: Usually called by the system (AppKit/SwiftUI) during app launch, reopen, and termination events.
// Calls into: Calls into AppEnvironment, view models, and menu/window controllers.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

// RuntimeConfiguration centralizes timing thresholds that act as reliability and UX contracts.
// Keep defaults stable unless you are intentionally changing behavior.
struct RuntimeConfiguration: Sendable {
    struct Remotes: Sendable {
        var connectWatchdogTimeout: TimeInterval = 45
        var disconnectWatchdogTimeout: TimeInterval = 10
        var refreshWatchdogTimeout: TimeInterval = 18
        var healthyPeriodicProbeInterval: TimeInterval = 60
        // Keep periodic probe cadence configurable for tests and reliability tuning.
        var periodicRecoveryPassInterval: TimeInterval = 15
        // Queue label is configurable so tests can use predictable queue names.
        var networkMonitorQueueLabel: String = "com.visualweb.macfusegui.network-monitor"
    }

    struct Unmount: Sendable {
        var totalUnmountTimeout: TimeInterval = 10
        var perCommandMaxTimeout: TimeInterval = 3
    }

    struct Browser: Sendable {
        var breakerThreshold: Int = 8
        var breakerWindow: TimeInterval = 30
    }

    struct Mount: Sendable {
        var sshfsConnectCommandTimeout: TimeInterval = 20
    }

    var remotes = Remotes()
    var unmount = Unmount()
    var browser = Browser()
    var mount = Mount()
}

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class AppEnvironment {
    let runtimeConfiguration: RuntimeConfiguration
    let diagnosticsService: DiagnosticsService
    let redactionService: RedactionService
    let processRunner: ProcessRunner
    let dependencyChecker: DependencyChecker
    let launchAtLoginService: LaunchAtLoginService
    let remoteStore: RemoteStore
    let keychainService: KeychainServiceProtocol
    let validationService: ValidationService
    let askpassHelper: AskpassHelper
    let mountStateParser: MountStateParser
    let mountCommandBuilder: MountCommandBuilder
    let unmountService: UnmountService
    let mountManager: MountManager
    let remoteDirectoryBrowserService: RemoteDirectoryBrowserService
    let editorPluginRegistry: EditorPluginRegistry
    let editorOpenService: EditorOpenService
    let remotesViewModel: RemotesViewModel
    let settingsWindowController: SettingsWindowController
    let editorPluginSettingsWindowController: EditorPluginSettingsWindowController

    /// Beginner note: Initializers create valid state before any other method is used.
    init() {
        runtimeConfiguration = RuntimeConfiguration()
        diagnosticsService = DiagnosticsService()
        redactionService = RedactionService()
        processRunner = ProcessRunner()
        dependencyChecker = DependencyChecker()
        launchAtLoginService = LaunchAtLoginService(runner: processRunner)
        do {
            try launchAtLoginService.updateLegacyLaunchAgent()
        } catch {
            diagnosticsService.append(
                level: .warning,
                category: "startup",
                message: "Could not update legacy launch at login: \(error.localizedDescription)"
            )
        }
        remoteStore = JSONRemoteStore()
        keychainService = KeychainService()
        validationService = ValidationService()
        askpassHelper = AskpassHelper(diagnostics: diagnosticsService)
        mountStateParser = MountStateParser()
        mountCommandBuilder = MountCommandBuilder(redactionService: redactionService)
        unmountService = UnmountService(
            runner: processRunner,
            diagnostics: diagnosticsService,
            mountStateParser: mountStateParser,
            totalUnmountTimeout: runtimeConfiguration.unmount.totalUnmountTimeout,
            perCommandMaxTimeout: runtimeConfiguration.unmount.perCommandMaxTimeout
        )
        mountManager = MountManager(
            runner: processRunner,
            dependencyChecker: dependencyChecker,
            askpassHelper: askpassHelper,
            unmountService: unmountService,
            mountStateParser: mountStateParser,
            diagnostics: diagnosticsService,
            commandBuilder: mountCommandBuilder,
            sshfsConnectCommandTimeout: runtimeConfiguration.mount.sshfsConnectCommandTimeout
        )
        let browserTransport = LibSSH2SFTPTransport(
            diagnostics: diagnosticsService
        )
        let browserSessionManager = RemoteBrowserSessionManager(
            transport: browserTransport,
            diagnostics: diagnosticsService,
            breakerThreshold: runtimeConfiguration.browser.breakerThreshold,
            breakerWindow: runtimeConfiguration.browser.breakerWindow
        )
        remoteDirectoryBrowserService = RemoteDirectoryBrowserService(
            manager: browserSessionManager,
            diagnostics: diagnosticsService
        )
        editorPluginRegistry = EditorPluginRegistry()
        editorOpenService = EditorOpenService(
            pluginRegistry: editorPluginRegistry,
            runner: processRunner
        )

        remotesViewModel = RemotesViewModel(
            remoteStore: remoteStore,
            keychainService: keychainService,
            validationService: validationService,
            dependencyChecker: dependencyChecker,
            mountManager: mountManager,
            remoteDirectoryBrowserService: remoteDirectoryBrowserService,
            diagnostics: diagnosticsService,
            launchAtLoginService: launchAtLoginService,
            runtimeConfiguration: runtimeConfiguration
        )

        let pluginSettingsWindowController = EditorPluginSettingsWindowController(
            editorPluginRegistry: editorPluginRegistry
        )
        editorPluginSettingsWindowController = pluginSettingsWindowController

        settingsWindowController = SettingsWindowController(
            viewModel: remotesViewModel,
            onOpenEditorPlugins: {
                pluginSettingsWindowController.showWindow(nil)
            }
        )
        remotesViewModel.load()
    }
}
