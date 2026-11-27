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
    private var runtimeSubscription: AnyCancellable?
    private var lastHardwarePath: [Int] = []
    private var runtime: RunningTouchBar { state.previewRuntime ?? TouchBarController.shared }

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
        preset.onSaved = { [weak self] in
            if let self { self.runtime.scheduleReload(path: self.preset.fileURL.path) }
        }

        window.title = NSLocalizedString("Customize Touch Bar", bundle: L10n.bundle, comment: "Customizer window title")
        window.contentViewController = makeContentController()
        window.contentMinSize = NSSize(width: 900, height: 560)
        window.setContentSize(NSSize(width: 1200, height: 700))
        window.center()
        self.state.revertPreset = { [weak self] _ in self?.revertPreset() }
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

    private func makeContentController() -> NSViewController {
        NSHostingController(rootView: CustomizerView(document: preset, state: state).appLocalized())
    }

    func show() {
        let opening = window?.isVisible != true
        startPreview(opening: opening)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func startPreview(opening: Bool) {
        guard runtimeSubscription == nil else { return }
        let runtime = self.runtime
        state.previewRuntime = runtime
        runtimeSubscription = runtime.layoutChanges.sink { [weak self] in self?.syncRuntime(opening: false) }
        syncRuntime(opening: opening)
        state.previewActive = true
    }

    private func syncRuntime(opening: Bool, discardingEdits: Bool = false) {
        guard !runtime.isReloadPending || discardingEdits else {
            state.objectWillChange.send()
            return
        }
        let url = runtime.presetURL
        let otherFile = url.standardizedFileURL != preset.fileURL.standardizedFileURL
        let revision = runtime.appliedRevision
        let changed = revision.map { $0 != preset.savedRevision } ?? false
        let hasDraft = state.hasDraft(in: preset)
        let wasFollowing = state.groupPath.isEmpty ? lastHardwarePath.isEmpty :
            state.groupPath.last.flatMap { preset.livePath(for: $0, revision: preset.savedRevision) } == lastHardwarePath
        if discardingEdits || (!hasDraft && (opening || otherFile || changed)) {
            preset.load(from: url)
            state.selection = nil
            state.groupPath = []
        }
        let notice: RunningPresetNotice?
        if runtime.isReloadPending {
            notice = nil
        } else if revision == nil {
            notice = .loadFailed
        } else if !discardingEdits && hasDraft && (otherFile || changed) {
            notice = .differentRevision
        } else {
            notice = nil
        }
        if state.presetNotice != notice { state.presetNotice = notice }
        let path = runtime.presentedGroupPath
        if opening || discardingEdits || (wasFollowing && path != lastHardwarePath) {
            if !path.isEmpty, let group = preset.item(at: path),
               preset.livePath(for: group.id, revision: runtime.appliedRevision) == path {
                state.enterGroup(group.id, in: preset)
            } else if path.isEmpty { state.backToMain() }
        }
        lastHardwarePath = path
        state.objectWillChange.send()
    }

    func revertPreset() {
        state.errorMessage = nil
        syncRuntime(opening: false, discardingEdits: true)
    }

    private func stopPreview() {
        runtimeSubscription?.cancel()
        runtimeSubscription = nil
        state.previewActive = false
        state.strip?.disconnect()
    }

    func windowWillClose(_ notification: Notification) { stopPreview() }
    func windowDidMiniaturize(_ notification: Notification) { stopPreview() }
    func windowDidDeminiaturize(_ notification: Notification) { startPreview(opening: false) }

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
        alert.messageText = "Do you want to save the changes to your Touch Bar before quitting?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
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
