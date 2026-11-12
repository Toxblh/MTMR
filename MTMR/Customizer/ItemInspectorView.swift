//
//  ItemInspectorView.swift
//  MTMR
//
//  Editor for the selected item. All edits go through `PresetDocument.update(_:)`; the views below
//  read the item fresh from the document on every access, so they never write back a stale copy.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ItemInspectorView: View {
    @ObservedObject var document: PresetDocument
    /// nil (or an id that no longer exists) shows the "nothing selected" hint.
    let selectedID: PresetItem.ID?

    private var itemID: PresetItem.ID { selectedID ?? PresetItem.ID() }
    private var item: PresetItem? { selectedID.flatMap { document.item(withID: $0) } }
    private var isTopLevel: Bool { document.items.contains { $0.id == itemID } }

    /// The item's JSON as a binding that writes through the document.
    private var jsonBinding: Binding<JSONObject> {
        Binding(
            get: { document.item(withID: itemID)?.json ?? JSONObject() },
            set: { newJSON in
                guard var current = document.item(withID: itemID) else { return }
                current.json = newJSON
                document.update(current)
            }
        )
    }

    var body: some View {
        if let item = item {
            let info = item.typeInfo
            VStack(spacing: 0) {
                header(item, info: info)
                Divider()
                Form {
                    if !item.isGesture {
                        Section(header: Text("Appearance")) {
                            AppearanceEditor(json: jsonBinding, showsAlign: isTopLevel)
                        }
                    }
                    if let info = info, !info.fields.isEmpty {
                        Section(header: Text("Settings")) {
                            FieldsEditor(fields: info.fields, object: jsonBinding)
                        }
                    }
                    if info?.supportsActions == true || jsonBinding.wrappedValue["actions"] != nil {
                        Section(header: Text("Actions")) {
                            ActionsEditor(json: jsonBinding)
                        }
                    }
                    if !item.isGesture {
                        Section(header: Text("Visibility")) {
                            LabeledRow(label: "Only in app", help: "Regular expression matched against the frontmost app’s bundle identifier, e.g. com\\.apple\\.Safari. Leave empty to show everywhere.", onReset: nil) {
                                TextField("", text: stringBinding(jsonBinding, "matchAppId"), prompt: Text("Bundle identifier pattern"))
                                    .labelsHidden()
                            }
                        }
                    }
                    Section {
                        AdvancedEditor(document: document, itemID: item.id)
                    }
                }
                .modifier(GroupedFormStyle())
            }
            .background(Color(NSColor.windowBackgroundColor))
        } else {
            Text("Select an item in the preview or the list")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func header(_ item: PresetItem, info: ItemTypeInfo?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.symbolName)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.typeDisplayName).font(.headline)
                Text(info?.summary ?? "Unknown item type “\(item.type)”. Only the common fields and the JSON can be edited.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// `.formStyle(.grouped)` exists from macOS 13; on 12 the plain form with section headers is used.
struct GroupedFormStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.formStyle(.grouped)
        } else {
            content.padding(.horizontal, 8)
        }
    }
}

// MARK: - Binding helpers

/// `keepEmpty`: for keys the decoder requires, clearing the field writes "" instead of removing the key,
/// otherwise the preset no longer decodes and Save fails with "missing key".
private func stringBinding(_ object: Binding<JSONObject>, _ key: String, keepEmpty: Bool = false) -> Binding<String> {
    Binding(
        get: { object.wrappedValue[key]?.stringValue ?? "" },
        // Empty text removes optional keys so the JSON stays minimal.
        set: { object.wrappedValue[key] = ($0.isEmpty && !keepEmpty) ? nil : .string($0) }
    )
}

// MARK: - Safe numbers

/// Largest magnitude converted to an integer. Beyond this (or for inf/nan) `Int64(_:)` would trap,
/// e.g. on typed "inf" or a hand-written `"refreshInterval": 1e30`.
private let maxIntegralMagnitude = 1e12

private func safeInt64(_ value: Double) -> Int64? {
    value.isFinite && abs(value) <= maxIntegralMagnitude ? Int64(value.rounded()) : nil
}

/// Whole numbers without ".0" (1800, not 1800.0); anything not safely integral as-is.
private func displayNumber(_ value: Double, integer: Bool) -> String {
    if integer || value.rounded() == value, let int = safeInt64(value) { return String(int) }
    return String(value)
}

// MARK: - Layout row

