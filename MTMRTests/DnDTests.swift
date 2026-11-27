import AppKit
import XCTest

final class DnDTests: XCTestCase {
    func testParseAssertionsJSONActive() {
        let json = """
        {
          "data": [
            {
              "storeAssertionRecords": [
                {
                  "assertionDetails": {
                    "assertionDetailsModeIdentifier": "com.apple.donotdisturb.mode.default"
                  }
                }
              ]
            }
          ]
        }
        """
        XCTAssertEqual(DoNotDisturb.parseAssertionsJSON(Data(json.utf8)), true)
    }

    func testParseAssertionsJSONInactive() {
        let emptyRecords = """
        {"data":[{"storeAssertionRecords":[]}]}
        """
        XCTAssertEqual(DoNotDisturb.parseAssertionsJSON(Data(emptyRecords.utf8)), false)

        let emptyData = """
        {"data":[]}
        """
        XCTAssertEqual(DoNotDisturb.parseAssertionsJSON(Data(emptyData.utf8)), false)
    }

    func testParseAssertionsJSONMalformedReturnsNil() {
        XCTAssertNil(DoNotDisturb.parseAssertionsJSON(Data("not json".utf8)))
        XCTAssertNil(DoNotDisturb.parseAssertionsJSON(Data("{}".utf8)))
    }

    func testInterpretControlCenterState() {
        // Always Show (2) and Don't Show (8) are ambiguous and must return nil
        XCTAssertNil(DoNotDisturb.interpretControlCenterState(focusModesSetting: 2, statusItemVisible: true))
        XCTAssertNil(DoNotDisturb.interpretControlCenterState(focusModesSetting: 2, statusItemVisible: false))
        XCTAssertNil(DoNotDisturb.interpretControlCenterState(focusModesSetting: 8, statusItemVisible: false))
        XCTAssertNil(DoNotDisturb.interpretControlCenterState(focusModesSetting: 8, statusItemVisible: true))

        // Show When Active (18 or default nil) reflects live status item visibility
        XCTAssertEqual(DoNotDisturb.interpretControlCenterState(focusModesSetting: 18, statusItemVisible: true), true)
        XCTAssertEqual(DoNotDisturb.interpretControlCenterState(focusModesSetting: 18, statusItemVisible: false), false)
        XCTAssertEqual(DoNotDisturb.interpretControlCenterState(focusModesSetting: nil, statusItemVisible: true), true)
        XCTAssertEqual(DoNotDisturb.interpretControlCenterState(focusModesSetting: nil, statusItemVisible: false), false)

        // Missing visibility key returns nil
        XCTAssertNil(DoNotDisturb.interpretControlCenterState(focusModesSetting: 18, statusItemVisible: nil))
    }

    func testHotKeyReadFailureMakesNoWritesOrKeyEvents() {
        DoNotDisturb.HotKeyToggler.performToggle(
            read: { nil },
            isEnabled: { XCTFail("No snapshot was read"); return false },
            setValue: { _ in XCTFail("Changed binding"); return 0 },
            setEnabled: { _ in XCTFail("Changed enable state"); return 0 },
            post: { _ in XCTFail("Posted a key event") },
            waitForDelivery: { XCTFail("Waited for key delivery") }
        )
    }

    func testUnboundHotKeyRestoresExactBindingAndEnableStateAfterDelivery() {
        typealias Binding = DoNotDisturb.HotKeyToggler.Binding
        let unbound = Binding(equivalent: 73, keyCode: 0xFFFF, modifiers: 12)
        for wasEnabled in [false, true] {
            var current = unbound
            var enabled = wasEnabled
            var operations: [String] = []
            DoNotDisturb.HotKeyToggler.performToggle(
                read: { current },
                isEnabled: { enabled },
                setValue: { current = $0; operations.append("bind"); return 0 },
                setEnabled: { enabled = $0; operations.append("enable"); return 0 },
                post: {
                    XCTAssertEqual($0, current)
                    XCTAssertEqual(current.keyCode, 80)
                    XCTAssertTrue(enabled)
                    operations.append("post")
                },
                waitForDelivery: { operations.append("wait") }
            )
            XCTAssertEqual(current, unbound)
            XCTAssertEqual(enabled, wasEnabled)
            XCTAssertEqual(operations, ["bind", "enable", "post", "wait", "bind", "enable"])
        }
    }

    func testBuiltInTouchBarIconAssetsFitTouchBarAt2x() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetsDir = repoRoot.appendingPathComponent("MTMR/Assets.xcassets")

        let assets: [(String, String)] = [
            ("dnd-off.imageset", "dnd-off.png"),
            ("dnd-on.imageset", "dnd-on.png"),
            ("dark-mode-off.imageset", "sun-icon-256.png"),
            ("dark-mode-on.imageset", "39857.png"),
            ("brightnessDown.imageset", "brightnessDown.png"),
            ("brightnessUp.imageset", "brightnessUp.png"),
            ("ill_down.imageset", "KeyboardBrightDown.png"),
            ("ill_up.imageset", "KeyboardBrightUp.png"),
            ("nightShiftOff.imageset", "NightShift.png"),
            ("nightShiftOn.imageset", "NightShiftEnabled.png"),
        ]

        for (set, filename) in assets {
            let url = assetsDir.appendingPathComponent(set).appendingPathComponent(filename)
            let image = try XCTUnwrap(NSImage(contentsOf: url), "Missing asset \(url.path)")
            let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
            // Assets are @2x in Contents.json; logical size must fit inside the 30pt Touch Bar height
            // because CustomButtonTouchBarItem renders with imageScaling = .scaleNone.
            let logicalWidth = Double(rep.pixelsWide) / 2.0
            let logicalHeight = Double(rep.pixelsHigh) / 2.0
            XCTAssertGreaterThanOrEqual(logicalWidth, 16.0, "\(filename) is too small")
            XCTAssertGreaterThanOrEqual(logicalHeight, 16.0, "\(filename) is too small")
            XCTAssertLessThanOrEqual(logicalWidth, 30.0, "\(filename) exceeds Touch Bar height and will clip")
            XCTAssertLessThanOrEqual(logicalHeight, 30.0, "\(filename) exceeds Touch Bar height and will clip")
        }
    }
}
