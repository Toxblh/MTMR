import AppKit
import Combine

/// AppKit gives each item an intrinsic-sized container. Its enclosing Touch Bar view owns
/// the application's allocation, including any unused space around those containers.
@MainActor struct MountedTouchBarViewport {
    let host: NSView
    let bounds: NSRect
    let panelRect: NSRect

    init?(anchor: NSView?) {
        guard let anchor, let content = anchor.window?.contentView,
              let hostClass = NSClassFromString("NSTouchBarView") else { return nil }
        var ancestor: NSView? = anchor
        while let view = ancestor, !view.isKind(of: hostClass) { ancestor = view.superview }
        guard let host = ancestor, !host.isHiddenOrHasHiddenAncestor else { return nil }
        let rect = host.bounds.intersection(host.visibleRect)
        guard !rect.isEmpty, rect.width.isFinite else { return nil }
        self.host = host
        bounds = rect
        panelRect = NSRect(x: host.convert(rect, to: content).minX, y: 0,
                           width: rect.width, height: TouchBarMetrics.height)
    }

    func frames(of view: NSView?) -> (item: NSRect, visible: NSRect)? {
        guard let view, view.isDescendant(of: host), !view.isHiddenOrHasHiddenAncestor else { return nil }
        func project(_ rect: NSRect) -> NSRect {
            let frame = view.convert(rect, to: host)
            let y = host.isFlipped ? bounds.maxY - frame.maxY : frame.minY - bounds.minY
            return NSRect(x: frame.minX - bounds.minX, y: y, width: frame.width, height: frame.height)
        }
        let visible = view.bounds.intersection(view.visibleRect)
        let clip = NSRect(origin: .zero, size: bounds.size)
        return (project(view.bounds), visible.isEmpty ? .zero : project(visible).intersection(clip))
    }
}

/// Only mounted hardware views are observed, and only while the customizer is displaying them.
@MainActor final class TouchBarLayoutObservation {
    private weak var bar: NSTouchBar?
    private var visibility: AnyCancellable?
    private var geometry: [ObjectIdentifier: [AnyCancellable]] = [:]

    func update(bar: NSTouchBar?, views: [NSView], changed: @escaping () -> Void) {
        if self.bar !== bar {
            self.bar = bar
            visibility = bar?.publisher(for: \.isVisible, options: [.new]).sink { _ in changed() }
        }
        var observed = Set<ObjectIdentifier>()
        for view in views {
            var ancestor: NSView? = view
            while let current = ancestor, observed.insert(ObjectIdentifier(current)).inserted {
                let id = ObjectIdentifier(current)
                if geometry[id] == nil {
                    current.postsFrameChangedNotifications = true
                    current.postsBoundsChangedNotifications = true
                    geometry[id] = [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification].map {
                        NotificationCenter.default.publisher(for: $0, object: current).sink { _ in changed() }
                    }
                }
                ancestor = current.superview
            }
        }
        geometry = geometry.filter { observed.contains($0.key) }
    }

    func disconnect() {
        visibility = nil
        bar = nil
        geometry.removeAll()
    }
}

/// Hardware-framed Touch Bar surface: detached physical Esc / Touch ID keycaps when present,
/// dark OLED glass housing, application region, selection halo overlay, and optional zone guides.
final class TouchBarPreviewSurface: NSView {
    struct ZoneGuideSpec {
        let align: PresetAlign
        let rect: NSRect
        let count: Int
        let overflowing: Bool
    }

    let application = NSView()
    private let oledHousing = OLEDBezelView()
    private let escape = SystemRegion()
    private let controls = SystemRegion()
    private let touchID = TouchIDCapView()
    private let expandedNote = ExpandedStripNoticeView()
    private let selectionHalo = SelectionHaloView()
    private let emptyZoneDrop = EmptyZoneDropView()
    private let dropIndicator = DropIndicatorView()
    private let dragGhost = DragGhostView()
    private let zoneGuides = ZoneGuideStripView()

    private(set) var currentScale: CGFloat = 1

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        appearance = TouchBarMetrics.appearance

        application.wantsLayer = true
        application.layer?.masksToBounds = false

