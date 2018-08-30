//
//  DnDBarItem.swift
//  MTMR
//
//  Created by Anton Palgunov on 29/08/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

class DnDBarItem : CustomButtonTouchBarItem {
    private var timer: Timer!
    
    init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier, title: "")
        self.isBordered = false
        self.setWidth(value: 32)
        
        self.tapClosure = { [weak self] in self?.DnDToggle() }
        
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        
        self.refresh()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func DnDToggle() {
        DoNotDisturb.isEnabled = !DoNotDisturb.isEnabled
        refresh()
    }
    
    @objc func refresh() {
        self.image = DoNotDisturb.isEnabled ? #imageLiteral(resourceName: "dnd-on") : #imageLiteral(resourceName: "dnd-off")
    }
}

public struct DoNotDisturb {
    private static let appId = "com.apple.notificationcenterui" as CFString
    private static let dndPref = "com.apple.notificationcenterui.dndprefs_changed"
    
    private static func set(_ key: String, value: CFPropertyList?) {
        CFPreferencesSetValue(key as CFString, value, appId, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
    
    private static func commitChanges() {
        CFPreferencesSynchronize(appId, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name(dndPref), object: nil, userInfo: nil, deliverImmediately: true)
        NSRunningApplication.runningApplications(withBundleIdentifier: appId as String).first?.terminate()
    }
    
    private static func enable() {
        set("dndStart", value: nil)
        set("dndEnd", value: nil)
        set("doNotDisturb", value: true as CFPropertyList)
        set("doNotDisturbDate", value: Date() as CFPropertyList)
        commitChanges()
    }
    
    private static func disable() {
        set("dndStart", value: nil)
        set("dndEnd", value: nil)
        set("doNotDisturb", value: false as CFPropertyList)
        set("doNotDisturbDate", value: nil)
        commitChanges()
    }
    
    static var isEnabled:Bool {
        get {
            return CFPreferencesGetAppBooleanValue("doNotDisturb" as CFString, appId, nil)
        }
        set {
            newValue ? enable() : disable()
        }
    }
}
