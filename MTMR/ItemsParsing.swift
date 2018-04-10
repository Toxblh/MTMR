import Foundation

extension Data {
    
    func barItemDefinitions() -> [BarItemDefinition]? {
        return try? JSONDecoder().decode([BarItemDefinition].self, from: self)
    }
    
}

struct BarItemDefinition: Decodable {
    let type: ItemType
    let action: ActionType
 
    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    init(type: ItemType, action: ActionType) {
        self.type = type
        self.action = action
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let parametersDecoder = SupportedTypesHolder.sharedInstance.lookup(by: type)
        if let result = try? parametersDecoder(decoder),
            case let (itemType, action) = result {
            self.init(type: itemType, action: action)
        } else {
            self.init(type: .staticButton(title: "unknown"), action: .none)
        }
    }

}

class SupportedTypesHolder {
    typealias ParametersDecoder = (Decoder) throws ->(item: ItemType, action: ActionType)
    private var supportedTypes: [String: ParametersDecoder] = [
        "brightnessUp": { _ in return (item: .staticButton(title: "🔆"), action: .keyPress(keycode: 113))  },
    ]
    
    static let sharedInstance = SupportedTypesHolder()
    
    func lookup(by type: String) -> ParametersDecoder {
        if let extraType = supportedTypes[type] {
            return extraType
        } else {
            return { decoder in
                return (item: try ItemType(from: decoder), action: try ActionType(from: decoder))
            }
        }
    }
}

enum ItemType: Decodable {
    case staticButton(title: String)
    case appleScriptTitledButton(source: String, refreshInterval: Double)

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case titleAppleScript
        case refreshInterval
    }
    
    private enum ItemTypeRaw: String, Decodable {
        case staticButton
        case appleScriptTitledButton
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemTypeRaw.self, forKey: .type)
        switch type {
        case .appleScriptTitledButton:
            let source = try container.decode(String.self, forKey: .titleAppleScript)
            let interval = try container.decode(Double.self, forKey: .refreshInterval)
            self = .appleScriptTitledButton(source: source, refreshInterval: interval)
        case .staticButton:
            let title = try container.decode(String.self, forKey: .title)
            self = .staticButton(title: title)
        }
    }
}

enum ActionType: Decodable {
    case none
    case hidKey(keycode: Int)
    case keyPress(keycode: Int)
    case appleSctipt(source: String)
    
    private enum CodingKeys: String, CodingKey {
        case action
        case keycode
        case actionAppleScript
    }
    
    private enum ActionTypeRaw: String, Decodable {
        case hidKey
        case keyPress
        case appleScript
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
        case .none:
            self = .none
        }
    }
}

extension ItemType: Equatable {}
func ==(lhs: ItemType, rhs: ItemType) -> Bool {
    switch (lhs, rhs) {
    case let (.staticButton(a),   .staticButton(b)):
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
    default:
        return false
    }
}

