//
//  EscapeBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class EscapeBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "escape"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.title = "escape"
        self.setTapAction(EventAction().setKeyPressClosure(keycode: 53))
        self.align = .left
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
