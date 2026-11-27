import AppKit
import Combine

extension L10n {
    /// Preview-specific strings ship with the editor and follow the selected bundle.
    static func preview(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: tr(key), table: "LivePreview")
    }
}

enum RunningPresetNotice: Equatable {
    case loadFailed
    case differentRevision

    var message: String {
        switch self {
        case .loadFailed:
            return L10n.preview("The running Touch Bar could not load its preset.")
        case .differentRevision:
            return L10n.preview("The running Touch Bar uses a different preset version. Save or revert to resume live preview.")
        }
    }
}

/// The window observes topology here. Widget display events go directly to the affected tile.
@MainActor protocol RunningTouchBar: AnyObject {
    var generation: Int { get }
    var appliedRevision: PresetRevision? { get }
    var layoutChanges: PassthroughSubject<Void, Never> { get }
    var presetURL: URL { get }
    var presentedGroupPath: [Int] { get }
    var isReloadPending: Bool { get }
    var panelWidth: CGFloat? { get }
    var presentedBar: NSTouchBar? { get }
    var layoutAnchor: NSView? { get }
    func rootItem(at index: Int) -> NSTouchBarItem?
    func scheduleReload(path: String)
}

/// Sources emit after applying a display change. With the editor closed, this is a weak nil check.
@MainActor protocol TouchBarPreviewSource: AnyObject {
    var previewChanges: PreviewChanges { get }
}

@MainActor protocol TouchBarPreviewObserver: AnyObject {
    func previewNeedsDisplay()
}

@MainActor final class PreviewChanges {
    weak var observer: TouchBarPreviewObserver?

    func send() { observer?.previewNeedsDisplay() }
}

enum PreviewClick: Equatable {
    case select, enterGroup, test, ignore

    static func resolve(count: Int, option: Bool, group: Bool) -> Self {
        if option { return count == 1 ? .test : .ignore }
        if count == 2 && group { return .enterGroup }
        return count == 1 ? .select : .ignore
    }
}

enum TouchBarMetrics {
    static let height: CGFloat = 30
    static let itemSpacing: CGFloat = 8       // BasicView and the gaps around its center scroller
    static let stackSpacing: CGFloat = 1      // center scroller, balanced side stacks and Dock
    static let dockIcon: CGFloat = 32
    static let calendarSpacing: CGFloat = 5
    /// Default standard preview magnification: 120% of logical Touch Bar points is treated as 100% standard.
    static let previewBaseScale: CGFloat = 1.2
    @MainActor static let appearance = NSAppearance(named: .init("NSAppearanceNameFunctionRow")) ?? NSAppearance(named: .darkAqua)
}

enum PreviewControlStrip: String, CaseIterable {
    case current = "Current", collapsed = "Collapsed", expanded = "Expanded"
}

enum PreviewZoom: String, CaseIterable, Identifiable {
    case fit = "Fit"
    case x85 = "85%"
    case x100 = "100%"
    case x125 = "125%"
    case x150 = "150%"

    var id: String { rawValue }

    var title: String {
        titleKey.map(L10n.preview) ?? rawValue
    }

    /// English key of the title; percentages are shown as they are.
    var titleKey: String? { self == .fit ? rawValue : nil }

    /// Physical scale factor relative to raw 30-pt Touch Bar points.
    /// `100%` is the default standard size (`1.2×` raw points).
    var fixedScale: CGFloat? {
        switch self {
        case .fit: return nil
        case .x85: return 1.0
        case .x100: return TouchBarMetrics.previewBaseScale
        case .x125: return TouchBarMetrics.previewBaseScale * 1.25
        case .x150: return TouchBarMetrics.previewBaseScale * 1.5
        }
    }

    /// Nominal vertical scale used to size the preview stage smoothly without layout loops.
    var stageScale: CGFloat { fixedScale ?? TouchBarMetrics.previewBaseScale }

    func scale(fitting available: CGFloat, barWidth: CGFloat) -> CGFloat {
        if let fixedScale { return fixedScale }
        return min(TouchBarMetrics.previewBaseScale, max(0, available) / max(1, barWidth))
    }
}

struct PreviewSpaceUsage: Equatable {
    enum Level: Equatable { case normal, tight, overflow }

