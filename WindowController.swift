//
//  WindowController.swift
//  MTMR
//
//  Created by Anton Palgunov on 17/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class WindowController: NSWindowController {
    
    func volume(directon: String) {
        var myAppleScript = "set volume output volume (output volume of (get volume settings) - 5)"
        
        if (directon == "up") {
            myAppleScript = "set volume output volume (output volume of (get volume settings) + 5)"
        }
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: myAppleScript) {
            if let output: NSAppleEventDescriptor = scriptObject.executeAndReturnError(
                &error) {
                print(output.stringValue as Any)
            } else if (error != nil) {
                print("error: \(String(describing: error))")
            }
        }
    }
    
    func brightness(directon: String) {
        let CodeUp: UInt16 = 107
        let CodeDown: UInt16 = 113
        let src = CGEventSource(stateID: .hidSystemState)

        let upd = CGEvent(keyboardEventSource: src, virtualKey: CodeUp, keyDown: true)
        let upu = CGEvent(keyboardEventSource: src, virtualKey: CodeUp, keyDown: false)
        let downd = CGEvent(keyboardEventSource: src, virtualKey: CodeDown, keyDown: true)
        let downu = CGEvent(keyboardEventSource: src, virtualKey: CodeDown, keyDown: false)

        let loc = CGEventTapLocation.cghidEventTap

        if (directon == "up") {
            upd?.post(tap: loc)
            upu?.post(tap: loc)
            print(CodeUp)
        } else {
            downd?.post(tap: loc)
            downu?.post(tap: loc)
            print(CodeDown)
        }
    }
    
    
    @IBAction func brightUp(_ sender: Any) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        brightness(directon: "up")
    }
    
    @IBAction func brightDown(_ sender: Any) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        brightness(directon: "down")
    }
    
    
    @IBAction func volumeUp(_ sender: Any) {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now);
        self.volume(directon: "up")
    }
    
    @IBAction func volumeDown(_ sender: Any) {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        self.volume(directon: "down")
    }
    
    @IBOutlet weak var timeLabel: NSTextField!
    
    override func windowDidLoad() {
        super.windowDidLoad()
    
    }
}
