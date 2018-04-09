//
//  KeyPress.swift
//  MTMR
//
//  Created by Anton Palgunov on 17/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

protocol KeyPress {
    var keyCode: CGKeyCode { get }
    func send()
}

extension KeyPress {
    func send () {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)

        let loc: CGEventTapLocation = .cghidEventTap
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }
}

struct ESCKeyPress: KeyPress {
    let keyCode: CGKeyCode = 53
}

struct BrightnessUpPress: KeyPress {
    let keyCode: CGKeyCode = 107
}

struct BrightnessDownPress: KeyPress {
    let keyCode: CGKeyCode = 113
}


func doKey(_ key: Int, down: Bool) {
    let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
    let data1 = (key << 16) | ((down ? 0xa : 0xb) << 8)
    
    let ev = NSEvent.otherEvent(
        with: NSEvent.EventType.systemDefined,
        location: NSPoint(x:0.0, y:0.0),
        modifierFlags: flags,
        timestamp: TimeInterval(0),
        windowNumber: 0,
        context: nil,
        // context: 0,
        subtype: 8,
        data1: data1,
        data2: -1
    )
    let cev = ev!.cgEvent!
    cev.post(tap: CGEventTapLocation(rawValue: 0)!)
}

func HIDPostAuxKey(_ key: Int) {
    doKey(key, down: true)
    doKey(key, down: false)
}


//     hidsystem/ev_keymap.h
let NX_KEYTYPE_SOUND_UP   = 0
let NX_KEYTYPE_SOUND_DOWN = 1

let NX_KEYTYPE_BRIGHTNESS_UP    = 2
let NX_KEYTYPE_BRIGHTNESS_DOWN  = 3

let NX_KEYTYPE_PLAY       = 16
let NX_KEYTYPE_NEXT       = 17
let NX_KEYTYPE_PREVIOUS   = 18