        [oledHousing, escape, application, controls, touchID, expandedNote, emptyZoneDrop, selectionHalo, dropIndicator, dragGhost, zoneGuides].forEach(addSubview)
        emptyZoneDrop.isHidden = true
        dropIndicator.isHidden = true
        dragGhost.isHidden = true
        escape.region = .escape
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func place(in contentRect: NSRect, geometry: TouchBarGeometry, scale: CGFloat, expanded: Bool, showsZones: Bool) {
        currentScale = max(0.25, scale)
        let logicalWidth = geometry.deckWidth
        let barH = TouchBarMetrics.height
        let topPad: CGFloat = 9
        let zoneBlockHeight: CGFloat = showsZones ? 24 : 0
        let bottomPad: CGFloat = 9 + zoneBlockHeight
        let logicalHeight = barH + topPad + bottomPad

        let scaledW = logicalWidth * currentScale
        let scaledH = logicalHeight * currentScale
        frame = NSRect(
            x: round(contentRect.midX - scaledW / 2),
            y: round(contentRect.midY - scaledH / 2),
            width: scaledW,
            height: scaledH
        )
        bounds = NSRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight)

        // Non-flipped AppKit coordinates: y=0 is bottom. Keep OLED bar above the zone guide area.
        let barY = bottomPad

        let oled = geometry.oledFrame.offsetBy(dx: 0, dy: barY)
        oledHousing.frame = oled.insetBy(dx: -3.5, dy: -3.5)
        oledHousing.needsDisplay = true

        let physicalEsc = geometry.panelOriginX > 0
        escape.region = physicalEsc ? .physicalEscape : .escape
        escape.frame = physicalEsc
            ? geometry.escape.offsetBy(dx: 0, dy: barY).insetBy(dx: 0, dy: -2)
            : geometry.escape.offsetBy(dx: 0, dy: barY)
        escape.isHidden = geometry.escape.isEmpty

        controls.region = expanded ? .expanded : .collapsed
        controls.frame = geometry.controlStrip.offsetBy(dx: 0, dy: barY)
        controls.isHidden = geometry.controlStrip.isEmpty

        application.frame = geometry.application.offsetBy(dx: 0, dy: barY)
        application.isHidden = geometry.application.isEmpty

        let touchRect = geometry.touchIDFrame.offsetBy(dx: 0, dy: barY)
        touchID.frame = touchRect.isEmpty ? .zero : touchRect.insetBy(dx: 0, dy: -2)
        touchID.isHidden = touchRect.isEmpty

        expandedNote.isHidden = !expanded
        if expanded {
            expandedNote.frame = controls.frame
        }