/// Label + control (+ help + reset). `LabeledContent` is macOS 13+, hence the fallback.
struct LabeledRow<Content: View>: View {
    let label: String
    var help: String?
    var stacked = false
    let onReset: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if stacked {
                HStack {
                    Text(label)
                    Spacer()
                    resetButton
                }
                content()
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(label).frame(width: 130, alignment: .leading)
                    content().frame(maxWidth: .infinity, alignment: .leading)
                    resetButton
                }
            }
            if let help = help {
                Text(help).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var resetButton: some View {
        if let onReset = onReset {
            Button(action: onReset) { Image(systemName: "arrow.uturn.backward.circle") }
                .buttonStyle(.borderless)
                .help("Reset “\(label)” to its default")
                .accessibilityLabel("Reset \(label)")
        }
    }
}

// MARK: - Appearance

private struct AppearanceEditor: View {
    @Binding var json: JSONObject
    let showsAlign: Bool

    private var type: String { json["type"]?.stringValue ?? "" }
    /// The app always places Escape on the left: its type parameters override "align" (ItemsParsing "escape").
    private var alignIsFixed: Bool { type == "escape" }

    var body: some View {
        LabeledRow(label: "Title", onReset: nil) {
            // staticButton requires "title" (ItemsParsing decodes it with `decode`, not `decodeIfPresent`).
            TextField("", text: stringBinding($json, "title", keepEmpty: type == "staticButton"), prompt: Text("No title")).labelsHidden()
        }
        imageRow
        widthRow
        LabeledRow(label: "Bordered", help: "Turn off to draw the item without a button background.", onReset: json["bordered"] == nil ? nil : { json["bordered"] = nil }) {
            Toggle("", isOn: Binding(
                get: { json["bordered"]?.boolValue ?? true },
                // `true` is the default, so it is expressed by leaving the key out.
                set: { json["bordered"] = $0 ? nil : .bool(false) }
            )).labelsHidden()
        }
        backgroundRow
        if showsAlign {
            LabeledRow(label: "Position", help: alignIsFixed ? "The app always places Escape on the left." : nil, onReset: nil) {
                Picker("", selection: Binding(
                    get: { alignIsFixed ? .left : (json["align"]?.stringValue.flatMap(PresetAlign.init(rawValue:)) ?? .center) },
                    set: { json["align"] = .string($0.rawValue) }
                )) {
                    ForEach(PresetAlign.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                .disabled(alignIsFixed)
            }
        }
    }

    // MARK: image

    private var imageRow: some View {
        let base64 = json["image"]?.objectValue?["base64"]?.stringValue
        let thumbnail = base64.flatMap { EmbeddedImageCache.image(forBase64: $0) }
        return LabeledRow(label: "Image", help: json["image"] != nil && base64 == nil ? "This image is not embedded (e.g. a file path); edit it in the JSON below." : nil, onReset: nil) {
            HStack(spacing: 8) {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable().scaledToFit()
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Image preview")
                }
                Button("Choose…", action: chooseImage)
                if json["image"] != nil {
                    Button("Remove") { json["image"] = nil }
                }
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose an image"
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let data = ImageImport.pngData(contentsOf: url) else { return }
        // Embedded so the preset stays a single portable file.
        json["image"] = .object(JSONObject(pairs: [("base64", .string(data.base64EncodedString()))]))
    }

    // MARK: width

    private var widthRow: some View {
        let width = json["width"]?.doubleValue
        return LabeledRow(label: "Width", help: "Points. Without a fixed width the item sizes to its content.", onReset: nil) {
            HStack(spacing: 8) {
                Toggle("Fixed width", isOn: Binding(
                    get: { width != nil },
                    set: { json["width"] = $0 ? .int(64) : nil }
                ))
                if width != nil {
                    NumberField(object: $json, key: "width", range: 1...2000, integer: true, unit: "pt",
                                placeholder: nil, fallback: 64, step: 4, onClear: .revert)
                }
            }
        }
    }

    // MARK: background

    private var backgroundRow: some View {
        let hex = json["background"]?.stringValue
        return LabeledRow(label: "Background", onReset: nil) {
            HStack(spacing: 8) {
                Toggle("Custom color", isOn: Binding(
                    get: { hex != nil },
                    set: { json["background"] = $0 ? .string("#444444") : nil }
                ))
                if let hex = hex {
                    ColorPicker("Background color", selection: Binding(
                        get: { HexColor.color(from: hex) ?? Color(white: 0.27) },
                        set: { json["background"] = .string(HexColor.string(from: $0)) }
                    ), supportsOpacity: false)
                        .labelsHidden()
                    Text(hex).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Generic field editor

struct FieldsEditor: View {
    let fields: [FieldSpec]
    @Binding var object: JSONObject
    /// All fields are required by the decoder (action parameters: keycode, url, executablePath,
    /// actionAppleScript). Clearing them must not remove the key, and they have no reset button.
    var keysRequired = false

    var body: some View {
        ForEach(fields) { spec in
            FieldRow(spec: spec, object: $object, required: keysRequired)
        }
    }
}

private struct FieldRow: View {
    let spec: FieldSpec
    @Binding var object: JSONObject
    var required = false

    private var isSet: Bool { object[spec.key] != nil }

    var body: some View {
        LabeledRow(label: spec.label, help: spec.help, stacked: isStacked, onReset: isSet && !required ? { object[spec.key] = nil } : nil) {
            editor
        }
    }

    private var isStacked: Bool {
        switch spec.kind {
        case .multilineText, .scriptSource, .stringList: return true
        default: return false
        }
    }

    @ViewBuilder private var editor: some View {
        switch spec.kind {
        case let .text(placeholder):
            TextField("", text: stringBinding($object, spec.key, keepEmpty: required), prompt: Text(placeholder ?? spec.defaultValue?.stringValue ?? ""))
                .labelsHidden()
        case .multilineText:
            MonospacedEditor(text: stringBinding($object, spec.key, keepEmpty: required), monospaced: false)
        case let .integer(range):
            numberEditor(range: range.map { Double($0.lowerBound)...Double($0.upperBound) }, unit: nil, integer: true)
        case let .number(range, unit):
            numberEditor(range: range, unit: unit, integer: false)
        case .bool:
            Toggle("", isOn: Binding(
                get: { object[spec.key]?.boolValue ?? spec.defaultValue?.boolValue ?? false },
                set: { object[spec.key] = .bool($0) }
            )).labelsHidden()
        case let .choice(options):
            let current = object[spec.key]?.stringValue ?? spec.defaultValue?.stringValue ?? options.first ?? ""
            Picker("", selection: Binding(get: { current }, set: { object[spec.key] = .string($0) })) {
                // A value written by hand that the catalog does not list must stay visible and selectable.
                ForEach(options.contains(current) ? options : options + [current], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case .scriptSource:
            ScriptSourceEditor(object: $object, key: spec.key)
        case .stringList:
            StringListEditor(object: $object, key: spec.key)
        }
    }

    private func numberEditor(range: ClosedRange<Double>?, unit: String?, integer: Bool) -> some View {
        NumberField(object: $object, key: spec.key, range: range, integer: integer, unit: unit,
                    placeholder: spec.defaultValue?.doubleValue,
                    fallback: spec.defaultValue?.doubleValue ?? range?.lowerBound ?? 0,
                    step: 1, onClear: required ? .revert : .remove)
    }
}

/// Number text field + stepper. Typed text is committed on Return or when the field loses focus,
/// not on every keystroke: clamping per keystroke made values like "5" in 10...100 or "-1" untypeable.
private struct NumberField: View {
    enum ClearBehavior {
        /// Optional key: empty text removes it.
        case remove
        /// Required key (or a field toggled elsewhere): empty text restores the stored value.
        case revert
    }

    @Binding var object: JSONObject
    let key: String
    let range: ClosedRange<Double>?
    let integer: Bool
    let unit: String?
    let placeholder: Double?
    let fallback: Double
    let step: Double
    let onClear: ClearBehavior

    @State private var text = ""
    @FocusState private var focused: Bool

    private var stored: Double? { object[key]?.doubleValue }
    private var storedText: String { stored.map { displayNumber($0, integer: integer) } ?? "" }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text, prompt: Text(placeholder.map { displayNumber($0, integer: integer) } ?? ""))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($focused)
                .onSubmit(commit)
            Stepper("", value: Binding(
                get: { stored.flatMap { $0.isFinite ? $0 : nil } ?? fallback },
                set: { write($0); text = storedText }
            ), in: (range ?? -maxIntegralMagnitude...maxIntegralMagnitude), step: step)
                .labelsHidden()
            if let unit = unit { Text(unit).foregroundColor(.secondary) }
        }
        .onAppear { text = storedText }
        // Follow changes made elsewhere (stepper, Advanced JSON, another selection) unless the user is typing.
        .onValueChange(of: storedText) { newValue in if !focused { text = newValue } }
        .onValueChange(of: focused) { isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if onClear == .remove { object[key] = nil }
        } else if let value = Double(trimmed) {
            write(value)
        }
        // Invalid or rejected input falls back to what is stored.
        text = storedText
    }

    /// Clamps to `range`; rejects nan/inf and magnitudes `Int64(_:)` cannot represent.
    private func write(_ value: Double) {
        guard value.isFinite, abs(value) <= maxIntegralMagnitude else { return }
        let clamped = range.map { min(max(value, $0.lowerBound), $0.upperBound) } ?? value
        // Whole numbers are written as integers so "keycode": 53 never becomes 53.0.
        if integer || clamped.rounded() == clamped, let int = safeInt64(clamped) {
            object[key] = .int(int)
        } else {
            object[key] = .double(clamped)
        }
    }
}

/// TextEditor with a visible frame, used for multi-line text and inline scripts.
private struct MonospacedEditor: View {
    @Binding var text: String
    var monospaced = true

    var body: some View {
        TextEditor(text: $text)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .frame(minHeight: 90)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor)))
    }
}

private struct ScriptSourceEditor: View {
    @Binding var object: JSONObject
    let key: String

    private enum Mode: String { case inline = "Inline", file = "File", embedded = "Embedded" }

    private var source: JSONObject? { object[key]?.objectValue }
    private var mode: Mode {
        if source?["filePath"] != nil { return .file }
        if source?["base64"] != nil { return .embedded }
        return .inline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch mode {
            case .embedded:
                Text("This script is stored base64-encoded. Edit it in the JSON below.")
                    .font(.caption).foregroundColor(.secondary)
            default:
                Picker("Source", selection: Binding(
                    get: { mode },
                    set: { object[key] = .object(JSONObject(pairs: [($0 == .file ? "filePath" : "inline", .string(""))])) }
                )) {
                    Text("Inline").tag(Mode.inline)
                    Text("File").tag(Mode.file)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
                if mode == .file { filePath } else { inline }
            }
        }
    }

    private var inline: some View {
        MonospacedEditor(text: Binding(
            get: { source?["inline"]?.stringValue ?? "" },
            // Cleared text keeps {"inline": ""}: script buttons require "source", so removing it would
            // make the preset undecodable. The row's reset button still removes optional sources.
            set: { object[key] = .object(JSONObject(pairs: [("inline", .string($0))])) }
        ))
    }

    private var filePath: some View {
        HStack {
            TextField("", text: Binding(
                get: { source?["filePath"]?.stringValue ?? "" },
                set: { object[key] = .object(JSONObject(pairs: [("filePath", .string($0))])) }
            ), prompt: Text("Path to a script file")).labelsHidden()
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    object[key] = .object(JSONObject(pairs: [("filePath", .string(url.path))]))
                }
            }
        }
    }
}

private struct StringListEditor: View {
    @Binding var object: JSONObject
    let key: String

    private var list: [String] { object[key]?.arrayValue?.compactMap(\.stringValue) ?? [] }

    private func write(_ strings: [String]) {
        object[key] = strings.isEmpty ? nil : .array(strings.map(JSONValue.string))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.enumerated()), id: \.offset) { index, _ in
                HStack {
                    TextField("", text: Binding(
                        get: { index < list.count ? list[index] : "" },
                        set: { var l = list; if index < l.count { l[index] = $0; write(l) } }
                    )).labelsHidden()
                    Button {
                        var l = list; l.remove(at: index); write(l)
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove this entry")
                        .accessibilityLabel("Remove entry \(index + 1)")
                }
            }
            Button {
                write(list + [""])
            } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(.borderless)
        }
    }
}

