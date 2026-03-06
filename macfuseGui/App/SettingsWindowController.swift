// BEGINNER FILE GUIDE
// Layer: App lifecycle layer
// Purpose: This file controls macOS app startup, window/bootstrap wiring, or application delegate behavior.
// Called by: Usually called by the system (AppKit/SwiftUI) during app launch, reopen, and termination events.
// Calls into: Calls into AppEnvironment, view models, and menu/window controllers.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import SwiftUI

private let baseSettingsDefaultWindowSize = NSSize(width: 980, height: 620)
private let baseSettingsMinimumWindowSize = NSSize(width: 600, height: 400)

@MainActor
/// Beginner note: Shared window setup keeps sizing, activation, and persistence behavior consistent.
class BaseSettingsWindowController: NSWindowController {
    private let hasSavedFrame: Bool
    private var didApplyInitialCentering = false

    /// Beginner note: Initializers create valid state before any other method is used.
    convenience init(
        rootView: AnyView,
        title: String,
        frameAutosaveName: String
    ) {
        self.init(
            rootView: rootView,
            title: title,
            frameAutosaveName: frameAutosaveName,
            defaultWindowSize: baseSettingsDefaultWindowSize,
            minimumWindowSize: baseSettingsMinimumWindowSize
        )
    }

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        rootView: AnyView,
        title: String,
        frameAutosaveName: String,
        defaultWindowSize: NSSize,
        minimumWindowSize: NSSize
    ) {
        hasSavedFrame = UserDefaults.standard.object(forKey: "NSWindow Frame \(frameAutosaveName)") != nil
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(defaultWindowSize)
        window.minSize = minimumWindowSize
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(frameAutosaveName)

        super.init(window: window)
    }

    @available(*, unavailable)
    /// Beginner note: Initializers create valid state before any other method is used.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    override func showWindow(_ sender: Any?) {
        if !didApplyInitialCentering && !hasSavedFrame {
            window?.center()
            didApplyInitialCentering = true
        }

        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class SettingsWindowController: BaseSettingsWindowController {
    /// Beginner note: Initializers create valid state before any other method is used.
    init(viewModel: RemotesViewModel, onOpenEditorPlugins: @escaping () -> Void) {
        let root = SettingsRootView(
            viewModel: viewModel,
            onOpenEditorPlugins: onOpenEditorPlugins
        )
        let appName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String ?? "App"
        super.init(
            rootView: AnyView(root),
            title: "\(appName) Settings",
            frameAutosaveName: "SettingsWindow",
            defaultWindowSize: SettingsRootView.minimumWindowSize,
            minimumWindowSize: SettingsRootView.minimumWindowSize
        )
    }

    @available(*, unavailable)
    /// Beginner note: Initializers create valid state before any other method is used.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

@MainActor
/// Beginner note: Dedicated controller for plugin management so settings stay focused.
final class EditorPluginSettingsWindowController: BaseSettingsWindowController {
    /// Beginner note: Initializers create valid state before any other method is used.
    init(editorPluginRegistry: EditorPluginRegistry) {
        let root = EditorPluginSettingsView(editorPluginRegistry: editorPluginRegistry)
        super.init(
            rootView: AnyView(root),
            title: "Editor Plugins",
            frameAutosaveName: "EditorPluginSettingsWindow",
            defaultWindowSize: baseSettingsDefaultWindowSize,
            minimumWindowSize: baseSettingsMinimumWindowSize
        )
    }

    @available(*, unavailable)
    /// Beginner note: Initializers create valid state before any other method is used.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
