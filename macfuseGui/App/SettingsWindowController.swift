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
/// Beginner note: Shared window setup keeps sizing, activation, and persistence behavior consistent.
/// Window sizing is driven by the SwiftUI view's .frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:)
/// via NSHostingSizingOptions. The window controller does not hardcode pixel dimensions.
class BaseSettingsWindowController: NSWindowController {
    private let hasSavedFrame: Bool
    private var didApplyInitialCentering = false

    /// Beginner note: Initializers create valid state before any other method is used.
    init(
        rootView: AnyView,
        title: String,
        frameAutosaveName: String
    ) {
        hasSavedFrame = UserDefaults.standard.object(forKey: "NSWindow Frame \(frameAutosaveName)") != nil
        let hosting = NSHostingController(rootView: rootView)

        // sizingOptions drives contentMinSize/contentMaxSize from the SwiftUI view's
        // .frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:).
        hosting.sizingOptions = [.preferredContentSize, .minSize, .maxSize]

        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false

        // Force a layout pass so the hosting controller measures the SwiftUI view
        // and populates preferredContentSize before the window is shown.
        // Then cap to the screen's visible area so the window never goes off-screen.
        hosting.view.layoutSubtreeIfNeeded()
        let preferred = hosting.preferredContentSize
        if preferred.width > 0 && preferred.height > 0 {
            let visibleFrame = NSScreen.main?.visibleFrame.size ?? preferred
            let capped = NSSize(
                width: min(preferred.width, visibleFrame.width),
                height: min(preferred.height, visibleFrame.height)
            )
            window.setContentSize(capped)
        }

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
            frameAutosaveName: "SettingsWindow"
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
            frameAutosaveName: "EditorPluginSettingsWindow"
        )
    }

    @available(*, unavailable)
    /// Beginner note: Initializers create valid state before any other method is used.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
