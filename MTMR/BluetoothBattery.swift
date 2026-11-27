//
//  BluetoothBattery.swift
//  MTMR
//
//  Battery levels of Bluetooth devices (AirPods per bud and case, mice, keyboards), read from
//  `system_profiler SPBluetoothDataType -json`: the same data System Settings shows, through a public tool
//  rather than private IOBluetooth selectors that may change with any macOS update.
//  See docs/superpowers/specs/2026-11-14-bluetooth-battery-design.md.
//

import Foundation
import IOKit.ps
import notify

enum BluetoothBattery {
    enum Part: String, CaseIterable {
        /// A device with one battery (mouse, keyboard, single-battery headphones).
        case main
        case left
        case right
        case case_ = "case"
    }

    enum Kind: Equatable {
        case headphones, mouse, keyboard, other

        init(minorType: String?) {
            switch minorType?.lowercased() {
            case "headphones", "headset", "speaker": self = .headphones
            case "mouse", "trackpad": self = .mouse
            case "keyboard": self = .keyboard
            default: self = .other
            }
        }
    }

    struct Device: Equatable {
        let name: String
        let address: String
        let kind: Kind
        let isConnected: Bool
        let levels: [Part: Int]
        /// Whether system_profiler gave a minor type: the second AirPods entry (the case's own address) has none.
        let hasMinorType: Bool
        /// "0x004C" for Apple. Apple headphones (AirPods, Beats with buds) report left, right and case, so they get
        /// the AirPods widget; other makers' headphones have one battery and get the device widget.
        var vendorID: String? = nil
        /// From "device_productID" ("0x2014"); matches the "Product ID" of IOKit's power sources (8212).
        var productID: Int? = nil
        /// Parts that are charging, filled in by `merge(_:charging:)`.
        var charging: Set<Part> = []
        /// Parts a power source said anything about, charging or not. A part not in here has no source right now.
        var chargingKnown: Set<Part> = []

        var isAirPods: Bool { kind == .headphones && vendorID?.uppercased() == "0X004C" }
    }

    // MARK: Parsing

