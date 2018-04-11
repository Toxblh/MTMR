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
        case .staticImageButton(title: _):
            return "com.toxblh.mtmr.staticImageButton."
        case .appleScriptTitledButton(source: _):
            return "com.toxblh.mtmr.appleScriptButton."
        case .timeButton(formatTemplate: _):
            return "com.toxblh.mtmr.timeButton."
        case .flexSpace():
            return "NSTouchBarItem.Identifier.flexibleSpace"
        }
    }
    
}

class TouchBarController: NSObject, NSTouchBarDelegate {

    static let shared = TouchBarController()
    
    let touchBar = NSTouchBar()
    
    var items: [NSTouchBarItem.Identifier: BarItemDefinition] = [:]
    
    private override init() {
        super.init()
        SupportedTypesHolder.sharedInstance.register(typename: "exitTouchbar", item: .staticButton(title: "exit"), action: .custom(closure: { [weak self] in
            self?.dismissTouchBar()
        }))
        
        loadItems()
        
        touchBar.delegate = self
        self.presentTouchBar()
    }
    
    func loadItems() {
        let appSupportDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR")
        let presetPath = appSupportDirectory.appending("/items.json")
        if !FileManager.default.fileExists(atPath: presetPath),
            let defaultPreset = Bundle.main.path(forResource: "defaultPreset", ofType: "json") {
            try? FileManager.default.createDirectory(atPath: appSupportDirectory, withIntermediateDirectories: true, attributes: nil)
            try? FileManager.default.copyItem(atPath: defaultPreset, toPath: presetPath)
        }
        let jsonData = try? Data(contentsOf: URL(fileURLWithPath: presetPath))
        let jsonItems = jsonData?.barItemDefinitions() ?? [BarItemDefinition(type: .staticButton(title: "bad preset"), action: .none, additionalParameters: [])]
        
        for item in jsonItems {
            let identifierString = item.type.identifierBase.appending(UUID().uuidString)
            let identifier = item.type == ItemType.flexSpace()
                ? NSTouchBarItem.Identifier.flexibleSpace
                : NSTouchBarItem.Identifier(identifierString)
            items[identifier] = item
            touchBar.defaultItemIdentifiers += [identifier]
        }
    }

    func setupControlStripPresence() {
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
        guard let item = self.items[identifier] else {
            return nil
        }
        let action = self.action(forItem: item)
        var barItem: NSTouchBarItem!
        switch item.type {
        case .staticButton(title: let title):
            barItem = CustomButtonTouchBarItem(identifier: identifier, title: title, onTap: action)
        case .staticImageButton(title: let title, image: let image):
            barItem = CustomButtonTouchBarItem(identifier: identifier, title: title, onTap: action, image: image)
        case .appleScriptTitledButton(source: let source, refreshInterval: let interval):
            barItem = AppleScriptTouchBarItem(identifier: identifier, appleScript: source, interval: interval)
        case .timeButton(formatTemplate: let template):
            barItem = TimeTouchBarItem(identifier: identifier, formatTemplate: template)
        case .flexSpace:
            barItem = nil
        }
        for parameter in item.additionalParameters {
            if case .width(let value) = parameter, let widthBarItem = barItem as? CanSetWidth {
                widthBarItem.setWidth(value: value)
            }
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
            guard let appleScript = NSAppleScript(source: source) else {
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

