//
//  Localization.swift
//  MTMR
//
//  User-facing text lives in Localizable.strings (en.lproj, zh-Hans.lproj). The English text in the
//  source is the key, so a missing translation, or a bundle without strings files (the unit-test
//  runner), falls back to the English default.
//
//  The app language can be changed at run time (status menu › Settings › Language). To make that
//  take effect without a relaunch, every lookup goes through the bundle of the chosen language:
//  - AppKit / model code: `NSLocalizedString("…", bundle: L10n.bundle, comment: "…")`
//    (LocalizationTests fails for a call without `bundle: L10n.bundle`).
//  - Keys only known at run time (catalog names, units, enum labels): `L10n.tr` / `L10n.option`.
//  - SwiftUI literals (`Text("…")`, `Button("…")`, `.help("…")`) resolve through the
//    `\.locale` environment, which the customizer sets with `appLocalized()`.
//  Never pass user content (preset titles) or values that are written to items.json through these.
//
//  Language changes post `L10n.languageDidChange`; observers rebuild their UI. System parts that are
//  only read at launch (storyboard main menu, Sparkle) follow the `AppleLanguages` override that is
//  written here, i.e. from the next launch on.
//

import Foundation

/// The language chosen by the user. Raw values are stored in user defaults and are lproj names.
enum AppLanguage: String, CaseIterable, Identifiable {
    /// Follow the macOS language order (default).
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// Parses a stored value; anything unknown (or missing) follows the system.
    init(storedValue: String?) {
        self = storedValue.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// The lproj this choice forces, nil when following the system.
    var forcedLocalization: String? { self == .system ? nil : rawValue }

    /// English key of the menu title. Language names are autonyms in every localization,
    /// so a user can always find their own language.
    var titleKey: String {
        switch self {
        case .system: return "Follow System"
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        }
    }

    var title: String { L10n.tr(titleKey) }
}

extension L10n {
    /// User defaults key of the chosen `AppLanguage`.
    static let languageDefaultsKey = "com.toxblh.mtmr.settings.language"
    /// Per-app language override read by Foundation/AppKit at launch.
    static let appleLanguagesKey = "AppleLanguages"
    /// Localizations that ship a complete Localizable.strings, in fallback order.
    static let supportedLocalizations = ["en", "zh-Hans"]
    static let developmentLocalization = "en"
    /// Posted on the main thread after `setLanguage(_:)` changed the language.
    static let languageDidChange = Notification.Name("com.toxblh.mtmr.languageDidChange")

    private struct State {
        let language: AppLanguage
        let localization: String
        let bundle: Bundle
    }

    private static var defaults: UserDefaults = .standard
    private static var resources: Bundle = .main
    private static var systemLanguagesOverride: [String]?
    private static var state = makeState()

    /// The language the user chose (may be `.system`).
    static var language: AppLanguage { state.language }
    /// The lproj in use, e.g. "zh-Hans"; resolved from the system order for `.system`.
    static var localization: String { state.localization }
    /// Display label for a JSON enum value such as "metric" or "left" (key "option.<value>").
    /// Only the label is translated; the value stored in items.json stays `raw`.
    /// Values without a translation (or written by hand) are shown as they are.
    static func option(_ raw: String) -> String {
        bundle.localizedString(forKey: "option." + raw, value: raw, table: nil)
    }

    // MARK: Changing the language

    /// Stores the choice, syncs `AppleLanguages` (removed when following the system, so macOS'
    /// own order applies again), switches all lookups and posts `languageDidChange`.
    static func setLanguage(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: languageDefaultsKey)
        if let forced = language.forcedLocalization {
            defaults.set([forced], forKey: appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: appleLanguagesKey)
        }
        state = makeState()
        bundle = state.bundle
        locale = Locale(identifier: state.localization)
        let post = { NotificationCenter.default.post(name: languageDidChange, object: nil) }
        Thread.isMainThread ? post() : DispatchQueue.main.async(execute: post)
    }

    /// Points the lookups at other sources and re-reads the stored language. For unit tests;
    /// `systemLanguages` replaces the macOS language order.
    static func configure(defaults: UserDefaults = .standard, resources: Bundle = .main, systemLanguages: [String]? = nil) {
        self.defaults = defaults
        self.resources = resources
        systemLanguagesOverride = systemLanguages
        state = makeState()
        bundle = state.bundle
        locale = Locale(identifier: state.localization)
    }

    // MARK: Resolution

    /// The lproj to use: the forced one, otherwise the best match of the system order, otherwise English.
    static func resolveLocalization(
        for language: AppLanguage,
        systemLanguages: [String],
        available: [String] = supportedLocalizations
    ) -> String {
        if let forced = language.forcedLocalization, available.contains(forced) { return forced }
        guard !systemLanguages.isEmpty else { return developmentLocalization }
        let match = Bundle.preferredLocalizations(from: available, forPreferences: systemLanguages).first
        return match.flatMap { available.contains($0) ? $0 : nil } ?? developmentLocalization
    }

    /// The macOS language order without this app's own override. The global domain is read
    /// directly because `Locale.preferredLanguages` still reports an override removed at run time.
    static var systemLanguages: [String] {
        if let override = systemLanguagesOverride { return override }
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return global?[appleLanguagesKey] as? [String] ?? Locale.preferredLanguages
    }

    private static func makeState() -> State {
        let language = AppLanguage(storedValue: defaults.string(forKey: languageDefaultsKey))
        let localization = resolveLocalization(for: language, systemLanguages: systemLanguages)
        let bundle = resources.path(forResource: localization, ofType: "lproj").flatMap(Bundle.init(path:)) ?? resources
        return State(language: language, localization: localization, bundle: bundle)
    }
}
