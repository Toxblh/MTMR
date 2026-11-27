
import Combine
import SwiftUI

@MainActor
private final class FixtureTouchBar: RunningTouchBar {
    let layoutChanges = PassthroughSubject<Void, Never>()
    var generation = 0
    var appliedRevision: PresetRevision?
    var isReloadPending = false
    var presetURL: URL
    var presentedGroupPath: [Int] = []
    var roots: [NSTouchBarItem] = []
    let layoutAnchor: NSView? = nil
    let panelWidth: CGFloat? = nil
    let presentedBar: NSTouchBar? = nil

    init(_ file: URL) throws {
        presetURL = file
        try reload(file)
    }

    func rootItem(at index: Int) -> NSTouchBarItem? {
        roots.indices.contains(index) ? roots[index] : nil
    }

    func scheduleReload(path: String) {
        isReloadPending = true
        appliedRevision = nil
        layoutChanges.send()
    }

    func reload(_ file: URL) throws {
        presetURL = file
        isReloadPending = false
        generation += 1
        let data = try Data(contentsOf: file)
        appliedRevision = data.barItemDefinitions() == nil ? nil : PresetRevision(url: file, data: data)
        layoutChanges.send()
    }
}

@main @MainActor
private enum CustomizerIntegration {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static var presets: URL {
        URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    }

    static func main() async throws {
        _ = NSApplication.shared
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let english = Bundle(path: path) {
            L10n.bundle = english
        }

        let scenarios: [(String, @MainActor () async throws -> Void)] = [
            ("failed external reload and save before notification", externalWrite),
            ("revert to the running preset", revertToRunning),
            ("Pomodoro completion and cancellation across groups", groupTimer),
            ("drop into empty zones using laid-out tiles", emptyDrops),
            ("release over sidebar and outside the window", cancelDrops),
            ("preview durations from Advanced JSON and existing presets", draftDuration),
            ("virtual Esc and physical Esc/Touch ID preview layout", hardwareLayout),
            ("clock context menu, save and reload", clockBorder),
            ("Preview status for matching rules and live output changes", previewStatuses),
        ]
        var failures = 0
        for (name, scenario) in scenarios {
            do {
                try await scenario()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name) – \(error)")
            }
        }
        print("Customizer integration: \(scenarios.count) scenarios, \(failures) failures")
        if failures > 0 { exit(1) }
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

    private static func makeWindow(_ document: PresetDocument, _ runtime: FixtureTouchBar,
                                   _ state: CustomizerState) throws -> CustomizerWindowController {
        state.previewRuntime = runtime
        let controller = CustomizerWindowController(preset: document, state: state)
        let window = try require(controller.window)
        window.setFrameAutosaveName("")
        window.alphaValue = 0
        controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        window.orderBack(nil)
        return controller
    }