        zoneGuides.isHidden = !showsZones || expanded || geometry.application.isEmpty
        if !zoneGuides.isHidden {
            zoneGuides.frame = NSRect(x: application.frame.minX, y: 2, width: application.frame.width, height: 22)
        }
    }

    func updateSelectionHalo(_ rectInApplication: NSRect?) {
        guard let rect = rectInApplication, !rect.isEmpty, !application.isHidden else {
            selectionHalo.isHidden = true
            return
        }
        let projected = rect.offsetBy(dx: application.frame.minX, dy: application.frame.minY)
        selectionHalo.frame = projected.insetBy(dx: -7, dy: -7)
        selectionHalo.isHidden = false
        selectionHalo.needsDisplay = true
    }

    func updateZoneGuides(_ specs: [ZoneGuideSpec]) {
        zoneGuides.specs = specs
    }

    func beginDrag(snapshot: NSImage?, size: NSSize, xInApplication: CGFloat) {
        dragGhost.configure(image: snapshot, tileSize: size)
        positionDragGhost(xInApplication: xInApplication, width: size.width)
        dragGhost.isHidden = false
        selectionHalo.isHidden = true
    }

    func updateDrag(xInApplication: CGFloat, ghostWidth: CGFloat, target: PreviewDropTarget?, landingSlot: NSRect?) {
        positionDragGhost(xInApplication: xInApplication, width: ghostWidth)

        guard let target, !application.isHidden else {
            emptyZoneDrop.isHidden = true
            dropIndicator.isHidden = true
            return
        }

        if let slot = landingSlot, !slot.isEmpty {
            let clampedMinX = max(0, slot.minX)
            let clampedMaxX = min(application.frame.width, slot.maxX)
            if clampedMaxX - clampedMinX >= 8 {
                let projected = NSRect(
                    x: application.frame.minX + clampedMinX,
                    y: application.frame.minY,
                    width: clampedMaxX - clampedMinX,
                    height: TouchBarMetrics.height
                )
                emptyZoneDrop.frame = projected
                emptyZoneDrop.align = target.align
                emptyZoneDrop.showsTitle = target.emptyZoneHighlight != nil
                emptyZoneDrop.isSubtle = target.isNoOp
                emptyZoneDrop.isWarning = target.constrainedToFixedAlign
                emptyZoneDrop.isHidden = false
                emptyZoneDrop.needsDisplay = true
            } else {
                emptyZoneDrop.isHidden = true
            }
        } else {
            emptyZoneDrop.isHidden = true
        }

        // Show crisp vertical indicator only when no spacious landing pocket is visible (e.g. tight overflow).
        if target.isNoOp || (landingSlot != nil && (landingSlot?.width ?? 0) >= 16) {
            dropIndicator.isHidden = true
        } else {
            let x = application.frame.minX + target.indicatorX
            let barY = application.frame.minY
            dropIndicator.isWarning = target.constrainedToFixedAlign
            dropIndicator.frame = NSRect(x: x - 6, y: barY - 6, width: 12, height: TouchBarMetrics.height + 12)
            dropIndicator.isHidden = false
            dropIndicator.needsDisplay = true
        }
    }

    func endDrag() {
        dragGhost.isHidden = true
        dropIndicator.isHidden = true
        emptyZoneDrop.isHidden = true
    }

    private func positionDragGhost(xInApplication: CGFloat, width: CGFloat) {
        let clampedX = min(max(-width * 0.35, xInApplication), application.frame.width - width * 0.65)
        let originX = application.frame.minX + clampedX
        let originY = application.frame.minY + 1.5
        dragGhost.frame = NSRect(x: originX - 4, y: originY - 4, width: width + 8, height: TouchBarMetrics.height + 8)
    }
}

private final class EmptyZoneDropView: NSView {
    var align: PresetAlign = .center
    var showsTitle = true
    var isSubtle = false
    var isWarning = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        if isWarning {
            color = .systemOrange
        } else if isSubtle {
            color = NSColor(calibratedWhite: 0.72, alpha: 1)
        } else {
            switch align {
            case .left: color = NSColor(calibratedRed: 0.35, green: 0.74, blue: 0.98, alpha: 1)
            case .center: color = NSColor(calibratedRed: 0.75, green: 0.52, blue: 0.99, alpha: 1)
            case .right: color = NSColor(calibratedRed: 0.28, green: 0.83, blue: 0.62, alpha: 1)
            }
        }
        let rect = bounds.insetBy(dx: 1, dy: 1.5)
        guard rect.width > 4, rect.height > 4 else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: 4.5, yRadius: 4.5)
        color.withAlphaComponent(isSubtle ? 0.08 : 0.16).setFill()
        path.fill()

        let pattern: [CGFloat] = [3.5, 2.5]
        path.setLineDash(pattern, count: pattern.count, phase: 0)
        color.withAlphaComponent(isSubtle ? 0.42 : 0.80).setStroke()
        path.lineWidth = 1.25
        path.stroke()

        if showsTitle {
            let text = NSAttributedString(string: align.title, attributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: color.withAlphaComponent(0.95),
            ])
            let size = text.size()
            if size.width <= rect.width - 6 {
                text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            }
        }
    }
}

private final class DropIndicatorView: NSView {
    var isWarning = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let color = isWarning ? NSColor.systemOrange : NSColor.controlAccentColor
        let lineX = bounds.midX
        let topY = bounds.maxY - 3.5
        let bottomY = bounds.minY + 3.5

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = color.withAlphaComponent(0.8)
        glow.shadowBlurRadius = 4
        glow.shadowOffset = .zero
        glow.set()

        color.setFill()
        let bar = NSRect(x: lineX - 1.25, y: bottomY, width: 2.5, height: max(2, topY - bottomY))
        NSBezierPath(roundedRect: bar, xRadius: 1.25, yRadius: 1.25).fill()

