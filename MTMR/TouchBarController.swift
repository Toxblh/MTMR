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
        case .timeButton(formatTemplate: _):
            return "com.toxblh.mtmr.timeButton."
        case .battery():
            return "com.toxblh.mtmr.battery."
        case .dock():
            return "com.toxblh.mtmr.dock"
        case .volume():
            return "com.toxblh.mtmr.volume"
        case .brightness(refreshInterval: _):
            return "com.toxblh.mtmr.brightness"
        case .weather(interval: _, units: _, api_key: _, icon_type: _):
            return "com.toxblh.mtmr.weather"
        case .currency(interval: _, from: _, to: _):
            return "com.toxblh.mtmr.currency"
        case .inputsource():
            return "com.toxblh.mtmr.inputsource."
        case .music(interval: _):
            return "com.toxblh.mtmr.music."
        case .groupBar(items: _):
            return "com.toxblh.mtmr.groupBar."
        case .nightShift(items: _):
            return "com.toxblh.mtmr.nightShift."
        case .dnd(items: _):
            return "com.toxblh.mtmr.dnd."
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
    var scrollArea: NSCustomTouchBarItem?
    var centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea.".appending(UUID().uuidString))

    var controlStripState: Bool {
        get {
            return UserDefaults.standard.bool(forKey: "com.toxblh.mtmr.settings.showControlStrip")
        }
        set {
            UserDefaults.standard.set(!controlStripState, forKey: "com.toxblh.mtmr.settings.showControlStrip")
        }
    }
    
    var touchbarNeedRefresh: Bool = true
    
    var blacklistAppIdentifiers: [String] = []
    var frontmostApplicationIdentifier: String? {
        get {
            guard let frontmostId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
            return frontmostId
        }
    }
    
    private override init() {
        super.init()
        SupportedTypesHolder.sharedInstance.register(typename: "exitTouchbar", item: .staticButton(title: "exit"), action: .custom(closure: { [weak self] in self?.dismissTouchBar()}), longAction: .none)
        
        SupportedTypesHolder.sharedInstance.register(typename: "close") { _ in
            return (item: .staticButton(title: ""), action: .custom(closure: { [weak self] in
                guard let `self` = self else { return }
                self.reloadPreset(path: self.lastPresetPath)
            }), longAction: .none, parameters: [.width: .width(30), .image: .image(source: (NSImage(named: NSImage.stopProgressFreestandingTemplateName))!)])
        }

        if let blackListed = UserDefaults.standard.stringArray(forKey: "com.toxblh.mtmr.blackListedApps") {
            self.blacklistAppIdentifiers = blackListed
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        reloadStandardConfig()
    }
    
    func createAndUpdatePreset(newJsonItems: [BarItemDefinition]) {
        if let oldBar = self.touchBar {
            minimizeSystemModal(oldBar)
        }
        self.touchBar = NSTouchBar()
        self.jsonItems = newJsonItems
        self.itemDefinitions = [:]
        self.items = [:]
        self.leftIdentifiers = []
        self.centerItems = []
        self.rightIdentifiers = []
        
        loadItemDefinitions(jsonItems: self.jsonItems)
        createItems()
        
        centerItems = centerIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            return items[identifier]
        })
        
        self.centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea.".appending(UUID().uuidString))
        self.scrollArea = ScrollViewItem(identifier: centerScrollArea, items: centerItems)
        
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = []
        touchBar.defaultItemIdentifiers = self.leftIdentifiers + [centerScrollArea] + self.rightIdentifiers
        
        self.updateActiveApp()
    }
    
    @objc func activeApplicationChanged(_ n: Notification) {
        updateActiveApp()
    }
    
    func updateActiveApp() {
        if self.blacklistAppIdentifiers.index(of: self.frontmostApplicationIdentifier!) != nil {
            DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, false)
            self.touchbarNeedRefresh = true
        } else {
            presentTouchBar()
            self.touchbarNeedRefresh = false
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
        touchbarNeedRefresh = true
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
        for (identifier, definition) in self.itemDefinitions {
            self.items[identifier] = self.createItem(forIdentifier: identifier, definition: definition)
        }
    }
    
    @objc func setupControlStripPresence() {
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        let item = NSCustomTouchBarItem(identifier: .controlStripItem)
        item.view = NSButton(image: #imageLiteral(resourceName: "StatusImage"), target: self, action: #selector(presentTouchBar))
        NSTouchBarItem.addSystemTrayItem(item)
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, true)
    }

    func updateControlStripPresence() {
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, true)
    }

    @objc private func presentTouchBar() {
        if touchbarNeedRefresh {
            if self.controlStripState {
                presentSystemModal(touchBar, systemTrayItemIdentifier: .controlStripItem)
            } else {
                presentSystemModal(touchBar, placement: 1, systemTrayItemIdentifier: .controlStripItem)
            }
        }
    }

    @objc private func dismissTouchBar() {
        self.touchbarNeedRefresh = true
        minimizeSystemModal(touchBar)
    }
    
    @objc func resetControlStrip() {
        dismissTouchBar()
        presentTouchBar()
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == centerScrollArea {
            return self.scrollArea
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
        case .staticButton(title: let title):
            barItem = CustomButtonTouchBarItem(identifier: identifier, title: title)
        case .appleScriptTitledButton(source: let source, refreshInterval: let interval):
            barItem = AppleScriptTouchBarItem(identifier: identifier, source: source, interval: interval)
        case .timeButton(formatTemplate: let template):
            barItem = TimeTouchBarItem(identifier: identifier, formatTemplate: template)
        case .battery():
            barItem = BatteryBarItem(identifier: identifier)
        case .dock:
            barItem = AppScrubberTouchBarItem(identifier: identifier)
        case .volume:
            if case .image(let source)? = item.additionalParameters[.image] {
                barItem = VolumeViewController(identifier: identifier, image: source.image)
            } else {
                barItem = VolumeViewController(identifier: identifier)
            }
        case .brightness(refreshInterval: let interval):
            if case .image(let source)? = item.additionalParameters[.image] {
                barItem = BrightnessViewController(identifier: identifier, refreshInterval: interval, image: source.image)
            } else {
                barItem = BrightnessViewController(identifier: identifier, refreshInterval: interval)
            }
        case .weather(interval: let interval, units: let units, api_key: let api_key, icon_type: let icon_type):
            barItem = WeatherBarItem(identifier: identifier, interval: interval, units: units, api_key: api_key, icon_type: icon_type)
        case .currency(interval: let interval, from: let from, to: let to):
            barItem = CurrencyBarItem(identifier: identifier, interval: interval, from: from, to: to)
        case .inputsource():
            barItem = InputSourceBarItem(identifier: identifier)
        case .music(interval: let interval):
            barItem = MusicBarItem(identifier: identifier, interval: interval)
        case .groupBar(items: let items):
            barItem = GroupBarItem(identifier: identifier, items: items)
        case .nightShift():
            barItem = NightShiftBarItem(identifier: identifier)
        case .dnd():
            barItem = DnDBarItem(identifier: identifier)
        }
        
        if let action = self.action(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.tapClosure = action
        }
        if let longAction = self.longAction(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.longTapClosure = longAction
        }
        if case .bordered(let bordered)? = item.additionalParameters[.bordered], let item = barItem as? CustomButtonTouchBarItem {
            item.isBordered = bordered
        }
        if case .background(let color)? = item.additionalParameters[.background], let item = barItem as? CustomButtonTouchBarItem {
            item.backgroundColor = color
        }
        if case .width(let value)? = item.additionalParameters[.width], let widthBarItem = barItem as? CanSetWidth {
            widthBarItem.setWidth(value: value)
        }
        if case .image(let source)? = item.additionalParameters[.image], let item = barItem as? CustomButtonTouchBarItem {
            item.image = source.image
        }
        if case .title(let value)? = item.additionalParameters[.title] {
            if let item = barItem as? GroupBarItem {
                item.collapsedRepresentationLabel = value
            } else if let item = barItem as? CustomButtonTouchBarItem {
                item.title = value
            }
        }
        return barItem
    }

    func action(forItem item: BarItemDefinition) -> (()->())? {
        switch item.action {
        case .hidKey(keycode: let keycode):
            return { HIDPostAuxKey(keycode) }
        case .keyPress(keycode: let keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case .appleScript(source: let source):
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
        case .shellScript(executable: let executable, parameters: let parameters):
            return {
                let task = Process()
                task.launchPath = executable
                task.arguments = parameters
                task.launch()
            }
        case .openUrl(url: let url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                    print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case .custom(closure: let closure):
            return closure
        case .none:
            return nil
        }
    }

    
    func longAction(forItem item: BarItemDefinition) -> (()->())? {
        switch item.longAction {
        case .hidKey(keycode: let keycode):
            return { HIDPostAuxKey(keycode) }
        case .keyPress(keycode: let keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case .appleScript(source: let source):
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
        case .shellScript(executable: let executable, parameters: let parameters):
            return {
                let task = Process()
                task.launchPath = executable
                task.arguments = parameters
                task.launch()
            }
        case .openUrl(url: let url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                    print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case .custom(closure: let closure):
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
        self.view.widthAnchor.constraint(equalToConstant: value).isActive = true
    }
}

extension BarItemDefinition {
    var align: Align {
        if case .align(let result)? = self.additionalParameters[.align] {
            return result
        }
        return .center
    }
}
