//
//  ItemCatalog.swift
//  MTMR
//
//  What the customizer knows about each item type: display name, category, SF Symbol,
//  editable fields and the JSON a freshly added item starts with.
//  Source of truth: ItemsParsing.swift (SupportedTypesHolder built-ins, ItemType.ItemTypeRaw,
//  Action) plus the two types TouchBarController registers ("exitTouchbar", "close"); README.md
//  only for wording. Where README and decoder defaults differ the decoder wins (see FieldSpec defaults).
//

import Foundation

enum ItemCategory: String, CaseIterable, Identifiable {
    case buttons = "System Buttons"
    case media = "Media Keys"
    case sliders = "Sliders"
    case widgets = "Widgets"
    case custom = "Custom Buttons"
    case layout = "Groups & Gestures"
    var id: String { rawValue }
}

struct FieldSpec: Identifiable {
    enum Kind {
        case text(placeholder: String?)
        case multilineText
        case integer(range: ClosedRange<Int>?)
        case number(range: ClosedRange<Double>?, unit: String?)
        case bool
        case choice([String])
        /// A script source object: `{"inline": "..."}`, `{"filePath": "..."}` or `{"base64": "..."}`.
        case scriptSource
        /// Array of strings (e.g. "shellArguments").
        case stringList
    }

    let key: String
    let label: String
    let kind: Kind
    /// Shown below the control; keep it to one short sentence.
    let help: String?
    /// Written when the user enables an optional field; nil = field is left out of the JSON until edited.
    let defaultValue: JSONValue?

    var id: String { key }
}

struct ItemTypeInfo: Identifiable {
    /// The JSON "type" value.
    let type: String
    let displayName: String
    let category: ItemCategory
    /// SF Symbol name (macOS 11+) used in the palette, list and preview.
    let symbolName: String
    /// One sentence describing what the item does.
    let summary: String
    /// Type-specific fields (common parameters are in `ItemCatalog.commonFields`).
    let fields: [FieldSpec]
    /// Whether the item accepts "actions" (taps) — custom buttons do, most widgets don't need them.
    let supportsActions: Bool
    /// JSON for a newly added item; must contain "type" and be accepted by the app's decoder.
    let defaultJSON: JSONObject

    var id: String { type }
}

struct ActionTypeInfo: Identifiable {
    /// The JSON "action" value.
    let action: String
    let displayName: String
    let fields: [FieldSpec]
    var id: String { action }
}

