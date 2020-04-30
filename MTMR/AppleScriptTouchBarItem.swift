import Foundation

class AppleScriptTouchBarItem: CustomButtonTouchBarItem {
    private var script: NSAppleScript!
    private let interval: TimeInterval
    private var forceHideConstraint: NSLayoutConstraint!
    private let alternativeImages: [String: SourceProtocol]
    
    private enum CodingKeys: String, CodingKey {
        case source
        case alternativeImages
        case refreshInterval
    }
    
    override class var typeIdentifier: String {
        return "appleScriptTitledButton"
    }

    init?(identifier: NSTouchBarItem.Identifier, source: SourceProtocol, interval: TimeInterval, alternativeImages: [String: SourceProtocol]) {
        self.interval = interval
        self.alternativeImages = alternativeImages
        super.init(identifier: identifier, title: "⏳")
        
        initScripts(source: source)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decode(Source.self, forKey: .source)
        self.interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 1800.0
        self.alternativeImages = try container.decodeIfPresent([String: Source].self, forKey: .alternativeImages) ?? [:]
        
        print("AppleScriptTouchBarItem.init(from decoder)")
        try super.init(from: decoder)
        self.title = "⏳"
        
        initScripts(source: source)
    }
    
    func initScripts(source: SourceProtocol) {
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
                self.setImage(self.alternativeImages[iconLabel]!.image)
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
