import SwiftUI

/// The selected bundle, or the main bundle when following the application's default language.
enum L10n {
    static var bundle: Bundle = .main
    static var locale: Locale = .autoupdatingCurrent

    static func tr(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

extension View {
    /// A popover may need its own locale environment on macOS 12.
    func appLocalized() -> some View {
        environment(\.locale, L10n.locale)
    }
}
