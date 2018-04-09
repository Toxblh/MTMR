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
    
    var timer = Timer()
    var timeButton: NSButton = NSButton()
    
    private override init() {
        super.init()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            .escButton,
            .dismissButton,
            
            .brightDown,
            .brightUp,
            
            .prev,
            .play,
            .next,
            
            .sleep,
            .weather,
            
            .volumeDown,
            .volumeUp,
            .battery,
            .time,
        ]
        self.presentTouchBar()
    }

    func setupControlStripPresence() {
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        let item = NSCustomTouchBarItem(identifier: .controlStripItem)
        item.view = NSButton(image: #imageLiteral(resourceName: "Strip"), target: self, action: #selector(presentTouchBar))
        NSTouchBarItem.addSystemTrayItem(item)
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, true)
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(self.updateTime), userInfo: nil, repeats: true)
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
        switch identifier {
        case .escButton:
            return CustomButtonTouchBarItem(identifier: identifier, title: "esc", key: ESCKeyPress())
        case .dismissButton:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "exit", target: self, action: #selector(dismissTouchBar))
            return item
            
        case .brightUp:
            return CustomButtonTouchBarItem(identifier: identifier, title: "🔆", key: BrightnessUpPress())
        case .brightDown:
            return CustomButtonTouchBarItem(identifier: identifier, title: "🔅", key: BrightnessDownPress())

        case .volumeDown:
            return CustomButtonTouchBarItem(identifier: identifier, title: "🔉", HIDKeycode: NX_KEYTYPE_SOUND_DOWN)
        case .volumeUp:
            return CustomButtonTouchBarItem(identifier: identifier, title: "🔊", HIDKeycode: NX_KEYTYPE_SOUND_UP)
 
        case .prev:
            return CustomButtonTouchBarItem(identifier: identifier, title: "⏪", HIDKeycode: NX_KEYTYPE_PREVIOUS)
        case .play:
            return CustomButtonTouchBarItem(identifier: identifier, title: "⏯", HIDKeycode: NX_KEYTYPE_PLAY)
        case .next:
            return CustomButtonTouchBarItem(identifier: identifier, title: "⏩", HIDKeycode: NX_KEYTYPE_NEXT)
    
        case .time:
            let item = NSCustomTouchBarItem(identifier: identifier)
            timeButton = NSButton(title: self.getCurrentTime(), target: self, action: nil)
            item.view = timeButton
            return item
            
        default:
            return nil
        }
    }
    
    func getCurrentTime() -> String  {
        let date = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("HH:mm")
        let timestamp = dateFormatter.string(from: date)
        return timestamp
    }
    
    @objc func updateTime() {
        timeButton.title = getCurrentTime()
    }
    
//    func getBattery() {
//        var error: NSDictionary?
//        if let scriptObject = NSAppleScript(source: <#T##String#>) {
//            if let output: NSAppleEventDescriptor = scriptObject.executeAndReturnError(
//                &error) {
//                print(output.stringValue)
//            } else if (error != nil) {
//                print("error: \(error)")
//            }
//        }
//    }

}

extension CustomButtonTouchBarItem {
    convenience init(identifier: NSTouchBarItem.Identifier, title: String, HIDKeycode: Int) {
        self.init(identifier: identifier, title: title) { _ in
            HIDPostAuxKey(HIDKeycode)
        }
    }
    convenience init(identifier: NSTouchBarItem.Identifier, title: String, key: KeyPress) {
        self.init(identifier: identifier, title: title) { _ in
            key.send()
        }
    }
}
