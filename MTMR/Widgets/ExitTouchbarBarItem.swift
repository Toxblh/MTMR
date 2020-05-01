//
//  ExitTouchbarBarItem.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/30/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class ExitTouchbarBarItem: CustomButtonTouchBarItem {
    private var timer: Timer!
    
    override class var typeIdentifier: String {
        return "exitTouchbar"
    }

    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: "")
        
        if self.title == "" {
            self.title = "exit"
        }
        
        self.setTapAction(EventAction.init({_ in
            
            TouchBarController.shared.dismissTouchBar()
            
        } ))
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        if self.title == "" {
            self.title = "exit"
        }
        
        self.setTapAction(EventAction.init({_ in
            
            TouchBarController.shared.dismissTouchBar()
            
        } ))
    }
    
}