enum ItemCatalog {
    /// Every type the app understands (README + ItemsParsing.swift), in palette order.
    static let all: [ItemTypeInfo] = [
        // MARK: System buttons
        button("escape", "Escape", "escape", "Sends the Esc key (always left-aligned by the app)."),
        button("delete", "Delete", "delete.right", "Sends the forward-delete key. Not listed in the README, but the decoder accepts it."),
        button("exitTouchbar", "Exit Touch Bar", "xmark.circle", "Dismisses MTMR's Touch Bar."),
        button("brightnessDown", "Brightness Down", "sun.min", "Lowers the display brightness."),
        button("brightnessUp", "Brightness Up", "sun.max", "Raises the display brightness."),
        button("illuminationDown", "Keyboard Light Down", "light.min", "Lowers the keyboard backlight."),
        button("illuminationUp", "Keyboard Light Up", "light.max", "Raises the keyboard backlight."),
        button("volumeDown", "Volume Down", "speaker.wave.1", "Lowers the sound volume."),
        button("volumeUp", "Volume Up", "speaker.wave.3", "Raises the sound volume."),
        button("mute", "Mute", "speaker.slash", "Mutes or unmutes the sound output."),
        button("sleep", "Sleep", "moon.zzz", "Puts the Mac to sleep."),
        button("displaySleep", "Display Sleep", "display", "Turns the display off."),
        button("dnd", "Do Not Disturb", "moon", "Toggles Do Not Disturb."),
        button("nightShift", "Night Shift", "sun.haze", "Toggles Night Shift."),
        button("darkMode", "Dark Mode", "circle.lefthalf.filled", "Toggles the system appearance."),
        button("inputsource", "Input Source", "keyboard", "Shows the current keyboard layout; tap to switch."),

        // MARK: Media keys
        ItemTypeInfo(type: "previous", displayName: "Previous Track", category: .media, symbolName: "backward", summary: "Media key: previous track.", fields: [], supportsActions: false, defaultJSON: obj("previous")),
        ItemTypeInfo(type: "play", displayName: "Play / Pause", category: .media, symbolName: "playpause", summary: "Media key: play or pause.", fields: [], supportsActions: false, defaultJSON: obj("play")),
        ItemTypeInfo(type: "next", displayName: "Next Track", category: .media, symbolName: "forward", summary: "Media key: next track.", fields: [], supportsActions: false, defaultJSON: obj("next")),
        ItemTypeInfo(
            type: "music", displayName: "Now Playing", category: .media, symbolName: "music.note",
            summary: "Shows the current track; tap pauses, long tap skips.",
            fields: [refresh(5), bool("disableMarquee", "Disable marquee", "Turns off the scrolling title effect.", false)],
            supportsActions: true, defaultJSON: obj("music")
        ),

        // MARK: Sliders
        ItemTypeInfo(type: "brightness", displayName: "Brightness Slider", category: .sliders, symbolName: "sun.max", summary: "Slider for the display brightness.", fields: [refresh(0.5)], supportsActions: false, defaultJSON: obj("brightness")),
        ItemTypeInfo(type: "volume", displayName: "Volume Slider", category: .sliders, symbolName: "speaker.wave.3", summary: "Slider for the sound volume.", fields: [], supportsActions: false, defaultJSON: obj("volume")),

        // MARK: Widgets
        ItemTypeInfo(
            type: "timeButton", displayName: "Clock", category: .widgets, symbolName: "clock",
            summary: "Shows the current time or date.",
            fields: [
                text("formatTemplate", "Format", "HH:mm", "Date format pattern, e.g. \"dd HH:mm\".", "HH:mm"),
                text("locale", "Locale", "en_GB", "Optional locale identifier.", nil),
                text("timeZone", "Time zone", "UTC", "Optional time zone abbreviation or identifier.", nil),
            ],
            supportsActions: true, defaultJSON: obj("timeButton")
        ),
        ItemTypeInfo(type: "battery", displayName: "Battery", category: .widgets, symbolName: "battery.100", summary: "Shows the battery level.", fields: [], supportsActions: true, defaultJSON: obj("battery")),
        ItemTypeInfo(type: "cpu", displayName: "CPU Load", category: .widgets, symbolName: "cpu", summary: "Shows the current CPU load.", fields: [refresh(5)], supportsActions: true, defaultJSON: obj("cpu")),
        ItemTypeInfo(
            type: "currency", displayName: "Currency Rate", category: .widgets, symbolName: "dollarsign.circle",
            summary: "Shows an exchange rate (Coinbase).",
            fields: [
                refresh(600),
                text("from", "From", "BTC", "Currency code to convert from.", "RUB"),
                text("to", "To", "USD", "Currency code to convert to.", "USD"),
                bool("full", "Full format", "Shows the currency symbols in addition to the rate.", false),
            ],
            supportsActions: true, defaultJSON: obj("currency", ("from", .string("BTC")), ("to", .string("USD")))
        ),
        ItemTypeInfo(
            type: "weather", displayName: "Weather", category: .widgets, symbolName: "cloud.sun",
            summary: "Shows the local weather (OpenWeatherMap).",
            fields: [
                refresh(1800),
                choice("units", "Units", ["metric", "imperial"], "Temperature units.", "metric"),
                choice("icon_type", "Icons", ["text", "images"], "Show the condition as text or as an image.", "text"),
                text("api_key", "API key", nil, "Your OpenWeatherMap key; leave empty to use the built-in one.", nil),
            ],
            supportsActions: true, defaultJSON: obj("weather")
        ),
        ItemTypeInfo(type: "yandexWeather", displayName: "Yandex Weather", category: .widgets, symbolName: "cloud.rain", summary: "Experimental: weather from Yandex; tap opens the forecast.", fields: [refresh(1800)], supportsActions: true, defaultJSON: obj("yandexWeather")),
        ItemTypeInfo(
            type: "dock", displayName: "Dock", category: .widgets, symbolName: "dock.rectangle",
            summary: "Shows running apps; half-long tap opens, long tap kills.",
            fields: [
                text("filter", "Filter", "(^Xcode$)|(Safari)", "Regular expression; only matching app names are shown.", nil),
                bool("autoResize", "Auto resize", "Expands the widget to fit all apps.", false),
            ],
            supportsActions: false, defaultJSON: obj("dock")
        ),
        ItemTypeInfo(
            type: "pomodoro", displayName: "Pomodoro", category: .widgets, symbolName: "timer",
            summary: "Tap starts the work timer, long tap the rest timer.",
            fields: [
                number("workTime", "Work time", 1500, "seconds", "Seconds of work."),
                number("restTime", "Rest time", 600, "seconds", "Seconds of rest."),
            ],
            supportsActions: true, defaultJSON: obj("pomodoro")
        ),
        ItemTypeInfo(
            type: "network", displayName: "Network Speed", category: .widgets, symbolName: "network",
            summary: "Shows the current network throughput.",
            fields: [
                bool("flip", "Flip", "Swaps the upload and download rows.", false),
                choice("units", "Units", ["dynamic", "B/s", "KB/s", "MB/s", "GB/s"], "Unit of the speed; dynamic picks the best fit.", "dynamic"),
            ],
            supportsActions: true, defaultJSON: obj("network")
        ),
        ItemTypeInfo(
            type: "upnext", displayName: "Up Next", category: .widgets, symbolName: "calendar",
            summary: "Shows upcoming events from the Calendar.",
            fields: [
                number("from", "From", 0, "hours", "Start of the search range in hours from now (may be negative)."),
                number("to", "To", 12, "hours", "End of the search range in hours from now."),
                FieldSpec(key: "maxToShow", label: "Max events", kind: .integer(range: 1 ... 20), help: "Maximum number of events shown.", defaultValue: .int(3)),
                bool("autoResize", "Auto resize", "Expands the widget to show all events.", false),
            ],
            supportsActions: false, defaultJSON: obj("upnext")
        ),

        // MARK: Custom buttons
        ItemTypeInfo(
            type: "staticButton", displayName: "Static Button", category: .custom, symbolName: "rectangle.and.hand.point.up.left",
            summary: "A button with a fixed title and/or image that runs actions.",
            fields: [], supportsActions: true,
            defaultJSON: obj("staticButton", ("title", .string("Button")))
        ),
        ItemTypeInfo(
            type: "appleScriptTitledButton", displayName: "AppleScript Button", category: .custom, symbolName: "applescript",
            summary: "A button whose title is the result of an AppleScript.",
            fields: [scriptSource("source", "Script", "AppleScript returning the title."), refresh(1800)],
            supportsActions: true,
            defaultJSON: obj("appleScriptTitledButton", ("source", .object(JSONObject(pairs: [("inline", .string("return \"Hello\""))]))))
        ),
        ItemTypeInfo(
            type: "shellScriptTitledButton", displayName: "Shell Script Button", category: .custom, symbolName: "terminal",
            summary: "A button whose title is the output of a shell script.",
            fields: [scriptSource("source", "Script", "Shell script printing the title."), refresh(1800)],
            supportsActions: true,
            defaultJSON: obj("shellScriptTitledButton", ("source", .object(JSONObject(pairs: [("inline", .string("echo Hello"))]))))
        ),

        // MARK: Groups & gestures
        ItemTypeInfo(
            type: "group", displayName: "Group", category: .layout, symbolName: "rectangle.3.group",
            summary: "A button that opens a sub-bar with more items.",
            fields: [], supportsActions: false,
            // "items" is lifted into PresetItem.children by PresetDocument; it is here so the JSON decodes.
            defaultJSON: obj("group", ("title", .string("Group")), ("items", .array([])))
        ),
        ItemTypeInfo(type: "close", displayName: "Close Group", category: .layout, symbolName: "xmark", summary: "Closes an open group and returns to the main bar.", fields: [], supportsActions: false, defaultJSON: obj("close")),
        ItemTypeInfo(
            type: "swipe", displayName: "Swipe Gesture", category: .layout, symbolName: "hand.draw",
            summary: "Runs a script on a multi-finger swipe over the Touch Bar.",
            fields: [
                // Integer, not a string choice: the decoder reads "fingers" as Int.
                FieldSpec(key: "fingers", label: "Fingers", kind: .integer(range: 2 ... 4), help: "Number of fingers (2, 3 or 4).", defaultValue: .int(4)),
                choice("direction", "Direction", ["left", "right"], "Swipe direction.", "right"),
                number("minOffset", "Min offset", 0, "pt", "Minimal distance before the gesture fires."),
                scriptSource("sourceApple", "AppleScript", "Optional AppleScript to run."),
                scriptSource("sourceBash", "Shell script", "Optional shell script to run."),
            ],
            supportsActions: false,
            defaultJSON: obj("swipe", ("fingers", .int(4)), ("direction", .string("right")))
        ),
    ]

