//
//  TouchBar.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class TouchBarController: NSObject, NSTouchBarDelegate {

    static let shared = TouchBarController()
    
    let touchBar = NSTouchBar()
    
    private override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [.escButton, .volumeUp, .volumeDown, .time, .preferences]
        self.presentTouchBar()
    }

    func setupControlStripPresence() {
        DFRSystemModalShowsCloseBoxWhenFrontMost(true)
        let item = NSCustomTouchBarItem(identifier: .controlStripItem)
        item.view = NSButton(image: #imageLiteral(resourceName: "Strip"), target: self, action: #selector(presentTouchBar))
        NSTouchBarItem.addSystemTrayItem(item)
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, true)
    }
    
    func updateControlStripPresence() {
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, true)
    }
    
    @objc private func presentTouchBar() {
        NSTouchBar.presentSystemModalFunctionBar(touchBar, systemTrayItemIdentifier: .controlStripItem)
    }
    
    private func dismissTouchBar() {
        NSTouchBar.minimizeSystemModalFunctionBar(touchBar)
    }
    
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .escButton:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "ESC", target: self, action: #selector(handleEsc))
            return item
        case .volumeDown:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "V-", target: self, action: #selector(handleVolumeDown))
            return item
        case .volumeUp:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "V+", target: self, action: #selector(handleVolumeUp))
            return item
        default:
            return nil
        }
    }
    
    @objc func handleEsc() {
        ESCKeyPress()
    }
    
    @objc func handleVolumeUp() {
        self.volume(directon: "up")
    }
    
    @objc func handleVolumeDown() {
        self.volume(directon: "down")
    }
    
    func volume(directon: String) {
        var myAppleScript = "set volume output volume (output volume of (get volume settings) - 5)"
        
        if (directon == "up") {
            myAppleScript = "set volume output volume (output volume of (get volume settings) + 5)"
        }
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: myAppleScript) {
            let output: NSAppleEventDescriptor = scriptObject.executeAndReturnError(&error)
            
            print(output.stringValue as Any)
            
            if (error != nil) {
                print("error: \(String(describing: error))")
            }
        }
    }
    
    @objc func brightness(directon: String) {
        if (directon == "up") {
            BrightnessUpPress()
            print("BR - Up")
        } else {
            BrightnessDownPress()
            print("BR - Down")
        }
    }
}
