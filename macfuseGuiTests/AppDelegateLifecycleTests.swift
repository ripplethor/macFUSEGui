// BEGINNER FILE GUIDE
// Layer: Automated test layer
// Purpose: This file verifies production behavior and protects against regressions when code changes.
// Called by: Executed by XCTest during xcodebuild test or IDE test runs.
// Calls into: Calls production code and test fixtures with deterministic assertions.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Start reading top-to-bottom once, then follow one user action end-to-end through call sites.

import AppKit
import XCTest
@testable import macfuseGui

/// Beginner note: This type groups related state and behavior for one part of the app.
/// Read stored properties first, then follow methods top-to-bottom to understand flow.
final class AppDelegateLifecycleTests: XCTestCase {
    @MainActor
    func testReopenShowsSettingsAndSuppressesDefaultHandling() {
        var settingsShowCount = 0
        let delegate = AppDelegate(showSettingsOnReopen: { settingsShowCount += 1 })

        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        XCTAssertEqual(settingsShowCount, 1)
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testIsRunningUnderXCTestUsesEnvironmentKeys() {
        XCTAssertTrue(
            AppDelegate.isRunningUnderXCTest(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctest"],
                processName: "macfuseGui",
                hasXCTestCaseClass: false
            )
        )
        XCTAssertTrue(
            AppDelegate.isRunningUnderXCTest(
                environment: ["XCTestBundlePath": "/tmp/bundle"],
                processName: "macfuseGui",
                hasXCTestCaseClass: false
            )
        )
        XCTAssertTrue(
            AppDelegate.isRunningUnderXCTest(
                environment: ["XCTestSessionIdentifier": "ABC"],
                processName: "macfuseGui",
                hasXCTestCaseClass: false
            )
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testIsRunningUnderXCTestUsesClassAndProcessFallbacks() {
        XCTAssertTrue(
            AppDelegate.isRunningUnderXCTest(
                environment: [:],
                processName: "macfuseGui",
                hasXCTestCaseClass: true
            )
        )
        XCTAssertTrue(
            AppDelegate.isRunningUnderXCTest(
                environment: [:],
                processName: "xctest",
                hasXCTestCaseClass: false
            )
        )
    }

    /// Beginner note: This method is one step in the feature workflow for this file.
    func testIsRunningUnderXCTestReturnsFalseForNormalAppProcess() {
        XCTAssertFalse(
            AppDelegate.isRunningUnderXCTest(
                environment: [:],
                processName: "macfuseGui",
                hasXCTestCaseClass: false
            )
        )
    }
}