    let usedWidth: CGFloat
    let availableWidth: CGFloat
    let measured: Bool
    let isOverflowing: Bool
    let isExpandedControlStrip: Bool

    var fillRatio: Double {
        if isExpandedControlStrip { return 1 }
        guard availableWidth > 0 else { return usedWidth > 0 ? 1 : 0 }
        return min(1, max(0, Double(usedWidth / availableWidth)))
    }

    var level: Level {
        if isExpandedControlStrip || isOverflowing || (availableWidth > 0 && usedWidth > availableWidth + 0.5) {
            return .overflow
        }
        if availableWidth > 0 && usedWidth / availableWidth >= 0.88 {
            return .tight
        }
        return .normal
    }

    static func contentWidth(left: CGFloat, center: CGFloat, right: CGFloat) -> CGFloat {
        let gap = TouchBarMetrics.itemSpacing
        let firstGap = left > 0 && (center > 0 || right > 0) ? gap : 0
        let lastGap = right > 0 && center > 0 ? gap : 0
        return ceil(max(0, left) + firstGap + max(0, center) + lastGap + max(0, right))
    }
}

/// All rectangles are logical Touch Bar points. Only the enclosing view scales to the window.
struct TouchBarGeometry {
    static let virtualEscapePanel: CGFloat = 1085
    static let physicalEscapePanel: CGFloat = 1004
    static let escapeWidth: CGFloat = 64
    static let systemGap: CGFloat = 16
    static let collapsedStripWidth: CGFloat = 304
    static let touchIDGap: CGFloat = 16
    static let touchIDWidth: CGFloat = 48

    let width: CGFloat
    let escape, application, controlStrip: CGRect
    let usesMountedWidth: Bool
    let usesMeasuredWidth: Bool
    let hasPhysicalEscape: Bool
    let panelOriginX: CGFloat

    var oledFrame: CGRect {
        CGRect(x: panelOriginX, y: 0, width: max(0, width - panelOriginX), height: TouchBarMetrics.height)
    }

    var touchIDFrame: CGRect {
        guard hasPhysicalEscape else { return .zero }
        return CGRect(x: width + Self.touchIDGap, y: 0, width: Self.touchIDWidth, height: TouchBarMetrics.height)
    }

    var deckWidth: CGFloat {
        hasPhysicalEscape ? width + Self.touchIDGap + Self.touchIDWidth : width
    }

    init(panelWidth: CGFloat?, mounted: CGRect?, mode: PreviewControlStrip, lastCollapsed: CGRect? = nil) {
        let panel = panelWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Self.virtualEscapePanel
        let gap = Self.systemGap
        let escSlot = Self.escapeWidth + gap
        let hasPhysicalEscape = abs(panel - Self.physicalEscapePanel) < 1
        func onPanel(_ rect: CGRect?) -> CGRect? {
            guard let rect else { return nil }
            guard rect.minX.isFinite, rect.width.isFinite, rect.width > 0 else { return nil }
            let clipped = rect.intersection(CGRect(x: 0, y: 0, width: panel, height: TouchBarMetrics.height))
            return clipped.isNull || clipped.isEmpty ? nil : clipped
        }
        let measured = onPanel(mounted)
        let hasCollapsedStrip = measured.map { panel - $0.maxX > gap } ?? false
        let active = mode == .current || (mode == .collapsed && hasCollapsedStrip) ? measured : nil
        usesMountedWidth = active != nil
        let observed = active ?? (mode == .collapsed ? onPanel(lastCollapsed) : nil)
        usesMeasuredWidth = observed != nil
        let leading = observed?.minX ?? (hasPhysicalEscape ? 0 : escSlot)
        // Only the physical Esc key takes space outside the OLED.
        let externalEsc = hasPhysicalEscape ? escSlot : 0
        let appWidth: CGFloat
        if let observed {
            appWidth = observed.width
        } else if mode == .expanded {
            appWidth = 0
        } else {
            appWidth = max(0, panel - leading - gap - Self.collapsedStripWidth)
        }
        self.hasPhysicalEscape = hasPhysicalEscape
        self.panelOriginX = externalEsc
        width = externalEsc + panel
        let h = TouchBarMetrics.height
        escape = CGRect(x: 0, y: 0, width: min(Self.escapeWidth, externalEsc > 0 ? externalEsc : leading), height: h)
        application = CGRect(x: externalEsc + leading, y: 0, width: appWidth, height: h)
        let stripStart = min(width, application.maxX + (mode == .expanded ? 0 : gap))
        controlStrip = CGRect(x: stripStart, y: 0, width: width - stripStart, height: h)
    }
}

