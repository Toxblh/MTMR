import AppKit
import QuartzCore

enum PreviewItemStatus: Equatable {
    case live
    case hiddenEmptyOutput
    case conditionalHidden(String)
    case draft

    var isHiddenByRuntime: Bool {
        switch self {
        case .hiddenEmptyOutput, .conditionalHidden: return true
        case .live, .draft: return false
        }
    }

    var isDraft: Bool { self == .draft }
}

/// Preserves the last rendered appearance of a live item so editing a property or reordering
/// siblings does not collapse sliders, widgets or docks into generic 28-pt placeholders.
struct PreviewItemSnapshot {
    let width: CGFloat
    let title: String?
    let image: NSImage?
    let sliderValue: Double?
    let picture: NSImage?
}

enum PreviewContextAction {
    case test(NSTouchBarItem?, NSPoint)
    case enterGroup
    case duplicate
    case moveTo(PresetAlign)
    case setBordered(Bool)
    case delete
}

enum PreviewDragEvent {
    case began(windowPoint: NSPoint, grabOffsetX: CGFloat)
    case moved(windowPoint: NSPoint)
    case ended(windowPoint: NSPoint)
    case cancelled
}

/// A display-only copy. All its live data comes from the single widget that owns the hardware view.
final class LivePreviewItemView: NSView, TouchBarPreviewObserver {
    let item: PresetItem
    private(set) var source: NSTouchBarItem?
    private(set) var status: PreviewItemStatus = .draft
    private(set) var preferredWidth: CGFloat = 0
    var widthDidChange: (() -> Void)?
    var onClick: ((PreviewClick, NSTouchBarItem?, NSPoint) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onContextAction: ((PreviewContextAction) -> Void)?
    var onDragEvent: ((PreviewDragEvent) -> Void)?
    var canMoveZone = true

    var isDragged = false {
        didSet {
            guard oldValue != isDragged else { return }
            alphaValue = isDragged ? 0.0 : 1.0
            updateOverlays()
        }
    }

    private var currentSlideOffset: CGFloat = 0

    func setDragSlideOffset(_ dx: CGFloat, animated: Bool) {
        guard abs(currentSlideOffset - dx) > 0.25 else { return }
        currentSlideOffset = dx
        let target = dx == 0 ? CATransform3DIdentity : CATransform3DMakeTranslation(dx, 0, 0)
        guard let layer else { return }
        if animated {
            let from = layer.presentation()?.transform ?? layer.transform
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = target
            CATransaction.commit()

            let anim = CABasicAnimation(keyPath: "transform")
            anim.fromValue = NSValue(caTransform3D: from)
            anim.toValue = NSValue(caTransform3D: target)
            anim.duration = 0.18
            anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            layer.add(anim, forKey: "dragSlide")
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "dragSlide")
            layer.transform = target
            CATransaction.commit()
        }
    }

    var showWhenHidden = false {
        didSet {
            if oldValue != showWhenHidden {
                refresh()
            }
        }
    }

    var selected = false {
        didSet {
            guard oldValue != selected else { return }
            setAccessibilitySelected(selected)
            updateOverlays()
            if status.isHiddenByRuntime { refresh() }
        }
    }

    private var hovered = false {
        didSet {
            guard oldValue != hovered else { return }
            updateOverlays()
            onHoverChanged?(hovered)
        }
    }

    private let fallbackSnapshot: PreviewItemSnapshot?
    private let savedMatchAppId: String?
    private weak var pressedTarget: NSTouchBarItem?
    private var pressedWithOption = false
    private var mouseDownWindowPoint: NSPoint = .zero
    private var mouseDownLocalX: CGFloat = 0
    private var isDragging = false
    private var didPushDragCursor = false

    private let faces = NSView()
    private var scroller: NSScrollView?
    private var buttons: [CustomHeightButton] = []
    private var targets: [CustomButtonTouchBarItem] = []
    private var indicators: [NSView] = []
    private var slider: CustomSlider?
    private var picture: NSImageView?
    private var updateQueued = false
    private var connected = true
    private var trackingAreaRef: NSTrackingArea?
    private var placeholderOutline: CAShapeLayer?
    private var draftDotLayer: CALayer?
    private var hoverLayer: CALayer?
    private var testFlashLayer: CALayer?
    private var scrollObserver: NSObjectProtocol?
    private var pendingScrollOffset: CGFloat?

