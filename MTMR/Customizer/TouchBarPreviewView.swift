//
//  TouchBarPreviewView.swift
//  MTMR
//
//  Live preview stage of the Touch Bar plus the small item helpers shared by the customizer views.
//

import AppKit
import QuartzCore
import SwiftUI

// MARK: - Shared item helpers

extension PresetItem {
    var typeInfo: ItemTypeInfo? { ItemCatalog.info(for: type) }

    var symbolName: String { typeInfo?.symbolName ?? "questionmark.square" }

    /// Localized type name; for unknown types the raw JSON "type" value is shown as it is.
    var typeDisplayName: String {
        typeInfo.map { L10n.tr($0.displayName) } ?? (type.isEmpty ? NSLocalizedString("Unknown", bundle: L10n.bundle, comment: "Item without a type") : type)
    }

    /// The configured title, if any.
    var configuredTitle: String? {
        guard let title = json["title"]?.stringValue, !title.isEmpty else { return nil }
        return title
    }

    /// Title used in lists and chips: the item's own title (shown verbatim, never translated),
    /// else the type's display name.
    var listTitle: String { configuredTitle ?? typeDisplayName }

    /// Decoded `"image": {"base64": …}`, if present and valid.
    var embeddedImage: NSImage? {
        guard let base64 = json["image"]?.objectValue?["base64"]?.stringValue else { return nil }
        return EmbeddedImageCache.image(forBase64: base64)
    }

    /// Resolved `"image"` supporting both `{"base64": …}` and `{"filePath": …}`.
    var resolvedImage: NSImage? {
        if let embedded = embeddedImage { return embedded }
        guard let rawPath = json["image"]?.objectValue?["filePath"]?.stringValue, !rawPath.isEmpty else { return nil }
        return EmbeddedImageCache.image(forFilePath: rawPath)
    }
}

/// Decoding a large base64 image or reading a disk icon on every SwiftUI body pass would be wasteful.
enum EmbeddedImageCache {
    private static let base64Cache = NSCache<NSString, NSImage>()
    private static let pathCache = NSCache<NSString, NSImage>()

