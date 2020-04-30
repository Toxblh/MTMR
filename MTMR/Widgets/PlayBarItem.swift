//
//  PlayBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class PlayBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "play"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.setImage(NSImage(named: NSImage.touchBarPlayPauseTemplateName)!)
        self.setTapAction(EventAction().setHidKeyClosure(keycode: NX_KEYTYPE_PLAY))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

