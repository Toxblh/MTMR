//
//  BluetoothBatteryBarItem.swift
//  MTMR
//
//  Battery of a Bluetooth device. Two presets use it:
//  - "bluetoothBattery": one device with one battery (mouse, keyboard, other makers' headphones), parts [.main];
//  - "airpodsBattery": AirPods as one widget, parts [.left, .right, .case_] side by side.
//

import AppKit

class BluetoothBatteryBarItem: CustomButtonTouchBarItem {
    /// Below this a percentage turns red, so a device that needs charging stands out.
    static let lowLevel = 20

    private let address: String
    private let parts: [BluetoothBattery.Part]

    init(identifier: NSTouchBarItem.Identifier, address: String, parts: [BluetoothBattery.Part]) {
        self.address = address
        self.parts = parts
        super.init(identifier: identifier, title: "")
        isBordered = false
        // Hidden until the first reading: a widget without a value takes no Touch Bar space.
        view.isHidden = true
        actions.append(ItemAction(trigger: .singleTap) { BluetoothBattery.Monitor.shared.refreshNow() })
        BluetoothBattery.Monitor.shared.subscribe(self) { [weak self] devices in self?.update(devices) }
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func update(_ devices: [BluetoothBattery.Device]) {
        // Parts without a value (a bud in its case) are left out. Nothing at all (not connected): hidden, and the
        // space goes to the other items.
        let readings = BluetoothBattery.readings(address: address, parts: parts, in: devices)
        guard !readings.isEmpty else {
            view.setShownInBar(false)
            return
        }
        let device = devices.first { $0.address == address }
        let font = NSFont.systemFont(ofSize: 15)
        let title = NSMutableAttributedString()
        for (index, reading) in readings.enumerated() {
            // Each part in its own colour: a red right bud must not turn the whole AirPods widget red. A part that
            // is charging is not red: it is being taken care of.
            let color: NSColor = reading.level < Self.lowLevel && !reading.isCharging ? .systemRed : .white
            let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color, .font: font, .baselineOffset: 1]
            if index > 0 { title.append(NSAttributedString(string: "  ", attributes: attributes)) }
            if let icon = IconLibrary.inlineIcon(Self.icon(part: reading.part, kind: device?.kind ?? .other), color: color, font: font) {
                let start = title.length
                title.append(icon)
                title.append(NSAttributedString(string: " "))
                title.addAttributes(attributes, range: NSRange(location: start, length: title.length - start))
            }
            // A bolt before the number while it charges, like the Mac battery widget.
            if reading.isCharging, let bolt = IconLibrary.inlineIcon("bolt", color: color, font: font) {
                let start = title.length
                title.append(bolt)
                title.addAttributes([.baselineOffset: 1], range: NSRange(location: start, length: title.length - start))
            }
            title.append(NSAttributedString(string: "\(reading.level)%", attributes: attributes))
        }
        attributedTitle = title
        let spoken = readings.map {
            "\($0.part == .main ? "battery" : $0.part.rawValue) \($0.level)%\($0.isCharging ? ", charging" : "")"
        }.joined(separator: ", ")
        view.setAccessibilityLabel("\(device?.name ?? "Bluetooth device"): \(spoken)")
        view.setShownInBar(true)
    }

    static func icon(part: BluetoothBattery.Part, kind: BluetoothBattery.Kind) -> String {
        switch part {
        case .left: return "airpod-left"
        case .right: return "airpod-right"
        case .case_: return "airpods-case"
        case .main:
            switch kind {
            case .mouse: return "mouse"
            case .keyboard: return "keyboard"
            case .headphones: return "headphones"
            case .other: return "battery"
            }
        }
    }
}
