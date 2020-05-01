import AppKit
import Foundation

extension Data {
    func barItemDefinitions() -> [BarItemDefinition]? {
        return try? JSONDecoder().decode([BarItemDefinition].self, from: utf8string!.stripComments().data(using: .utf8)!)
    }
}

struct BarItemDefinition: Decodable {
    let obj: CustomTouchBarItem
    
    enum ParsingErrors: Error {
        case noMatchingType(description: String)
    }

    private enum CodingKeys: String, CodingKey {
        case objtype = "type"
    }
    
    static let types: [CustomTouchBarItem.Type] = [
        
        // custom buttons
        CustomButtonTouchBarItem.self,
        AppleScriptTouchBarItem.self,
        ShellScriptTouchBarItem.self,
        
        
        // basic widget buttons
        EscapeBarItem.self,
        DeleteBarItem.self,
        BrightnessUpBarItem.self,
        BrightnessDownBarItem.self,
        IlluminationUpBarItem.self,
        IlluminationDownBarItem.self,
        VolumeUpBarItem.self,
        VolumeDownBarItem.self,
        MuteBarItem.self,
        PreviousBarItem.self,
        PlayBarItem.self,
        NextBarItem.self,
        SleepBarItem.self,
        DisplaySleepBarItem.self,
        
        
        // custom widgets
        TimeTouchBarItem.self,
        BatteryBarItem.self,
        AppScrubberTouchBarItem.self,
        VolumeViewController.self,
        BrightnessViewController.self,
        WeatherBarItem.self,
        YandexWeatherBarItem.self,
        CurrencyBarItem.self,
        InputSourceBarItem.self,
        MusicBarItem.self,
        NightShiftBarItem.self,
        DnDBarItem.self,
        PomodoroBarItem.self,
        NetworkBarItem.self,
        DarkModeBarItem.self,
        
        
        // custom-custom objects!
        SwipeItem.self,
        GroupBarItem.self,
        ExitTouchbarBarItem.self,
        CloseBarItem.self,
    ]

    init(obj: CustomTouchBarItem) {
        self.obj = obj
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let objType = try container.decode(String.self, forKey: .objtype)
        
        
        for obj in BarItemDefinition.types {
            if obj.typeIdentifier == objType {
                self.obj = try obj.init(from: decoder)
                return
            }
        }
        
        
        print("Cannot find preset mapping for \(objType)")
        throw ParsingErrors.noMatchingType(description: "Cannot find preset mapping for \(objType)")
    }
}

protocol SourceProtocol {
    var data: Data? { get }
    var string: String? { get }
    var image: NSImage? { get }
    var appleScript: NSAppleScript? { get }
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
        return inline ?? filePath?.fileString
    }

    var image: NSImage? {
        return data?.image
    }

    var appleScript: NSAppleScript? {
        return filePath?.fileURL.appleScript ?? string?.appleScript
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

    var appleScript: NSAppleScript? {
        return nil
    }
}

extension String {
    var base64Data: Data? {
        return Data(base64Encoded: self)
    }

    var fileData: Data? {
        return try? Data(contentsOf: URL(fileURLWithPath: (self as NSString).expandingTildeInPath))
    }

    var fileString: String? {
        var encoding: String.Encoding = .utf8
        return try? String(contentsOf: URL(fileURLWithPath: (self as NSString).expandingTildeInPath), usedEncoding: &encoding)
    }

    var fileURL: URL {
        return URL(fileURLWithPath: (self as NSString).expandingTildeInPath)
    }

    var appleScript: NSAppleScript? {
        return NSAppleScript(source: self)
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

extension URL {
    var appleScript: NSAppleScript? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSAppleScript(contentsOf: self, error: nil)
    }
}
