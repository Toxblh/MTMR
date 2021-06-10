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
        0x200_0000_0100_0000, // MacBook Pro 2016/2017
        0x300000080500000, // MacBook Pro 2019 (possibly 2018 as well)
        0x200000000000024 // MacBook Pro (13-inch, M1, 2020)
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

    private var correctDeviceID: UInt64?
    private var actuatorRef: CFTypeRef?

    static var instance = HapticFeedback()

    // MARK: - Init

    private init() {
        self.recreateDevice()
        //        HapticFeedback.shared = AppSettings.hapticFeedbackState ? HapticFeedback() : nil
    }

    private func recreateDevice() {
        if let actuatorRef = self.actuatorRef {
            MTActuatorClose(actuatorRef)
            self.actuatorRef = nil // just in case %)
        }

        if let correctDeviceID = self.correctDeviceID {
            self.actuatorRef = MTActuatorCreateFromDeviceID(correctDeviceID).takeRetainedValue()
        } else {
            // Let's find our Haptic device
            self.possibleDeviceIDs.forEach {(deviceID) in
                guard self.correctDeviceID == nil else {return}
                self.actuatorRef = MTActuatorCreateFromDeviceID(deviceID).takeRetainedValue()

                if self.actuatorRef != nil {
                    self.correctDeviceID = deviceID
                }
            }
        }
    }

    // MARK: - Tap action

    func tap(type: HapticType) {
        guard AppSettings.hapticFeedbackState else {
            // Haptic feedback is disabled by user
            return
        }

        guard self.correctDeviceID != nil, let actuatorRef = self.actuatorRef else {
            print("guard actuatorRef == nil (no haptic device found?)")
            return
        }

        var result: IOReturn

        result = MTActuatorOpen(actuatorRef)
        guard result == kIOReturnSuccess else {
            print("guard MTActuatorOpen")
            self.recreateDevice()
            return
        }

        print("Try tap with: \(type.rawValue)")
        result = MTActuatorActuate(actuatorRef, type.rawValue, 0, 0, 0)
        guard result == kIOReturnSuccess else {
            print("guard MTActuatorActuate")
            return
        }

        result = MTActuatorClose(actuatorRef)
        guard result == kIOReturnSuccess else {
            print("guard MTActuatorClose")
            return
        }
    }
}