/// Used for drafts and simulated widths. Mounted items use their actual AppKit frames instead.
struct PreviewZoneWidths {
    let left, center, right: CGFloat
    let firstGap, lastGap: CGFloat

    init(available: CGFloat, left: CGFloat, center: CGFloat, right: CGFloat, balanced: Bool) {
        let width = max(0, available)
        let gap = TouchBarMetrics.itemSpacing
        // Both hardware layouts insert a center scroller, even when its document is empty.
        firstGap = left > 0 ? min(width, gap) : 0
        lastGap = right > 0 ? min(width - firstGap, gap) : 0
        let room = width - firstGap - lastGap
        // Scroll oversized groups. Keep one visible control in each populated zone when space permits.
        let leftControl = min(left, TouchBarMetrics.dockIcon, room)
        let centerControl = min(center, TouchBarMetrics.height, room - leftControl)
        self.right = min(right, room - leftControl - centerControl)
        self.left = min(left, max(leftControl, room - self.right - center))
        let remaining = room - self.left - self.right
        self.center = balanced ? remaining : min(center, remaining)
    }
}

/// Pure geometry resolver for dragging a preview tile within or across Left / Center / Right zones.
struct PreviewDropSlot: Equatable {
    let id: UUID
    let frame: CGRect
}

struct PreviewDropTarget: Equatable {
    let align: PresetAlign
    let beforeItemID: UUID?
    let indicatorX: CGFloat
    let emptyZoneHighlight: CGRect?
    let isNoOp: Bool
    let constrainedToFixedAlign: Bool
}

enum PreviewDropResolver {
    static func resolve(
        cursorX: CGFloat,
        appWidth: CGFloat,
        draggedID: UUID,
        draggedAlign: PresetAlign,
        hasFixedAlign: Bool,
        leftZone: CGRect,
        centerZone: CGRect,
        rightZone: CGRect,
        leftSlots: [PreviewDropSlot],
        centerSlots: [PreviewDropSlot],
        rightSlots: [PreviewDropSlot]
    ) -> PreviewDropTarget? {
        guard appWidth > 0 else { return nil }
        let x = min(max(0, cursorX), appWidth)

        let resolvedAlign: PresetAlign
        let constrained: Bool
        if hasFixedAlign {
            resolvedAlign = .left
            let natural = pickZone(x: x, appWidth: appWidth, leftZone: leftZone, centerZone: centerZone, rightZone: rightZone,
                                   hasLeft: !leftSlots.isEmpty, hasCenter: !centerSlots.isEmpty, hasRight: !rightSlots.isEmpty)
            constrained = natural != .left
        } else {
            resolvedAlign = pickZone(x: x, appWidth: appWidth, leftZone: leftZone, centerZone: centerZone, rightZone: rightZone,
                                     hasLeft: !leftSlots.isEmpty, hasCenter: !centerSlots.isEmpty, hasRight: !rightSlots.isEmpty)
            constrained = false
        }

        let slots: [PreviewDropSlot]
        switch resolvedAlign {
        case .left: slots = leftSlots
        case .center: slots = centerSlots
        case .right: slots = rightSlots
        }

        if slots.isEmpty {
            let band = emptyBand(for: resolvedAlign, appWidth: appWidth, leftZone: leftZone, centerZone: centerZone, rightZone: rightZone,
                                 hasLeft: !leftSlots.isEmpty, hasCenter: !centerSlots.isEmpty, hasRight: !rightSlots.isEmpty)
            let highlightWidth = min(max(24, band.width - 8), 88)
            let indicatorX: CGFloat
            let highlightRect: CGRect
            switch resolvedAlign {
            case .left:
                indicatorX = max(2, band.minX + 2)
                highlightRect = CGRect(x: band.minX + 2, y: 0, width: min(highlightWidth, max(16, band.width - 4)), height: TouchBarMetrics.height)
            case .center:
                indicatorX = band.midX
                let w = min(highlightWidth, max(16, band.width - 4))
                highlightRect = CGRect(x: band.midX - w / 2, y: 0, width: w, height: TouchBarMetrics.height)
            case .right:
                indicatorX = min(appWidth - 2, band.maxX - 2)
                let w = min(highlightWidth, max(16, band.width - 4))
                highlightRect = CGRect(x: band.maxX - w - 2, y: 0, width: w, height: TouchBarMetrics.height)
            }
            return PreviewDropTarget(
                align: resolvedAlign,
                beforeItemID: nil,
                indicatorX: indicatorX,
                emptyZoneHighlight: highlightRect,
                isNoOp: draggedAlign == resolvedAlign,
                constrainedToFixedAlign: constrained
            )
        }

        let rawIndex = slots.firstIndex { x < $0.frame.midX } ?? slots.count
        let draggedIndex = slots.firstIndex { $0.id == draggedID }
        let isNoOp = draggedAlign == resolvedAlign && draggedIndex.map { rawIndex == $0 || rawIndex == $0 + 1 } == true

        let beforeItemID: UUID? = rawIndex < slots.count ? slots[rawIndex].id : nil
        let indicatorX: CGFloat
        if rawIndex == 0 {
            indicatorX = max(1.5, slots[0].frame.minX - 2)
        } else if rawIndex == slots.count {
            indicatorX = min(appWidth - 1.5, slots[slots.count - 1].frame.maxX + 2)
        } else {
            indicatorX = (slots[rawIndex - 1].frame.maxX + slots[rawIndex].frame.minX) / 2
        }

        return PreviewDropTarget(
            align: resolvedAlign,
            beforeItemID: beforeItemID,
            indicatorX: indicatorX,
            emptyZoneHighlight: nil,
            isNoOp: isNoOp,
            constrainedToFixedAlign: constrained
        )
    }

