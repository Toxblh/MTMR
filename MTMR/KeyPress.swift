//
//  KeyPress.swift
//  MTMR
//
//  Created by Anton Palgunov on 17/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation


func KeyPress (keyCode: CGKeyCode) {
    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)

    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
}

func ESCKeyPress() {
    KeyPress(keyCode: 53)
}

func BrightnessUpPress() {
    KeyPress(keyCode: 107)
}

func BrightnessDownPress() {
    KeyPress(keyCode: 113)
}
