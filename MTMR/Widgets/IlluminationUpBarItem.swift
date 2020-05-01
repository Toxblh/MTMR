//
//  illuminationUpBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class IlluminationUpBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "illuminationUp"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.setImage(#imageLiteral(resourceName: "ill_up"))
        self.setTapAction(EventAction().setHidKeyClosure(keycode: NX_KEYTYPE_ILLUMINATION_UP))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

