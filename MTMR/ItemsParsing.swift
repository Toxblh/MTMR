import Foundation

struct BarItemDefinition: Decodable {
    let type: ItemType
    let action: ActionType
 
    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let parametersDecoder = SupportedTypesHolder.sharedInstance.lookup(by: type)
        if let result = try? parametersDecoder(decoder),
            case let (itemType, action) = result {
            self.type = itemType
            self.action = action
        } else {
            self.type = .staticButton(title: "unknown")
            self.action = .none
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
    case appleScriptTitledButton(source: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case titleAppleScript
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
            self = .appleScriptTitledButton(source: source)
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
    case let (.staticButton(a),   .staticButton(b)),
         let (.appleScriptTitledButton(a), .appleScriptTitledButton(b)):
        return a == b
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

