//
//  BatteryBarItem.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation
import IOKit.ps

class BatteryBarItem: CustomButtonTouchBarItem {
    private let batteryInfo = BatteryInfo()

    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: " ")

        batteryInfo.start { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh() {
        attributedTitle = batteryInfo.formattedInfo()
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
    var notifyBlock: () -> Void = {}
    var loop: CFRunLoopSource?

    func start(notifyBlock: @escaping () -> Void) {
        self.notifyBlock = notifyBlock
        let opaque = Unmanaged.passRetained(self).toOpaque()
        let context = UnsafeMutableRawPointer(opaque)
        loop = IOPSNotificationCreateRunLoopSource({ context in
            guard let ctx = context else {
                return
            }

            let watcher = Unmanaged<BatteryInfo>.fromOpaque(ctx).takeUnretainedValue()
            watcher.notifyBlock()
        }, context).takeRetainedValue() as CFRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), loop, CFRunLoopMode.defaultMode)
    }

    func stop() {
        notifyBlock = {}
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
                if let current = psDesc[kIOPSCurrentCapacityKey] as? Int {
                    self.current = current
                }

                if let timeToEmpty = psDesc[kIOPSTimeToEmptyKey] as? Int {
                    self.timeToEmpty = timeToEmpty
                }

                if let timeToFull = psDesc[kIOPSTimeToFullChargeKey] as? Int {
                    self.timeToFull = timeToFull
                }

                if let isCharged = psDesc[kIOPSIsChargedKey] as? Bool {
                    self.isCharged = isCharged
                }

                if let isCharging = psDesc[kIOPSIsChargingKey] as? Bool {
                    self.isCharging = isCharging
                }

                if let ACPower = psDesc[kIOPSPowerSourceStateKey] as? String {
                    self.ACPower = ACPower
                }
            }
        }
    }

    func getFormattedTime(time: Int) -> String {
        if time > 0 {
            let timeFormatted = NSString(format: " %d:%02d", time / 60, time % 60) as String
            return timeFormatted
        }

        return ""
    }

    public func formattedInfo() -> NSAttributedString {
        var title = ""
        getPSInfo()

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
        let newTitleSecond = NSMutableAttributedString(string: timeRemaining as String, attributes: [NSAttributedString.Key.foregroundColor: color, NSAttributedString.Key.font: NSFont.systemFont(ofSize: 8, weight: .regular), NSAttributedString.Key.baselineOffset: 7])
        newTitle.append(newTitleSecond)
        newTitle.setAlignment(.center, range: NSRange(location: 0, length: title.count))
        return newTitle
    }
}
