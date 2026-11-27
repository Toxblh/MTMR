//
//  LocalizationTests.swift
//  MTMRTests
//
//  Guards the bilingual (English / Simplified Chinese) localization:
//  - both Localizable.strings files have the same keys, no empty values, no duplicates, matching
//    format specifiers and no orphaned keys;
//  - everything the customizer shows from ItemCatalog has an entry in both files;
//  - every localized literal in MTMR/*.swift (NSLocalizedString, L10n.tr, SwiftUI Text/Button/.help…)
//    has an entry in both files, and NSLocalizedString goes through L10n.bundle so the run-time
//    language switch reaches it;
//  - the language setting resolves, persists and falls back as documented in Localization.swift.
//
//  The files are read from the source tree (the test runner bundle has no strings files).
//  When a test here fails after adding a feature: add the English key to en.lproj and its
//  translation to zh-Hans.lproj (same key, same format specifiers).
//

import XCTest

final class LocalizationTests: XCTestCase {
    // MARK: Sources

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let appSources = repoRoot.appendingPathComponent("MTMR")
    private static let localizations = ["en", "zh-Hans"]

    private static func stringsURL(_ localization: String) -> URL {
        appSources.appendingPathComponent("\(localization).lproj/Localizable.strings")
    }

    private static func loadStrings(_ localization: String) throws -> [String: String] {
        let data = try Data(contentsOf: stringsURL(localization))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: String], "\(localization): Localizable.strings is not a flat string table")
    }

    private lazy var tables: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for localization in Self.localizations {
            result[localization] = (try? Self.loadStrings(localization)) ?? [:]
        }
        return result
    }()

    // MARK: 1. The two strings files match

    func testStringsFilesExistAndParse() throws {
        for localization in Self.localizations {
            let table = try Self.loadStrings(localization)
            XCTAssertFalse(table.isEmpty, "\(localization): no entries")
        }
    }

    func testStringsFilesHaveIdenticalKeys() {
        let en = Set(tables["en", default: [:]].keys)
        let zh = Set(tables["zh-Hans", default: [:]].keys)
        XCTAssertEqual(en.subtracting(zh).sorted(), [], "Keys missing in zh-Hans.lproj/Localizable.strings")
        XCTAssertEqual(zh.subtracting(en).sorted(), [], "Keys missing in en.lproj/Localizable.strings")
    }

    func testNoEmptyValues() {
        for (localization, table) in tables {
            let empty = table.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.keys.sorted()
            XCTAssertEqual(empty, [], "\(localization): empty translations")
        }
    }

    /// PropertyListSerialization keeps the last of two equal keys silently, so look at the raw text.
    func testNoDuplicateKeys() throws {
        let keyPattern = try NSRegularExpression(pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*="#, options: .anchorsMatchLines)
        for localization in Self.localizations {
            let text = try String(contentsOf: Self.stringsURL(localization), encoding: .utf8)
            var seen = Set<String>(), duplicates: [String] = []
            for match in keyPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(match.range(at: 1), in: text)!])
                if !seen.insert(key).inserted { duplicates.append(key) }
            }
            XCTAssertEqual(duplicates, [], "\(localization): duplicate keys")
        }
    }

    /// "%@ · %ld" must not become "%ld · %@" without positions, or lose an argument.
    func testFormatSpecifiersMatchBetweenLocalizations() {
        let en = tables["en", default: [:]], zh = tables["zh-Hans", default: [:]]
        for (key, english) in en {
            guard let chinese = zh[key] else { continue }
            let source = Self.formatSpecifiers(in: key)
            XCTAssertEqual(Self.formatSpecifiers(in: english), source, "en value of \"\(key)\" changes the format arguments")
            XCTAssertEqual(Self.formatSpecifiers(in: chinese), source, "zh-Hans value of \"\(key)\" changes the format arguments")
        }
    }

    /// Every key must still be used: by a literal in the code, by ItemCatalog or by a known enum.
    func testNoOrphanedKeys() throws {
        let used = try Set(Self.scanSourceKeys().map(\.key)).union(Self.catalogKeys()).union(Self.enumKeys())
        let orphans = Set(tables["en", default: [:]].keys).subtracting(used).sorted()
        XCTAssertEqual(orphans, [], "Keys no longer used anywhere; remove them from both Localizable.strings files")
    }

    // MARK: 2. Item catalog

    func testCatalogTextIsLocalizedInBothLanguages() {
        assertLocalized(Self.catalogKeys(), what: "ItemCatalog text")
    }

    func testEnumLabelsAreLocalizedInBothLanguages() {
        assertLocalized(Self.enumKeys(), what: "enum label")
    }

    /// Catalog wording, field labels, help texts, units, choice labels, action names and triggers.
    private static func catalogKeys() -> Set<String> {
        var keys = Set(ItemCategory.allCases.map(\.rawValue))
        func add(_ fields: [FieldSpec]) {
            for field in fields {
                keys.insert(field.label)
                if let help = field.help { keys.insert(help) }
                switch field.kind {
                case let .number(_, unit): if let unit = unit { keys.insert(unit) }
                case let .choice(options): options.forEach { keys.insert("option." + $0) }
                default: break
                }
            }
        }
        for info in ItemCatalog.all {
            keys.insert(info.displayName)
            keys.insert(info.summary)
            add(info.fields)
        }
        add(ItemCatalog.commonFields)
        for action in ItemCatalog.actionTypes {
            keys.insert(action.displayName)
            add(action.fields)
        }
        ItemCatalog.actionTriggers.forEach { keys.insert(ItemCatalog.triggerTitleKey($0)) }
        return keys
    }

    /// Keys of enums shown through `L10n.tr` (language menu, zones, Control Strip modes, zoom).
    private static func enumKeys() -> Set<String> {
        var keys = Set(AppLanguage.allCases.map(\.titleKey))
        keys.formUnion(PresetAlign.allCases.map(\.titleKey))
        return keys
    }

    // MARK: 3. Localized literals in the app sources

    func testSourceLiteralsAreLocalizedInBothLanguages() throws {
        let found = try Self.scanSourceKeys()
        XCTAssertFalse(found.isEmpty, "The source scan found no localized literals; is the path right?")
        for localization in Self.localizations {
            let table = tables[localization, default: [:]]
            let missing = found.filter { table[$0.key] == nil }.map { "\($0.location): \"\($0.key)\"" }
            XCTAssertEqual(missing, [], "Missing in \(localization).lproj/Localizable.strings")
        }
    }

    /// `NSLocalizedString` reads Bundle.main, which keeps the launch language; it has to be given
    /// `bundle: L10n.bundle`, and a literal key so this test can check it.
    func testNSLocalizedStringUsesSwitchableBundle() throws {
        let call = try NSRegularExpression(pattern: #"NSLocalizedString\("#)
        let good = try NSRegularExpression(pattern: #"NSLocalizedString\(\s*"(?:[^"\\\n]|\\.)*"\s*,\s*bundle:\s*L10n\.bundle\s*,\s*comment:"#)
        var offenders: [String] = []
        for (file, text) in try Self.swiftSources() {
            let range = NSRange(text.startIndex..., in: text)
            let goodStarts = Set(good.matches(in: text, range: range).map(\.range.location))
            for match in call.matches(in: text, range: range) where !goodStarts.contains(match.range.location) {
                offenders.append("\(file):\(Self.line(of: match.range.location, in: text))")
            }
        }
        XCTAssertEqual(offenders, [], "Use NSLocalizedString(\"English key\", bundle: L10n.bundle, comment: \"…\")")
    }

    /// SwiftUI turns "Width \(w)" into the key "Width %lld"; that is easy to get wrong in the strings
    /// files. Use String(format: NSLocalizedString(…)) and pass the result instead.
    func testNoInterpolatedSwiftUILiterals() throws {
        let interpolated = try Self.scanSourceLiterals().filter { literal in
            literal.raw.contains("\\(") && !literal.raw.isPureInterpolation
        }
        XCTAssertEqual(interpolated.map { "\($0.location): \($0.raw)" }, [], "Interpolated localized literals")
    }

    func testSourceScannerFindsKnownCalls() throws {
        let keys = Set(try Self.scanSourceKeys().map(\.key))
        // One of each kind: NSLocalizedString, SwiftUI Text, Button, .help, Label, TextField.
        for key in ["Customize Touch Bar…", "Your Touch Bar is empty", "Reload", "Add an item", "Duplicate", "Search item types", "Language"] {
            XCTAssertTrue(keys.contains(key), "Scanner did not find \"\(key)\"")
        }
    }

    // MARK: 4. Language setting

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MTMRLocalizationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        L10n.configure()
        super.tearDown()
    }

    private var sourceResources: Bundle { Bundle(path: Self.appSources.path)! }

    func testStoredValueParsing() {
        XCTAssertEqual(AppLanguage(storedValue: nil), .system)
        XCTAssertEqual(AppLanguage(storedValue: "garbage"), .system)
        XCTAssertEqual(AppLanguage(storedValue: "system"), .system)
        XCTAssertEqual(AppLanguage(storedValue: "en"), .english)
        XCTAssertEqual(AppLanguage(storedValue: "zh-Hans"), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.allCases.map(\.rawValue), ["system", "en", "zh-Hans"])
        XCTAssertNil(AppLanguage.system.forcedLocalization)
    }

    func testEverySupportedLocalizationShipsStrings() {
        XCTAssertEqual(L10n.supportedLocalizations, Self.localizations)
        for language in AppLanguage.allCases {
            if let forced = language.forcedLocalization {
                XCTAssertTrue(FileManager.default.fileExists(atPath: Self.stringsURL(forced).path), "\(forced).lproj missing")
            }
        }
    }

    func testForcedLanguageWinsOverSystemOrder() {
        XCTAssertEqual(L10n.resolveLocalization(for: .english, systemLanguages: ["zh-Hans-CN"]), "en")
        XCTAssertEqual(L10n.resolveLocalization(for: .simplifiedChinese, systemLanguages: ["en-US"]), "zh-Hans")
        XCTAssertEqual(L10n.resolveLocalization(for: .simplifiedChinese, systemLanguages: []), "zh-Hans")
    }

    func testSystemLanguageResolution() {
        XCTAssertEqual(L10n.resolveLocalization(for: .system, systemLanguages: ["zh-Hans-CN", "en-CN"]), "zh-Hans")
        XCTAssertEqual(L10n.resolveLocalization(for: .system, systemLanguages: ["zh-CN"]), "zh-Hans")
        XCTAssertEqual(L10n.resolveLocalization(for: .system, systemLanguages: ["en-GB"]), "en")
        // Second preference is used when the first isn't shipped.
        XCTAssertEqual(L10n.resolveLocalization(for: .system, systemLanguages: ["fr-FR", "zh-Hans-CN"]), "zh-Hans")
    }

    func testFallbackToEnglish() {
        XCTAssertEqual(L10n.resolveLocalization(for: .system, systemLanguages: []), "en")
        XCTAssertEqual(L10n.resolveLocalization(for: .system, systemLanguages: ["fr-FR"]), "en")
        XCTAssertEqual(L10n.resolveLocalization(for: .system, systemLanguages: ["ja-JP", "de-DE"]), "en")
        // A forced language that isn't available falls back like "follow system".
        XCTAssertEqual(L10n.resolveLocalization(for: .simplifiedChinese, systemLanguages: ["en"], available: ["en"]), "en")
    }

    func testSetLanguagePersistsAndSyncsAppleLanguages() {
        L10n.configure(defaults: defaults, resources: sourceResources, systemLanguages: ["en-US"])
        XCTAssertEqual(L10n.language, .system)

        L10n.setLanguage(.simplifiedChinese)
        XCTAssertEqual(defaults.string(forKey: L10n.languageDefaultsKey), "zh-Hans")
        XCTAssertEqual(ownValue(L10n.appleLanguagesKey) as? [String], ["zh-Hans"])
        XCTAssertEqual(L10n.language, .simplifiedChinese)

        L10n.setLanguage(.english)
        XCTAssertEqual(ownValue(L10n.appleLanguagesKey) as? [String], ["en"])

        // Following the system again removes the override instead of writing the system order.
        L10n.setLanguage(.system)
        XCTAssertEqual(defaults.string(forKey: L10n.languageDefaultsKey), "system")
        XCTAssertNil(ownValue(L10n.appleLanguagesKey))
        XCTAssertEqual(L10n.localization, "en")
    }

    func testSwitchingChangesLookupsImmediately() throws {
        let zh = try XCTUnwrap(tables["zh-Hans"]?["Save"])
        L10n.configure(defaults: defaults, resources: sourceResources, systemLanguages: ["en-US"])
        XCTAssertEqual(L10n.tr("Save"), "Save")

        L10n.setLanguage(.simplifiedChinese)
        XCTAssertEqual(L10n.localization, "zh-Hans")
        XCTAssertEqual(L10n.locale.identifier, "zh-Hans")
        XCTAssertEqual(L10n.tr("Save"), zh)
        XCTAssertEqual(NSLocalizedString("Save", bundle: L10n.bundle, comment: ""), zh)
        XCTAssertEqual(L10n.option("metric"), tables["zh-Hans"]?["option.metric"])
        XCTAssertEqual(PresetAlign.left.title, tables["zh-Hans"]?["Left"])
        XCTAssertEqual(ItemCatalog.localizedTriggerTitle("doubleTap"), tables["zh-Hans"]?["Double Tap"])

        L10n.setLanguage(.english)
        XCTAssertEqual(L10n.tr("Save"), "Save")
        XCTAssertEqual(PresetAlign.left.title, "Left")
    }

    func testSystemModeFollowsSystemOrder() {
        L10n.configure(defaults: defaults, resources: sourceResources, systemLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(L10n.language, .system)
        XCTAssertEqual(L10n.localization, "zh-Hans")
        XCTAssertEqual(L10n.tr("Quit"), tables["zh-Hans"]?["Quit"])

        L10n.setLanguage(.english)
        XCTAssertEqual(L10n.tr("Quit"), "Quit")
        L10n.setLanguage(.system)
        XCTAssertEqual(L10n.tr("Quit"), tables["zh-Hans"]?["Quit"])
    }

    func testStoredLanguageIsReadOnLaunch() {
        defaults.set("zh-Hans", forKey: L10n.languageDefaultsKey)
        L10n.configure(defaults: defaults, resources: sourceResources, systemLanguages: ["en-US"])
        XCTAssertEqual(L10n.language, .simplifiedChinese)
        XCTAssertEqual(L10n.localization, "zh-Hans")
    }

    func testMissingKeysAndMissingStringsFallBackToEnglishKey() {
        L10n.configure(defaults: defaults, resources: sourceResources, systemLanguages: ["en-US"])
        L10n.setLanguage(.simplifiedChinese)
        XCTAssertEqual(L10n.tr("No such key 4711"), "No such key 4711")
        XCTAssertEqual(L10n.option("handWritten"), "handWritten")

        // A bundle without lproj folders (the unit-test runner) shows the English keys.
        L10n.configure(defaults: defaults, resources: Bundle(for: LocalizationTests.self), systemLanguages: ["zh-Hans-CN"])
        XCTAssertEqual(L10n.tr("Save"), "Save")
    }

    func testSetLanguagePostsChangeNotification() {
        L10n.configure(defaults: defaults, resources: sourceResources, systemLanguages: ["en-US"])
        let posted = expectation(forNotification: L10n.languageDidChange, object: nil)
        L10n.setLanguage(.simplifiedChinese)
        wait(for: [posted], timeout: 1)
    }

    private func ownValue(_ key: String) -> Any? {
        // `object(forKey:)` would fall through to the global domain once the override is removed.
        defaults.persistentDomain(forName: suiteName)?[key]
    }

    // MARK: Helpers

    private func assertLocalized(_ keys: Set<String>, what: String, file: StaticString = #filePath, line: UInt = #line) {
        for localization in Self.localizations {
            let table = tables[localization, default: [:]]
            let missing = keys.filter { table[$0] == nil }.sorted()
            XCTAssertEqual(missing, [], "\(what) missing in \(localization).lproj/Localizable.strings", file: file, line: line)
        }
    }

    private struct SourceLiteral {
        let raw: String
        let location: String
        var key: String { raw.unescapedSwiftLiteral }
    }

    /// Calls whose first argument is a localization key: Foundation / L10n, SwiftUI initializers that
    /// take a `LocalizedStringKey` and view modifiers that do. `Text(verbatim:)` and variables are skipped.
    private static let literalPattern: NSRegularExpression = {
        let initializers = ["Text", "Button", "Label", "Toggle", "Picker", "Menu", "TextField", "SecureField",
                            "ColorPicker", "Section", "Link", "GroupBox", "DisclosureGroup", "LabeledContent"]
        let modifiers = ["help", "accessibilityLabel", "accessibilityHint", "accessibilityValue", "navigationTitle",
                         "confirmationDialog", "alert"]
        let callees = ["NSLocalizedString", #"L10n\.tr"#]
            + initializers.map { #"(?<![\w.])"# + $0 }
            + modifiers.map { #"\."# + $0 }
        let pattern = "(?:" + callees.joined(separator: "|") + #")\(\s*"((?:[^"\\\n]|\\.)*)""#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static func swiftSources() throws -> [(String, String)] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil))
        var result: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            // Blank out comment lines (keeping line numbers) so examples in comments aren't scanned.
            let code = text.components(separatedBy: "\n").map {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : $0
            }.joined(separator: "\n")
            result.append((url.path.replacingOccurrences(of: repoRoot.path + "/", with: ""), code))
        }
        return result.sorted { $0.0 < $1.0 }
    }

    private static func scanSourceLiterals() throws -> [SourceLiteral] {
        var result: [SourceLiteral] = []
        for (file, text) in try swiftSources() {
            for match in literalPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let raw = String(text[Range(match.range(at: 1), in: text)!])
                result.append(SourceLiteral(raw: raw, location: "\(file):\(line(of: match.range.location, in: text))"))
            }
        }
        return result
    }

    /// Literals that are looked up as keys: not empty, not a pure interpolation like "\(count)".
    private static func scanSourceKeys() throws -> [SourceLiteral] {
        try scanSourceLiterals().filter { !$0.raw.isEmpty && !$0.raw.isPureInterpolation }
    }

    private static func line(of utf16Offset: Int, in text: String) -> Int {
        let prefix = (text as NSString).substring(to: utf16Offset)
        return prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// printf-style specifiers ("%@", "%ld", "%1$@"), sorted so positional reordering is allowed.
    private static func formatSpecifiers(in text: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@dDiuUxXoOfeEgGcCsSpaA%])"#)
        var result: [String] = []
        var index = 0
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let conversion = String(text[Range(match.range(at: 3), in: text)!])
            if conversion == "%" { continue }
            index += 1
            let position = Range(match.range(at: 1), in: text).map { Int(text[$0])! } ?? index
            let length = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            result.append("\(position):\(length)\(conversion)")
        }
        return result.sorted()
    }
}

private extension String {
    /// Interpolated values separated only by punctuation have no words to translate.
    var isPureInterpolation: Bool {
        guard contains("\\(") else { return false }
        let words = replacingOccurrences(of: #"\\\([^()]*(\([^()]*\))?[^()]*\)"#,
                                         with: "", options: .regularExpression)
        return words.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.punctuationCharacters.contains($0)
        }
    }

    /// The runtime value of a Swift string literal body (the key stored in Localizable.strings).
    var unescapedSwiftLiteral: String {
        var result = ""
        var iterator = makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let escaped = iterator.next() else {
                result.append(character)
                continue
            }
            switch escaped {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            case "0": result.append("\0")
            case "u":
                // \u{XXXX}
                var hex = ""
                _ = iterator.next() // "{"
                while let h = iterator.next(), h != "}" { hex.append(h) }
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) { result.unicodeScalars.append(scalar) }
            default: result.append(escaped) // \" \\ \'
            }
        }
        return result
    }
}
