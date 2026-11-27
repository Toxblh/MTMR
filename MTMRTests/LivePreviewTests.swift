import XCTest

final class LivePreviewTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("items.json") }

    func testPreviewStringsCoverBothLanguagesAndKeepFormatArguments() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MTMR")
        func table(_ language: String) throws -> [String: String] {
            let url = app.appendingPathComponent("\(language).lproj/LivePreview.strings")
            let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
            return try XCTUnwrap(plist as? [String: String])
        }
        let english = try table("en")
        let chinese = try table("zh-Hans")
        let call = try NSRegularExpression(pattern: #"L10n\.preview\("([^"]+)"\)"#)
        var used = Set(PreviewControlStrip.allCases.map(\.rawValue))
        used.formUnion(PreviewZoom.allCases.compactMap(\.titleKey))
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let key = Range(match.range(at: 1), in: text) { used.insert(String(text[key])) }
            }
        }
        XCTAssertEqual(Set(english.keys), used)
        XCTAssertEqual(Set(chinese.keys), used)

        let format = try NSRegularExpression(pattern: #"%(?:[0-9]+\$)?(?:hh|ll|[hlzt])?[@diuoxXfFeEgGcsap%]"#)
        func arguments(in text: String) -> [String] {
            format.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        }
        for key in used {
            XCTAssertEqual(english[key], key)
            let translation = try XCTUnwrap(chinese[key])
            XCTAssertFalse(translation.isEmpty, key)
            XCTAssertEqual(arguments(in: translation), arguments(in: key), key)
        }
    }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func load(_ text: String) throws -> PresetDocument {
        try Data(text.utf8).write(to: file)
        let document = PresetDocument(fileURL: file)
        document.load()
        XCTAssertNil(document.loadError)
        return document
    }

    func testIdenticalButtonsMovedAcrossOneAnotherWaitForReload() throws {
        let document = try load("""
        [{"type":"timeButton"},{"type":"timeButton"},{"type":"battery"}]
        """)
        let ids = document.items.map(\.id)
        let original = try XCTUnwrap(document.savedRevision)
        document.move(in: .center, from: IndexSet(integer: 0), to: 2)
        XCTAssertNil(document.livePath(for: ids[0], revision: original))
        XCTAssertNil(document.livePath(for: ids[1], revision: original))
        XCTAssertEqual(document.livePath(for: ids[2], revision: original), [2])
        try document.save()
        XCTAssertNil(document.livePath(for: ids[0], revision: nil)) // controller's pending reload
        let applied = PresetRevision(url: file, data: try Data(contentsOf: file))
        XCTAssertEqual(document.livePath(for: ids[0], revision: applied), [1])
        XCTAssertEqual(document.livePath(for: ids[1], revision: applied), [0])
        XCTAssertFalse(document.isDirty)
    }

    func testAddDeleteDuplicateEditAndForeignFile() throws {
        let document = try load("""
        [{"type":"staticButton","title":"A"},{"type":"staticButton","title":"B"},{"type":"battery"}]
        """)
        let original = document.savedRevision
        let ids = document.items.map(\.id)
        let copy = try XCTUnwrap(document.duplicate(id: ids[0]))
        XCTAssertNil(document.livePath(for: copy, revision: original))
        XCTAssertNil(document.livePath(for: ids[1], revision: original))
        XCTAssertEqual(document.livePath(for: ids[0], revision: original), [0])
        document.remove(id: ids[0])
        XCTAssertNil(document.livePath(for: copy, revision: original))
        XCTAssertEqual(document.livePath(for: ids[1], revision: original), [1])
        let new = document.add(type: "timeButton", align: .right)
        XCTAssertNil(document.livePath(for: new, revision: original))
        var changed = try XCTUnwrap(document.item(withID: ids[1]))
        changed.json["title"] = .string("C")
        document.update(changed)
        XCTAssertNil(document.livePath(for: ids[1], revision: original))
        let foreign = PresetRevision(url: directory.appendingPathComponent("other.json"), data: try Data(contentsOf: file))
        XCTAssertNil(document.livePath(for: ids[2], revision: foreign))
    }

    func testNestedGroupBindingsAndAdvancedEdits() throws {
        let document = try load("""
        [{"type":"group","items":[{"type":"group","items":[{"type":"timeButton"},{"type":"battery"}]}],"title":"Info","extra":7}]
        """)
        let outer = document.items[0]
        let inner = try XCTUnwrap(outer.children?.first)
        let clock = try XCTUnwrap(inner.children?.first)
        XCTAssertEqual(document.ancestors(of: clock.id), [outer.id, inner.id])
        XCTAssertEqual(document.livePath(for: clock.id, revision: document.savedRevision), [0, 0, 0])
        let revision = document.savedRevision
        document.moveChildren(ofGroup: inner.id, from: IndexSet(integer: 0), to: 2)
        XCTAssertNil(document.livePath(for: clock.id, revision: revision))
        XCTAssertNil(document.livePath(for: outer.id, revision: revision))
        XCTAssertEqual(document.livePath(for: inner.id, revision: revision, checkingChildren: false), [0, 0])
        var attributes = outer.json
        attributes["title"] = .string("Stats")
        try document.applyJSON(attributes, to: outer.id)
        XCTAssertEqual(document.item(at: [0, 0, 1])?.id, clock.id)
        try document.save()
        let text = try String(contentsOf: file)
        XCTAssertFalse(text.contains(clock.id.uuidString))
        XCTAssertTrue(text.contains("\"extra\": 7"))
        document.revert()
        XCTAssertEqual(document.item(at: [0, 0, 1])?.type, "timeButton")
        XCTAssertNil(document.livePath(for: clock.id, revision: document.savedRevision))
    }

    func testOptionIsTheOnlyRealActionAndDoubleClickEntersOnlyGroups() {
        XCTAssertEqual(PreviewClick.resolve(count: 1, option: false, group: true), .select)
        XCTAssertEqual(PreviewClick.resolve(count: 1, option: false, group: false), .select)
        XCTAssertEqual(PreviewClick.resolve(count: 2, option: false, group: true), .enterGroup)
        XCTAssertEqual(PreviewClick.resolve(count: 2, option: false, group: false), .ignore)
        XCTAssertEqual(PreviewClick.resolve(count: 1, option: true, group: false), .test)
        XCTAssertEqual(PreviewClick.resolve(count: 2, option: true, group: true), .ignore)
    }

    func testPhysicalPanelAndSystemReservations() {
        let classic = TouchBarGeometry(panelWidth: nil, mounted: nil, mode: .current)
        XCTAssertEqual(classic.width, 1085)
        XCTAssertEqual(classic.application, CGRect(x: 80, y: 0, width: 685, height: 30))
        XCTAssertEqual(classic.controlStrip.width, 304)
        let modern = TouchBarGeometry(panelWidth: 1004, mounted: nil, mode: .collapsed)
        XCTAssertEqual(modern.application.width, 684)
        XCTAssertEqual(modern.application.minX, 80) // dedicated Esc lies outside the 1004-pt panel
        XCTAssertEqual(PreviewZoom.fit.scale(fitting: 574, barWidth: modern.deckWidth), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PreviewZoom.fit.scale(fitting: 1800, barWidth: modern.deckWidth), 1.2, accuracy: 0.0001)
        let expanded = TouchBarGeometry(panelWidth: 1004, mounted: nil, mode: .expanded)
        XCTAssertTrue(expanded.application.isEmpty)
        XCTAssertEqual(expanded.controlStrip.width, 1004)
    }

    func testMountedAppKitBoundsTakePrecedenceInTheirControlStripState() {
        let compact = CGRect(x: 64, y: 0, width: 836, height: 30)
        for mode in [PreviewControlStrip.current, .collapsed] {
            let bar = TouchBarGeometry(panelWidth: 1004, mounted: compact, mode: mode)
            XCTAssertTrue(bar.usesMountedWidth)
            XCTAssertEqual(bar.application.width, compact.width)
            XCTAssertEqual(bar.application.minX, 80 + compact.minX)
        }
        let full = CGRect(x: 0, y: 0, width: 1004, height: 30)
        XCTAssertEqual(TouchBarGeometry(panelWidth: 1004, mounted: full, mode: .current).application.width, 1004)
        XCTAssertEqual(TouchBarGeometry(panelWidth: 1004, mounted: full, mode: .collapsed).application.width, 684)
        let remembered = TouchBarGeometry(panelWidth: 1004, mounted: full, mode: .collapsed, lastCollapsed: compact)
        XCTAssertEqual(remembered.application.width, 836)
        XCTAssertTrue(remembered.usesMeasuredWidth)
        XCTAssertFalse(remembered.usesMountedWidth)
        XCTAssertEqual(TouchBarGeometry(panelWidth: 1004, mounted: compact, mode: .expanded).application.width, 0)
    }

    func testFullWidthVirtualEscapePanelUsesNoExternalKeySlots() {
        let full = CGRect(x: 0, y: 0, width: 1085, height: 30)
        let bar = TouchBarGeometry(panelWidth: 1085, mounted: full, mode: .current)
        XCTAssertTrue(bar.usesMountedWidth)
        XCTAssertEqual(bar.application, full)
        XCTAssertEqual(bar.oledFrame, full)
        XCTAssertTrue(bar.escape.isEmpty)
        XCTAssertTrue(bar.controlStrip.isEmpty)
        XCTAssertTrue(bar.touchIDFrame.isEmpty)
        XCTAssertEqual(bar.width, 1085)
        XCTAssertEqual(bar.deckWidth, 1085)
    }

    func testDockOverflowsAtPhysicalPointBoundaryAndFlatLayoutPacksItems() {
        let fit = PreviewZoneWidths(available: 685, left: 450, center: 50, right: 169, balanced: false)
        XCTAssertEqual(fit.left, 450) // 450 + 8 + 50 + 8 + 169
        let over = PreviewZoneWidths(available: 685, left: 450, center: 50, right: 170, balanced: false)
        XCTAssertEqual(over.left, 449)
        XCTAssertEqual(over.right, 170)
        let sparse = PreviewZoneWidths(available: 685, left: 32, center: 24, right: 40, balanced: false)
        XCTAssertEqual(sparse.center, 24)
        let balanced = PreviewZoneWidths(available: 685, left: 32, center: 24, right: 40, balanced: true)
        XCTAssertEqual(balanced.center, 597)
        let crowded = PreviewZoneWidths(available: 685, left: 2400, center: 1200, right: 1100, balanced: false)
        XCTAssertGreaterThan(crowded.left, 0)
        XCTAssertGreaterThan(crowded.center, 0)
        XCTAssertEqual(crowded.left + crowded.center + crowded.right + crowded.firstGap + crowded.lastGap, 685)
    }

    func testPreviewZoomHardwareDeckAndSpaceUsage() throws {
        let classic = TouchBarGeometry(panelWidth: nil, mounted: nil, mode: .current)
        XCTAssertFalse(classic.hasPhysicalEscape)
        XCTAssertEqual(classic.panelOriginX, 0)
        XCTAssertEqual(classic.oledFrame, CGRect(x: 0, y: 0, width: 1085, height: 30))
        XCTAssertEqual(classic.touchIDFrame, .zero)
        XCTAssertEqual(classic.deckWidth, 1085)

        let modern = TouchBarGeometry(panelWidth: 1004, mounted: nil, mode: .collapsed)
        XCTAssertTrue(modern.hasPhysicalEscape)
        XCTAssertEqual(modern.panelOriginX, 80)
        XCTAssertEqual(modern.oledFrame, CGRect(x: 80, y: 0, width: 1004, height: 30))
        XCTAssertEqual(modern.escape, CGRect(x: 0, y: 0, width: 64, height: 30))
        XCTAssertEqual(modern.touchIDFrame, CGRect(x: 1100, y: 0, width: 48, height: 30))
        XCTAssertEqual(modern.deckWidth, 1148)

        XCTAssertEqual(PreviewZoom.fit.scale(fitting: 1400, barWidth: 1085), TouchBarMetrics.previewBaseScale, accuracy: 0.0001)
        XCTAssertEqual(PreviewZoom.fit.scale(fitting: 542.5, barWidth: 1085), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PreviewZoom.x85.scale(fitting: 500, barWidth: 1085), 1.0, accuracy: 0.0001)
        XCTAssertEqual(PreviewZoom.x100.scale(fitting: 500, barWidth: 1085), 1.2, accuracy: 0.0001)
        XCTAssertEqual(PreviewZoom.x125.scale(fitting: 500, barWidth: 1085), 1.5, accuracy: 0.0001)
        XCTAssertEqual(PreviewZoom.x150.scale(fitting: 500, barWidth: 1085), 1.8, accuracy: 0.0001)

        XCTAssertEqual(PreviewSpaceUsage.contentWidth(left: 100, center: 200, right: 150), 466)
        XCTAssertEqual(PreviewSpaceUsage.contentWidth(left: 100, center: 0, right: 150), 258)
        XCTAssertEqual(PreviewSpaceUsage.contentWidth(left: 0, center: 200, right: 0), 200)

        let normal = PreviewSpaceUsage(usedWidth: 400, availableWidth: 685, measured: true, isOverflowing: false, isExpandedControlStrip: false)
        XCTAssertEqual(normal.level, .normal)
        let tight = PreviewSpaceUsage(usedWidth: 620, availableWidth: 685, measured: true, isOverflowing: false, isExpandedControlStrip: false)
        XCTAssertEqual(tight.level, .tight)
        let overflow = PreviewSpaceUsage(usedWidth: 720, availableWidth: 685, measured: true, isOverflowing: true, isExpandedControlStrip: false)
        XCTAssertEqual(overflow.level, .overflow)
        XCTAssertEqual(overflow.fillRatio, 1.0)
        let expanded = PreviewSpaceUsage(usedWidth: 400, availableWidth: 0, measured: false, isOverflowing: false, isExpandedControlStrip: true)
        XCTAssertEqual(expanded.level, .overflow)
        XCTAssertEqual(expanded.fillRatio, 1.0)

        let doc = try load("""
        [{"type":"staticButton","title":"Safari","matchAppId":"com\\\\.apple\\\\.Safari"},{"type":"staticButton","title":"Empty","matchAppId":""}]
        """)
        XCTAssertEqual(doc.items[0].matchAppIdPattern, "com\\.apple\\.Safari")
        XCTAssertNil(doc.items[1].matchAppIdPattern)
    }

    func testRelocateWithinZoneAcrossZonesGroupsAndEscapeConstraint() throws {
        let doc = try load("""
        [
          {"type":"escape"},
          {"type":"staticButton","title":"L1","align":"left"},
          {"type":"staticButton","title":"R1","align":"right"},
          {"type":"staticButton","title":"R2","align":"right"},
          {"type":"group","title":"G","align":"right","items":[
            {"type":"staticButton","title":"G1"},
            {"type":"staticButton","title":"G2"}
          ]}
        ]
        """)
        let esc = doc.items[0].id
        let l1 = doc.items[1].id
        let r1 = doc.items[2].id
        let r2 = doc.items[3].id
        let group = doc.items[4].id
        let g1 = try XCTUnwrap(doc.items[4].children?[0].id)
        let g2 = try XCTUnwrap(doc.items[4].children?[1].id)

        // No-op drops leave document clean.
        XCTAssertFalse(doc.relocate(id: r1, to: .right, before: r1))
        XCTAssertFalse(doc.relocate(id: r1, to: .right, before: r2))
        XCTAssertFalse(doc.relocate(id: group, to: .right, before: nil))
        XCTAssertFalse(doc.isDirty)

        // Escape cannot move out of left, but can reorder within left.
        XCTAssertFalse(doc.relocate(id: esc, to: .center, before: nil))
        XCTAssertFalse(doc.relocate(id: esc, to: .right, before: r1))
        XCTAssertFalse(doc.isDirty)
        XCTAssertTrue(doc.relocate(id: esc, to: .left, before: nil))
        XCTAssertEqual(doc.items(in: .left).map(\.id), [l1, esc])

        // Reorder within right zone.
        XCTAssertTrue(doc.relocate(id: r2, to: .right, before: r1))
        XCTAssertEqual(doc.items(in: .right).map(\.id), [r2, r1, group])

        // Move across zones into an empty center zone.
        XCTAssertTrue(doc.relocate(id: r1, to: .center, before: nil))
        XCTAssertEqual(doc.items(in: .center).map(\.id), [r1])
        XCTAssertEqual(doc.items(in: .right).map(\.id), [r2, group])
        XCTAssertEqual(doc.item(withID: r1)?.align, .center)

        // Move from center into left before a specific item.
        XCTAssertTrue(doc.relocate(id: r1, to: .left, before: esc))
        XCTAssertEqual(doc.items(in: .left).map(\.id), [l1, r1, esc])
        XCTAssertEqual(doc.items(in: .center).map(\.id), [])

        // Reorder children inside a group.
        XCTAssertTrue(doc.relocate(id: g2, to: .center, before: g1, inGroup: group))
        XCTAssertEqual(doc.item(withID: group)?.children?.map(\.id), [g2, g1])
    }

    func testPreviewDropResolverHandlesReorderEmptyZonesAndFixedEscape() {
        let l1 = UUID(), l2 = UUID(), r1 = UUID(), r2 = UUID()
        let leftZone = CGRect(x: 0, y: 0, width: 120, height: 30)
        let rightZone = CGRect(x: 420, y: 0, width: 180, height: 30)
        let leftSlots = [
            PreviewDropSlot(id: l1, frame: CGRect(x: 0, y: 0, width: 56, height: 30)),
            PreviewDropSlot(id: l2, frame: CGRect(x: 64, y: 0, width: 56, height: 30)),
        ]
        let rightSlots = [
            PreviewDropSlot(id: r1, frame: CGRect(x: 420, y: 0, width: 80, height: 30)),
            PreviewDropSlot(id: r2, frame: CGRect(x: 508, y: 0, width: 80, height: 30)),
        ]

        // Dropping r2 back onto its own left or right half is a no-op.
        let noopLeft = PreviewDropResolver.resolve(
            cursorX: 520, appWidth: 600, draggedID: r2, draggedAlign: .right, hasFixedAlign: false,
            leftZone: leftZone, centerZone: .zero, rightZone: rightZone,
            leftSlots: leftSlots, centerSlots: [], rightSlots: rightSlots
        )
        XCTAssertEqual(noopLeft?.align, .right)
        XCTAssertEqual(noopLeft?.isNoOp, true)

        // Dragging r2 before r1 targets before r1.
        let beforeR1 = PreviewDropResolver.resolve(
            cursorX: 430, appWidth: 600, draggedID: r2, draggedAlign: .right, hasFixedAlign: false,
            leftZone: leftZone, centerZone: .zero, rightZone: rightZone,
            leftSlots: leftSlots, centerSlots: [], rightSlots: rightSlots
        )
        XCTAssertEqual(beforeR1?.align, .right)
        XCTAssertEqual(beforeR1?.beforeItemID, r1)
        XCTAssertEqual(beforeR1?.isNoOp, false)

        // Dragging into the empty middle gap targets .center with an empty-zone highlight.
        let intoCenter = PreviewDropResolver.resolve(
            cursorX: 270, appWidth: 600, draggedID: r2, draggedAlign: .right, hasFixedAlign: false,
            leftZone: leftZone, centerZone: .zero, rightZone: rightZone,
            leftSlots: leftSlots, centerSlots: [], rightSlots: rightSlots
        )
        XCTAssertEqual(intoCenter?.align, .center)
        XCTAssertNil(intoCenter?.beforeItemID)
        XCTAssertNotNil(intoCenter?.emptyZoneHighlight)
        XCTAssertEqual(intoCenter?.isNoOp, false)

        // Dragging between l1 and l2 places indicator in the midpoint gap (60).
        let betweenLeft = PreviewDropResolver.resolve(
            cursorX: 60, appWidth: 600, draggedID: r2, draggedAlign: .right, hasFixedAlign: false,
            leftZone: leftZone, centerZone: .zero, rightZone: rightZone,
            leftSlots: leftSlots, centerSlots: [], rightSlots: rightSlots
        )
        XCTAssertEqual(betweenLeft?.align, .left)
        XCTAssertEqual(betweenLeft?.beforeItemID, l2)
        XCTAssertEqual(betweenLeft?.indicatorX, 60)

        // Fixed-align Escape stays constrained to .left when dragged over right.
        let escOverRight = PreviewDropResolver.resolve(
            cursorX: 500, appWidth: 600, draggedID: l1, draggedAlign: .left, hasFixedAlign: true,
            leftZone: leftZone, centerZone: .zero, rightZone: rightZone,
            leftSlots: leftSlots, centerSlots: [], rightSlots: rightSlots
        )
        XCTAssertEqual(escOverRight?.align, .left)
        XCTAssertEqual(escOverRight?.constrainedToFixedAlign, true)
    }

    func testPomodoroDisplayUsesSafeSecondsWithoutRoundingNormalDurationsUp() {
        let fallback = PomodoroDuration.defaultWork
        for duration in [1e20, -1e20, Double(Int.max), .infinity, .nan] {
            let seconds = PomodoroDuration.seconds(duration, fallback: fallback)
            XCTAssertEqual(PomodoroDuration.display(seconds), "25:00")
        }
        XCTAssertEqual(PomodoroDuration.display(PomodoroDuration.seconds(125.9, fallback: fallback)), "02:05")
        XCTAssertEqual(PomodoroDuration.display(PomodoroDuration.seconds(-1, fallback: fallback)), "00:00")
        XCTAssertEqual(PomodoroDuration.display(180_000_000_000), "3000000000:00")
    }

    func testPreviewSlidePlannerSlidesNeighborsAndOpensExactGap() {
        let a = UUID(), b = UUID(), c = UUID()
        let rightSlots = [
            PreviewDropSlot(id: a, frame: CGRect(x: 400, y: 0, width: 50, height: 30)),
            PreviewDropSlot(id: b, frame: CGRect(x: 458, y: 0, width: 32, height: 30)),
            PreviewDropSlot(id: c, frame: CGRect(x: 498, y: 0, width: 46, height: 30)),
        ]

        // Same-zone: dragging A(50) to before C shifts B left by -58 and opens a 50-pt pocket at 440...490.
        let sameZoneTarget = PreviewDropTarget(align: .right, beforeItemID: c, indicatorX: 494, emptyZoneHighlight: nil, isNoOp: false, constrainedToFixedAlign: false)
        let samePlan = PreviewSlidePlanner.plan(
            align: .right, slots: rightSlots, spacing: 8,
            draggedID: a, draggedWidth: 50, draggedAlign: .right,
            target: sameZoneTarget, availableLeadingRoom: 100, availableTrailingRoom: 0
        )
        XCTAssertEqual(samePlan.offsets[b], -58)
        XCTAssertEqual(samePlan.offsets[c], 0)
        XCTAssertEqual(samePlan.gapRectInApplication, CGRect(x: 440, y: 0, width: 50, height: 30))

        // Same-zone no-op: no tiles shift, pocket sits in A's resting frame.
        let noopTarget = PreviewDropTarget(align: .right, beforeItemID: b, indicatorX: 454, emptyZoneHighlight: nil, isNoOp: true, constrainedToFixedAlign: false)
        let noopPlan = PreviewSlidePlanner.plan(
            align: .right, slots: rightSlots, spacing: 8,
            draggedID: a, draggedWidth: 50, draggedAlign: .right,
            target: noopTarget, availableLeadingRoom: 100, availableTrailingRoom: 0
        )
        XCTAssertTrue(noopPlan.offsets.isEmpty)
        XCTAssertEqual(noopPlan.gapRectInApplication, rightSlots[0].frame)

        // Cross-zone source (Right loses B): A shifts right by +40 to stay right-aligned, C stays anchored.
        let crossToLeft = PreviewDropTarget(align: .left, beforeItemID: nil, indicatorX: 120, emptyZoneHighlight: nil, isNoOp: false, constrainedToFixedAlign: false)
        let sourcePlan = PreviewSlidePlanner.plan(
            align: .right, slots: rightSlots, spacing: 8,
            draggedID: b, draggedWidth: 32, draggedAlign: .right,
            target: crossToLeft, availableLeadingRoom: 100, availableTrailingRoom: 0
        )
        XCTAssertEqual(sourcePlan.offsets[a], 40)
        XCTAssertEqual(sourcePlan.offsets[c], 0)
        XCTAssertNil(sourcePlan.gapRectInApplication)

        // Cross-zone target (Left gains a 40-pt item before L2): L2 shifts right by +48 and expands trailing room.
        let l1 = UUID(), l2 = UUID()
        let leftSlots = [
            PreviewDropSlot(id: l1, frame: CGRect(x: 0, y: 0, width: 60, height: 30)),
            PreviewDropSlot(id: l2, frame: CGRect(x: 68, y: 0, width: 50, height: 30)),
        ]
        let intoLeftBeforeL2 = PreviewDropTarget(align: .left, beforeItemID: l2, indicatorX: 64, emptyZoneHighlight: nil, isNoOp: false, constrainedToFixedAlign: false)
        let targetPlan = PreviewSlidePlanner.plan(
            align: .left, slots: leftSlots, spacing: 8,
            draggedID: a, draggedWidth: 40, draggedAlign: .right,
            target: intoLeftBeforeL2, availableLeadingRoom: 0, availableTrailingRoom: 120
        )
        XCTAssertEqual(targetPlan.offsets[l1], 0)
        XCTAssertEqual(targetPlan.offsets[l2], 48)
        XCTAssertEqual(targetPlan.gapRectInApplication, CGRect(x: 68, y: 0, width: 40, height: 30))
        XCTAssertEqual(targetPlan.expandTrailing, 48)
    }

    func testPreviewSlidePlannerKeepsTargetAnchorsAndEmptyZoneHighlight() {
        let first = UUID(), second = UUID(), dragged = UUID()
        let slots = [
            PreviewDropSlot(id: first, frame: CGRect(x: 100, y: 0, width: 36, height: 30)),
            PreviewDropSlot(id: second, frame: CGRect(x: 144, y: 0, width: 52, height: 30)),
        ]

        func plan(_ align: PresetAlign, before: UUID?, leading: CGFloat, trailing: CGFloat,
                  in slots: [PreviewDropSlot], highlight: CGRect? = nil) -> PreviewZoneSlideResult {
            let target = PreviewDropTarget(align: align, beforeItemID: before, indicatorX: 0,
                                           emptyZoneHighlight: highlight, isNoOp: false, constrainedToFixedAlign: false)
            return PreviewSlidePlanner.plan(
                align: align, slots: slots, spacing: 8, draggedID: dragged, draggedWidth: 40,
                draggedAlign: .left, target: target, availableLeadingRoom: leading, availableTrailingRoom: trailing
            )
        }

        let right = plan(.right, before: nil, leading: 5, trailing: 0, in: slots)
        XCTAssertEqual(right.offsets, [first: -48, second: -48])
        XCTAssertEqual(right.gapRectInApplication, CGRect(x: 156, y: 0, width: 40, height: 30))
        XCTAssertEqual(right.expandLeading, 5)
        XCTAssertEqual(right.expandTrailing, 0)
        XCTAssertEqual(plan(.right, before: UUID(), leading: 5, trailing: 0, in: slots), right)

        let center = plan(.center, before: first, leading: 3, trailing: 12, in: slots)
        XCTAssertEqual(center.offsets, [first: 24, second: 24])
        XCTAssertEqual(center.gapRectInApplication, CGRect(x: 76, y: 0, width: 40, height: 30))
        XCTAssertEqual(center.expandLeading, 3)
        XCTAssertEqual(center.expandTrailing, 12)

        let highlight = CGRect(x: 9, y: 0, width: 25, height: 30)
        let empty = plan(.center, before: nil, leading: 20, trailing: 20, in: [], highlight: highlight)
        XCTAssertEqual(empty, PreviewZoneSlideResult(offsets: [:], gapRectInApplication: highlight,
                                                      expandLeading: 0, expandTrailing: 0))
    }
}
