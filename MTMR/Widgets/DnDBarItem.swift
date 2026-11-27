//
//  DnDBarItem.swift
//  MTMR
//
//  Created by Anton Palgunov on 29/08/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import AppKit
import Foundation

class DnDBarItem: CustomButtonTouchBarItem {
    private var stateObserver: NSObjectProtocol?
    private var lastRenderedState: Bool?

    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: "")
        isBordered = false
        setWidth(value: 32)

        actions.append(ItemAction(trigger: .singleTap) { [weak self] in self?.DnDToggle() })

        DoNotDisturb.startObserving()
        stateObserver = NotificationCenter.default.addObserver(
            forName: DoNotDisturb.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        refresh()
    }

    deinit {
        if let stateObserver {
            NotificationCenter.default.removeObserver(stateObserver)
        }
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func DnDToggle() {
        DoNotDisturb.toggle()
    }

    @objc func refresh() {
        let enabled = DoNotDisturb.isEnabled
        guard enabled != lastRenderedState else { return }
        lastRenderedState = enabled
        image = enabled
            ? IconLibrary.image(named: "dnd-on", fallback: #imageLiteral(resourceName: "dnd-on"))
            : IconLibrary.image(named: "dnd-off", fallback: #imageLiteral(resourceName: "dnd-off"))
    }
}
