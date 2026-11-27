//
//  AppDelegate.swift
//  MTMR
//
//  Created by Anton Palgunov on 16/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa
import ServiceManagement
import Sparkle
import UniformTypeIdentifiers

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var isBlockedApp: Bool = false

    private var fileSystemSource: DispatchSourceFileSystemObject?

    /// Version found by a background update check that the user hasn't looked at yet (shown in the status menu).
    private var pendingUpdateVersion: String?

    // Sparkle 2 API (the bundled framework is Sparkle 2.1.0). SUUpdater is the deprecated Sparkle 1 compat shim.
    // The controller is created un-started so the settings below are applied before the first scheduled check.
    private lazy var updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_: Notification) {
        L10n.configure()
        // Configure Sparkle
        updaterController.updater.automaticallyDownloadsUpdates = false
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.startUpdater()
        updaterController.updater.checkForUpdatesInBackground()

        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true] as NSDictionary)

        TouchBarController.shared.setupControlStripPresence()

        if let button = statusItem.button {
            button.image = #imageLiteral(resourceName: "StatusImage")
        }
        createMenu()

        reloadOnDefaultConfigChanged()

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateIsBlockedApp), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateIsBlockedApp), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateIsBlockedApp), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange(_:)), name: L10n.languageDidChange, object: nil)
    }

    @objc func selectLanguage(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        AppSettings.language = language
    }

    @objc private func languageDidChange(_: Notification) {
        createMenu()
    }

    private func languageMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(title: language.title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = AppSettings.language == language ? .on : .off
            submenu.addItem(item)
            if language == .system { submenu.addItem(NSMenuItem.separator()) }
        }
        let item = NSMenuItem(title: NSLocalizedString("Language", bundle: L10n.bundle, comment: "Status menu: app language submenu"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        CustomizerWindowController.confirmTermination()
    }

    func applicationWillTerminate(_: Notification) {}

    @objc func updateIsBlockedApp() {
        if let frontmostAppId = TouchBarController.shared.frontmostApplicationIdentifier {
            isBlockedApp = AppSettings.blacklistedAppIds.firstIndex(of: frontmostAppId) != nil
        } else {
            isBlockedApp = false
        }
        createMenu()
    }

    @objc func openCustomizer(_: Any?) {
        CustomizerWindowController.shared.show()
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
    }

    @objc func toggleMultitouch(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        AppSettings.multitouchGestures = item.state == .on
        TouchBarController.shared.basicView?.legacyGesturesEnabled = item.state == .on
    }

    @objc func openPreset(_: Any?) {
        let dialog = NSOpenPanel()

        dialog.title = NSLocalizedString("Choose a items.json file", bundle: L10n.bundle, comment: "Open preset panel title")
        dialog.showsResizeIndicator = true
        dialog.showsHiddenFiles = true
        dialog.canChooseDirectories = false
        dialog.canCreateDirectories = false
        dialog.allowsMultipleSelection = false
        dialog.allowedContentTypes = [UTType.json]
        dialog.directoryURL = NSURL.fileURL(withPath: NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR"), isDirectory: true)

        if dialog.runModal() == .OK, let path = dialog.url?.path {
            TouchBarController.shared.reloadPreset(path: path)
        }
    }

    @objc func toggleStartAtLogin(_: Any?) {
        if #available(macOS 13.0, *) {
            // SMAppService replaces the LSSharedFileList login-item API (macOS 13+).
            let service = SMAppService.mainApp
            do {
                switch service.status {
                case .enabled:
                    try service.unregister()
                case .requiresApproval:
                    // Registered but disabled by the user in System Settings: send them there.
                    SMAppService.openSystemSettingsLoginItems()
                default:
                    try service.register()
                }
            } catch {
                NSLog("MTMR: changing launch-at-login failed: \(error)")
            }
        } else {
            // macOS 12 (deployment target): legacy LSSharedFileList controller.
            let controller = LaunchAtLoginController()
            controller.setLaunchAtLogin(!controller.launchAtLogin, for: NSURL.fileURL(withPath: Bundle.main.bundlePath))
        }
        createMenu()
    }

    private var launchAtLoginState: NSControl.StateValue {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return .on
            case .requiresApproval: return .mixed
            default: return .off
            }
        }
        return LaunchAtLoginController().launchAtLogin ? .on : .off
    }

    func createMenu() {
        let menu = NSMenu()

        if let version = pendingUpdateVersion {
            let title = String(format: NSLocalizedString("Install Update %@…", bundle: L10n.bundle, comment: "Status menu; %@ = version"), version)
            let update = NSMenuItem(title: title, action: #selector(showPendingUpdate(_:)), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
            menu.addItem(NSMenuItem.separator())
        }

        let startAtLogin = NSMenuItem(title: NSLocalizedString("Start at login", bundle: L10n.bundle, comment: "Status menu"), action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "L")
        startAtLogin.state = launchAtLoginState

        let toggleBlackList = NSMenuItem(title: NSLocalizedString("Toggle current app in blacklist", bundle: L10n.bundle, comment: "Status menu"), action: #selector(toggleBlackListedApp(_:)), keyEquivalent: "B")
        toggleBlackList.state = isBlockedApp ? .on : .off

        let hideControlStrip = NSMenuItem(title: NSLocalizedString("Hide Control Strip", bundle: L10n.bundle, comment: "Status menu"), action: #selector(toggleControlStrip(_:)), keyEquivalent: "T")
        hideControlStrip.state = AppSettings.showControlStripState ? .off : .on

        let hapticFeedback = NSMenuItem(title: NSLocalizedString("Haptic Feedback", bundle: L10n.bundle, comment: "Status menu"), action: #selector(toggleHapticFeedback(_:)), keyEquivalent: "H")
        hapticFeedback.state = AppSettings.hapticFeedbackState ? .on : .off

        let multitouchGestures = NSMenuItem(title: NSLocalizedString("Volume/Brightness gestures", bundle: L10n.bundle, comment: "Status menu"), action: #selector(toggleMultitouch(_:)), keyEquivalent: "")
        multitouchGestures.state = AppSettings.multitouchGestures ? .on : .off

        let settingSeparator = NSMenuItem(title: NSLocalizedString("Settings", bundle: L10n.bundle, comment: "Status menu section header"), action: nil, keyEquivalent: "")
        settingSeparator.isEnabled = false

        menu.addItem(withTitle: NSLocalizedString("Customize Touch Bar…", bundle: L10n.bundle, comment: "Status menu"), action: #selector(openCustomizer(_:)), keyEquivalent: ",")
        menu.addItem(withTitle: NSLocalizedString("Edit Preset File…", bundle: L10n.bundle, comment: "Status menu"), action: #selector(openPreferences(_:)), keyEquivalent: "")
        menu.addItem(withTitle: NSLocalizedString("Open preset", bundle: L10n.bundle, comment: "Status menu"), action: #selector(openPreset(_:)), keyEquivalent: "O")
        menu.addItem(withTitle: NSLocalizedString("Check for Updates...", bundle: L10n.bundle, comment: "Status menu"), action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "").target = updaterController

        menu.addItem(NSMenuItem.separator())
        menu.addItem(settingSeparator)
        menu.addItem(hapticFeedback)
        menu.addItem(hideControlStrip)
        menu.addItem(toggleBlackList)
        menu.addItem(startAtLogin)
        menu.addItem(multitouchGestures)
        menu.addItem(languageMenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: NSLocalizedString("Quit", bundle: L10n.bundle, comment: "Status menu"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func reloadOnDefaultConfigChanged() {
        let file = NSURL.fileURL(withPath: standardConfigPath)

        let fd = open(file.path, O_EVTONLY)

        fileSystemSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: DispatchQueue(label: "DefaultConfigChanged"))

        fileSystemSource?.setEventHandler(handler: {
            print("Config changed, reloading...")
            DispatchQueue.main.async {
                TouchBarController.shared.scheduleReload(path: file.path)
            }
        })

        fileSystemSource?.setCancelHandler(handler: {
            close(fd)
        })

        fileSystemSource?.resume()
    }
}

extension AppDelegate: SPUUpdaterDelegate {
    // MTMR is a menu-bar (LSUIElement) app. When a *background* check finds an update, Sparkle 2.1 tries to
    // activate the app and otherwise waits for it to become active before showing its window. Modern macOS
    // refuses activation that isn't triggered by the user, so the window would never appear. Surface the
    // update in the status menu instead; clicking it is a user action, so activation is allowed there.
    func updater(_: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        pendingUpdateVersion = item.displayVersionString
        createMenu()
    }

    func updaterDidNotFindUpdate(_: SPUUpdater) {
        guard pendingUpdateVersion != nil else { return }
        pendingUpdateVersion = nil
        createMenu()
    }

    @objc func showPendingUpdate(_ sender: Any?) {
        pendingUpdateVersion = nil
        createMenu()
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(sender)
    }
}
