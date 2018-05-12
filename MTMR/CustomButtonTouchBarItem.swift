//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

class CustomButtonTouchBarItem: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    var tapClosure: (() -> ())?
    var longTapClosure: (() -> ())?
    private var button: NSButton!
    
    private var singleClick: NSClickGestureRecognizer!
    private var longClick: NSPressGestureRecognizer!

    init(identifier: NSTouchBarItem.Identifier, title: String) {
        self.attributedTitle = title.defaultTouchbarAttributedString
        
        super.init(identifier: identifier)
        button = CustomHeightButton(title: title, target: nil, action: nil)
        
        longClick = NSPressGestureRecognizer(target: self, action: #selector(handleGestureLong))
        longClick.allowedTouchTypes = .direct
        longClick.delegate = self
        
        singleClick = NSClickGestureRecognizer(target: self, action: #selector(handleGestureSingle))
        singleClick.allowedTouchTypes = .direct
        singleClick.delegate = self
        
        reinstallButton()
        button.attributedTitle = attributedTitle
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var isBordered: Bool = true {
        didSet {
            reinstallButton()
        }
    }
    
    var backgroundColor: NSColor? {
        didSet {
            reinstallButton()
        }
    }
    
    var title: String {
        get {
            return self.attributedTitle.string
        }
        set {
            self.attributedTitle = newValue.defaultTouchbarAttributedString
        }
    }
    
    var attributedTitle: NSAttributedString {
        didSet {
            self.button?.imagePosition = attributedTitle.length > 0 ? .imageLeading : .imageOnly
            self.button?.attributedTitle = attributedTitle
        }
    }
    
    var image: NSImage? {
        didSet {
            button.image = image
        }
    }
    
    private func reinstallButton() {
        let title = button.attributedTitle
        let image = button.image
        let cell = CustomButtonCell(parentItem: self)
        button.cell = cell
        if let color = backgroundColor {
            cell.isBordered = true
            button.bezelColor = color
            cell.backgroundColor = color
        } else {
            button.isBordered = isBordered
            button.bezelStyle = isBordered ? .rounded : .inline
        }
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.attributedTitle = title
        self.button?.imagePosition = title.length > 0 ? .imageLeading : .imageOnly
        button.image = image
        self.view = button
        
        self.view.addGestureRecognizer(longClick)
        self.view.addGestureRecognizer(singleClick)
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
    weak var parentItem: CustomButtonTouchBarItem?
    
    init(parentItem: CustomButtonTouchBarItem) {
        super.init(textCell: "")
        self.parentItem = parentItem
    }
    
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        if !self.isBordered {
            if flag {
                self.setAttributedTitle(self.attributedTitle, withColor: .lightGray)
            } else if let parentItem = self.parentItem {
                self.attributedTitle = parentItem.attributedTitle
            }
        }
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAttributedTitle(_ title: NSAttributedString, withColor color: NSColor) {
        let attrTitle = NSMutableAttributedString(attributedString: title)
        attrTitle.addAttributes([.foregroundColor: color], range: NSRange(location: 0, length: attrTitle.length))
        self.attributedTitle = attrTitle
    }
    
}

extension String {
    var defaultTouchbarAttributedString: NSAttributedString {
        let attrTitle = NSMutableAttributedString(string: self, attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 15, weight: .regular), .baselineOffset: 1])
        attrTitle.setAlignment(.center, range: NSRange(location: 0, length: self.count))
        return attrTitle
    }
}

