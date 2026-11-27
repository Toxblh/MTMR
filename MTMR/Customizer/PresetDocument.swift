//
//  PresetDocument.swift
//  MTMR
//
//  Editable model of a preset file (items.json) for the Touch Bar customizer.
//  Compiled into the app AND the test target, so it must not reference TouchBarController
//  or AppKit-only UI types; the app injects `onSaved` to trigger a reload.
//

import CryptoKit
import Foundation

/// Identifies the exact bytes consumed by both the editor and the Touch Bar loader.
struct PresetRevision: Equatable {
    let url: URL
    private let digest: Data

    init(url: URL, data: Data) {
        self.url = url.standardizedFileURL
        digest = Data(SHA256.hash(data: data))
    }
}

enum PresetAlign: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    /// English key of the zone name ("Left"); `rawValue` is the JSON value and is never translated.
    var titleKey: String { rawValue.capitalized }
    var title: String { L10n.tr(titleKey) }
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

    static func showsBorder(in json: JSONObject) -> Bool {
        if let bordered = json["bordered"]?.boolValue { return bordered }
        switch json["type"]?.stringValue {
        case "timeButton", "music", "dnd", "darkMode", "nightShift": return false
        default: return true
        }
    }

    /// The app always places Escape on the left: its built-in type parameters set align .left and
    /// override the general "align" key (ItemsParsing.swift, SupportedTypesHolder "escape").
    var hasFixedAlign: Bool { type == "escape" }

    /// Missing or unknown "align" means center (TouchBarController/ItemsParsing default).
    /// Escape always reports .left and ignores writes, matching what the app does.
    var align: PresetAlign {
        get {
            if hasFixedAlign { return .left }
            return json["align"]?.stringValue.flatMap(PresetAlign.init(rawValue:)) ?? .center
        }
        set {
            guard !hasFixedAlign else { return }
            json["align"] = .string(newValue.rawValue)
        }
    }

    /// Gestures ("swipe") have no visual on the Touch Bar.
    var isGesture: Bool { type == "swipe" }

    /// Optional frontmost-app bundle identifier regex (`"matchAppId"`).
    var matchAppIdPattern: String? {
        guard let pattern = json["matchAppId"]?.stringValue, !pattern.isEmpty else { return nil }
        return pattern
    }
}

