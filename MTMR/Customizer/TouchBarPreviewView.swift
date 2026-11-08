//
//  TouchBarPreviewView.swift
//  MTMR
//
//  Live preview strip of the Touch Bar plus the small item helpers shared by the customizer views.
//

import AppKit
import SwiftUI

// MARK: - Shared item helpers

extension PresetItem {
    var typeInfo: ItemTypeInfo? { ItemCatalog.info(for: type) }

    var symbolName: String { typeInfo?.symbolName ?? "questionmark.square" }

    var typeDisplayName: String {
        typeInfo?.displayName ?? (type.isEmpty ? "Unknown" : type)
    }

    /// The configured title, if any.
    var configuredTitle: String? {
        guard let title = json["title"]?.stringValue, !title.isEmpty else { return nil }
        return title
    }

    /// Title used in lists and chips: the item's own title, else the type's display name.
    var listTitle: String { configuredTitle ?? typeDisplayName }

    /// Decoded `"image": {"base64": …}`, if present and valid.
    var embeddedImage: NSImage? {
        guard let base64 = json["image"]?.objectValue?["base64"]?.stringValue else { return nil }
        return EmbeddedImageCache.image(forBase64: base64)
    }
}

/// Decoding a large base64 image on every SwiftUI body pass would be wasteful, so decoded images are cached.
enum EmbeddedImageCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(forBase64 base64: String) -> NSImage? {
        let key = base64 as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
            let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// Parsing and writing of the "#RRGGBB" strings used by the "background" parameter.
/// Mirrors `String.hexColor` in SupportHelpers.swift: 3 digits = RGB, 6 = RRGGBB, 8 = RRGGBBAA.
enum HexColor {
    static func color(from string: String) -> Color? {
        let hex = string.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let value = UInt32(hex, radix: 16) else { return nil }
        let r, g, b, a: UInt32
        switch hex.count {
        case 3: (r, g, b, a) = ((value >> 8) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17, 255)
        case 6: (r, g, b, a) = (value >> 16, value >> 8 & 0xFF, value & 0xFF, 255)
        case 8: (r, g, b, a) = (value >> 24, value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default: return nil
        }
        return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    /// "#RRGGBB" (opacity is not editable in the UI).
    static func string(from color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(ns.redComponent), byte(ns.greenComponent), byte(ns.blueComponent))
    }
}

// MARK: - Preview

struct TouchBarPreviewView: View {
    @ObservedObject var document: PresetDocument
    @Binding var selection: PresetItem.ID?

    var body: some View {
        // The strip stays dark in both appearances, like the hardware; only the surroundings follow the system.
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    zone(.left)
                    Spacer(minLength: 24)
                    zone(.center)
                    Spacer(minLength: 24)
                    zone(.right)
                }
                .padding(.horizontal, 10)
                // Fills the viewport so left/center/right zones spread like on the real bar; grows (and scrolls) when too wide.
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
        }
        .frame(height: 56)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Touch Bar preview")
    }

    private func zone(_ align: PresetAlign) -> some View {
        HStack(spacing: 6) {
            ForEach(document.items(in: align)) { item in
                PreviewChip(item: item, isSelected: selection == item.id) { selection = item.id }
            }
        }
    }
}

private struct PreviewChip: View {
    let item: PresetItem
    let isSelected: Bool
    let action: () -> Void

    private var isGroup: Bool { item.children != nil }

    var body: some View {
        let image = item.embeddedImage
        Button(action: action) {
            HStack(spacing: 5) {
                if let image = image {
                    // Template images (the common case for Touch Bar icons) are tinted white like on the hardware.
                    Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original).resizable().scaledToFit().frame(height: 18)
                } else {
                    Image(systemName: item.symbolName).font(.system(size: 14))
                }
                if image == nil || item.configuredTitle != nil {
                    Text(item.listTitle).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                }
                if isGroup {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).opacity(0.7)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(width: fixedWidth, height: 32)
            .frame(maxWidth: fixedWidth == nil ? 180 : nil)
            .background(chipBackground)
            // Accent ring plus a thin white inner line, so the ring stays visible on accent-coloured chips.
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 3)
                    RoundedRectangle(cornerRadius: 6, style: .continuous).inset(by: 3).strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                }
                .opacity(isSelected ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(item.listTitle) (\(item.typeDisplayName))")
        .accessibilityLabel("\(item.listTitle), \(item.typeDisplayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "width" in points; nil lets the chip size to its content.
    private var fixedWidth: CGFloat? {
        guard let width = item.json["width"]?.doubleValue, width > 0 else { return nil }
        return CGFloat(width)
    }

    @ViewBuilder private var chipBackground: some View {
        // Mirrors the app: "bordered": false removes the button chrome; "background" overrides the fill.
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if let hex = item.json["background"]?.stringValue, let color = HexColor.color(from: hex) {
            shape.fill(color)
        } else if item.json["bordered"]?.boolValue == false {
            shape.fill(Color.clear)
        } else {
            shape.fill(Color(white: 0.24))
        }
    }
}
