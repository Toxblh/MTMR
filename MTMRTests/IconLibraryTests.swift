import AppKit
import XCTest

final class IconLibraryTests: XCTestCase {
    // #filePath is MTMRTests/IconLibraryTests.swift; the repository root is two levels up.
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let iconsDirectory = root.appendingPathComponent("Resources/Icons")

    private struct ManifestEntry: Decodable { let name: String; let title: String; let category: String }

    private func manifest() throws -> [ManifestEntry] {
        try JSONDecoder().decode([ManifestEntry].self, from: Data(contentsOf: Self.iconsDirectory.appendingPathComponent("manifest.json")))
    }

    private func svgExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: Self.iconsDirectory.appendingPathComponent(name + ".svg").path)
    }

    /// The unit-test process has no app bundle, so icons are loaded from Resources/Icons/*.svg instead.
    /// Images are cached so tests can compare identity.
    private var cache: [String: NSImage] = [:]
    private var savedLoader: ((String) -> NSImage?)!

    override func setUp() {
        savedLoader = IconLibrary.loader
        IconLibrary.loader = { [unowned self] name in
            if let hit = self.cache[name] { return hit }
            guard let image = NSImage(contentsOf: Self.iconsDirectory.appendingPathComponent(name + ".svg")) else { return nil }
            self.cache[name] = image
            return image
        }
    }

    override func tearDown() {
        IconLibrary.loader = savedLoader
    }

    // MARK: list <-> manifest <-> files

    func testSwiftListMatchesManifest() throws {
        let entries = try manifest()
        XCTAssertEqual(IconLibrary.all.map(\.name), entries.map(\.name))
        XCTAssertEqual(IconLibrary.all.map(\.title), entries.map(\.title))
        XCTAssertEqual(IconLibrary.all.map(\.category.rawValue), entries.map(\.category))
        XCTAssertEqual(Set(IconLibrary.all.map(\.name)).count, IconLibrary.all.count, "duplicate icon names")
    }

    /// Reports (does not fail) while icons are still being drawn; testAllManifestSVGsExist is the strict variant.
    func testMissingSVGsAreReported() throws {
        let missing = try manifest().map(\.name).filter { !svgExists($0) }
        if !missing.isEmpty { print("IconLibraryTests: \(missing.count) SVG(s) missing: \(missing.joined(separator: ", "))") }
    }

    /// Expected to fail until every designed SVG is merged into Resources/Icons.
    func testAllManifestSVGsExist() throws {
        let missing = try manifest().map(\.name).filter { !svgExists($0) }
        XCTAssertTrue(missing.isEmpty, "missing SVGs: \(missing.joined(separator: ", "))")
    }

    func testEveryBuiltInDefaultIconIsInTheManifest() {
        for (type, icon) in IconLibrary.builtInDefaults {
            XCTAssertNotNil(IconLibrary.info(for: icon), "default icon \(icon) of \(type) is not in the manifest")
        }
        // Names used directly by widgets.
        for icon in ["bolt", "hourglass", "dnd-on", "dnd-off", "dark-mode-on", "dark-mode-off", "night-shift-on", "night-shift-off", "sidecar-on", "sidecar-off", "eject"] {
            XCTAssertNotNil(IconLibrary.info(for: icon), icon)
        }
    }

    func testEveryBuiltInTypeWithADefaultIsACatalogType() {
        for type in IconLibrary.builtInDefaults.keys {
            XCTAssertNotNil(ItemCatalog.info(for: type), "\(type) is not a customizer item type")
        }
    }

    func testWeatherMappingsReferenceManifestIcons() {
        let codes = ["01d", "01n", "02d", "02n", "03d", "04n", "09d", "10n", "11d", "13n", "50d"]
        for code in codes {
            guard let name = IconLibrary.weatherIcon(openWeatherCode: code) else { return XCTFail(code) }
            XCTAssertNotNil(IconLibrary.info(for: name), name)
        }
        XCTAssertEqual(IconLibrary.weatherIcon(openWeatherCode: "01n"), "weather-clear-night")
        XCTAssertNil(IconLibrary.weatherIcon(openWeatherCode: "99d"))
        let conditions = ["clear", "mostly-clear", "partly-cloudy", "overcast", "cloudy", "light-rain", "drizzle", "rain", "heavy-rain",
                          "storm", "thunderstorm-with-rain", "sleet", "light-snow", "snow", "fog"]
        for condition in conditions {
            guard let name = IconLibrary.weatherIcon(yandexCondition: condition) else { return XCTFail(condition) }
            XCTAssertNotNil(IconLibrary.info(for: name), name)
        }
        XCTAssertNil(IconLibrary.weatherIcon(yandexCondition: "unknown"))
    }

    // MARK: loading

    func testImageIsTemplateAndUnknownNamesGiveNil() {
        let image = IconLibrary.image(named: "brightness-up")
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.isTemplate, true)
        XCTAssertNil(IconLibrary.image(named: "no-such-icon"))
        XCTAssertNil(IconLibrary.image(named: "../brightness-up"), "only manifest names are accepted")
    }

    func testFallbackIsUsedOnlyWhenTheIconIsMissing() {
        let fallback = NSImage(size: NSSize(width: 1, height: 1))
        XCTAssertTrue(IconLibrary.image(named: "brightness-up", fallback: fallback) !== fallback)
        // "sleep" is in the manifest but may not be drawn yet; either way the result must not be nil.
        XCTAssertNotNil(IconLibrary.image(named: "sleep", fallback: fallback))
        XCTAssertTrue(IconLibrary.image(named: "no-such-icon", fallback: fallback) === fallback)
    }

    func testInlineIconIsATintedAttachmentOrNil() throws {
        let font = NSFont.systemFont(ofSize: 15)
        let inline = try XCTUnwrap(IconLibrary.inlineIcon("brightness-up", color: .red, font: font))
        let attachment = try XCTUnwrap(inline.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(attachment.image?.isTemplate, false, "the attachment image carries its colour")
        XCTAssertGreaterThan(attachment.bounds.width, 0)
        XCTAssertNil(IconLibrary.inlineIcon("no-such-icon", color: .white, font: font))
    }

    // MARK: JSON "image": {"icon": ...}

    private func decode(_ json: String) throws -> BarItemDefinition {
        try JSONDecoder().decode([BarItemDefinition].self, from: Data(("[" + json + "]").utf8))[0]
    }

    private func image(of definition: BarItemDefinition) -> NSImage? {
        if case let .image(source)? = definition.additionalParameters[.image] { return source.image }
        return nil
    }

    func testIconSourceDecodes() throws {
        let item = try decode(#"{"type":"staticButton","title":"x","image":{"icon":"brightness-up"}}"#)
        XCTAssertTrue(image(of: item) === cache["brightness-up"])
        XCTAssertEqual(image(of: item)?.isTemplate, true)
    }

    func testUnknownIconNameGivesNilImage() throws {
        let item = try decode(#"{"type":"staticButton","title":"x","image":{"icon":"nope"}}"#)
        guard case .image? = item.additionalParameters[.image] else { return XCTFail("image parameter missing") }
        XCTAssertNil(image(of: item))
    }

    func testOldImageFormsStillWork() throws {
        // 1x1 transparent PNG
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        let embedded = try decode(#"{"type":"staticButton","title":"x","image":{"base64":"\#(png)"}}"#)
        XCTAssertNotNil(image(of: embedded))
        let path = try decode(#"{"type":"staticButton","title":"x","image":{"filePath":"/no/such/file.png"}}"#)
        XCTAssertNil(image(of: path))
    }

    func testDefaultIconAndUserImageOverride() throws {
        let plain = try decode(#"{"type":"volumeUp"}"#)
        XCTAssertTrue(image(of: plain) === cache["volume-up"], "built-in default icon")
        let overridden = try decode(#"{"type":"volumeUp","image":{"icon":"brightness-up"}}"#)
        XCTAssertTrue(image(of: overridden) === cache["brightness-up"], "an \"image\" in the preset replaces the default icon")
    }

    func testMissingDefaultIconFallsBackToTitleForTextButtons() throws {
        // Keep setUp's disk loader: `savedLoader` is the app's asset-catalog loader, which finds nothing in
        // the xctest process, so restoring it would make the "with icon" check below see the fallback.
        let diskLoader = IconLibrary.loader
        IconLibrary.loader = { _ in nil }
        XCTAssertEqual(try titleOf(decode(#"{"type":"sleep"}"#)), "☕️")
        XCTAssertEqual(try titleOf(decode(#"{"type":"delete"}"#)), "del")
        IconLibrary.loader = diskLoader
        let withIcon = try decode(#"{"type":"delete"}"#)
        if svgExists("delete") {
            XCTAssertEqual(titleOf(withIcon), "")
        }
    }

    private func titleOf(_ definition: BarItemDefinition) -> String? {
        if case let .staticButton(title) = definition.type { return title }
        return nil
    }

    // MARK: Resources/Icons/build-assets.py

    private func run(_ script: URL, _ arguments: [String] = []) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-I", script.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { throw XCTSkip("python3 is not available: \(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func testBuildAssetsScriptOutputFormat() throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.appendingPathComponent("MTMRIconTests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: sandbox) }
        let icons = sandbox.appendingPathComponent("Resources/Icons")
        try fm.createDirectory(at: icons, withIntermediateDirectories: true)
        let script = icons.appendingPathComponent("build-assets.py")
        try fm.copyItem(at: Self.iconsDirectory.appendingPathComponent("build-assets.py"), to: script)
        let svg = try String(contentsOf: Self.iconsDirectory.appendingPathComponent("brightness-up.svg"))
        try svg.write(to: icons.appendingPathComponent("a.svg"), atomically: true, encoding: .utf8)
        try svg.write(to: icons.appendingPathComponent("b.svg"), atomically: true, encoding: .utf8)
        func writeManifest(_ names: [String]) throws {
            let entries = names.map { #"{"name":"\#($0)","title":"T","category":"System"}"# }
            try ("[" + entries.joined(separator: ",") + "]").write(to: icons.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        }
        try writeManifest(["a", "b", "c"])

        let catalog = sandbox.appendingPathComponent("MTMR/Assets.xcassets/Icons")
        let first = try run(script)
        XCTAssertEqual(first.status, 0, first.output)
        XCTAssertTrue(first.output.contains("2 of 3 icons"), first.output)
        XCTAssertTrue(first.output.contains("1 missing SVG(s): c"), first.output)

        let folder = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog.appendingPathComponent("Contents.json"))) as? [String: Any]
        XCTAssertEqual((folder?["properties"] as? [String: Any])?["provides-namespace"] as? Bool, true)
        let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog.appendingPathComponent("a.imageset/Contents.json"))) as? [String: Any]
        let properties = contents?["properties"] as? [String: Any]
        XCTAssertEqual(properties?["template-rendering-intent"] as? String, "template")
        XCTAssertEqual(properties?["preserves-vector-representation"] as? Bool, true)
        let images = contents?["images"] as? [[String: Any]]
        XCTAssertEqual(images?.first?["filename"] as? String, "a.svg")
        XCTAssertEqual(images?.first?["idiom"] as? String, "universal")
        XCTAssertEqual(try String(contentsOf: catalog.appendingPathComponent("a.imageset/a.svg")), svg)
        XCTAssertFalse(fm.fileExists(atPath: catalog.appendingPathComponent("c.imageset").path))

        // Idempotent.
        let second = try run(script)
        XCTAssertTrue(second.output.contains("0 change(s)"), second.output)
        XCTAssertEqual(try run(script, ["--check"]).status, 0)

        // Icons that left the manifest lose their imageset; AppleDouble files are ignored.
        try fm.createDirectory(at: catalog.appendingPathComponent("stale.imageset"), withIntermediateDirectories: true)
        try writeManifest(["a", "c"])
        XCTAssertEqual(try run(script, ["--check"]).status, 1)
        _ = try run(script)
        XCTAssertFalse(fm.fileExists(atPath: catalog.appendingPathComponent("b.imageset").path))
        XCTAssertFalse(fm.fileExists(atPath: catalog.appendingPathComponent("stale.imageset").path))
        XCTAssertTrue(fm.fileExists(atPath: catalog.appendingPathComponent("a.imageset").path))
    }

    /// Fails when an SVG was added or changed without re-running build-assets.py.
    func testCommittedCatalogIsUpToDate() throws {
        let result = try run(Self.iconsDirectory.appendingPathComponent("build-assets.py"), ["--check"])
        XCTAssertEqual(result.status, 0, "run `python3 -I Resources/Icons/build-assets.py`:\n" + result.output)
    }
}