// MARK: - Actions

private struct ActionsEditor: View {
    @Binding var json: JSONObject

    private var actions: [JSONObject] { json["actions"]?.arrayValue?.compactMap(\.objectValue) ?? [] }

    private func write(_ list: [JSONObject]) {
        json["actions"] = list.isEmpty ? nil : .array(list.map(JSONValue.object))
    }

    var body: some View {
        if actions.isEmpty {
            Text("No actions. The item does nothing when tapped.").foregroundColor(.secondary)
        }
        ForEach(Array(actions.enumerated()), id: \.offset) { index, _ in
            ActionRow(
                object: Binding(
                    get: { index < actions.count ? actions[index] : JSONObject() },
                    set: { var l = actions; if index < l.count { l[index] = $0; write(l) } }
                ),
                remove: { var l = actions; l.remove(at: index); write(l) }
            )
            if index < actions.count - 1 { Divider() }
        }
        Button {
            let first = ItemCatalog.actionTypes.first?.action ?? "openUrl"
            let new = JSONObject(pairs: [("trigger", .string("singleTap")), ("action", .string(first))])
            write(actions + [new])
        } label: { Label("Add Action", systemImage: "plus") }
    }
}

private struct ActionRow: View {
    @Binding var object: JSONObject
    let remove: () -> Void