        let capSize: CGFloat = 5.5
        NSBezierPath(ovalIn: NSRect(x: lineX - capSize / 2, y: topY - capSize / 2, width: capSize, height: capSize)).fill()
        NSBezierPath(ovalIn: NSRect(x: lineX - capSize / 2, y: bottomY - capSize / 2, width: capSize, height: capSize)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class DragGhostView: NSView {
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4.5
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1.5
        imageView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        imageView.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 0.92).cgColor
        addSubview(imageView)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        self.shadow = shadow
        alphaValue = 0.94
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(image: NSImage?, tileSize: NSSize) {
        imageView.image = image
        imageView.frame = NSRect(x: 4, y: 4, width: max(1, tileSize.width), height: max(1, tileSize.height))
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds.insetBy(dx: 4, dy: 4)
    }
}

private final class OLEDBezelView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
        let bezelPath = NSBezierPath(roundedRect: outer, xRadius: 7, yRadius: 7)
        NSColor(calibratedWhite: 0.02, alpha: 1).setFill()
        bezelPath.fill()

        // Inner pure black OLED surface
        let inner = bounds.insetBy(dx: 3, dy: 3)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: inner, xRadius: 4.5, yRadius: 4.5).fill()

        // Subtle glass rim highlight
        NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
        bezelPath.lineWidth = 1
        bezelPath.stroke()
    }
}

private final class TouchIDCapView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let cap = bounds.insetBy(dx: 0.5, dy: 0.5)
        guard cap.width > 4, cap.height > 4 else { return }
        // Matte dark sapphire rectangular key matching Touch Bar MacBook Pro hardware (no circular ring).
        let outer = NSBezierPath(roundedRect: cap, xRadius: 5, yRadius: 5)
        if let gradient = NSGradient(starting: NSColor(calibratedWhite: 0.145, alpha: 1),
                                     ending: NSColor(calibratedWhite: 0.095, alpha: 1)) {
            gradient.draw(in: outer, angle: -90)
        }
        NSColor(calibratedWhite: 1, alpha: 0.11).setStroke()
        outer.lineWidth = 1
        outer.stroke()

        // Subtle recessed matte sapphire inner border.
        let inner = cap.insetBy(dx: 2.5, dy: 2.5)
        if inner.width > 4, inner.height > 4 {
            let sensor = NSBezierPath(roundedRect: inner, xRadius: 3, yRadius: 3)
            NSColor(calibratedWhite: 0.06, alpha: 0.55).setFill()
            sensor.fill()
            NSColor(calibratedWhite: 1, alpha: 0.06).setStroke()
            sensor.lineWidth = 0.75
            sensor.stroke()
        }
    }
}

private final class SelectionHaloView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let strokeRect = bounds.insetBy(dx: 6, dy: 6)
        guard strokeRect.width > 1, strokeRect.height > 1 else { return }

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = accent.withAlphaComponent(0.65)
        glow.shadowBlurRadius = 5
        glow.shadowOffset = .zero
        glow.set()

        let path = NSBezierPath(roundedRect: strokeRect, xRadius: 5.5, yRadius: 5.5)
        accent.setStroke()
        path.lineWidth = 2
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class ExpandedStripNoticeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let message = L10n.preview("Expanded Control Strip covers MTMR")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 0.99, green: 0.78, blue: 0.25, alpha: 1),
        ]
        let text = NSAttributedString(string: message, attributes: attributes)
        let size = text.size()
        let pillWidth = min(bounds.width - 12, size.width + 18)
        let pillHeight: CGFloat = 22
        guard pillWidth > 32 else { return }
        let pill = NSRect(x: bounds.midX - pillWidth / 2, y: bounds.midY - pillHeight / 2, width: pillWidth, height: pillHeight)
        NSColor(calibratedWhite: 0.08, alpha: 0.88).setFill()
        let path = NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5)
        path.fill()
        NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.14, alpha: 0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        text.draw(in: NSRect(x: pill.minX + 9, y: pill.midY - size.height / 2, width: pill.width - 18, height: size.height))
    }
}

