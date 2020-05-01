import Cocoa

class TimeTouchBarItem: CustomButtonTouchBarItem {
    private let dateFormatter = DateFormatter()
    private var timer: Timer!

    private enum CodingKeys: String, CodingKey {
        case formatTemplate
        case timeZone
        case locale
    }
    
    override class var typeIdentifier: String {
        return "timeButton"
    }
    
    init(identifier: NSTouchBarItem.Identifier, formatTemplate: String, timeZone: String? = nil, locale: String? = nil) {
        super.init(identifier: identifier, title: " ")
        self.setupFormatter(formatTemplate: formatTemplate, timeZone: timeZone, locale: locale)
        self.setupTimer()
        updateTime()
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let template = try container.decodeIfPresent(String.self, forKey: .formatTemplate) ?? "HH:mm"
        let timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone) ?? nil
        let locale = try container.decodeIfPresent(String.self, forKey: .locale) ?? nil
       
        try super.init(from: decoder)
        self.setupFormatter(formatTemplate: template, timeZone: timeZone, locale: locale)
        self.setupTimer()
        updateTime()
   }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setupFormatter(formatTemplate: String, timeZone: String? = nil, locale: String? = nil) {
        dateFormatter.dateFormat = formatTemplate
        if let locale = locale {
            dateFormatter.locale = Locale(identifier: locale)
        }
        if let abbr = timeZone {
            dateFormatter.timeZone = TimeZone(abbreviation: abbr)
        }
    }
    
    func setupTimer() {
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateTime), userInfo: nil, repeats: true)
    }

    @objc func updateTime() {
        title = dateFormatter.string(from: Date())
    }
}
