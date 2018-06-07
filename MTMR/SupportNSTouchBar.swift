//
//  ExtendNSTouchBar.swift
//  MTMR
//
//  Created by Anton Palgunov on 07/06/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

func presentSystemModal(_ touchBar: NSTouchBar!, systemTrayItemIdentifier identifier: NSTouchBarItem.Identifier!) -> Void {
    if #available(OSX 10.14, *) {
        NSTouchBar.presentSystemModalTouchBar(touchBar, systemTrayItemIdentifier: identifier)
    } else {
        NSTouchBar.presentSystemModalFunctionBar(touchBar, systemTrayItemIdentifier: identifier)
    }
}

func presentSystemModal(_ touchBar: NSTouchBar!, placement: Int64, systemTrayItemIdentifier identifier: NSTouchBarItem.Identifier!) -> Void {
    if #available(OSX 10.14, *) {
        NSTouchBar.presentSystemModalTouchBar(touchBar, placement: placement, systemTrayItemIdentifier: identifier)
    } else {
        NSTouchBar.presentSystemModalFunctionBar(touchBar, placement: placement, systemTrayItemIdentifier: identifier)
    }
}

func minimizeSystemModal(_ touchBar: NSTouchBar!) -> Void {
    if #available(OSX 10.14, *) {
        NSTouchBar.minimizeSystemModalTouchBar(touchBar)
    } else {
        NSTouchBar.minimizeSystemModalFunctionBar(touchBar)
    }
}
