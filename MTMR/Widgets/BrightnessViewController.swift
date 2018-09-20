import Cocoa
import AppKit
import AVFoundation
import CoreAudio

class BrightnessViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: CustomSlider!
    
    init(identifier: NSTouchBarItem.Identifier, refreshInterval: Double, image: NSImage? = nil) {
        super.init(identifier: identifier)
        
        if (image == nil) {
            sliderItem = CustomSlider()
        } else {
            sliderItem = CustomSlider(knob: image!)
        }
        sliderItem.target = self
        sliderItem.action =  #selector(BrightnessViewController.sliderValueChanged(_:))
        sliderItem.minValue = 0.0
        sliderItem.maxValue = 100.0
        sliderItem.floatValue = getBrightness()*100
        
        self.view = sliderItem
        
        let timer = Timer.scheduledTimer(timeInterval: refreshInterval, target: self, selector: #selector(BrightnessViewController.updateBrightnessSlider), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: RunLoop.Mode.common)
    }
    
    required init?(coder: NSCoder) {
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
            setBrightness(level: Float32(sliderItem.intValue)/100.0)
        }
    }
    
    private func getBrightness() -> Float32 {
        var level: Float32 = 0.5
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"))
        
        IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &level)
        return level
    }
    
    private func setBrightness(level: Float) {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IODisplayConnect"))
        
        IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, level)
        IOObjectRelease(service)
    }
}
