//
//  TouchBar.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

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
        case .dock(autoResize: _, filter: _):
            return "com.toxblh.mtmr.dock"
        case .volume:
            return "com.toxblh.mtmr.volume"
        case .brightness(refreshInterval: _):
            return "com.toxblh.mtmr.brightness"
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
        case .group(items: _):
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
    var jsonItems: [BarItemDefinition] = []
    var itemDefinitions: [NSTouchBarItem.Identifier: BarItemDefinition] = [:]
    var items: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    var leftIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerItems: [NSTouchBarItem] = []
    var rightIdentifiers: [NSTouchBarItem.Identifier] = []
    var scrollArea: ScrollViewItem?
    var centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea.".appending(UUID().uuidString))

    var blacklistAppIdentifiers: [String] = []
    var frontmostApplicationIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private override init() {
        super.init()
        SupportedTypesHolder.sharedInstance.register(typename: "exitTouchbar", item: .staticButton(title: "exit"), action: .custom(closure: { [weak self] in self?.dismissTouchBar() }), longAction: .none)

        SupportedTypesHolder.sharedInstance.register(typename: "close") { _ in
            (item: .staticButton(title: ""), action: .custom(closure: { [weak self] in
                guard let `self` = self else { return }
                self.reloadPreset(path: self.lastPresetPath)
            }), longAction: .none, parameters: [.width: .width(30), .image: .image(source: (NSImage(named: NSImage.stopProgressFreestandingTemplateName))!)])
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
        }
        touchBar = NSTouchBar()
        jsonItems = newJsonItems
        itemDefinitions = [:]
        items = [:]
        leftIdentifiers = []
        centerItems = []
        rightIdentifiers = []

        loadItemDefinitions(jsonItems: jsonItems)
        createItems()

        centerItems = centerIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })

        centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea.".appending(UUID().uuidString))
        scrollArea = ScrollViewItem(identifier: centerScrollArea, items: centerItems)
        scrollArea?.gesturesEnabled = AppSettings.multitouchGestures

        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = []
        touchBar.defaultItemIdentifiers = leftIdentifiers + [centerScrollArea] + rightIdentifiers

        updateActiveApp()
    }

    @objc func activeApplicationChanged(_: Notification) {
        updateActiveApp()
    }

    func updateActiveApp() {
        if frontmostApplicationIdentifier != nil && blacklistAppIdentifiers.firstIndex(of: frontmostApplicationIdentifier!) != nil {
            dismissTouchBar()
        } else {
            presentTouchBar()
        }
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

    func reloadPreset(path: String) {
        lastPresetPath = path
        let items = path.fileData?.barItemDefinitions() ?? [BarItemDefinition(type: .staticButton(title: "bad preset"), action: .none, longAction: .none, additionalParameters: [:])]
        createAndUpdatePreset(newJsonItems: items)
    }

    func loadItemDefinitions(jsonItems: [BarItemDefinition]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH-mm-ss"
        let time = dateFormatter.string(from: Date())
        for item in jsonItems {
            let identifierString = item.type.identifierBase.appending(time + "--" + UUID().uuidString)
            let identifier = NSTouchBarItem.Identifier(identifierString)
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
        for (identifier, definition) in itemDefinitions {
            items[identifier] = createItem(forIdentifier: identifier, definition: definition)
        }
    }

    @objc func setupControlStripPresence() {
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        let item = NSCustomTouchBarItem(identifier: .controlStripItem)
        item.view = NSButton(image: #imageLiteral(resourceName: "StatusImage"), target: self, action: #selector(presentTouchBar))
        NSTouchBarItem.addSystemTrayItem(item)
        updateControlStripPresence()
    }

    func updateControlStripPresence() {
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, true)
    }

    @objc private func presentTouchBar() {
        if AppSettings.showControlStripState {
            updateControlStripPresence()
            presentSystemModal(touchBar, systemTrayItemIdentifier: .controlStripItem)
        } else {
            presentSystemModal(touchBar, placement: 1, systemTrayItemIdentifier: .controlStripItem)
        }
    }

    @objc private func dismissTouchBar() {
        minimizeSystemModal(touchBar)
        updateControlStripPresence()
    }

    @objc func resetControlStrip() {
        dismissTouchBar()
        presentTouchBar()
    }

    func touchBar(_: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == centerScrollArea {
            return scrollArea
        }

        guard let item = self.items[identifier],
            let definition = self.itemDefinitions[identifier],
            definition.align != .center else {
            return nil
        }
        return item
    }

    func createItem(forIdentifier identifier: NSTouchBarItem.Identifier, definition item: BarItemDefinition) -> NSTouchBarItem? {
        var barItem: NSTouchBarItem!
        switch item.type {
        case let .staticButton(title: title):
            barItem = CustomButtonTouchBarItem(identifier: identifier, title: title)
        case let .appleScriptTitledButton(source: source, refreshInterval: interval):
            barItem = AppleScriptTouchBarItem(identifier: identifier, source: source, interval: interval)
        case let .shellScriptTitledButton(source: source, refreshInterval: interval):
            barItem = ShellScriptTouchBarItem(identifier: identifier, source: source, interval: interval)
        case let .timeButton(formatTemplate: template, timeZone: timeZone, locale: locale):
            barItem = TimeTouchBarItem(identifier: identifier, formatTemplate: template, timeZone: timeZone, locale: locale)
        case .battery:
            barItem = BatteryBarItem(identifier: identifier)
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
        case let .group(items: items):
            barItem = GroupBarItem(identifier: identifier, items: items)
        case .nightShift:
            barItem = NightShiftBarItem(identifier: identifier)
        case .dnd:
            barItem = DnDBarItem(identifier: identifier)
        case let .pomodoro(workTime: workTime, restTime: restTime):
            barItem = PomodoroBarItem(identifier: identifier, workTime: workTime, restTime: restTime)
        case let .network(flip: flip):
            barItem = NetworkBarItem(identifier: identifier, flip: flip)
        case .darkMode:
            barItem = DarkModeBarItem(identifier: identifier)
        }

        if let action = self.action(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.tapClosure = action
        }
        if let longAction = self.longAction(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.longTapClosure = longAction
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
        if case let .title(value)? = item.additionalParameters[.title] {
            if let item = barItem as? GroupBarItem {
                item.collapsedRepresentationLabel = value
            } else if let item = barItem as? CustomButtonTouchBarItem {
                item.title = value
            }
        }
        return barItem
    }

    func action(forItem item: BarItemDefinition) -> (() -> Void)? {
        switch item.action {
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
        switch item.longAction {
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

extension NSCustomTouchBarItem: CanSetWidth {
    func setWidth(value: CGFloat) {
        view.widthAnchor.constraint(equalToConstant: value).isActive = true
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
