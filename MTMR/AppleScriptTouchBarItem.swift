import Foundation

class AppleScriptTouchBarItem: NSCustomTouchBarItem {
    let script: NSAppleScript
    private var timer: Timer!
    private let button = NSButton(title: "", target: nil, action: nil)
    
    init?(identifier: NSTouchBarItem.Identifier, appleScript: String, interval: TimeInterval) {
        guard let script = NSAppleScript(source: appleScript) else {
            return nil
        }
        self.script = script
        super.init(identifier: identifier)
        timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        self.view = button
        button.bezelColor = .clear
        refresh()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func refresh() {
        self.button.title = self.execute()
    }
    
    func execute() -> String {
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error = error {
            print(error)
            return "error"
        }
        return output.stringValue ?? "empty value"
    }
}
