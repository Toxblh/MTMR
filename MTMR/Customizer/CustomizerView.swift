//
//  CustomizerView.swift
//  MTMR
//
//  Root layout of the Touch Bar customizer: preview strip on top, item list and inspector below.
//

import AppKit
import SwiftUI

extension View {
    /// `onChange(of:)` changed its signature in macOS 14 (the old one is deprecated); the deployment target is 12.
    @ViewBuilder func onValueChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }
}

extension PresetDocument {
    /// Validates and saves; returns a user-facing message on failure, nil on success.
    func saveReportingError() -> String? {
        if let problem = validate() { return problem }
        do {
            try save()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// Window-level UI state that the window controller also needs to set (save errors from the close sheet).
@MainActor
final class CustomizerState: ObservableObject {
    /// Attached when the window starts previewing the running Touch Bar.
    @Published var previewRuntime: RunningTouchBar?
    var revertPreset: (PresetDocument) -> Void = { $0.revert() }
    @Published var presetNotice: RunningPresetNotice?
    @Published var groupPath: [UUID] = []
    @Published var previewActive = false
    weak var strip: LivePreviewStrip?

    func enterGroup(_ id: UUID, in document: PresetDocument) {
        guard document.item(withID: id)?.children != nil else { return }
        selection = id
        groupPath = document.ancestors(of: id) + [id]
    }

    func backToMain() {
        selection = groupPath.first
        groupPath = []
    }

    func reconcile(in document: PresetDocument) {
        let valid = Array(groupPath.prefix { document.item(withID: $0)?.children != nil })
        if valid != groupPath { groupPath = valid }
        if let selection, document.item(withID: selection) == nil { self.selection = valid.last }
    }

    @Published var errorMessage: String?
    @Published var selection: UUID? {
        didSet {
            if selection != oldValue { advancedDraft = nil }
        }
    }
    @Published var advancedDraft: String?
    @Published var advancedExpanded = false
    func hasDraft(in document: PresetDocument) -> Bool { document.isDirty || advancedDraft != nil }
}

struct CustomizerView: View {
    @ObservedObject var document: PresetDocument
    @ObservedObject var state: CustomizerState

    @Binding private var selection: PresetItem.ID?
    @State private var showingPalette = false
    @State private var confirmingRevert = false
    @State private var collapsedGroups: Set<PresetItem.ID> = []

    init(document: PresetDocument, state: CustomizerState) {
        self.document = document
        self.state = state
        _selection = Binding(get: { state.selection }, set: { state.selection = $0 })
    }

    /// A stale id (item deleted, document reloaded) behaves like no selection.
    private var selectedItem: PresetItem? { selection.flatMap { document.item(withID: $0) } }

    var body: some View {
        VStack(spacing: 0) {
            if let message = state.errorMessage { ErrorBanner(message: message) { state.errorMessage = nil } }
            if let notice = state.presetNotice {
                NoticeBanner(
                    message: notice.message,
                    onSave: document.isDirty ? save : nil,
                    onRevert: state.hasDraft(in: document) ? { confirmingRevert = true } : nil
                )
            }

            if let runtime = state.previewRuntime {
                TouchBarPreviewView(document: document, state: state, runtime: runtime, onSave: save)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.windowBackgroundColor))
            }
            Divider()

            if let loadError = document.loadError {
                loadErrorView(loadError)
            } else if document.items.isEmpty {
                emptyView
            } else {
                HSplitView {
                    sidebar.frame(minWidth: 240, idealWidth: 280, maxWidth: 420)
                    ItemInspectorView(document: document, state: state)
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .toolbar { toolbarContent }
        .onValueChange(of: document.items) { _ in state.reconcile(in: document) }
        .onValueChange(of: selection) { id in
            guard let id, document.item(withID: id) != nil else { return }
            let ancestors = document.ancestors(of: id)
            collapsedGroups.subtract(ancestors)
            if state.groupPath.last != id, state.groupPath != ancestors { state.groupPath = ancestors }
        }
        .onValueChange(of: state.groupPath) { collapsedGroups.subtract($0) }
        .confirmationDialog("Discard all unsaved changes?", isPresented: $confirmingRevert) {
            Button("Revert", role: .destructive) { state.revertPreset(document) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button { showingPalette = true } label: { Label("Add", systemImage: "plus") }
                .help("Add an item")
                .accessibilityLabel("Add item")
                .disabled(document.loadError != nil)
                .popover(isPresented: $showingPalette, arrowEdge: .bottom) {
                    ItemPaletteView { type in
                        addItem(type: type)
                        showingPalette = false
                    }
                    .appLocalized()
                }
            Button(action: removeSelected) { Label("Remove", systemImage: "minus") }
                .help("Remove the selected item")
                .accessibilityLabel("Remove selected item")
                .disabled(selectedItem == nil)
            Button(action: duplicateSelected) { Label("Duplicate", systemImage: "plus.square.on.square") }
                .help("Duplicate the selected item")
                .accessibilityLabel("Duplicate selected item")
                .disabled(selectedItem == nil)
        }
        ToolbarItemGroup {
            Button { confirmingRevert = true } label: { Label("Revert", systemImage: "arrow.uturn.backward") }
                .help("Discard unsaved changes")
                .accessibilityLabel("Revert changes")
                .disabled(!state.hasDraft(in: document))
            Button(action: save) { Label("Save", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: .command)
                .help("Save and apply to the Touch Bar (⌘S)")
                .accessibilityLabel("Save")
                .disabled(!document.isDirty)
        }
    }

    // MARK: Actions

    private func save() {
        state.errorMessage = document.saveReportingError()
    }

    /// Target zone: the zone of the selected top-level item, the selected group (or a child's group), else center.
    private func addItem(type: String) {
        var align = PresetAlign.center
        var group = state.groupPath.last
        if let item = selectedItem {
            if item.children != nil {
                align = item.align
                group = item.id
            } else if let parentID = document.ancestors(of: item.id).last, let parent = document.item(withID: parentID) {
                align = parent.align
                group = parent.id
            } else {
                align = item.isGesture ? .center : item.align
                group = nil
            }
        }
        // Groups can't nest and gestures aren't visual, so those types always go to the top level.
        if type == "group" || type == "swipe" { group = nil }
        selection = document.add(type: type, align: align, intoGroup: group)
        if let group = group { collapsedGroups.remove(group) }
    }

    private func removeSelected() {
        guard let id = selection else { return }
        document.remove(id: id)
        selection = nil
    }

    private func duplicateSelected() {
        guard let id = selection, let copy = document.duplicate(id: id) else { return }
        selection = copy
    }

    private func move(_ item: PresetItem, to align: PresetAlign) {
        var updated = item
        updated.align = align
        document.update(updated)
    }

    // MARK: States

    private func loadErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundColor(.orange)
            Text("The preset could not be loaded").font(.headline)
            Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
            HStack {
                Button("Edit Preset File…") { NSWorkspace.shared.open(document.fileURL) }
                Button("Reload") { document.load() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.dashed").font(.system(size: 32)).foregroundColor(.secondary)
            Text("Your Touch Bar is empty").font(.headline)
            Text("Add buttons, sliders and widgets to build your own Touch Bar.").foregroundColor(.secondary)
            Button("Add Item…") { showingPalette = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(PresetAlign.allCases) { align in
                    Section(header: Text(align.title)) {
                        ForEach(document.items(in: align)) { item in
                            itemRow(item)
                        }
                        .onMove { document.move(in: align, from: $0, to: $1) }
                    }
                }
                Section(header: Text("Gestures")) {
                    ForEach(document.gestures) { item in
                        row(for: item, canMoveZone: false)
                    }
                }
            }
            .onDeleteCommand(perform: removeSelected)
            .onValueChange(of: selection) { id in
                if let id { DispatchQueue.main.async { proxy.scrollTo(id) } }
            }
        }
    }

    // Type erasure closes the recursive view type for groups loaded from existing presets.
    private func itemRow(_ item: PresetItem, topLevel: Bool = true) -> AnyView {
        if let children = item.children {
            return AnyView(DisclosureGroup(isExpanded: Binding(
                get: { !collapsedGroups.contains(item.id) },
                set: { if $0 { collapsedGroups.remove(item.id) } else { collapsedGroups.insert(item.id) } }
            )) {
                ForEach(children) { child in
                    itemRow(child, topLevel: false)
                }
                .onMove { document.moveChildren(ofGroup: item.id, from: $0, to: $1) }
            } label: {
                row(for: item, canMoveZone: topLevel)
            }
            .tag(item.id).id(item.id))
        } else {
            return AnyView(row(for: item, canMoveZone: topLevel).id(item.id))
        }
    }

    private func row(for item: PresetItem, canMoveZone: Bool) -> some View {
        ItemRow(item: item)
            .tag(item.id)
            .contextMenu {
                Button("Duplicate") { if let copy = document.duplicate(id: item.id) { selection = copy } }
                if canMoveZone && !item.isGesture {
                    Menu("Move to") {
                        ForEach(PresetAlign.allCases) { align in
                            // The app forces Escape to the left (ItemsParsing "escape" parameters override "align").
                            Button(align.title) { move(item, to: align) }.disabled(item.align == align || item.type == "escape")
                        }
                    }
                }
                Divider()
                Button("Delete") {
                    if selection == item.id { selection = nil }
                    document.remove(id: item.id)
                }
            }
    }
}

private struct ItemRow: View {
    let item: PresetItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.symbolName)
                .frame(width: 20)
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: item.listTitle).lineLimit(1)
                // Untitled items already show the type name as their title.
                if item.configuredTitle != nil {
                    Text(verbatim: item.typeDisplayName).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).accessibilityHidden(true)
            Text(message).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
                .accessibilityLabel("Dismiss error")
        }
        .padding(10)
        .background(Color.red.opacity(0.15))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.red.opacity(0.4)), alignment: .bottom)
        .accessibilityElement(children: .combine)
    }
}

private struct NoticeBanner: View {
    let message: String
    let onSave: (() -> Void)?
    let onRevert: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let onRevert {
                Button("Revert", action: onRevert)
                    .controlSize(.small)
            }
            if let onSave {
                Button("Save", action: onSave)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.13))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.orange.opacity(0.35)), alignment: .bottom)
        .accessibilityElement(children: .contain)
    }
}