    var hardwareViews: [NSView] {
        guard let view = source?.view else { return [] }
        return scroller == nil ? [view] : [view] + targets.map { $0.view }
    }

    var isSliderType: Bool {
        item.type == "volume" || item.type == "brightness"
    }

    init(item: PresetItem, source: NSTouchBarItem?, isConditionalHidden: Bool = false, fallback: PreviewItemSnapshot? = nil) {
        self.item = item
        self.source = source
        self.fallbackSnapshot = fallback
        self.savedMatchAppId = isConditionalHidden ? item.matchAppIdPattern : nil

        super.init(frame: .zero)
        appearance = TouchBarMetrics.appearance
        wantsLayer = true
        faces.wantsLayer = true
        // Match the physical Touch Bar's unclipped NSStackView cells so scaleNone icons
        // (e.g. 24x24 custom images in a narrower fixed-width button) are not sliced off.
        layer?.masksToBounds = false
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.listTitle)
        setAccessibilityChildren([])

        setupOverlayLayers()

        if source is AppScrubberTouchBarItem || source is UpNextScrubberTouchBarItem {
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.documentView = faces
            addSubview(scroll)
            scroller = scroll
            if let clip = (source?.view as? NSScrollView)?.contentView {
                clip.postsBoundsChangedNotifications = true
                pendingScrollOffset = clip.bounds.minX
                scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                         object: clip, queue: .main) { [weak self, weak clip] _ in
                    guard let self, let clip else { return }
                    self.pendingScrollOffset = clip.bounds.minX
                    self.needsLayout = true
                }
            }
        } else {
            addSubview(faces)
        }
        (source as? TouchBarPreviewSource)?.previewChanges.observer = self
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
    }

    func disconnect() {
        cancelDragIfActive()
        connected = false
        if hovered {
            hovered = false
        }
        if let changes = (source as? TouchBarPreviewSource)?.previewChanges, changes.observer === self {
            changes.observer = nil
        }
        source = nil
        if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        scrollObserver = nil
        targets.removeAll()
        widthDidChange = nil
        onClick = nil
        onHoverChanged = nil
        onContextAction = nil
        onDragEvent = nil
    }

    func cancelDragIfActive() {
        guard isDragging else { return }
        isDragging = false
        isDragged = false
        popDragCursorIfNeeded()
        onDragEvent?(.cancelled)
    }

    func dragSnapshot() -> NSImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let previousAlpha = alphaValue
        let wasHoverHidden = hoverLayer?.isHidden ?? true
        alphaValue = 1
        hoverLayer?.isHidden = true
        defer {
            alphaValue = previousAlpha
            hoverLayer?.isHidden = wasHoverHidden
        }
        layoutSubtreeIfNeeded()
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func popDragCursorIfNeeded() {
        if didPushDragCursor {
            didPushDragCursor = false
            NSCursor.pop()
        }
    }

    func captureSnapshot() -> PreviewItemSnapshot? {
        guard preferredWidth > 0 else { return fallbackSnapshot }
        let title: String?
        let image: NSImage?
        if let button = source as? CustomButtonTouchBarItem {
            title = button.title.isEmpty ? nil : button.title
            image = button.image
        } else if let group = source as? GroupBarItem {
            title = group.collapsedRepresentationLabel.isEmpty ? nil : group.collapsedRepresentationLabel
            image = group.collapsedRepresentationImage
        } else {
            title = fallbackSnapshot?.title
            image = fallbackSnapshot?.image
        }
        return PreviewItemSnapshot(
            width: preferredWidth,
            title: title,
            image: image,
            sliderValue: slider?.doubleValue ?? fallbackSnapshot?.sliderValue,
            picture: picture?.image ?? fallbackSnapshot?.picture
        )
    }

    func flashTestFeedback() {
        guard let flash = testFlashLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flash.opacity = 1
        CATransaction.commit()

        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.0
        anim.duration = 0.24
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flash.opacity = 0
        flash.add(anim, forKey: "testFlash")
    }

    func previewNeedsDisplay() {
        guard connected, !updateQueued else { return }
        if source is CodexTodayBarItem, window == nil || visibleRect.isEmpty { return }
        updateQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.connected else { return }
            self.updateQueued = false
            self.refresh()
        }
    }

    private func setupOverlayLayers() {
        let outline = CAShapeLayer()
        outline.fillColor = nil
        outline.lineDashPattern = [3, 3]
        outline.lineWidth = 1
        outline.zPosition = 2
        outline.isHidden = true
        layer?.addSublayer(outline)
        placeholderOutline = outline

        let hover = CALayer()
        hover.cornerRadius = 4
        hover.backgroundColor = NSColor.white.withAlphaComponent(0.13).cgColor
        hover.borderWidth = 1
        hover.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        hover.zPosition = 3
        hover.isHidden = true
        layer?.addSublayer(hover)
        hoverLayer = hover

        let flash = CALayer()
        flash.cornerRadius = 4
        flash.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.28).cgColor
        flash.borderWidth = 1.5
        flash.borderColor = NSColor.systemGreen.cgColor
        flash.zPosition = 4
        flash.opacity = 0
        layer?.addSublayer(flash)
        testFlashLayer = flash

        let dot = CALayer()
        dot.backgroundColor = NSColor.systemOrange.cgColor
        dot.borderColor = NSColor.black.cgColor
        dot.borderWidth = 1
        dot.cornerRadius = 3
        dot.zPosition = 5
        dot.isHidden = true
        layer?.addSublayer(dot)
        draftDotLayer = dot
    }

    private func refreshStatusAndTooltip() {
        if let button = source as? CustomButtonTouchBarItem, button.hidesEmptyOutput {
            status = .hiddenEmptyOutput
        } else if source != nil {
            status = .live
        } else if let pattern = savedMatchAppId {
            status = .conditionalHidden(pattern)
        } else {
            status = .draft
        }

        switch status {
        case .draft:
            toolTip = String(format: L10n.preview("%@ — draft preview. Save edits (⌘S) to apply to the Touch Bar."), item.listTitle)
        case .hiddenEmptyOutput:
            toolTip = String(format: L10n.preview("%@ — hidden on the Touch Bar because its output is empty."), item.listTitle)
        case let .conditionalHidden(pattern):
            toolTip = String(format: L10n.preview("%@ — shown only when the frontmost app matches “%@”."), item.listTitle, pattern)
        case .live:
            if item.children != nil {
                toolTip = String(format: L10n.preview("%@ — double-click to edit contents, Option-click to test"), item.listTitle)
            } else {
                toolTip = String(format: L10n.preview("%@ — click to select, Option-click to test"), item.listTitle)
            }
        }
        setAccessibilityHelp(toolTip)
    }

    private func updateOverlays() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hoverLayer?.isHidden = !hovered || isDragged
        let isGhost = status.isHiddenByRuntime
        faces.alphaValue = isGhost ? 0.56 : 1.0
        draftDotLayer?.isHidden = !status.isDraft || isDragged
        if status.isDraft {
            placeholderOutline?.strokeColor = NSColor.systemOrange.withAlphaComponent(0.75).cgColor
            placeholderOutline?.isHidden = selected || isDragged
        } else if isGhost {
            placeholderOutline?.strokeColor = NSColor.white.withAlphaComponent(0.38).cgColor
            placeholderOutline?.isHidden = selected || isDragged
        } else {
            placeholderOutline?.isHidden = true
        }
        CATransaction.commit()
    }

    private func refresh() {
        refreshStatusAndTooltip()
        let shouldShowGhost = showWhenHidden || selected

        let contentWidth: CGFloat
        switch status {
        case .hiddenEmptyOutput:
            if shouldShowGhost {
                let image = item.resolvedImage ?? (source as? CustomButtonTouchBarItem)?.image ?? NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil)
                contentWidth = showGhostLabel(title: item.configuredTitle ?? item.typeDisplayName, image: image)
            } else {
                contentWidth = 0
            }
        case .conditionalHidden:
            if shouldShowGhost {
                let image = item.resolvedImage ?? NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil)
                contentWidth = showGhostLabel(title: item.configuredTitle ?? item.typeDisplayName, image: image)
            } else {
                contentWidth = 0
            }
        case .live:
            switch source {
            case let button as CustomButtonTouchBarItem:
                contentWidth = showButtons([button], spacing: 0)
            case let dock as AppScrubberTouchBarItem:
                contentWidth = showButtons(dock.items, spacing: TouchBarMetrics.stackSpacing)
            case let calendar as UpNextScrubberTouchBarItem:
                contentWidth = showButtons(calendar.previewButtons, spacing: TouchBarMetrics.calendarSpacing)
            case let group as GroupBarItem:
                contentWidth = showLabel(title: group.collapsedRepresentationLabel, image: group.collapsedRepresentationImage, bordered: true, backgroundColor: nil)
            case let widget? where widget.view is CustomSlider:
                contentWidth = showSlider(widget.view as! CustomSlider)
            case let widget?:
                contentWidth = showPicture(of: widget.view)
            case nil:
                contentWidth = showDraft()
            }
        case .draft:
            contentWidth = showDraft()
        }

        faces.setFrameSize(NSSize(width: contentWidth, height: TouchBarMetrics.height))

        let nextWidth: CGFloat
        if status.isHiddenByRuntime && !shouldShowGhost {
            nextWidth = 0
        } else {
            let configured = item.json["width"]?.doubleValue.map { CGFloat($0) }
            let hardwareWidth = source?.view?.constraints.first {
                $0.isActive && $0.firstItem === source?.view && $0.firstAttribute == .width &&
                $0.secondItem == nil && $0.relation == .equal && $0.constant > 0
            }?.constant
            let width: CGFloat
            if status.isHiddenByRuntime {
                width = configured.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? contentWidth
            } else {
                width = [configured, hardwareWidth].compactMap { $0 }.first { $0.isFinite && $0 > 0 } ?? contentWidth
            }
            nextWidth = ceil(max(1, width))
        }

        updateOverlays()
        if nextWidth != preferredWidth {
            preferredWidth = nextWidth
            widthDidChange?()
        }
        needsLayout = true
    }

    // MARK: - Draft Fidelity Rendering

    private func resetFacesIfNeeded(keeping keep: NSView?) {
        for subview in faces.subviews where subview !== keep {
            subview.removeFromSuperview()
        }
        if keep !== slider { slider = nil }
        if keep !== picture { picture = nil }
        if keep == nil || !(keep is CustomHeightButton) {
            buttons.removeAll()
            targets.removeAll()
            indicators.removeAll()
        }
    }

    private func showDraft() -> CGFloat {
        // Sliders keep a genuine CustomSlider look instead of collapsing to a small icon.
        if isSliderType {
            return showDraftSlider()
        }
        if item.type == "dock" {
            return showDraftDock()
        }
        if item.type == "upnext" {
            return showDraftUpNext()
        }
        if (item.type == "codexToday" || item.type == "codexQuota"), let cached = fallbackSnapshot?.picture {
            return showCachedPicture(cached, width: fallbackSnapshot?.width ?? (item.type == "codexToday" ? 160 : 90))
        }

        let background = item.json["background"]?.stringValue?.hexColor
        let bordered = PresetItem.showsBorder(in: item.json)
        // Without an "image", show the default icon the built-in type draws on the Touch Bar.
        let customImage = item.resolvedImage ?? item.previewImage
        let (title, image, minWidth) = draftTitleAndImage(customImage: customImage)
        let width = showLabel(title: title, image: image, bordered: bordered, backgroundColor: background)
        return max(minWidth, width)
    }

    private func draftTitleAndImage(customImage: NSImage?) -> (String, NSImage?, CGFloat) {
        let configuredTitle = item.configuredTitle
        let fallbackTitle = (item.type == "staticButton" || item.type == "group") ? nil : fallbackSnapshot?.title
        let symbol = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil)

        switch item.type {
        case "escape":
            return (configuredTitle ?? "esc", customImage, 64)
        case "exitTouchbar":
            return (configuredTitle ?? "exit", customImage, 44)
        case "timeButton":
            return (configuredTitle ?? formattedClockSample(), customImage, 44)
        case "battery":
            return (configuredTitle ?? fallbackTitle ?? "85%", customImage ?? NSImage(systemSymbolName: "battery.75", accessibilityDescription: nil), 54)
        case "cpu":
            return (configuredTitle ?? fallbackTitle ?? "18%", customImage ?? symbol, 52)
        case "weather", "yandexWeather":
            return (configuredTitle ?? fallbackTitle ?? "21°", customImage ?? NSImage(systemSymbolName: "cloud.sun.fill", accessibilityDescription: nil), 56)
        case "currency":
            let from = item.json["from"]?.stringValue ?? "BTC"
            return (configuredTitle ?? fallbackTitle ?? "\(from) 1.00", customImage, 68)
        case "pomodoro":
            let fallback = PomodoroDuration.defaultWork
            let seconds = PomodoroDuration.seconds(item.json["workTime"]?.doubleValue ?? Double(fallback), fallback: fallback)
            let sample = PomodoroDuration.display(seconds)
            return (configuredTitle ?? fallbackTitle ?? sample, customImage ?? symbol, 66)
        case "network":
            return (configuredTitle ?? fallbackTitle ?? "↓ 8.4M", customImage ?? symbol, 64)
        case "inputsource":
            return (configuredTitle ?? fallbackTitle ?? "ABC", customImage, 42)
        case "music":
            return (configuredTitle ?? fallbackTitle ?? item.typeDisplayName, customImage ?? symbol, 88)
        case "codexToday":
            return (configuredTitle ?? fallbackTitle ?? "Codex", customImage ?? symbol, 120)
        case "codexQuota":
            return (configuredTitle ?? fallbackTitle ?? "Quota", customImage ?? symbol, 80)
        case "group":
            if item.isIconGroup { return ("", customImage ?? symbol, 32) }
            return (configuredTitle ?? item.listTitle, customImage ?? symbol, 48)
        case "appleScriptTitledButton", "shellScriptTitledButton":
            let label = configuredTitle ?? fallbackTitle ?? (customImage == nil ? item.typeDisplayName : "")
            return (label, customImage ?? (label.isEmpty ? symbol : nil), 36)
        case "staticButton":
            let label = configuredTitle ?? ""
            return (label, customImage ?? (label.isEmpty ? symbol : nil), 28)
        default:
            // Built-in icon buttons (brightnessDown, volumeUp, play, dnd, etc.)
            let image = customImage ?? fallbackSnapshot?.image ?? symbol
            return (configuredTitle ?? fallbackTitle ?? "", image, 28)
        }
    }

    private func formattedClockSample() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = item.json["formatTemplate"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? "HH:mm"
        if let localeID = item.json["locale"]?.stringValue, !localeID.isEmpty {
            formatter.locale = Locale(identifier: localeID)
        }
        if let tzName = item.json["timeZone"]?.stringValue, !tzName.isEmpty {
            formatter.timeZone = TimeZone(identifier: tzName) ?? TimeZone(abbreviation: tzName)
        }
        return formatter.string(from: Date())
    }

    private func showDraftSlider() -> CGFloat {
        if slider == nil {
            resetFacesIfNeeded(keeping: nil)
            let knob = item.resolvedImage
            let mirror = knob.map(CustomSlider.init(knob:)) ?? CustomSlider()
            mirror.minValue = 0
            mirror.maxValue = 100
            mirror.doubleValue = fallbackSnapshot?.sliderValue ?? 60
            slider = mirror
            faces.addSubview(mirror)
        }
        let defaultWidth: CGFloat = 100
        if let prev = fallbackSnapshot?.width, prev >= 60 { return prev }
        return defaultWidth
    }

    private func showDraftDock() -> CGFloat {
        resetFacesIfNeeded(keeping: nil)
        let symbols = ["macwindow", "safari", "terminal", "folder"]
        var x: CGFloat = 0
        for name in symbols {
            let button = CustomHeightButton(title: "", target: nil, action: nil)
            button.isBordered = false
            button.bezelStyle = .inline
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            button.contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.focusRingType = .none
            button.frame = NSRect(x: x, y: 0, width: TouchBarMetrics.dockIcon, height: TouchBarMetrics.height)
            faces.addSubview(button)
            buttons.append(button)
            x += TouchBarMetrics.dockIcon + TouchBarMetrics.stackSpacing
        }
        let natural = max(0, x - TouchBarMetrics.stackSpacing)
        return max(natural, fallbackSnapshot?.width ?? natural)
    }

    private func showDraftUpNext() -> CGFloat {
        let icon = item.resolvedImage ?? NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
        let text = item.configuredTitle ?? fallbackSnapshot?.title ?? L10n.preview("14:00 · Event")
        let width = showLabel(title: text, image: icon, bordered: true, backgroundColor: item.json["background"]?.stringValue?.hexColor)
        return max(108, fallbackSnapshot?.width ?? width)
    }

    private func showCachedPicture(_ image: NSImage, width: CGFloat) -> CGFloat {
        resetFacesIfNeeded(keeping: picture)
        if picture == nil {
            let mirror = NSImageView()
            mirror.imageScaling = .scaleAxesIndependently
            faces.addSubview(mirror)
            picture = mirror
        }
        picture?.image = image
        return max(48, width)
    }

    private func showGhostLabel(title: String, image: NSImage?) -> CGFloat {
        let width = showLabel(title: title, image: image, bordered: false, backgroundColor: nil)
        return min(140, max(36, width))
    }

    private func showLabel(title: String, image: NSImage?, bordered: Bool, backgroundColor: NSColor?) -> CGFloat {
        let existing = buttons.count == 1 ? buttons.first : nil
        resetFacesIfNeeded(keeping: existing)
        targets.removeAll()
        indicators.removeAll()
        let button = existing ?? CustomHeightButton(title: title, target: nil, action: nil)
        let effectiveBordered = backgroundColor != nil || bordered
        button.isBordered = effectiveBordered
        button.bezelStyle = effectiveBordered ? .rounded : .inline
        button.bezelColor = backgroundColor
        button.attributedTitle = title.defaultTouchbarAttributedString
        button.image = image
        button.contentTintColor = .white
        button.imagePosition = title.isEmpty ? .imageOnly : (image == nil ? .noImage : .imageLeading)
        button.imageScaling = .scaleProportionallyDown
        button.lineBreakMode = .byTruncatingTail
        button.focusRingType = .none
        if button.superview == nil { faces.addSubview(button) }
        buttons = [button]
        return min(180, max(28, button.intrinsicContentSize.width))
    }

    private func showButtons(_ items: [CustomButtonTouchBarItem], spacing: CGFloat) -> CGFloat {
        if targets.map(ObjectIdentifier.init) != items.map(ObjectIdentifier.init) {
            faces.subviews.forEach { $0.removeFromSuperview() }
            slider = nil
            picture = nil
            targets = items
            indicators = []
            buttons = items.map { item in
                let button = CustomHeightButton(title: "", target: nil, action: nil)
                button.focusRingType = .none
                faces.addSubview(button)
                if item is DockBarItem {
                    let dot = NSView()
                    dot.wantsLayer = true
                    dot.layer?.cornerRadius = 1.5
                    button.addSubview(dot)
                    indicators.append(dot)
                }
                return button
            }
        }

        var x: CGFloat = 0
        for (index, item) in items.enumerated() {
            let button = buttons[index]
            item.applyAppearance(to: button)
            button.frame = NSRect(x: x, y: 0, width: max(1, button.intrinsicContentSize.width), height: TouchBarMetrics.height)
            if let dock = item as? DockBarItem {
                let dot = indicators[index]
                dot.frame = dock.dotView.frame
                dot.layer?.backgroundColor = dock.dotView.layer?.backgroundColor
            }
            x = button.frame.maxX + spacing
        }
        return synchronizeMountedButtons() ?? max(0, x - spacing)
    }

    /// AppKit can mount or resize the native Dock after the tile subscribed to its data.
    /// Use its laid-out subviews (including alignment insets) whenever they are available.
    @discardableResult func synchronizeMountedButtons() -> CGFloat? {
        guard let stack = (source?.view as? NSScrollView)?.documentView as? NSStackView,
              stack.window != nil, stack.bounds.width > 0 else { return nil }
        for (target, mirror) in zip(targets, buttons) where target.view.isDescendant(of: stack) {
            let rect = target.view.convert(target.view.bounds, to: stack)
            if mirror.frame != rect { mirror.frame = rect }
        }
        let size = NSSize(width: stack.bounds.width, height: TouchBarMetrics.height)
        if faces.frame.size != size { faces.setFrameSize(size) }
        return size.width
    }

    private func showSlider(_ actual: CustomSlider) -> CGFloat {
        if slider == nil {
            resetFacesIfNeeded(keeping: nil)
            let knob = (actual.cell as? CustomSliderCell)?.knobImage
            let mirror = knob.map(CustomSlider.init(knob:)) ?? CustomSlider()
            mirror.minValue = actual.minValue
            mirror.maxValue = actual.maxValue
            slider = mirror
            faces.addSubview(mirror)
        }
        slider?.doubleValue = actual.doubleValue
        return actual.bounds.width > 0 ? actual.bounds.width : 100
    }

    private func showPicture(of view: NSView?) -> CGFloat {
        guard let view, view.bounds.width > 0, view.bounds.height > 0 else { return 0 }
        view.layoutSubtreeIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(bitmap)
            resetFacesIfNeeded(keeping: picture)
            if picture == nil {
                let mirror = NSImageView()
                mirror.imageScaling = .scaleAxesIndependently
                faces.addSubview(mirror)
                picture = mirror
            }
            picture?.image = image
        }
        return view.bounds.width
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        placeholderOutline?.path = CGPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 4, cornerHeight: 4, transform: nil)
        hoverLayer?.frame = bounds
        testFlashLayer?.frame = bounds
        draftDotLayer?.frame = NSRect(x: max(0, bounds.maxX - 5), y: max(0, bounds.maxY - 5), width: 6, height: 6)
        CATransaction.commit()

        if let scroller {
            scroller.frame = bounds
            if let x = pendingScrollOffset, scroller.contentSize.width > 0 {
                scrollToHardwareOffset(x)
                pendingScrollOffset = nil
            }
        } else {
            faces.frame = bounds
            if buttons.count == 1 {
                buttons.first?.frame = faces.bounds
            }
            slider?.frame = faces.bounds
            picture?.frame = faces.bounds
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
    }

    private func scrollToHardwareOffset(_ x: CGFloat) {
        guard let scroller else { return }
        let offset = min(max(0, x), max(0, faces.frame.width - scroller.contentSize.width))
        scroller.contentView.scroll(to: NSPoint(x: offset, y: 0))
        scroller.reflectScrolledClipView(scroller.contentView)
    }

    func actionTarget(at point: NSPoint) -> NSTouchBarItem? {
        guard scroller != nil else { return source }
        let local = faces.convert(point, from: self)
        return zip(buttons, targets).first { $0.0.frame.contains(local) }?.1
    }

    // Only the editing surface participates in hit testing, including over sliders and Dock apps.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden || !frame.contains(point) ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        pressedWithOption = event.modifierFlags.contains(.option)
        let local = convert(event.locationInWindow, from: nil)
        pressedTarget = actionTarget(at: local)
        mouseDownWindowPoint = event.locationInWindow
        mouseDownLocalX = local.x
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard connected, !pressedWithOption, onDragEvent != nil else { return }
        if !isDragging {
            let dx = event.locationInWindow.x - mouseDownWindowPoint.x
            let dy = event.locationInWindow.y - mouseDownWindowPoint.y
            guard hypot(dx, dy) >= 5 else { return }
            isDragging = true
            isDragged = true
            NSCursor.closedHand.push()
            didPushDragCursor = true
            onDragEvent?(.began(windowPoint: event.locationInWindow, grabOffsetX: mouseDownLocalX))
        } else {
            onDragEvent?(.moved(windowPoint: event.locationInWindow))
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedTarget = nil }
        if isDragging {
            isDragging = false
            isDragged = false
            popDragCursorIfNeeded()
            onDragEvent?(.ended(windowPoint: event.locationInWindow))
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard connected, bounds.contains(point), pressedWithOption == event.modifierFlags.contains(.option) else { return }
        let click = PreviewClick.resolve(count: event.clickCount, option: pressedWithOption, group: item.children != nil)
        let target = actionTarget(at: point)
        if click == .test && (target == nil || pressedTarget !== target) { return }
        onClick?(click, target, point)
    }

    // MARK: - Context Menu

    private var contextMenuPoint: NSPoint = .zero
    private weak var contextMenuTarget: NSTouchBarItem?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard connected else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        contextMenuPoint = point
        contextMenuTarget = actionTarget(at: point)
        onClick?(.select, nil, point)

        let menu = NSMenu()
        var addedTopSection = false

        if status == .live, let target = contextMenuTarget, isTestable(target) {
            let testItem = NSMenuItem(title: L10n.preview("Test Action"),
                                      action: #selector(handleMenuTest), keyEquivalent: "")
            testItem.target = self
            testItem.image = NSImage(systemSymbolName: "play.circle", accessibilityDescription: nil)
            menu.addItem(testItem)
            addedTopSection = true
        }
        if item.children != nil {
            let openItem = NSMenuItem(title: L10n.preview("Open Group"),
                                      action: #selector(handleMenuEnterGroup), keyEquivalent: "")
            openItem.target = self
            openItem.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
            menu.addItem(openItem)
            addedTopSection = true
        }
        if addedTopSection { menu.addItem(.separator()) }

        let dupItem = NSMenuItem(title: L10n.preview("Duplicate"),
                                 action: #selector(handleMenuDuplicate), keyEquivalent: "")
        dupItem.target = self
        menu.addItem(dupItem)

        if canMoveZone && !item.isGesture {
            let moveItem = NSMenuItem(title: L10n.preview("Move to"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for align in PresetAlign.allCases {
                let entry = NSMenuItem(title: align.title, action: #selector(handleMenuMove(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = align.rawValue
                entry.isEnabled = item.align != align && !item.hasFixedAlign
                if item.align == align { entry.state = .on }
                sub.addItem(entry)
            }
            moveItem.submenu = sub
            menu.addItem(moveItem)
        }

        if !isSliderType && !item.isGesture {
            let borderItem = NSMenuItem(title: L10n.preview("Bordered"),
                                        action: #selector(handleMenuToggleBordered(_:)), keyEquivalent: "")
            borderItem.target = self
            let isBordered = item.json["bordered"]?.boolValue
                ?? (source as? CustomButtonTouchBarItem)?.isBordered
                ?? PresetItem.showsBorder(in: item.json)
            borderItem.state = isBordered ? .on : .off
            menu.addItem(borderItem)
        }

        menu.addItem(.separator())
        let deleteItem = NSMenuItem(title: L10n.preview("Delete"),
                                    action: #selector(handleMenuDelete), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        return menu
    }

    private func isTestable(_ target: NSTouchBarItem) -> Bool {
        target is CustomButtonTouchBarItem || target is GroupBarItem || target is CodexTodayBarItem
    }

    @objc private func handleMenuTest() {
        onContextAction?(.test(contextMenuTarget, contextMenuPoint))
    }

    @objc private func handleMenuEnterGroup() {
        onContextAction?(.enterGroup)
    }

    @objc private func handleMenuDuplicate() {
        onContextAction?(.duplicate)
    }

    @objc private func handleMenuMove(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let align = PresetAlign(rawValue: raw) else { return }
        onContextAction?(.moveTo(align))
    }

    @objc private func handleMenuToggleBordered(_ sender: NSMenuItem) {
        onContextAction?(.setBordered(sender.state != .on))
    }

    @objc private func handleMenuDelete() {
        onContextAction?(.delete)
    }

    override func accessibilityPerformPress() -> Bool {
        guard connected else { return false }
        onClick?(.select, nil, .zero)
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        if let scroller, faces.frame.width > bounds.width {
            scroller.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
