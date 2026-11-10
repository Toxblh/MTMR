//
//  GroupBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 11.05.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//
import Cocoa
import os.log

class GroupBarItem: NSPopoverTouchBarItem, NSTouchBarDelegate, NSGestureRecognizerDelegate {
    var jsonItems: [BarItemDefinition]

    var itemDefinitions: [NSTouchBarItem.Identifier: BarItemDefinition] = [:]
    var items: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    var leftIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerItems: [NSTouchBarItem] = []
    var rightIdentifiers: [NSTouchBarItem.Identifier] = []

    /// `"style": "icon"`: the group is shown as a borderless icon button like the other icon buttons.
    /// Otherwise the system's titled button (light background) is kept, as before.
    let showsIcon: Bool

    /// The preset's "image". Without one an icon group shows the folder icon.
    var iconImage: NSImage? {
        didSet { updateCollapsedRepresentation() }
    }

    override var collapsedRepresentationLabel: String {
        didSet { iconButton?.view.setAccessibilityLabel(collapsedRepresentationLabel) }
    }

    private var iconButton: CustomButtonTouchBarItem?

    /// The open group, as one item laid out like the main bar (left, scrolling centre, right). One view spanning
    /// the whole bar is what lets a tap on the free space be noticed at all; separate items leave gaps that
    /// belong to no view.
    private var groupView: BasicView?
    private var groupViewIdentifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.groupView.".appending(UUID().uuidString))
    private var itemViews: [NSView] = []
    private var emptySpaceTap: TouchTapRecognizer?

