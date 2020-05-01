//
//  BrightnessUpBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class BrightnessUpBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "brightnessUp"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.setImage(#imageLiteral(resourceName: "brightnessUp"))
        self.setTapAction(EventAction().setKeyPressClosure(keycode: 144))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

