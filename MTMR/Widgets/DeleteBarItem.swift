//
//  DeleteBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class DeleteBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "delete"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        print("DeleteBarItem.init")
        self.title = "del"
        self.setTapAction(EventAction().setKeyPressClosure(keycode: 117))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
