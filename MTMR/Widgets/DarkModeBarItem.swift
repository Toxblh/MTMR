import Foundation

class DarkModeBarItem: CustomButtonTouchBarItem {
    private var timer: Timer!
    
    override class var typeIdentifier: String {
        return "darkMode"
    }

    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: "")
        
        self.setup()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        self.setup()
    }
    
    func setup() {
        if getWidth() == 0.0 {
            setWidth(value: 24)
        }

        self.setTapAction(
            EventAction({ [weak self] (_ caller: CustomButtonTouchBarItem) in
                self?.DarkModeToggle()
            } )
        )

        timer = Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)

        refresh()
    }

    func DarkModeToggle() {
        DarkMode.isEnabled = !DarkMode.isEnabled
        refresh()
    }

    @objc func refresh() {
        self.setImage(DarkMode.isEnabled ? #imageLiteral(resourceName: "dark-mode-on") : #imageLiteral(resourceName: "dark-mode-off"))
    }
}


struct DarkMode {
    private static let prefix = "tell application \"System Events\" to tell appearance preferences to"

    static var isEnabled: Bool {
        get {
            return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
        set {
            toggle(force: newValue)
        }
    }

    static func toggle(force: Bool? = nil) {
        let value = force.map(String.init) ?? "not dark mode"
        _ = runAppleScript("\(prefix) set dark mode to \(value)")
    }
}

func runAppleScript(_ source: String) -> String? {
    return NSAppleScript(source: source)?.executeAndReturnError(nil).stringValue
}

