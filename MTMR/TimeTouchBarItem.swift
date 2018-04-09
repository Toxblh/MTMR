import Cocoa

@available(OSX 10.12.2, *)
class TimeTouchBarItem: NSCustomTouchBarItem {
    private let dateFormatter = DateFormatter()
    private var timer: Timer!
    private let button = NSButton(title: "", target: nil, action: nil)
    
    init(identifier: NSTouchBarItem.Identifier, formatTemplate: String) {
        dateFormatter.setLocalizedDateFormatFromTemplate(formatTemplate)
        super.init(identifier: identifier)
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateTime), userInfo: nil, repeats: true)
        self.view = button
        button.bezelColor = .clear
        updateTime()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func updateTime() {
        button.title = self.dateFormatter.string(from: Date())
    }
    
}
