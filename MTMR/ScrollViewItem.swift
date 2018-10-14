import Foundation

class ScrollViewItem: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    var twofingersPrev: CGFloat = 0.0
    var brightnessAtStart: Float = 0.0
    
    init(identifier: NSTouchBarItem.Identifier, items: [NSTouchBarItem]) {
        super.init(identifier: identifier)
        let views = items.compactMap { $0.view }
        let stackView = NSStackView(views: views)
        stackView.spacing = 1
        stackView.orientation = .horizontal
        let scrollView = NSScrollView(frame: CGRect(origin: .zero, size: stackView.fittingSize))
        scrollView.documentView = stackView
        self.view = scrollView
        
        let twofingers = NSPanGestureRecognizer(target: self, action: #selector(twofingersHandler(_:)))
        twofingers.allowedTouchTypes = .direct
        twofingers.numberOfTouchesRequired = 2
        self.view.addGestureRecognizer(twofingers)
        
        let threefingers = NSPanGestureRecognizer(target: self, action: #selector(threefingersHandler(_:)))
        threefingers.allowedTouchTypes = .direct
        threefingers.numberOfTouchesRequired = 3
        self.view.addGestureRecognizer(threefingers)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func twofingersHandler(_ sender: NSGestureRecognizer?) { // Volume
        let position = (sender?.location(in: sender?.view).x)!
        
        switch sender!.state {
        case .began:
            twofingersPrev = position
        case .changed:
            if (((position-twofingersPrev) > 10) || ((twofingersPrev-position) > 10)) {
                if position > twofingersPrev {
                    HIDPostAuxKey(NX_KEYTYPE_SOUND_UP)
                } else if position < twofingersPrev {
                    HIDPostAuxKey(NX_KEYTYPE_SOUND_DOWN)
                }
                twofingersPrev = position
            }
        case .ended:
            twofingersPrev = 0.0
        default:
            break
        }
    }
    
    @objc func threefingersHandler(_ sender: NSPanGestureRecognizer?) { // Brightness
        switch sender!.state {
        case .began:
            brightnessAtStart = sharedBrightnessController.brightness
        case .changed:
            let panOffset = sender!.translation(in: sender!.view).x
            sharedBrightnessController.brightness = brightnessAtStart + Float(panOffset) / 200.0
        default:
            break
        }
    }
}
