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
    private let filter: NSRegularExpression?

    private var persistentAppIdentifiers: [String] = []
    private var runningAppsIdentifiers: [String] = []

    private var frontmostApplicationIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private var applications: [DockItem] = []
    private var items: [DockBarItem] = []

    init(identifier: NSTouchBarItem.Identifier, autoResize: Bool = false, filter: NSRegularExpression? = nil) {
        self.filter = filter
        super.init(identifier: identifier)
        self.autoResize = autoResize
        view = scrollView

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hardReloadItems), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hardReloadItems), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(softReloadItems), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        persistentAppIdentifiers = AppSettings.dockPersistentAppIds
        hardReloadItems()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func hardReloadItems() {
        applications = launchedApplications()
        applications += getDockPersistentAppsList()
        reloadData()
        softReloadItems()
        updateSize()
    }
    
    @objc func softReloadItems() {
        let frontMostAppId = self.frontmostApplicationIdentifier
        let runningAppsIds = NSWorkspace.shared.runningApplications.map { $0.bundleIdentifier }
        for barItem in items {
            let bundleId = barItem.dockItem.bundleIdentifier
            barItem.isRunning = runningAppsIds.contains(bundleId)
            barItem.isFrontmost = frontMostAppId == bundleId
        }
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
        items = applications.map { self.createAppButton(for: $0) }
        let stackView = NSStackView(views: items.compactMap { $0.view })
        stackView.spacing = 1
        stackView.orientation = .horizontal
        let visibleRect = self.scrollView.documentVisibleRect
        scrollView.documentView = stackView
        stackView.scroll(visibleRect.origin)
    }

    public func createAppButton(for app: DockItem) -> DockBarItem {
        let item = DockBarItem(app)
        item.isBordered = false
        item.tapClosure = { [weak self] in
            self?.switchToApp(app: app)
        }
        item.longTapClosure = { [weak self] in
            self?.handleHalfLongPress(item: app)
        }
        item.killAppClosure = {[weak self] in
            self?.handleLongPress(item: app)
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
        softReloadItems()

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
            hardReloadItems()
        }
    }
    
    private func handleHalfLongPress(item: DockItem) {
        if let index = self.persistentAppIdentifiers.firstIndex(of: item.bundleIdentifier) {
            persistentAppIdentifiers.remove(at: index)
            hardReloadItems()
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
            if let filter = self.filter,
                let name = app.localizedName,
                filter.numberOfMatches(in: name, options: [], range: NSRange(location: 0, length: name.count)) == 0 {
                continue
            }
            
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
    let dotView = NSView(frame: .zero)
    let dockItem: DockItem
    fileprivate var killGestureRecognizer: LongPressGestureRecognizer!
    var killAppClosure: () -> Void = { }
    
    var isRunning = false {
        didSet {
            redrawDotView()
        }
    }
    
    var isFrontmost = false {
        didSet {
            redrawDotView()
        }
    }
    
    init(_ app: DockItem) {
        self.dockItem = app
        super.init(identifier: .init(app.bundleIdentifier), title: "")
        dotView.wantsLayer = true
        
        image = app.icon
        image?.size = NSSize(width: iconWidth, height: iconWidth)

        killGestureRecognizer = LongPressGestureRecognizer(target: self, action: #selector(firePanGestureRecognizer))
        killGestureRecognizer.allowedTouchTypes = .direct
        killGestureRecognizer.recognizeTimeout = 1.5
        killGestureRecognizer.minimumPressDuration = 1.5
        killGestureRecognizer.isEnabled = isRunning
        
        self.finishViewConfiguration = { [weak self] in
            guard let selfie = self else { return }
            selfie.dotView.layer?.cornerRadius = 1.5
            selfie.view.addSubview(selfie.dotView)
            selfie.redrawDotView()
            selfie.view.addGestureRecognizer(selfie.killGestureRecognizer)
        }
    }
    
    func redrawDotView() {
        dotView.layer?.backgroundColor = isRunning ? NSColor.white.cgColor : NSColor.clear.cgColor
        dotView.frame.size = NSSize(width: isFrontmost ? iconWidth - 14 : 3, height: 3)
        dotView.setFrameOrigin(NSPoint(x: 18.0 - Double(dotView.frame.size.width) / 2.0, y: iconWidth - 5))
    }
    
    @objc func firePanGestureRecognizer() {
        self.killAppClosure()
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
