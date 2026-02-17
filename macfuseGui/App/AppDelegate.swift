// BEGINNER FILE GUIDE
// Layer: App lifecycle layer
// Purpose: This file controls macOS app startup, window/bootstrap wiring, or application delegate behavior.
// Called by: Usually called by the system (AppKit/SwiftUI) during app launch, reopen, and termination events.
// Calls into: Calls into AppEnvironment, view models, and menu/window controllers.
// Concurrency: Runs on MainActor for UI-safe state updates; this means logic is serialized on the main actor context.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import Darwin
import Foundation

// AppDelegate owns high-level lifecycle control:
// - app bootstrap
// - global quit behavior
// - graceful shutdown coordination
//
// This app is LSUIElement (menu-bar style), so normal document-window behavior
// is intentionally different from a standard foreground macOS app.
extension Notification.Name {
    static let forceQuitRequested = Notification.Name("com.visualweb.macfusegui.forceQuitRequested")
}

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var menuBarController: MenuBarController?
    private var keyboardMonitor: Any?
    private var terminationFallback: DispatchWorkItem?
    private var terminationTask: Task<Void, Never>?
    private var isTerminating = false
    // File descriptor for singleton lock file. `-1` means no lock held.
    // We keep this open for process lifetime so flock lock stays active.
    private var singletonLockFD: CInt = -1

    /// Beginner note: This method is one step in the feature workflow for this file.
    func applicationDidFinishLaunching(_ notification: Notification) {
        if isRunningUnderXCTest() {
            // Test host process should not create a menu bar icon or run recovery startup.
            // Unit tests instantiate their own services/view-models directly.
            return
        }

        if !acquireSingletonLock() {
            _ = shouldTerminateAsDuplicateInstance()
            NSApp.terminate(nil)
            return
        }

        // Prevent duplicate app instances from creating duplicate menu bar icons.
        // If another instance is already running, we activate it and exit this one.
        //
        // Note for tests:
        // When running unit tests, Xcode launches a copy of the app as the "test host".
        // If the real app is already running, the duplicate-instance guard would
        // immediately terminate the test host and cause "early unexpected exit" failures.
        if shouldTerminateAsDuplicateInstance() {
            NSApp.terminate(nil)
            return
        }

        // Accessory policy keeps app in menu bar without Dock icon focus behavior.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()
        installKeyboardMonitor()

        // Build dependency graph once and wire menu controller to shared view model.
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let environment = AppEnvironment()
            self.environment = environment

            self.menuBarController = MenuBarController(
                viewModel: environment.remotesViewModel,
                settingsWindowController: environment.settingsWindowController,
                editorPluginRegistry: environment.editorPluginRegistry,
                editorOpenService: environment.editorOpenService
            )

            Task { @MainActor [weak self] in
                guard self != nil else {
                    return
                }
                // First refresh from real mount state, then run startup auto-connect intent.
                await environment.remotesViewModel.refreshAllStatuses()
                await environment.remotesViewModel.runStartupAutoConnect()
            }
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func applicationWillTerminate(_ notification: Notification) {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }

        terminationTask?.cancel()
        terminationTask = nil
        terminationFallback?.cancel()
        terminationFallback = nil
        releaseSingletonLock()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTerminating {
            return .terminateNow
        }
        // We intercept default termination to run controlled shutdown path.
        forceQuit()
        return .terminateCancel
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func forceQuit() {
        guard !isTerminating else {
            return
        }

        isTerminating = true
        // Lets any listeners proactively stop background work.
        NotificationCenter.default.post(name: .forceQuitRequested, object: nil)
        // Give termination cleanup enough runway to force-stop/unmount sshfs mounts.
        scheduleTerminationFallback(after: 15.0)
        // Close modal/sheet/window stacks first to avoid quit being blocked by UI state.
        closeAllWindowsForTermination()

        terminationTask?.cancel()
        terminationTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.environment?.remotesViewModel.prepareForTermination()
            // Final pass asks AppKit to stop runloop + terminate process.
            self.performTerminationPass()
        }
    }

    @objc
    /// Beginner note: This method is one step in the feature workflow for this file.
    private func handleQuitMenuAction(_ sender: Any?) {
        forceQuit()
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func closeAllWindowsForTermination() {
        // Modal loops can block app termination; abort/stop repeatedly as defensive cleanup.
        var modalTeardownPasses = 0
        while let modalWindow = NSApp.modalWindow, modalTeardownPasses < 8 {
            modalTeardownPasses += 1
            NSApp.abortModal()
            NSApp.stopModal()
            modalWindow.orderOut(nil)
            modalWindow.close()
        }

        var sheetTeardownPasses = 0
        while sheetTeardownPasses < 8 {
            sheetTeardownPasses += 1
            let windowsWithSheets = NSApp.windows.filter { $0.attachedSheet != nil }
            if windowsWithSheets.isEmpty {
                break
            }

            for window in windowsWithSheets {
                guard let attachedSheet = window.attachedSheet else {
                    continue
                }
                window.endSheet(attachedSheet, returnCode: .cancel)
                attachedSheet.orderOut(nil)
                attachedSheet.close()
            }
        }

        for window in NSApp.windows.reversed() {
            if window.isSheet, let parent = window.sheetParent {
                parent.endSheet(window, returnCode: .cancel)
            }
            window.orderOut(nil)
            window.close()
        }

        for window in NSApp.windows where window.isVisible {
            window.performClose(nil)
            window.orderOut(nil)
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func performTerminationPass() {
        closeAllWindowsForTermination()
        NSApp.stop(nil)
        NSApp.terminate(nil)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func scheduleTerminationFallback(after delay: TimeInterval) {
        terminationFallback?.cancel()

        // Hard fallback: ensures Quit always exits even if modal teardown gets stuck.
        // _exit is intentionally last-resort and bypasses normal teardown callbacks.
        let fallback = DispatchWorkItem {
            _exit(0)
        }
        terminationFallback = fallback
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: fallback)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func installKeyboardMonitor() {
        // Extra safeguard: command+Q should always route through same controlled quit flow.
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            let isCommandQ = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) &&
                event.charactersIgnoringModifiers?.lowercased() == "q"

            if isCommandQ {
                self.forceQuit()
                return nil
            }
            return event
        }
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit macfuseGui", action: #selector(handleQuitMenuAction(_:)), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        return mainMenu
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    private func shouldTerminateAsDuplicateInstance() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let executableName = Bundle.main.executableURL?.lastPathComponent
        let bundleDisplayName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
        let currentBundleName = Bundle.main.bundleURL.lastPathComponent

        let otherInstances = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != currentPID && !app.isTerminated else {
                return false
            }

            // Ignore Xcode test hosts in DerivedData when deciding duplicate real app instances.
            if app.bundleURL?.path.contains("/DerivedData/") == true {
                return false
            }

            let candidateBundleName = app.bundleURL?.lastPathComponent
            let sameBundleID = bundleIdentifier != nil && app.bundleIdentifier == bundleIdentifier
            let sameExecutable = executableName != nil && app.executableURL?.lastPathComponent == executableName
            let sameDisplayName = bundleDisplayName != nil && app.localizedName == bundleDisplayName
            let sameBundleName = candidateBundleName != nil && candidateBundleName == currentBundleName

            if bundleIdentifier != nil {
                // Prefer bundle identifier when available to avoid false positives.
                return sameBundleID
            }

            // Fallback heuristics for unusual launch contexts where bundle ID is unavailable.
            return sameBundleName && (sameExecutable || sameDisplayName)
        }

        guard !otherInstances.isEmpty else {
            return false
        }

        // Prefer the oldest running instance and bring it to foreground focus.
        let existingInstance = otherInstances
            .sorted { lhs, rhs in
                let lhsLaunch = lhs.launchDate ?? .distantPast
                let rhsLaunch = rhs.launchDate ?? .distantPast
                if lhsLaunch == rhsLaunch {
                    return lhs.processIdentifier < rhs.processIdentifier
                }
                return lhsLaunch < rhsLaunch
            }
            .first

        existingInstance?.activate(options: [.activateIgnoringOtherApps])
        NSLog(
            "[app] Duplicate instance detected. Existing pid=%d, current pid=%d. Terminating current process.",
            existingInstance?.processIdentifier ?? -1,
            currentPID
        )
        return true
    }

    /// Beginner note: Tries to become the single app instance using an OS file lock.
    /// If another process already holds the lock, this returns false.
    private func acquireSingletonLock() -> Bool {
        let lockPath = "/tmp/com.visualweb.macfusegui.instance.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard fd >= 0 else {
            // If lock setup fails, continue with bundle-id duplicate detection path.
            return true
        }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            singletonLockFD = fd
            return true
        }

        close(fd)
        return false
    }

    /// Beginner note: Releases lock file on app termination.
    /// Always close FD after unlocking so future launches can lock cleanly.
    private func releaseSingletonLock() {
        guard singletonLockFD >= 0 else {
            return
        }
        flock(singletonLockFD, LOCK_UN)
        close(singletonLockFD)
        singletonLockFD = -1
    }

    /// Beginner note: Detects whether this process is an XCTest host process.
    /// We use multiple checks because Xcode launch contexts vary by test mode.
    private func isRunningUnderXCTest() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["XCTestSessionIdentifier"] != nil {
            return true
        }

        if NSClassFromString("XCTestCase") != nil {
            return true
        }

        return ProcessInfo.processInfo.processName.lowercased().contains("xctest")
    }

}
