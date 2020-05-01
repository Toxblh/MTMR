//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

enum Align: String, Decodable {
    case left
    case center
    case right
}

// CustomTouchBarItem is a base class for all widgets
// This class provides some basic parameter parsing (width, align)
// To implement a new class:
// 1. Derive your class from CustomTouchBarItem (for static) or CustomButtonTouchBarItem (for buttons)
// 2. Override class var typeIdentifier with your object identificator
// 3. Override init(from decoder: Decoder) and read all custom json params you need
// 4. Don't forget to call super.init(identifier: CustomTouchBarItem.createIdentifier(type)) in the init() function
// 5. Add your new class to BarItemDefinition.types in ItemParsing.swift
//
// Good example is PomodoroBarItem
//
// If you want to inherid from some other NS class (NSSlider or NSPopoverTouchBarItem or other) then
// look into GroupBarItem and BrightnessViewController

class CustomTouchBarItem: NSCustomTouchBarItem, Decodable {
    var align: Align
    private var width: NSLayoutConstraint?
    
    class var typeIdentifier: String {
        return "NOTDEFINED"
    }
    
    func setWidth(value: CGFloat) {
        guard value > 0 else {
            return
        }
 
        if let width = self.width {
            width.isActive = false
        }
        self.width = view.widthAnchor.constraint(equalToConstant: value)
        self.width!.isActive = true
    }
    
    func getWidth() -> CGFloat {
        return width?.constant ?? 0.0
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case width
        case align
        // TODO move bordered and background from custom button class
        //case bordered
        //case background
        //case title
    }
    
    override init(identifier: NSTouchBarItem.Identifier) {
        self.align = .center
        
        // setting width here wouldn't make any affect
        super.init(identifier: identifier)
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let type = try container.decode(String.self, forKey: .type)
        self.align = try container.decodeIfPresent(Align.self, forKey: .align) ?? .center
        
        super.init(identifier: CustomTouchBarItem.createIdentifier(type))
        
        if let width = try container.decodeIfPresent(CGFloat.self, forKey: .width) {
            self.setWidth(value: width)
        }
    }
    
    static func identifierBase(_ type: String) -> String {
        return "com.toxblh.mtmr." + type
    }
    
    static func createIdentifier(_ type: String) -> NSTouchBarItem.Identifier {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH-mm-ss"
        let time = dateFormatter.string(from: Date())
        let identifierString = CustomTouchBarItem.identifierBase(type).appending(time + "--" + UUID().uuidString)
        return NSTouchBarItem.Identifier(identifierString)
    }
}

class CustomButtonTouchBarItem: CustomTouchBarItem, NSGestureRecognizerDelegate {
    private var tapAction: EventAction?
    private var longTapAction: EventAction?
    var finishViewConfiguration: ()->() = {}
    override class var typeIdentifier: String {
        return "staticButton"
    }
    
    private enum CodingKeys: String, CodingKey {
        case title
        case bordered
        case background
        case image
        case action
        case longAction
    }
    
    private var button: NSButton!
    private var singleClick: HapticClickGestureRecognizer!
    private var longClick: LongPressGestureRecognizer!
    private var attributedTitle: NSAttributedString

    init(identifier: NSTouchBarItem.Identifier, title: String) {
        attributedTitle = title.defaultTouchbarAttributedString

        super.init(identifier: identifier)
        
        initButton(title: title, imageSource: nil)
    }
    
