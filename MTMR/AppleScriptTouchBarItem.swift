import Foundation

class AppleScriptTouchBarItem: NSCustomTouchBarItem {
    private var script: NSAppleScript!
    private let button = NSButton(title: "", target: nil, action: nil)
    private let interval: TimeInterval
    private var forceHideConstraint: NSLayoutConstraint!
    
    init?(identifier: NSTouchBarItem.Identifier, source: Source, interval: TimeInterval) {
        self.interval = interval
        super.init(identifier: identifier)
        self.view = button
        self.forceHideConstraint = self.view.widthAnchor.constraint(equalToConstant: 0)
        guard let source = source.string else {
            button.title = "no script"
            return
        }
        guard let script = NSAppleScript(source: source) else {
            button.title = "isn't a script"
            return
        }
        self.script = script
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
            self.forceHideConstraint.isActive = scriptResult == ""
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
        return output.stringValue ?? ""
    }

}