    static func info(for type: String) -> ItemTypeInfo? {
        all.first { $0.type == type }
    }

    static func types(in category: ItemCategory) -> [ItemTypeInfo] {
        all.filter { $0.category == category }
    }

    /// Parameters every visual item accepts: title, width, align, bordered, background, image, matchAppId.
    static let commonFields: [FieldSpec] = [
        text("title", "Title", nil, "Text shown on the button.", nil),
        FieldSpec(key: "width", label: "Width", kind: .integer(range: 1 ... 2000), help: "Width in points; omit for automatic.", defaultValue: .int(64)),
        choice("align", "Alignment", ["left", "center", "right"], "Zone of the Touch Bar.", "center"),
        bool("bordered", "Bordered", "Draws the button background.", true),
        text("background", "Background", "#RRGGBB", "Hex color, e.g. #FF0000.", "#FF0000"),
        // Same {filePath|base64} object shape as a script source; the UI renders an image picker for this key.
        FieldSpec(key: "image", label: "Image", kind: .scriptSource, help: "Icon (resized to 24x24): base64 data or a file path.", defaultValue: nil),
        text("matchAppId", "Only in app", "com\\.apple\\.Safari", "Regular expression on the bundle identifier; the item is shown only in matching apps.", nil),
    ]

    /// "singleTap", "doubleTap", "tripleTap", "longTap".
    static let actionTriggers: [String] = ["singleTap", "doubleTap", "tripleTap", "longTap"]

