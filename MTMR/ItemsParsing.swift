import Foundation
import AppKit

extension Data {
    func barItemDefinitions() -> [BarItemDefinition]? {
      return try? JSONDecoder().decode([BarItemDefinition].self, from: self.utf8string!.stripComments().data(using: .utf8)!)
    }
}

struct BarItemDefinition: Decodable {
    let type: ItemType
    let action: ActionType
    let longAction: LongActionType
    let additionalParameters: [GeneralParameters.CodingKeys: GeneralParameter]

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(type: ItemType, action: ActionType, longAction: LongActionType, additionalParameters: [GeneralParameters.CodingKeys:GeneralParameter]) {
        self.type = type
        self.action = action
        self.longAction = longAction
        self.additionalParameters = additionalParameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let parametersDecoder = SupportedTypesHolder.sharedInstance.lookup(by: type)
        var additionalParameters = try GeneralParameters(from: decoder).parameters
        if let result = try? parametersDecoder(decoder),
            case let (itemType, action, longAction, parameters) = result {
            parameters.forEach { additionalParameters[$0] = $1 }
            self.init(type: itemType, action: action, longAction: longAction, additionalParameters: additionalParameters)
        } else {
            self.init(type: .staticButton(title: "unknown"), action: .none, longAction: .none, additionalParameters: additionalParameters)
        }
    }

}

class SupportedTypesHolder {
    typealias ParametersDecoder = (Decoder) throws ->(item: ItemType, action: ActionType, longAction: LongActionType, parameters: [GeneralParameters.CodingKeys: GeneralParameter])
    private var supportedTypes: [String: ParametersDecoder] = [
        "escape": { _ in return (item: .staticButton(title: "esc"), action: .keyPress(keycode: 53), longAction: .none, parameters: [.align: .align(.left)])  },
        "delete": { _ in return (item: .staticButton(title: "del"), action: .keyPress(keycode: 117), longAction: .none, parameters: [:])},
        "brightnessUp": { _ in
            let imageParameter = GeneralParameter.image(source: #imageLiteral(resourceName: "brightnessUp"))
            return (item: .staticButton(title: ""), action: .keyPress(keycode: 113), longAction: .none, parameters: [.image: imageParameter])
        },
        "brightnessDown": { _ in
            let imageParameter = GeneralParameter.image(source: #imageLiteral(resourceName: "brightnessDown"))
            return (item: .staticButton(title: ""), action: .keyPress(keycode: 107), longAction: .none, parameters: [.image: imageParameter])
        },
        "volumeDown": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarVolumeDownTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_SOUND_DOWN), longAction: .none, parameters: [.image: imageParameter])
        },
        "volumeUp": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarVolumeUpTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_SOUND_UP), longAction: .none, parameters: [.image: imageParameter])
        },
        "mute": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarAudioOutputMuteTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_MUTE), longAction: .none, parameters: [.image: imageParameter])
        },
        "previous": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarRewindTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_PREVIOUS), longAction: .none, parameters: [.image: imageParameter])
        },
        "play": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarPlayPauseTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_PLAY), longAction: .none, parameters: [.image: imageParameter])
        },
        "next": { _ in
            let imageParameter = GeneralParameter.image(source: NSImage(named: .touchBarFastForwardTemplate)!)
            return (item: .staticButton(title: ""), action: .hidKey(keycode: NX_KEYTYPE_NEXT), longAction: .none, parameters: [.image: imageParameter])
        },
        "weather": { decoder in
            enum CodingKeys: String, CodingKey { case refreshInterval; case units; case api_key ; case icon_type }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval)
            let units = try container.decodeIfPresent(String.self, forKey: .units)
            let api_key = try container.decodeIfPresent(String.self, forKey: .api_key)
            let icon_type = try container.decodeIfPresent(String.self, forKey: .icon_type)
            let action = try ActionType(from: decoder)
            let longAction = try LongActionType(from: decoder)
            return (item: .weather(interval: interval ?? 1800.00, units: units ?? "metric", api_key: api_key ?? "32c4256d09a4c52b38aecddba7a078f6", icon_type: icon_type ?? "text"), action: action, longAction: longAction, parameters: [:])
        },
        "currency": { decoder in
            enum CodingKeys: String, CodingKey { case refreshInterval; case from; case to }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval)
            let from = try container.decodeIfPresent(String.self, forKey: .from)
            let to = try container.decodeIfPresent(String.self, forKey: .to)
            let action = try ActionType(from: decoder)
            let longAction = try LongActionType(from: decoder)
            return (item: .currency(interval: interval ?? 600.00, from: from ?? "RUB", to: to ?? "USD"), action: action, longAction: longAction, parameters: [:])
        },
        "dock": { decoder in
            return (item: .dock(), action: .none, longAction: .none, parameters: [:])
        },
        "inputsource": { decoder in
            return (item: .inputsource(), action: .none, longAction: .none, parameters: [:])
        },
        "volume": { decoder in
            enum CodingKeys: String, CodingKey { case image }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if var img = try container.decodeIfPresent(Source.self, forKey: .image) {
                return (item: .volume(), action: .none, longAction: .none, parameters: [.image: .image(source: img)])
            } else {
                return (item: .volume(), action: .none, longAction: .none, parameters: [:])
            }
        },
        "brightness": { decoder in
            enum CodingKeys: String, CodingKey { case refreshInterval; case image }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval)
            if var img = try container.decodeIfPresent(Source.self, forKey: .image) {
                return (item: .brightness(refreshInterval: interval ?? 0.5), action: .none, longAction: .none, parameters: [.image: .image(source: img)])
            } else {
                return (item: .brightness(refreshInterval: interval ?? 0.5), action: .none, longAction: .none, parameters: [:])
            }
        },
        "sleep": { _ in return (item: .staticButton(title: "☕️"), action: .shellScript(executable: "/usr/bin/pmset", parameters: ["sleepnow"]), longAction: .none, parameters: [:]) },
        "displaySleep": { _ in return (item: .staticButton(title: "☕️"), action: .shellScript(executable: "/usr/bin/pmset", parameters: ["displaysleepnow"]), longAction: .none,  parameters: [:])},
    ]

    static let sharedInstance = SupportedTypesHolder()

    func lookup(by type: String) -> ParametersDecoder {
        return supportedTypes[type] ?? { decoder in
            return (item: try ItemType(from: decoder), action: try ActionType(from: decoder), longAction: try LongActionType(from: decoder), parameters: [:])
        }
    }

    func register(typename: String, decoder: @escaping ParametersDecoder) {
        supportedTypes[typename] = decoder
    }

    func register(typename: String, item: ItemType, action: ActionType, longAction: LongActionType) {
        register(typename: typename) { _ in
            return (item: item, action: action, longAction: longAction, parameters: [:])
        }
    }
}

