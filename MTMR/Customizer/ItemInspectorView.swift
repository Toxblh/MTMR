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

private func stringBinding(_ object: Binding<JSONObject>, _ key: String) -> Binding<String> {
    Binding(
        get: { object.wrappedValue[key]?.stringValue ?? "" },
        // Empty text removes the key so the JSON stays minimal.
        set: { object.wrappedValue[key] = $0.isEmpty ? nil : .string($0) }
    )
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

    var body: some View {
        LabeledRow(label: "Title", onReset: nil) {
            TextField("", text: stringBinding($json, "title"), prompt: Text("No title")).labelsHidden()
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
            LabeledRow(label: "Position", onReset: nil) {
                Picker("", selection: Binding(
                    get: { json["align"]?.stringValue.flatMap(PresetAlign.init(rawValue:)) ?? .center },
                    set: { json["align"] = .string($0.rawValue) }
                )) {
                    ForEach(PresetAlign.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
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
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
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
                if let width = width {
                    TextField("", value: Binding(
                        get: { Int(width.rounded()) },
                        set: { json["width"] = .int(Int64(max($0, 1))) }
                    ), formatter: NumberFormatter())
                        .labelsHidden()
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: Binding(
                        get: { Int(width.rounded()) },
                        set: { json["width"] = .int(Int64(max($0, 1))) }
                    ), in: 1...2000, step: 4).labelsHidden()
                    Text("pt").foregroundColor(.secondary)
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

    var body: some View {
        ForEach(fields) { spec in
            FieldRow(spec: spec, object: $object)
        }
    }
}

private struct FieldRow: View {
    let spec: FieldSpec
    @Binding var object: JSONObject

    private var isSet: Bool { object[spec.key] != nil }

    var body: some View {
        LabeledRow(label: spec.label, help: spec.help, stacked: isStacked, onReset: isSet ? { object[spec.key] = nil } : nil) {
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
            TextField("", text: stringBinding($object, spec.key), prompt: Text(placeholder ?? spec.defaultValue?.stringValue ?? ""))
                .labelsHidden()
        case .multilineText:
            MonospacedEditor(text: stringBinding($object, spec.key), monospaced: false)
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
        let stored = object[spec.key]?.doubleValue
        let fallback = spec.defaultValue?.doubleValue ?? range?.lowerBound ?? 0
        // Whole numbers are shown without ".0" (a default of 1800.0 seconds reads as "1800").
        func display(_ value: Double) -> String { integer || value.rounded() == value ? String(Int64(value)) : String(value) }
        func write(_ value: Double) {
            let clamped = range.map { min(max(value, $0.lowerBound), $0.upperBound) } ?? value
            // Whole numbers are written as integers so "keycode": 53 never becomes 53.0.
            object[spec.key] = (integer || clamped.rounded() == clamped) ? .int(Int64(clamped)) : .double(clamped)
        }
        let text = Binding<String>(
            get: { stored.map(display) ?? "" },
            set: { newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { object[spec.key] = nil } else if let value = Double(trimmed) { write(value) }
            }
        )
        return HStack(spacing: 6) {
            TextField("", text: text, prompt: Text(spec.defaultValue.flatMap { $0.doubleValue }.map(display) ?? ""))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Stepper("", value: Binding(get: { stored ?? fallback }, set: { write($0) }),
                    in: (range ?? -1_000_000_000...1_000_000_000), step: 1)
                .labelsHidden()
            if let unit = unit { Text(unit).foregroundColor(.secondary) }
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
            set: { object[key] = $0.isEmpty ? nil : .object(JSONObject(pairs: [("inline", .string($0))])) }
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
                FieldsEditor(fields: info.fields, object: $object)
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
