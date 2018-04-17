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

class AppScrubberTouchBarItem: NSCustomTouchBarItem, NSScrubberDelegate, NSScrubberDataSource {
    
    var scrubber: NSScrubber!
    
    var runningApplications: [NSRunningApplication] = []
    
    override init(identifier: NSTouchBarItem.Identifier) {
        super.init(identifier: identifier)
        
        scrubber = NSScrubber();
        scrubber.delegate = self
        scrubber.dataSource = self
        scrubber.mode = .free // .fixed
        let layout = NSScrubberFlowLayout();
        layout.itemSize = NSSize(width: 44, height: 30)
        layout.itemSpacing = 2
        scrubber.scrubberLayout = layout
        scrubber.selectionBackgroundStyle = .roundedBackground
        scrubber.showsAdditionalContentIndicators = true

        view = scrubber
        
        scrubber.register(NSScrubberImageItemView.self, forItemIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ScrubberApplicationsItemReuseIdentifier"))
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        
        updateRunningApplication()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func activeApplicationChanged(n: Notification) {
        updateRunningApplication()
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        updateRunningApplication()
    }
    
    func updateRunningApplication() {
        let newApplications = launchedApplications().filter {
            !$0.isTerminated && $0.bundleIdentifier != nil
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let index = newApplications.index {
            $0.processIdentifier == frontmost?.processIdentifier
        }

        runningApplications = newApplications
        scrubber.reloadData()
        
        scrubber.selectedIndex = index ?? 0
    }
    
    public func numberOfItems(for scrubber: NSScrubber) -> Int {
        return runningApplications.count
    }
    
    public func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let item = scrubber.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ScrubberApplicationsItemReuseIdentifier"), owner: self) as? NSScrubberImageItemView ?? NSScrubberImageItemView()
        item.imageView.imageScaling = .scaleProportionallyDown
        if let icon = runningApplications[index].icon {
            item.image = icon
        }
        return item
    }
    
    public func didFinishInteracting(with scrubber: NSScrubber) {
        runningApplications[scrubber.selectedIndex].activate(options: [ .activateIgnoringOtherApps ])
        
        // NB: if you can't open app which on another space, try to check mark
        // "When switching to an application, switch to a Space with open windows for the application"
        // in Mission control settings
        
        // TODO: deminiaturize app
//        if let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[ String : Any]] {
//            for dict in info {
//                if dict["kCGWindowOwnerName"] as! String == runningApplications[scrubber.selectedIndex].localizedName {
//                    print(dict["kCGWindowNumber"], dict["kCGWindowOwnerName"])
//                }
//            }
//        }
    }
}

private func launchedApplications() -> [NSRunningApplication] {
    let asns = _LSCopyApplicationArrayInFrontToBackOrder(~0)?.takeRetainedValue()
    return (0..<CFArrayGetCount(asns)).compactMap { index in
        let asn = CFArrayGetValueAtIndex(asns, index)
        let pid = pidFromASN(asn)
        return NSRunningApplication(processIdentifier: pid)
    }
}

