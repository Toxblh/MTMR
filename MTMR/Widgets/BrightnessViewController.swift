import AppKit
import AVFoundation
import Cocoa
import CoreAudio

class BrightnessViewController: CustomTouchBarItem {
    private(set) var sliderItem: CustomSlider!

    override class var typeIdentifier: String {
        return "brightness"
    }
    
    private enum CodingKeys: String, CodingKey {
        case image
        case refreshInterval
    }
    
    init(identifier: NSTouchBarItem.Identifier, refreshInterval: Double, image: NSImage? = nil) {
        super.init(identifier: identifier)
        self.setup(image: nil, interval: refreshInterval)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let image = try container.decodeIfPresent(Source.self, forKey: .image)?.image
        let interval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 0.5
        
        try super.init(from: decoder)

        self.setup(image: image, interval: interval)
    }
    
    
    func setup(image: NSImage?, interval: Double) {
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

        let timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(BrightnessViewController.updateBrightnessSlider), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: RunLoop.Mode.common)
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

    private func getBrightness() -> Float32 {
        if #available(OSX 10.13, *) {
            return Float32(CoreDisplay_Display_GetUserBrightness(0))
        } else {
            var level: Float32 = 0.5
            let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"))

            IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &level)
            return level
        }
    }

    private func setBrightness(level: Float) {
        if #available(OSX 10.13, *) {
            CoreDisplay_Display_SetUserBrightness(0, Double(level))
        } else {
            let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"))

            IODisplaySetFloatParameter(service, 1, kIODisplayBrightnessKey as CFString, level)
            IOObjectRelease(service)
        }
    }
}
