// BEGINNER FILE GUIDE
// Layer: App lifecycle layer
// Purpose: This file controls macOS app startup, window/bootstrap wiring, or application delegate behavior.
// Called by: Usually called by the system (AppKit/SwiftUI) during app launch, reopen, and termination events.
// Calls into: Calls into AppEnvironment, view models, and menu/window controllers.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import Foundation

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class AppEnvironment {
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
        diagnosticsService = DiagnosticsService()
        redactionService = RedactionService()
        processRunner = ProcessRunner()
        dependencyChecker = DependencyChecker()
        launchAtLoginService = LaunchAtLoginService(runner: processRunner)
        remoteStore = JSONRemoteStore()
        keychainService = KeychainService()
        validationService = ValidationService()
        askpassHelper = AskpassHelper()
        mountStateParser = MountStateParser()
        mountCommandBuilder = MountCommandBuilder(redactionService: redactionService)
        unmountService = UnmountService(
            runner: processRunner,
            diagnostics: diagnosticsService,
            mountStateParser: mountStateParser
        )
        mountManager = MountManager(
            runner: processRunner,
            dependencyChecker: dependencyChecker,
            askpassHelper: askpassHelper,
            unmountService: unmountService,
            mountStateParser: mountStateParser,
            diagnostics: diagnosticsService,
            commandBuilder: mountCommandBuilder
        )
        let browserTransport = LibSSH2SFTPTransport(
            diagnostics: diagnosticsService
        )
        let browserSessionManager = RemoteBrowserSessionManager(
            transport: browserTransport,
            diagnostics: diagnosticsService
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
            launchAtLoginService: launchAtLoginService
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
