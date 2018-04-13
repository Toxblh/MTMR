import Foundation
import AppKit

extension Data {

    func barItemDefinitions() -> [BarItemDefinition]? {
        return try? JSONDecoder().decode([BarItemDefinition].self, from: self)
    }

}

struct BarItemDefinition: Decodable {
    let type: ItemType
    let action: ActionType
    let additionalParameters: [GeneralParameters.CodingKeys: GeneralParameter]

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(type: ItemType, action: ActionType, additionalParameters: [GeneralParameters.CodingKeys:GeneralParameter]) {
        self.type = type
        self.action = action
        self.additionalParameters = additionalParameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let parametersDecoder = SupportedTypesHolder.sharedInstance.lookup(by: type)
        var additionalParameters = try GeneralParameters(from: decoder).parameters
        if let result = try? parametersDecoder(decoder),
            case let (itemType, action, parameters) = result {
            parameters.forEach { additionalParameters[$0] = $1 }
            self.init(type: itemType, action: action, additionalParameters: additionalParameters)
        } else {
            self.init(type: .staticButton(title: "unknown"), action: .none, additionalParameters: additionalParameters)
        }
    }

}

class SupportedTypesHolder {
    typealias ParametersDecoder = (Decoder) throws ->(item: ItemType, action: ActionType, parameters: [GeneralParameters.CodingKeys: GeneralParameter])
    private var supportedTypes: [String: ParametersDecoder] = [
        "escape": { _ in return (item: .staticButton(title: "esc"), action: .keyPress(keycode: 53), parameters: [.align: .align(.left)])  },
        "brightnessUp": { _ in
            let imageParameter = GeneralParameter.image(source: #imageLiteral(resourceName: "brightnessUp"))
            return (item: .staticButton(title: ""), action: .keyPress(keycode: 113), parameters: [.image: imageParameter])
        },
        "brightnessDown": { _ in
            let imageParameter = GeneralParameter.image(source: #imageLiteral(resourceName: "brightnessDown"))
            return (item: .staticButton(title: ""), action: .keyPress(keycode: 107), parameters: [.image: imageParameter])
        },
        "volumeDown": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarVolumeDownTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_SOUND_DOWN), parameters: [.image: imageParameter])
        },
        "volumeUp": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarVolumeUpTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_SOUND_UP), parameters: [.image: imageParameter])
        },
        "previous": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarRewindTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_PREVIOUS), parameters: [.image: imageParameter])
        },
        "play": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarPlayPauseTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_PLAY), parameters: [.image: imageParameter])
        },
        "next": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarFastForwardTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_NEXT), parameters: [.image: imageParameter])
        },
        "weather": { decoder in
            enum CodingKeys: String, CodingKey { case refreshInterval }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval)
            let scriptPath = Bundle.main.path(forResource: "Weather", ofType: "scpt")!
            let item = ItemType.appleScriptTitledButton(source: Source(filePath: scriptPath), refreshInterval: interval ?? 1800.0)
            return (item: item, action: .none, parameters: [:])
        },
        "battery": { decoder in
            enum CodingKeys: String, CodingKey { case refreshInterval }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval)
            let scriptPath = Bundle.main.path(forResource: "Battery", ofType: "scpt")!
            let item = ItemType.appleScriptTitledButton(source: Source(filePath: scriptPath), refreshInterval: interval ?? 1800.0)
            return (item: item, action: .none, parameters: [:])
        },
        "sleep": { _ in return (item: .staticButton(title: "☕️"), action: .shellScript(executable: "/usr/bin/pmset", parameters: ["sleepnow"]), parameters: [:]) },
        "displaySleep": { _ in return (item: .staticButton(title: "☕️"), action: .shellScript(executable: "/usr/bin/pmset", parameters: ["displaysleepnow"]), parameters: [:]) },
    ]

    static let sharedInstance = SupportedTypesHolder()

    func lookup(by type: String) -> ParametersDecoder {
        return supportedTypes[type] ?? { decoder in
            return (item: try ItemType(from: decoder), action: try ActionType(from: decoder), parameters: [:])
        }
    }

    func register(typename: String, decoder: @escaping ParametersDecoder) {
        supportedTypes[typename] = decoder
    }

    func register(typename: String, item: ItemType, action: ActionType) {
        register(typename: typename) { _ in
            return (item: item, action: action, parameters: [:])
        }
    }
}