enum ItemType: Decodable {
    case staticButton(title: String)
    case appleScriptTitledButton(source: SourceProtocol, refreshInterval: Double)
    case timeButton(formatTemplate: String)
    case battery()
    case dock()
    case volume()
    case brightness(refreshInterval: Double)
    case weather(interval: Double, units: String, api_key: String, icon_type: String)
    case currency(interval: Double, from: String, to: String)
    case inputsource()

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case source
        case refreshInterval
        case from
        case to
        case units
        case api_key
        case icon_type
        case formatTemplate
        case image
        case url
        case longUrl
    }

    enum ItemTypeRaw: String, Decodable {
        case staticButton
        case appleScriptTitledButton
        case timeButton
        case battery
        case dock
        case volume
        case brightness
        case weather
        case currency
        case inputsource
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
        case .battery:
            self = .battery()
        case .dock:
            self = .dock()
        case .volume:
            self = .volume()
        case .brightness:
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 0.5
            self = .brightness(refreshInterval: interval)
        case .weather:
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 1800.0
            let units = try container.decodeIfPresent(String.self, forKey: .units) ?? "metric"
            let api_key = try container.decodeIfPresent(String.self, forKey: .api_key) ?? "32c4256d09a4c52b38aecddba7a078f6"
            let icon_type = try container.decodeIfPresent(String.self, forKey: .icon_type) ?? "text"
            self = .weather(interval: interval, units: units, api_key: api_key, icon_type: icon_type)
        case .currency:
            let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 600.0
            let from = try container.decodeIfPresent(String.self, forKey: .from) ?? "RUB"
            let to = try container.decodeIfPresent(String.self, forKey: .to) ?? "USD"
            self = .currency(interval: interval, from: from, to: to)
        case .inputsource:
            self = .inputsource()
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
    case openUrl(url: String)

    private enum CodingKeys: String, CodingKey {
        case action
        case keycode
        case actionAppleScript
        case executablePath
        case shellArguments
        case url
    }

    private enum ActionTypeRaw: String, Decodable {
        case hidKey
        case keyPress
        case appleScript
        case shellScript
        case openUrl
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
        case .some(.openUrl):
            let url = try container.decode(String.self, forKey: .url)
            self = .openUrl(url: url)
        case .none:
            self = .none
        }
    }
}


enum LongActionType: Decodable {
    case none
    case hidKey(keycode: Int)
    case keyPress(keycode: Int)
    case appleSctipt(source: SourceProtocol)
    case shellScript(executable: String, parameters: [String])
    case custom(closure: ()->())
    case openUrl(url: String)
    
    private enum CodingKeys: String, CodingKey {
        case longAction
        case keycode
        case actionAppleScript
        case executablePath
        case shellArguments
        case longUrl
    }
    
    private enum LongActionTypeRaw: String, Decodable {
        case hidKey
        case keyPress
        case appleScript
        case shellScript
        case openUrl
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let longType = try container.decodeIfPresent(LongActionTypeRaw.self, forKey: .longAction)
        switch longType {
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
        case .some(.openUrl):
            let longUrl = try container.decode(String.self, forKey: .longUrl)
            self = .openUrl(url: longUrl)
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
    case let (.openUrl(a), .openUrl(b)):
        return a == b
    default:
        return false
    }
}


extension LongActionType: Equatable {}
func ==(lhs: LongActionType, rhs: LongActionType) -> Bool {
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
    case let (.openUrl(a), .openUrl(b)):
        return a == b
    default:
        return false
    }
}

enum GeneralParameter {
    case width(_: CGFloat)
    case image(source: SourceProtocol)
    case align(_: Align)
    case bordered(_: Bool)
    case background(_:NSColor)
}

struct GeneralParameters: Decodable {
    let parameters: [GeneralParameters.CodingKeys: GeneralParameter]

    enum CodingKeys: String, CodingKey {
        case width
        case image
        case align
        case bordered
        case background
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
        if let borderedFlag = try container.decodeIfPresent(Bool.self, forKey: .bordered) {
            result[.bordered] = .bordered(borderedFlag)
        }
        if let backgroundColor = try container.decodeIfPresent(String.self, forKey: .background)?.hexColor {
            result[.background] = .background(backgroundColor)
        }
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