    private static func pickZone(
        x: CGFloat,
        appWidth: CGFloat,
        leftZone: CGRect,
        centerZone: CGRect,
        rightZone: CGRect,
        hasLeft: Bool,
        hasCenter: Bool,
        hasRight: Bool
    ) -> PresetAlign {
        let l = hasLeft && leftZone.width > 0 ? leftZone : nil
        let c = hasCenter && centerZone.width > 0 ? centerZone : nil
        let r = hasRight && rightZone.width > 0 ? rightZone : nil
        let edgeBand = min(12, appWidth / 3)

        // If all zones are populated, pick nearest/containing zone by boundaries.
        if let l, let c, let r {
            if x <= (l.maxX + c.minX) / 2 { return .left }
            if x >= (c.maxX + r.minX) / 2 { return .right }
            return .center
        }

        // Keep a center target even when the packed side zones leave only a narrow gap.
        if let l, c == nil, let r {
            let gap = r.minX - l.maxX
            let midpoint = (l.maxX + r.minX) / 2
            let halfBand = gap > 0 ? gap / 2 - min(10, gap * 0.2) : min(6, appWidth / 6)
            if x < midpoint - halfBand { return .left }
            if x > midpoint + halfBand { return .right }
            return .center
        }

        // Left & Center populated, Right empty.
        if let l, let c, r == nil {
            if x <= (l.maxX + c.minX) / 2 { return .left }
            let trailing = appWidth - c.maxX
            if trailing >= 24 && x >= c.maxX + min(12, trailing * 0.25) { return .right }
            if x >= appWidth - edgeBand { return .right }
            return .center
        }

        // Center & Right populated, Left empty.
        if l == nil, let c, let r {
            if x >= (c.maxX + r.minX) / 2 { return .right }
            let leading = c.minX
            if leading >= 24 && x <= c.minX - min(12, leading * 0.25) { return .left }
            if x <= edgeBand { return .left }
            return .center
        }

        // Only Left populated.
        if let l, c == nil, r == nil {
            let trailing = appWidth - l.maxX
            if trailing >= 48 {
                if x <= l.maxX + 10 { return .left }
                if x >= appWidth - max(40, trailing * 0.35) { return .right }
                return .center
            }
            if x >= appWidth - edgeBand { return .right }
            return x >= appWidth - 2 * edgeBand ? .center : .left
        }

        // Only Right populated.
        if l == nil, c == nil, let r {
            let leading = r.minX
            if leading >= 48 {
                if x >= r.minX - 10 { return .right }
                if x <= max(40, leading * 0.35) { return .left }
                return .center
            }
            if x <= edgeBand { return .left }
            return x <= 2 * edgeBand ? .center : .right
        }

        // Only Center populated.
        if l == nil, let c, r == nil {
            if x <= max(edgeBand, c.minX - min(12, c.minX * 0.25)) { return .left }
            let trailing = appWidth - c.maxX
            if x >= min(appWidth - edgeBand, c.maxX + min(12, trailing * 0.25)) { return .right }
            return .center
        }

        // Fallback: split bar into thirds.
        if x < appWidth / 3 { return .left }
        if x > appWidth * 2 / 3 { return .right }
        return .center
    }

