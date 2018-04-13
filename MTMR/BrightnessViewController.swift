import Cocoa
import AppKit
import AVFoundation
import CoreAudio

class BrightnessViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: NSSlider!
    
    init(identifier: NSTouchBarItem.Identifier, image: NSImage? = nil) {
        super.init(identifier: identifier)
        let brightness:Double = Double(getBrightness())
        sliderItem = NSSlider(value: brightness*100.0, minValue: 0.0, maxValue: 100.0, target: self, action:#selector(BrightnessViewController.sliderValueChanged(_:)))
        
        if (image != nil) {
            sliderItem.cell = CustomSliderCell(knob: image!)
        }
        
        self.view = sliderItem
        
        let timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(BrightnessViewController.updateBrightnessSlider), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: RunLoopMode.commonModes)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
