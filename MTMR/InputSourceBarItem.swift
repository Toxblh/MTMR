//
//  InputSourceBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 22.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class InputSourceBarItem: NSCustomTouchBarItem {
    private(set) var button: NSButton!
    fileprivate var notificationCenter: CFNotificationCenter
    var lastLang: String!
    
    override init(identifier: NSTouchBarItem.Identifier) {
        notificationCenter = CFNotificationCenterGetDistributedCenter();
        super.init(identifier: identifier)
        
        button = NSButton(title: " ", target: self, action: nil)

        self.view = button
        
        observeIputSourceChangedNotification();
        
        textInputSourceDidChange()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc public func textInputSourceDidChange() {
        let currentSource = TISCopyCurrentKeyboardInputSource().takeUnretainedValue()
        let ptrID = TISGetInputSourceProperty(currentSource as TISInputSource, kTISPropertyInputSourceID)
        let ID = unsafeBitCast(ptrID, to: CFString.self)
        
        switch String(ID) {
        case "com.apple.keylayout.RussianWin":
            self.button.title = "RU"
            break
        case "com.apple.keylayout.US":
            self.button.title = "US"
            break
        default:
            self.button.title = String(ID)
        }
//        print(ID)
    }
    
//    private func getInputSource() -> String {
//        let keyboard = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
//        let keyboardString = String(describing: keyboard)
//        let range = keyboardString.range(of: "KB Layout: ", options: .literal, range: keyboardString.startIndex..<keyboardString.endIndex)!
//        let startingKeyboard = range.upperBound
//        let theKeyboardLayout = keyboardString[startingKeyboard ..< keyboardString.endIndex]
//        print("theKeyboardLayout ", theKeyboardLayout)
//        return String(theKeyboardLayout)
//    }

    @objc public func observeIputSourceChangedNotification(){
        let callback: CFNotificationCallback = { center, observer, name, object, info in
            let mySelf = Unmanaged<InputSourceBarItem>.fromOpaque(observer!).takeUnretainedValue()
            mySelf.textInputSourceDidChange()
        }
        
        CFNotificationCenterAddObserver(notificationCenter,
                                        UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                        callback,
                                        kTISNotifySelectedKeyboardInputSourceChanged,
                                        nil,
                                        .deliverImmediately)
    }
}


