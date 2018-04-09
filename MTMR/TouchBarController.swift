//
//  TouchBar.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

@available(OSX 10.12.2, *)
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
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "esc", target: self, action: #selector(handleEsc))
            return item
        case .dismissButton:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "exit", target: self, action: #selector(dismissTouchBar))
            return item

        case .brightUp:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "🔆", target: self, action: #selector(handleBrightUp))
            return item
        case .brightDown:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "🔅", target: self, action: #selector(handleBrightDown))
            return item

        case .volumeDown:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "🔉", target: self, action: #selector(handleVolumeDown))
            return item
        case .volumeUp:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "🔊", target: self, action: #selector(handleVolumeUp))
            return item

        case .prev:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "⏪", target: self, action: #selector(handlePrev))
            return item
        case .play:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "⏯", target: self, action: #selector(handlePlay))
            return item
        case .next:
            let item = NSCustomTouchBarItem(identifier: identifier)
            item.view = NSButton(title: "⏩", target: self, action: #selector(handleNext))
            return item

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

    @objc func handleEsc() {
        let sender = ESCKeyPress()
        sender.send()
    }

    @objc func handleVolumeUp() {
        HIDPostAuxKey(Int(NX_KEYTYPE_SOUND_UP))
    }

    @objc func handleVolumeDown() {
        HIDPostAuxKey(Int(NX_KEYTYPE_SOUND_DOWN))
    }

    @objc func handleBrightDown() {
//        HIDPostAuxKey(Int(NX_KEYTYPE_BRIGHTNESS_DOWN))

        let sender = BrightnessUpPress()
        sender.send()
    }

    @objc func handleBrightUp() {
//        HIDPostAuxKey(Int(NX_KEYTYPE_BRIGHTNESS_UP))

        let sender = BrightnessDownPress()
        sender.send()
    }

    @objc func handlePrev() {
        HIDPostAuxKey(Int(NX_KEYTYPE_PREVIOUS))
    }

    @objc func handlePlay() {
        HIDPostAuxKey(Int(NX_KEYTYPE_PLAY))
    }

    @objc func handleNext() {
        HIDPostAuxKey(Int(NX_KEYTYPE_NEXT))
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
