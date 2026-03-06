import Foundation

enum L10n {
    private final class BundleToken {}

    private static let bundle = Bundle(for: BundleToken.self)

    static func tr(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: arguments)
    }
}
