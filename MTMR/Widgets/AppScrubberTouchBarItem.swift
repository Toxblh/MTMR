//
//  AppScrubberTouchBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 18.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.

import Cocoa

class AppScrubberTouchBarItem: NSCustomTouchBarItem, NSScrubberDelegate, NSScrubberDataSource {
    private var scrubber: NSScrubber!

    private var timer: Timer!
    private var ticks: Int = 0
    private let minTicks: Int = 5
    private let maxTicks: Int = 20
    private var lastSelected: Int = 0
    private var autoResize: Bool = false
    private var widthConstraint: NSLayoutConstraint?

    private var persistentAppIdentifiers: [String] = []
    private var runningAppsIdentifiers: [String] = []

    private var frontmostApplicationIdentifier: String? {
        guard let frontmostId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        return frontmostId
    }

    private var applications: [DockItem] = []
    
    convenience override init(identifier: NSTouchBarItem.Identifier) {
        self.init(identifier: identifier, autoResize: false)
    }
    
    static var iconWidth = 36
    static var spacingWidth = 2

    init(identifier: NSTouchBarItem.Identifier, autoResize: Bool) {
        super.init(identifier: identifier)
        self.autoResize = autoResize
        
        scrubber = NSScrubber()
        scrubber.delegate = self
        scrubber.dataSource = self
        scrubber.mode = .free // .fixed
        let layout = NSScrubberFlowLayout()
        layout.itemSize = NSSize(width: AppScrubberTouchBarItem.iconWidth, height: 32)
        layout.itemSpacing = CGFloat(AppScrubberTouchBarItem.spacingWidth)
        scrubber.scrubberLayout = layout
        scrubber.selectionBackgroundStyle = .roundedBackground
        scrubber.showsAdditionalContentIndicators = true

        view = scrubber

        scrubber.register(NSScrubberImageItemView.self, forItemIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ScrubberApplicationsItemReuseIdentifier"))

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        persistentAppIdentifiers = AppSettings.dockPersistentAppIds
        updateRunningApplication()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func activeApplicationChanged(n _: Notification) {
        updateRunningApplication()
    }

    override func observeValue(forKeyPath _: String?, of _: Any?, change _: [NSKeyValueChangeKey: Any]?, context _: UnsafeMutableRawPointer?) {
        updateRunningApplication()
    }

    func updateRunningApplication() {
        let newApplications = launchedApplications()

        let index = newApplications.firstIndex {
            $0.bundleIdentifier == frontmostApplicationIdentifier
        }

        applications = newApplications
        applications += getDockPersistentAppsList()
        scrubber.reloadData()
        updateSize()

        scrubber.selectedIndex = index ?? 0
    }
    
    func updateSize() {
        if self.autoResize {
            if let constraint: NSLayoutConstraint = self.widthConstraint {
                constraint.isActive = false
                self.scrubber.removeConstraint(constraint)
            }
            let width = (AppScrubberTouchBarItem.iconWidth + AppScrubberTouchBarItem.spacingWidth) * self.applications.count - AppScrubberTouchBarItem.spacingWidth
            self.widthConstraint = self.scrubber.widthAnchor.constraint(equalToConstant: CGFloat(width))
            self.widthConstraint!.isActive = true
        }
    }

    public func numberOfItems(for _: NSScrubber) -> Int {
        return applications.count
    }

    public func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let item = scrubber.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ScrubberApplicationsItemReuseIdentifier"), owner: self) as? NSScrubberImageItemView ?? NSScrubberImageItemView()
        item.imageView.imageScaling = .scaleProportionallyDown

        let app = applications[index]

        if let icon = app.icon {
            item.image = icon
            item.image.size = NSSize(width: 26, height: 26)
        }

        item.removeFromSuperview()

        let dotView = NSView(frame: .zero)
        dotView.wantsLayer = true
        if runningAppsIdentifiers.contains(app.bundleIdentifier!) {
            dotView.layer?.backgroundColor = NSColor.white.cgColor
        } else {
            dotView.layer?.backgroundColor = NSColor.black.cgColor
        }
        dotView.layer?.cornerRadius = 1.5
        dotView.setFrameOrigin(NSPoint(x: 17, y: 1))
        dotView.frame.size = NSSize(width: 3, height: 3)
        item.addSubview(dotView)

        return item
    }

    public func didBeginInteracting(with _: NSScrubber) {
        stopTimer()
        ticks = 0
        timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(checkTimer), userInfo: nil, repeats: true)
    }

