import XCTest

final class PresetDocumentTests: XCTestCase {
    private var directory: URL!

    /// The built-in types below load images (`#imageLiteral` from the app's asset catalog, or
    /// `NSImage(named:)!`) while decoding. The xctest process has neither, so decoding them traps.
    /// Registering image-less stand-ins keeps the decoding path testable; "exitTouchbar" and "close"
    /// are normally registered by TouchBarController, which does not exist in this process.
    private static let registerStubs: Void = {
        let names = ["brightnessUp", "brightnessDown", "illuminationUp", "illuminationDown", "volumeDown", "volumeUp",
                     "mute", "previous", "play", "next", "exitTouchbar", "close"]
        for name in names {
            SupportedTypesHolder.sharedInstance.register(typename: name, item: .staticButton(title: ""), actions: [], legacyAction: .none, legacyLongAction: .none)
        }
    }()

    override func setUpWithError() throws {
        _ = PresetDocumentTests.registerStubs
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("MTMRTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL { directory.appendingPathComponent("items.json") }
    private var backupURL: URL { directory.appendingPathComponent("items.backup.json") }

    private func write(_ text: String) throws { try text.write(to: fileURL, atomically: true, encoding: .utf8) }

    private func document(_ text: String) throws -> PresetDocument {
        try write(text)
        let document = PresetDocument(fileURL: fileURL)
        document.load()
        XCTAssertNil(document.loadError)
        return document
    }

    private func types(_ items: [PresetItem]) -> [String] { items.map(\.type) }

    private let sample = """
    [
      { "type": "escape", "align": "left" },
      { "type": "play", "align": "right" },
      { "type": "swipe", "fingers": 3, "direction": "left" },
      { "type": "mute", "align": "left" },
      { "type": "battery" },
      { "type": "cpu", "align": "right" }
    ]
    """

    private let groupSample = """
    [
      { "type": "play" },
      { "type": "group", "title": "g", "items": [ { "type": "mute" }, { "type": "volumeUp" } ], "align": "left" }
    ]
    """

    // MARK: Load

    func testLoadSetsItemsAndStaysClean() throws {
        let doc = try document(sample)
        XCTAssertEqual(types(doc.items), ["escape", "play", "swipe", "mute", "battery", "cpu"])
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(types(doc.items(in: .left)), ["escape", "mute"])
        XCTAssertEqual(types(doc.items(in: .center)), ["battery"]) // missing align == center
        XCTAssertEqual(types(doc.items(in: .right)), ["play", "cpu"])
        XCTAssertEqual(types(doc.gestures), ["swipe"])
    }

    func testLoadAcceptsCommentsAndTrailingCommas() throws {
        let doc = try document("// my preset\n[ { \"type\": \"escape\", }, /* x */ ]")
        XCTAssertEqual(types(doc.items), ["escape"])
    }

    func testLoadErrors() throws {
        let missing = PresetDocument(fileURL: directory.appendingPathComponent("nope.json"))
        missing.load()
        XCTAssertNotNil(missing.loadError)
        XCTAssertTrue(missing.items.isEmpty)
        XCTAssertFalse(missing.isDirty)

        for bad in ["{}", "[1, 2]", "[{\"type\": \"a\"}, \"x\"]", "[{", "", "[{\"type\":\"group\",\"items\":5}]"] {
            try write(bad)
            let doc = PresetDocument(fileURL: fileURL)
            doc.load()
            XCTAssertNotNil(doc.loadError, bad)
            XCTAssertTrue(doc.items.isEmpty, bad)
            XCTAssertFalse(doc.isDirty, bad)
        }
        XCTAssertTrue(try document("[{\"type\":\"a\"}]").loadError == nil)
    }

    func testLoadClearsPreviousError() throws {
        try write("nonsense")
        let doc = PresetDocument(fileURL: fileURL)
        doc.load()
        XCTAssertNotNil(doc.loadError)
        try write(sample)
        doc.load()
        XCTAssertNil(doc.loadError)
        XCTAssertEqual(doc.items.count, 6)
    }

    func testGroupChildrenAreLifted() throws {
        let doc = try document(groupSample)
        let group = try XCTUnwrap(doc.items.last)
        XCTAssertNil(group.json["items"])
        XCTAssertEqual(types(group.children ?? []), ["mute", "volumeUp"])
        XCTAssertNil(doc.items[0].children)
        let child = try XCTUnwrap(group.children?.first)
        XCTAssertEqual(doc.item(withID: child.id)?.type, "mute")
    }

    func testGroupRoundTripKeepsKeyOrder() throws {
        let doc = try document(groupSample)
        let reparsed = try JSONValue.parse(doc.serializedText())
        let group = try XCTUnwrap(reparsed.arrayValue?.last?.objectValue)
        XCTAssertEqual(group.keys, ["type", "title", "items", "align"])
        XCTAssertEqual(group["items"]?.arrayValue?.count, 2)
    }

    func testUnknownKeysAreKept() throws {
        let doc = try document(#"[{"type": "escape", "futureKey": {"a": [1, 2.0]}}]"#)
        XCTAssertTrue(doc.serializedText().contains("futureKey"))
        XCTAssertEqual(try JSONValue.parse(doc.serializedText()), try JSONValue.parse(#"[{"type": "escape", "futureKey": {"a": [1, 2.0]}}]"#))
    }

    // MARK: Validate and save

    func testValidateAcceptsValidAndRejectsBroken() throws {
        let doc = try document(sample)
        XCTAssertNil(doc.validate())

        var broken = try XCTUnwrap(doc.items.first)
        broken.json["width"] = .string("wide") // GeneralParameters expects a number
        doc.update(broken)
        XCTAssertNotNil(doc.validate())
    }

    func testValidateReportsMissingRequiredKeyOfSwipe() throws {
        // The app's decoder would silently show "unknown" for this; validate() must not.
        let doc = try document(#"[{"type": "swipe", "direction": "left"}]"#)
        let message = try XCTUnwrap(doc.validate())
        XCTAssertTrue(message.contains("fingers"), message)
    }

    func testValidateChecksGroupChildren() throws {
        let doc = try document(#"[{"type": "group", "items": [{"type": "staticButton"}]}]"#)
        let message = try XCTUnwrap(doc.validate())
        XCTAssertTrue(message.contains("title"), message)
    }

    func testValidateDoesNotTrapWithoutType() throws {
        let doc = try document(#"[{"align": "left"}]"#)
        XCTAssertNotNil(doc.validate())
    }

    func testSaveWritesInPlaceKeepingInode() throws {
        let doc = try document(sample)
        let before = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.systemFileNumber] as? Int
        doc.add(type: "cpu", align: .left)
        XCTAssertTrue(doc.isDirty)
        try doc.save()
        XCTAssertFalse(doc.isDirty)
        let after = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.systemFileNumber] as? Int
        XCTAssertNotNil(before)
        XCTAssertEqual(before, after)
        XCTAssertEqual(try String(contentsOf: fileURL), doc.serializedText())

        // Shrinking must also keep the inode and leave no stale tail.
        let first = try XCTUnwrap(doc.items.first)
        doc.remove(id: first.id)
        doc.remove(id: try XCTUnwrap(doc.items.first).id)
        try doc.save()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: fileURL.path)[.systemFileNumber] as? Int, before)
        XCTAssertEqual(try String(contentsOf: fileURL), doc.serializedText())
        XCTAssertNoThrow(try JSONValue.parse(try String(contentsOf: fileURL)))
    }

    func testSaveCreatesMissingFileAndDirectory() throws {
        let nested = directory.appendingPathComponent("a/b/items.json")
        let doc = PresetDocument(fileURL: nested)
        doc.load()
        XCTAssertNotNil(doc.loadError)
        doc.add(type: "escape", align: .left)
        try doc.save()
        XCTAssertEqual(try JSONValue.parse(String(contentsOf: nested)).arrayValue?.count, 1)
        XCTAssertFalse(doc.isDirty)
    }

    func testInvalidPresetIsNotWritten() throws {
        let doc = try document(sample)
        let original = try String(contentsOf: fileURL)
        var broken = try XCTUnwrap(doc.items.first)
        broken.json["width"] = .string("wide")
        doc.update(broken)
        XCTAssertThrowsError(try doc.save())
        XCTAssertEqual(try String(contentsOf: fileURL), original)
        XCTAssertTrue(doc.isDirty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func testBackupOnlyWhenCommentsAndOnlyOnce() throws {
        // No comments -> no backup.
        let plain = try document(sample)
        plain.add(type: "mute", align: .left)
        try plain.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))

        // Comments -> backup holds the original text.
        let commented = "// keep me\n[ { \"type\": \"escape\" } /* x */ ]\n"
        let doc = try document(commented)
        doc.add(type: "mute", align: .left)
        try doc.save()
        XCTAssertEqual(try String(contentsOf: backupURL), commented)
        XCTAssertFalse(JSONValue.containsComments(try String(contentsOf: fileURL)))

        // A second save (file now without comments) and even a new comment never overwrite the backup.
        try write("// other comment\n[ { \"type\": \"play\" } ]\n")
        doc.load()
        doc.add(type: "mute", align: .left)
        try doc.save()
        XCTAssertEqual(try String(contentsOf: backupURL), commented)
    }

    func testOnSavedCalledOnMainQueue() throws {
        let doc = try document(sample)
        let called = expectation(description: "onSaved")
        doc.onSaved = {
            XCTAssertTrue(Thread.isMainThread)
            called.fulfill()
        }
        doc.add(type: "mute", align: .left)
        try doc.save()
        wait(for: [called], timeout: 2)
    }

    // MARK: isDirty

    func testDirtyTransitions() throws {
        let doc = try document(sample)
        XCTAssertFalse(doc.isDirty)
        let id = doc.add(type: "mute", align: .right)
        XCTAssertTrue(doc.isDirty)
        try doc.save()
        XCTAssertFalse(doc.isDirty)
        doc.remove(id: id)
        XCTAssertTrue(doc.isDirty)
        doc.revert()
        XCTAssertFalse(doc.isDirty)
        XCTAssertEqual(doc.items.count, 7) // revert reloads the saved file, which includes the added item

        var item = try XCTUnwrap(doc.items.first)
        item.align = .right
        doc.update(item)
        XCTAssertTrue(doc.isDirty)
        doc.load()

        let group = try document(groupSample)
        let child = try XCTUnwrap(group.items.last?.children?.first)
        var edited = child
        edited.json["width"] = .int(90)
        group.update(edited) // nested edit must mark dirty too
        XCTAssertTrue(group.isDirty)
        XCTAssertEqual(group.item(withID: child.id)?.json["width"], .int(90))
    }

    func testNoOpMoveDoesNotMarkDirty() throws {
        let doc = try document(sample)
        doc.move(in: .left, from: IndexSet(integer: 0), to: 1) // List.onMove: moving to own slot
        doc.move(in: .left, from: IndexSet(integer: 0), to: 0)
        XCTAssertFalse(doc.isDirty)
    }

    // MARK: Editing

    func testAddUsesCatalogDefaultsAndAlign() throws {
        let doc = try document(sample)
        let id = doc.add(type: "timeButton", align: .right)
        let item = try XCTUnwrap(doc.item(withID: id))
        XCTAssertEqual(item.json["type"], .string("timeButton"))
        XCTAssertEqual(item.align, .right)
        XCTAssertEqual(doc.items.last?.id, id)
        XCTAssertEqual(types(doc.items(in: .right)).last, "timeButton")

        let unknown = doc.add(type: "futureType", align: .left)
        XCTAssertEqual(doc.item(withID: unknown)?.json, JSONObject(pairs: [("type", .string("futureType")), ("align", .string("left"))]))

        let swipe = doc.add(type: "swipe", align: .left)
        XCTAssertNil(doc.item(withID: swipe)?.json["align"])
        XCTAssertTrue(doc.gestures.contains { $0.id == swipe })
    }

    func testAddGroupAndAddIntoGroup() throws {
        let doc = try document("[]")
        let groupID = doc.add(type: "group", align: .center)
        let group = try XCTUnwrap(doc.item(withID: groupID))
        XCTAssertEqual(group.children?.count, 0)
        XCTAssertNil(group.json["items"])

        let child = doc.add(type: "play", align: .left, intoGroup: groupID)
        XCTAssertNil(doc.item(withID: child)?.json["align"], "children do not get an alignment")
        XCTAssertEqual(doc.items.count, 1)
        XCTAssertEqual(doc.item(withID: groupID)?.children?.map(\.id), [child])

        // Unknown or non-group parent falls back to the top level.
        let orphan = doc.add(type: "mute", align: .left, intoGroup: UUID())
        XCTAssertEqual(doc.items.last?.id, orphan)
        let notAGroup = doc.add(type: "mute", align: .left, intoGroup: orphan)
        XCTAssertEqual(doc.items.last?.id, notAGroup)

        XCTAssertNil(doc.validate())
        XCTAssertEqual(try JSONValue.parse(doc.serializedText()).arrayValue?.first?.objectValue?["items"]?.arrayValue?.count, 1)
    }

    func testRemoveNested() throws {
        let doc = try document(groupSample)
        let child = try XCTUnwrap(doc.items.last?.children?.first)
        doc.remove(id: child.id)
        XCTAssertNil(doc.item(withID: child.id))
        XCTAssertEqual(doc.items.last?.children?.count, 1)
        doc.remove(id: UUID()) // unknown id: no-op
        XCTAssertEqual(doc.items.count, 2)
    }

    func testDuplicateInsertsRightAfterWithFreshIDs() throws {
        let doc = try document(groupSample)
        let group = try XCTUnwrap(doc.items.last)
        let copyID = try XCTUnwrap(doc.duplicate(id: group.id))
        XCTAssertEqual(doc.items.count, 3)
        XCTAssertEqual(doc.items[2].id, copyID)
        let copy = doc.items[2]
        XCTAssertEqual(copy.json, group.json)
        XCTAssertEqual(types(copy.children ?? []), ["mute", "volumeUp"])
        let allIDs = (doc.items + doc.items.flatMap { $0.children ?? [] }).map(\.id)
        XCTAssertEqual(Set(allIDs).count, allIDs.count, "ids must be unique after duplicating")

        // Duplicate inside a group stays inside that group, right after the original.
        let inner = try XCTUnwrap(group.children?.first)
        let innerCopy = try XCTUnwrap(doc.duplicate(id: inner.id))
        XCTAssertEqual(doc.items[1].children?.map(\.id).count, 3)
        XCTAssertEqual(doc.items[1].children?[1].id, innerCopy)
        XCTAssertNil(doc.duplicate(id: UUID()))
        XCTAssertEqual(doc.serializedText().components(separatedBy: "\"mute\"").count - 1, 3)
    }

    func testMoveWithinZoneLeavesOthersAlone() throws {
        let doc = try document("""
        [
          {"type": "a1", "align": "left"}, {"type": "r1", "align": "right"}, {"type": "swipe", "fingers": 2, "direction": "left"},
          {"type": "a2", "align": "left"}, {"type": "c1"}, {"type": "a3", "align": "left"}, {"type": "r2", "align": "right"}
        ]
        """)
        // List.onMove: move a1 (index 0) to the end of the left zone (destination == count).
        doc.move(in: .left, from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(types(doc.items(in: .left)), ["a2", "a3", "a1"])
        XCTAssertEqual(types(doc.items), ["a2", "r1", "swipe", "a3", "c1", "a1", "r2"])

        // Move last item to the front.
        doc.move(in: .left, from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(types(doc.items(in: .left)), ["a1", "a2", "a3"])
        XCTAssertEqual(types(doc.items(in: .right)), ["r1", "r2"])
        XCTAssertEqual(types(doc.gestures), ["swipe"])

        // Moving down by one: destination is the slot *after* the target.
        doc.move(in: .left, from: IndexSet(integer: 0), to: 2)
        XCTAssertEqual(types(doc.items(in: .left)), ["a2", "a1", "a3"])

        // Multiple sources.
        doc.move(in: .left, from: IndexSet([0, 1]), to: 3)
        XCTAssertEqual(types(doc.items(in: .left)), ["a3", "a2", "a1"])

        // Out-of-range input is ignored, not a crash.
        doc.move(in: .left, from: IndexSet(integer: 9), to: 0)
        doc.move(in: .left, from: IndexSet(integer: 0), to: 99)
        XCTAssertEqual(types(doc.items(in: .left)), ["a2", "a1", "a3"])
        XCTAssertEqual(doc.items.count, 7)
    }

    func testMoveChildren() throws {
        let doc = try document(#"[{"type": "group", "title": "g", "items": [{"type":"a"},{"type":"b"},{"type":"c"}]}]"#)
        let group = try XCTUnwrap(doc.items.first)
        doc.moveChildren(ofGroup: group.id, from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(types(doc.items[0].children ?? []), ["b", "c", "a"])
        doc.moveChildren(ofGroup: group.id, from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(types(doc.items[0].children ?? []), ["a", "b", "c"])
        XCTAssertTrue(doc.isDirty)
    }

    // MARK: Real preset

    private var defaultPresetURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MTMR/defaultPreset.json")
    }

    func testDefaultPresetLoadsValidatesAndRoundTrips() throws {
        let original = try Data(contentsOf: defaultPresetURL)
        let doc = PresetDocument(fileURL: defaultPresetURL)
        doc.load()
        XCTAssertNil(doc.loadError)
        XCTAssertFalse(doc.isDirty)
        XCTAssertNil(doc.validate())

        let expected = try XCTUnwrap(original.barItemDefinitions()).count
        XCTAssertGreaterThan(expected, 0)
        let decoded = try JSONDecoder().decode([BarItemDefinition].self, from: Data(doc.serializedText().utf8))
        XCTAssertEqual(decoded.count, expected)
        XCTAssertEqual(doc.items.count, expected)
    }

    func testDefaultPresetSurvivesSaveToTempCopy() throws {
        try FileManager.default.copyItem(at: defaultPresetURL, to: fileURL)
        let doc = PresetDocument(fileURL: fileURL)
        doc.load()
        try doc.save()
        let again = PresetDocument(fileURL: fileURL)
        again.load()
        XCTAssertEqual(again.serializedText(), doc.serializedText())
    }

    // MARK: Catalog

    func testEveryCatalogDefaultDecodesWithTheAppsDecoder() throws {
        for info in ItemCatalog.all {
            let text = JSONValue.array([.object(info.defaultJSON)]).serialized()
            let decoded = try JSONDecoder().decode([BarItemDefinition].self, from: Data(text.utf8))
            XCTAssertEqual(decoded.count, 1, info.type)
            if case let .staticButton(title) = decoded[0].type, title == "unknown" {
                XCTFail("\(info.type): decoder fell back to the 'unknown' button")
            }
            XCTAssertEqual(info.defaultJSON["type"], .string(info.type), info.type)
        }
    }

    func testCatalogDefaultsPassValidation() throws {
        let doc = PresetDocument(fileURL: fileURL)
        for info in ItemCatalog.all { doc.add(type: info.type, align: .center) }
        XCTAssertNil(doc.validate())
    }

    func testCatalogTypesAreUniqueAndKnownCategories() {
        let ids = ItemCatalog.all.map(\.type)
        XCTAssertEqual(Set(ids).count, ids.count)
        for category in ItemCategory.allCases {
            XCTAssertFalse(ItemCatalog.types(in: category).isEmpty, category.rawValue)
        }
        XCTAssertEqual(ItemCatalog.all.map(\.type).sorted(), ItemCatalog.all.map(\.type).sorted())
        XCTAssertEqual(Set(ItemCatalog.commonFields.map(\.key)), ["title", "width", "align", "bordered", "background", "image", "matchAppId"])
        XCTAssertEqual(ItemCatalog.actionTypes.map(\.action), ["hidKey", "keyPress", "appleScript", "shellScript", "openUrl"])
    }

    func testCatalogCoversDecoderTypes() {
        // Types registered in ItemsParsing.swift (SupportedTypesHolder + ItemTypeRaw) and
        // TouchBarController ("exitTouchbar", "close"); keep in sync when the decoder grows.
        let builtIns = ["escape", "delete", "brightnessUp", "brightnessDown", "illuminationUp", "illuminationDown", "volumeDown", "volumeUp",
                        "mute", "previous", "play", "next", "sleep", "displaySleep", "exitTouchbar", "close"]
        let raw = ["staticButton", "appleScriptTitledButton", "shellScriptTitledButton", "timeButton", "battery", "cpu", "dock", "volume",
                   "brightness", "weather", "yandexWeather", "currency", "inputsource", "music", "group", "nightShift", "dnd", "pomodoro",
                   "network", "darkMode", "swipe", "upnext"]
        XCTAssertEqual(Set(ItemCatalog.all.map(\.type)), Set(builtIns + raw))
        for type in raw { XCTAssertNotNil(ItemType.ItemTypeRaw(rawValue: type), type) }
    }

    func testCatalogCoversDefaultPreset() throws {
        let doc = PresetDocument(fileURL: defaultPresetURL)
        doc.load()
        XCTAssertFalse(doc.items.isEmpty)
        for item in doc.items + doc.items.flatMap({ $0.children ?? [] }) {
            XCTAssertNotNil(ItemCatalog.info(for: item.type), "defaultPreset.json uses \(item.type)")
        }
    }

    func testCatalogFieldKeysAreUniquePerType() {
        for info in ItemCatalog.all {
            let keys = info.fields.map(\.key)
            XCTAssertEqual(Set(keys).count, keys.count, info.type)
            XCTAssertTrue(Set(keys).isDisjoint(with: ["type", "actions", "items"]), info.type)
        }
    }
}
