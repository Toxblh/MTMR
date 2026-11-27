//
//  DoNotDisturb.swift
//  MTMR
//

import AppKit
import CoreGraphics
import Foundation

public struct DoNotDisturb {
    static let didChangeNotification = Notification.Name("com.toxblh.mtmr.dndDidChange")

    static func startObserving() {
        StateTracker.shared.start()
    }

    static func toggle() {
        StateTracker.shared.start()
        HotKeyToggler.toggle()
    }

    static var isEnabled: Bool {
        StateTracker.shared.start()
        return StateTracker.shared.isEnabled
    }

    /// Parses macOS Focus `~/Library/DoNotDisturb/DB/Assertions.json`.
    /// Returns `nil` when the payload does not match the expected structure.
    static func parseAssertionsJSON(_ data: Data) -> Bool? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else {
            return nil
        }
        return entries.contains { entry in
            guard let records = entry["storeAssertionRecords"] as? [Any] else { return false }
            return !records.isEmpty
        }
    }

    /// Interprets `com.apple.controlcenter` Focus menu bar defaults into a Focus state when unambiguous.
    /// - `focusModesSetting == 2` ("Always Show in Menu Bar"): status item is always visible even when Focus is off.
    /// - `focusModesSetting == 8` ("Don't Show in Menu Bar"): status item is always hidden even when Focus is on.
    /// - Otherwise ("Show When Active", e.g. 18 or unset): status item visibility mirrors active Focus state.
    static func interpretControlCenterState(focusModesSetting: Int?, statusItemVisible: Bool?) -> Bool? {
        guard let visible = statusItemVisible else { return nil }
        switch focusModesSetting {
        case 2, 8:
            return nil
        default:
            return visible
        }
    }

    private final class StateTracker {
        static let shared = StateTracker()

        private static let enabledNotification = Notification.Name("_NSDoNotDisturbEnabledNotification")
        private static let disabledNotification = Notification.Name("_NSDoNotDisturbDisabledNotification")
        private static let controlCenterAppID = "com.apple.controlcenter" as CFString
        private static let assertionsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

        private let lock = NSLock()
        private var started = false
        private var _isEnabled = false

        var isEnabled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _isEnabled
        }

        func start() {
            lock.lock()
            if started {
                lock.unlock()
                return
            }
            started = true
            _isEnabled = Self.probeCurrentState() ?? false
            lock.unlock()

            let distributed = DistributedNotificationCenter.default()
            distributed.addObserver(
                forName: Self.enabledNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateState(true)
            }
            distributed.addObserver(
                forName: Self.disabledNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateState(false)
            }
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                if let probed = Self.probeCurrentState() {
                    self?.updateState(probed)
                }
            }
        }

        private func updateState(_ value: Bool) {
            lock.lock()
            let changed = (_isEnabled != value)
            _isEnabled = value
            lock.unlock()

            if changed {
                NotificationCenter.default.post(name: DoNotDisturb.didChangeNotification, object: nil)
            }
        }

        /// Best-effort synchronous probe for Focus/DND state before a distributed notification arrives or after wake.
        private static func probeCurrentState() -> Bool? {
            // 1. Authoritative Focus DB (readable when Full Disk Access is granted).
            if let data = try? Data(contentsOf: assertionsURL),
               let active = DoNotDisturb.parseAssertionsJSON(data) {
                return active
            }

            // 2. Control Center status-item visibility (works without FDA when Focus is set to "Show When Active").
            CFPreferencesAppSynchronize(controlCenterAppID)
            let setting = (CFPreferencesCopyAppValue("FocusModes" as CFString, controlCenterAppID) as? NSNumber)?.intValue
            let visible = (CFPreferencesCopyAppValue("NSStatusItem Visible FocusModes" as CFString, controlCenterAppID) as? NSNumber)?.boolValue
            return DoNotDisturb.interpretControlCenterState(focusModesSetting: setting, statusItemVisible: visible)
        }
    }

    /// Toggles macOS Do Not Disturb via System Symbolic HotKey 175 ("Turn Do Not Disturb On/Off").
    /// If the user already configured HotKey 175, its exact key chord is posted directly.
    /// Otherwise, HotKey 175 is temporarily bound in-memory to an unused F19 chord, triggered, and restored.
    enum HotKeyToggler {
        private static let dndSymbolicHotKeyID: Int32 = 175
        private static let unboundKeyCode: UInt16 = 0xFFFF
        private static let restoreDelay: TimeInterval = 0.15

        struct Binding: Equatable {
            var equivalent: UInt16
            var keyCode: UInt16
            var modifiers: UInt32
        }

        // F19 with SecondaryFn (required for F-keys) + Cmd + Opt + Ctrl + Shift.
        private static let temporaryBinding = Binding(equivalent: 0xFFFF, keyCode: 80, modifiers: 0x800000 | 0x1E0000)

        private static let queue = DispatchQueue(label: "com.toxblh.mtmr.dnd.toggle", qos: .userInteractive)

        private typealias IsEnabledFn = @convention(c) (Int32) -> Bool
        private typealias SetEnabledFn = @convention(c) (Int32, Bool) -> Int32
        private typealias GetValueFn = @convention(c) (Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>) -> Int32
        private typealias SetValueFn = @convention(c) (Int32, UInt16, UInt16, UInt32) -> Int32

        private struct CGSFunctions {
            let isEnabled: IsEnabledFn
            let setEnabled: SetEnabledFn
            let getValue: GetValueFn
            let setValue: SetValueFn
        }

        private static let cgs: CGSFunctions? = {
            let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
                ?? dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
            guard let handle,
                  let isEn = dlsym(handle, "CGSIsSymbolicHotKeyEnabled"),
                  let setEn = dlsym(handle, "CGSSetSymbolicHotKeyEnabled"),
                  let getVal = dlsym(handle, "CGSGetSymbolicHotKeyValue"),
                  let setVal = dlsym(handle, "CGSSetSymbolicHotKeyValue") else {
                return nil
            }
            return CGSFunctions(
                isEnabled: unsafeBitCast(isEn, to: IsEnabledFn.self),
                setEnabled: unsafeBitCast(setEn, to: SetEnabledFn.self),
                getValue: unsafeBitCast(getVal, to: GetValueFn.self),
                setValue: unsafeBitCast(setVal, to: SetValueFn.self)
            )
        }()

        static func toggle() {
            queue.async {
                performToggle()
            }
        }

        private static func performToggle() {
            guard AXIsProcessTrusted() else {
                NSLog("MTMR: toggling Do Not Disturb requires Accessibility permission")
                return
            }
            guard let cgs else {
                NSLog("MTMR: failed to resolve CGS symbolic hotkey functions for Do Not Disturb")
                return
            }

            let id = dndSymbolicHotKeyID
            performToggle(
                read: {
                    var equivalent: UInt16 = 0
                    var keyCode = unboundKeyCode
                    var modifiers: UInt32 = 0
                    guard cgs.getValue(id, &equivalent, &keyCode, &modifiers) == 0 else {
                        NSLog("MTMR: failed to read the Do Not Disturb symbolic hotkey")
                        return nil
                    }
                    return Binding(equivalent: equivalent, keyCode: keyCode, modifiers: modifiers)
                },
                isEnabled: { cgs.isEnabled(id) },
                setValue: { cgs.setValue(id, $0.equivalent, $0.keyCode, $0.modifiers) },
                setEnabled: { cgs.setEnabled(id, $0) },
                post: { postKeyChord(keyCode: $0.keyCode, modifiers: $0.modifiers) },
                waitForDelivery: { Thread.sleep(forTimeInterval: restoreDelay) }
            )
        }

        static func performToggle(read: () -> Binding?, isEnabled: () -> Bool,
                                  setValue: (Binding) -> Int32, setEnabled: (Bool) -> Int32,
                                  post: (Binding) -> Void, waitForDelivery: () -> Void) {
            guard let original = read() else { return }
            let wasEnabled = isEnabled()
            if wasEnabled && original.keyCode != unboundKeyCode {
                post(original)
                return
            }

            // HotKey 175 is disabled or unbound: temporarily bind an unused F19 chord in WindowServer,
            // dispatch it, wait briefly for WindowServer to process, then restore the exact prior state.
            defer {
                _ = setValue(original)
                _ = setEnabled(wasEnabled)
            }

            guard setValue(temporaryBinding) == 0, setEnabled(true) == 0 else {
                NSLog("MTMR: failed to temporarily enable Do Not Disturb symbolic hotkey")
                return
            }

            post(temporaryBinding)
            waitForDelivery()
        }

        private static func postKeyChord(keyCode: UInt16, modifiers: UInt32) {
            guard let source = CGEventSource(stateID: .hidSystemState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else {
                return
            }
            let flags = CGEventFlags(rawValue: UInt64(modifiers))
            keyDown.flags = flags
            keyUp.flags = flags
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
}
