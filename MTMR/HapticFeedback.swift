//
//  HapticFeedback.swift
//  MTMR
//
//  Created by Anton Palgunov on 09/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import IOKit

class HapticFeedback {

    // Here we have list of possible IDs for Haptic Generator Device. They are not constant
    // To find deviceID, you will need IORegistryExplorer app from Additional Tools for Xcode dmg
    // which you can download from https://developer.apple.com/download/more/?=Additional%20Tools
    // Open IORegistryExplorer app, search for AppleMultitouchDevice and get "Multitouch ID"
    // There should be programmatic way to get it but I can't find, no docs for macOS :(
    private let possibleDeviceIDs: [UInt64] = [
        0x200_0000_0100_0000,   // MacBook Pro 2016/2017
        0x300_0000_8050_0000,   // MacBook Pro 2019/2018
        0x200_0000_0000_0024,   // MacBook Pro (13-inch, M1, 2020)
    ]

    // you can get a plist `otool -s __TEXT __tpad_act_plist /System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/Current/MultitouchSupport|tail -n +3|awk -F'\t' '{print $2}'|xxd -r -p`
    enum HapticType: Int32, CaseIterable {
        case back = 1
        case click = 2
        case weak = 3
        case medium = 4
        case weakMedium = 5
        case strong = 6
        case reserved1 = 15
        case reserved2 = 16
    }

    private var actuatorRef: CFTypeRef?

    static var instance = HapticFeedback()

    // MARK: - Init

    private init() {
        self.recreateDevice()
    }

    private func recreateDevice() {
        if let actuatorRef = self.actuatorRef {
            MTActuatorClose(actuatorRef)
            self.actuatorRef = nil // just in case %)
        }

        guard self.actuatorRef == nil else {
            return
        }

        // Let's find our Haptic device
        self.possibleDeviceIDs.forEach {(deviceID) in
            let actuatorRef = MTActuatorCreateFromDeviceID(deviceID).takeRetainedValue()

            if actuatorRef != nil {
                self.actuatorRef = actuatorRef
            }
        }
    }

    // MARK: - Tap action

    private func getActuatorIfPosible() -> CFTypeRef? {
        guard AppSettings.hapticFeedbackState else { return nil }
        guard let actuatorRef = self.actuatorRef else {
            print("guard actuatorRef == nil (no haptic device found?)")
            return nil
        }

        guard MTActuatorOpen(actuatorRef) == kIOReturnSuccess else {
            print("guard MTActuatorOpen")
            self.recreateDevice()
            return nil
        }

        return actuatorRef
    }

    func tap(type: HapticType) {
        guard let actuator = getActuatorIfPosible() else { return }

        guard MTActuatorActuate(actuator, type.rawValue, 0, 0, 0) == kIOReturnSuccess else {
            print("guard MTActuatorActuate")
            return
        }

        guard MTActuatorClose(actuator) == kIOReturnSuccess else {
            print("guard MTActuatorClose")
            return
        }
    }
}
