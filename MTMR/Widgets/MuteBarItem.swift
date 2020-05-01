//
//  MuteBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class MuteBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "mute"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.setImage(NSImage(named: NSImage.touchBarAudioOutputMuteTemplateName)!)
        self.setTapAction(EventAction().setHidKeyClosure(keycode: NX_KEYTYPE_MUTE))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

