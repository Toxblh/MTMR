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


extension NSTouchBarItem.Identifier {
    static let controlStripItem = NSTouchBarItem.Identifier("com.toxblh.mtmr.controlStrip")
}

class TouchBarController: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarController()

    var touchBar: NSTouchBar!

    fileprivate var lastPresetPath = ""
    var items: [CustomTouchBarItem] = []
    var basicViewIdentifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollView.".appending(UUID().uuidString))
    var basicView: BasicView?
    var swipeItems: [SwipeItem] = []

    var blacklistAppIdentifiers: [String] = []
    var frontmostApplicationIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private override init() {
        super.init()

        blacklistAppIdentifiers = AppSettings.blacklistedAppIds
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        reloadStandardConfig()
    }

    func createAndUpdatePreset(newItems: [BarItemDefinition]) {
        if let oldBar = self.touchBar {
            minimizeSystemModal(oldBar)
        }
        touchBar = NSTouchBar()
        (items, swipeItems) = getItems(newItems: newItems)

        let leftItems = items.compactMap({ (item) -> CustomTouchBarItem? in
            item.align == .left ? item : nil
        })
        let centerItems = items.compactMap({ (item) -> CustomTouchBarItem? in
            item.align == .center ? item : nil
        })
        let rightItems = items.compactMap({ (item) -> CustomTouchBarItem? in
            item.align == .right ? item : nil
        })
        
        
        let centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea.".appending(UUID().uuidString))
        let scrollArea = ScrollViewItem(identifier: centerScrollArea, items: centerItems)

        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [basicViewIdentifier]
        
        basicView = BasicView(identifier: basicViewIdentifier, items: leftItems + [scrollArea] + rightItems, swipeItems: swipeItems)
        basicView?.legacyGesturesEnabled = AppSettings.multitouchGestures
        
        // it seems that we need to set width only after we added them to the view
        // so lets reset width here
        for item in items {
            item.setWidth(value: item.getWidth())
            if item is CustomButtonTouchBarItem {
                (item as! CustomButtonTouchBarItem).reinstallButton()
            }
        }

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

    func reloadPreset(path: String?) {
        if path != nil {
            lastPresetPath = path!
        }
        
        let items = lastPresetPath.fileData?.barItemDefinitions() ?? [BarItemDefinition(obj: CustomButtonTouchBarItem(title: "bad preset"))]
        createAndUpdatePreset(newItems: items)
    }

    func getItems(newItems: [BarItemDefinition]) -> ([CustomTouchBarItem], [SwipeItem]) {
        var items: [CustomTouchBarItem] = []
        var swipeItems: [SwipeItem] = []
        for item in newItems {
            if item.obj is SwipeItem {
                swipeItems.append(item.obj as! SwipeItem)
            } else {
                items.append(item.obj)
            }
        }
        return (items, swipeItems)
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

    @objc func dismissTouchBar() {
        minimizeSystemModal(touchBar)
        updateControlStripPresence()
    }

    @objc func resetControlStrip() {
        dismissTouchBar()
        presentTouchBar()
    }

    func touchBar(_: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == basicViewIdentifier {
            return basicView
        }

        return nil
    }
}

protocol CanSetWidth {
    func setWidth(value: CGFloat)
}
