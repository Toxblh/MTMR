//
//  BrightnessDownBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class BrightnessDownBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "brightnessDown"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.setImage(#imageLiteral(resourceName: "brightnessDown"))
        self.setTapAction(EventAction().setKeyPressClosure(keycode: 145))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

