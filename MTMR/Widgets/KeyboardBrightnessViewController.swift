//
//  KeyboardBrightnessViewController.swift
//  MTMR
//
//  Slider for the keyboard backlight.
//

import AppKit
import ObjectiveC

/// Keyboard backlight level through CoreBrightness' private `KeyboardBrightnessClient`.
///
/// There is no public API for an absolute keyboard backlight level; the illumination HID keys only step it.
/// The selectors below were checked on a MacBookPro17,1 (M1, macOS 27) with `class_copyMethodList`:
/// `copyKeyboardBacklightIDs` (@16@0:8), `brightnessForKeyboard:` (f24@0:8Q16),
/// `setBrightness:forKeyboard:` (B28@0:8f16Q20). Everything is resolved at runtime, so a macOS without them
/// leaves the slider disabled instead of crashing.
final class KeyboardBacklight {
    static let shared = KeyboardBacklight()

    private typealias GetFn = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetFn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private let client: NSObject?
    private let keyboardID: UInt64?
    private let getSel = NSSelectorFromString("brightnessForKeyboard:")
    private let setSel = NSSelectorFromString("setBrightness:forKeyboard:")
    private let getImp: GetFn?
    private let setImp: SetFn?

    private init() {
        // CoreBrightness is already linked for Night Shift (CBBlueLightClient); dlopen is a no-op then.
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type,
              class_getInstanceMethod(cls, getSel) != nil,
              class_getInstanceMethod(cls, setSel) != nil
        else {
            client = nil; keyboardID = nil; getImp = nil; setImp = nil
            NSLog("MTMR: KeyboardBrightnessClient is not available, keyboard brightness slider disabled")
            return
        }
        let client = cls.init()
        self.client = client
        // "copy" returns a +1 object.
        let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber]
        keyboardID = ids?.first?.uint64Value
        getImp = unsafeBitCast(class_getMethodImplementation(cls, getSel), to: GetFn.self)
        setImp = unsafeBitCast(class_getMethodImplementation(cls, setSel), to: SetFn.self)
    }

    var isAvailable: Bool { client != nil && keyboardID != nil }

    /// 0...1, or nil when unavailable.
    var level: Float? {
        guard let client = client, let id = keyboardID, let get = getImp else { return nil }
        return get(client, getSel, id)
    }

    func setLevel(_ value: Float) {
        guard let client = client, let id = keyboardID, let set = setImp else { return }
        _ = set(client, setSel, min(max(value, 0), 1), id)
    }
}

class KeyboardBrightnessViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: CustomSlider!
    private var timer: Timer?

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: Double, image: NSImage? = nil) {
        super.init(identifier: identifier)

        sliderItem = image.map { CustomSlider(knob: $0) } ?? CustomSlider()
        sliderItem.target = self
        sliderItem.action = #selector(sliderValueChanged(_:))
        sliderItem.minValue = 0.0
        sliderItem.maxValue = 100.0
        sliderItem.isEnabled = KeyboardBacklight.shared.isAvailable
        sliderItem.floatValue = (KeyboardBacklight.shared.level ?? 0) * 100
        view = sliderItem
        sliderItem.applyDefaultTouchBarWidth()

        // The level also changes through the F-keys, ambient-light auto adjustment and idle dimming,
        // so it is polled like the display brightness slider.
        // Block-based with a weak capture: a target/selector timer would retain the item, so items replaced
        // by a preset reload would never be freed and keep polling.
        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    private func refresh() {
        guard let level = KeyboardBacklight.shared.level else { return }
        sliderItem.showSystemValue(level * 100)
    }

    @objc private func sliderValueChanged(_ sender: Any) {
        guard let slider = sender as? NSSlider else { return }
        KeyboardBacklight.shared.setLevel(slider.floatValue / 100)
    }
}
