//
//  IconLibrary.swift
//  MTMR
//
//  The bundled outline icon set (Resources/Icons/*.svg, compiled into Assets.xcassets/Icons by
//  Resources/Icons/build-assets.py) and the helpers that put those icons on the Touch Bar.
//  Every helper degrades to the previous asset/emoji while an icon asset is missing, so a button
//  is never empty.
//

import AppKit

enum IconCategory: String, CaseIterable {
    case system = "System"
    case media = "Media"
    case widgets = "Widgets"
    case weather = "Weather"
    case general = "General"
}

struct IconInfo: Identifiable, Hashable {
    let name: String
    let title: String
    let category: IconCategory
    var id: String { name }

    init(_ name: String, _ title: String, _ category: IconCategory) {
        self.name = name
        self.title = title
        self.category = category
    }
}

enum IconLibrary {
    /// Same content and order as Resources/Icons/manifest.json; IconLibraryTests keeps the two in sync.
    /// A Swift list (rather than a bundled copy of the manifest) because the unit-test process has no
    /// app bundle, and the decoding tests need the names there.
    static let all: [IconInfo] = [
        IconInfo("brightness-down", "Brightness Down", .system),
        IconInfo("brightness-up", "Brightness Up", .system),
        IconInfo("keyboard-light-down", "Keyboard Light Down", .system),
        IconInfo("keyboard-light-up", "Keyboard Light Up", .system),
        IconInfo("display-sleep", "Display Sleep", .system),
        IconInfo("sleep", "Sleep", .system),
        IconInfo("dnd-on", "Do Not Disturb On", .system),
        IconInfo("dnd-off", "Do Not Disturb Off", .system),
        IconInfo("dark-mode-on", "Dark Mode On", .system),
        IconInfo("dark-mode-off", "Dark Mode Off", .system),
        IconInfo("night-shift-on", "Night Shift On", .system),
        IconInfo("night-shift-off", "Night Shift Off", .system),
        IconInfo("delete", "Delete", .system),
        IconInfo("close", "Close", .system),
        IconInfo("power", "Power", .system),
        IconInfo("lock", "Lock", .system),
        IconInfo("gear", "Settings", .system),
        IconInfo("keyboard", "Keyboard", .system),
        IconInfo("app-grid", "Apps", .system),
        IconInfo("cpu", "CPU", .system),
        IconInfo("hourglass", "Loading", .system),
        IconInfo("volume-down", "Volume Down", .media),
        IconInfo("volume-up", "Volume Up", .media),
        IconInfo("volume-mute", "Mute", .media),
        IconInfo("previous", "Previous", .media),
        IconInfo("play-pause", "Play / Pause", .media),
        IconInfo("next", "Next", .media),
        IconInfo("play", "Play", .media),
        IconInfo("pause", "Pause", .media),
        IconInfo("music-note", "Music", .media),
        IconInfo("microphone", "Microphone", .media),
        IconInfo("headphones", "Headphones", .media),
        IconInfo("battery", "Battery", .widgets),
        IconInfo("battery-charging", "Battery Charging", .widgets),
        IconInfo("bolt", "Bolt", .widgets),
        IconInfo("clock", "Clock", .widgets),
        IconInfo("timer", "Timer", .widgets),
        IconInfo("calendar", "Calendar", .widgets),
        IconInfo("weather-clear-day", "Sunny", .weather),
        IconInfo("weather-clear-night", "Clear Night", .weather),
        IconInfo("weather-partly-cloudy", "Partly Cloudy", .weather),
        IconInfo("weather-cloudy", "Cloudy", .weather),
        IconInfo("weather-drizzle", "Drizzle", .weather),
        IconInfo("weather-rain", "Rain", .weather),
        IconInfo("weather-thunder", "Thunderstorm", .weather),
        IconInfo("weather-snow", "Snow", .weather),
        IconInfo("weather-fog", "Fog", .weather),
        IconInfo("thermometer", "Temperature", .weather),
        IconInfo("network-up", "Upload", .widgets),
        IconInfo("network-down", "Download", .widgets),
        IconInfo("currency", "Currency", .widgets),
        IconInfo("globe", "Globe", .general),
        IconInfo("wifi", "Wi-Fi", .general),
        IconInfo("star", "Star", .general),
        IconInfo("heart", "Heart", .general),
        IconInfo("home", "Home", .general),
        IconInfo("folder", "Folder", .general),
        IconInfo("document", "Document", .general),
        IconInfo("terminal", "Terminal", .general),
        IconInfo("code", "Code", .general),
        IconInfo("mail", "Mail", .general),
        IconInfo("message", "Message", .general),
        IconInfo("magnifier", "Search", .general),
        IconInfo("camera", "Camera", .general),
        IconInfo("lightbulb", "Idea", .general),
        IconInfo("link", "Link", .general),
        IconInfo("bookmark", "Bookmark", .general),
        IconInfo("trash", "Trash", .general),
        IconInfo("bell", "Bell", .general),
        IconInfo("download", "Download File", .general),
        IconInfo("refresh", "Refresh", .general),
        IconInfo("user", "User", .general),
        IconInfo("flag", "Flag", .general),
        IconInfo("map-pin", "Location", .general),
    ]

