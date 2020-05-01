//
//  PreviousBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class PreviousBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "previous"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.setImage(NSImage(named: NSImage.touchBarRewindTemplateName)!)
        self.setTapAction(EventAction().setHidKeyClosure(keycode: NX_KEYTYPE_PREVIOUS))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

