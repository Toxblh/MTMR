import AppKit
import XCTest

final class SliderTests: XCTestCase {
    private final class Sink: NSObject {
        @objc func changed(_: Any) {}
    }

    func testSystemValueIsShownWhenTheUserIsNotMovingTheSlider() {
        let slider = CustomSlider()
        slider.maxValue = 100
        slider.showSystemValue(40)
        XCTAssertEqual(slider.floatValue, 40)
    }

    func testSystemValueIsIgnoredRightAfterUserInput() {
        let sink = Sink()
        let slider = CustomSlider()
        slider.maxValue = 100
        slider.target = sink
        slider.action = #selector(Sink.changed(_:))
        slider.floatValue = 70
        // The cell calls sendAction for every movement of the finger.
        _ = slider.sendAction(slider.action, to: slider.target)
        slider.showSystemValue(20)
        XCTAssertEqual(slider.floatValue, 70, "a polled value must not pull the knob away from the finger")
    }

    // Items are replaced on every preset reload. These controllers used to retain themselves through a
    // target/selector timer or CoreAudio listener blocks and kept polling forever.

    func testVolumeSliderIsReleased() {
        weak var weakItem: VolumeViewController?
        autoreleasepool {
            let item = VolumeViewController(identifier: NSTouchBarItem.Identifier("test.volume"))
            weakItem = item
        }
        XCTAssertNil(weakItem)
    }

    func testKeyboardBrightnessSliderIsReleased() {
        weak var weakItem: KeyboardBrightnessViewController?
        autoreleasepool {
            let item = KeyboardBrightnessViewController(identifier: NSTouchBarItem.Identifier("test.keyboard"), refreshInterval: 0.5)
            weakItem = item
        }
        XCTAssertNil(weakItem)
    }
}
