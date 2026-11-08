//
//  PresetDocument.swift
//  MTMR
//
//  Editable model of a preset file (items.json) for the Touch Bar customizer.
//  Compiled into the app AND the test target, so it must not reference TouchBarController
//  or AppKit-only UI types; the app injects `onSaved` to trigger a reload.
//

import Foundation

enum PresetAlign: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// One entry of the preset array. Group children are lifted out of the JSON into `children`
/// so they can be selected and edited like top-level items; they are written back to "items" on save.
struct PresetItem: Identifiable, Equatable {
    let id: UUID
    /// The item's JSON object. For groups the "items" key is NOT kept here (see `children`).
    var json: JSONObject
    /// Non-nil only for `"type": "group"`.
    var children: [PresetItem]?

    init(id: UUID = UUID(), json: JSONObject, children: [PresetItem]? = nil) {
        self.id = id
        self.json = json
        self.children = children
    }

    var type: String { json["type"]?.stringValue ?? "" }

    /// Missing or unknown "align" means center (TouchBarController/ItemsParsing default).
    var align: PresetAlign {
        get { json["align"]?.stringValue.flatMap(PresetAlign.init(rawValue:)) ?? .center }
        set { json["align"] = .string(newValue.rawValue) }
    }

    /// Gestures ("swipe") have no visual on the Touch Bar.
    var isGesture: Bool { type == "swipe" }
}

final class PresetDocument: ObservableObject {
    /// ~/Library/Application Support/MTMR/items.json (same path as `standardConfigPath`).
    static var standardFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTMR/items.json")
    }

    let fileURL: URL

    /// Top-level items in file order.
    @Published var items: [PresetItem] = [] {
        didSet { if !isLoading { isDirty = true } }
    }

    @Published private(set) var isDirty = false
    /// Set when the file could not be read or parsed; `items` is then empty.
    @Published private(set) var loadError: String?

    /// Called on the main queue after a successful save (the app reloads the Touch Bar here).
    var onSaved: (() -> Void)?

    private var isLoading = false

    init(fileURL: URL = PresetDocument.standardFileURL) {
        self.fileURL = fileURL
    }

    // MARK: File I/O

    /// Reads and parses `fileURL`, replacing `items`, clearing `isDirty`.
    func load() {
        fatalError("TODO: implemented by the model agent")
    }

    /// Discards unsaved edits (same as `load()`).
    func revert() { load() }

    /// The preset as it would be written by `save()`.
    func serializedText() -> String {
        fatalError("TODO: implemented by the model agent")
    }

    /// nil when the app's real decoder (`JSONDecoder().decode([BarItemDefinition].self, …)`) accepts
    /// `serializedText()`, otherwise a human-readable reason. Must never trap
    /// (do NOT use `Data.barItemDefinitions()`, it uses `try!`).
    func validate() -> String? {
        fatalError("TODO: implemented by the model agent")
    }

    /// Validates, makes a one-time backup if the file on disk contains comments,
    /// writes IN PLACE (no atomic replace: AppDelegate watches the file's descriptor),
    /// clears `isDirty`, then calls `onSaved`.
    func save() throws {
        fatalError("TODO: implemented by the model agent")
    }

    // MARK: Queries

    /// Visual top-level items with the given alignment, in file order (gestures excluded).
    func items(in align: PresetAlign) -> [PresetItem] {
        fatalError("TODO: implemented by the model agent")
    }

    /// Top-level gesture items ("swipe").
    var gestures: [PresetItem] {
        fatalError("TODO: implemented by the model agent")
    }

    /// Finds an item anywhere in the tree (top level or inside a group).
    func item(withID id: PresetItem.ID) -> PresetItem? {
        fatalError("TODO: implemented by the model agent")
    }

    // MARK: Editing (all mark the document dirty)

    /// Replaces the item with the same id anywhere in the tree.
    func update(_ item: PresetItem) {
        fatalError("TODO: implemented by the model agent")
    }

    /// Inserts a new item of `type` (default JSON from `ItemCatalog`) with the given alignment,
    /// at the end of that zone, or into the group `parent` when given. Returns the new id.
    @discardableResult
    func add(type: String, align: PresetAlign, intoGroup parent: PresetItem.ID? = nil) -> PresetItem.ID {
        fatalError("TODO: implemented by the model agent")
    }

    /// Removes the item anywhere in the tree.
    func remove(id: PresetItem.ID) {
        fatalError("TODO: implemented by the model agent")
    }

    /// Inserts a copy (new ids, recursively) right after the original. Returns the copy's id.
    @discardableResult
    func duplicate(id: PresetItem.ID) -> PresetItem.ID? {
        fatalError("TODO: implemented by the model agent")
    }

    /// Reorders within one zone, with List.onMove semantics (`source` and `destination` are
    /// indices into `items(in: align)`). Relative order of other zones is untouched.
    func move(in align: PresetAlign, from source: IndexSet, to destination: Int) {
        fatalError("TODO: implemented by the model agent")
    }

    /// Reorders children of a group with List.onMove semantics.
    func moveChildren(ofGroup group: PresetItem.ID, from source: IndexSet, to destination: Int) {
        fatalError("TODO: implemented by the model agent")
    }
}