    private static let byName: [String: IconInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    static func info(for name: String) -> IconInfo? { byName[name] }

    // MARK: Loading

    /// How an icon name becomes an image. Replaceable so tests and tools can load the SVGs from disk.
    /// The catalog folder provides a namespace ("Icons/cpu") because the catalog still holds legacy
    /// imagesets with the same names ("cpu", "dnd-on", ...).
    static var loader: (String) -> NSImage? = { NSImage(named: "Icons/" + $0) }

    /// Template image (drawn in the control's text colour) or nil for an unknown name or a missing asset.
    static func image(named name: String) -> NSImage? {
        guard byName[name] != nil, let image = loader(name) else { return nil }
        image.isTemplate = true
        return image
    }

    /// The icon, or `fallback` while the asset is missing (the fallback is only evaluated then).
    static func image(named name: String, fallback: @autoclosure () -> NSImage?) -> NSImage? {
        image(named: name) ?? fallback()
    }

    // MARK: Inline use in attributed titles

    /// A copy of the icon filled with `color`. NSTextAttachment images are not tinted by the text
    /// colour, so the template has to be baked into the colour the text uses.
    static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        return result
    }

    /// The icon as a single attachment character sized to `font` and centred on its cap height,
    /// or nil while the asset is missing.
    static func inlineIcon(_ name: String, color: NSColor, font: NSFont) -> NSAttributedString? {
        guard let image = image(named: name) else { return nil }
        let side = (font.pointSize * 1.1).rounded()
        let attachment = NSTextAttachment()
        attachment.image = tinted(image, color: color)
        attachment.bounds = CGRect(x: 0, y: ((font.capHeight - side) / 2).rounded(), width: side, height: side)
        return NSAttributedString(attachment: attachment)
    }

    // MARK: Defaults

    /// Icon shown by built-in item types that have no "image" in the preset.
    /// Used by the item itself (via SupportedTypesHolder/widgets) and by the customizer for its preview.
    static let builtInDefaults: [String: String] = [
        "brightnessUp": "brightness-up", "brightnessDown": "brightness-down",
        "illuminationUp": "keyboard-light-up", "illuminationDown": "keyboard-light-down",
        "volumeUp": "volume-up", "volumeDown": "volume-down", "mute": "volume-mute",
        "previous": "previous", "play": "play-pause", "next": "next",
        "sleep": "sleep", "displaySleep": "display-sleep", "delete": "delete",
        "exitTouchbar": "close", "close": "close",
        "dnd": "dnd-off", "darkMode": "dark-mode-off", "nightShift": "night-shift-off", "cpu": "cpu",
    ]

    /// OpenWeatherMap condition code ("01d", "10n", ...) to icon name.
    static func weatherIcon(openWeatherCode code: String) -> String? {
        let night = code.hasSuffix("n")
        switch code.prefix(2) {
        case "01": return night ? "weather-clear-night" : "weather-clear-day"
        case "02": return "weather-partly-cloudy"
        case "03", "04": return "weather-cloudy"
        case "09": return "weather-drizzle"
        case "10": return "weather-rain"
        case "11": return "weather-thunder"
        case "13": return "weather-snow"
        case "50": return "weather-fog"
        default: return nil
        }
    }

    /// Yandex condition ("partly-cloudy", ...) to icon name. The page gives no day/night flag, so "clear" is the day icon.
    static func weatherIcon(yandexCondition condition: String) -> String? {
        switch condition {
        case "clear", "mostly-clear": return "weather-clear-day"
        case "partly-cloudy": return "weather-partly-cloudy"
        case "overcast", "cloudy": return "weather-cloudy"
        case "light-rain", "drizzle": return "weather-drizzle"
        case "rain", "heavy-rain", "sleet": return "weather-rain"
        case "storm", "thunderstorm-with-rain": return "weather-thunder"
        case "light-snow", "snow": return "weather-snow"
        case "fog": return "weather-fog"
        default: return nil
        }
    }
}
