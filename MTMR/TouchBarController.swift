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

extension ItemType {

    var identifierBase: String {
        switch self {
        case .staticButton(title: _):
            return "com.toxblh.mtmr.staticButton."
        case .appleScriptTitledButton(source: _):
            return "com.toxblh.mtmr.appleScriptButton."
        case .timeButton(formatTemplate: _):
            return "com.toxblh.mtmr.timeButton."
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
        }
    }

}

extension NSTouchBarItem.Identifier {
    static let controlStripItem = NSTouchBarItem.Identifier("com.toxblh.mtmr.controlStrip")
    static let centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea")
}

class TouchBarController: NSObject, NSTouchBarDelegate {

    static let shared = TouchBarController()

    let touchBar = NSTouchBar()

    var itemDefinitions: [NSTouchBarItem.Identifier: BarItemDefinition] = [:]
    var items: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    var leftIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerItems: [NSTouchBarItem] = []
    var rightIdentifiers: [NSTouchBarItem.Identifier] = []

    private override init() {
        super.init()
        SupportedTypesHolder.sharedInstance.register(typename: "exitTouchbar", item: .staticButton(title: "exit"), action: .custom(closure: { [weak self] in
            self?.dismissTouchBar()
        }))

        createAndUpdatePreset()
    }
    
    func createAndUpdatePreset(jsonItems: [BarItemDefinition]? = nil) {
        var jsonItems = jsonItems
        self.itemDefinitions = [:]
        self.items = [:]
        self.leftIdentifiers = []
        self.centerItems = []
        self.rightIdentifiers = []
        
        if (jsonItems == nil) {
            jsonItems = readConfig()
        }
        loadItemDefinitions(jsonItems: jsonItems!)
        createItems()
        centerItems = self.itemDefinitions.compactMap { (identifier, definition) -> NSTouchBarItem? in
            return definition.align == .center ? items[identifier] : nil
        }
        
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = self.leftIdentifiers + [.centerScrollArea] + self.rightIdentifiers
        self.presentTouchBar()
    }
    
    func readConfig() -> [BarItemDefinition]?  {
        let appSupportDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR")
        let presetPath = appSupportDirectory.appending("/items.json")
        if !FileManager.default.fileExists(atPath: presetPath),
            let defaultPreset = Bundle.main.path(forResource: "defaultPreset", ofType: "json") {
            try? FileManager.default.createDirectory(atPath: appSupportDirectory, withIntermediateDirectories: true, attributes: nil)
            try? FileManager.default.copyItem(atPath: defaultPreset, toPath: presetPath)
        }
        
        let jsonData = presetPath.fileData
        
        return jsonData?.barItemDefinitions() ?? [BarItemDefinition(type: .staticButton(title: "bad preset"), action: .none, additionalParameters: [:])]
    }
    
    func loadItemDefinitions(jsonItems: [BarItemDefinition]) {
        for item in jsonItems {
            let identifierString = item.type.identifierBase.appending(UUID().uuidString)
            let identifier = NSTouchBarItem.Identifier(identifierString)
            itemDefinitions[identifier] = item
            if item.align == .left {
                leftIdentifiers.append(identifier)
            }
            if item.align == .right {
                rightIdentifiers.append(identifier)
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
        item.view = NSButton(image: #imageLiteral(resourceName: "Strip"), target: self, action: #selector(presentTouchBar))
        NSTouchBarItem.addSystemTrayItem(item)
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, true)
    }

    func updateControlStripPresence() {
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, true)
    }

    @objc private func presentTouchBar() {
        NSTouchBar.presentSystemModalFunctionBar(touchBar, placement: 1, systemTrayItemIdentifier: .controlStripItem)
    }

    @objc private func dismissTouchBar() {
        NSTouchBar.minimizeSystemModalFunctionBar(touchBar)
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == .centerScrollArea {
            return ScrollViewItem(identifier: identifier, items: centerItems)
        }

        guard let item = self.items[identifier],
            let definition = self.itemDefinitions[identifier],
            definition.align != .center else {
            return nil
        }
        return item
    }
    
    func createItem(forIdentifier identifier: NSTouchBarItem.Identifier, definition item: BarItemDefinition) -> NSTouchBarItem? {
        let action = self.action(forItem: item)

        var barItem: NSTouchBarItem!
        switch item.type {
        case .staticButton(title: let title):
            barItem = CustomButtonTouchBarItem(identifier: identifier, title: title, onTap: action)
        case .appleScriptTitledButton(source: let source, refreshInterval: let interval):
            barItem = AppleScriptTouchBarItem(identifier: identifier, source: source, interval: interval, onTap: action)
        case .timeButton(formatTemplate: let template):
            barItem = TimeTouchBarItem(identifier: identifier, formatTemplate: template)
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
            barItem = WeatherBarItem(identifier: identifier, interval: interval, units: units, api_key: api_key, icon_type: icon_type, onTap: action)
        case .currency(interval: let interval, from: let from, to: let to):
            barItem = CurrencyBarItem(identifier: identifier, interval: interval, from: from, to: to, onTap: action)
        }
        
        if case .width(let value)? = item.additionalParameters[.width], let widthBarItem = barItem as? CanSetWidth {
            widthBarItem.setWidth(value: value)
        }
        if case .image(let source)? = item.additionalParameters[.image], let item = barItem as? CustomButtonTouchBarItem {
            let button = item.button!
            button.image = source.image
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.bezelColor = .clear
        }
        return barItem
    }

    func action(forItem item: BarItemDefinition) -> ()->() {
        switch item.action {
        case .hidKey(keycode: let keycode):
            return { HIDPostAuxKey(keycode) }
        case .keyPress(keycode: let keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case .appleSctipt(source: let source):
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
//                    print("URL was successfully opened")
                } else {
                    print("error", url)
                }
            }
        case .custom(closure: let closure):
            return closure
        case .none:
            return {}
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