private final class ZoneGuideStripView: NSView {
    var specs: [TouchBarPreviewSurface.ZoneGuideSpec] = [] {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        for spec in specs where spec.rect.width >= 6 {
            let color: NSColor
            switch spec.align {
            case .left: color = NSColor(calibratedRed: 0.35, green: 0.74, blue: 0.98, alpha: 1)
            case .center: color = NSColor(calibratedRed: 0.75, green: 0.52, blue: 0.99, alpha: 1)
            case .right: color = NSColor(calibratedRed: 0.28, green: 0.83, blue: 0.62, alpha: 1)
            }
            let x = max(0, spec.rect.minX)
            let w = min(bounds.width - x, spec.rect.width)
            guard w >= 4 else { continue }

            // Crisp 2pt top rail
            let rail = NSRect(x: x, y: bounds.height - 3, width: w, height: 2)
            color.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: rail, xRadius: 1, yRadius: 1).fill()

            // Compact label when wide enough
            let title: String
            if spec.overflowing {
                title = String(format: L10n.preview("%@ · %ld (scrolls)"), spec.align.title, spec.count)
            } else {
                title = String(format: L10n.preview("%@ · %ld"), spec.align.title, spec.count)
            }
            let shortTitle = spec.align.title
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: color.withAlphaComponent(0.92),
            ]
            let full = NSAttributedString(string: title, attributes: attrs)
            let compact = NSAttributedString(string: shortTitle, attributes: attrs)
            let chosen: NSAttributedString?
            if full.size().width <= w - 4 {
                chosen = full
            } else if compact.size().width <= w - 4 {
                chosen = compact
            } else {
                chosen = nil
            }
            if let chosen {
                let sz = chosen.size()
                chosen.draw(at: NSPoint(x: x + (w - sz.width) / 2, y: 1.5))
            }
        }
    }
}

private final class SystemRegion: NSView {
    enum Region { case escape, physicalEscape, collapsed, expanded }
    var region: Region = .collapsed {
        didSet { if oldValue != region { needsDisplay = true } }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? {
        switch region {
        case .escape, .physicalEscape:
            return L10n.preview("System Escape key")
        case .collapsed:
            return L10n.preview("Collapsed system Control Strip")
        case .expanded:
            return L10n.preview("Expanded system Control Strip")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if region == .physicalEscape {
            let cap = bounds.insetBy(dx: 0.5, dy: 0.5)
            guard cap.width > 0 else { return }
            let path = NSBezierPath(roundedRect: cap, xRadius: 5, yRadius: 5)
            if let gradient = NSGradient(starting: NSColor(calibratedWhite: 0.21, alpha: 1),
                                         ending: NSColor(calibratedWhite: 0.14, alpha: 1)) {
                gradient.draw(in: path, angle: -90)
            }
            NSColor(calibratedWhite: 1, alpha: 0.13).setStroke()
            path.lineWidth = 1
            path.stroke()
            let text = NSAttributedString(string: "esc", attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1),
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: cap.midX - size.width / 2, y: cap.midY - size.height / 2))
            return
        }

        let ink = NSColor(white: 0.57, alpha: 1)
        let fill = NSColor(white: 0.14, alpha: 1)
        let pill = bounds.insetBy(dx: 1, dy: 1)
        guard pill.width > 0 else { return }
        fill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
        if region == .escape {
            let text = NSAttributedString(string: "esc", attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: ink])
            let size = text.size()
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
            return
        }
        let symbols = region == .expanded
            ? ["xmark", "sun.min", "sun.max", "rectangle.3.group", "light.min", "light.max", "backward.fill", "playpause.fill", "forward.fill", "speaker.slash", "speaker.wave.1", "speaker.wave.3"]
            : ["chevron.left", "sun.max", "speaker.wave.2", "speaker.slash", "mic"]
        let count = min(symbols.count, max(1, Int(bounds.width / 22)))
        let segment = bounds.width / CGFloat(count)
        for (index, symbol) in symbols.prefix(count).enumerated() {
            let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [ink]))
            guard let icon else { continue }
            let scale = min(16 / max(1, icon.size.width), 16 / max(1, icon.size.height))
            let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
            icon.draw(in: NSRect(x: (CGFloat(index) + 0.5) * segment - size.width / 2,
                                 y: bounds.midY - size.height / 2, width: size.width, height: size.height))
        }
    }
}