    private var actionType: String { object["action"]?.stringValue ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Trigger", selection: Binding(
                    get: { object["trigger"]?.stringValue ?? "singleTap" },
                    set: { object["trigger"] = .string($0) }
                )) {
                    ForEach(ItemCatalog.actionTriggers, id: \.self) { Text(Self.triggerTitle($0)).tag($0) }
                }
                Picker("Action", selection: Binding(
                    get: { actionType },
                    set: { newType in
                        // Parameters belong to the action type, so they are dropped on a change.
                        object = JSONObject(pairs: [("trigger", object["trigger"] ?? .string("singleTap")), ("action", .string(newType))])
                    }
                )) {
                    let known = ItemCatalog.actionTypes
                    ForEach(known) { Text($0.displayName).tag($0.action) }
                    if !known.contains(where: { $0.action == actionType }) {
                        Text(actionType.isEmpty ? "Choose…" : actionType).tag(actionType)
                    }
                }
                Button(action: remove) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Remove this action")
                    .accessibilityLabel("Remove action")
            }
            if let info = ItemCatalog.actionTypes.first(where: { $0.action == actionType }) {
                // Every action parameter is decoded with `decode` (ItemsParsing Action), i.e. required.
                FieldsEditor(fields: info.fields, object: $object, keysRequired: true)
            }
        }
        .padding(.vertical, 2)
    }

    private static func triggerTitle(_ trigger: String) -> String {
        // "singleTap" -> "Single Tap"
        trigger.unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar) { result += " " }
            result.unicodeScalars.append(scalar)
        }.capitalized
    }
}

