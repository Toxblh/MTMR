//
//  GroupBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 11.05.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//
// Group children are shared by the hardware and any open editor. The weak cache lets
// a preview-only child stop as soon as its last consumer releases it.
import Cocoa
import os.log

final class GroupBarItem: NSPopoverTouchBarItem, NSTouchBarDelegate, NSGestureRecognizerDelegate {
    private let definitions: [BarItemDefinition]
    private let makeItem: (NSTouchBarItem.Identifier, BarItemDefinition) -> NSTouchBarItem?
    private let children = NSMapTable<NSNumber, NSTouchBarItem>.strongToWeakObjects()
    weak var parentGroup: GroupBarItem?
    var sourcePath: [Int] = []

    private var hardwareItems: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    private var scrollArea: ScrollViewItem?
    var layoutAnchor: NSView? {
        let center = scrollArea?.view
        if center?.window != nil { return center }
        return hardwareItems.values.lazy.compactMap { $0.view }.first { $0.window != nil } ?? center
    }

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

    init(identifier: NSTouchBarItem.Identifier, items: [BarItemDefinition], showsIcon: Bool = false,
         makeItem: @escaping (NSTouchBarItem.Identifier, BarItemDefinition) -> NSTouchBarItem?) {
        definitions = items
        self.makeItem = makeItem
        self.showsIcon = showsIcon
        super.init(identifier: identifier)
        popoverTouchBar.delegate = self
        updateCollapsedRepresentation()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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

    func child(at index: Int) -> NSTouchBarItem? {
        guard definitions.indices.contains(index) else { return nil }
        let key = NSNumber(value: index)
        if let child = children.object(forKey: key) { return child }
        let definition = definitions[index]
        let identifier = NSTouchBarItem.Identifier(definition.type.identifierBase + UUID().uuidString)
        guard let child = makeItem(identifier, definition) else { return nil }
        if let group = child as? GroupBarItem {
            group.sourcePath = sourcePath + [index]
            group.parentGroup = self
        }
        children.setObject(child, forKey: key)
        return child
    }

    @objc override func showPopover(_ sender: Any?) {
        TouchBarController.shared.presentGroup(self)
    }

    func install(on bar: NSTouchBar) {
        var left: [NSTouchBarItem] = []
        var center: [NSTouchBarItem] = []
        var right: [NSTouchBarItem] = []
        var retained: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
        for (index, definition) in definitions.enumerated() {
            guard let item = child(at: index) else { continue }
            retained[item.identifier] = item
            switch definition.align {
            case .left: left.append(item)
            case .center: center.append(item)
            case .right: right.append(item)
            }
        }
        hardwareItems = retained
        let area = ScrollViewItem(identifier: .init("com.toxblh.mtmr.scrollArea." + UUID().uuidString), items: center)
        scrollArea = area

        // The scroll area takes only the width of its items (it may shrink and scroll when space is short). The free
        // rest goes to an empty view instead: a scroll view handles touches itself for scrolling, so a tap on its
        // empty part never reached the close recognizer (first test on the device).
        let contentWidth = (area.view as? NSScrollView)?.documentView?.fittingSize.width ?? 0
        let fitContent = area.view.widthAnchor.constraint(equalToConstant: contentWidth)
        fitContent.priority = .defaultHigh
        fitContent.isActive = true
        let emptySpace = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("com.toxblh.mtmr.groupEmptySpace.".appending(UUID().uuidString)))
        let emptyView = NSView()
        emptyView.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        emptyView.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        emptySpace.view = emptyView

        groupViewIdentifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.groupView.".appending(UUID().uuidString))
        let groupView = BasicView(identifier: groupViewIdentifier, items: left + [area, emptySpace] + right, swipeItems: [])
        groupView.legacyGesturesEnabled = AppSettings.multitouchGestures
        itemViews = (left + center + right).compactMap(\.view)
        installEmptySpaceTap(on: groupView.view)
        self.groupView = groupView

        bar.delegate = self
        bar.defaultItemIdentifiers = []
        bar.defaultItemIdentifiers = [groupViewIdentifier]
    }

    func releaseHardwareItems() {
        scrollArea = nil
        groupView = nil
        itemViews = []
        emptySpaceTap = nil
        hardwareItems.removeAll()
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
        return !isOnItem(touch.location(in: view), in: view)
    }

    private func emptySpaceTapped() {
        os_log("MTMR group: tap on free space: closing", log: .default, type: .default)
        HapticFeedback.instance.tap(type: .back)
        TouchBarController.shared.closeGroup()
    }

    // MARK: NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == groupViewIdentifier { return groupView }
        if identifier == scrollArea?.identifier { return scrollArea }
        return hardwareItems[identifier]
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