enum ItemType: Decodable {
    case staticButton(title: String)
    case appleScriptTitledButton(source: SourceProtocol, refreshInterval: Double)
    case timeButton(formatTemplate: String)
    case flexSpace()
    case volume()
    case brightness()

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case source
        case refreshInterval
        case formatTemplate
        case image
    }

    enum ItemTypeRaw: String, Decodable {
        case staticButton
        case appleScriptTitledButton
        case timeButton
        case flexSpace
        case volume
        case brightness
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemTypeRaw.self, forKey: .type)
        switch type {
        case .appleScriptTitledButton:
            let source = try container.decode(Source.self, forKey: .source)
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 1800.0
            self = .appleScriptTitledButton(source: source, refreshInterval: interval)
        case .staticButton:
            let title = try container.decode(String.self, forKey: .title)
            self = .staticButton(title: title)
        case .timeButton:
            let template = try container.decodeIfPresent(String.self, forKey: .formatTemplate) ?? "HH:mm"
            self = .timeButton(formatTemplate: template)
        case .flexSpace:
            self = .flexSpace()
        case .volume:
            self = .volume()
        case .brightness:
            self = .brightness()
        }
    }
}

enum ActionType: Decodable {
    case none
    case hidKey(keycode: Int)
    case keyPress(keycode: Int)
    case appleSctipt(source: SourceProtocol)
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
            let source = try container.decode(Source.self, forKey: .actionAppleScript)
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
    case image(source: SourceProtocol)
    case align(_: Align)
}

struct GeneralParameters: Decodable {
    let parameters: [GeneralParameters.CodingKeys: GeneralParameter]

    enum CodingKeys: String, CodingKey {
        case width
        case image
        case align
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var result: [GeneralParameters.CodingKeys: GeneralParameter] = [:]
        if let value = try container.decodeIfPresent(CGFloat.self, forKey: .width) {
            result[.width] = .width(value)
        }
        if let imageSource = try container.decodeIfPresent(Source.self, forKey: .image) {
            result[.image] = .image(source: imageSource)
        }
        let align = try container.decodeIfPresent(Align.self, forKey: .align) ?? .center
        result[.align] = .align(align)
        parameters = result
    }
}
protocol SourceProtocol {
    var data: Data? { get }
    var string: String? { get }
    var image: NSImage? { get }
}
struct Source: Decodable, SourceProtocol {
    let filePath: String?
    let base64: String?
    let inline: String?
    
    private enum CodingKeys: String, CodingKey {
        case filePath
        case base64
        case inline
    }
    
    var data: Data? {
        return base64?.base64Data ?? inline?.data(using: .utf8) ?? filePath?.fileData
    }
    var string: String? {
        return inline ?? self.data?.utf8string
    }
    var image: NSImage? {
        return data?.image
    }

    private init(filePath: String?, base64: String?, inline: String?) {
        self.filePath = filePath
        self.base64 = base64
        self.inline = inline
    }
    init(filePath: String) {
        self.init(filePath: filePath, base64: nil, inline: nil)
    }
}
extension NSImage: SourceProtocol {
    var data: Data? {
        return nil
    }
    var string: String? {
        return nil
    }
    var image: NSImage? {
        return self
    }
}
extension SourceProtocol where Self: Equatable {}
func ==(left: SourceProtocol, right: SourceProtocol) -> Bool {
    return left.data == right.data
}

extension String {
    var base64Data: Data? {
        return Data(base64Encoded: self)
    }
    var fileData: Data? {
        return try? Data(contentsOf: URL(fileURLWithPath: self))
    }
}
extension Data {
    var utf8string: String? {
        return String(data: self, encoding: .utf8)
    }
    var image: NSImage? {
        return NSImage(data: self)?.resize(maxSize: NSSize(width: 24, height: 24))
    }
}

enum Align: String, Decodable {
    case left
    case center
    case right
}
