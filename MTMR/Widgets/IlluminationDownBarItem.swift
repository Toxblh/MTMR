//
//  illuminationDownBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class IlluminationDownBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "illuminationDown"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.setImage(#imageLiteral(resourceName: "ill_down"))
        self.setTapAction(EventAction().setHidKeyClosure(keycode: NX_KEYTYPE_ILLUMINATION_DOWN))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

