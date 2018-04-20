//
//  BatteryBarItem.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import IOKit.ps
import Foundation

class BatteryBarItem: NSCustomTouchBarItem {
    private var timer: Timer!
    private let button = NSButton(title: "", target: nil, action: nil)
    
    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateInfo), userInfo: nil, repeats: true)
        self.view = button
        button.bezelColor = .clear
//        updateInfo()
        
        BatteryMonitor(button: button)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func updateInfo() {
        var title = ""
        
        let info = BatteryInfo().getInfo()
        let timeRemainig = info["timeRemainig"] as! String
        let percentage = info["percentage"] as! Int
        let isCharging = info["isCharging"] as! Bool
        let isCharged = info["isCharged"] as! Bool
        
        if isCharged {
            title += "⚡️"
        }
        
        title += String(percentage) + "%" + timeRemainig
        
        button.title = title
    }
}

class BatteryInfo: NSObject {
    var current: Int = 0
    var timeToEmpty: Int = 0
    var timeToFull: Int = 0
    var isCharged: Bool = false
    var isCharging: Bool = false
    
    var button: NSButton?
    var loop:CFRunLoopSource?
    
    override convenience init(button: NSButton) {
        super.init()
        
        self.button = button
        self.start()
    }
    
    func start() {
        let opaque = Unmanaged.passRetained(self).toOpaque()
        let context = UnsafeMutableRawPointer(opaque)
        loop = IOPSNotificationCreateRunLoopSource({ (context) in
            guard let ctx = context else {
                return
            }
            
            let watcher = Unmanaged<BatteryInfo>.fromOpaque(ctx).takeUnretainedValue()
            watcher.getInfo()
            }, context).takeRetainedValue() as CFRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, CFRunLoopMode.defaultMode)
    }
    

    
    func stop() {
        if !(self.loop != nil) {
            return
        }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), self.loop, CFRunLoopMode.defaultMode)
        self.loop = nil
    }
    
    func getFormattedTime(time: Int) -> String {
        if (time > 0) {
            let timeFormatted = NSString(format: " (%d:%02d)", time / 60, time % 60) as String
            print(timeFormatted)
            return timeFormatted
        } else if (time == 0) {
            return ""
        }
        
        return "(?)"
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
            }
        }
    }
    
    public func getInfo() -> [String: Any] {
        var result: [String: Any] = [:]
        var timeRemaining = ""
        
        self.getPSInfo()
//        print(self.current)
//        print(self.timeToEmpty)
//        print(self.timeToFull)
//        print(self.isCharged)
//        print(self.isCharging)
        
        if isCharged {
            timeRemaining = getFormattedTime(time: self.timeToFull)
        } else {
            timeRemaining = getFormattedTime(time: self.timeToEmpty)
        }
        
        result["timeRemainig"] = timeRemaining
        result["percentage"] = self.current
        result["isCharging"] = self.isCharging
        result["isCharged"] = self.isCharged
        
        return result
    }
}
