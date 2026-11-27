//
//  TouchBar.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa
import Combine

struct ExactItem {
    let identifier: NSTouchBarItem.Identifier
    let presetItem: BarItemDefinition
}

let appSupportDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR")
let standardConfigPath = appSupportDirectory.appending("/items.json")

extension ItemType {
    var identifierBase: String {
        switch self {
        case .staticButton(title: _):
            return "com.toxblh.mtmr.staticButton."
        case .appleScriptTitledButton(source: _):
            return "com.toxblh.mtmr.appleScriptButton."
        case .shellScriptTitledButton(source: _):
            return "com.toxblh.mtmr.shellScriptButton."
        case .timeButton(formatTemplate: _, timeZone: _, locale: _):
            return "com.toxblh.mtmr.timeButton."
        case .battery:
            return "com.toxblh.mtmr.battery."
        case .cpu(refreshInterval: _):
            return "com.toxblh.mtmr.cpu."
        case .codexToday(refreshInterval: _):
            return "com.toxblh.mtmr.codexToday."
        case .codexQuota(refreshInterval: _):
            return "com.toxblh.mtmr.codexQuota."
        case .dock(autoResize: _, filter: _):
            return "com.toxblh.mtmr.dock"
        case .volume:
            return "com.toxblh.mtmr.volume"
        case .brightness(refreshInterval: _):
            return "com.toxblh.mtmr.brightness"
        case .keyboardBrightness(refreshInterval: _):
            return "com.toxblh.mtmr.keyboardBrightness"
        case .weather(interval: _, units: _, api_key: _, icon_type: _):
            return "com.toxblh.mtmr.weather"
        case .yandexWeather(interval: _):
            return "com.toxblh.mtmr.yandexWeather"
        case .currency(interval: _, from: _, to: _, full: _):
            return "com.toxblh.mtmr.currency"
        case .inputsource:
            return "com.toxblh.mtmr.inputsource."
        case .music(interval: _):
            return "com.toxblh.mtmr.music."
        case .group(items: _, showsIcon: _):
            return "com.toxblh.mtmr.groupBar."
        case .nightShift:
            return "com.toxblh.mtmr.nightShift."
        case .dnd:
            return "com.toxblh.mtmr.dnd."
        case .pomodoro(interval: _):
            return PomodoroBarItem.identifier
        case .network(flip: _):
            return NetworkBarItem.identifier
        case .darkMode:
            return DarkModeBarItem.identifier
        case .sidecar(deviceName: _):
            return "com.toxblh.mtmr.sidecar."
        case .eject(volumes: _):
            return "com.toxblh.mtmr.eject."
        case .bluetoothBattery(device: _):
            return "com.toxblh.mtmr.bluetoothBattery."
        case .airpodsBattery(device: _):
            return "com.toxblh.mtmr.airpodsBattery."
        case .swipe(direction: _, fingers: _, minOffset: _, sourceApple: _, sourceBash: _):
            return "com.toxblh.mtmr.swipe."
        case .upnext(from: _, to: _, maxToShow: _, autoResize: _):
            return "com.connorgmeehan.mtmrup.next."
        }
    }
}

extension NSTouchBarItem.Identifier {
    static let controlStripItem = NSTouchBarItem.Identifier("com.toxblh.mtmr.controlStrip")
}

