//
//  CustomizerWindowController.swift
//  MTMR
//
//  Hosts the SwiftUI customizer in a regular window. MTMR is an LSUIElement agent, so the window
//  has to activate the app explicitly when it is shown.
//

import Combine
import SwiftUI

final class CustomizerWindowController: NSWindowController, NSWindowDelegate {
    static let shared = CustomizerWindowController()

    private let preset = PresetDocument()
    private let state = CustomizerState()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        preset.load()
        // Saving rewrites the file in place; the explicit reload makes the Touch Bar update without waiting for the file watcher.
        preset.onSaved = { [preset] in
            TouchBarController.shared.scheduleReload(path: preset.fileURL.path)
        }

        window.title = "Customize Touch Bar"
        window.contentViewController = NSHostingController(rootView: CustomizerView(document: preset, state: state))
        window.contentMinSize = NSSize(width: 900, height: 560)
        window.setContentSize(NSSize(width: 1000, height: 680))
        window.center()
        // Set after sizing so a stored frame from a previous run wins over the defaults.
        window.setFrameAutosaveName("CustomizerWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self

        preset.$isDirty
            .receive(on: DispatchQueue.main)
            .sink { [weak window] dirty in window?.isDocumentEdited = dirty }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        // Pick up edits made to the file in the meantime, but never throw away unsaved work.
        if !preset.isDirty { preset.load() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard preset.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to your Touch Bar?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self = self else { return }
            switch response {
            case .alertFirstButtonReturn:
                // On failure stay open: the error banner explains what to fix.
                self.state.errorMessage = self.preset.saveReportingError()
                if self.state.errorMessage == nil { sender.close() }
            case .alertSecondButtonReturn:
                self.preset.revert()
                sender.close()
            default:
                break
            }
        }
        return false
    }
}
