import Foundation

extension Data {

    func barItemDefinitions() -> [BarItemDefinition]? {
        return try? JSONDecoder().decode([BarItemDefinition].self, from: self)
    }

}

struct BarItemDefinition: Decodable {
    let type: ItemType
    let action: ActionType
    let additionalParameters: [GeneralParameter]

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(type: ItemType, action: ActionType, additionalParameters: [GeneralParameter]) {
        self.type = type
        self.action = action
        self.additionalParameters = additionalParameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let parametersDecoder = SupportedTypesHolder.sharedInstance.lookup(by: type)
        let additionalParameters = try GeneralParameters(from: decoder).parameters
        if let result = try? parametersDecoder(decoder),
            case let (itemType, action) = result {
            self.init(type: itemType, action: action, additionalParameters: additionalParameters)
        } else {
            self.init(type: .staticButton(title: "unknown"), action: .none, additionalParameters: additionalParameters)
        }
    }

}

class SupportedTypesHolder {
    typealias ParametersDecoder = (Decoder) throws ->(item: ItemType, action: ActionType)
    private var supportedTypes: [String: ParametersDecoder] = [
        "escape": { _ in return (item: .staticButton(title: "esc"), action: .keyPress(keycode: 53))  },
        "brightnessUp": { _ in return (item: .staticButton(title: "🔆"), action: .keyPress(keycode: 113))  },
        "brightnessDown": { _ in return (item: .staticButton(title: "🔅"), action: .keyPress(keycode: 107))  },
        "volumeDown": { _ in return (item: .staticButton(title: "🔉"), action: .hidKey(keycode: NX_KEYTYPE_SOUND_DOWN))  },
        "volumeUp": { _ in return (item: .staticButton(title: "🔊"), action: .hidKey(keycode: NX_KEYTYPE_SOUND_UP))  },
        "previous": { _ in return (item: .staticButton(title: "⏪"), action: .hidKey(keycode: NX_KEYTYPE_PREVIOUS))  },
        "play": { _ in return (item: .staticButton(title: "⏯"), action: .hidKey(keycode: NX_KEYTYPE_PLAY))  },
        "next": { _ in return (item: .staticButton(title: "⏩"), action: .hidKey(keycode: NX_KEYTYPE_NEXT))  },
        "weather": { decoder in
            enum CodingKeys: String, CodingKey { case refreshInterval }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval)
            let scriptURL = Bundle.main.url(forResource: "Weather", withExtension: "scpt")!
            let item = ItemType.appleScriptTitledButton(source: try! String(contentsOf: scriptURL), refreshInterval: interval ?? 1800.0)
            return (item: item, action: .none)
        },
        "battery": { decoder in
            enum CodingKeys: String, CodingKey { case refreshInterval }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval)
            let scriptURL = Bundle.main.url(forResource: "Battery", withExtension: "scpt")!
            print(try! String(contentsOf: scriptURL))
            let item = ItemType.appleScriptTitledButton(source: try! String(contentsOf: scriptURL), refreshInterval: interval ?? 1800.0)
            return (item: item, action: .none)
        },
        "sleep": { _ in return (item: .staticButton(title: "☕️"), action: .shellScript(executable: "/usr/bin/pmset", parameters: ["sleepnow"]) ) },
        "displaySleep": { _ in return (item: .staticButton(title: "☕️"), action: .shellScript(executable: "/usr/bin/pmset", parameters: ["displaysleepnow"]) ) },
    ]

    static let sharedInstance = SupportedTypesHolder()

    func lookup(by type: String) -> ParametersDecoder {
        return supportedTypes[type] ?? { decoder in
            return (item: try ItemType(from: decoder), action: try ActionType(from: decoder))
        }
    }

    func register(typename: String, decoder: @escaping ParametersDecoder) {
        supportedTypes[typename] = decoder
    }

    func register(typename: String, item: ItemType, action: ActionType) {
        register(typename: typename) { _ in
            return (item: item, action: action)
        }
    }
}

enum ItemType: Decodable {
    case staticButton(title: String)
    case appleScriptTitledButton(source: String, refreshInterval: Double)
    case timeButton(formatTemplate: String)
    case flexSpace()

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case titleAppleScript
        case refreshInterval
        case formatTemplate
    }

    enum ItemTypeRaw: String, Decodable {
        case staticButton
        case appleScriptTitledButton
        case timeButton
        case flexSpace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemTypeRaw.self, forKey: .type)
        switch type {
        case .appleScriptTitledButton:
            let source = try container.decode(String.self, forKey: .titleAppleScript)
            let interval = try container.decode(Double.self, forKey: .refreshInterval)
            self = .appleScriptTitledButton(source: try String(contentsOfFile: source), refreshInterval: interval)
        case .staticButton:
            let title = try container.decode(String.self, forKey: .title)
            self = .staticButton(title: title)
        case .timeButton:
            let template = try container.decodeIfPresent(String.self, forKey: .formatTemplate) ?? "HH:mm"
            self = .timeButton(formatTemplate: template)
        case .flexSpace:
            self = .flexSpace()
        }
    }
}

enum ActionType: Decodable {
    case none
    case hidKey(keycode: Int)
    case keyPress(keycode: Int)
    case appleSctipt(source: String)
    case shellScript(executable: String, parameters: [String])
    case custom(closure: ()->())

    private enum CodingKeys: String, CodingKey {
        case action
        case keycode
        case actionAppleScript
        case executablePath
        case shellArguments
    }

    private enum ActionTypeRaw: String, Decodable {
        case hidKey
        case keyPress
        case appleScript
        case shellScript
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(ActionTypeRaw.self, forKey: .action)
        switch type {
        case .some(.hidKey):
            let keycode = try container.decode(Int.self, forKey: .keycode)
            self = .hidKey(keycode: keycode)
        case .some(.keyPress):
            let keycode = try container.decode(Int.self, forKey: .keycode)
            self = .keyPress(keycode: keycode)
        case .some(.appleScript):
            let source = try container.decode(String.self, forKey: .actionAppleScript)
            self = .appleSctipt(source: source)
        case .some(.shellScript):
            let executable = try container.decode(String.self, forKey: .executablePath)
            let parameters = try container.decodeIfPresent([String].self, forKey: .shellArguments) ?? []
            self = .shellScript(executable: executable, parameters: parameters)
        case .none:
            self = .none
        }
    }
}

extension ItemType: Equatable {}
func ==(lhs: ItemType, rhs: ItemType) -> Bool {
    switch (lhs, rhs) {
    case let (.staticButton(a), .staticButton(b)):
        return a == b
    case let (.flexSpace(a), .flexSpace(b)):
        return a == b
    case let (.appleScriptTitledButton(a, b), .appleScriptTitledButton(c, d)):
        return a == c && b == d

    default:
        return false
    }
}

extension ActionType: Equatable {}
func ==(lhs: ActionType, rhs: ActionType) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        return true
    case let (.hidKey(a), .hidKey(b)),
         let (.keyPress(a), .keyPress(b)):
        return a == b
    case let (.appleSctipt(a), .appleSctipt(b)):
        return a == b
    case let (.shellScript(a, b), .shellScript(c, d)):
        return a == c && b == d
    default:
        return false
    }
}

enum GeneralParameter {
    case width(_: CGFloat)
}

struct GeneralParameters: Decodable {
    let parameters: [GeneralParameter]
    
    fileprivate enum CodingKeys: String, CodingKey {
        case width
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var result: [GeneralParameter] = []
        if let value = try container.decodeIfPresent(CGFloat.self, forKey: .width) {
            result.append(.width(value))
        }
        parameters = result
    }
}
