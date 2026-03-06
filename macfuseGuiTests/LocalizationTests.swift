// BEGINNER FILE GUIDE
// Layer: Automated test layer
// Purpose: This file verifies localization resources and localized production strings.
// Called by: Executed by XCTest during xcodebuild test or IDE test runs.
// Calls into: Calls production code and bundle localization resources.
// Concurrency: Runs with standard synchronous execution unless specific methods use async/await.
// Maintenance tip: Keep these assertions focused on visible strings that must remain localized.

import XCTest
@testable import macfuseGui

final class LocalizationTests: XCTestCase {
    private lazy var catalog = try! loadCatalog()

    func testEnglishProductionStringsRemainReadable() {
        XCTAssertEqual(RemoteAuth.password.displayName, "Password")
        XCTAssertEqual(RemoteAuth.privateKey.displayName, "SSH Private Key")
        XCTAssertEqual(AppError.timeout("x").failureReason, "The operation exceeded its time limit.")
        XCTAssertEqual(AppError.timeout("x").recoverySuggestion, "Check network/system load and retry.")
    }

    func testValidationServiceUsesLocalizedEnglishMessages() {
        let service = ValidationService()
        let draft = RemoteDraft(
            displayName: "",
            host: "2001:db8::1",
            port: 0,
            username: "",
            authMode: .password,
            privateKeyPath: "",
            password: "",
            remoteDirectory: "relative/path",
            localMountPoint: "/"
        )

        let errors = service.validateDraft(draft, hasStoredPassword: false)
        XCTAssertTrue(errors.contains("Display name is required."))
        XCTAssertTrue(errors.contains("IPv6 addresses must be wrapped in brackets, for example [::1]."))
        XCTAssertTrue(errors.contains("Password is required for password authentication."))
    }

    func testGermanCatalogContainsTranslatedCoreKeys() throws {
        XCTAssertEqual(localizedString("Settings", locale: "de"), "Einstellungen")
        XCTAssertEqual(localizedString("Connect", locale: "de"), "Verbinden")
        XCTAssertEqual(localizedString("Remote Browser", locale: "de"), "Remote-Browser")
    }

    func testJapaneseCatalogContainsTranslatedCoreKeys() throws {
        XCTAssertEqual(localizedString("Settings", locale: "ja"), "設定")
        XCTAssertEqual(localizedString("Connect", locale: "ja"), "接続")
        XCTAssertEqual(localizedString("Remote Browser", locale: "ja"), "リモートブラウザ")
    }

    func testLaunchAtLoginFallbackDetailIsLocalizedFromCatalog() throws {
        XCTAssertEqual(
            localizedString("Enabled via LaunchAgent fallback.", locale: "de"),
            "Über LaunchAgent-Fallback aktiviert."
        )
    }

    func testCatalogDeclaresWaveOneLocales() {
        let locales = Set(catalog.locales)
        XCTAssertEqual(locales, Set(["en", "de", "es", "fr", "ja", "ko", "pt-BR", "zh-Hans"]))
    }

    private func localizedString(_ key: String, locale: String) -> String {
        catalog.string(for: key, locale: locale)
    }

    private func loadCatalog() throws -> StringCatalog {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = sourceRoot
            .appendingPathComponent("macfuseGui")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        return try JSONDecoder().decode(StringCatalog.self, from: data)
    }
}

private struct StringCatalog: Decodable {
    let sourceLanguage: String
    let version: String
    let strings: [String: CatalogEntry]

    var locales: [String] {
        let locales = strings.values.reduce(into: Set([sourceLanguage])) { partialResult, entry in
            partialResult.formUnion(entry.localizations.keys)
        }
        return Array(locales).sorted()
    }

    func string(for key: String, locale: String) -> String {
        strings[key]?.localizations[locale]?.stringUnit.value ?? key
    }
}

private struct CatalogEntry: Decodable {
    let localizations: [String: CatalogLocalization]
}

private struct CatalogLocalization: Decodable {
    let stringUnit: CatalogStringUnit
}

private struct CatalogStringUnit: Decodable {
    let value: String
}
