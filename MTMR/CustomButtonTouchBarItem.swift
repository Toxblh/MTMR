//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class CustomButtonTouchBarItem: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    public var tapClosure: (() -> ())?
    public var longTapClosure: (() -> ())?
    private(set) var button: NSButton!
    
    private var singleClick: NSClickGestureRecognizer!
    private var longClick: NSPressGestureRecognizer!

    init(identifier: NSTouchBarItem.Identifier, title: String, onTap callback: @escaping () -> (), onLongTap callbackLong: @escaping () -> (), bezelColor: NSColor? = .clear) {
        self.tapClosure = callback
        self.longTapClosure = callbackLong
        
        super.init(identifier: identifier)
        installButton(titled: title, bordered: true, backgroundColor: nil)
        
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
    
    var isBordered: Bool = true {
        didSet {
            installButton(titled: self.button.title, bordered: isBordered, backgroundColor: backgroundColor)
        }
    }
    
    var backgroundColor: NSColor? {
        didSet {
            installButton(titled: self.button.title, bordered: isBordered, backgroundColor: backgroundColor)
        }
    }
    
    private func installButton(titled title: String, bordered: Bool, backgroundColor: NSColor?) {
        button = CustomHeightButton(title: title, target: nil, action: nil)
        let cell = CustomButtonCell()
        button.cell = cell
        if let color = backgroundColor {
            cell.isBordered = true
            button.bezelColor = color
            cell.backgroundColor = color
        } else {
            button.isBordered = bordered
            button.bezelStyle = bordered ? .rounded : .inline
        }
        button.title = title
        self.view = button
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
            self.tapClosure?()
            break
        default:
            break
        }
    }
    
    @objc func handleGestureLong(gr: NSPressGestureRecognizer) {
        let hf: HapticFeedback = HapticFeedback()
        switch gr.state {
        case .began:
            if let closure = self.longTapClosure {
                hf.tap(strong: 2)
                closure()
            } else if let closure = self.tapClosure {
                hf.tap(strong: 6)
                closure()
                print("long click")
            }
            break
        default:
            break
            
        }
    }
}

class CustomHeightButton : NSButton {
    
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = 30
        return size
    }
    
}

class CustomButtonCell: NSButtonCell {
    
    init() {
        super.init(textCell: "")
    }
    
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        if !self.isBordered {
            self.setTitle(self.title, withColor: flag ? .lightGray : .white)
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var title: String! {
        get {
            return self.attributedTitle.string
        }

        set (newTitle) {
            setTitle(newTitle, withColor: .white)
        }
    }

    func setTitle(_ title: String, withColor color: NSColor) {
        let attrTitle = NSMutableAttributedString(string: title as String, attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 15, weight: .regular), .baselineOffset: 1])
        attrTitle.setAlignment(.center, range: NSRange(location: 0, length: title.count))

        self.attributedTitle = attrTitle
    }
    
}

