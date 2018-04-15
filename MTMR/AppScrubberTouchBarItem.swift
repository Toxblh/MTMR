//
//  AppScrubberTouchBarItem.swift
//
//  This file is part of TouchDock
//  Copyright (C) 2017  Xander Deng
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Cocoa

let activateKeyIndex = "ActivateKeyIndex"
let appScrubberOrderIndex = "AppScrubberOrderIndex"
let appScrubberModeIndex = "AppScrubberModeIndex"

class AppScrubberTouchBarItem: NSCustomTouchBarItem, NSScrubberDelegate, NSScrubberDataSource {
    
    var scrubber: NSScrubber!
    
    var runningApplications: [NSRunningApplication] = []
    
    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        
        scrubber = NSScrubber().then {
            $0.delegate = self
            $0.dataSource = self
            $0.mode = UserDefaults.standard.appScrubberMode
            let layout = NSScrubberFlowLayout().then {
                $0.itemSize = NSSize(width: 50, height: 30)
            }
            $0.scrubberLayout = layout
            $0.selectionBackgroundStyle = .roundedBackground
        }
        view = scrubber
        
        scrubber.register(NSScrubberImageItemView.self, forItemIdentifier: .scrubberApplicationsItem)
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: appScrubberOrderIndex, context: nil)
        
        updateRunningApplication(animated: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func activeApplicationChanged(n: Notification) {
        updateRunningApplication(animated: true)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        updateRunningApplication(animated: false)
    }
    
    func updateRunningApplication(animated: Bool) {
        let isDockOrder = UserDefaults.standard.integer(forKey: appScrubberOrderIndex) != 0
        let newApplications = (isDockOrder ? dockPersistentApplications() : launchedApplications()).filter {
            !$0.isTerminated && $0.bundleIdentifier != nil
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let index = newApplications.index {
            $0.processIdentifier == frontmost?.processIdentifier
        }
        if animated {
            scrubber.performSequentialBatchUpdates {
//                print("-----update-----")
                for (index, app) in newApplications.enumerated() {
                    while runningApplications[safe:index].map(newApplications.contains) == false {
                        scrubber.removeItems(at: [index])
                        let r = runningApplications.remove(at: index)
//                        print("remove \(r.localizedName!) at \(index)")
                    }
                    if let oldIndex = runningApplications.index(of: app) {
                        guard oldIndex != index else {
                            return
                        }
                        scrubber.moveItem(at: oldIndex, to: index)
                        runningApplications.move(at: oldIndex, to: index)
//                        print("move \(app.localizedName!) at \(oldIndex) to \(index)")
                    } else {
                        scrubber.insertItems(at: [index])
                        runningApplications.insert(app, at: index)
//                        print("insert \(app.localizedName!) to \(index)")
                    }
                }
                assert(runningApplications == newApplications)
            }
        } else {
            runningApplications = newApplications
            scrubber.reloadData()
        }
        scrubber.selectedIndex = index ?? 0
    }
    
    // MARK: - NSScrubberDataSource
    
    public func numberOfItems(for scrubber: NSScrubber) -> Int {
        return runningApplications.count
    }
    
    public func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let item = scrubber.makeItem(withIdentifier: .scrubberApplicationsItem, owner: self) as? NSScrubberImageItemView ?? NSScrubberImageItemView()
        item.imageView.imageScaling = .scaleProportionallyDown
        if let icon = runningApplications[index].icon {
            item.image = icon
        }
        return item
    }
    
    public func didFinishInteracting(with scrubber: NSScrubber) {
        guard scrubber.selectedIndex > 0 else {
            return
        }
        runningApplications[scrubber.selectedIndex].activate(options: .activateIgnoringOtherApps)
    }
    
}

// MARK: - Applications

private func launchedApplications() -> [NSRunningApplication] {
    let asns = _LSCopyApplicationArrayInFrontToBackOrder(~0)?.takeRetainedValue()
    return (0..<CFArrayGetCount(asns)).flatMap { index in
        let asn = CFArrayGetValueAtIndex(asns, index)
        let pid = pidFromASN(asn)
        return NSRunningApplication(processIdentifier: pid)
    }
}

private func dockPersistentApplications() -> [NSRunningApplication] {
    let apps = NSWorkspace.shared.runningApplications.filter {
        $0.activationPolicy == .regular
    }
    
    guard let dockDefaults = UserDefaults(suiteName: "com.apple.dock"),
        let persistentApps = dockDefaults.array(forKey: "persistent-apps") as [AnyObject]?,
        let bundleIDs = persistentApps.flatMap({ $0.value(forKeyPath: "tile-data.bundle-identifier") }) as? [String] else {
            return apps
    }
    
    return apps.sorted { (lhs, rhs) in
        if lhs.bundleIdentifier == "com.apple.finder" {
            return true
        }
        if rhs.bundleIdentifier == "com.apple.finder" {
            return false
        }
        switch ((bundleIDs.index(of: lhs.bundleIdentifier!)), bundleIDs.index(of: rhs.bundleIdentifier!)) {
        case (nil, _):
            return false;
        case (_?, nil):
            return true
        case let (i1?, i2?):
            return i1 < i2;
        }
    }
}

public protocol Then {}

extension Then where Self: Any {
    
    /// Makes it available to set properties with closures just after initializing and copying the value types.
    ///
    ///     let frame = CGRect().with {
    ///       $0.origin.x = 10
    ///       $0.size.width = 100
    ///     }
    public func with(_ block: (inout Self) throws -> Void) rethrows -> Self {
        var copy = self
        try block(&copy)
        return copy
    }
    
    /// Makes it available to execute something with closures.
    ///
    ///     UserDefaults.standard.do {
    ///       $0.set("devxoul", forKey: "username")
    ///       $0.set("devxoul@gmail.com", forKey: "email")
    ///       $0.synchronize()
    ///     }
    public func `do`(_ block: (Self) throws -> Void) rethrows {
        try block(self)
    }
    
}

extension Then where Self: AnyObject {
    
    /// Makes it available to set properties with closures just after initializing.
    ///
    ///     let label = UILabel().then {
    ///       $0.textAlignment = .Center
    ///       $0.textColor = UIColor.blackColor()
    ///       $0.text = "Hello, World!"
    ///     }
    public func then(_ block: (Self) throws -> Void) rethrows -> Self {
        try block(self)
        return self
    }
    
}

extension NSObject: Then {}

extension CGPoint: Then {}
extension CGRect: Then {}
extension CGSize: Then {}
extension CGVector: Then {}

extension UserDefaults {
    
    var activateKey: NSEvent.ModifierFlags? {
        let keys: [NSEvent.ModifierFlags?] = [.command, .option, .control, .shift, nil]
        let index = integer(forKey: activateKeyIndex)
        return keys[index]
    }
    
    var appScrubberMode: NSScrubber.Mode {
        let actions: [NSScrubber.Mode] = [.fixed, .free]
        let index = integer(forKey: appScrubberModeIndex)
        return actions[index]
    }
}

extension NSUserInterfaceItemIdentifier {
    
    static let scrubberApplicationsItem = NSUserInterfaceItemIdentifier("ScrubberApplicationsItemReuseIdentifier")
}

extension RangeReplaceableCollection {
    
    mutating func move(at oldIndex: Self.Index, to newIndex: Self.Index) {
        guard oldIndex != newIndex else {
            return
        }
        let item = remove(at: oldIndex)
        insert(item, at: newIndex)
    }
}

extension Collection {
    
    subscript(safe index: Self.Index) -> Self.Iterator.Element? {
        guard index < endIndex else {
            return nil
        }
        return self[index]
    }
}
