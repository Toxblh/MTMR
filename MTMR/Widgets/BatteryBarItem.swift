//
//  BatteryBarItem.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import IOKit.ps
import Foundation

class BatteryBarItem: CustomButtonTouchBarItem {
    private let batteryInfo = BatteryInfo()
    
    init(identifier: NSTouchBarItem.Identifier, onTap: @escaping () -> (), onLongTap: @escaping () -> ()) {
        super.init(identifier: identifier, title: " ", onTap: onTap, onLongTap: onLongTap)
        
        batteryInfo.start { [weak self] in
            self?.refresh()
        }
        self.refresh()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func refresh() {
        self.attributedTitle = self.batteryInfo.formattedInfo()
    }
    
    deinit {
        batteryInfo.stop()
    }
}

class BatteryInfo: NSObject {
    var current: Int = 0
    var timeToEmpty: Int = 0
    var timeToFull: Int = 0
    var isCharged: Bool = false
    var isCharging: Bool = false
    var ACPower: String = ""
    var timeRemaining: String = ""
    var notifyBlock: ()->() = {}
    var loop:CFRunLoopSource?
    
    func start(notifyBlock: @escaping ()->()) {
        self.notifyBlock = notifyBlock
        let opaque = Unmanaged.passRetained(self).toOpaque()
        let context = UnsafeMutableRawPointer(opaque)
        loop = IOPSNotificationCreateRunLoopSource({ (context) in
            guard let ctx = context else {
                return
            }
            
            let watcher = Unmanaged<BatteryInfo>.fromOpaque(ctx).takeUnretainedValue()
            watcher.notifyBlock()
        }, context).takeRetainedValue() as CFRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, CFRunLoopMode.defaultMode)
    }
    
    func stop() {
        self.notifyBlock = {}
        guard let loop = self.loop else {
            return
        }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), loop, CFRunLoopMode.defaultMode)
        self.loop = nil
    }
    
    func getPSInfo() {
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]
        
        for ps in psList {
            if let psDesc = IOPSGetPowerSourceDescription(psInfo, ps).takeUnretainedValue() as? [String: Any] {
                let current = psDesc[kIOPSCurrentCapacityKey]
                if (current != nil) {
                    self.current = current as! Int
                }
                
                let timeToEmpty = psDesc[kIOPSTimeToEmptyKey]
                if (timeToEmpty != nil) {
                    self.timeToEmpty = timeToEmpty as! Int
                }
                
                let timeToFull = psDesc[kIOPSTimeToFullChargeKey]
                if (timeToFull != nil) {
                    self.timeToFull = timeToFull as! Int
                }
                
                let isCharged = psDesc[kIOPSIsChargedKey]
                if (isCharged != nil) {
                    self.isCharged = isCharged as! Bool
                }
                
                let isCharging = psDesc[kIOPSIsChargingKey]
                if (isCharging != nil) {
                    self.isCharging = isCharging as! Bool
                }
                
                let ACPower = psDesc[kIOPSPowerSourceStateKey]
                if (ACPower != nil) {
                    self.ACPower = ACPower as! String
                }
            }
        }
    }
    
    func getFormattedTime(time: Int) -> String {
        if (time > 0) {
            let timeFormatted = NSString(format: " %d:%02d", time / 60, time % 60) as String
            return timeFormatted
        }
        
        return ""
    }
    
    public func formattedInfo() -> NSAttributedString {
        var title = ""
        self.getPSInfo()
        
        if ACPower == "AC Power" {
            if current < 100 {
                title += "⚡️"
            }
            timeRemaining = getFormattedTime(time: timeToFull)
        } else {
            timeRemaining = getFormattedTime(time: timeToEmpty)
        }
        
        title += String(current) + "%"
        
        var color = NSColor.white
        if current <= 10 && ACPower != "AC Power" {
            color = NSColor.red
        }
        
        let newTitle = NSMutableAttributedString(string: title as String, attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 15), .baselineOffset: 1])
        let newTitleSecond = NSMutableAttributedString(string: timeRemaining as String, attributes: [NSAttributedStringKey.foregroundColor: color, NSAttributedStringKey.font: NSFont.systemFont(ofSize: 8, weight: .regular), NSAttributedStringKey.baselineOffset: 7])
        newTitle.append(newTitleSecond)
        newTitle.setAlignment(.center, range: NSRange(location: 0, length: title.count))
        return newTitle
    }
    
}
