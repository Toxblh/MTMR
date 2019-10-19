//
//  AppDelegate.swift
//  MTMR
//
//  Created by Anton Palgunov on 16/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa
import Sparkle

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var isBlockedApp: Bool = false

    private var fileSystemSource: DispatchSourceFileSystemObject?

    func applicationDidFinishLaunching(_: Notification) {
        // Configure Sparkle
        SUUpdater.shared().automaticallyDownloadsUpdates = false
        SUUpdater.shared().automaticallyChecksForUpdates = true
        SUUpdater.shared().checkForUpdatesInBackground()

        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true] as NSDictionary)

        TouchBarController.shared.setupControlStripPresence()
        HapticFeedbackUpdate()

        if let button = statusItem.button {
            button.image = #imageLiteral(resourceName: "StatusImage")
        }
        createMenu()

        reloadOnDefaultConfigChanged()

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateIsBlockedApp), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateIsBlockedApp), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateIsBlockedApp), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func applicationWillTerminate(_: Notification) {}

    func HapticFeedbackUpdate() {
        HapticFeedback.shared = AppSettings.hapticFeedbackState ? HapticFeedback() : nil
    }

    @objc func updateIsBlockedApp() {
        if let frontmostAppId = TouchBarController.shared.frontmostApplicationIdentifier {
            isBlockedApp = AppSettings.blacklistedAppIds.firstIndex(of: frontmostAppId) != nil
        } else {
            isBlockedApp = false
        }
        createMenu()
    }

    @objc func openPreferences(_: Any?) {
        let task = Process()
        let appSupportDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR")
        let presetPath = appSupportDirectory.appending("/items.json")
        task.launchPath = "/usr/bin/open"
        task.arguments = [presetPath]
        task.launch()
    }

    @objc func toggleControlStrip(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        AppSettings.showControlStripState = item.state == .off
        TouchBarController.shared.resetControlStrip()
    }

    @objc func toggleBlackListedApp(_: Any?) {
        if let appIdentifier = TouchBarController.shared.frontmostApplicationIdentifier {
            if let index = TouchBarController.shared.blacklistAppIdentifiers.firstIndex(of: appIdentifier) {
                TouchBarController.shared.blacklistAppIdentifiers.remove(at: index)
            } else {
                TouchBarController.shared.blacklistAppIdentifiers.append(appIdentifier)
            }
            
            AppSettings.blacklistedAppIds = TouchBarController.shared.blacklistAppIdentifiers
            TouchBarController.shared.updateActiveApp()
            updateIsBlockedApp()
        }
    }

    @objc func toggleHapticFeedback(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        AppSettings.hapticFeedbackState = item.state == .on
        HapticFeedbackUpdate()
    }

    @objc func toggleMultitouch(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        AppSettings.multitouchGestures = item.state == .on
        TouchBarController.shared.scrollArea?.gesturesEnabled = item.state == .on
    }

    @objc func openPreset(_: Any?) {
        let dialog = NSOpenPanel()

        dialog.title = "Choose a items.json file"
        dialog.showsResizeIndicator = true
        dialog.showsHiddenFiles = true
        dialog.canChooseDirectories = false
        dialog.canCreateDirectories = false
        dialog.allowsMultipleSelection = false
        dialog.allowedFileTypes = ["json"]
        dialog.directoryURL = NSURL.fileURL(withPath: NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR"), isDirectory: true)

        if dialog.runModal() == .OK, let path = dialog.url?.path {
            TouchBarController.shared.reloadPreset(path: path)
        }
    }

    @objc func toggleStartAtLogin(_: Any?) {
        LaunchAtLoginController().setLaunchAtLogin(!LaunchAtLoginController().launchAtLogin, for: NSURL.fileURL(withPath: Bundle.main.bundlePath))
        createMenu()
    }

    func createMenu() {
        let menu = NSMenu()

        let startAtLogin = NSMenuItem(title: "Start at login", action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "L")
        startAtLogin.state = LaunchAtLoginController().launchAtLogin ? .on : .off

        let toggleBlackList = NSMenuItem(title: "Toggle current app in blacklist", action: #selector(toggleBlackListedApp(_:)), keyEquivalent: "B")
        toggleBlackList.state = isBlockedApp ? .on : .off

        let hideControlStrip = NSMenuItem(title: "Hide Control Strip", action: #selector(toggleControlStrip(_:)), keyEquivalent: "T")
        hideControlStrip.state = AppSettings.showControlStripState ? .off : .on

        let hapticFeedback = NSMenuItem(title: "Haptic Feedback", action: #selector(toggleHapticFeedback(_:)), keyEquivalent: "H")
        hapticFeedback.state = AppSettings.hapticFeedbackState ? .on : .off

        let multitouchGestures = NSMenuItem(title: "Volume/Brightness gestures", action: #selector(toggleMultitouch(_:)), keyEquivalent: "")
        multitouchGestures.state = AppSettings.multitouchGestures ? .on : .off

        let settingSeparator = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingSeparator.isEnabled = false

        menu.addItem(withTitle: "Preferences", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        menu.addItem(withTitle: "Open preset", action: #selector(openPreset(_:)), keyEquivalent: "O")
        menu.addItem(withTitle: "Check for Updates...", action: #selector(SUUpdater.checkForUpdates(_:)), keyEquivalent: "").target = SUUpdater.shared()

        menu.addItem(NSMenuItem.separator())
        menu.addItem(settingSeparator)
        menu.addItem(hapticFeedback)
        menu.addItem(hideControlStrip)
        menu.addItem(toggleBlackList)
        menu.addItem(startAtLogin)
        menu.addItem(multitouchGestures)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func reloadOnDefaultConfigChanged() {
        let file = NSURL.fileURL(withPath: standardConfigPath)

        let fd = open(file.path, O_EVTONLY)

        fileSystemSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: DispatchQueue(label: "DefaultConfigChanged"))

        fileSystemSource?.setEventHandler(handler: {
            print("Config changed, reloading...")
            DispatchQueue.main.async {
                TouchBarController.shared.reloadPreset(path: file.path)
            }
        })

        fileSystemSource?.setCancelHandler(handler: {
            close(fd)
        })

        fileSystemSource?.resume()
    }
}
