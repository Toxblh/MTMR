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

struct GenericKeyCombo {
    var keyCode: CGKeyCode
    var modifiers: [String]

    func send() {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = modifiers.reduce(CGEventFlags()) { result, modifier in
            switch modifier.lowercased() {
            case "command": return result.union(.maskCommand)
            case "option", "alternate": return result.union(.maskAlternate)
            case "control": return result.union(.maskControl)
            case "shift": return result.union(.maskShift)
            default: return result
            }
        }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

extension KeyPress {
    func send() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)

        let loc: CGEventTapLocation = .cghidEventTap
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }
}

func HIDPostAuxKey(_ key: Int32) {
    let key = UInt8(key)
    MediaKeys.hidPostAuxKey(key)
}