    static func parse(_ data: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }
        var devices: [Device] = []
        for controller in controllers {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                let entries = controller[key] as? [[String: Any]] ?? []
                for entry in entries {
                    for (name, value) in entry {
                        guard let info = value as? [String: Any], let address = info["device_address"] as? String else { continue }
                        devices.append(Device(name: name, address: address,
                                              kind: Kind(minorType: info["device_minorType"] as? String),
                                              isConnected: connected, levels: levels(info),
                                              hasMinorType: info["device_minorType"] != nil,
                                              vendorID: info["device_vendorID"] as? String,
                                              productID: (info["device_productID"] as? String).flatMap(hexNumber)))
                    }
                }
            }
        }
        return devices
    }

    /// AirPods report Left, Right and Case. Any other `device_batteryLevel…` key is the device's one battery.
    /// Assumption, not yet seen: a mouse or keyboard uses `device_batteryLevelMain`. Accepting any other suffix
    /// keeps the widget working if the key turns out different.
    private static func levels(_ info: [String: Any]) -> [Part: Int] {
        var result: [Part: Int] = [:]
        for (key, value) in info where key.hasPrefix("device_batteryLevel") {
            guard let text = value as? String, let level = percent(text) else { continue }
            switch key {
            case "device_batteryLevelLeft": result[.left] = level
            case "device_batteryLevelRight": result[.right] = level
            case "device_batteryLevelCase": result[.case_] = level
            default: result[.main] = level
            }
        }
        return result
    }

    /// "0x2014" to 8212.
    private static func hexNumber(_ text: String) -> Int? {
        let digits = text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text
        return Int(digits, radix: 16)
    }

    /// "74 %" (with a no-break space, as macOS writes it), "100%" or "5 %" to the number.
    static func percent(_ text: String) -> Int? {
        let digits = text.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits), (0 ... 100).contains(value) else { return nil }
        return value
    }

    // MARK: Lookup

    /// The level of a part, or nil when the device is not connected or reports nothing for it (a bud in its case).
    /// AirPods also appear as a second entry with its own, changing address. Any part may come only there (seen:
    /// right bud and case there, left bud on the main entry), so a part missing on the main entry is taken from a
    /// connected entry with the same name.
    static func level(address: String, part: Part, in devices: [Device]) -> Int? {
        let connected = devices.filter(\.isConnected)
        guard let device = connected.first(where: { $0.address == address }) else { return nil }
        if let level = device.levels[part] { return level }
        return connected.first { $0.name == device.name && $0.levels[part] != nil }?.levels[part]
    }

    /// The levels of `parts` that the device reports right now, in the order of `parts`, and whether each is
    /// charging. The AirPods widget shows these side by side and leaves out a bud that sits in its case.
    /// How a part's percentage is coloured on the Touch Bar.
    enum Tint: Equatable {
        case normal, low, charging
    }

    /// Below this a percentage turns red, so a device that needs charging stands out.
    static let lowLevel = 20

    /// Charging wins over low: a part on the charger is green, not red, because it is being taken care of. Green
    /// replaces the bolt the widget showed before; the user asked for colour instead of a symbol (2026-11-15).
    static func tint(level: Int, isCharging: Bool) -> Tint {
        if isCharging { return .charging }
        return level < lowLevel ? .low : .normal
    }

    static func readings(address: String, parts: [Part], in devices: [Device]) -> [(part: Part, level: Int, isCharging: Bool)] {
        let charging = devices.first { $0.isConnected && $0.address == address }?.charging ?? []
        return parts.compactMap { part in
            level(address: address, part: part, in: devices).map { (part: part, level: $0, isCharging: charging.contains(part)) }
        }
    }

    // MARK: Charging

    /// One battery of an accessory as IOKit's power sources describe it. system_profiler has no charging state;
    /// these do, per part.
    struct ChargingSource: Equatable {
        let name: String
        let productID: Int?
        let part: Part
        let isCharging: Bool
    }

    /// The accessories among IOKit power source descriptions ("Type" = "Accessory Source"). "Part Identifier" is
    /// Left, Right or Case for AirPods; a device with one battery has none.
    static func chargingSources(_ descriptions: [[String: Any]]) -> [ChargingSource] {
        descriptions.compactMap { info in
            guard (info["Type"] as? String) == "Accessory Source", let name = info["Name"] as? String else { return nil }
            let part: Part
            switch (info["Part Identifier"] as? String)?.lowercased() {
            case "left": part = .left
            case "right": part = .right
            case "case": part = .case_
            default: part = .main
            }
            return ChargingSource(name: name, productID: info["Product ID"] as? Int, part: part,
                                  isCharging: (info["Is Charging"] as? Bool) ?? ((info["Is Charging"] as? Int) == 1))
        }
    }

    /// Marks the charging parts on the devices. The power sources carry no Bluetooth address, so a source belongs
    /// to a device by product ID when both have one, otherwise by name. The AirPods case is named "<name> Case".
    static func merge(_ devices: [Device], charging sources: [ChargingSource]) -> [Device] {
        devices.map { device in
            var result = device
            let matching = sources.filter { source in
                if let a = source.productID, let b = device.productID { return a == b }
                return source.name == device.name || source.name == device.name + " Case"
            }
            result.charging = Set(matching.filter(\.isCharging).map(\.part))
            result.chargingKnown = Set(matching.map(\.part))
            return result
        }
    }

    /// Keeps the previous charging state of parts that have no power source in this reading. Seen live: the sources
    /// of the right bud and the case vanish for about 16 s at a time while the levels are still reported, and the
    /// bolt flickered. A source that is there and says "not charging" ends it.
    static func carryCharging(from previous: [Device], into current: [Device]) -> [Device] {
        current.map { device in
            guard let before = previous.first(where: { $0.address == device.address }) else { return device }
            var result = device
            let unknown = Set(Part.allCases).subtracting(device.chargingKnown)
            result.charging.formUnion(before.charging.intersection(unknown))
            return result
        }
    }

    /// Accessory power sources from IOKit. `IOPSCopyPowerSourcesByType` is what `pmset -g accps` uses; it is not in
    /// the public headers, so it is looked up at run time. Without it there is no charging state, and the levels
    /// (from system_profiler) still work.
    static func readPowerSources() -> [[String: Any]] {
        typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOPSCopyPowerSourcesByType"),
              let info = unsafeBitCast(symbol, to: CopyByType.self)(0)?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }
        return list.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
    }

    /// Devices the customizer offers, connected first, then by name: AirPods for the AirPods widget, everything
    /// else for the device widget. The AirPods' second, case-only entry (no minor type, same name) is never offered.
    static func pickerDevices(_ devices: [Device], airPods: Bool) -> [Device] {
        let typedNames = Set(devices.filter(\.hasMinorType).map(\.name))
        let shown = devices.filter { ($0.hasMinorType || !typedNames.contains($0.name)) && $0.isAirPods == airPods }
        var seen = Set<String>()
        return shown
            .filter { seen.insert($0.address).inserted }
            .sorted { ($0.isConnected ? 0 : 1, $0.name.lowercased()) < ($1.isConnected ? 0 : 1, $1.name.lowercased()) }
    }

    // MARK: Polling

    /// One poller for every battery widget, so five widgets start one system_profiler per interval, not five.
    final class Monitor {
        static let shared = Monitor()
        static let interval: TimeInterval = 60

        private(set) var devices: [Device] = []
        private var subscribers: [(owner: () -> AnyObject?, onChange: ([Device]) -> Void)] = []
        private var timer: Timer?
        private var notifyTokens: [Int32] = []
        private var pendingRefresh: DispatchWorkItem?

        /// Posted by macOS when an accessory's battery changes (level, charging, connected), checked live: each
        /// change came as a burst of "attach" and "timeremaining" within a second. The names are not in the public
        /// headers (they are strings in IOKit); if they stop firing, the 60 s timer still refreshes. The public
        /// IOPSNotificationCreateRunLoopSource fired only once a minute, for the Mac's own battery.
        static let accessoryNotifications = [
            "com.apple.system.accpowersources.source",
            "com.apple.system.accpowersources.attach",
            "com.apple.system.accpowersources.timeremaining",
        ]
        private var isRefreshing = false
        private let queue = DispatchQueue(label: "MTMR.bluetoothBattery", qos: .utility)

        /// Calls `onChange` on the main thread with the current devices now (if known) and after every refresh,
        /// as long as `owner` lives. Call on the main thread.
        func subscribe(_ owner: AnyObject, _ onChange: @escaping ([Device]) -> Void) {
            subscribers.append((owner: { [weak owner] in owner }, onChange: onChange))
            if !devices.isEmpty { onChange(devices) }
            if timer == nil {
                let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.refreshNow() }
                timer.tolerance = 5
                RunLoop.main.add(timer, forMode: .common)
                self.timer = timer
            }
            // A case put on the charger, a bud put in the case: read within a second instead of up to a minute later.
            if notifyTokens.isEmpty {
                for name in Self.accessoryNotifications {
                    var token: Int32 = 0
                    if notify_register_dispatch(name, &token, .main, { [weak self] _ in self?.refreshSoon() }) == NOTIFY_STATUS_OK {
                        notifyTokens.append(token)
                    }
                }
            }
            refreshNow()
        }

        /// One refresh 1 s after the last of a burst of notifications, not one per notification.
        private func refreshSoon() {
            pendingRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refreshNow() }
            pendingRefresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }

        /// Reads the levels again off the main thread. A refresh already running is not started twice.
        /// Call on the main thread.
        func refreshNow() {
            guard !isRefreshing else { return }
            isRefreshing = true
            queue.async { [weak self] in
                let devices = BluetoothBattery.readDevices()
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isRefreshing = false
                    self.devices = BluetoothBattery.carryCharging(from: self.devices, into: devices)
                    self.subscribers.removeAll { $0.owner() == nil }
                    self.subscribers.forEach { $0.onChange(self.devices) }
                    // Nobody left (all battery widgets removed from the preset): stop polling.
                    if self.subscribers.isEmpty {
                        self.timer?.invalidate()
                        self.timer = nil
                        self.notifyTokens.forEach { notify_cancel($0) }
                        self.notifyTokens = []
                        self.pendingRefresh?.cancel()
                    }
                }
            }
        }
    }

    /// Runs system_profiler and parses it. Blocks for about 0.1 s; call it off the main thread.
    static func readDevices() -> [Device] {
        merge(parse(runProfiler()), charging: chargingSources(readPowerSources()))
    }

    private static func runProfiler() -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return Data() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}
