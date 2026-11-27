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
    static let shared: CustomizerWindowController = {
        isCreated = true
        return CustomizerWindowController()
    }()
    /// Set once `shared` exists, so quitting can skip the check without creating the window.
    private(set) static var isCreated = false

    private let preset: PresetDocument
    private let state: CustomizerState
    private var cancellables = Set<AnyCancellable>()

    init(preset: PresetDocument = PresetDocument(), state: CustomizerState? = nil) {
        self.preset = preset
        self.state = state ?? CustomizerState()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        // Saving rewrites the file in place; the explicit reload makes the Touch Bar update without waiting for the file watcher.
        preset.onSaved = { [preset] in
            TouchBarController.shared.scheduleReload(path: preset.fileURL.path)
        }

        window.title = NSLocalizedString("Customize Touch Bar", bundle: L10n.bundle, comment: "Customizer window title")
        window.contentViewController = makeContentController()
        window.contentMinSize = NSSize(width: 900, height: 560)
        window.setContentSize(NSSize(width: 1000, height: 680))
        window.center()
        // Set after sizing so a stored frame from a previous run wins over the defaults.
        window.setFrameAutosaveName("CustomizerWindow")
        window.isReleasedWhenClosed = false
        NotificationCenter.default.publisher(for: L10n.languageDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.languageDidChange() }
            .store(in: &cancellables)
        window.delegate = self

        preset.$isDirty
            .receive(on: DispatchQueue.main)
            .sink { [weak window] dirty in window?.isDocumentEdited = dirty }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

    private func makeContentController() -> NSViewController {
        NSHostingController(rootView: CustomizerView(document: preset, state: state).appLocalized())
    }

    func show() {
        // Pick up edits made to the file in the meantime, but never throw away unsaved work.
        if !preset.isDirty { preset.load() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Quitting

    /// Asked by AppDelegate.applicationShouldTerminate. Unsaved edits get the same Save / Don't Save /
    /// Cancel choice as closing the window; quitting from the status menu used to discard them silently.
    static func confirmTermination() -> NSApplication.TerminateReply {
        guard isCreated else { return .terminateNow }
        return shared.confirmTermination()
    }

    private func confirmTermination() -> NSApplication.TerminateReply {
        guard preset.isDirty else { return .terminateNow }
        show()

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Do you want to save the changes to your Touch Bar before quitting?", bundle: L10n.bundle, comment: "Quit alert")
        alert.informativeText = NSLocalizedString("Your changes will be lost if you don’t save them.", bundle: L10n.bundle, comment: "Unsaved changes alert")
        alert.addButton(withTitle: NSLocalizedString("Save", bundle: L10n.bundle, comment: "Alert button"))
        alert.addButton(withTitle: NSLocalizedString("Don’t Save", bundle: L10n.bundle, comment: "Alert button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", bundle: L10n.bundle, comment: "Alert button"))
        // App-modal rather than a sheet: termination needs a synchronous answer.
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // On failure stay running: the error banner explains what to fix.
            state.errorMessage = preset.saveReportingError()
            return state.errorMessage == nil ? .terminateNow : .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard preset.isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Do you want to save the changes to your Touch Bar?", bundle: L10n.bundle, comment: "Close window alert")
        alert.informativeText = NSLocalizedString("Your changes will be lost if you don’t save them.", bundle: L10n.bundle, comment: "Unsaved changes alert")
        alert.addButton(withTitle: NSLocalizedString("Save", bundle: L10n.bundle, comment: "Alert button"))
        alert.addButton(withTitle: NSLocalizedString("Don’t Save", bundle: L10n.bundle, comment: "Alert button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", bundle: L10n.bundle, comment: "Alert button"))
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

    private func languageDidChange() {
        guard let window else { return }
        let frame = window.frame
        window.title = NSLocalizedString("Customize Touch Bar", bundle: L10n.bundle, comment: "Customizer window title")
        window.contentViewController = makeContentController()
        window.setFrame(frame, display: true)
        if preset.loadError != nil && !state.hasDraft(in: preset) { preset.load() }
    }
}
