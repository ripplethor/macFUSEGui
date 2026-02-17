// BEGINNER FILE GUIDE
// Layer: App lifecycle layer
// Purpose: This file controls macOS app startup, window/bootstrap wiring, or application delegate behavior.
// Called by: Usually called by the system (AppKit/SwiftUI) during app launch, reopen, and termination events.
// Calls into: Calls into AppEnvironment, view models, and menu/window controllers.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import SwiftUI

@MainActor
/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class SettingsWindowController: NSWindowController {
    /// Beginner note: Initializers create valid state before any other method is used.
    init(viewModel: RemotesViewModel, onOpenEditorPlugins: @escaping () -> Void) {
        let root = SettingsRootView(
            viewModel: viewModel,
            onOpenEditorPlugins: onOpenEditorPlugins
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "macfuseGui Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 620))
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    /// Beginner note: Initializers create valid state before any other method is used.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
/// Beginner note: Dedicated controller for plugin management so settings stay focused.
final class EditorPluginSettingsWindowController: NSWindowController {
    /// Beginner note: Initializers create valid state before any other method is used.
    init(editorPluginRegistry: EditorPluginRegistry) {
        let root = EditorPluginSettingsView(editorPluginRegistry: editorPluginRegistry)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Editor Plugins"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 620))
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    /// Beginner note: Initializers create valid state before any other method is used.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