    func initButton(title: String, imageSource: Source?) {
        button = CustomHeightButton(title: title, target: nil, action: nil)
        self.setImage(imageSource?.image)

        longClick = LongPressGestureRecognizer(target: self, action: #selector(handleGestureLong))
        longClick.isEnabled = false
        longClick.allowedTouchTypes = .direct
        longClick.delegate = self

        singleClick = HapticClickGestureRecognizer(target: self, action: #selector(handleGestureSingle))
        singleClick.isEnabled = false
        singleClick.allowedTouchTypes = .direct
        singleClick.delegate = self

        reinstallButton()
        button.attributedTitle = attributedTitle
    }

    required init(from decoder: Decoder) throws {
        attributedTitle = "".defaultTouchbarAttributedString

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""

        try super.init(from: decoder)
        
        if let borderedFlag = try container.decodeIfPresent(Bool.self, forKey: .bordered) {
            self.isBordered = borderedFlag
        }

        if let bgColor = try container.decodeIfPresent(String.self, forKey: .background)?.hexColor {
            self.backgroundColor = bgColor
        }
        

        let imageSource = try container.decodeIfPresent(Source.self, forKey: .image)
        initButton(title: title, imageSource: imageSource)
        
        self.setTapAction(try? SingleTapEventAction(from: decoder))
        self.setLongTapAction(try? LongTapEventAction(from: decoder))
    }
    
    // From for static buttons
    convenience init(title: String) {
        self.init(identifier: CustomTouchBarItem.createIdentifier(CustomButtonTouchBarItem.typeIdentifier), title: title)
    }
    
    func setTapAction(_ action: EventAction?) {
        self.tapAction = action
        self.singleClick?.isEnabled = action != nil
    }
    
    func setLongTapAction(_ action: EventAction?) {
        self.longTapAction = action
        self.longClick?.isEnabled = action != nil
    }
    
    required init?(coder _: NSCoder) {
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
            return getAttributedTitle().string
        }
        set {
            setAttributedTitle(newValue.defaultTouchbarAttributedString)
        }
    }
    
    func getAttributedTitle() -> NSAttributedString {
        return attributedTitle
    }
    
    func setAttributedTitle(_ attributedTitle: NSAttributedString) {
        self.attributedTitle = attributedTitle
        button?.imagePosition = attributedTitle.length > 0 ? .imageLeading : .imageOnly
        button?.attributedTitle = attributedTitle
    }
    
    private var image: NSImage?
    
    func getImage() -> NSImage? {
        return image
    }
    
    func setImage(_ image: NSImage?) {
        self.image = image
        button.image = image
    }

    func reinstallButton() {
        let title = button.attributedTitle
        let image = button.image
        let cell = CustomButtonCell(parentItem: self)
        button.cell = cell
        if let color = backgroundColor {
            cell.isBordered = true
            button.bezelColor = color
            button.bezelStyle = .rounded
            cell.backgroundColor = color
        } else {
            button.isBordered = isBordered
            button.bezelStyle = isBordered ? .rounded : .inline
        }
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.attributedTitle = title
        button?.imagePosition = title.length > 0 ? .imageLeading : .imageOnly
        button.image = image
        view = button

        view.addGestureRecognizer(longClick)
        view.addGestureRecognizer(singleClick)
        finishViewConfiguration()
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        if gestureRecognizer == singleClick && otherGestureRecognizer == longClick
            || gestureRecognizer == longClick && otherGestureRecognizer == singleClick // need it
        {
            return false
        }
        return true
    }

    @objc func handleGestureSingle(gr: NSClickGestureRecognizer) {
        switch gr.state {
        case .ended:
            self.tapAction?.closure(self)
            break
        default:
            break
        }
    }

    @objc func handleGestureLong(gr: NSPressGestureRecognizer) {
        switch gr.state {
        case .possible: // tiny hack because we're calling action manually
            (self.longTapAction?.closure ?? self.tapAction?.closure)?(self)
            break
        default:
            break
        }
    }
}

class CustomHeightButton: NSButton {
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
        if !isBordered {
            if flag {
                setAttributedTitle(attributedTitle, withColor: .lightGray)
            } else if let parentItem = self.parentItem {
                attributedTitle = parentItem.getAttributedTitle()
            }
        }
    }
    
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return rect // need that so content may better fit in button with very limited width
    }

    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAttributedTitle(_ title: NSAttributedString, withColor color: NSColor) {
        let attrTitle = NSMutableAttributedString(attributedString: title)
        attrTitle.addAttributes([.foregroundColor: color], range: NSRange(location: 0, length: attrTitle.length))
        attributedTitle = attrTitle
    }
}

class HapticClickGestureRecognizer: NSClickGestureRecognizer {
    override func touchesBegan(with event: NSEvent) {
        HapticFeedback.shared?.tap(strong: 2)
        super.touchesBegan(with: event)
    }
    
    override func touchesEnded(with event: NSEvent) {
        HapticFeedback.shared?.tap(strong: 1)
        super.touchesEnded(with: event)
    }
}

class LongPressGestureRecognizer: NSPressGestureRecognizer {
    var recognizeTimeout = 0.4
    private var timer: Timer?
    
    override func touchesBegan(with event: NSEvent) {
        timerInvalidate()
        
        let touches = event.touches(for: self.view!)
        if touches.count == 1 { // to prevent it for built-in two/three-finger gestures
            timer = Timer.scheduledTimer(timeInterval: recognizeTimeout, target: self, selector: #selector(self.onTimer), userInfo: nil, repeats: false)
        }
        
        super.touchesBegan(with: event)
    }
    
    override func touchesMoved(with event: NSEvent) {
        timerInvalidate() // to prevent it for built-in two/three-finger gestures
        super.touchesMoved(with: event)
    }
    
    override func touchesCancelled(with event: NSEvent) {
        timerInvalidate()
        super.touchesCancelled(with: event)
    }
    
    override func touchesEnded(with event: NSEvent) {
        timerInvalidate()
        super.touchesEnded(with: event)
    }
    
    private func timerInvalidate() {
        if let timer = timer {
            timer.invalidate()
            self.timer = nil
        }
    }
    
    @objc private func onTimer() {
        if let target = self.target, let action = self.action {
            target.performSelector(onMainThread: action, with: self, waitUntilDone: false)
            HapticFeedback.shared?.tap(strong: 6)
        }
    }
    
    deinit {
        timerInvalidate()
    }
}

extension String {
    var defaultTouchbarAttributedString: NSAttributedString {
        let attrTitle = NSMutableAttributedString(string: self, attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 15, weight: .regular), .baselineOffset: 1])
        attrTitle.setAlignment(.center, range: NSRange(location: 0, length: count))
        return attrTitle
    }
}
