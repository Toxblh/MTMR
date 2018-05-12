import Foundation

class AppleScriptTouchBarItem: CustomButtonTouchBarItem {
    private var script: NSAppleScript!
    private let interval: TimeInterval
    private var forceHideConstraint: NSLayoutConstraint!
    
    init?(identifier: NSTouchBarItem.Identifier, source: SourceProtocol, interval: TimeInterval, onTap: @escaping ()->(), onLongTap: @escaping ()->()) {
        self.interval = interval
        super.init(identifier: identifier, title: "⏳", onTap: onTap, onLongTap: onLongTap)
        self.forceHideConstraint = self.view.widthAnchor.constraint(equalToConstant: 0)
        guard let script = source.appleScript else {
            self.title = "no script"
            return
        }
        self.script = script
        button.bezelColor = .clear
        DispatchQueue.main.async {
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

extension SourceProtocol {
    var appleScript: NSAppleScript? {
        guard let source = self.string else { return nil }
        return NSAppleScript(source: source)
    }
}