    @objc private func checkTimer() {
        ticks += 1

        if ticks == minTicks {
            HapticFeedback.shared?.tap(strong: 2)
        }

        if ticks > maxTicks {
            stopTimer()
            HapticFeedback.shared?.tap(strong: 6)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        lastSelected = 0
    }

    public func didCancelInteracting(with _: NSScrubber) {
        stopTimer()
    }

    public func didFinishInteracting(with scrubber: NSScrubber) {
        stopTimer()

        if ticks == 0 {
            return
        }

        if ticks >= minTicks && scrubber.selectedIndex > 0 {
            longPress(selected: scrubber.selectedIndex)
            return
        }

        let bundleIdentifier = applications[scrubber.selectedIndex].bundleIdentifier
        if bundleIdentifier!.contains("file://") {
            NSWorkspace.shared.openFile(bundleIdentifier!.replacingOccurrences(of: "file://", with: ""))
        } else {
            NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleIdentifier!, options: [.default], additionalEventParamDescriptor: nil, launchIdentifier: nil)
            HapticFeedback.shared?.tap(strong: 6)
        }
        updateRunningApplication()

        // NB: if you can't open app which on another space, try to check mark
        // "When switching to an application, switch to a Space with open windows for the application"
        // in Mission control settings
    }

    private func longPress(selected: Int) {
        let bundleIdentifier = applications[selected].bundleIdentifier

        if ticks > maxTicks {
            if let processIdentifier = applications[selected].pid {
                if !(NSRunningApplication(processIdentifier: processIdentifier)?.terminate())! {
                    NSRunningApplication(processIdentifier: processIdentifier)?.forceTerminate()
                }
            }
        } else {
            HapticFeedback.shared?.tap(strong: 6)
            if let index = self.persistentAppIdentifiers.firstIndex(of: bundleIdentifier!) {
                persistentAppIdentifiers.remove(at: index)
            } else {
                persistentAppIdentifiers.append(bundleIdentifier!)
            }

            AppSettings.dockPersistentAppIds = persistentAppIdentifiers
        }
        ticks = 0
        updateRunningApplication()
    }

    private func launchedApplications() -> [DockItem] {
        runningAppsIdentifiers = []
        var returnable: [DockItem] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == NSApplication.ActivationPolicy.regular else { continue }
            guard let bundleIdentifier = app.bundleIdentifier else { continue }

            runningAppsIdentifiers.append(bundleIdentifier)

            let dockItem = DockItem(bundleIdentifier: bundleIdentifier, icon: getIcon(forBundleIdentifier: bundleIdentifier), pid: app.processIdentifier)
            returnable.append(dockItem)
        }
        return returnable
    }

    public func getIcon(forBundleIdentifier bundleIdentifier: String? = nil, orPath path: String? = nil, orType _: String? = nil) -> NSImage {
        if bundleIdentifier != nil {
            if let appPath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleIdentifier!) {
                return NSWorkspace.shared.icon(forFile: appPath)
            }
        }

        if path != nil {
            return NSWorkspace.shared.icon(forFile: path!)
        }

        let genericIcon = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns")
        return genericIcon ?? NSImage(size: .zero)
    }

    public func getDockPersistentAppsList() -> [DockItem] {
        var returnable: [DockItem] = []

        for bundleIdentifier in persistentAppIdentifiers {
            if !runningAppsIdentifiers.contains(bundleIdentifier) {
                let dockItem = DockItem(bundleIdentifier: bundleIdentifier, icon: getIcon(forBundleIdentifier: bundleIdentifier))
                returnable.append(dockItem)
            }
        }

        return returnable
    }
}

public class DockItem: NSObject {
    var bundleIdentifier: String!, icon: NSImage!, pid: Int32!

    convenience init(bundleIdentifier: String, icon: NSImage, pid: Int32? = nil) {
        self.init()
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
        self.pid = pid
    }
}
