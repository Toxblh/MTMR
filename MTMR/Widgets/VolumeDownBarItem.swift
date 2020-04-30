//
//  volumeDownBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class VolumeDownBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "volumeDown"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.setImage(NSImage(named: NSImage.touchBarVolumeDownTemplateName)!)
        self.setTapAction(EventAction().setHidKeyClosure(keycode: NX_KEYTYPE_SOUND_DOWN))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

