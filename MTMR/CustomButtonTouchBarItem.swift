//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class CustomButtonTouchBarItem: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    private let tapClosure: () -> ()?
    private let longTapClosure: () -> ()?
    private(set) var button: NSButton!
    
    private var singleClick: NSClickGestureRecognizer!
    private var longClick: NSPressGestureRecognizer!

    init(identifier: NSTouchBarItem.Identifier, title: String, onTap callback: @escaping () -> (), onLongTap callbackLong: @escaping () -> (), bezelColor: NSColor? = .clear) {
        self.tapClosure = callback
        self.longTapClosure = callbackLong
        
        super.init(identifier: identifier)
        button = NSButton(title: title, target: self, action: nil)
        
        button.cell = CustomButtonCell(backgroundColor: bezelColor!)
        button.cell?.title = title
        
        button.bezelColor = bezelColor
        self.view = button
        
        longClick = NSPressGestureRecognizer(target: self, action: #selector(handleGestureLong))
        longClick.allowedTouchTypes = .direct
        longClick.delegate = self
        
        singleClick = NSClickGestureRecognizer(target: self, action: #selector(handleGestureSingle))
        singleClick.allowedTouchTypes = .direct
        singleClick.delegate = self
        
        self.view.addGestureRecognizer(longClick)
        self.view.addGestureRecognizer(singleClick)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        if gestureRecognizer == singleClick && otherGestureRecognizer == longClick {
            return false
        }
        return true
    }
    
    @objc func handleGestureSingle(gr: NSClickGestureRecognizer) {
        let hf: HapticFeedback = HapticFeedback()
        switch gr.state {
        case .ended:
            hf.tap(strong: 2)
            self.tapClosure()
            break
        default:
            break
        }
    }
    
    @objc func handleGestureLong(gr: NSPressGestureRecognizer) {
        let hf: HapticFeedback = HapticFeedback()
        switch gr.state {
        case .began:
            if self.longTapClosure != nil {
                hf.tap(strong: 2)
                self.tapClosure()
            } else {
                hf.tap(strong: 6)
                self.longTapClosure()
                print("long click")
            }
            break
        default:
            break
            
        }
    }
}

class CustomButtonCell: NSButtonCell {
    init(backgroundColor: NSColor) {
        super.init(textCell: "")
        if backgroundColor != .clear {
            self.isBordered = true
            self.bezelStyle = .rounded
            self.backgroundColor = backgroundColor
        } else {
            self.isBordered = false
        }

        self.font = NSFont.systemFont(ofSize: 15, weight: .regular )

    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

