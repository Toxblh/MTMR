import Foundation

class AppleScriptTouchBarItem: NSCustomTouchBarItem {
    private let script: NSAppleScript!
    private let button = NSButton(title: "", target: nil, action: nil)
    private let interval: TimeInterval
    
    init?(identifier: NSTouchBarItem.Identifier, appleScript: String, interval: TimeInterval) {
        guard let script = NSAppleScript(source: appleScript) else {
            return nil
        }
        self.script = script
        self.interval = interval
        super.init(identifier: identifier)
        self.view = button
        button.bezelColor = .clear
        button.title = "compile"
        DispatchQueue.main.async {
            var error: NSDictionary?
            guard script.compileAndReturnError(&error) else {
                print(error?.description ?? "unknown error")
                DispatchQueue.main.async {
                    self.button.title = "compile error"
                }
                return
            }
            self.refreshAndSchedule()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func refreshAndSchedule() {
        print("refresh happened")
        let scriptResult = self.execute()
        DispatchQueue.main.async {
            self.button.title = scriptResult
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + self.interval) { [weak self] in
            self?.refreshAndSchedule()
        }
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
