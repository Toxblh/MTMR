//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class CustomButtonTouchBarItem: NSCustomTouchBarItem {
    let tapClosure: () -> ()
    private(set) var button: NSButton!

    init(identifier: NSTouchBarItem.Identifier, title: String, onTap callback: @escaping () -> ()) {
        self.tapClosure = callback
        super.init(identifier: identifier)
        button = NSButton(title: title, target: self, action: #selector(didTapped))
        self.view = button
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func didTapped() {
        self.tapClosure()
        let hf: HapticFeedback = HapticFeedback()
        hf.tap(strong: 6)
    }
}

