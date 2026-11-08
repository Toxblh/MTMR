import AppKit
import AVFoundation
import Cocoa
import CoreAudio

class VolumeViewController: NSCustomTouchBarItem {
    private(set) var sliderItem: CustomSlider!
    private var currentDeviceId: AudioObjectID = AudioObjectID(0)

    // CoreAudio removes a listener only when it gets the same block object back, so each listener is
    // stored once instead of passing a method reference (a new block per call). The blocks capture self
    // weakly: the previous method references retained the item, so every replaced item stayed alive and
    // kept reacting to volume changes (116 instances after 1.5 h on an M1).
    private var routeListener: AudioObjectPropertyListenerBlock?
    private var volumeListener: AudioObjectPropertyListenerBlock?

    /// Setting the volume takes ~17 ms and the mute flag ~12 ms (median on an M1, p95 over 50 ms together),
    /// which held the main thread on every slider movement. Values are applied on this queue instead, and
    /// a drag only sends the newest value once the previous one is done.
    private let applyQueue = DispatchQueue(label: "com.toxblh.mtmr.volume")
    private var pendingVolume: Float32? // main thread
    private var isApplying = false // main thread

    init(identifier: NSTouchBarItem.Identifier, image: NSImage? = nil) {
        super.init(identifier: identifier)

        if image == nil {
            sliderItem = CustomSlider()
        } else {
            sliderItem = CustomSlider(knob: image!)
        }
        sliderItem.target = self
        sliderItem.action = #selector(VolumeViewController.sliderValueChanged(_:))
        sliderItem.minValue = 0.0
        sliderItem.maxValue = 100.0
        sliderItem.floatValue = getInputGain() * 100

        view = sliderItem
        sliderItem.applyDefaultTouchBarWidth()

        routeListener = { [weak self] _, _ in DispatchQueue.main.async { self?.audioRouteChanged() } }
        volumeListener = { [weak self] _, _ in DispatchQueue.main.async { self?.showCurrentVolume() } }

        currentDeviceId = defaultDeviceID
        addAudioRouteChangedListener()
        addCurrentAudioVolumeChangedListener()
    }

    private var routeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private func addAudioRouteChangedListener() {
        guard let listener = routeListener else { return }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(bitPattern: kAudioObjectSystemObject), &routeAddress, nil, listener)
    }

    private func audioRouteChanged() {
        removeLastAudioVolumeChangeListener()
        currentDeviceId = defaultDeviceID
        addCurrentAudioVolumeChangedListener()
        showCurrentVolume()
    }

    private func addCurrentAudioVolumeChangedListener() {
        guard let listener = volumeListener else { return }
        AudioObjectAddPropertyListenerBlock(currentDeviceId, &volumeAddress, nil, listener)
    }

    private func removeLastAudioVolumeChangeListener() {
        guard let listener = volumeListener else { return }
        AudioObjectRemovePropertyListenerBlock(currentDeviceId, &volumeAddress, nil, listener)
    }

    private func showCurrentVolume() {
        sliderItem.showSystemValue(getInputGain() * 100)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeLastAudioVolumeChangeListener()
        if let listener = routeListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(bitPattern: kAudioObjectSystemObject), &routeAddress, nil, listener)
        }
        sliderItem.unbind(NSBindingName.value)
    }

    @objc func sliderValueChanged(_ sender: Any) {
        if let sliderItem = sender as? NSSlider {
            pendingVolume = Float32(sliderItem.intValue) / 100.0
            applyPendingVolume()
        }
    }

    private func applyPendingVolume() {
        guard !isApplying, let volume = pendingVolume else { return }
        pendingVolume = nil
        isApplying = true
        applyQueue.async { [weak self] in
            _ = self?.setInputGain(volume)
            DispatchQueue.main.async {
                self?.isApplying = false
                self?.applyPendingVolume()
            }
        }
    }

    private var defaultDeviceID: AudioObjectID {
        var deviceID: AudioObjectID = AudioObjectID(0)
        var size: UInt32 = UInt32(MemoryLayout<AudioObjectID>.size)
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice)
        address.mScope = AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private func getInputGain() -> Float32 {
        var volume: Float32 = 0.5
        var size: UInt32 = UInt32(MemoryLayout.size(ofValue: volume))
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &volume)
        return volume
    }

    private func setInputGain(_ volume: Float32) -> OSStatus {
        var inputVolume: Float32 = volume

        // Only touch the mute flag when it has to change: writing it costs ~12 ms each time.
        let mute = inputVolume == 0.0 ? 1 : 0
        if isMuted != (mute == 1) {
            _ = setMute(mute: mute)
        }

        let size: UInt32 = UInt32(MemoryLayout.size(ofValue: inputVolume))
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        address.mSelector = AudioObjectPropertySelector(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        return AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &inputVolume)
    }

    private var isMuted: Bool? {
        var muteVal: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: muteVal))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &muteVal) == noErr else { return nil }
        return muteVal != 0
    }

    private func setMute(mute: Int) -> OSStatus {
        var muteVal: Int = mute
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress()
        address.mSelector = AudioObjectPropertySelector(kAudioDevicePropertyMute)
        let size: UInt32 = UInt32(MemoryLayout.size(ofValue: muteVal))
        address.mScope = AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput)
        address.mElement = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        return AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &muteVal)
    }
}
