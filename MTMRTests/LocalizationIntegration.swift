import SwiftUI

@main @MainActor
private enum LocalizationIntegration {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static var presets: URL {
        URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    }

    static func main() async throws {
        _ = NSApplication.shared
        let suite = "local.MTMR.CustomizerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        L10n.configure(defaults: defaults, resources: .main, systemLanguages: ["en"])
        defer { defaults.removePersistentDomain(forName: suite) }

        try await languageChange()
        print("Localization integration: language changes preserved the JSON draft and selection")
    }

    private static func check(_ condition: @autoclosure () throws -> Bool,
                              line: UInt = #line) throws {
        guard try condition() else { throw Failure(description: "assertion failed at line \(line)") }
    }

    private static func require<T>(_ value: T?, line: UInt = #line) throws -> T {
        guard let value else { throw Failure(description: "missing value at line \(line)") }
        return value
    }

    private static func preset(_ name: String, _ contents: String) throws -> URL {
        let url = presets.appendingPathComponent(name + ".json")
        try Data(contents.utf8).write(to: url)
        return url
    }

    private static func refresh(_ window: NSWindow) async throws {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private static func languageChange() async throws {
        let url = try preset("language", #"[{"type":"staticButton","title":"Language fixture"}]"#)
        let document = PresetDocument(fileURL: url)
        document.load()
        let state = CustomizerState()
        let controller = CustomizerWindowController(preset: document, state: state)
        defer {
            controller.close()
            L10n.setLanguage(.english)
        }
        let window = try require(controller.window)
        window.setFrameAutosaveName("")
        window.alphaValue = 0
        window.orderBack(nil)
        state.selection = document.items.first?.id
        state.advancedExpanded = true
        try await refresh(window)
        var customFrame = window.frame
        customFrame.size.width += 94
        customFrame.size.height += 36
        window.setFrame(customFrame, display: true)
        let savedFrame = window.frame
        let editor = try require(descendants(of: window.contentView).compactMap { $0 as? NSTextView }
            .first { $0.string.contains("Language fixture") && $0.string.contains("\"staticButton\"") })
        let draft = #"{ "type": "staticButton", "title": "未完成"#
        editor.insertText(draft, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        try check(state.advancedDraft == draft)

        for (language, title) in [(AppLanguage.simplifiedChinese, "自定触控栏"), (.english, "Customize Touch Bar")] {
            let previous = window.contentViewController
            L10n.setLanguage(language)
            try await refresh(window)
            try check(window.contentViewController !== previous && window.title == title)
            try check(window.frame == savedFrame)
            try check(state.advancedDraft == draft && state.selection == document.items.first?.id)
            try check(descendants(of: window.contentView).compactMap { $0 as? NSTextView }.contains { $0.string == draft })
            try check(!document.isDirty && document.items.first?.listTitle == "Language fixture")
        }
    }

    private static func descendants(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
