// Group children are shared by the hardware and any open editor. The weak cache lets
// a preview-only child stop as soon as its last consumer releases it.
import Cocoa

final class GroupBarItem: NSPopoverTouchBarItem, NSTouchBarDelegate {
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

    init(identifier: NSTouchBarItem.Identifier, items: [BarItemDefinition],
         makeItem: @escaping (NSTouchBarItem.Identifier, BarItemDefinition) -> NSTouchBarItem?) {
        definitions = items
        self.makeItem = makeItem
        super.init(identifier: identifier)
        popoverTouchBar.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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
        var left: [NSTouchBarItem.Identifier] = []
        var center: [NSTouchBarItem] = []
        var right: [NSTouchBarItem.Identifier] = []
        var retained: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
        for (index, definition) in definitions.enumerated() {
            guard let item = child(at: index) else { continue }
            retained[item.identifier] = item
            switch definition.align {
            case .left: left.append(item.identifier)
            case .center: center.append(item)
            case .right: right.append(item.identifier)
            }
        }
        hardwareItems = retained
        let area = ScrollViewItem(identifier: .init("com.toxblh.mtmr.scrollArea." + UUID().uuidString), items: center)
        scrollArea = area
        bar.delegate = self
        bar.defaultItemIdentifiers = []
        bar.defaultItemIdentifiers = left + [area.identifier] + right
    }

    func releaseHardwareItems() {
        scrollArea = nil
        hardwareItems.removeAll()
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == scrollArea?.identifier { return scrollArea }
        return hardwareItems[identifier]
    }
}
