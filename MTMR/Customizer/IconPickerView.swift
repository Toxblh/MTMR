//
//  IconPickerView.swift
//  MTMR
//
//  Popover content for choosing one of the bundled outline icons (IconLibrary) for an item's "image".
//

import AppKit
import SwiftUI

struct IconPickerView: View {
    /// Name of the currently chosen icon, highlighted in the grid.
    let selected: String?
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var hovered: IconInfo?
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 40), spacing: 4)]

    /// Only icons whose asset exists are offered, so the grid never shows blank cells.
    private var matches: [IconInfo] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        return IconLibrary.all.filter { icon in
            IconLibrary.image(named: icon.name) != nil
                && terms.allSatisfy { icon.title.lowercased().contains($0) || icon.name.contains($0) || icon.category.rawValue.lowercased().contains($0) }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search icons", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityLabel("Search icons")
            let shown = matches
            if shown.isEmpty {
                Text(query.isEmpty ? "No icons are installed." : "No icons match “\(query)”.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(IconCategory.allCases, id: \.self) { category in
                            let icons = shown.filter { $0.category == category }
                            if !icons.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.rawValue).font(.caption).foregroundColor(.secondary)
                                        .accessibilityAddTraits(.isHeader)
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                                        ForEach(icons) { icon in cell(icon) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Text((hovered ?? selected.flatMap(IconLibrary.info(for:)))?.title ?? " ")
                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(width: 320, height: 380)
        .onAppear { searchFocused = true }
    }

    private func cell(_ icon: IconInfo) -> some View {
        let isSelected = icon.name == selected
        return Button { onSelect(icon.name) } label: {
            // Template image, tinted by the label colour so it follows light and dark appearance.
            Image(nsImage: IconLibrary.image(named: icon.name) ?? NSImage())
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? Color.accentColor : Color.primary.opacity(hovered == icon ? 0.12 : 0.05)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hovered = icon } else if hovered == icon { hovered = nil }
        }
        .help(icon.title)
        .accessibilityLabel(icon.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
