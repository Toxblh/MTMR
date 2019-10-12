//
//  HapticFeedback.swift
//  MTMR
//
//  Created by Anton Palgunov on 09/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import IOKit

class HapticFeedback {
    static var shared: HapticFeedback?
    
    // Here we have list of possible IDs for Haptic Generator Device. They are not constant
    // To find deviceID, you will need IORegistryExplorer app from Additional Tools for Xcode dmg
    // which you can download from https://developer.apple.com/download/more/?=Additional%20Tools
    // Open IORegistryExplorer app, search for AppleMultitouchDevice and get "Multitouch ID"
    // There should be programmatic way to get it but I can't find, no docs for macOS :(
    private let possibleDeviceIDs: [UInt64] = [
        0x200_0000_0100_0000, // MacBook Pro 2016/2017
        0x300000080500000 // MacBook Pro 2019 (possibly 2018 as well)
    ]
    private var correctDeviceID: UInt64?
    private var actuatorRef: CFTypeRef?
    
    init() {
        recreateDevice()
    }

    // Don't know how to do strong is enum one of
    // 1 like back Click
    // 2 like Click
    // 3 week
    // 4 medium
    // 5 week medium
    // 6 strong
    // 15 nothing
    // 16 nothing
    // you can get a plist `otool -s __TEXT __tpad_act_plist /System/Library/PrivateFrameworks/MultitouchSupport.framework/Versions/Current/MultitouchSupport|tail -n +3|awk -F'\t' '{print $2}'|xxd -r -p`

    func tap(strong: Int32) {
        guard correctDeviceID != nil, actuatorRef != nil else {
            print("guard actuatorRef == nil (no haptic device found?)")
            return
        }

        var result: IOReturn
        
        result = MTActuatorOpen(actuatorRef!)
        guard result == kIOReturnSuccess else {
            print("guard MTActuatorOpen")
            recreateDevice()
            return
        }

        result = MTActuatorActuate(actuatorRef!, strong, 0, 0, 0)
        guard result == kIOReturnSuccess else {
            print("guard MTActuatorActuate")
            return
        }

        result = MTActuatorClose(actuatorRef!)
        guard result == kIOReturnSuccess else {
            print("guard MTActuatorClose")
            return
        }
    }
    
    private func recreateDevice() {
        if let actuatorRef = actuatorRef {
            MTActuatorClose(actuatorRef)
            self.actuatorRef = nil // just in case %)
        }
        
        if let correctDeviceID = correctDeviceID {
            actuatorRef = MTActuatorCreateFromDeviceID(correctDeviceID).takeRetainedValue()
        } else {
            // Let's find our Haptic device
            possibleDeviceIDs.forEach {(deviceID) in
                guard correctDeviceID == nil else {return}
                actuatorRef = MTActuatorCreateFromDeviceID(deviceID).takeRetainedValue()
                
                if actuatorRef != nil {
                    correctDeviceID = deviceID
                }
            }
        }
    }
}
