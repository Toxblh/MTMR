//
//  ItemCatalog.swift
//  MTMR
//
//  What the customizer knows about each item type: display name, category, SF Symbol,
//  editable fields and the JSON a freshly added item starts with.
//  Source of truth: README.md ("Built-in button types", "Native plugins", "Actions",
//  "Additional parameters") and ItemsParsing.swift.
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
    static let all: [ItemTypeInfo] = [] // TODO: filled by the model agent

    static func info(for type: String) -> ItemTypeInfo? {
        all.first { $0.type == type }
    }

    static func types(in category: ItemCategory) -> [ItemTypeInfo] {
        all.filter { $0.category == category }
    }

    /// Parameters every visual item accepts: title, width, align, bordered, background, image, matchAppId.
    static let commonFields: [FieldSpec] = [] // TODO: filled by the model agent

    /// "singleTap", "doubleTap", "tripleTap", "longTap".
    static let actionTriggers: [String] = ["singleTap", "doubleTap", "tripleTap", "longTap"]

    /// hidKey, keyPress, appleScript, shellScript, openUrl with their parameters.
    static let actionTypes: [ActionTypeInfo] = [] // TODO: filled by the model agent
}
