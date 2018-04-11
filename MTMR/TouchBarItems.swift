//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

extension NSTouchBarItem.Identifier {
    static let controlStripItem = NSTouchBarItem.Identifier("com.toxblh.mtmr.controlStrip")
}

class CustomButtonTouchBarItem: NSCustomTouchBarItem {
    let tapClosure: () -> ()

    init(identifier: NSTouchBarItem.Identifier, title: String, onTap callback: @escaping () -> ()) {
        self.tapClosure = callback
        super.init(identifier: identifier)
        var button = NSButton(title: "", target: nil, action: nil)
        button = NSButton(title: title, target: self, action: #selector(didTapped))
        self.view = button
    }

    init(identifier: NSTouchBarItem.Identifier, title: String, onTap callback: @escaping () -> (), image: NSImage?) {
        self.tapClosure = callback
        super.init(identifier: identifier)
        var button = NSButton(title: "", target: nil, action: nil)
        if ((image) != nil) {
            button = NSButton(title: title, image: image!, target: self, action: #selector(didTapped))
        } else {
            button = NSButton(title: title, target: self, action: #selector(didTapped))
        }
        self.view = button
        button.bezelColor = .clear
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

