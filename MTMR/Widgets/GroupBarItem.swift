//
//  GroupBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 11.05.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//
import Cocoa


class GroupBarItem: CustomTouchBarItem, NSTouchBarDelegate {
    private(set) var popoverItem: NSPopoverTouchBarItem!
    var jsonItems: [BarItemDefinition] = []

    override class var typeIdentifier: String {
        return "group"
    }
    
    private enum CodingKeys: String, CodingKey {
        case items
        case title
    }
    
    var itemDefinitions: [NSTouchBarItem.Identifier: BarItemDefinition] = [:]
    var items: [CustomTouchBarItem] = []
    var leftIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerItems: [NSTouchBarItem] = []
    var rightIdentifiers: [NSTouchBarItem.Identifier] = []
    var scrollArea: NSCustomTouchBarItem?
    var swipeItems: [SwipeItem] = []
    var centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.GroupScrollArea.".appending(UUID().uuidString))
    var basicView: BasicView?
    var basicViewIdentifier = NSTouchBarItem.Identifier("com.toxblh.mtmr.GroupScrollView.".appending(UUID().uuidString))


    init(identifier: NSTouchBarItem.Identifier, items: [BarItemDefinition], title: String) {
        jsonItems = items
        popoverItem = NSPopoverTouchBarItem(identifier: identifier)
        super.init(identifier: identifier)
        
        self.setup(title: title)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        popoverItem = NSPopoverTouchBarItem(identifier: identifier)
        
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.jsonItems = try container.decode([BarItemDefinition].self, forKey: .items)
        let title = try container.decodeIfPresent(String.self, forKey: .title) ?? " "
        
        self.setup(title: title)
    }
    
    
    func setup(title: String) {
        let button = NSButton(title: title, target: self,
                              action: #selector(GroupBarItem.showPopover(_:)))
        
        // Use the built-in gesture recognizer for tap and hold to open our popover's NSTouchBar.
        let gestureRecognizer = popoverItem.makeStandardActivatePopoverGestureRecognizer()
        button.addGestureRecognizer(gestureRecognizer)
        
        popoverItem.collapsedRepresentation = button
        
        view = button

        if getWidth() == 0.0 {
            setWidth(value: 60)
        }
    }

    @objc func showPopover(_: Any?) {
        items = getItems(newItems: jsonItems)
        
        let leftItems = items.compactMap({ (item) -> CustomTouchBarItem? in
            item.align == .left || item.align == .center ? item : nil
        })
        let centerItems = items.compactMap({ (item) -> CustomTouchBarItem? in
            item.align == .center && false ? item : nil
        })
        let rightItems = items.compactMap({ (item) -> CustomTouchBarItem? in
            item.align == .right ? item : nil
        })

        let centerScrollArea = NSTouchBarItem.Identifier("com.toxblh.mtmr.scrollArea.".appending(UUID().uuidString))
        let scrollArea = ScrollViewItem(identifier: centerScrollArea, items: centerItems)
        
        TouchBarController.shared.touchBar.delegate = self
        TouchBarController.shared.touchBar.defaultItemIdentifiers = [basicViewIdentifier]
        
        basicView = BasicView(identifier: basicViewIdentifier, items: leftItems + [scrollArea] + rightItems, swipeItems: swipeItems)
        basicView?.legacyGesturesEnabled = AppSettings.multitouchGestures
        

        if AppSettings.showControlStripState {
            presentSystemModal(TouchBarController.shared.touchBar, systemTrayItemIdentifier: .controlStripItem)
        } else {
            presentSystemModal(TouchBarController.shared.touchBar, placement: 1, systemTrayItemIdentifier: .controlStripItem)
        }
    }

    func touchBar(_: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == basicViewIdentifier {
            return basicView
        }

        return nil
    }
    
    func getItems(newItems: [BarItemDefinition]) -> [CustomTouchBarItem] {
        var items: [CustomTouchBarItem] = []
        for item in newItems {
            if item.obj is SwipeItem {
                swipeItems.append(item.obj as! SwipeItem)
            } else {
                items.append(item.obj)
            }
        }
        return items
    }
}

