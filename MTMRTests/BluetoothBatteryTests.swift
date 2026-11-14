import XCTest

final class BluetoothBatteryTests: XCTestCase {
    private typealias BB = BluetoothBattery
    private let airPods = "D0:3E:07:CD:30:F2"
    private let caseEntry = "DD:CB:78:6B:84:CF"
    private let mouse = "D5:86:7C:AD:15:0A"

    /// The user's `system_profiler SPBluetoothDataType -json` from 2026-11-14, trimmed to the keys the parser reads.
    /// macOS writes "74 %" with a no-break space (U+00A0).
    private func fixture(airPods: [String: String]? = nil, caseEntry: [String: String]? = nil,
                         connectedExtra: [[String: [String: String]]] = [],
                         notConnectedExtra: [[String: [String: String]]] = []) -> Data {
        let mainAirPods = airPods ?? [
            "device_address": self.airPods,
            "device_batteryLevelCase": "53\u{a0}%",
            "device_batteryLevelLeft": "74\u{a0}%",
            "device_batteryLevelRight": "9\u{a0}%",
            "device_minorType": "Headphones",
            "device_vendorID": "0x004C",
        ]
        let second = caseEntry ?? ["device_address": self.caseEntry, "device_batteryLevelCase": "53\u{a0}%"]
        let root: [String: Any] = ["SPBluetoothDataType": [[
            "controller_properties": ["controller_state": "attrib_on"],
            "device_connected": [["Pro 2": mainAirPods], ["Pro 2": second]] + connectedExtra,
            "device_not_connected": [
                ["MX Keys Mini": ["device_address": "DF:AF:1F:16:D5:62", "device_minorType": "Keyboard", "device_vendorID": "0x046D"]],
                ["MX Master 3S": ["device_address": mouse, "device_minorType": "Mouse", "device_vendorID": "0x046D"]],
            ] + notConnectedExtra,
        ]]]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    func testParsesAirPodsAndMiceFromFixture() throws {
        let devices = BB.parse(fixture())
        let pods = try XCTUnwrap(devices.first { $0.address == airPods })
        XCTAssertEqual(pods.name, "Pro 2")
        XCTAssertEqual(pods.kind, .headphones)
        XCTAssertTrue(pods.isConnected)
        XCTAssertEqual(pods.levels, [.left: 74, .right: 9, .case_: 53])
        let mx = try XCTUnwrap(devices.first { $0.address == mouse })
        XCTAssertEqual(mx.kind, .mouse)
        XCTAssertFalse(mx.isConnected)
        XCTAssertEqual(devices.count, 4)
    }

    func testParsesPercentStrings() {
        XCTAssertEqual(BB.percent("74\u{a0}%"), 74)
        XCTAssertEqual(BB.percent("100%"), 100)
        XCTAssertEqual(BB.percent("5 %"), 5)
        XCTAssertNil(BB.percent(""))
        XCTAssertNil(BB.percent("n/a"))
    }

    func testMissingSideHasNoLevel() {
        // A bud in its case: macOS drops that side's key.
        let devices = BB.parse(fixture(airPods: [
            "device_address": airPods, "device_batteryLevelRight": "9\u{a0}%", "device_minorType": "Headphones",
        ]))
        XCTAssertNil(BB.level(address: airPods, part: .left, in: devices))
        XCTAssertEqual(BB.level(address: airPods, part: .right, in: devices), 9)
    }

    func testCaseFallsBackToEntryWithSameName() {
        let devices = BB.parse(fixture(airPods: [
            "device_address": airPods, "device_batteryLevelLeft": "74\u{a0}%", "device_minorType": "Headphones",
        ]))
        XCTAssertEqual(BB.level(address: airPods, part: .case_, in: devices), 53)
    }

    func testAnyPartFallsBackToEntryWithSameName() {
        // Seen on 2026-11-14: the main entry had only the left bud; right and case came on the second entry,
        // whose address had changed.
        let devices = BB.parse(fixture(
            airPods: ["device_address": airPods, "device_batteryLevelLeft": "65\u{a0}%", "device_minorType": "Headphones"],
            caseEntry: ["device_address": "FD:96:8E:6C:38:94", "device_batteryLevelCase": "34\u{a0}%", "device_batteryLevelRight": "61\u{a0}%"]
        ))
        XCTAssertEqual(BB.readings(address: airPods, parts: [.left, .right, .case_], in: devices).map(\.level), [65, 61, 34])
    }

    func testDisconnectedDeviceHasNoLevel() {
        let devices = BB.parse(fixture(notConnectedExtra: [
            ["Magic Mouse": ["device_address": "AA:BB", "device_minorType": "Mouse", "device_batteryLevelMain": "80\u{a0}%"]],
        ]))
        XCTAssertNil(BB.level(address: "AA:BB", part: .main, in: devices))
    }

    func testMainLevelOfMouse() {
        let devices = BB.parse(fixture(connectedExtra: [
            ["MX Master 3S": ["device_address": mouse, "device_minorType": "Mouse", "device_batteryLevelMain": "61\u{a0}%"]],
        ]))
        XCTAssertEqual(BB.level(address: mouse, part: .main, in: devices), 61)
    }

    func testUnknownBatteryKeyCountsAsMain() {
        // The key for single devices is not verified yet (the MX devices were not connected when this was written).
        let devices = BB.parse(fixture(connectedExtra: [
            ["Keys": ["device_address": "CC:DD", "device_minorType": "Keyboard", "device_batteryLevel": "42\u{a0}%"]],
        ]))
        XCTAssertEqual(BB.level(address: "CC:DD", part: .main, in: devices), 42)
    }

    func testAirPodsPickerOffersOnlyAppleHeadphonesWithoutTheCaseEntry() {
        let names = BB.pickerDevices(BB.parse(fixture()), airPods: true).map(\.address)
        XCTAssertEqual(names, [airPods])
    }

    func testDevicePickerOffersEverythingButAirPods() {
        let devices = BB.parse(fixture(notConnectedExtra: [
            ["Beats Solo": ["device_address": "EE:FF", "device_minorType": "Headphones", "device_vendorID": "0x0059"]],
        ]))
        let names = BB.pickerDevices(devices, airPods: false).map(\.address)
        // Headphones of other makers have one battery and belong here; sorted connected first, then by name.
        XCTAssertEqual(names, ["EE:FF", "DF:AF:1F:16:D5:62", mouse])
    }

    func testAirPodsWidgetShowsTheReportedPartsInOrder() {
        let all = BB.readings(address: airPods, parts: [.left, .right, .case_], in: BB.parse(fixture()))
        XCTAssertEqual(all.map(\.part), [.left, .right, .case_])
        XCTAssertEqual(all.map(\.level), [74, 9, 53])

        // Left bud in the case: it is left out, the rest stays.
        let inCase = BB.readings(address: airPods, parts: [.left, .right, .case_], in: BB.parse(fixture(airPods: [
            "device_address": airPods, "device_batteryLevelRight": "9\u{a0}%", "device_minorType": "Headphones",
        ])))
        XCTAssertEqual(inCase.map(\.part), [.right, .case_])
    }

    // MARK: Charging

    /// IOKit accessory power sources as seen on 2026-11-14 (trimmed): the right bud in the case is charging.
    private let powerSources: [[String: Any]] = [
        ["Type": "InternalBattery", "Name": "InternalBattery-0", "Is Charging": false],
        ["Type": "Accessory Source", "Name": "Pro 2 Case", "Part Identifier": "Case", "Product ID": 8212, "Is Charging": false],
        ["Type": "Accessory Source", "Name": "Pro 2", "Part Identifier": "Left", "Product ID": 8212, "Is Charging": false],
        ["Type": "Accessory Source", "Name": "Pro 2", "Part Identifier": "Right", "Product ID": 8212, "Is Charging": true],
        ["Type": "Accessory Source", "Name": "MX Master 3S", "Product ID": 45108, "Is Charging": true],
    ]

    func testReadsChargingPartsOfAccessories() {
        let sources = BB.chargingSources(powerSources)
        XCTAssertEqual(sources.count, 4) // the Mac's own battery is not an accessory
        XCTAssertEqual(sources.filter(\.isCharging).map(\.part), [.right, .main])
    }

    func testChargingIsMatchedByProductIDAndShownPerPart() {
        let devices = BB.merge(BB.parse(fixture(airPods: [
            "device_address": airPods, "device_batteryLevelLeft": "74\u{a0}%", "device_batteryLevelRight": "9\u{a0}%",
            "device_batteryLevelCase": "53\u{a0}%", "device_minorType": "Headphones", "device_productID": "0x2014",
        ])), charging: BB.chargingSources(powerSources))
        let readings = BB.readings(address: airPods, parts: [.left, .right, .case_], in: devices)
        XCTAssertEqual(readings.map(\.isCharging), [false, true, false])
    }

    func testChargingFallsBackToTheName() {
        // A mouse whose system_profiler entry has no product ID.
        let devices = BB.merge(BB.parse(fixture(connectedExtra: [
            ["MX Master 3S": ["device_address": mouse, "device_minorType": "Mouse", "device_batteryLevelMain": "61\u{a0}%"]],
        ])), charging: BB.chargingSources(powerSources))
        XCTAssertEqual(BB.readings(address: mouse, parts: [.main], in: devices).map(\.isCharging), [true])
    }

    private func airPodsWithProductID() -> [BB.Device] {
        BB.parse(fixture(airPods: [
            "device_address": airPods, "device_batteryLevelLeft": "74\u{a0}%", "device_batteryLevelRight": "9\u{a0}%",
            "device_batteryLevelCase": "53\u{a0}%", "device_minorType": "Headphones", "device_productID": "0x2014",
        ]))
    }

    func testChargingIsKeptWhileItsSourceIsMissing() {
        // Seen live: the sources of the right bud and the case vanish for ~16 s at a time while system_profiler still
        // reports their levels. Missing is not "not charging"; the bolt must not flicker.
        let before = BB.merge(airPodsWithProductID(), charging: BB.chargingSources(powerSources))
        let leftOnly = BB.chargingSources(powerSources.filter { ($0["Part Identifier"] as? String) == "Left" })
        let now = BB.carryCharging(from: before, into: BB.merge(airPodsWithProductID(), charging: leftOnly))
        XCTAssertEqual(BB.readings(address: airPods, parts: [.left, .right, .case_], in: now).map(\.isCharging), [false, true, false])
    }

    func testChargingEndsWhenTheSourceSaysSo() {
        let before = BB.merge(airPodsWithProductID(), charging: BB.chargingSources(powerSources))
        let unplugged = powerSources.map { source -> [String: Any] in
            var copy = source
            copy["Is Charging"] = false
            return copy
        }
        let now = BB.carryCharging(from: before, into: BB.merge(airPodsWithProductID(), charging: BB.chargingSources(unplugged)))
        XCTAssertEqual(BB.readings(address: airPods, parts: [.left, .right, .case_], in: now).map(\.isCharging), [false, false, false])
    }

    func testNoPowerSourcesMeansNotCharging() {
        let devices = BB.merge(BB.parse(fixture()), charging: [])
        XCTAssertEqual(BB.readings(address: airPods, parts: [.left, .right, .case_], in: devices).map(\.isCharging), [false, false, false])
    }

    func testGarbageGivesNoDevices() {
        XCTAssertTrue(BB.parse(Data("x".utf8)).isEmpty)
        XCTAssertTrue(BB.parse(Data("{}".utf8)).isEmpty)
    }
}
