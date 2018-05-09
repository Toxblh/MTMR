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

struct GenericKeyPress: KeyPress {
    var keyCode: CGKeyCode
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

func doKey(_ key: UInt16, down: Bool) {
    let ev = NSEvent.keyEvent(
        with: down ? .keyDown : .keyUp,
        location: .zero,
        modifierFlags: [],
        timestamp: TimeInterval(0),
        windowNumber: 0,
        context: nil,
        characters: "",
        charactersIgnoringModifiers: "",
        isARepeat: false,
        keyCode: key)
    let cev = ev!.cgEvent!
    cev.post(tap: CGEventTapLocation(rawValue: 0)!)
}

func HIDPostAuxKey(_ key: Int32) {
    let key = UInt16(key)
    doKey(key, down: true)
    doKey(key, down: false)
}