    private static func emptyBand(
        for align: PresetAlign,
        appWidth: CGFloat,
        leftZone: CGRect,
        centerZone: CGRect,
        rightZone: CGRect,
        hasLeft: Bool,
        hasCenter: Bool,
        hasRight: Bool
    ) -> CGRect {
        let lEnd = hasLeft && leftZone.width > 0 ? leftZone.maxX : 0
        let rStart = hasRight && rightZone.width > 0 ? rightZone.minX : appWidth
        let cMin = hasCenter && centerZone.width > 0 ? centerZone.minX : nil
        let cMax = hasCenter && centerZone.width > 0 ? centerZone.maxX : nil

        switch align {
        case .left:
            let rightEdge = cMin ?? (rStart < appWidth ? rStart : appWidth / 3)
            return CGRect(x: 0, y: 0, width: max(20, rightEdge), height: TouchBarMetrics.height)
        case .center:
            let start = lEnd
            let end = rStart
            return CGRect(x: start, y: 0, width: max(20, end - start), height: TouchBarMetrics.height)
        case .right:
            let leftEdge = cMax ?? (lEnd > 0 ? max(lEnd, appWidth * 2 / 3) : appWidth * 2 / 3)
            return CGRect(x: leftEdge, y: 0, width: max(20, appWidth - leftEdge), height: TouchBarMetrics.height)
        }
    }
}

/// Computes smooth horizontal slide offsets (`dx`) for non-dragged tiles and the opened landing pocket
/// rect in application coordinates so surrounding tiles visibly slide aside to make room during a drag.
struct PreviewZoneSlideResult: Equatable {
    let offsets: [UUID: CGFloat]
    let gapRectInApplication: CGRect?
    let expandLeading: CGFloat
    let expandTrailing: CGFloat
}

