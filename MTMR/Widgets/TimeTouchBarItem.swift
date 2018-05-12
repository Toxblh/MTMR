import Cocoa

class TimeTouchBarItem: CustomButtonTouchBarItem {
    private let dateFormatter = DateFormatter()
    private var timer: Timer!
    
    init(identifier: NSTouchBarItem.Identifier, formatTemplate: String) {
        dateFormatter.setLocalizedDateFormatFromTemplate(formatTemplate)
        super.init(identifier: identifier, title: " ")
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateTime), userInfo: nil, repeats: true)
        self.isBordered = false
        updateTime()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func updateTime() {
        self.title = self.dateFormatter.string(from: Date())
    }
    
}