final class PresetDocument: ObservableObject {
    /// ~/Library/Application Support/MTMR/items.json (same path as `standardConfigPath`).
    static var standardFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MTMR/items.json")
    }

    private(set) var fileURL: URL
    private(set) var savedRevision: PresetRevision?
    private var savedLocations: [UUID: (path: [Int], item: PresetItem)] = [:]
    private var locations: [UUID: [Int]] = [:]

    /// Top-level items in file order.
    @Published var items: [PresetItem] = [] {
        didSet {
            locations.removeAll(keepingCapacity: true)
            index(items, under: [])
            if !isLoading { isDirty = true }
        }
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
    func load(from url: URL? = nil) {
        if let url { fileURL = url }
        isLoading = true
        defer {
            isLoading = false
            isDirty = false
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                throw PresetDocumentError.message(NSLocalizedString("The file is not valid UTF-8 text.", bundle: L10n.bundle, comment: "Preset load error"))
            }
            let root = try JSONValue.parse(text)
            guard case let .array(elements) = root else {
                throw PresetDocumentError.message(NSLocalizedString("The preset must be a JSON array of items at the top level.", bundle: L10n.bundle, comment: "Preset load error"))
            }
            items = try elements.enumerated().map { index, element in
                try PresetDocument.makeItem(from: element, path: PresetDocument.itemPath(index))
            }
            recordSavedItems(data)
            loadError = nil
        } catch {
            items = []
            savedRevision = nil
            savedLocations.removeAll()
            loadError = error.localizedDescription
        }
    }

    /// Discards unsaved edits (same as `load()`).
    func revert() { load() }

    /// "Item 3": position of a top-level item in error messages (1-based).
    private static func itemPath(_ index: Int) -> String {
        String(format: NSLocalizedString("Item %ld", bundle: L10n.bundle, comment: "Position of a preset item in error messages"), index + 1)
    }

    /// "Item 3, child 2": position of a group child in error messages (1-based).
    private static func childPath(_ parent: String, _ index: Int) -> String {
        String(format: NSLocalizedString("%@, child %ld", bundle: L10n.bundle, comment: "Position of a group child in error messages"), parent, index + 1)
    }

    private static func makeItem(from value: JSONValue, path: String) throws -> PresetItem {
        guard case var .object(object) = value else {
            throw PresetDocumentError.message(String(format: NSLocalizedString("%@ is not a JSON object.", bundle: L10n.bundle, comment: "Preset load error; %@ = item position"), path))
        }
        // Only real groups get their "items" lifted; any other type keeps the key as plain JSON.
        guard object["type"]?.stringValue == "group" else { return PresetItem(json: object) }
        var position: Int?
        var children: [PresetItem] = []
        if let index = object.keys.firstIndex(of: "items") {
            position = index
            guard case let .array(elements)? = object["items"] else {
                throw PresetDocumentError.message(String(format: NSLocalizedString("%@: \"items\" of a group must be an array.", bundle: L10n.bundle, comment: "Preset load error; %@ = item position"), path))
            }
            children = try elements.enumerated().map { index, element in
                try makeItem(from: element, path: childPath(path, index))
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
            if let message = PresetDocument.strictCheck(item, path: PresetDocument.itemPath(index)) { return message }
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
            if let message = strictCheck(child, path: childPath(path, index)) { return message }
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
            prefix = String(format: NSLocalizedString("Missing key “%@”. ", bundle: L10n.bundle, comment: "Validation error; %@ = JSON key (not translated)"), key.stringValue)
        @unknown default:
            return decoding.localizedDescription
        }
        let path = context.codingPath.map { $0.intValue.map { "[\($0 + 1)]" } ?? ".\($0.stringValue)" }.joined()
        // context.debugDescription comes from Swift's decoder and is English only.
        return "\(prefix)\(context.debugDescription)"
            + (path.isEmpty ? "" : String(format: NSLocalizedString(" (at %@)", bundle: L10n.bundle, comment: "Validation error; %@ = JSON path"), path))
    }

    /// Validates, makes a one-time backup if the file on disk contains comments,
    /// writes IN PLACE (no atomic replace: AppDelegate watches the file's descriptor),
    /// clears `isDirty`, then calls `onSaved`.
    func save() throws {
        if let problem = validate() {
            throw PresetDocumentError.message(String(format: NSLocalizedString("The preset is invalid and was not saved. %@", bundle: L10n.bundle, comment: "Save error; %@ = reason"), problem))
        }
        let fm = FileManager.default
        let data = Data(serializedText().utf8)
        let conflict = PresetDocumentError.message(L10n.preview("The preset changed on disk. Reload it before saving."))

        if fm.fileExists(atPath: fileURL.path) {
            // Read and write through the same descriptor so a replacement at the path cannot
            // redirect this write to a file whose revision was never checked.
            let handle = try FileHandle(forUpdating: fileURL)
            defer { try? handle.close() }
            let existing = try handle.readToEnd() ?? Data()
            guard PresetRevision(url: fileURL, data: existing) == savedRevision else {
                throw conflict
            }
            if let old = String(data: existing, encoding: .utf8), JSONValue.containsComments(old) {
                let backup = backupURL
                // Never overwrite: the first backup is the user's original hand-written file.
                if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: fileURL, to: backup) }
            }
            try PresetDocument.writeInPlace(data, to: handle, previousSize: existing.count)
        } else {
            guard savedRevision == nil else { throw conflict }
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .withoutOverwriting)
        }
        recordSavedItems(data)
        isDirty = false
        if Thread.isMainThread {
            onSaved?()
        } else {
            DispatchQueue.main.async { [onSaved] in onSaved?() }
        }
    }

    /// `items.json` -> `items.backup.json` in the same directory.
    var backupURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent + ".backup." + fileURL.pathExtension)
    }

    /// Overwrites the file's contents keeping its inode (the app's O_EVTONLY watcher stays attached).
    /// When the new text is shorter, the old tail is first overwritten with spaces and cut off
    /// afterwards, so the completed write leaves no stale JSON after the new contents.
    private static func writeInPlace(_ data: Data, to handle: FileHandle, previousSize: Int) throws {
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

    private func index(_ siblings: [PresetItem], under parent: [Int]) {
        for (offset, item) in siblings.enumerated() {
            let path = parent + [offset]
            locations[item.id] = path
            if let children = item.children { index(children, under: path) }
        }
    }

    func item(at path: [Int]) -> PresetItem? {
        var siblings = items
        var result: PresetItem?
        for offset in path {
            guard siblings.indices.contains(offset) else { return nil }
            result = siblings[offset]
            siblings = result?.children ?? []
        }
        return result
    }

    func ancestors(of id: UUID) -> [UUID] {
        guard let path = locations[id] else { return [] }
        return path.indices.dropFirst().compactMap { item(at: Array(path.prefix($0)))?.id }
    }

    private func recordSavedItems(_ data: Data) {
        savedRevision = PresetRevision(url: fileURL, data: data)
        savedLocations = locations.compactMapValues { path in
            item(at: path).map { (path, $0) }
        }
    }

    /// A moved item, a shifted sibling, a copy or an edited definition must never borrow
    /// the live item at its draft position, even when two definitions are byte-identical.
    func livePath(for id: UUID, revision: PresetRevision?, checkingChildren: Bool = true) -> [Int]? {
        guard let revision, revision == savedRevision, let saved = savedLocations[id],
              locations[id] == saved.path, let current = item(at: saved.path),
              current.id == id, current.json == saved.item.json else { return nil }
        if checkingChildren, current.children != saved.item.children { return nil }
        return saved.path
    }

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

    /// The advanced editor displays group attributes separately from the editable children.
    func applyJSON(_ object: JSONObject, to id: UUID) throws {
        guard var item = item(withID: id) else { return }
        var parsed = try Self.makeItem(from: .object(object), path: item.type)
        if parsed.children != nil, object["items"] == nil {
            parsed.children = item.children ?? []
            parsed.itemsKeyPosition = item.itemsKeyPosition
        }
        item.json = parsed.json
        item.children = parsed.children
        item.itemsKeyPosition = parsed.itemsKeyPosition
        update(item)
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

    /// Moves `id` to `targetAlign` and places it immediately before `beforeID` among siblings in that zone
    /// (or at the end of `targetAlign` when `beforeID` is nil). Works for top-level items and group children.
    /// Returns true if the document changed.
    @discardableResult
    func relocate(id: PresetItem.ID, to targetAlign: PresetAlign, before beforeID: PresetItem.ID?, inGroup groupID: PresetItem.ID? = nil) -> Bool {
        var copy = items
        var changed = false
        if let groupID {
            _ = PresetDocument.mutateContainer(of: groupID, in: &copy) { list, index in
                guard var children = list[index].children else { return }
                if PresetDocument.relocateItem(id: id, to: targetAlign, before: beforeID, in: &children) {
                    list[index].children = children
                    changed = true
                }
            }
        } else {
            changed = PresetDocument.relocateItem(id: id, to: targetAlign, before: beforeID, in: &copy)
        }
        if changed { items = copy }
        return changed
    }

    private static func relocateItem(id: PresetItem.ID, to targetAlign: PresetAlign, before beforeID: PresetItem.ID?, in list: inout [PresetItem]) -> Bool {
        guard let sourceIndex = list.firstIndex(where: { $0.id == id }) else { return false }
        var moving = list[sourceIndex]
        guard !moving.isGesture else { return false }
        if moving.hasFixedAlign && targetAlign != .left { return false }
        if beforeID == id { return false }

        let oldAlign = moving.align
        let oldZoneIDs = list.filter { !$0.isGesture && $0.align == targetAlign }.map(\.id)

        var updated = list
        updated.remove(at: sourceIndex)
        if oldAlign != targetAlign {
            moving.align = targetAlign
        }

        let insertIndex: Int
        if let beforeID, let targetIndex = updated.firstIndex(where: { $0.id == beforeID }) {
            insertIndex = targetIndex
        } else if let lastInTarget = updated.lastIndex(where: { !$0.isGesture && $0.align == targetAlign }) {
            insertIndex = lastInTarget + 1
        } else {
            // Target zone was empty: insert in logical left → center → right order.
            switch targetAlign {
            case .left:
                insertIndex = 0
            case .center:
                if let lastLeft = updated.lastIndex(where: { !$0.isGesture && $0.align == .left }) {
                    insertIndex = lastLeft + 1
                } else if let firstRight = updated.firstIndex(where: { !$0.isGesture && $0.align == .right }) {
                    insertIndex = firstRight
                } else {
                    insertIndex = updated.count
                }
            case .right:
                insertIndex = updated.count
            }
        }
        updated.insert(moving, at: insertIndex)

        let newZoneIDs = updated.filter { !$0.isGesture && $0.align == targetAlign }.map(\.id)
        if oldAlign == targetAlign && oldZoneIDs == newZoneIDs { return false }
        list = updated
        return true
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
