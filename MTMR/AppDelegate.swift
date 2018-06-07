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
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    private var fileSystemSource: DispatchSourceFileSystemObject?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        TouchBarController.shared.setupControlStripPresence()
        
        if let button = statusItem.button {
            button.image = #imageLiteral(resourceName: "StatusImage")
        }
        createMenu()
        
        reloadOnDefaultConfigChanged()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        
    }
    
    @objc func openPreferences(_ sender: Any?) {
        let task = Process()
        let appSupportDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR")
        let presetPath = appSupportDirectory.appending("/items.json")
        task.launchPath = "/usr/bin/open"
        task.arguments = [presetPath]
        task.launch()
    }
    
    @objc func toggleControlStrip(_ sender: Any?) {
        TouchBarController.shared.controlStripState = !TouchBarController.shared.controlStripState
        createMenu()
        TouchBarController.shared.resetControlStrip()
    }
    
    @objc func toggleBlackListedApp(_ sender: Any?) {
        let appIdentifier = TouchBarController.shared.frontmostApplicationIdentifier
        if appIdentifier != nil {
            if let index = TouchBarController.shared.blacklistAppIdentifiers.index(of: appIdentifier!) {
                TouchBarController.shared.blacklistAppIdentifiers.remove(at: index)
            } else {
                TouchBarController.shared.blacklistAppIdentifiers.append(appIdentifier!)
            }
            
            UserDefaults.standard.set(TouchBarController.shared.blacklistAppIdentifiers, forKey: "com.toxblh.mtmr.blackListedApps")
            UserDefaults.standard.synchronize()
            
            TouchBarController.shared.updateActiveApp()
        }
    }
    
    @objc func openPreset(_ sender: Any?) {
        let dialog = NSOpenPanel();
        
        dialog.title                   = "Choose a items.json file"
        dialog.showsResizeIndicator    = true
        dialog.showsHiddenFiles        = true
        dialog.canChooseDirectories    = false
        dialog.canCreateDirectories    = false
        dialog.allowsMultipleSelection = false
        dialog.allowedFileTypes        = ["json"]
        dialog.directoryURL = NSURL.fileURL(withPath: NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first!.appending("/MTMR"), isDirectory: true)
        
        if dialog.runModal() == .OK, let path = dialog.url?.path {
            TouchBarController.shared.reloadPreset(path: path)
        }
    }
    
    @objc func toggleStartAtLogin(_ sender: Any?) {
        LaunchAtLoginController().setLaunchAtLogin(!LaunchAtLoginController().launchAtLogin, for: NSURL.fileURL(withPath: Bundle.main.bundlePath))
        createMenu()
    }
    
    func createMenu() {
        let menu = NSMenu()
        
        let startAtLogin = NSMenuItem(title: "Start at login", action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "L")
        startAtLogin.state = LaunchAtLoginController().launchAtLogin ? .on : .off
        
        let hideControlStrip = NSMenuItem(title: "Hide Control Strip", action: #selector(toggleControlStrip(_:)), keyEquivalent: "T")
        hideControlStrip.state = TouchBarController.shared.controlStripState ? .on : .off
        
        let settingSeparator = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingSeparator.isEnabled = false
       
        menu.addItem(withTitle: "Preferences", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        menu.addItem(withTitle: "Open preset", action: #selector(openPreset(_:)), keyEquivalent: "O")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(settingSeparator)
        menu.addItem(hideControlStrip)
        menu.addItem(withTitle: "Toggle current app in blacklist" , action: #selector(toggleBlackListedApp(_:)), keyEquivalent: "B")
        menu.addItem(startAtLogin)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func reloadOnDefaultConfigChanged() {
        let file = NSURL.fileURL(withPath: standardConfigPath)
        
        let fd = open(file.path, O_EVTONLY)
        
        self.fileSystemSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: DispatchQueue(label: "DefaultConfigChanged"))
        
        self.fileSystemSource?.setEventHandler(handler: {
            print("Config changed, reloading...")
            DispatchQueue.main.async {
                TouchBarController.shared.reloadPreset(path: file.path)
            }
        })
        
        self.fileSystemSource?.setCancelHandler(handler: {
            close(fd)
        })
        
        self.fileSystemSource?.resume()
    }
}

