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
    
    private var blueLightStatus: Status {
        var status: Status = Status()
        nsclient.getBlueLightStatus(&status)
        return status
    }
    
    private var isNightShiftEnabled: Bool {
        return self.blueLightStatus.enabled.boolValue
    }
    
    private func setNightShift(state: Bool) {
        self.nsclient.setEnabled(state)
    }
    
    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: "")
        self.isBordered = false
        self.setWidth(value: 28)

        self.tapClosure = { [weak self] in self?.nightShiftAction() }
        
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        
        self.refresh()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func nightShiftAction() {
        self.setNightShift(state: !self.isNightShiftEnabled)
        self.refresh()
    }
    
    @objc func refresh() {
        self.image = isNightShiftEnabled ? #imageLiteral(resourceName: "nightShiftOn") : #imageLiteral(resourceName: "nightShiftOff")
    }
}