    init(identifier: NSTouchBarItem.Identifier, items: [BarItemDefinition], showsIcon: Bool = false) {
        jsonItems = items
        self.showsIcon = showsIcon
        super.init(identifier: identifier)
        popoverTouchBar.delegate = self
        updateCollapsedRepresentation()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {}

    /// For an icon group, replaces the system's titled button with an icon button that opens the group.
    /// Set last: `CustomButtonTouchBarItem` builds a new view whenever its image or border changes.
    private func updateCollapsedRepresentation() {
        guard showsIcon else { return }
        let button: CustomButtonTouchBarItem
        if let existing = iconButton {
            button = existing
        } else {
            button = CustomButtonTouchBarItem(identifier: NSTouchBarItem.Identifier(identifier.rawValue + ".icon"), title: "")
            button.actions.append(ItemAction(trigger: .singleTap) { [weak self] in self?.showPopover(nil) })
            iconButton = button
        }
        button.isBordered = false
        button.image = iconImage ?? IconLibrary.image(named: "folder", fallback: NSImage(named: NSImage.touchBarFolderTemplateName))
        button.setWidth(value: 32)
        button.view.setAccessibilityLabel(collapsedRepresentationLabel)
        collapsedRepresentation = button.view
    }

    @objc override func showPopover(_: Any?) {
        itemDefinitions = [:]
        items = [:]
        leftIdentifiers = []
        centerIdentifiers = []
        centerItems = []
        rightIdentifiers = []

        loadItemDefinitions(jsonItems: jsonItems)
        createItems()

        centerItems = centerIdentifiers.compactMap { items[$0] }
        let leftItems = leftIdentifiers.compactMap { items[$0] }
        let rightItems = rightIdentifiers.compactMap { items[$0] }

        let scrollArea = ScrollViewItem(
            identifier: NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea.".appending(UUID().uuidString)),
            items: centerItems
        )
        // The scroll area takes only the width of its items (it may shrink and scroll when space is short). The free
        // rest goes to an empty view instead: a scroll view handles touches itself for scrolling, so a tap on its
        // empty part never reached the close recognizer (first test on the device).
        let contentWidth = (scrollArea.view as? NSScrollView)?.documentView?.fittingSize.width ?? 0
        let fitContent = scrollArea.view.widthAnchor.constraint(equalToConstant: contentWidth)
        fitContent.priority = .defaultHigh
        fitContent.isActive = true
        let emptySpace = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("com.toxblh.mtmr.groupEmptySpace.".appending(UUID().uuidString)))
        let emptyView = NSView()
        emptyView.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        emptyView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        emptySpace.view = emptyView

        groupViewIdentifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.groupView.".appending(UUID().uuidString))
        let groupView = BasicView(identifier: groupViewIdentifier, items: leftItems + [scrollArea, emptySpace] + rightItems, swipeItems: [])
        groupView.legacyGesturesEnabled = AppSettings.multitouchGestures
        itemViews = (leftItems + centerItems + rightItems).compactMap(\.view)
        installEmptySpaceTap(on: groupView.view)
        self.groupView = groupView

        TouchBarController.shared.touchBar.delegate = self
        TouchBarController.shared.touchBar.defaultItemIdentifiers = []
        TouchBarController.shared.touchBar.defaultItemIdentifiers = [groupViewIdentifier]

        if AppSettings.showControlStripState {
            presentSystemModal(TouchBarController.shared.touchBar, systemTrayItemIdentifier: .controlStripItem)
        } else {
            presentSystemModal(TouchBarController.shared.touchBar, placement: 1, systemTrayItemIdentifier: .controlStripItem)
        }

        // The layout on the hardware cannot be seen from outside; log it once it has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak groupView, weak emptyView] in
            guard let self = self, let root = groupView?.view else { return }
            let frames = ([root] + self.itemViews + [emptyView].compactMap { $0 }).map { view -> String in
                let f = view.convert(view.bounds, to: nil)
                return "\(type(of: view)) x=\(Int(f.minX)) w=\(Int(f.width))"
            }
            Self.log("group opened: \(frames.joined(separator: ", "))")
        }
    }

    private static func log(_ message: String) {
        os_log("MTMR group: %{public}@", log: .default, type: .default, message)
    }

    // MARK: Closing with a tap next to the buttons

    private func installEmptySpaceTap(on view: NSView) {
        let tap = TouchTapRecognizer { [weak self] in self?.emptySpaceTapped() }
        tap.allowedTouchTypes = .direct
        tap.delegate = self
        view.addGestureRecognizer(tap)
        emptySpaceTap = tap
    }

    /// Whether a point of the group view lies on one of the group's items (buttons, sliders, widgets).
    private func isOnItem(_ point: NSPoint, in view: NSView) -> Bool {
        itemViews.contains { item in
            item.superview != nil && item.convert(item.bounds, to: view).contains(point)
        }
    }

    /// Touches on an item never reach this recognizer, so the item's own taps, long presses and slider drags
    /// work exactly as before.
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldReceive touch: NSTouch) -> Bool {
        guard gestureRecognizer === emptySpaceTap, let view = gestureRecognizer.view else { return true }
        let point = touch.location(in: view)
        let onItem = isOnItem(point, in: view)
        os_log("MTMR group: touch at x=%{public}d %{public}@", log: .default, type: .debug, Int(point.x), onItem ? "on an item" : "on free space")
        return !onItem
    }

    private func emptySpaceTapped() {
        Self.log("tap on free space: closing")
        HapticFeedback.instance.tap(type: .back)
        close()
    }

    func close() {
        TouchBarController.shared.closeGroup()
        groupView = nil
        itemViews = []
        items = [:]
    }

    // MARK: NSTouchBarDelegate

    func touchBar(_: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        identifier == groupViewIdentifier ? groupView : nil
    }

    func loadItemDefinitions(jsonItems: [BarItemDefinition]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH-mm-ss"
        let time = dateFormatter.string(from: Date())
        for item in jsonItems {
            let identifierString = item.type.identifierBase.appending(time + "--" + UUID().uuidString)
            let identifier = NSTouchBarItem.Identifier(identifierString)
            itemDefinitions[identifier] = item
            if item.align == .left {
                leftIdentifiers.append(identifier)
            }
            if item.align == .right {
                rightIdentifiers.append(identifier)
            }
            if item.align == .center {
                centerIdentifiers.append(identifier)
            }
        }
    }

    func createItems() {
        for (identifier, definition) in itemDefinitions {
            items[identifier] = TouchBarController.shared.createItem(forIdentifier: identifier, definition: definition)
        }
    }
}

/// A one-finger tap from Touch Bar touches. AppKit's NSClickGestureRecognizer does not recognize direct touches
/// (on the device the touches arrived, but its action never fired), so this reacts to the touch events itself,
/// like MTMR's button recognizers do. A finger that moves more than 10 pt is a swipe or scroll, not a tap.
final class TouchTapRecognizer: NSGestureRecognizer {
    private let onTap: () -> Void
    private var start: NSPoint?

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(target: nil, action: nil)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func touches(_ event: NSEvent) -> Set<NSTouch> {
        guard let view = view else { return [] }
        return event.touches(matching: .any, in: view)
    }

    override func touchesBegan(with event: NSEvent) {
        super.touchesBegan(with: event)
        let all = touches(event)
        // More than one finger: a swipe gesture, not a tap.
        start = all.count == 1 ? all.first.map { $0.location(in: view) } : nil
    }

    override func touchesMoved(with event: NSEvent) {
        super.touchesMoved(with: event)
        guard let start = start, let touch = touches(event).first else { return }
        if abs(touch.location(in: view).x - start.x) > 10 { self.start = nil }
    }

    override func touchesCancelled(with event: NSEvent) {
        super.touchesCancelled(with: event)
        start = nil
    }

    override func touchesEnded(with event: NSEvent) {
        super.touchesEnded(with: event)
        if start != nil { onTap() }
        start = nil
    }
}
