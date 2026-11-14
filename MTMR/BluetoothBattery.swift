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
                                              vendorID: info["device_vendorID"] as? String))
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

    /// "74 %" (with a no-break space, as macOS writes it), "100%" or "5 %" to the number.
    static func percent(_ text: String) -> Int? {
        let digits = text.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits), (0 ... 100).contains(value) else { return nil }
        return value
    }

    // MARK: Lookup

    /// The level of a part, or nil when the device is not connected or reports nothing for it (a bud in its case).
    /// The case value also comes on a second entry with the case's own address; it is used when the main entry
    /// lacks it.
    static func level(address: String, part: Part, in devices: [Device]) -> Int? {
        let connected = devices.filter(\.isConnected)
        guard let device = connected.first(where: { $0.address == address }) else { return nil }
        if let level = device.levels[part] { return level }
        guard part == .case_ else { return nil }
        return connected.first { $0.name == device.name && $0.levels[.case_] != nil }?.levels[.case_]
    }

    /// The levels of `parts` that the device reports right now, in the order of `parts`. The AirPods widget shows
    /// these side by side and leaves out a bud that sits in its case.
    static func readings(address: String, parts: [Part], in devices: [Device]) -> [(part: Part, level: Int)] {
        parts.compactMap { part in level(address: address, part: part, in: devices).map { (part: part, level: $0) } }
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
            refreshNow()
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
                    self.devices = devices
                    self.subscribers.removeAll { $0.owner() == nil }
                    self.subscribers.forEach { $0.onChange(devices) }
                    // Nobody left (all battery widgets removed from the preset): stop polling.
                    if self.subscribers.isEmpty {
                        self.timer?.invalidate()
                        self.timer = nil
                    }
                }
            }
        }
    }

    /// Runs system_profiler and parses it. Blocks for about 0.1 s; call it off the main thread.
    static func readDevices() -> [Device] {
        parse(runProfiler())
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
