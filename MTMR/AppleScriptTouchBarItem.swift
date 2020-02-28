import Foundation

class AppleScriptTouchBarItem: CustomButtonTouchBarItem {
    private var script: NSAppleScript!
    private let interval: TimeInterval
    private var forceHideConstraint: NSLayoutConstraint!
    private let alternativeImages: [String: SourceProtocol]

    init?(identifier: NSTouchBarItem.Identifier, source: SourceProtocol, interval: TimeInterval, alternativeImages: [String: SourceProtocol]) {
        self.interval = interval
        self.alternativeImages = alternativeImages
        super.init(identifier: identifier, title: "⏳")
        forceHideConstraint = view.widthAnchor.constraint(equalToConstant: 0)
        title = "scheduled"
        DispatchQueue.appleScriptQueue.async {
            guard let script = source.appleScript else {
                DispatchQueue.main.async {
                    self.title = "no script"
                }
                return
            }
            self.script = script
            DispatchQueue.main.async {
                self.isBordered = false
            }
            
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

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshAndSchedule() {
        #if DEBUG
            print("refresh happened (interval \(interval)), self \(identifier.rawValue))")
        #endif
        let scriptResult = execute()
        DispatchQueue.main.async {
            self.title = scriptResult
            self.forceHideConstraint.isActive = scriptResult == ""
            #if DEBUG
                print("did set new script result title \(scriptResult)")
            #endif
        }
        DispatchQueue.appleScriptQueue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.refreshAndSchedule()
        }
    }

    func updateIcon(iconLabel: String) {
        if alternativeImages[iconLabel] != nil {
            DispatchQueue.main.async {
                self.image = self.alternativeImages[iconLabel]!.image
            }
        } else {
            print("Cannot find icon with label \"\(iconLabel)\"")
        }
    }

    func execute() -> String {
        var error: NSDictionary?
        let output = script.executeAndReturnError(&error)
        if let error = error {
            print(error)
            return "error"
        }
        if output.descriptorType == typeAEList {
            let arr = Array(1...output.numberOfItems).compactMap({ output.atIndex($0)!.stringValue ?? "" })

            if arr.count <= 0 {
                return ""
            } else if arr.count == 1 {
                return arr[0]
            } else {
                updateIcon(iconLabel: arr[1])
                return arr[0]
            }
        }
        return output.stringValue ?? ""
    }
}

extension DispatchQueue {
    static let appleScriptQueue = DispatchQueue(label: "mtmr.applescript")
}
