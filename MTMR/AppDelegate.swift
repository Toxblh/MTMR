//
//  AppDelegate.swift
//  MTMR
//
//  Created by Anton Palgunov on 16/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if #available(OSX 10.12.2, *) {
            TouchBarController.shared.setupControlStripPresence()
        } else {
            // Fallback on earlier versions
        }
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

