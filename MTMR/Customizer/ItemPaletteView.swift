//
//  ItemPaletteView.swift
//  MTMR
//
//  "Add item" picker shown in a popover: searchable, grouped by category.
//

import SwiftUI

struct ItemPaletteView: View {
    /// Called with the chosen item type; the caller adds the item and dismisses the popover.
    let onAdd: (String) -> Void

    @State private var query = ""
    @State private var selectedType: String?

    private var sections: [(category: ItemCategory, types: [ItemTypeInfo])] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ItemCategory.allCases.compactMap { category in
            let types = ItemCatalog.types(in: category).filter { info in
                needle.isEmpty
                    || info.displayName.lowercased().contains(needle)
                    || info.summary.lowercased().contains(needle)
                    || info.type.lowercased().contains(needle)
            }
            return types.isEmpty ? nil : (category, types)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search item types", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .onSubmit(addSelected)

            List(selection: $selectedType) {
                ForEach(sections, id: \.category) { section in
                    Section(header: Text(section.category.rawValue)) {
                        ForEach(section.types) { info in
                            row(info)
                                .tag(info.type)
                                // Double-click adds right away; a single click only selects.
                                .onTapGesture(count: 2) { onAdd(info.type) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .overlay(Group {
                if sections.isEmpty {
                    Text("No matching item types").foregroundColor(.secondary)
                }
            })

            Divider()
            HStack {
                Spacer()
                Button("Add") { addSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedType == nil && sections.isEmpty)
            }
            .padding(10)
        }
        .frame(width: 380, height: 460)
    }

    private func row(_ info: ItemTypeInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: info.symbolName)
                .frame(width: 24)
                .foregroundColor(.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.displayName)
                Text(info.summary).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func addSelected() {
        // With a search active and nothing selected, Return adds the first match.
        if let type = selectedType ?? sections.first?.types.first?.type { onAdd(type) }
    }
}