    static func image(forBase64 base64: String) -> NSImage? {
        let key = base64 as NSString
        if let hit = base64Cache.object(forKey: key) { return hit }
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data) else { return nil }
        base64Cache.setObject(image, forKey: key)
        return image
    }

    static func image(forFilePath path: String) -> NSImage? {
        let expanded = (path as NSString).expandingTildeInPath
        let key = expanded as NSString
        if let hit = pathCache.object(forKey: key) { return hit }
        guard let image = NSImage(contentsOfFile: expanded) else { return nil }
        pathCache.setObject(image, forKey: key)
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

// MARK: - Preview View

extension PreviewControlStrip {
    /// Localized segment title ("Current" / "Collapsed" / "Expanded").
    var title: String { L10n.preview(rawValue) }
}

private struct PreviewStageMetrics: Equatable {
    let usage: PreviewSpaceUsage
    let liveCount: Int
    let draftCount: Int
    let hiddenCount: Int
    let connectedLive: Bool
}

private struct PreviewItemSummary: Equatable {
    let id: UUID
    let title: String
    let align: PresetAlign
    let width: CGFloat
    let isFixedWidth: Bool
    let status: PreviewItemStatus
    let isGroup: Bool
}

private struct PreviewDragFeedback: Equatable {
    let title: String
    let targetAlign: PresetAlign
    let isNoOp: Bool
    let constrainedToFixedAlign: Bool
}

struct TouchBarPreviewView: View {
    @ObservedObject var document: PresetDocument
    @ObservedObject var state: CustomizerState
    let runtime: RunningTouchBar
    var onSave: (() -> Void)? = nil

    @State private var controlStrip = PreviewControlStrip.current
    @State private var metrics: PreviewStageMetrics?
    @State private var hoveredSummary: PreviewItemSummary?
    @State private var selectedSummary: PreviewItemSummary?
    @State private var dragFeedback: PreviewDragFeedback?
    @State private var optionKeyHeld = false

    @AppStorage("com.toxblh.mtmr.preview.showZones") private var showZones = true
    @AppStorage("com.toxblh.mtmr.preview.showHiddenItems") private var showHiddenItems = false
    @AppStorage("com.toxblh.mtmr.preview.zoomScale") private var zoomRaw = PreviewZoom.fit.rawValue

    private var zoom: PreviewZoom {
        get { PreviewZoom(rawValue: zoomRaw) ?? .fit }
        nonmutating set { zoomRaw = newValue.rawValue }
    }

    private var stageHeight: CGFloat {
        let scale = zoom.stageScale
        let barHeight = TouchBarMetrics.height * scale
        let verticalPadding: CGFloat = 22 * scale + 6
        let zonesExtra: CGFloat = (showZones && controlStrip != .expanded) ? 24 * scale : 0
        return ceil(barHeight + verticalPadding + zonesExtra)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .frame(height: 26)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider()

            ZStack {
                LinearGradient(
                    colors: [
                        Color(NSColor(calibratedWhite: 0.125, alpha: 1)),
                        Color(NSColor(calibratedWhite: 0.085, alpha: 1)),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                PreviewStripBridge(
                    document: document,
                    state: state,
                    runtime: runtime,
                    controlStrip: controlStrip,
                    zoom: zoom,
                    showZones: showZones,
                    showHiddenItems: showHiddenItems,
                    metrics: $metrics,
                    hoveredSummary: $hoveredSummary,
                    selectedSummary: $selectedSummary,
                    dragFeedback: $dragFeedback,
                    optionKeyHeld: $optionKeyHeld
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: stageHeight)
            .clipped()

            Divider()

            footerBar
                .frame(height: 22)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Touch Bar preview")
    }

    // MARK: Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            breadcrumbAndStatus
            Spacer(minLength: 8)
            if let metrics {
                spaceUsageMeter(metrics.usage)
            }
            viewOptionToggles
            zoomMenu
            Picker(L10n.preview("Control Strip"), selection: $controlStrip) {
                ForEach(PreviewControlStrip.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.regular)
            .fixedSize()
            .help(L10n.preview("Compare the current Touch Bar with a collapsed or expanded system Control Strip"))
        }
    }

    private var breadcrumbAndStatus: some View {
        HStack(spacing: 8) {
            if state.groupPath.isEmpty {
                statusPill
            } else {
                HStack(spacing: 4) {
                    Button {
                        state.backToMain()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text(L10n.preview("Main Bar"))
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.accentColor)
                    .help(L10n.preview("Return to the main Touch Bar"))

                    ForEach(Array(state.groupPath.enumerated()), id: \.element) { index, groupID in
                        if let group = document.item(withID: groupID) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .accessibilityHidden(true)
                            if index == state.groupPath.count - 1 {
                                Text(verbatim: group.listTitle)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .lineLimit(1)
                            } else {
                                Button {
                                    state.enterGroup(groupID, in: document)
                                } label: {
                                    Text(verbatim: group.listTitle)
                                        .font(.system(size: 12.5))
                                        .lineLimit(1)
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                statusPill
            }

            if document.isDirty, let onSave {
                Button(action: onSave) {
                    Text(L10n.preview("Apply (⌘S)"))
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(L10n.preview("Save and apply to the Touch Bar (⌘S)"))
            }
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if document.isDirty {
            let count = metrics?.draftCount ?? 0
            let label = count > 0
                ? String(format: L10n.preview("Unsaved (%ld)"), count)
                : L10n.preview("Unsaved draft")
            pillBadge(text: label, dotColor: .orange, tint: .orange)
                .help(L10n.preview("Items with an orange dot are draft previews until saved"))
        } else if metrics?.connectedLive == true {
            pillBadge(text: L10n.preview("Live"), dotColor: .green, tint: .green)
                .help(L10n.preview("Mirrored live from your active Touch Bar"))
        } else {
            pillBadge(text: L10n.preview("Simulated"), dotColor: .secondary, tint: .secondary)
                .help(L10n.preview("Touch Bar is not currently mounted; showing simulated layout"))
        }
    }

    private func pillBadge(text: String, dotColor: Color, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(verbatim: text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(tint == .secondary ? .secondary : tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .background(tint.opacity(0.13))
        .clipShape(Capsule())
    }

    private func spaceUsageMeter(_ usage: PreviewSpaceUsage) -> some View {
        let barColor: Color = {
            switch usage.level {
            case .normal: return .accentColor
            case .tight: return .orange
            case .overflow: return .red
            }
        }()
        let text: String = usage.isExpandedControlStrip
            ? L10n.preview("0 pt (covered)")
            : String(format: L10n.preview("%g / %g pt"),
                     usage.usedWidth, usage.availableWidth)
        let helpText: String = {
            if usage.isExpandedControlStrip {
                return L10n.preview("Expanded Control Strip covers the entire MTMR area")
            }
            let source = usage.measured
                ? L10n.preview("Application width measured on this Touch Bar")
                : L10n.preview("Reference width for the simulated layout")
            if usage.level == .overflow {
                return source + " · " + L10n.preview("Overflowing zones scroll horizontally")
            }
            return source
        }()

        return HStack(spacing: 7) {
            Text(verbatim: text)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundColor(usage.level == .overflow ? .red : .secondary)
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.22))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * CGFloat(usage.fillRatio)))
                }
            }
            .frame(width: 44, height: 6)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.75)
        )
        .help(helpText)
    }

    private var viewOptionToggles: some View {
        HStack(spacing: 5) {
            Button {
                showZones.toggle()
            } label: {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(showZones ? .accentColor : .secondary)
                    .frame(width: 28, height: 24)
                    .background(showZones ? Color.accentColor.opacity(0.14) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(showZones ? Color.accentColor.opacity(0.45) : Color(NSColor.separatorColor).opacity(0.75), lineWidth: 0.75)
            )
            .help(L10n.preview("Show Left / Center / Right zone guides"))
            .accessibilityLabel(L10n.preview("Toggle zone guides"))

            let hiddenCount = metrics?.hiddenCount ?? 0
            Button {
                showHiddenItems.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showHiddenItems ? "eye" : "eye.slash")
                        .font(.system(size: 12.5, weight: .medium))
                    if hiddenCount > 0 {
                        Text("\(hiddenCount)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    }
                }
                .foregroundColor(showHiddenItems ? .accentColor : .secondary)
                .padding(.horizontal, hiddenCount > 0 ? 7 : 6)
                .frame(height: 24)
                .background(showHiddenItems ? Color.accentColor.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(showHiddenItems ? Color.accentColor.opacity(0.45) : Color(NSColor.separatorColor).opacity(0.75), lineWidth: 0.75)
            )
            .help(hiddenCount > 0
                  ? String(format: L10n.preview("Show %ld hidden or app-specific items as ghosts"), hiddenCount)
                  : L10n.preview("Show hidden or app-specific items as ghosts"))
            .accessibilityLabel(L10n.preview("Toggle hidden items"))
        }
    }

    private var zoomMenu: some View {
        Menu {
            ForEach(PreviewZoom.allCases) { option in
                Button {
                    zoom = option
                } label: {
                    if option == zoom {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                Text(verbatim: zoom.title)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
        }
        .fixedSize()
        .help(L10n.preview("Preview zoom scale"))
        .accessibilityLabel(L10n.preview("Preview zoom"))
    }

    // MARK: Footer

    private var footerBar: some View {
        HStack(spacing: 10) {
            if let drag = dragFeedback {
                dragSummaryView(drag)
            } else if let summary = hoveredSummary ?? selectedSummary {
                itemSummaryView(summary, isHovered: hoveredSummary != nil)
            } else {
                Text(L10n.preview("Select an item in the preview to inspect or right-click for quick actions"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            if let drag = dragFeedback {
                if drag.isNoOp {
                    Text(L10n.preview("Drop to keep position · Esc to cancel"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(verbatim: String(format: L10n.preview("Drop in %@ · Esc to cancel"), drag.targetAlign.title))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                }
            } else if optionKeyHeld {
                HStack(spacing: 5) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 12.5))
                    Text(L10n.preview("Test mode: click an item to trigger its action"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.green)
                .lineLimit(1)
            } else {
                Text(L10n.preview("Drag reorder · Option-click test · Right-click menu · Double-click group"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if dragFeedback == nil && !document.gestures.isEmpty {
                Button {
                    state.selection = document.gestures.first?.id
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 11))
                        Text(String(format: L10n.preview("Gestures %ld"), document.gestures.count))
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(L10n.preview("Jump to swipe gestures in the sidebar"))
            }
        }
    }

    private func dragSummaryView(_ drag: PreviewDragFeedback) -> some View {
        HStack(spacing: 7) {
            Text(L10n.preview("Dragging"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))

            Text(verbatim: drag.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            if drag.constrainedToFixedAlign {
                Text(L10n.preview("Escape stays on the left"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
                    .lineLimit(1)
            } else {
                Text(verbatim: "→ \(drag.targetAlign.title)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func itemSummaryView(_ summary: PreviewItemSummary, isHovered: Bool) -> some View {
        HStack(spacing: 7) {
            Text(isHovered
                 ? L10n.preview("Hover")
                 : L10n.preview("Selected"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovered ? .secondary : .accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((isHovered ? Color.secondary : Color.accentColor).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))

            Text(verbatim: summary.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(verbatim: "· \(summary.align.title)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if summary.width > 0 {
                let widthLabel = summary.isFixedWidth
                    ? String(format: L10n.preview("%g pt"), summary.width)
                    : String(format: L10n.preview("Auto %g pt"), summary.width)
                Text(verbatim: "· \(widthLabel)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.secondary)
            }

            if let tag = statusTag(for: summary) {
                Text(verbatim: tag.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(tag.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tag.color.opacity(0.14))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
        }
    }

    private func statusTag(for summary: PreviewItemSummary) -> (text: String, color: Color)? {
        switch summary.status {
        case .draft:
            return (L10n.preview("Draft"), .orange)
        case .hiddenEmptyOutput:
            return (L10n.preview("Empty output"), .secondary)
        case .conditionalHidden:
            return (L10n.preview("App-specific"), .purple)
        case .live:
            return summary.isGroup ? (L10n.preview("Group"), .accentColor) : nil
        }
    }
}

// MARK: - NSViewRepresentable Bridge

private struct PreviewStripBridge: NSViewRepresentable {
    @ObservedObject var document: PresetDocument
    @ObservedObject var state: CustomizerState
    let runtime: RunningTouchBar
    let controlStrip: PreviewControlStrip
    let zoom: PreviewZoom
    let showZones: Bool
    let showHiddenItems: Bool
    @Binding var metrics: PreviewStageMetrics?
    @Binding var hoveredSummary: PreviewItemSummary?
    @Binding var selectedSummary: PreviewItemSummary?
    @Binding var dragFeedback: PreviewDragFeedback?
    @Binding var optionKeyHeld: Bool

    func makeNSView(context: Context) -> LivePreviewStrip { LivePreviewStrip() }

    func updateNSView(_ strip: LivePreviewStrip, context: Context) {
        state.strip = strip
        if state.previewActive {
            strip.onMetricsChange = { [binding = $metrics] in binding.wrappedValue = $0 }
            strip.onHoverSummaryChange = { [binding = $hoveredSummary] in binding.wrappedValue = $0 }
            strip.onSelectedSummaryChange = { [binding = $selectedSummary] in binding.wrappedValue = $0 }
            strip.onDragFeedbackChange = { [binding = $dragFeedback] in binding.wrappedValue = $0 }
            strip.onOptionKeyChange = { [binding = $optionKeyHeld] in binding.wrappedValue = $0 }
            strip.update(
                document: document,
                state: state,
                controller: runtime,
                controlStrip: controlStrip,
                zoom: zoom,
                showZones: showZones,
                showHiddenItems: showHiddenItems
            )
        } else {
            strip.disconnect()
        }
    }

    static func dismantleNSView(_ strip: LivePreviewStrip, coordinator: ()) { strip.disconnect() }
}

// MARK: - Preview Zone with Overflow Fades & Auto-Scroll

private final class EdgeFadeView: NSView {
    private let gradient = CAGradientLayer()
    private let isLeading: Bool

    init(leading: Bool) {
        self.isLeading = leading
        super.init(frame: .zero)
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        let dark = NSColor.black.withAlphaComponent(0.92).cgColor
        let clear = NSColor.black.withAlphaComponent(0).cgColor
        gradient.colors = leading ? [dark, clear] : [clear, dark]
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
}

private final class PreviewZone: NSScrollView {
    private let canvas = NSView()
    private let leadingFade = EdgeFadeView(leading: true)
    private let trailingFade = EdgeFadeView(leading: false)
    private var boundsObserver: NSObjectProtocol?

    var tiles: [LivePreviewItemView] = []
    var spacing = TouchBarMetrics.stackSpacing
    var onScroll: (() -> Void)?
    private var lastMountedOffset: CGFloat?

    var naturalWidth: CGFloat {
        let sizes = tiles.map(\.preferredWidth).filter { $0 > 0 }
        return sizes.reduce(0, +) + CGFloat(max(0, sizes.count - 1)) * spacing
    }

    var visibleTileCount: Int {
        tiles.filter { $0.preferredWidth > 0 }.count
    }

    var isOverflowing: Bool {
        canvas.frame.width > bounds.width + 0.5
    }

    init() {
        super.init(frame: .zero)
        drawsBackground = false
        scrollerStyle = .overlay
        autohidesScrollers = true
        horizontalScrollElasticity = .none
        documentView = canvas
        contentView.postsBoundsChangedNotifications = true

        addSubview(leadingFade)
        addSubview(trailingFade)
        leadingFade.isHidden = true
        trailingFade.isHidden = true

        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: contentView,
            queue: .main
        ) { [weak self] _ in
            self?.updateOverflowFades()
            self?.onScroll?()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    override func layout() {
        super.layout()
        let fadeWidth: CGFloat = min(18, bounds.width * 0.25)
        leadingFade.frame = NSRect(x: 0, y: 0, width: fadeWidth, height: bounds.height)
        trailingFade.frame = NSRect(x: max(0, bounds.width - fadeWidth), y: 0, width: fadeWidth, height: bounds.height)
        updateOverflowFades()
    }

    func updateOverflowFades() {
        guard bounds.width > 8, canvas.frame.width > bounds.width + 0.5 else {
            leadingFade.isHidden = true
            trailingFade.isHidden = true
            return
        }
        let visible = contentView.bounds
        leadingFade.isHidden = visible.minX <= 1
        trailingFade.isHidden = (canvas.frame.width - visible.maxX) <= 1
    }

    private var dragExpandLeading: CGFloat = 0
    private var dragExpandTrailing: CGFloat = 0

    func setDragExpansion(leading: CGFloat, trailing: CGFloat, restingFrame: NSRect) {
        // Keep expansion monotonic during an active drag so tiles returning to rest never clip mid-animation.
        let targetL = max(dragExpandLeading, max(0, leading))
        let targetT = max(dragExpandTrailing, max(0, trailing))
        let deltaL = targetL - dragExpandLeading
        let deltaT = targetT - dragExpandTrailing
        guard deltaL > 0.25 || deltaT > 0.25 else { return }

        dragExpandLeading = targetL
        dragExpandTrailing = targetT

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = NSRect(
            x: restingFrame.minX - targetL,
            y: restingFrame.minY,
            width: restingFrame.width + targetL + targetT,
            height: restingFrame.height
        )
        let nextCanvasW = max(frame.width, canvas.frame.width + deltaL + deltaT)
        canvas.setFrameSize(NSSize(width: nextCanvasW, height: frame.height))
        if deltaL > 0 {
            for tile in tiles {
                tile.frame.origin.x += deltaL
            }
        }
        updateOverflowFades()
        CATransaction.commit()
    }

    func resetDragExpansion() {
        dragExpandLeading = 0
        dragExpandTrailing = 0
    }

    func autoScroll(by deltaX: CGFloat) -> Bool {
        guard bounds.width > 0, canvas.frame.width > bounds.width + 0.5 else { return false }
        let maxOffset = max(0, canvas.frame.width - contentView.bounds.width)
        let current = contentView.bounds.minX
        let next = min(max(0, current + deltaX), maxOffset)
        guard abs(next - current) > 0.25 else { return false }
        contentView.scroll(to: NSPoint(x: next, y: 0))
        reflectScrolledClipView(contentView)
        updateOverflowFades()
        return true
    }

    func scrollTileToVisible(_ tile: LivePreviewItemView) {
        guard tile.superview === canvas, !tile.isHidden, bounds.width > 0 else { return }
        let visible = contentView.bounds
        if visible.contains(tile.frame) { return }
        let padded = tile.frame.insetBy(dx: -14, dy: 0)
        let clampedX = min(max(0, padded.minX), max(0, canvas.frame.width - visible.width))
        let target: CGFloat
        if tile.frame.maxX > visible.maxX {
            target = min(max(0, tile.frame.maxX + 14 - visible.width), max(0, canvas.frame.width - visible.width))
        } else {
            target = clampedX
        }
        contentView.scroll(to: NSPoint(x: target, y: 0))
        reflectScrolledClipView(contentView)
        updateOverflowFades()
    }

    func place(in rect: NSRect, centered: Bool) {
        if lastMountedOffset != nil {
            lastMountedOffset = nil
            contentView.scroll(to: .zero)
        }
        frame = rect
        let width = naturalWidth
        let size = NSSize(width: max(rect.width, width), height: rect.height)
        if canvas.frame.size != size { canvas.setFrameSize(size) }
        var x = centered ? max(0, (rect.width - width) / 2) : 0
        for tile in tiles {
            if tile.superview !== canvas { canvas.addSubview(tile) }
            tile.isHidden = tile.preferredWidth == 0
            guard !tile.isHidden else { continue }
            tile.frame = NSRect(x: x, y: 0, width: tile.preferredWidth, height: rect.height)
            x += tile.preferredWidth + spacing
        }
        // Clamp existing scroll offset if content shrank.
        let maxOffset = max(0, canvas.frame.width - contentView.bounds.width)
        if contentView.bounds.minX > maxOffset {
            contentView.scroll(to: NSPoint(x: maxOffset, y: 0))
            reflectScrolledClipView(contentView)
        }
        updateOverflowFades()
    }

    func place(in viewport: MountedTouchBarViewport) {
        var positions: [(tile: LivePreviewItemView, frame: NSRect)] = []
        var visible = NSRect.null
        var extent = NSRect.null
        for tile in tiles {
            if tile.superview !== canvas { canvas.addSubview(tile) }
            guard let frames = viewport.frames(of: tile.source?.view), frames.item.width > 0, tile.preferredWidth > 0 else {
                tile.isHidden = true
                continue
            }
            tile.isHidden = false
            tile.synchronizeMountedButtons()
            positions.append((tile, frames.item))
            extent = extent.union(frames.item)
            if !frames.visible.isEmpty { visible = visible.union(frames.visible) }
        }
        guard !visible.isEmpty else {
            frame = .zero
            updateOverflowFades()
            return
        }
        frame = NSRect(x: visible.minX, y: 0, width: visible.width, height: TouchBarMetrics.height)
        canvas.setFrameSize(NSSize(width: extent.width, height: TouchBarMetrics.height))
        for (tile, position) in positions { tile.frame = position.offsetBy(dx: -extent.minX, dy: 0) }
        let offset = visible.minX - extent.minX
        if lastMountedOffset != offset {
            lastMountedOffset = offset
            contentView.scroll(to: NSPoint(x: offset, y: 0))
            reflectScrolledClipView(contentView)
        }
        updateOverflowFades()
    }
}

// MARK: - LivePreviewStrip

final class LivePreviewStrip: NSView {
    private let stageScrollView = NSScrollView()
    private let stageDocument = NSView()
    private let surface = TouchBarPreviewSurface()
    private let observation = TouchBarLayoutObservation()
    private let left = PreviewZone()
    private let center = PreviewZone()
    private let right = PreviewZone()
    private var tiles: [UUID: LivePreviewItemView] = [:]
    private var snapshots: [UUID: PreviewItemSnapshot] = [:]
    // Keep ancestors alive when browsing an off-hardware nested group.
    private var groups: [GroupBarItem] = []
    private var generation = -1
    private weak var runtime: RunningTouchBar?
    private var panelWidth: CGFloat?
    private var lastCollapsed: NSRect?
    private var mode = PreviewControlStrip.current
    private var zoom = PreviewZoom.fit
    private var showZones = true
    private var showsMountedLevel = false
    private var balanced = false
    private var selectedID: UUID?
    private var hoveredID: UUID?
    private var pendingScrollToSelection = false
    private struct RestingZoneSnapshot {
        let frame: NSRect
        let spacing: CGFloat
        let slots: [PreviewDropSlot] // stored in resting canvas coordinates
    }

    private struct DragSession {
        let id: UUID
        let item: PresetItem
        let groupID: UUID?
        let grabOffsetX: CGFloat
        let tileWidth: CGFloat
        let appWidth: CGFloat
        let leftResting: RestingZoneSnapshot
        let centerResting: RestingZoneSnapshot
        let rightResting: RestingZoneSnapshot
        var lastWindowPoint: NSPoint
        var currentTarget: PreviewDropTarget?
        var escapeMonitor: Any?
        var autoScrollTimer: Timer?
    }

    private var lastMetrics: PreviewStageMetrics?
    private var lastHoverSummary: PreviewItemSummary?
    private var lastSelectedSummary: PreviewItemSummary?
    private var lastDragFeedback: PreviewDragFeedback?
    private var activeDrag: DragSession?
    private var optionHeld = false
    private var flagsMonitor: Any?

    fileprivate var onMetricsChange: ((PreviewStageMetrics) -> Void)?
    fileprivate var onHoverSummaryChange: ((PreviewItemSummary?) -> Void)?
    fileprivate var onSelectedSummaryChange: ((PreviewItemSummary?) -> Void)?
    fileprivate var onDragFeedbackChange: ((PreviewDragFeedback?) -> Void)?
    fileprivate var onOptionKeyChange: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        stageScrollView.drawsBackground = false
        stageScrollView.hasHorizontalScroller = true
        stageScrollView.hasVerticalScroller = false
        stageScrollView.scrollerStyle = .overlay
        stageScrollView.autohidesScrollers = true
        stageScrollView.documentView = stageDocument
        addSubview(stageScrollView)

        stageDocument.addSubview(surface)
        for zone in [left, center, right] {
            surface.application.addSubview(zone)
            zone.onScroll = { [weak self] in self?.updateSelectionHalo() }
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let monitor = activeDrag?.escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        activeDrag?.autoScrollTimer?.invalidate()
        removeFlagsMonitor()
    }

    private func installFlagsMonitorIfNeeded() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateOptionKey(event.modifierFlags.contains(.option))
            return event
        }
    }

    private func removeFlagsMonitor() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
    }

    private func updateOptionKey(_ held: Bool) {
        guard optionHeld != held else { return }
        optionHeld = held
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onOptionKeyChange?(self.optionHeld)
        }
    }

    func disconnect() {
        cancelActiveDrag()
        removeFlagsMonitor()
        observation.disconnect()
        runtime = nil
        lastMetrics = nil
        lastHoverSummary = nil
        lastSelectedSummary = nil
        lastDragFeedback = nil
        hoveredID = nil
        selectedID = nil
        optionHeld = false
        onMetricsChange = nil
        onHoverSummaryChange = nil
        onSelectedSummaryChange = nil
        onDragFeedbackChange = nil
        onOptionKeyChange = nil
        for tile in tiles.values {
            tile.disconnect()
            tile.removeFromSuperview()
        }
        tiles.removeAll()
        snapshots.removeAll()
        left.tiles = []
        center.tiles = []
        right.tiles = []
        groups.removeAll()
        generation = -1
        surface.updateSelectionHalo(nil)
        surface.updateZoneGuides([])
    }

    func update(document: PresetDocument, state: CustomizerState, controller: RunningTouchBar,
                controlStrip: PreviewControlStrip = .current, zoom: PreviewZoom = .fit,
                showZones: Bool = true, showHiddenItems: Bool = false) {
        installFlagsMonitorIfNeeded()
        if generation != -1 && generation != controller.generation {
            for (id, tile) in tiles {
                if let snap = tile.captureSnapshot() { snapshots[id] = snap }
            }
            for tile in tiles.values {
                tile.disconnect()
                tile.removeFromSuperview()
            }
            tiles.removeAll()
            groups.removeAll()
        }
        generation = controller.generation
        runtime = controller
        let width = controller.panelWidth
        if width != panelWidth { lastCollapsed = nil }
        panelWidth = width
        mode = controlStrip
        self.zoom = zoom
        self.showZones = showZones

        if selectedID != state.selection {
            selectedID = state.selection
            pendingScrollToSelection = selectedID != nil
        }

        let groupIDs = state.groupPath
        var chain: [GroupBarItem] = []
        for id in groupIDs {
            // Editing one child prevents testing the old Group button, but its unchanged
            // siblings can still bind individually through this verified parent.
            guard let path = document.livePath(for: id, revision: controller.appliedRevision, checkingChildren: false),
                  let group = lookup(path: path, parents: chain, controller: controller) as? GroupBarItem else { break }
            chain.append(group)
        }
        groups = chain
        let siblings = groupIDs.last.map { document.item(withID: $0)?.children ?? [] } ?? document.items
        let siblingIDs = Set(siblings.map(\.id))
        snapshots = snapshots.filter { siblingIDs.contains($0.key) }

        showsMountedLevel = chain.count == groupIDs.count && (chain.last?.sourcePath ?? []) == controller.presentedGroupPath
        balanced = groupIDs.isEmpty && siblings.contains { $0.type == "codexToday" && $0.align == .center }
        left.spacing = balanced ? TouchBarMetrics.stackSpacing : TouchBarMetrics.itemSpacing
        right.spacing = left.spacing

        var next: [UUID: LivePreviewItemView] = [:]
        left.tiles = []
        center.tiles = []
        right.tiles = []
        let isTopLevel = groupIDs.isEmpty

        for item in siblings where !item.isGesture {
            var source: NSTouchBarItem?
            let livePath: [Int]?
            if chain.count == groupIDs.count {
                livePath = document.livePath(for: item.id, revision: controller.appliedRevision)
                if let livePath {
                    source = lookup(path: livePath, parents: chain, controller: controller)
                }
            } else {
                livePath = nil
            }
            let isConditionalHidden = source == nil && livePath != nil && item.matchAppIdPattern != nil

            let existing = tiles[item.id]
            if let existing, existing.source != nil, let snap = existing.captureSnapshot() {
                snapshots[item.id] = snap
            }

            let tile: LivePreviewItemView
            if let existing, existing.source === source, existing.item.json == item.json,
               (existing.item.children != nil) == (item.children != nil),
               (existing.status == .conditionalHidden(item.matchAppIdPattern ?? "")) == isConditionalHidden {
                tile = existing
            } else {
                let fallback = snapshots[item.id]
                existing?.disconnect()
                existing?.removeFromSuperview()
                tile = LivePreviewItemView(item: item, source: source, isConditionalHidden: isConditionalHidden, fallback: fallback)
                tile.widthDidChange = { [weak self] in
                    self?.needsLayout = true
                    self?.reportSummaries()
                }
            }

            tile.canMoveZone = isTopLevel
            tile.showWhenHidden = showHiddenItems
            tile.selected = item.id == state.selection

            let id = item.id
            tile.onHoverChanged = { [weak self] isHovered in
                guard let self else { return }
                if isHovered {
                    self.hoveredID = id
                } else if self.hoveredID == id {
                    self.hoveredID = nil
                }
                self.reportSummaries()
            }
            tile.onClick = { [weak self, weak tile, weak state, weak document] click, target, point in
                guard let self, let tile, let state, let document, state.previewActive,
                      state.groupPath == groupIDs, self.tiles[id] === tile, document.item(withID: id) != nil else { return }
                switch click {
                case .select: state.selection = id
                case .enterGroup: state.enterGroup(id, in: document)
                case .test:
                    self.performTest(target, id: id, in: tile, at: point, document: document, controller: controller)
                case .ignore: break
                }
            }
            tile.onContextAction = { [weak self, weak tile, weak state, weak document] action in
                guard let self, let tile, let state, let document, state.previewActive,
                      state.groupPath == groupIDs, self.tiles[id] === tile, let current = document.item(withID: id) else { return }
                switch action {
                case let .test(target, point):
                    self.performTest(target, id: id, in: tile, at: point, document: document, controller: controller)
                case .enterGroup:
                    state.enterGroup(id, in: document)
                case .duplicate:
                    if let copy = document.duplicate(id: id) { state.selection = copy }
                case let .moveTo(align):
                    var updated = current
                    updated.align = align
                    document.update(updated)
                case let .setBordered(bordered):
                    var updated = current
                    updated.json["bordered"] = .bool(bordered)
                    document.update(updated)
                case .delete:
                    if state.selection == id { state.selection = nil }
                    document.remove(id: id)
                }
            }
            tile.onDragEvent = { [weak self, weak tile, weak state, weak document] event in
                guard let self, let tile, let state, let document, state.previewActive,
                      state.groupPath == groupIDs, self.tiles[id] === tile,
                      let current = document.item(withID: id) else {
                    self?.cancelActiveDrag()
                    return
                }
                self.handleDragEvent(event, item: current, tile: tile, groupID: groupIDs.last, state: state, document: document)
            }

            next[id] = tile
            switch item.align {
            case .left: left.tiles.append(tile)
            case .center: center.tiles.append(tile)
            case .right: right.tiles.append(tile)
            }
        }
        for (id, tile) in tiles where next[id] == nil {
            tile.disconnect()
            tile.removeFromSuperview()
        }
        tiles = next
        if let dragID = activeDrag?.id, tiles[dragID] == nil {
            cancelActiveDrag()
        }
        if let hoveredID, tiles[hoveredID] == nil {
            self.hoveredID = nil
        }
        needsLayout = true
        reportSummaries()
    }

    // MARK: - Drag Reorder & Cross-Zone Move

    private func handleDragEvent(_ event: PreviewDragEvent, item: PresetItem, tile: LivePreviewItemView,
                                 groupID: UUID?, state: CustomizerState, document: PresetDocument) {
        switch event {
        case let .began(windowPoint, grabOffsetX):
            cancelActiveDrag()
            state.selection = item.id
            let width = max(16, tile.bounds.width)
            let snapshot = tile.dragSnapshot()
            let pointInApp = surface.application.convert(windowPoint, from: nil)
            surface.beginDrag(snapshot: snapshot, size: NSSize(width: width, height: TouchBarMetrics.height), xInApplication: pointInApp.x - grabOffsetX)

            var session = DragSession(
                id: item.id,
                item: item,
                groupID: groupID,
                grabOffsetX: grabOffsetX,
                tileWidth: width,
                appWidth: surface.application.bounds.width,
                leftResting: captureRestingZone(left),
                centerResting: captureRestingZone(center),
                rightResting: captureRestingZone(right),
                lastWindowPoint: windowPoint,
                currentTarget: nil,
                escapeMonitor: nil,
                autoScrollTimer: nil
            )
            session.escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak tile] keyEvent in
                if keyEvent.keyCode == 53 {
                    tile?.cancelDragIfActive()
                    self?.cancelActiveDrag()
                    return nil
                }
                return keyEvent
            }
            session.autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.stepDragAutoScroll()
            }
            activeDrag = session
            updateDragTarget(at: windowPoint, animated: false)

        case let .moved(windowPoint):
            guard activeDrag?.id == item.id else { return }
            activeDrag?.lastWindowPoint = windowPoint
            updateDragTarget(at: windowPoint, animated: true)

        case let .ended(windowPoint):
            guard activeDrag?.id == item.id else { return }
            updateDragTarget(at: windowPoint, animated: false)
            let target = activeDrag?.currentTarget
            let targetGroup = activeDrag?.groupID
            let willMove = target.map { !$0.isNoOp && !$0.constrainedToFixedAlign } ?? false
            finishDragCleanup(animated: !willMove)
            if let target, willMove {
                if document.relocate(id: item.id, to: target.align, before: target.beforeItemID, inGroup: targetGroup) {
                    state.selection = item.id
                }
                needsLayout = true
                layoutSubtreeIfNeeded()
            }
            updateSelectionHalo()

        case .cancelled:
            if activeDrag?.id == item.id {
                finishDragCleanup(animated: true)
                updateSelectionHalo()
            }
        }
    }

    private func cancelActiveDrag() {
        guard let id = activeDrag?.id else { return }
        finishDragCleanup(animated: true)
        tiles[id]?.cancelDragIfActive()
        updateSelectionHalo()
    }

    private func finishDragCleanup(animated: Bool = false) {
        if let monitor = activeDrag?.escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        activeDrag?.autoScrollTimer?.invalidate()
        activeDrag = nil
        for tile in tiles.values {
            tile.setDragSlideOffset(0, animated: animated)
        }
        surface.endDrag()
        reportDragFeedback(nil)
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) { [weak self] in
                guard let self, self.activeDrag == nil else { return }
                for zone in [self.left, self.center, self.right] {
                    zone.resetDragExpansion()
                }
                self.needsLayout = true
            }
        } else {
            for zone in [left, center, right] {
                zone.resetDragExpansion()
            }
        }
    }

    private func captureRestingZone(_ zone: PreviewZone) -> RestingZoneSnapshot {
        guard !zone.isHidden, zone.frame.width > 0 else {
            return RestingZoneSnapshot(frame: .zero, spacing: zone.spacing, slots: [])
        }
        let slots: [PreviewDropSlot] = zone.tiles.compactMap { tile in
            guard !tile.isHidden, tile.superview != nil, tile.frame.width > 0 else { return nil }
            return PreviewDropSlot(id: tile.item.id, frame: tile.frame)
        }
        let measuredSpacing: CGFloat
        if slots.count >= 2 {
            measuredSpacing = max(0, slots[1].frame.minX - slots[0].frame.maxX)
        } else {
            measuredSpacing = zone.spacing
        }
        return RestingZoneSnapshot(frame: zone.frame, spacing: measuredSpacing, slots: slots)
    }

    private func projectedRestingSlots(_ snapshot: RestingZoneSnapshot, zone: PreviewZone) -> [PreviewDropSlot] {
        guard !snapshot.slots.isEmpty, snapshot.frame.width > 0 else { return [] }
        let scrollX = zone.contentView.bounds.minX
        return snapshot.slots.map { slot in
            PreviewDropSlot(
                id: slot.id,
                frame: CGRect(
                    x: snapshot.frame.minX + slot.frame.minX - scrollX,
                    y: 0,
                    width: slot.frame.width,
                    height: TouchBarMetrics.height
                )
            )
        }
    }

    private func updateDragTarget(at windowPoint: NSPoint, animated: Bool = true) {
        guard var session = activeDrag else { return }
        let pointInApp = surface.application.convert(windowPoint, from: nil)
        let leftSlots = projectedRestingSlots(session.leftResting, zone: left)
        let centerSlots = projectedRestingSlots(session.centerResting, zone: center)
        let rightSlots = projectedRestingSlots(session.rightResting, zone: right)

        let viewport = stageScrollView.contentView
        let inViewport = viewport.bounds.contains(viewport.convert(windowPoint, from: nil))
        let target = inViewport && surface.application.bounds.contains(pointInApp) ? PreviewDropResolver.resolve(
            cursorX: pointInApp.x,
            appWidth: session.appWidth,
            draggedID: session.id,
            draggedAlign: session.item.align,
            hasFixedAlign: session.item.hasFixedAlign,
            leftZone: session.leftResting.frame,
            centerZone: session.centerResting.frame,
            rightZone: session.rightResting.frame,
            leftSlots: leftSlots,
            centerSlots: centerSlots,
            rightSlots: rightSlots
        ) : nil
        session.currentTarget = target
        activeDrag = session

        var landingSlot: NSRect?
        if let target {
            let lFrame = session.leftResting.frame
            let cFrame = session.centerResting.frame
            let rFrame = session.rightResting.frame

            let leftTrailingRoom: CGFloat = {
                if cFrame.width > 0 { return max(0, cFrame.minX - lFrame.maxX) }
                if rFrame.width > 0 { return max(0, rFrame.minX - lFrame.maxX) }
                return max(0, session.appWidth - lFrame.maxX)
            }()
            let centerLeadingRoom = cFrame.width > 0 ? max(0, cFrame.minX - (lFrame.width > 0 ? lFrame.maxX : 0)) : 0
            let centerTrailingRoom = cFrame.width > 0 ? max(0, (rFrame.width > 0 ? rFrame.minX : session.appWidth) - cFrame.maxX) : 0
            let rightLeadingRoom: CGFloat = {
                if cFrame.width > 0 { return max(0, rFrame.minX - cFrame.maxX) }
                if lFrame.width > 0 { return max(0, rFrame.minX - lFrame.maxX) }
                return max(0, rFrame.minX)
            }()

            let configs: [(PresetAlign, PreviewZone, RestingZoneSnapshot, [PreviewDropSlot], CGFloat, CGFloat)] = [
                (.left, left, session.leftResting, leftSlots, 0, leftTrailingRoom),
                (.center, center, session.centerResting, centerSlots, centerLeadingRoom, centerTrailingRoom),
                (.right, right, session.rightResting, rightSlots, rightLeadingRoom, 0),
            ]

            for (align, zone, resting, slots, leadRoom, trailRoom) in configs {
                let plan = PreviewSlidePlanner.plan(
                    align: align,
                    slots: slots,
                    spacing: resting.spacing,
                    draggedID: session.id,
                    draggedWidth: session.tileWidth,
                    draggedAlign: session.item.align,
                    target: target,
                    availableLeadingRoom: leadRoom,
                    availableTrailingRoom: trailRoom
                )
                if plan.expandLeading > 0 || plan.expandTrailing > 0, resting.frame.width > 0 {
                    zone.setDragExpansion(leading: plan.expandLeading, trailing: plan.expandTrailing, restingFrame: resting.frame)
                }
                for tile in zone.tiles where tile.item.id != session.id {
                    tile.setDragSlideOffset(plan.offsets[tile.item.id] ?? 0, animated: animated)
                }
                if align == target.align, let gap = plan.gapRectInApplication {
                    landingSlot = gap
                }
            }
        } else {
            for tile in tiles.values {
                tile.setDragSlideOffset(0, animated: animated)
            }
        }

        surface.updateDrag(
            xInApplication: pointInApp.x - session.grabOffsetX,
            ghostWidth: session.tileWidth,
            target: target,
            landingSlot: landingSlot
        )
        if let target {
            reportDragFeedback(PreviewDragFeedback(
                title: session.item.listTitle,
                targetAlign: target.align,
                isNoOp: target.isNoOp,
                constrainedToFixedAlign: target.constrainedToFixedAlign
            ))
        } else {
            reportDragFeedback(nil)
        }
    }

    private func stepDragAutoScroll() {
        guard let session = activeDrag else { return }
        let local = convert(session.lastWindowPoint, from: nil)
        let pointInApp = surface.application.convert(session.lastWindowPoint, from: nil)
        guard bounds.contains(local), pointInApp.y >= 0, pointInApp.y < surface.application.bounds.height else { return }
        var scrolled = false

        // 1. Auto-scroll zoomed outer stage when cursor approaches stage viewport edges.
        if stageDocument.frame.width > stageScrollView.contentSize.width + 0.5 {
            let edge: CGFloat = 34
            var delta: CGFloat = 0
            if local.x < edge {
                delta = -max(2, (edge - local.x) * 0.25)
            } else if local.x > bounds.width - edge {
                delta = max(2, (local.x - (bounds.width - edge)) * 0.25)
            }
            if delta != 0 {
                let clip = stageScrollView.contentView
                let maxX = max(0, stageDocument.frame.width - clip.bounds.width)
                let nextX = min(max(0, clip.bounds.minX + delta), maxX)
                if abs(nextX - clip.bounds.minX) > 0.25 {
                    clip.scroll(to: NSPoint(x: nextX, y: 0))
                    stageScrollView.reflectScrolledClipView(clip)
                    scrolled = true
                }
            }
        }

        // 2. Auto-scroll an overflowing zone when dragging near its inner edges.
        let cursorInApp = surface.application.convert(session.lastWindowPoint, from: nil)
        for zone in [left, center, right] where zone.isOverflowing && zone.frame.contains(cursorInApp) {
            let localX = cursorInApp.x - zone.frame.minX
            let edge: CGFloat = min(26, zone.frame.width * 0.22)
            if localX < edge {
                if zone.autoScroll(by: -max(1.5, (edge - localX) * 0.2)) { scrolled = true }
            } else if localX > zone.frame.width - edge {
                if zone.autoScroll(by: max(1.5, (localX - (zone.frame.width - edge)) * 0.2)) { scrolled = true }
            }
        }

        if scrolled {
            updateDragTarget(at: session.lastWindowPoint)
        }
    }

    private func reportDragFeedback(_ feedback: PreviewDragFeedback?) {
        guard lastDragFeedback != feedback else { return }
        lastDragFeedback = feedback
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onDragFeedbackChange?(self.lastDragFeedback)
        }
    }

    private func performTest(_ target: NSTouchBarItem?, id: UUID, in tile: LivePreviewItemView, at point: NSPoint,
                             document: PresetDocument, controller: RunningTouchBar) {
        guard generation == controller.generation,
              let path = document.livePath(for: id, revision: controller.appliedRevision),
              lookup(path: path, parents: groups, controller: controller) === tile.source else { return }
        test(target, in: tile, at: point)
        tile.flashTestFeedback()
    }

    private func lookup(path: [Int], parents: [GroupBarItem], controller: RunningTouchBar) -> NSTouchBarItem? {
        guard path.count == parents.count + 1, let index = path.last else { return nil }
        if let root = parents.first, let first = path.first {
            guard controller.rootItem(at: first) === root, let parent = parents.last,
                  parent.sourcePath == Array(path.dropLast()) else { return nil }
            return parent.child(at: index)
        }
        return controller.rootItem(at: index)
    }

    private func test(_ target: NSTouchBarItem?, in tile: LivePreviewItemView, at point: NSPoint) {
        if let dock = tile.source as? AppScrubberTouchBarItem, !dock.items.contains(where: { $0 === target }) { return }
        if let calendar = tile.source as? UpNextScrubberTouchBarItem, !calendar.previewButtons.contains(where: { $0 === target }) { return }
        switch target {
        case let button as CustomButtonTouchBarItem: button.callActions(for: .singleTap)
        case let group as GroupBarItem: group.showPopover(nil)
        case let today as CodexTodayBarItem:
            let size = today.view.bounds.size
            today.previewTap(at: NSPoint(x: point.x * size.width / max(1, tile.bounds.width),
                                         y: point.y * size.height / max(1, tile.bounds.height)))
        default: break
        }
    }

    private func summary(for id: UUID?) -> PreviewItemSummary? {
        guard let id, let tile = tiles[id] else { return nil }
        return PreviewItemSummary(
            id: id,
            title: tile.item.listTitle,
            align: tile.item.align,
            width: tile.preferredWidth,
            isFixedWidth: tile.item.json["width"]?.doubleValue != nil,
            status: tile.status,
            isGroup: tile.item.children != nil
        )
    }

    private func reportSummaries() {
        let nextHover = summary(for: hoveredID)
        let nextSelected = summary(for: selectedID)
        let hoverChanged = nextHover != lastHoverSummary
        let selectedChanged = nextSelected != lastSelectedSummary
        guard hoverChanged || selectedChanged else { return }
        lastHoverSummary = nextHover
        lastSelectedSummary = nextSelected
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if hoverChanged { self.onHoverSummaryChange?(self.lastHoverSummary) }
            if selectedChanged { self.onSelectedSummaryChange?(self.lastSelectedSummary) }
        }
    }

    private func updateSelectionHalo() {
        guard activeDrag == nil, let selectedID, let tile = tiles[selectedID], !tile.isHidden,
              let zone = zoneContaining(tile), !zone.isHidden, zone.frame.width > 0 else {
            surface.updateSelectionHalo(nil)
            return
        }
        let raw = tile.convert(tile.bounds, to: surface.application)
        let zoneFrame = zone.frame
        let minX = max(raw.minX, zoneFrame.minX)
        let maxX = min(raw.maxX, zoneFrame.maxX)
        guard maxX > minX else {
            surface.updateSelectionHalo(nil)
            return
        }
        surface.updateSelectionHalo(NSRect(x: minX, y: 0, width: maxX - minX, height: TouchBarMetrics.height))
    }

    private func zoneContaining(_ tile: LivePreviewItemView) -> PreviewZone? {
        if left.tiles.contains(where: { $0 === tile }) { return left }
        if center.tiles.contains(where: { $0 === tile }) { return center }
        if right.tiles.contains(where: { $0 === tile }) { return right }
        return nil
    }

    private func scrollSelectedTileToVisible() {
        guard let selectedID, let tile = tiles[selectedID], !tile.isHidden,
              let zone = zoneContaining(tile) else { return }
        zone.scrollTileToVisible(tile)
        if stageDocument.frame.width > stageScrollView.contentSize.width + 0.5 {
            let rectInDoc = tile.convert(tile.bounds, to: stageDocument).insetBy(dx: -36, dy: 0)
            stageDocument.scrollToVisible(rectInDoc)
        }
    }

    override func layout() {
        super.layout()
        guard let runtime else { return }
        stageScrollView.frame = bounds

        let anchor = runtime.layoutAnchor
        let viewport = MountedTouchBarViewport(anchor: anchor)
        if let panelWidth, let rect = viewport?.panelRect, panelWidth - rect.maxX > TouchBarGeometry.systemGap {
            lastCollapsed = rect
        }
        let geometry = TouchBarGeometry(panelWidth: panelWidth, mounted: viewport?.panelRect, mode: mode, lastCollapsed: lastCollapsed)
        let horizontalMargin: CGFloat = 24
        let scale = zoom.scale(fitting: max(1, bounds.width - horizontalMargin), barWidth: geometry.deckWidth)
        let docWidth = max(bounds.width, ceil(geometry.deckWidth * scale + horizontalMargin))
        let docSize = NSSize(width: docWidth, height: bounds.height)
        if stageDocument.frame.size != docSize {
            stageDocument.setFrameSize(docSize)
        }
        if docWidth <= bounds.width + 0.5 && stageScrollView.contentView.bounds.minX != 0 {
            stageScrollView.contentView.scroll(to: .zero)
            stageScrollView.reflectScrolledClipView(stageScrollView.contentView)
        }

        let effectiveZones = showZones && mode != .expanded
        surface.place(in: stageDocument.bounds, geometry: geometry, scale: scale, expanded: mode == .expanded, showsZones: effectiveZones)

        let itemViews = showsMountedLevel && mode != .expanded ? tiles.values.flatMap(\.hardwareViews) : []
        observation.update(bar: runtime.presentedBar, views: [anchor].compactMap { $0 } + itemViews) { [weak self] in
            self?.needsLayout = true
        }

        let hasGhostVisible = tiles.values.contains { $0.status.isHiddenByRuntime && ($0.showWhenHidden || $0.selected) }
        let mountedInViewport = viewport.map { vp in itemViews.contains(where: { $0.isDescendant(of: vp.host) }) } ?? false
        let usesMountedLayout = geometry.application.width > 0
            && geometry.usesMountedWidth
            && showsMountedLevel
            && !hasGhostVisible
            && tiles.values.allSatisfy { $0.source != nil }
            && mountedInViewport

        if let drag = activeDrag {
            // Keep resting zone geometry and live slide transforms untouched while the user is actively dragging.
            updateDragTarget(at: drag.lastWindowPoint, animated: false)
            return
        }

        if geometry.application.width > 0 {
            if usesMountedLayout, let viewport {
                [left, center, right].forEach { $0.place(in: viewport) }
            } else {
                let widths = PreviewZoneWidths(
                    available: geometry.application.width,
                    left: left.naturalWidth,
                    center: center.naturalWidth,
                    right: right.naturalWidth,
                    balanced: balanced
                )
                let height = TouchBarMetrics.height
                left.place(in: NSRect(x: 0, y: 0, width: widths.left, height: height), centered: false)
                center.place(in: NSRect(x: widths.left + widths.firstGap, y: 0, width: widths.center, height: height), centered: true)
                let rightX = widths.left + widths.firstGap + widths.center + widths.lastGap
                right.place(in: NSRect(x: rightX, y: 0, width: widths.right, height: height), centered: false)
            }
        }

        if pendingScrollToSelection {
            pendingScrollToSelection = false
            scrollSelectedTileToVisible()
        }
        updateSelectionHalo()

        if effectiveZones {
            let specs: [TouchBarPreviewSurface.ZoneGuideSpec] = [
                (.left, left),
                (.center, center),
                (.right, right),
            ].compactMap { align, zone in
                guard zone.frame.width > 0, zone.visibleTileCount > 0 else { return nil }
                return TouchBarPreviewSurface.ZoneGuideSpec(
                    align: align,
                    rect: zone.frame,
                    count: zone.visibleTileCount,
                    overflowing: zone.isOverflowing
                )
            }
            surface.updateZoneGuides(specs)
        } else {
            surface.updateZoneGuides([])
        }

        let usedWidth = PreviewSpaceUsage.contentWidth(left: left.naturalWidth, center: center.naturalWidth, right: right.naturalWidth)
        let isOverflowing = left.isOverflowing || center.isOverflowing || right.isOverflowing
        let usage = PreviewSpaceUsage(
            usedWidth: usedWidth,
            availableWidth: geometry.application.width,
            measured: geometry.usesMeasuredWidth,
            isOverflowing: isOverflowing,
            isExpandedControlStrip: mode == .expanded
        )
        let liveCount = tiles.values.filter { $0.status == .live }.count
        let draftCount = tiles.values.filter { $0.status.isDraft }.count
        let hiddenCount = tiles.values.filter { $0.status.isHiddenByRuntime }.count
        let currentMetrics = PreviewStageMetrics(
            usage: usage,
            liveCount: liveCount,
            draftCount: draftCount,
            hiddenCount: hiddenCount,
            connectedLive: runtime.presentedBar != nil && (liveCount > 0 || tiles.isEmpty)
        )
        if lastMetrics != currentMetrics {
            lastMetrics = currentMetrics
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastMetrics == currentMetrics else { return }
                self.onMetricsChange?(currentMetrics)
            }
        }
        reportSummaries()
    }
}