    /// hidKey, keyPress, appleScript, shellScript, openUrl with their parameters.
    static let actionTypes: [ActionTypeInfo] = [
        ActionTypeInfo(action: "hidKey", displayName: "Media / system key", fields: [
            FieldSpec(key: "keycode", label: "Key code", kind: .integer(range: 0 ... 255), help: "NX_KEYTYPE_* value, e.g. 0 = sound up, 1 = sound down, 7 = mute.", defaultValue: .int(0)),
        ]),
        ActionTypeInfo(action: "keyPress", displayName: "Key press", fields: [
            FieldSpec(key: "keycode", label: "Key code", kind: .integer(range: 0 ... 255), help: "Virtual key code, e.g. 53 = Esc.", defaultValue: .int(53)),
        ]),
        ActionTypeInfo(action: "appleScript", displayName: "AppleScript", fields: [
            scriptSource("actionAppleScript", "Script", "AppleScript to run."),
        ]),
        ActionTypeInfo(action: "shellScript", displayName: "Shell script", fields: [
            text("executablePath", "Executable", "/usr/bin/open", "Absolute path of the program.", "/usr/bin/open"),
            FieldSpec(key: "shellArguments", label: "Arguments", kind: .stringList, help: "One entry per argument.", defaultValue: .array([])),
        ]),
        ActionTypeInfo(action: "openUrl", displayName: "Open URL", fields: [
            text("url", "URL", "https://example.com", "URL opened in the default handler.", "https://"),
        ]),
    ]

    // MARK: Builders

    private static func obj(_ type: String, _ extra: (String, JSONValue)...) -> JSONObject {
        JSONObject(pairs: [("type", .string(type))] + extra)
    }

    private static func button(_ type: String, _ name: String, _ symbol: String, _ summary: String) -> ItemTypeInfo {
        ItemTypeInfo(type: type, displayName: name, category: .buttons, symbolName: symbol, summary: summary, fields: [], supportsActions: false, defaultJSON: obj(type))
    }

    private static func text(_ key: String, _ label: String, _ placeholder: String?, _ help: String, _ def: String?) -> FieldSpec {
        FieldSpec(key: key, label: label, kind: .text(placeholder: placeholder), help: help, defaultValue: def.map(JSONValue.string))
    }

    private static func bool(_ key: String, _ label: String, _ help: String, _ def: Bool) -> FieldSpec {
        FieldSpec(key: key, label: label, kind: .bool, help: help, defaultValue: .bool(def))
    }

    private static func choice(_ key: String, _ label: String, _ options: [String], _ help: String, _ def: String) -> FieldSpec {
        FieldSpec(key: key, label: label, kind: .choice(options), help: help, defaultValue: .string(def))
    }

    private static func number(_ key: String, _ label: String, _ def: Double, _ unit: String?, _ help: String) -> FieldSpec {
        FieldSpec(key: key, label: label, kind: .number(range: nil, unit: unit), help: help, defaultValue: def.rounded() == def ? .int(Int64(def)) : .double(def))
    }

    /// "refreshInterval" in seconds; `def` is the default of the decoder in ItemsParsing.swift.
    private static func refresh(_ def: Double) -> FieldSpec {
        number("refreshInterval", "Refresh interval", def, "seconds", "How often the value is updated.")
    }

    private static func scriptSource(_ key: String, _ label: String, _ help: String) -> FieldSpec {
        FieldSpec(key: key, label: label, kind: .scriptSource, help: help, defaultValue: .object(JSONObject(pairs: [("inline", .string(""))])))
    }
}
