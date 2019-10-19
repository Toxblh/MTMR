import Foundation

class ScrollViewItem: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    var twofingersPrev: CGFloat = 0.0
    var threefingersPrev: CGFloat = 0.0
    var twofingers: NSPanGestureRecognizer!
    var threefingers: NSPanGestureRecognizer!

    init(identifier: NSTouchBarItem.Identifier, items: [NSTouchBarItem]) {
        super.init(identifier: identifier)
        let views = items.compactMap { $0.view }
        let stackView = NSStackView(views: views)
        stackView.spacing = 1
        stackView.orientation = .horizontal
        let scrollView = NSScrollView(frame: CGRect(origin: .zero, size: stackView.fittingSize))
        scrollView.documentView = stackView
        view = scrollView

        twofingers = NSPanGestureRecognizer(target: self, action: #selector(twofingersHandler(_:)))
        twofingers.allowedTouchTypes = .direct
        twofingers.numberOfTouchesRequired = 2
        view.addGestureRecognizer(twofingers)

        threefingers = NSPanGestureRecognizer(target: self, action: #selector(threefingersHandler(_:)))
        threefingers.allowedTouchTypes = .direct
        threefingers.numberOfTouchesRequired = 3
        view.addGestureRecognizer(threefingers)
    }
    
    var gesturesEnabled = true {
        didSet {
            twofingers.isEnabled = gesturesEnabled
            threefingers.isEnabled = gesturesEnabled
        }
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func twofingersHandler(_ sender: NSGestureRecognizer?) { // Volume
        let position = (sender?.location(in: sender?.view).x)!

        switch sender!.state {
        case .began:
            twofingersPrev = position
        case .changed:
            if ((position - twofingersPrev) > 10) || ((twofingersPrev - position) > 10) {
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

    @objc func threefingersHandler(_ sender: NSGestureRecognizer?) { // Brightness
        let position = (sender?.location(in: sender?.view).x)!

        switch sender!.state {
        case .began:
            threefingersPrev = position
        case .changed:
            if ((position - threefingersPrev) > 15) || ((threefingersPrev - position) > 15) {
                if position > threefingersPrev {
                    GenericKeyPress(keyCode: CGKeyCode(144)).send()
                } else if position < threefingersPrev {
                    GenericKeyPress(keyCode: CGKeyCode(145)).send()
                }
                threefingersPrev = position
            }
        case .ended:
            threefingersPrev = 0.0
        default:
            break
        }
    }
}
