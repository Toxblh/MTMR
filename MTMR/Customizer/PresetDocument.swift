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
    /// Where the "items" key stood among the group's keys in the file, so saving keeps the
    /// original key order (nil = append at the end). Additive to the contract; not meant for the UI.
    var itemsKeyPosition: Int?

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
        isLoading = true
        defer {
            isLoading = false
            isDirty = false
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                throw PresetDocumentError.message("The file is not valid UTF-8 text.")
            }
            let root = try JSONValue.parse(text)
            guard case let .array(elements) = root else {
                throw PresetDocumentError.message("The preset must be a JSON array of items at the top level.")
            }
            items = try elements.enumerated().map { index, element in
                try PresetDocument.makeItem(from: element, path: "Item \(index + 1)")
            }
            loadError = nil
        } catch {
            items = []
            loadError = error.localizedDescription
        }
    }

    /// Discards unsaved edits (same as `load()`).
    func revert() { load() }

    private static func makeItem(from value: JSONValue, path: String) throws -> PresetItem {
        guard case var .object(object) = value else {
            throw PresetDocumentError.message("\(path) is not a JSON object.")
        }
        // Only real groups get their "items" lifted; any other type keeps the key as plain JSON.
        guard object["type"]?.stringValue == "group" else { return PresetItem(json: object) }
        var position: Int?
        var children: [PresetItem] = []
        if let index = object.keys.firstIndex(of: "items") {
            position = index
            guard case let .array(elements)? = object["items"] else {
                throw PresetDocumentError.message("\(path): \"items\" of a group must be an array.")
            }
            children = try elements.enumerated().map { index, element in
                try makeItem(from: element, path: "\(path), child \(index + 1)")
            }
            object["items"] = nil
        }
        var item = PresetItem(json: object, children: children)
        item.itemsKeyPosition = position
        return item
    }

    private static func jsonObject(of item: PresetItem) -> JSONObject {
        guard let children = item.children else { return item.json }
        var entries = item.json.entries
        let entry = JSONObject.Entry(key: "items", value: .array(children.map { .object(jsonObject(of: $0)) }))
        entries.insert(entry, at: min(item.itemsKeyPosition ?? entries.count, entries.count))
        return JSONObject(entries)
    }

    /// The preset as it would be written by `save()`.
    func serializedText() -> String {
        JSONValue.array(items.map { .object(PresetDocument.jsonObject(of: $0)) }).serialized(indent: 2)
    }

    /// nil when the app's real decoder (`JSONDecoder().decode([BarItemDefinition].self, …)`) accepts
    /// `serializedText()`, otherwise a human-readable reason. Must never trap
    /// (not `Data.barItemDefinitions()`, which only returns nil and loses the reason).
    ///
    /// Stricter than the app on one point: `BarItemDefinition` swallows errors of the type-specific
    /// parameters (a swipe without "fingers" silently becomes an "unknown" button), so each item whose
    /// type is decoded by `ItemType` is decoded once more directly to surface such mistakes.
    func validate() -> String? {
        do {
            _ = try JSONDecoder().decode([BarItemDefinition].self, from: Data(serializedText().utf8))
        } catch {
            return PresetDocument.describe(error)
        }
        for (index, item) in items.enumerated() {
            if let message = PresetDocument.strictCheck(item, path: "Item \(index + 1)") { return message }
        }
        return nil
    }

    private static func strictCheck(_ item: PresetItem, path: String) -> String? {
        let name = item.type.isEmpty ? path : "\(path) (\(item.type))"
        if ItemType.ItemTypeRaw(rawValue: item.type) != nil {
            do {
                let data = Data(JSONValue.object(jsonObject(of: item)).serialized().utf8)
                _ = try JSONDecoder().decode(ItemType.self, from: data)
            } catch {
                return "\(name): \(describe(error))"
            }
        }
        for (index, child) in (item.children ?? []).enumerated() {
            if let message = strictCheck(child, path: "\(path), child \(index + 1)") { return message }
        }
        return nil
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        let context: DecodingError.Context
        var prefix = ""
        switch decoding {
        case let .typeMismatch(_, c), let .valueNotFound(_, c), let .dataCorrupted(c):
            context = c
        case let .keyNotFound(key, c):
            context = c
            prefix = "Missing key “\(key.stringValue)”. "
        @unknown default:
            return decoding.localizedDescription
        }
        let path = context.codingPath.map { $0.intValue.map { "[\($0 + 1)]" } ?? ".\($0.stringValue)" }.joined()
        return "\(prefix)\(context.debugDescription)" + (path.isEmpty ? "" : " (at \(path))")
    }

    /// Validates, makes a one-time backup if the file on disk contains comments,
    /// writes IN PLACE (no atomic replace: AppDelegate watches the file's descriptor),
    /// clears `isDirty`, then calls `onSaved`.
    func save() throws {
        if let problem = validate() {
            throw PresetDocumentError.message("The preset is invalid and was not saved. \(problem)")
        }
        let fm = FileManager.default
        let data = Data(serializedText().utf8)

        if fm.fileExists(atPath: fileURL.path) {
            let existing = try Data(contentsOf: fileURL)
            if let old = String(data: existing, encoding: .utf8), JSONValue.containsComments(old) {
                let backup = backupURL
                // Never overwrite: the first backup is the user's original hand-written file.
                if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: fileURL, to: backup) }
            }
            try PresetDocument.writeInPlace(data, to: fileURL, previousSize: existing.count)
        } else {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: fileURL.path, contents: data) else {
                throw PresetDocumentError.message("Could not create \(fileURL.path).")
            }
        }
        isDirty = false
        DispatchQueue.main.async { [onSaved] in onSaved?() }
    }

    /// `items.json` -> `items.backup.json` in the same directory.
    var backupURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + ".backup." + fileURL.pathExtension)
    }

    /// Overwrites the file's contents keeping its inode (the app's O_EVTONLY watcher stays attached).
    /// When the new text is shorter, the old tail is first overwritten with spaces and cut off
    /// afterwards, so the file is valid JSON at every instant: the watcher reloads with `try!`
    /// and would crash on a truncated or half-overwritten file.
    private static func writeInPlace(_ data: Data, to url: URL, previousSize: Int) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var padded = data
        if previousSize > data.count {
            padded.append(Data(repeating: UInt8(ascii: " "), count: previousSize - data.count))
        }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: padded)
        try handle.synchronize()
        if padded.count > data.count {
            try handle.truncate(atOffset: UInt64(data.count))
            try handle.synchronize()
        }
    }

    // MARK: Queries

    /// Visual top-level items with the given alignment, in file order (gestures excluded).
    func items(in align: PresetAlign) -> [PresetItem] {
        items.filter { !$0.isGesture && $0.align == align }
    }

    /// Top-level gesture items ("swipe").
    var gestures: [PresetItem] {
        items.filter(\.isGesture)
    }

    /// Finds an item anywhere in the tree (top level or inside a group).
    func item(withID id: PresetItem.ID) -> PresetItem? {
        PresetDocument.find(id, in: items)
    }

    private static func find(_ id: PresetItem.ID, in list: [PresetItem]) -> PresetItem? {
        for item in list {
            if item.id == id { return item }
            if let found = find(id, in: item.children ?? []) { return found }
        }
        return nil
    }

    // MARK: Editing (all mark the document dirty)

    // All mutations work on a copy and assign `items` once, so `didSet` (dirty flag + @Published)
    // fires exactly once and nested edits cannot bypass it.

    /// Applies `change` to the list that directly contains `id`; returns false if `id` is not found.
    private static func mutateContainer(of id: PresetItem.ID, in list: inout [PresetItem],
                                        _ change: (inout [PresetItem], Int) -> Void) -> Bool {
        if let index = list.firstIndex(where: { $0.id == id }) {
            change(&list, index)
            return true
        }
        for i in list.indices where list[i].children != nil {
            if mutateContainer(of: id, in: &list[i].children!, change) { return true }
        }
        return false
    }

    /// Replaces the item with the same id anywhere in the tree.
    func update(_ item: PresetItem) {
        var copy = items
        if PresetDocument.mutateContainer(of: item.id, in: &copy, { list, index in list[index] = item }) {
            items = copy
        }
    }

    /// Inserts a new item of `type` (default JSON from `ItemCatalog`) with the given alignment,
    /// at the end of that zone, or into the group `parent` when given. Returns the new id.
    @discardableResult
    func add(type: String, align: PresetAlign, intoGroup parent: PresetItem.ID? = nil) -> PresetItem.ID {
        var json = ItemCatalog.info(for: type)?.defaultJSON ?? JSONObject(pairs: [("type", .string(type))])
        var newItem = PresetItem(json: json)
        if type == "group" {
            json["items"] = nil
            newItem = PresetItem(json: json, children: [])
        }
        var copy = items
        var placedInGroup = false
        if let parent = parent {
            placedInGroup = PresetDocument.mutateContainer(of: parent, in: &copy) { list, index in
                if list[index].children != nil {
                    list[index].children!.append(newItem)
                } else {
                    // Not a group: fall through to the top level below.
                    return
                }
            }
            // Verify it really landed (mutateContainer is true also for non-groups).
            placedInGroup = placedInGroup && PresetDocument.find(newItem.id, in: copy) != nil
        }
        if !placedInGroup {
            // Appending to the array puts the item at the end of its zone: zones are only
            // ordered relative to themselves. Gestures have no zone, so they get no "align".
            if newItem.type != "swipe" { newItem.align = align }
            copy.append(newItem)
        }
        items = copy
        return newItem.id
    }

    /// Removes the item anywhere in the tree.
    func remove(id: PresetItem.ID) {
        var copy = items
        if PresetDocument.mutateContainer(of: id, in: &copy, { list, index in list.remove(at: index) }) {
            items = copy
        }
    }

    /// Inserts a copy (new ids, recursively) right after the original. Returns the copy's id.
    @discardableResult
    func duplicate(id: PresetItem.ID) -> PresetItem.ID? {
        var copy = items
        var newID: PresetItem.ID?
        let found = PresetDocument.mutateContainer(of: id, in: &copy) { list, index in
            let clone = PresetDocument.cloneWithFreshIDs(list[index])
            list.insert(clone, at: index + 1)
            newID = clone.id
        }
        guard found else { return nil }
        items = copy
        return newID
    }

    private static func cloneWithFreshIDs(_ item: PresetItem) -> PresetItem {
        var clone = PresetItem(json: item.json, children: item.children?.map(cloneWithFreshIDs))
        clone.itemsKeyPosition = item.itemsKeyPosition
        return clone
    }

    /// Reorders within one zone, with List.onMove semantics (`source` and `destination` are
    /// indices into `items(in: align)`). Relative order of other zones is untouched.
    func move(in align: PresetAlign, from source: IndexSet, to destination: Int) {
        // The zone's members keep occupying the same slots of the full array; only the
        // members are permuted among those slots, so other zones and gestures do not move.
        let slots = items.indices.filter { !items[$0].isGesture && items[$0].align == align }
        var zone = slots.map { items[$0] }
        let before = zone.map(\.id)
        PresetDocument.moveElements(&zone, from: source, to: destination)
        guard zone.map(\.id) != before else { return }
        var copy = items
        for (slot, item) in zip(slots, zone) { copy[slot] = item }
        items = copy
    }

    /// Reorders children of a group with List.onMove semantics.
    func moveChildren(ofGroup group: PresetItem.ID, from source: IndexSet, to destination: Int) {
        var copy = items
        var changed = false
        _ = PresetDocument.mutateContainer(of: group, in: &copy) { list, index in
            guard var children = list[index].children else { return }
            let before = children.map(\.id)
            PresetDocument.moveElements(&children, from: source, to: destination)
            if children.map(\.id) != before {
                list[index].children = children
                changed = true
            }
        }
        if changed { items = copy }
    }

    /// `Array.move(fromOffsets:toOffset:)` is SwiftUI API; the model must not import SwiftUI.
    private static func moveElements<T>(_ array: inout [T], from source: IndexSet, to destination: Int) {
        let valid = source.filter { array.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { array[$0] }
        let target = min(max(destination, 0), array.count)
        let shift = valid.filter { $0 < target }.count
        for index in valid.reversed() { array.remove(at: index) }
        array.insert(contentsOf: moving, at: target - shift)
    }
}

/// Errors raised by `PresetDocument`; `localizedDescription` is shown to the user as is.
enum PresetDocumentError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(text): return text
        }
    }
}
