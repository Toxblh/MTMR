//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

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

class CustomButtonTouchBarItem: NSCustomTouchBarItem {
    let tapClosure: (NSCustomTouchBarItem) -> ()
    
    init(identifier: NSTouchBarItem.Identifier, title: String, onTap callback: @escaping (NSCustomTouchBarItem) -> ()) {
        self.tapClosure = callback
        super.init(identifier: identifier)
        self.view = NSButton(title: title, target: self, action: #selector(didTapped))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func didTapped() {
        self.tapClosure(self)
    }
}