    private static func refresh(_ window: NSWindow) async throws {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private static func externalWrite() async throws {
        let url = try preset("external", #"[{"type":"staticButton","title":"Original"}]"#)
        let document = PresetDocument(fileURL: url)
        let runtime = try FixtureTouchBar(url)
        let state = CustomizerState()
        let controller = try makeWindow(document, runtime, state)
        defer { controller.close() }
        let original = try require(document.items.first)
        let originalRevision = document.savedRevision
        document.duplicate(id: original.id)
        state.selection = original.id
        let draft = document.items

        let invalid = Data("[".utf8)
        try invalid.write(to: url)
        // The user presses Save before the watcher even starts the reload.
        try check(runtime.appliedRevision == originalRevision)
        try check(document.saveReportingError() != nil)
        try check(try Data(contentsOf: url) == invalid)
        try check(document.isDirty && document.items == draft)

        runtime.scheduleReload(path: url.path)
        try check(state.presetNotice == nil)
        try runtime.reload(url)
        try check(state.presetNotice?.message == L10n.preview("The running Touch Bar could not load its preset."))
        do {
            let english = L10n.bundle
            let originalMessage = state.presetNotice?.message
            let path = try require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
            L10n.bundle = try require(Bundle(path: path))
            defer { L10n.bundle = english }
            try check(state.presetNotice?.message != originalMessage)
            try check(state.presetNotice?.message == L10n.preview("The running Touch Bar could not load its preset."))
        }
        try check(state.selection == original.id)
        try check(document.isDirty && document.items == draft && document.savedRevision == originalRevision)
        try check(document.saveReportingError() != nil)
        try check(try Data(contentsOf: url) == invalid)

        let repaired = Data(#"[{"type":"staticButton","title":"External edit"}]"#.utf8)
        try repaired.write(to: url)
        try runtime.reload(url)
        try check(state.presetNotice?.message == L10n.preview("The running Touch Bar uses a different preset version. Save or revert to resume live preview."))
        try check(document.saveReportingError() != nil)
        try check(try Data(contentsOf: url) == repaired)
    }

    private static func revertToRunning() async throws {
        let a = try preset("A", #"[{"type":"staticButton","title":"A"}]"#)
        let b = try preset("B", #"[{"type":"staticButton","title":"B"}]"#)
        let document = PresetDocument(fileURL: a)
        let runtime = try FixtureTouchBar(a)
        let state = CustomizerState()
        let controller = try makeWindow(document, runtime, state)
        defer { controller.close() }
        let window = try require(controller.window)
        let bytesA = try Data(contentsOf: a)
        let bytesB = try Data(contentsOf: b)
        state.selection = document.items.first?.id
        document.add(type: "escape", align: .left)
        try await refresh(window)
        try check(window.isDocumentEdited)

        try runtime.reload(b)
        try check(document.fileURL == a && state.presetNotice != nil)
        controller.revertPreset()
        try await refresh(window)
        try check(document.fileURL == b && document.items.map(\.listTitle) == ["B"])
        try check(document.savedRevision == runtime.appliedRevision)
        try check(state.selection == nil && state.groupPath.isEmpty && state.presetNotice == nil)
        try check(!document.isDirty && !window.isDocumentEdited)
        try check(try Data(contentsOf: a) == bytesA && Data(contentsOf: b) == bytesB)
    }

    private static func groupTimer() async throws {
        let data = Data(#"[{"type":"pomodoro","workTime":1,"restTime":1},{"type":"group","items":[]}]"#.utf8)
        let definitions = try require(data.barItemDefinitions())
        var notifications: [Bool] = []
        let parent = GroupBarItem(identifier: .init("parent"), items: definitions) { id, definition in
            switch definition.type {
            case let .pomodoro(work, rest):
                return PomodoroBarItem(identifier: id, workTime: work, restTime: rest) { notifications.append($0) }
            case let .group(items):
                return GroupBarItem(identifier: id, items: items) { _, _ in nil }
            default:
                return nil
            }
        }
        let bar = NSTouchBar()

        parent.install(on: bar)
        let child = try require(parent.child(at: 1) as? GroupBarItem)
        weak let timer = parent.child(at: 0) as? PomodoroBarItem
        try check(timer != nil)
        timer?.startStopWork()
        child.install(on: bar)
        parent.releaseHardwareItems()
        try check(timer != nil)
        let deadline = Date().addingTimeInterval(1.5)
        while timer?.title.contains("00:00") == false && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try check(timer?.title.contains("00:00") == true)
        try await Task.sleep(nanoseconds: 2_100_000_000)
        try check(notifications == [true] && timer == nil)

        parent.install(on: bar)
        weak let cancelled = parent.child(at: 0) as? PomodoroBarItem
        cancelled?.startStopRest()
        child.install(on: bar)
        parent.releaseHardwareItems()
        parent.install(on: bar)
        try check(cancelled != nil && parent.child(at: 0) === cancelled)
        cancelled?.startStopRest()
        child.install(on: bar)
        parent.releaseHardwareItems()
        try await Task.sleep(nanoseconds: 1_300_000_000)
        try check(notifications == [true] && cancelled == nil)
    }

    private static func tile(in view: NSView?, title: String) throws -> LivePreviewItemView {
        try require(descendants(of: view).compactMap { $0 as? LivePreviewItemView }.first { $0.item.listTitle == title })
    }

    private static func application(in view: NSView?) throws -> NSView {
        try require(descendants(of: view).compactMap { $0 as? TouchBarPreviewSurface }.first?.application)
    }

    private static func emptyDrops() async throws {
        let layouts = [
            (#"[{"type":"staticButton","title":"Center","align":"center","width":64}]"#, "Center", PresetAlign.left),
            (#"[{"type":"staticButton","title":"Left","align":"left","width":64},{"type":"staticButton","title":"Right","align":"right","width":64}]"#, "Left", PresetAlign.center),
        ]
        for (json, title, destination) in layouts {
            let url = try preset("drop-" + destination.rawValue, json)
            let document = PresetDocument(fileURL: url)
            let controller = try makeWindow(document, FixtureTouchBar(url), CustomizerState())
            defer { controller.close() }
            let window = try require(controller.window)
            try await refresh(window)
            let view = window.contentView
            let app = try application(in: view)
            let dragged = try tile(in: view, title: title)
            try check(app.bounds.width == 685 && dragged.bounds.width == 64)
            let frame = dragged.convert(dragged.bounds, to: app)
            let x: CGFloat
            if destination == .left {
                try check(abs(frame.minX) < 0.5)
                x = app.bounds.minX + 3
            } else {
                let right = try tile(in: view, title: "Right")
                let rightFrame = right.convert(right.bounds, to: app)
                try check(rightFrame.width == 64 && rightFrame.minX - frame.maxX == 16)
                x = (rightFrame.minX + frame.maxX) / 2
            }
            let target = app.convert(NSPoint(x: x, y: app.bounds.midY), to: nil)
            drag(dragged, in: window, through: target, release: target)
            try check(document.item(withID: dragged.item.id)?.align == destination && document.isDirty)
        }
    }

    private static func cancelDrops() async throws {
        let url = try preset("cancel-drag", """
        [{"type":"staticButton","title":"L1","width":64,"align":"left"},
         {"type":"staticButton","title":"L2","width":64,"align":"left"},
         {"type":"staticButton","title":"R","width":64,"align":"right"}]
        """)
        let document = PresetDocument(fileURL: url)
        let controller = try makeWindow(document, FixtureTouchBar(url), CustomizerState())
        defer { controller.close() }
        let window = try require(controller.window)
        try await refresh(window)
        let view = try require(window.contentView)
        let app = try application(in: view)
        let original = document.items
        let legal = app.convert(NSPoint(x: 4, y: app.bounds.midY), to: nil)
        let sidebar = NSPoint(x: legal.x, y: view.bounds.midY)
        let outside = NSPoint(x: legal.x, y: -100)
        try check(view.bounds.contains(view.convert(sidebar, from: nil)) && sidebar.x < 240)
        try check(!view.bounds.contains(view.convert(outside, from: nil)))
        try check(!app.bounds.contains(app.convert(sidebar, from: nil)))
        for release in [sidebar, outside] {
            drag(try tile(in: view, title: "R"), in: window, through: legal, release: release)
            try await refresh(window)
            try check(document.items == original && !document.isDirty && !window.isDocumentEdited)
        }
    }

    private static func drag(_ tile: LivePreviewItemView, in window: NSWindow,
                             through point: NSPoint, release: NSPoint) {
        let start = tile.convert(NSPoint(x: tile.bounds.midX, y: tile.bounds.midY), to: nil)
        tile.mouseDown(with: event(.leftMouseDown, at: start, in: window))
        tile.mouseDragged(with: event(.leftMouseDragged, at: point, in: window))
        tile.mouseUp(with: event(.leftMouseUp, at: release, in: window))
    }

    private static func draftDuration() async throws {
        let url = try preset("durations", """
        [{"type":"pomodoro","title":"Legacy","workTime":1e20},{"type":"pomodoro","workTime":125.9}]
        """)
        let document = PresetDocument(fileURL: url)
        let runtime = try FixtureTouchBar(url)
        let controller = try makeWindow(document, runtime, CustomizerState())
        defer { controller.close() }
        let window = try require(controller.window)
        try await refresh(window)
        let legacy = try tile(in: window.contentView, title: "Legacy")
        try check(legacy.status == .draft)
        let normal = try require(descendants(of: window.contentView).compactMap { $0 as? LivePreviewItemView }
            .first { $0.item.id == document.items[1].id })
        try check(descendants(of: normal).compactMap { $0 as? NSButton }.contains { $0.attributedTitle.string == "02:05" })
        let raw = try JSONValue.parse(#"{"type":"pomodoro","workTime":1e20}"#)
        try document.applyJSON(require(raw.objectValue), to: normal.item.id)
        try check(document.validate() == nil)
        try await refresh(window)
        let edited = try require(descendants(of: window.contentView).compactMap { $0 as? LivePreviewItemView }
            .first { $0.item.id == normal.item.id })
        try check(edited.status == .draft)
        try check(descendants(of: edited).compactMap { $0 as? NSButton }.contains { $0.attributedTitle.string == "25:00" })
    }

    private static func hardwareLayout() async throws {
        let surface = TouchBarPreviewSurface()
        let stage = CGRect(x: 0, y: 0, width: 1200, height: 120)
        let virtualOLED = CGRect(x: 0, y: 0, width: 1085, height: 30)
        let virtual = TouchBarGeometry(panelWidth: 1085, mounted: virtualOLED, mode: .current)
        surface.place(in: stage, geometry: virtual, scale: 1, expanded: false, showsZones: false)
        let touchID = try require(surface.subviews.first { String(describing: type(of: $0)) == "TouchIDCapView" })
        try check(surface.bounds.width == 1085 && surface.application.frame.width == 1085)
        try check(touchID.isHidden)

        let physicalOLED = CGRect(x: 0, y: 0, width: 1004, height: 30)
        let physical = TouchBarGeometry(panelWidth: 1004, mounted: physicalOLED, mode: .current)
        surface.place(in: stage, geometry: physical, scale: 1, expanded: false, showsZones: false)
        try check(surface.bounds.width == 1148 && surface.application.frame.minX == 80)
        try check(surface.application.frame.width == 1004 && !touchID.isHidden)
        try check(touchID.frame.minX == 1100 && touchID.frame.width == 48)
        print("Host panel size: \(MTMRMainTouchBarSize())")
    }

    private static func clockBorder() async throws {
        let url = try preset("clock", #"[{"type":"timeButton","title":"Clock"}]"#)
        let document = PresetDocument(fileURL: url)
        let runtime = try FixtureTouchBar(url)
        let clock = TimeTouchBarItem(identifier: .init("clock"), formatTemplate: "HH:mm")
        runtime.roots = [clock]
        let controller = try makeWindow(document, runtime, CustomizerState())
        defer { controller.close() }
        let window = try require(controller.window)
        try await refresh(window)
        let before = try tile(in: window.contentView, title: "Clock")
        let selector = NSSelectorFromString("handleMenuToggleBordered:")
        let menu = before.menu(for: event(.rightMouseDown, at: .zero, in: window))
        let entry = try require(menu?.items.first { $0.action == selector })
        try check(before.status == .live && entry.state == .off && !clock.isBordered)
        try check(NSApp.sendAction(selector, to: entry.target, from: entry))
        try check(document.items.first?.json["bordered"] == .bool(true))
        try document.save()
        let data = try Data(contentsOf: url)
        let definitions = try require(data.barItemDefinitions())
        guard case .bordered(true)? = definitions.first?.additionalParameters[.bordered] else {
            throw Failure(description: "runtime decoder lost the explicit border")
        }

        // Reopen the saved preset and render its stored border even without a mounted clock.
        runtime.roots = []
        try runtime.reload(url)
        controller.revertPreset()
        try await refresh(window)
        let after = try tile(in: window.contentView, title: "Clock")
        let reloaded = after.menu(for: event(.rightMouseDown, at: .zero, in: window))?.items.first { $0.action == selector }
        try check(reloaded?.state == .on)
        try check(descendants(of: after).compactMap { $0 as? NSButton }.contains { $0.isBordered })
    }

    private static func previewStatuses() async throws {
        let suite = "local.MTMR.PreviewStatusTests.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suite))
        defaults.set(false, forKey: "com.toxblh.mtmr.preview.showHiddenItems")
        defer { defaults.removePersistentDomain(forName: suite) }

        let url = try preset("preview-status", """
        [{"type":"staticButton","title":"Live","matchAppId":"example.app","width":64},
         {"type":"staticButton","title":"Conditional","matchAppId":"example.app"},
         {"type":"staticButton","title":"Editable","matchAppId":"example.app"}]
        """)
        let document = PresetDocument(fileURL: url)
        let runtime = try FixtureTouchBar(url)
        let button = CustomButtonTouchBarItem(identifier: .init("preview-status"), title: "Live")
        runtime.roots = [button]
        let state = CustomizerState()
        let controller = try makeWindow(document, runtime, state)
        defer { controller.close() }
        let window = try require(controller.window)
        window.contentViewController = NSHostingController(rootView:
            CustomizerView(document: document, state: state).appLocalized()
                .defaultAppStorage(defaults)
        )
        var edited = try require(document.items.last)
        edited.json["title"] = .string("Draft")
        document.update(edited)
        try await refresh(window)

        let conditional = try tile(in: window.contentView, title: "Conditional")
        let draft = try tile(in: window.contentView, title: "Draft")
        let live = try tile(in: window.contentView, title: "Live")
        try check(conditional.status == .conditionalHidden("example.app") && conditional.isHidden && conditional.preferredWidth == 0)
        try check(conditional.toolTip?.contains("example.app") == true)
        try check(draft.status == .draft && !draft.isHidden && draft.preferredWidth > 0)
        try check(draft.toolTip?.contains("draft preview") == true)
        let liveTooltip = try require(live.toolTip)
        try check(live.status == .live && !live.isHidden && live.preferredWidth == 64)

        button.title = ""
        button.hidesEmptyOutput = true
        try await refresh(window)
        try check(live.status == .hiddenEmptyOutput && live.isHidden && live.preferredWidth == 0)
        try check(live.toolTip?.contains("output is empty") == true)

        state.selection = live.item.id
        try await refresh(window)
        try check(live.status == .hiddenEmptyOutput && !live.isHidden && live.preferredWidth > 0)
        state.selection = nil
        try await refresh(window)
        try check(live.isHidden && live.preferredWidth == 0)

        button.title = "Recovered"
        button.hidesEmptyOutput = false
        try await refresh(window)
        try check(live.status == .live && !live.isHidden && live.preferredWidth == 64 && live.toolTip == liveTooltip)
    }

    private static func descendants(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private static func event(_ kind: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0.5)!
    }
}
