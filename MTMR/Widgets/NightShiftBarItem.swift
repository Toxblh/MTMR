//
//  NightShiftBarItem.swift
//  MTMR
//
//  Created by Anton Palgunov on 28/08/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

class NightShiftBarItem: CustomButtonTouchBarItem {
    private let nsclient = CBBlueLightClient()
    private var timer: Timer!
    
    override class var typeIdentifier: String {
        return "nightShift"
    }

    private var blueLightStatus: Status {
        var status: Status = Status()
        nsclient.getBlueLightStatus(&status)
        return status
    }

    private var isNightShiftEnabled: Bool {
        return blueLightStatus.enabled.boolValue
    }

    private func setNightShift(state: Bool) {
        nsclient.setEnabled(state)
    }

    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: "")
        self.setup()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        self.setup()
    }
    
    func setup() {
        if getWidth() == 0.0 {
            setWidth(value: 28)
        }

        self.setTapAction(
            EventAction( { [weak self] (_ caller: CustomButtonTouchBarItem) in
                self?.nightShiftAction()
            } )
        )

        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)

        refresh()
    }

    func nightShiftAction() {
        setNightShift(state: !isNightShiftEnabled)
        refresh()
    }

    @objc func refresh() {
        self.setImage(isNightShiftEnabled ? #imageLiteral(resourceName: "nightShiftOn") : #imageLiteral(resourceName: "nightShiftOff"))
    }
}
