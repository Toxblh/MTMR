//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

@available(OSX 10.12.2, *)
extension NSTouchBarItem.Identifier {
    static let escButton = NSTouchBarItem.Identifier("com.toxblh.mtmr.escButton")
    static let dismissButton = NSTouchBarItem.Identifier("com.toxblh.mtmr.dismissButton")
    
    // Volume
    static let volumeUp = NSTouchBarItem.Identifier("com.toxblh.mtmr.volumeUp")
    static let volumeDown = NSTouchBarItem.Identifier("com.toxblh.mtmr.volumeDown")
    
    // Brightness
    static let brightUp = NSTouchBarItem.Identifier("com.toxblh.mtmr.brightUp")
    static let brightDown = NSTouchBarItem.Identifier("com.toxblh.mtmr.brightDown")
    
    // Music
    static let prev = NSTouchBarItem.Identifier("com.toxblh.mtmr.prev")
    static let next = NSTouchBarItem.Identifier("com.toxblh.mtmr.next")
    static let play = NSTouchBarItem.Identifier("com.toxblh.mtmr.play")
    
    // Plugins
    static let sleep = NSTouchBarItem.Identifier("com.toxblh.mtmr.sleep")
    static let weather = NSTouchBarItem.Identifier("com.toxblh.mtmr.weather")
    static let time = NSTouchBarItem.Identifier("com.toxblh.mtmr.time")
    static let battery = NSTouchBarItem.Identifier("com.toxblh.mtmr.battery")
    static let nowPlaying = NSTouchBarItem.Identifier("com.toxblh.mtmr.nowPlaying")
    
    static let controlStripItem = NSTouchBarItem.Identifier("com.toxblh.mtmr.controlStrip")
}
