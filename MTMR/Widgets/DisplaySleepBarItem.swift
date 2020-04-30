//
//  DisplaySleep.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 4/27/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import Foundation

class DisplaySleepBarItem: CustomButtonTouchBarItem {
    override class var typeIdentifier: String {
        return "displaySleep"
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.title = "☕️"
        self.setTapAction(EventAction().setShellScriptClosure(executable: "/usr/bin/pmset", parameters: ["displaysleepnow"]))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

