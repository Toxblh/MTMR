//
//  SidecarBarItem.swift
//  MTMR
//
//  Button that connects an iPad as an external display (Sidecar) or disconnects it.
//

import AppKit
import ObjectiveC

/// Sidecar through SidecarCore's private `SidecarDisplayManager`.
///
/// There is no public API for starting Sidecar; the only alternatives are clicking through Control Center
/// (UI scripting, breaks with every macOS layout change) or the Displays settings pane.
/// The selectors were checked on a MacBookPro17,1 (M1, macOS 27) with `class_copyMethodList`:
/// `+sharedManager`, `-devices` / `-connectedDevices` (@16@0:8, arrays of `SidecarDevice`),
/// `-connectToDevice:completion:` / `-disconnectFromDevice:completion:` (v32@0:8@16@?24), and on
/// `SidecarDevice` `-name` and `-isRealityDevice` (Vision Pro uses the same service as Mac Virtual Display).
/// Everything is resolved at runtime, so a macOS without them shows a disabled button instead of crashing.
final class Sidecar {
    static let shared = Sidecar()

    typealias Completion = @convention(block) (NSError?) -> Void
    private typealias DeviceFn = @convention(c) (AnyObject, Selector, AnyObject, Completion) -> Void

    private let manager: NSObject?
    private let connectSel = NSSelectorFromString("connectToDevice:completion:")
    private let disconnectSel = NSSelectorFromString("disconnectFromDevice:completion:")

    private init() {
        _ = dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY)
        let shared = NSSelectorFromString("sharedManager")
        guard let cls = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
              cls.responds(to: shared),
              class_getInstanceMethod(cls, connectSel) != nil,
              class_getInstanceMethod(cls, disconnectSel) != nil,
              class_getInstanceMethod(cls, NSSelectorFromString("devices")) != nil,
              class_getInstanceMethod(cls, NSSelectorFromString("connectedDevices")) != nil
        else {
            manager = nil
            NSLog("MTMR: SidecarDisplayManager is not available, Sidecar button disabled")
            return
        }
        manager = cls.perform(shared)?.takeUnretainedValue() as? NSObject
    }

    var isAvailable: Bool { manager != nil }

    private func list(_ selector: String) -> [NSObject] {
        guard let manager = manager else { return [] }
        let devices = manager.perform(NSSelectorFromString(selector))?.takeUnretainedValue() as? [NSObject] ?? []
        return devices.filter { device in
            let isReality = device.responds(to: NSSelectorFromString("isRealityDevice"))
                && (device.value(forKey: "isRealityDevice") as? Bool ?? false)
            return !isReality
        }
    }

    static func name(of device: NSObject) -> String? {
        device.value(forKey: "name") as? String
    }

    /// iPads this Mac can use as a display right now (signed in to the same Apple ID, nearby or on USB).
    var devices: [NSObject] { list("devices") }
    var connectedDevices: [NSObject] { list("connectedDevices") }

    func connect(_ device: NSObject, completion: @escaping (NSError?) -> Void) {
        call(connectSel, device, completion)
    }

    func disconnect(_ device: NSObject, completion: @escaping (NSError?) -> Void) {
        call(disconnectSel, device, completion)
    }

    private func call(_ selector: Selector, _ device: NSObject, _ completion: @escaping (NSError?) -> Void) {
        guard let manager = manager, let imp = class_getMethodImplementation(type(of: manager), selector) else {
            completion(NSError(domain: "MTMR.Sidecar", code: 1))
            return
        }
        let fn = unsafeBitCast(imp, to: DeviceFn.self)
        // SidecarCore calls back on its own queue.
        let block: Completion = { error in DispatchQueue.main.async { completion(error) } }
        fn(manager, selector, device, block)
    }
}

class SidecarBarItem: CustomButtonTouchBarItem {
    private let deviceName: String?
    private var timer: Timer?
    private var isBusy = false

    /// `deviceName`: the iPad to use when several are available (its name as shown in Control Center).
    /// Without it the first available iPad is used.
    init(identifier: NSTouchBarItem.Identifier, deviceName: String?) {
        self.deviceName = deviceName?.isEmpty == true ? nil : deviceName
        super.init(identifier: identifier, title: "")
        isBordered = false
        setWidth(value: 32)

        actions.append(ItemAction(trigger: .singleTap) { [weak self] in self?.toggle() })

        // Sidecar also starts and stops from Control Center, the iPad itself or when the iPad leaves,
        // so the state is polled like the Do Not Disturb button.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer

        refresh()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    private func matches(_ device: NSObject) -> Bool {
        guard let wanted = deviceName else { return true }
        return Sidecar.name(of: device) == wanted
    }

    private var connectedDevice: NSObject? { Sidecar.shared.connectedDevices.first(where: matches) }
    private var availableDevice: NSObject? { Sidecar.shared.devices.first(where: matches) }

    func toggle() {
        guard !isBusy else { return }
        // Connecting takes a few seconds; a second tap meanwhile would start a second request.
        let done: (NSError?) -> Void = { [weak self] error in
            if let error = error { NSLog("MTMR: Sidecar request failed: \(error)") }
            self?.isBusy = false
            self?.refresh()
        }
        if let device = connectedDevice {
            isBusy = true
            Sidecar.shared.disconnect(device, completion: done)
        } else if let device = availableDevice {
            isBusy = true
            Sidecar.shared.connect(device, completion: done)
        } else {
            NSLog("MTMR: no iPad available for Sidecar\(deviceName.map { " named \"\($0)\"" } ?? "")")
        }
        refresh()
    }

    func refresh() {
        let connected = connectedDevice != nil
        let usable = connected || availableDevice != nil
        let icon = IconLibrary.image(
            named: connected ? "sidecar-on" : "sidecar-off",
            fallback: NSImage(named: NSImage.touchBarSidebarTemplateName)
        )
        // Dimmed while no iPad is in reach or a request is running, so the tap visibly does nothing.
        if let icon = icon, !usable || isBusy {
            image = IconLibrary.tinted(icon, color: NSColor(white: 1, alpha: 0.4))
        } else {
            image = icon
        }
    }
}
