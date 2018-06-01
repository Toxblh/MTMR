import Foundation

class AppleScriptTouchBarItem: CustomButtonTouchBarItem {
    private var script: NSAppleScript!
    private let interval: TimeInterval
    private var forceHideConstraint: NSLayoutConstraint!
    
    init?(identifier: NSTouchBarItem.Identifier, source: SourceProtocol, interval: TimeInterval) {
        self.interval = interval
        super.init(identifier: identifier, title: "⏳")
        self.forceHideConstraint = self.view.widthAnchor.constraint(equalToConstant: 0)
        guard let script = source.appleScript else {
            self.title = "no script"
            return
        }
        self.script = script
        self.isBordered = false
        DispatchQueue.appleScriptQueue.async {
            var error: NSDictionary?
            guard script.compileAndReturnError(&error) else {
                #if DEBUG
                    print(error?.description ?? "unknown error")
                #endif
                DispatchQueue.main.async {
                    self.title = "error"
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
        #if DEBUG
            print("refresh happened (interval \(self.interval)), self \(self.identifier.rawValue))")
        #endif
        let scriptResult = self.execute()
        DispatchQueue.main.async {
            self.title = scriptResult
            self.forceHideConstraint.isActive = scriptResult == ""
            #if DEBUG
            print("did set new script result title \(scriptResult)")
            #endif
        }
        DispatchQueue.appleScriptQueue.asyncAfter(deadline: .now() + self.interval) { [weak self] in
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

extension DispatchQueue {
    static let appleScriptQueue = DispatchQueue(label: "mtmr.applescript")
}
