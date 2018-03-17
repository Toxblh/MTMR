//
//  WindowController.swift
//  MTMR
//
//  Created by Anton Palgunov on 16/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

fileprivate extension NSTouchBar.CustomizationIdentifier {
    static let touchBar = NSTouchBar.CustomizationIdentifier("com.MTMR.touchBar")
}

fileprivate extension NSTouchBarItem.Identifier {
    static let popover = NSTouchBarItem.Identifier("com.MTMR.TouchBarItem.popover")
    static let fontStyle = NSTouchBarItem.Identifier("com.MTMR.TouchBarItem.fontStyle")
    static let popoverSlider = NSTouchBarItem.Identifier("com.MTMR.popoverBar.slider")
}

class WindowController: NSWindowController, NSToolbarDelegate {
    let FontSizeToolbarItemID = "FontSize"
    let FontStyleToolbarItemID = "FontStyle"
    let DefaultFontSize : Int = 18
}

