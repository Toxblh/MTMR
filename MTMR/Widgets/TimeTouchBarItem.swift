import Cocoa

class TimeTouchBarItem: CustomButtonTouchBarItem {
    private let dateFormatter = DateFormatter()
    private var timer: Timer?

    init(identifier: NSTouchBarItem.Identifier, formatTemplate: String, timeZone: String? = nil, locale: String? = nil) {
        dateFormatter.dateFormat = formatTemplate
        if let locale = locale {
            dateFormatter.locale = Locale(identifier: locale)
        }
        if let abbr = timeZone {
            dateFormatter.timeZone = TimeZone(abbreviation: abbr)
        }
        super.init(identifier: identifier, title: " ")
        timer = Timer.widgetTimer(every: 1) { [weak self] in self?.updateTime() }
        isBordered = false
        updateTime()
    }

    deinit { timer?.invalidate() }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func updateTime() {
        title = dateFormatter.string(from: Date())
    }
}
