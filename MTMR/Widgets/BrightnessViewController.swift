import AppKit
import AVFoundation
import Cocoa
import CoreAudio

class BrightnessViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: CustomSlider!

    init(identifier: NSTouchBarItem.Identifier, refreshInterval: Double, image: NSImage? = nil) {
        super.init(identifier: identifier)

        if image == nil {
            sliderItem = CustomSlider()
        } else {
            sliderItem = CustomSlider(knob: image!)
        }
        sliderItem.target = self
        sliderItem.action = #selector(BrightnessViewController.sliderValueChanged(_:))
        sliderItem.minValue = 0.0
        sliderItem.maxValue = 100.0
        sliderItem.floatValue = getBrightness() * 100

        view = sliderItem

        let timer = Timer.scheduledTimer(timeInterval: refreshInterval, target: self, selector: #selector(BrightnessViewController.updateBrightnessSlider), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: RunLoop.Mode.common)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        sliderItem.unbind(NSBindingName.value)
    }

    @objc func updateBrightnessSlider() {
        DispatchQueue.main.async {
            self.sliderItem.floatValue = self.getBrightness() * 100
        }
    }

    @objc func sliderValueChanged(_ sender: Any) {
        if let sliderItem = sender as? NSSlider {
            setBrightness(level: Float32(sliderItem.intValue) / 100.0)
        }
    }

    // Apple Silicon has no IODisplayConnect service, and CoreDisplay's user-brightness calls do not reliably
    // drive the built-in panel. The private DisplayServices framework does: measured on a MacBookPro17,1
    // (M1 2020): DisplayServicesSetBrightness(builtin, 0.95) -> Get returns 0.95, rc == 0.
    // It is loaded with dlopen/dlsym instead of being linked, so the app still launches if a future macOS
    // drops the framework; CoreDisplay / IODisplayConnect remain as fallbacks (Intel Macs).
    private typealias DSGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let displayServices: (get: DSGetBrightness, set: DSSetBrightness)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let g = dlsym(handle, "DisplayServicesGetBrightness"),
              let s = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return (unsafeBitCast(g, to: DSGetBrightness.self), unsafeBitCast(s, to: DSSetBrightness.self))
    }()

    // Prefer the built-in display (the Touch Bar belongs to the internal panel), else the main display.
    // The previous code passed 0, which is not a valid CGDirectDisplayID.
    private var targetDisplay: CGDirectDisplayID {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        if CGGetActiveDisplayList(16, &ids, &count) == .success,
           let builtin = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return builtin
        }
        return CGMainDisplayID()
    }

    private func getBrightness() -> Float32 {
        let display = targetDisplay
        if let ds = Self.displayServices {
            var level: Float = 0
            if ds.get(display, &level) == 0 { return level }
        }
        let level = Float32(CoreDisplay_Display_GetUserBrightness(Int32(bitPattern: display)))
        if level > 0 { return level }
        // Last resort for Intel Macs that expose IODisplayConnect.
        var ioLevel: Float32 = 0.5
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"))
        if service != 0 {
            IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &ioLevel)
            IOObjectRelease(service)
        }
        return ioLevel
    }

    private func setBrightness(level: Float) {
        let display = targetDisplay
        if let ds = Self.displayServices, ds.set(display, level) == 0 { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"))
        if service != 0 {
            IODisplaySetFloatParameter(service, 1, kIODisplayBrightnessKey as CFString, level)
            IOObjectRelease(service)
        } else {
            CoreDisplay_Display_SetUserBrightness(Int32(bitPattern: display), Double(level))
        }
    }
}