// MARK: - Advanced (raw JSON)

private struct AdvancedEditor: View {
    @ObservedObject var document: PresetDocument
    let itemID: PresetItem.ID

    @State private var draft = ""
    /// The text `draft` was last synchronised to; while they match the user has no unapplied edits.
    @State private var baseline = ""
    @State private var error: String?
    @State private var expanded = false

    private var current: String {
        guard let item = document.item(withID: itemID) else { return "" }
        return JSONValue.object(item.json).serialized()
    }

    var body: some View {
        DisclosureGroup("Advanced", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text("The item’s JSON. Group children are edited in the list.")
                    .font(.caption).foregroundColor(.secondary)
                MonospacedEditor(text: $draft)
                if let error = error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button("Revert") { draft = current; baseline = current; error = nil }
                        .disabled(draft == baseline)
                    Button("Apply", action: apply).disabled(draft == baseline)
                }
            }
            .padding(.top, 4)
        }
        .onAppear { sync() }
        .onValueChange(of: current) { _ in sync() }
        .onValueChange(of: itemID) { _ in sync(force: true) }
    }

    /// Follow external edits (made through the controls above) unless the user is typing here.
    private func sync(force: Bool = false) {
        let text = current
        if force || draft == baseline { draft = text; error = nil }
        baseline = text
    }

    private func apply() {
        do {
            let value = try JSONValue.parse(draft)
            guard var object = value.objectValue else { error = "The JSON must be an object ({ … })."; return }
            guard let type = object["type"]?.stringValue, !type.isEmpty else { error = "The object needs a “type” string."; return }
            guard var item = document.item(withID: itemID) else { return }
            if type == "group" {
                // Same split as the document: "items" becomes editable children.
                let kids = object["items"]?.arrayValue?.compactMap(\.objectValue) ?? []
                object["items"] = nil
                item.children = kids.map { PresetItem(json: $0) }
            } else {
                item.children = nil
            }
            item.json = object
            document.update(item)
            error = nil
            draft = current
            baseline = current
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Image import

enum ImageImport {
    /// Longest side of an imported image in pixels. Touch Bar icons are drawn at roughly 24-30 pt @2x and
    /// the app scales images to 24x24 anyway, so larger images only bloat the preset (they are embedded
    /// as base64 and re-serialised on every edit).
    static let maxPixels: CGFloat = 64

    /// The image at `url` as PNG data, downscaled to `maxPixels` (never upscaled); vector images (PDF)
    /// are rasterised at `maxPixels`.
    static func pngData(contentsOf url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return nil }
        let bitmap = image.representations.compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide }
        let source: NSSize
        if let bitmap = bitmap, bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 {
            source = NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        } else {
            // No pixel size (vector): rasterise at the maximum size.
            let scale = maxPixels / max(image.size.width, image.size.height)
            source = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        }
        let scale = min(1, maxPixels / max(source.width, source.height))
        let width = max(1, Int((source.width * scale).rounded()))
        let height = max(1, Int((source.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
