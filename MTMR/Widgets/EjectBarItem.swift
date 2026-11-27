//
//  EjectBarItem.swift
//  MTMR
//
//  Button that ejects chosen external drives and disk images, like the eject entries in Finder's sidebar.
//

import AppKit

class EjectBarItem: CustomButtonTouchBarItem {
    private let volumes: [String]
    private var isBusy = false
    private var showsFailure = false
    private var observers: [NSObjectProtocol] = []

    /// `volumes`: volume names as shown in Finder. Empty ejects every external volume.
    init(identifier: NSTouchBarItem.Identifier, volumes: [String]) {
        self.volumes = volumes.filter { !$0.isEmpty }
        super.init(identifier: identifier, title: "")
        isBordered = false
        setWidth(value: 32)

        actions.append(ItemAction(trigger: .singleTap) { [weak self] in self?.eject() })

        // Mount notifications instead of polling: they also cover drives plugged in or ejected in Finder.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        refresh()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private var hasSomethingToEject: Bool {
        let mounted = VolumeEjector.mountedVolumes()
        return volumes.isEmpty ? !mounted.isEmpty : mounted.contains { volumes.contains($0.name) }
    }

    func eject() {
        guard !isBusy else { return }
        isBusy = true
        refresh()
        VolumeEjector.eject(names: volumes) { [weak self] outcome in
            guard let self = self else { return }
            self.isBusy = false
            if case let .failed(volume, error, ejected) = outcome {
                self.reportFailure(volume: volume, error: error, ejected: ejected)
            }
            self.refresh()
        }
    }

    /// A drive that stays mounted must not look ejected: someone might pull the cable. The icon turns red and an
    /// alert names the drive and the reason (usually an app with an open file), because the Touch Bar alone
    /// cannot show why.
    ///
    /// When diskutil names the process that keeps the drive busy, the alert offers to quit it and eject again.
    /// Only on the user's click in this alert, never by itself: quitting a program is the user's call. "OK" stays
    /// the default button, so Return never quits anything.
    private func reportFailure(volume: String, error: Error, ejected: [String]) {
        showsFailure = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.showsFailure = false
            self?.refresh()
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\"\(volume)\" was not ejected"
        var info = error.localizedDescription
        if !ejected.isEmpty {
            info += "\n\nAlready ejected: " + ejected.joined(separator: ", ")
        }
        let blocker = VolumeEjector.blocker(in: error.localizedDescription).flatMap { VolumeEjector.mayQuit($0) ? $0 : nil }
        alert.addButton(withTitle: "OK")
        if let blocker = blocker {
            let origin = blocker.appName.map { ", started by \($0)," } ?? ""
            info += "\n\nQuitting \"\(blocker.name)\"\(origin) ends what it is doing; unsaved work in it may be lost."
            alert.addButton(withTitle: "Quit \"\(blocker.name)\" and Eject").hasDestructiveAction = true
        }
        alert.informativeText = info
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn, let blocker = blocker {
            quitAndEject(blocker)
        }
    }

    private func quitAndEject(_ blocker: VolumeEjector.Blocker) {
        showsFailure = false
        isBusy = true
        refresh()
        DispatchQueue.global(qos: .userInitiated).async {
            let quit = VolumeEjector.quit(blocker)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isBusy = false
                if quit {
                    self.eject()
                } else {
                    self.refresh()
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "\"\(blocker.name)\" did not quit"
                    alert.informativeText = "Nothing was ejected. Quit it yourself, then press the eject button again."
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
        }
    }

    func refresh() {
        // Once none of the chosen drives is mounted any more (ejected, or unplugged), a checkmark says that
        // they can be unplugged safely. Busy keeps the eject glyph, dimmed, so the check appears only when done.
        let done = !isBusy && !showsFailure && !hasSomethingToEject
        let icon = IconLibrary.image(
            named: done ? "eject-done" : "eject",
            fallback: NSImage(named: done ? NSImage.menuOnStateTemplateName : NSImage.touchBarGoUpTemplateName)
        )
        guard let base = icon else { return }
        if showsFailure {
            image = IconLibrary.tinted(base, color: .systemRed)
        } else if isBusy {
            // Dimmed while ejecting, so a second tap visibly does nothing.
            image = IconLibrary.tinted(base, color: NSColor(white: 1, alpha: 0.4))
        } else {
            image = base
        }
    }
}
