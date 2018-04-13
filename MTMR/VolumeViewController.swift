import Cocoa
import AppKit
import AVFoundation
import CoreAudio

class VolumeViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: NSSlider!
    
    init(identifier: NSTouchBarItem.Identifier, image: NSImage? = nil) {
        super.init(identifier: identifier)
        let volume:Double = Double(getInputGain())
        sliderItem = NSSlider(value: volume*100, minValue: 0.0, maxValue: 100.0, target: self, action:#selector(VolumeViewController.sliderValueChanged(_:)))
        
        if (image != nil) {
            sliderItem.cell = CustomSliderCell(knob: image!)
        }

        self.view = sliderItem
        
        var forPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMasterVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMaster)
        
        addListenerBlock(listenerBlock: audioObjectPropertyListenerBlock,
                         onAudioObjectID: defaultDeviceID,
                         forPropertyAddress: &forPropertyAddress)
    }
    
    func addListenerBlock( listenerBlock: @escaping AudioObjectPropertyListenerBlock, onAudioObjectID: AudioObjectID, forPropertyAddress: UnsafePointer<AudioObjectPropertyAddress>) {

        if (kAudioHardwareNoError != AudioObjectAddPropertyListenerBlock(onAudioObjectID, forPropertyAddress, nil, listenerBlock)) {
            print("Error calling: AudioObjectAddPropertyListenerBlock") }
    }
    
    func audioObjectPropertyListenerBlock (numberAddresses: UInt32, addresses: UnsafePointer<AudioObjectPropertyAddress>) {
        var index: UInt32 = 0
        while index < numberAddresses {
            let address: AudioObjectPropertyAddress = addresses[Int(index)]
            switch address.mSelector {
            case kAudioHardwareServiceDeviceProperty_VirtualMasterVolume:
                DispatchQueue.main.async {
                    self.sliderItem.floatValue = self.getInputGain() * 100
                }
            default:
                
                print("We didn't expect this!")
                
            }
            index += 1
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func sliderValueChanged(_ sender: Any) {
        if let sliderItem = sender as? NSSlider {
            _ = setInputGain(Float32(sliderItem.intValue)/100.0)
        }
    }
    
    private var defaultDeviceID: AudioObjectID {
        var deviceID: AudioObjectID = AudioObjectID(0)
        var size: UInt32 = UInt32(MemoryLayout<AudioObjectID>.size)
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice)
        address.mScope = AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }
    
    private func getInputGain() -> Float32 {
        var volume: Float32 = 0.5
        var size: UInt32 = UInt32(MemoryLayout.size(ofValue: volume))
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMasterVolume)
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
        AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &volume)
        return volume
    }
    
    private func setInputGain(_ volume: Float32) -> OSStatus {
        var inputVolume: Float32 = volume
        
        if inputVolume == 0.0 {
           _ = setMute( mute: 1)
        } else {
            _ = setMute( mute: 0)
        }
        
        let size: UInt32 = UInt32(MemoryLayout.size(ofValue: inputVolume))
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
        address.mSelector = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMasterVolume)
        return AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &inputVolume)
    }
    
    private func setMute( mute: Int) -> OSStatus {
        var muteVal: Int = mute
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioDevicePropertyMute)
        let size: UInt32 = UInt32(MemoryLayout.size(ofValue: muteVal))
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
        return AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &muteVal)
    }
}

class CustomSliderCell: NSSliderCell {
    var knobImage:NSImage!
    private var _currentKnobRect:NSRect!
    private var _barRect:NSRect!

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override init() {
        super.init()
    }
    
    init(knob:NSImage) {
        knobImage = knob;
        super.init()
    }

    override func drawKnob(_ knobRect: NSRect) {
        
        if (knobImage == nil) {
            super.drawKnob(knobRect)
            return;
        }
        
        _currentKnobRect = knobRect;
        drawBar(inside: _barRect, flipped: true)
        self.controlView?.lockFocus()
        
        knobImage.size.width = knobRect.size.width
        knobImage.size.height = knobRect.size.height
    
        let newOriginX:CGFloat = knobRect.origin.x *
            (_barRect.size.width - (knobImage.size.width - knobRect.size.width)) / _barRect.size.width;
        
        knobImage.draw(at: NSPoint(x: newOriginX, y: knobRect.origin.y), from: NSRect(x: 0, y: 0, width: knobImage.size.width, height: knobImage.size.height), operation: NSCompositingOperation.sourceOver, fraction: 1)
        
        self.controlView?.unlockFocus()
        
    }
    
    override func drawBar(inside aRect: NSRect, flipped: Bool) {
        _barRect = aRect

        var rect = aRect
        rect.size.height = CGFloat(3)
        let barRadius = CGFloat(2.5)
        let value = CGFloat((self.doubleValue - self.minValue) / (self.maxValue - self.minValue))
        let finalWidth = CGFloat(value * (self.controlView!.frame.size.width - 8))
        var leftRect = rect
        leftRect.size.width = finalWidth
        let bg = NSBezierPath(roundedRect: rect, xRadius: barRadius, yRadius: barRadius)
        NSColor.lightGray.setFill()
        bg.fill()
        let active = NSBezierPath(roundedRect: leftRect, xRadius: barRadius, yRadius: barRadius)
        NSColor.darkGray.setFill()
        active.fill()
    }
}