class TouchBarController: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarController()

    var touchBar: NSTouchBar!

    fileprivate var lastPresetPath = ""
    let layoutChanges = PassthroughSubject<Void, Never>()
    private(set) var appliedRevision: PresetRevision?
    private(set) var isReloadPending = false
    private(set) var generation = 0
    private var sourceIdentifiers: [NSTouchBarItem.Identifier] = []
    private var presentedGroups: [GroupBarItem] = []
    var presentedGroupPath: [Int] { presentedGroups.last?.sourcePath ?? [] }
    var presetURL: URL { URL(fileURLWithPath: lastPresetPath) }
    var jsonItems: [BarItemDefinition] = []
    var itemDefinitions: [NSTouchBarItem.Identifier: BarItemDefinition] = [:]
    var items: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    var leftIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerIdentifiers: [NSTouchBarItem.Identifier] = []
    var rightIdentifiers: [NSTouchBarItem.Identifier] = []
    var basicViewIdentifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollView.".appending(UUID().uuidString))
    var basicView: BasicView?
    var swipeItems: [SwipeItem] = []
    private var isTouchBarPresented = false

    var blacklistAppIdentifiers: [String] = []
    var frontmostApplicationIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private override init() {
        super.init()
        SupportedTypesHolder.sharedInstance.register(typename: "exitTouchbar") { [weak self] _ in
            makeIconButton("close", fallbackTitle: "exit",
                           action: Action(trigger: .singleTap, value: .custom(closure: { self?.dismissTouchBar() })))
        }

        SupportedTypesHolder.sharedInstance.register(typename: "close") { [weak self] _ in
            makeIconButton("close", fallback: NSImage(named: NSImage.stopProgressFreestandingTemplateName),
                           action: Action(trigger: .singleTap, value: .custom(closure: {
                               guard let `self` = self else { return }
                               self.reloadPreset(path: self.lastPresetPath)
                           })),
                           parameters: [.width: .width(30)])
        }

        blacklistAppIdentifiers = AppSettings.blacklistedAppIds

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        reloadStandardConfig()
    }

    func createAndUpdatePreset(newJsonItems: [BarItemDefinition]) {
        if let oldBar = self.touchBar {
            minimizeSystemModal(oldBar)
            isTouchBarPresented = false
        }
        touchBar = NSTouchBar()
        releasePresentedGroup()
        basicView = nil
        items.removeAll()
        swipeItems.removeAll()
        jsonItems = newJsonItems
        itemDefinitions = [:]
        sourceIdentifiers.removeAll()
        leftIdentifiers.removeAll()
        centerIdentifiers.removeAll()
        rightIdentifiers.removeAll()

        loadItemDefinitions(jsonItems: jsonItems)
        
        updateActiveApp()
        layoutChanges.send()
    }
    
    func didItemsChange(prevItems: [NSTouchBarItem.Identifier: NSTouchBarItem], prevSwipeItems: [SwipeItem]) -> Bool {
        let previousItemIdentifiers = Set(prevItems.keys)
        let currentItemIdentifiers = Set(items.keys)
        let previousSwipeIdentifiers = Set(prevSwipeItems.map { $0.identifier })
        let currentSwipeIdentifiers = Set(swipeItems.map { $0.identifier })

        return previousItemIdentifiers != currentItemIdentifiers || previousSwipeIdentifiers != currentSwipeIdentifiers
    }
    
    @discardableResult
    func prepareTouchBar() -> Bool {
        let prevItems = items
        let prevSwipeItems = swipeItems

        createItems()

        let changed = didItemsChange(prevItems: prevItems, prevSwipeItems: prevSwipeItems)

        if !changed {
            // Keep timer-backed items alive while the existing BasicView owns
            // their views. Replacing them here freezes dynamic widgets.
            items = prevItems
            swipeItems = prevSwipeItems
            return false
        }
        
        let centerItems = centerIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })

        let centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea.".appending(UUID().uuidString))
        let scrollArea = ScrollViewItem(identifier: centerScrollArea, items: centerItems)
        
        basicViewIdentifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollView.".appending(UUID().uuidString))

        releasePresentedGroup()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [basicViewIdentifier]

        let leftItems = leftIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })
        let rightItems = rightIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })

        let usesBalancedLayout = centerIdentifiers.contains { identifier in
            guard let definition = itemDefinitions[identifier] else { return false }
            if case .codexToday = definition.type { return true }
            return false
        }
        if usesBalancedLayout {
            basicView = BasicView(
                identifier: basicViewIdentifier,
                leftItems: leftItems,
                centerItem: scrollArea,
                rightItems: rightItems,
                swipeItems: swipeItems
            )
        } else {
            basicView = BasicView(identifier: basicViewIdentifier, items: leftItems + [scrollArea] + rightItems, swipeItems: swipeItems)
        }
        basicView?.legacyGesturesEnabled = AppSettings.multitouchGestures
        return true
    }

    @objc func activeApplicationChanged(_: Notification) {
        updateActiveApp()
    }

    func updateActiveApp() {
        if frontmostApplicationIdentifier != nil && blacklistAppIdentifiers.firstIndex(of: frontmostApplicationIdentifier!) != nil {
            if isTouchBarPresented {
                dismissTouchBar()
            }
        } else {
            let layoutChanged = prepareTouchBar()
            if touchBarContainsAnyItems() {
                if layoutChanged || !isTouchBarPresented {
                    presentTouchBar()
                }
            } else if isTouchBarPresented {
                dismissTouchBar()
            }
        }
    }
    
    func touchBarContainsAnyItems() -> Bool {
        return items.count != 0 || swipeItems.count != 0
    }

    func reloadStandardConfig() {
        let presetPath = standardConfigPath
        if !FileManager.default.fileExists(atPath: presetPath),
            let defaultPreset = Bundle.main.path(forResource: "defaultPreset", ofType: "json") {
            try? FileManager.default.createDirectory(atPath: appSupportDirectory, withIntermediateDirectories: true, attributes: nil)
            try? FileManager.default.copyItem(atPath: defaultPreset, toPath: presetPath)
        }

        reloadPreset(path: presetPath)
    }

    private var pendingReload: DispatchWorkItem?

    /// Coalesces reload requests that arrive in a burst. One save from the customizer produces several
    /// file-watcher events (write, truncate) plus its own explicit reload; without this the system-modal
    /// Touch Bar was rebuilt two or three times per save. Must be called on the main queue.
    func scheduleReload(path: String) {
        enqueueReload(path: path, after: 0.15)
    }

    private func enqueueReload(path: String, after delay: TimeInterval) {
        pendingReload?.cancel()
        if !isReloadPending {
            isReloadPending = true
            appliedRevision = nil
            layoutChanges.send()
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingReload = nil
            self?.reloadPreset(path: path)
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func reloadPreset(path: String) {
        // Replacing the system-modal Touch Bar while a modal session runs (e.g. an AppleScript
        // "Where is <app>?" dialog surfaced when MTMR is activated) crashed AppKit with
        // "NSConcretePointerArray was mutated while being enumerated" in
        // +[NSFunctionRow markActiveFunctionRowsAsDimmed:]. Retry once the modal session has ended.
        if NSApp.modalWindow != nil {
            enqueueReload(path: path, after: 0.5)
            return
        }
        pendingReload?.cancel()
        pendingReload = nil
        isReloadPending = false
        lastPresetPath = path
        let data = path.fileData
        let definitions = data?.barItemDefinitions()
        generation += 1
        appliedRevision = definitions == nil ? nil : data.map { PresetRevision(url: presetURL, data: $0) }
        let items = definitions ?? [BarItemDefinition(type: .staticButton(title: "bad preset"), actions: [], action: .none, legacyLongAction: .none, additionalParameters: [:])]
        createAndUpdatePreset(newJsonItems: items)
    }

    func loadItemDefinitions(jsonItems: [BarItemDefinition]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH-mm-ss"
        let time = dateFormatter.string(from: Date())
        for item in jsonItems {
            let identifierString = item.type.identifierBase.appending(time + "--" + UUID().uuidString)
            let identifier = NSTouchBarItem.Identifier(identifierString)
            sourceIdentifiers.append(identifier)
            itemDefinitions[identifier] = item
            if item.align == .left {
                leftIdentifiers.append(identifier)
            }
            if item.align == .right {
                rightIdentifiers.append(identifier)
            }
            if item.align == .center {
                centerIdentifiers.append(identifier)
            }
        }
    }

    func createItems() {
        let previousItems = items
        let previousSwipeItems = Dictionary(uniqueKeysWithValues: swipeItems.map { ($0.identifier, $0) })
        var nextItems: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
        var nextSwipeItems: [SwipeItem] = []

        for (index, identifier) in sourceIdentifiers.enumerated() {
            guard let definition = itemDefinitions[identifier] else { continue }
            var show = true
            
            if let frontApp = frontmostApplicationIdentifier {
                if case let .matchAppId(regexString)? = definition.additionalParameters[.matchAppId] {
                    let regex = try? NSRegularExpression(pattern: regexString)
                    let range = NSRange(frontApp.startIndex..., in: frontApp)
                    if regex?.firstMatch(in: frontApp, range: range) == nil {
                        show = false
                    }
                }
            }
            
            if show {
                if let previousItem = previousItems[identifier] {
                    nextItems[identifier] = previousItem
                    continue
                }

                if let previousSwipeItem = previousSwipeItems[identifier] {
                    nextSwipeItems.append(previousSwipeItem)
                    continue
                }

                let item = createItem(forIdentifier: identifier, definition: definition)
                (item as? GroupBarItem)?.sourcePath = [index]
                if item is SwipeItem {
                    nextSwipeItems.append(item as! SwipeItem)
                } else {
                    nextItems[identifier] = item
                }
            }
        }

        items = nextItems
        swipeItems = nextSwipeItems
    }

    @objc func setupControlStripPresence() {
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        let item = NSCustomTouchBarItem(identifier: .controlStripItem)
        item.view = NSButton(image: #imageLiteral(resourceName: "StatusImage"), target: self, action: #selector(presentTouchBar))
        NSTouchBarItem.addSystemTrayItem(item)
        updateControlStripPresence()
    }

    func updateControlStripPresence() {
        let showMtmrButtonOnControlStrip = touchBarContainsAnyItems()
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, showMtmrButtonOnControlStrip)
    }

    @objc private func presentTouchBar() {
        if AppSettings.showControlStripState {
            presentSystemModal(touchBar, systemTrayItemIdentifier: .controlStripItem)
        } else {
            presentSystemModal(touchBar, placement: 1, systemTrayItemIdentifier: .controlStripItem)
        }
        isTouchBarPresented = true
        updateControlStripPresence()
        layoutChanges.send()
    }

    func rootItem(at index: Int) -> NSTouchBarItem? {
        guard isTouchBarPresented, sourceIdentifiers.indices.contains(index) else { return nil }
        return items[sourceIdentifiers[index]]
    }

    func presentGroup(_ group: GroupBarItem) {
        var chain = [group]
        while let parent = chain.last?.parentGroup { chain.append(parent) }
        guard let root = chain.last, let index = root.sourcePath.first, rootItem(at: index) === root else { return }
        let previous = presentedGroups.last
        presentedGroups = chain.reversed()
        group.install(on: touchBar)
        if previous !== group { previous?.releaseHardwareItems() }
        presentTouchBar()
    }

    private func releasePresentedGroup() {
        presentedGroups.last?.releaseHardwareItems()
        presentedGroups.removeAll()
    }

    @objc private func dismissTouchBar() {
        // When every item is filtered out by matchAppId, items is empty but
        // the previously presented MTMR bar must still be dismissed.
        minimizeSystemModal(touchBar)
        isTouchBarPresented = false
        if !presentedGroups.isEmpty {
            releasePresentedGroup()
            touchBar.delegate = self
            touchBar.defaultItemIdentifiers = [basicViewIdentifier]
        }
        updateControlStripPresence()
        layoutChanges.send()
    }

    /// Shows the main bar again after a group replaced it. The main bar's items still exist (a group only swaps
    /// the delegate and the identifiers of the shared bar), so they are shown again instead of reloading the
    /// preset, which would rebuild every widget.
    func closeGroup() {
        releasePresentedGroup()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = []
        touchBar.defaultItemIdentifiers = [basicViewIdentifier]
        layoutChanges.send()
    }

    @objc func resetControlStrip() {
        dismissTouchBar()
        updateActiveApp()
    }

    func touchBar(_: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == basicViewIdentifier {
            return basicView
        }

        return nil
    }

    func createItem(forIdentifier identifier: NSTouchBarItem.Identifier, definition item: BarItemDefinition) -> NSTouchBarItem? {
        var barItem: NSTouchBarItem!
        switch item.type {
        case let .staticButton(title: title):
            barItem = CustomButtonTouchBarItem(identifier: identifier, title: title)
        case let .appleScriptTitledButton(source: source, refreshInterval: interval, alternativeImages: alternativeImages):
            barItem = AppleScriptTouchBarItem(identifier: identifier, source: source, interval: interval, alternativeImages: alternativeImages)
        case let .shellScriptTitledButton(source: source, refreshInterval: interval):
            barItem = ShellScriptTouchBarItem(identifier: identifier, source: source, interval: interval)
        case let .timeButton(formatTemplate: template, timeZone: timeZone, locale: locale):
            barItem = TimeTouchBarItem(identifier: identifier, formatTemplate: template, timeZone: timeZone, locale: locale)
        case .battery:
            barItem = BatteryBarItem(identifier: identifier)
        case let .cpu(refreshInterval: refreshInterval):
            barItem = CPUBarItem(identifier: identifier, refreshInterval: refreshInterval)
        case let .codexToday(refreshInterval: refreshInterval):
            barItem = CodexTodayBarItem(identifier: identifier, refreshInterval: refreshInterval)
        case let .codexQuota(refreshInterval: refreshInterval):
            barItem = CodexQuotaBarItem(identifier: identifier, refreshInterval: refreshInterval)
        case let .dock(autoResize: autoResize, filter: regexString):
            if let regexString = regexString {
                guard let regex = try? NSRegularExpression(pattern: regexString, options: []) else {
                    barItem = CustomButtonTouchBarItem(identifier: identifier, title: "Bad regex")
                    break
                }
                barItem = AppScrubberTouchBarItem(identifier: identifier, autoResize: autoResize, filter: regex)
            } else {
                barItem = AppScrubberTouchBarItem(identifier: identifier, autoResize: autoResize)
            }
        case .volume:
            if case let .image(source)? = item.additionalParameters[.image] {
                barItem = VolumeViewController(identifier: identifier, image: source.image)
            } else {
                barItem = VolumeViewController(identifier: identifier)
            }
        case let .brightness(refreshInterval: interval):
            if case let .image(source)? = item.additionalParameters[.image] {
                barItem = BrightnessViewController(identifier: identifier, refreshInterval: interval, image: source.image)
            } else {
                barItem = BrightnessViewController(identifier: identifier, refreshInterval: interval)
            }
        case let .keyboardBrightness(refreshInterval: interval):
            if case let .image(source)? = item.additionalParameters[.image] {
                barItem = KeyboardBrightnessViewController(identifier: identifier, refreshInterval: interval, image: source.image)
            } else {
                barItem = KeyboardBrightnessViewController(identifier: identifier, refreshInterval: interval)
            }
        case let .weather(interval: interval, units: units, api_key: api_key, icon_type: icon_type):
            barItem = WeatherBarItem(identifier: identifier, interval: interval, units: units, api_key: api_key, icon_type: icon_type)
        case let .yandexWeather(interval: interval):
            barItem = YandexWeatherBarItem(identifier: identifier, interval: interval)
        case let .currency(interval: interval, from: from, to: to, full: full):
            barItem = CurrencyBarItem(identifier: identifier, interval: interval, from: from, to: to, full: full)
        case .inputsource:
            barItem = InputSourceBarItem(identifier: identifier)
        case let .music(interval: interval, disableMarquee: disableMarquee):
            barItem = MusicBarItem(identifier: identifier, interval: interval, disableMarquee: disableMarquee)
        case let .group(items: items, showsIcon: showsIcon):
            barItem = GroupBarItem(identifier: identifier, items: items, showsIcon: showsIcon) { [weak self] identifier, definition in
                self?.createItem(forIdentifier: identifier, definition: definition)
            }
        case .nightShift:
            barItem = NightShiftBarItem(identifier: identifier)
        case .dnd:
            barItem = DnDBarItem(identifier: identifier)
        case let .pomodoro(workTime: workTime, restTime: restTime):
            barItem = PomodoroBarItem(identifier: identifier, workTime: workTime, restTime: restTime)
        case let .network(flip: flip, units: units):
            barItem = NetworkBarItem(identifier: identifier, flip: flip, units: units)
        case .darkMode:
            barItem = DarkModeBarItem(identifier: identifier)
        case let .sidecar(deviceName: deviceName):
            barItem = SidecarBarItem(identifier: identifier, deviceName: deviceName)
        case let .eject(volumes: volumes):
            barItem = EjectBarItem(identifier: identifier, volumes: volumes)
        case let .bluetoothBattery(device: device):
            barItem = BluetoothBatteryBarItem(identifier: identifier, address: device, parts: [.main])
        case let .airpodsBattery(device: device):
            barItem = BluetoothBatteryBarItem(identifier: identifier, address: device, parts: [.left, .right, .case_])
        case let .swipe(direction: direction, fingers: fingers, minOffset: minOffset, sourceApple: sourceApple, sourceBash: sourceBash):
            barItem = SwipeItem(identifier: identifier, direction: direction, fingers: fingers, minOffset: minOffset, sourceApple: sourceApple, sourceBash: sourceBash)
        case let .upnext(from: from, to: to, maxToShow: maxToShow, autoResize: autoResize):
            barItem = UpNextScrubberTouchBarItem(identifier: identifier, interval: 60, from: from, to: to, maxToShow: maxToShow, autoResize: autoResize)
        }

        if let action = self.action(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.actions.append(ItemAction(trigger: .singleTap, action))
        }
        if let longAction = self.longAction(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.actions.append(ItemAction(trigger: .longTap, longAction))
        }
        
        if let touchBarItem = barItem as? CustomButtonTouchBarItem {
            for action in item.actions {
                touchBarItem.actions.append(ItemAction(trigger: action.trigger, self.closure(for: action)))
            }
        }
        if case let .bordered(bordered)? = item.additionalParameters[.bordered], let item = barItem as? CustomButtonTouchBarItem {
            item.isBordered = bordered
        }
        if case let .background(color)? = item.additionalParameters[.background], let item = barItem as? CustomButtonTouchBarItem {
            item.backgroundColor = color
        }
        if case let .width(value)? = item.additionalParameters[.width], let widthBarItem = barItem as? CanSetWidth {
            widthBarItem.setWidth(value: value)
        }
        if case let .image(source)? = item.additionalParameters[.image], let item = barItem as? CustomButtonTouchBarItem {
            item.image = source.image
        }
        if case let .image(source)? = item.additionalParameters[.image], let group = barItem as? GroupBarItem {
            group.iconImage = source.image
        }
        if case let .title(value)? = item.additionalParameters[.title] {
            if let item = barItem as? GroupBarItem {
                item.collapsedRepresentationLabel = value
            } else if let item = barItem as? CustomButtonTouchBarItem {
                item.title = value
            }
        }
        return barItem
    }
    
    func closure(for action: Action) -> (() -> Void)? {
        switch action.value {
        case let .hidKey(keycode: keycode):
            return { HIDPostAuxKey(keycode) }
        case let .keyPress(keycode: keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case let .keyCombo(keycode: keycode, modifiers: modifiers):
            return { GenericKeyCombo(keyCode: CGKeyCode(keycode), modifiers: modifiers).send() }
        case let .appleScript(source: source):
            guard let appleScript = source.appleScript else {
                print("cannot create apple script for item \(action)")
                return {}
            }
            return {
                DispatchQueue.appleScriptQueue.async {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                    if let error = error {
                        print("error \(error) when handling \(action) ")
                    }
                }
            }
        case let .shellScript(executable: executable, parameters: parameters):
            return {
                let task = Process()
                task.launchPath = executable
                task.arguments = parameters
                task.launch()
            }
        case let .openUrl(url: url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                        print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case let .custom(closure: closure):
            return closure
        case .none:
            return nil
        }
    }

    func action(forItem item: BarItemDefinition) -> (() -> Void)? {
        switch item.legacyAction {
        case let .hidKey(keycode: keycode):
            return { HIDPostAuxKey(keycode) }
        case let .keyPress(keycode: keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case let .keyCombo(keycode: keycode, modifiers: modifiers):
            return { GenericKeyCombo(keyCode: CGKeyCode(keycode), modifiers: modifiers).send() }
        case let .appleScript(source: source):
            guard let appleScript = source.appleScript else {
                print("cannot create apple script for item \(item)")
                return {}
            }
            return {
                DispatchQueue.appleScriptQueue.async {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                    if let error = error {
                        print("error \(error) when handling \(item) ")
                    }
                }
            }
        case let .shellScript(executable: executable, parameters: parameters):
            return {
                let task = Process()
                task.launchPath = executable
                task.arguments = parameters
                task.launch()
            }
        case let .openUrl(url: url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                        print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case let .custom(closure: closure):
            return closure
        case .none:
            return nil
        }
    }

    func longAction(forItem item: BarItemDefinition) -> (() -> Void)? {
        switch item.legacyLongAction {
        case let .hidKey(keycode: keycode):
            return { HIDPostAuxKey(keycode) }
        case let .keyPress(keycode: keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case let .appleScript(source: source):
            guard let appleScript = source.appleScript else {
                print("cannot create apple script for item \(item)")
                return {}
            }
            return {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("error \(error) when handling \(item) ")
                }
            }
        case let .shellScript(executable: executable, parameters: parameters):
            return {
                let task = Process()
                task.launchPath = executable
                task.arguments = parameters
                task.launch()
            }
        case let .openUrl(url: url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                        print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case let .custom(closure: closure):
            return closure
        case .none:
            return nil
        }
    }
}

protocol CanSetWidth {
    func setWidth(value: CGFloat)
}

extension TouchBarController: RunningTouchBar {
    var panelWidth: CGFloat? {
        let size = MTMRMainTouchBarSize()
        return size.height == TouchBarMetrics.height && size.width > 0 ? size.width : nil
    }

    var presentedBar: NSTouchBar? { isTouchBarPresented ? touchBar : nil }

    var layoutAnchor: NSView? {
        guard isTouchBarPresented else { return nil }
        if let group = presentedGroups.last { return group.layoutAnchor }
        return basicView?.view
    }
}

extension NSCustomTouchBarItem: CanSetWidth {
    func setWidth(value: CGFloat) {
        view.widthAnchor.constraint(equalToConstant: value).isActive = true
    }
}

extension NSPopoverTouchBarItem: CanSetWidth {
    func setWidth(value: CGFloat) {
        view?.widthAnchor.constraint(equalToConstant: value).isActive = true
    }
}

extension BarItemDefinition {
    var align: Align {
        if case let .align(result)? = additionalParameters[.align] {
            return result
        }
        return .center
    }
}