enum PreviewSlidePlanner {
    static func plan(
        align: PresetAlign,
        slots: [PreviewDropSlot],
        spacing: CGFloat,
        draggedID: UUID,
        draggedWidth: CGFloat,
        draggedAlign: PresetAlign,
        target: PreviewDropTarget,
        availableLeadingRoom: CGFloat,
        availableTrailingRoom: CGFloat
    ) -> PreviewZoneSlideResult {
        let isSource = align == draggedAlign
        let isTarget = align == target.align

        guard isSource || isTarget else {
            return PreviewZoneSlideResult(offsets: [:], gapRectInApplication: nil, expandLeading: 0, expandTrailing: 0)
        }

        // Same-zone reorder: total width is invariant, so tiles slide smoothly within existing zone bounds.
        if isSource && isTarget {
            guard let draggedIndex = slots.firstIndex(where: { $0.id == draggedID }) else {
                return PreviewZoneSlideResult(offsets: [:], gapRectInApplication: nil, expandLeading: 0, expandTrailing: 0)
            }
            if target.isNoOp {
                return PreviewZoneSlideResult(
                    offsets: [:],
                    gapRectInApplication: slots[draggedIndex].frame,
                    expandLeading: 0,
                    expandTrailing: 0
                )
            }
            let others = slots.filter { $0.id != draggedID }
            let insertIndex = target.beforeItemID.flatMap { bid in others.firstIndex { $0.id == bid } } ?? others.count
            let startX = slots[0].frame.minX
            let (offsets, gapRect) = placeInsertion(in: others, at: insertIndex, from: startX, width: draggedWidth, spacing: spacing)
            return PreviewZoneSlideResult(offsets: offsets, gapRectInApplication: gapRect, expandLeading: 0, expandTrailing: 0)
        }

        // Cross-zone source: remaining tiles close the gap smoothly toward the zone's anchor edge.
        if isSource {
            let others = slots.filter { $0.id != draggedID }
            guard !others.isEmpty, let first = slots.first, let last = slots.last else {
                return PreviewZoneSlideResult(offsets: [:], gapRectInApplication: nil, expandLeading: 0, expandTrailing: 0)
            }
            let packedWidth = others.reduce(CGFloat(0)) { $0 + $1.frame.width } + CGFloat(max(0, others.count - 1)) * spacing
            let startX: CGFloat
            switch align {
            case .left:
                startX = first.frame.minX
            case .right:
                startX = last.frame.maxX - packedWidth
            case .center:
                startX = (first.frame.minX + last.frame.maxX) / 2 - packedWidth / 2
            }
            var x = startX
            var offsets: [UUID: CGFloat] = [:]
            for slot in others {
                offsets[slot.id] = x - slot.frame.minX
                x += slot.frame.width + spacing
            }
            return PreviewZoneSlideResult(offsets: offsets, gapRectInApplication: nil, expandLeading: 0, expandTrailing: 0)
        }

        // Cross-zone target: open a landing pocket of width `draggedWidth` by sliding tiles aside.
        guard !slots.isEmpty, let first = slots.first, let last = slots.last else {
            return PreviewZoneSlideResult(
                offsets: [:],
                gapRectInApplication: target.emptyZoneHighlight,
                expandLeading: 0,
                expandTrailing: 0
            )
        }
        let insertIndex = target.beforeItemID.flatMap { bid in slots.firstIndex { $0.id == bid } } ?? slots.count
        let currentWidth = last.frame.maxX - first.frame.minX
        let totalNewWidth = slots.reduce(CGFloat(0)) { $0 + $1.frame.width } + draggedWidth + CGFloat(slots.count) * spacing
        let extraNeeded = max(0, totalNewWidth - currentWidth)

        let startX: CGFloat
        let expandLeading: CGFloat
        let expandTrailing: CGFloat
        switch align {
        case .left:
            startX = first.frame.minX
            expandLeading = 0
            expandTrailing = min(extraNeeded, max(0, availableTrailingRoom))
        case .right:
            let shiftLeft = min(extraNeeded, max(0, availableLeadingRoom))
            startX = last.frame.maxX - totalNewWidth
            expandLeading = shiftLeft
            expandTrailing = 0
        case .center:
            let half = extraNeeded / 2
            expandLeading = min(half, max(0, availableLeadingRoom))
            expandTrailing = min(half, max(0, availableTrailingRoom))
            startX = (first.frame.minX + last.frame.maxX) / 2 - totalNewWidth / 2
        }

        let (offsets, gapRect) = placeInsertion(in: slots, at: insertIndex, from: startX, width: draggedWidth, spacing: spacing)
        return PreviewZoneSlideResult(
            offsets: offsets,
            gapRectInApplication: gapRect,
            expandLeading: expandLeading,
            expandTrailing: expandTrailing
        )
    }

    private static func placeInsertion(
        in slots: [PreviewDropSlot], at insertIndex: Int, from startX: CGFloat, width: CGFloat, spacing: CGFloat
    ) -> (offsets: [UUID: CGFloat], gap: CGRect) {
        var x = startX
        var gapX: CGFloat?
        var offsets: [UUID: CGFloat] = [:]
        for (index, slot) in slots.enumerated() {
            if index == insertIndex {
                gapX = x
                x += width + spacing
            }
            offsets[slot.id] = x - slot.frame.minX
            x += slot.frame.width + spacing
        }
        return (offsets, CGRect(x: gapX ?? x, y: 0, width: width, height: TouchBarMetrics.height))
    }
}
