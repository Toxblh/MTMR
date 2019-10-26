//
//  AppScrubberTouchBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 18.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.

import Cocoa

class AppScrubberTouchBarItem: NSCustomTouchBarItem {
    private var scrollView = NSScrollView()
    private var autoResize: Bool = false
    private var widthConstraint: NSLayoutConstraint?

    private var persistentAppIdentifiers: [String] = []
    private var runningAppsIdentifiers: [String] = []

    private var frontmostApplicationIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private var applications: [DockItem] = []
    private var items: [CustomButtonTouchBarItem] = []

    init(identifier: NSTouchBarItem.Identifier, autoResize: Bool = false) {
        super.init(identifier: identifier)
        self.autoResize = autoResize //todo
        view = scrollView

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
        applications = launchedApplications()
        applications += getDockPersistentAppsList()
        reloadData()
        updateSize()
    }
    
    func updateSize() {
        if self.autoResize {
            self.widthConstraint?.isActive = false
            
            let width = self.scrollView.documentView?.fittingSize.width ?? 0
            self.widthConstraint = self.scrollView.widthAnchor.constraint(equalToConstant: width)
            self.widthConstraint!.isActive = true
        }
    }
    
    func reloadData() {
        let frontMostAppId = self.frontmostApplicationIdentifier
        items = applications.map { self.createAppButton(for: $0, isFrontmost: $0.bundleIdentifier == frontMostAppId) }
        let stackView = NSStackView(views: items.compactMap { $0.view })
        stackView.spacing = 1
        stackView.orientation = .horizontal
        let visibleRect = self.scrollView.documentVisibleRect
        scrollView.documentView = stackView
        stackView.scroll(visibleRect.origin)
    }

    public func createAppButton(for app: DockItem, isFrontmost: Bool) -> CustomButtonTouchBarItem {
        let item = DockBarItem(app, isRunning: runningAppsIdentifiers.contains(app.bundleIdentifier), isFrontmost: isFrontmost)
        item.isBordered = false
        item.tapClosure = { [weak self] in
            self?.switchToApp(app: app)
        }
        item.longTapClosure = { [weak self] in
            self?.handleHalfLongPress(item: app)
        }
        
        return item
    }
    
    public func switchToApp(app: DockItem) {
        let bundleIdentifier = app.bundleIdentifier
        if bundleIdentifier!.contains("file://") {
            NSWorkspace.shared.openFile(bundleIdentifier!.replacingOccurrences(of: "file://", with: ""))
        } else {
            NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleIdentifier!, options: [.default], additionalEventParamDescriptor: nil, launchIdentifier: nil)
        }
        updateRunningApplication()

        // NB: if you can't open app which on another space, try to check mark
        // "When switching to an application, switch to a Space with open windows for the application"
        // in Mission control settings
    }
    
    //todo
    private func handleLongPress(item: DockItem) {
        if let pid = item.pid, let app = NSRunningApplication(processIdentifier: pid) {
            if !app.terminate() {
                app.forceTerminate()
            }
            updateRunningApplication()
        }
    }
    
    private func handleHalfLongPress(item: DockItem) {
        if let index = self.persistentAppIdentifiers.firstIndex(of: item.bundleIdentifier) {
            persistentAppIdentifiers.remove(at: index)
        } else {
            persistentAppIdentifiers.append(item.bundleIdentifier)
        }

        AppSettings.dockPersistentAppIds = persistentAppIdentifiers
    }
    
    private func launchedApplications() -> [DockItem] {
        runningAppsIdentifiers = []
        var returnable: [DockItem] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == NSApplication.ActivationPolicy.regular else { continue }
            guard let bundleIdentifier = app.bundleIdentifier else { continue }

            runningAppsIdentifiers.append(bundleIdentifier)

            let dockItem = DockItem(bundleIdentifier: bundleIdentifier, icon: app.icon ?? getIcon(forBundleIdentifier: bundleIdentifier), pid: app.processIdentifier)
            returnable.append(dockItem)
        }
        return returnable
    }

    public func getIcon(forBundleIdentifier bundleIdentifier: String? = nil, orPath path: String? = nil) -> NSImage {
        if let bundleIdentifier = bundleIdentifier, let appPath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        if let path = path {
            return NSWorkspace.shared.icon(forFile: path)
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

private let iconWidth = 32.0
class DockBarItem: CustomButtonTouchBarItem {
    
    init(_ app: DockItem, isRunning: Bool, isFrontmost: Bool) {
        super.init(identifier: .init(app.bundleIdentifier), title: "")
        
        image = app.icon
        image?.size = NSSize(width: iconWidth, height: iconWidth)

        let dotColor: NSColor = isRunning ? .white : .black
        self.finishViewConfiguration = { [weak self] in
            let dotView = NSView(frame: .zero)
            dotView.wantsLayer = true
            dotView.layer?.backgroundColor = dotColor.cgColor
            dotView.layer?.cornerRadius = 1.5
            dotView.frame.size = NSSize(width: isFrontmost ? iconWidth - 14 : 3, height: 3)
            self?.view.addSubview(dotView)
            dotView.setFrameOrigin(NSPoint(x: 18.0 - Double(dotView.frame.size.width) / 2.0, y: iconWidth - 5))
        }
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
