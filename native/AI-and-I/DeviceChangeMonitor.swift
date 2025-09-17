//
//  DeviceChangeMonitor.swift
//  AI-and-I
//
//  monitors audio device changes and notifies recorders
//  uses core audio property listeners for maximum reliability
//

import Foundation
import AVFoundation
import CoreAudio

/// monitors audio device changes and coordinates recorder responses
@MainActor
class DeviceChangeMonitor: ObservableObject {
    // MARK: - callbacks
    var onMicDeviceChange: ((String) -> Void)?
    var onSystemDeviceChange: ((String) -> Void)?
    
    // MARK: - published state
    @Published var currentInputDevice: String = "unknown"
    @Published var currentOutputDevice: String = "unknown"
    @Published var isMonitoring = false
    
    // MARK: - monitoring state
    private var propertyListenerAdded = false
    private var lastChangeTime = Date.distantPast
    private let debounceInterval: TimeInterval = 1.0  // 1 second debounce
    
    // MARK: - core audio property listener
    private var audioObjectPropertyListenerBlock: AudioObjectPropertyListenerBlock?
    
    // MARK: - public interface
    
    /// starts monitoring for device changes
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("🎧 starting device change monitoring")
        
        // setup core audio property listeners (most reliable on macos)
        setupCoreAudioListeners()
        
        // setup macOS-specific notifications (backup)
        setupAVAudioSessionNotifications()
        
        // setup avaudioengine notifications (additional signal)
        setupAudioEngineNotifications()
        
        // get initial device state
        updateCurrentDevices()
        
        isMonitoring = true
        print("✅ device monitoring active")
    }
    
    /// stops monitoring for device changes
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("🛑 stopping device change monitoring")
        
        // remove core audio listeners
        removeCoreAudioListeners()
        
        // remove notifications
        NotificationCenter.default.removeObserver(self)
        
        isMonitoring = false
    }
    
    // MARK: - core audio property listeners (primary detection)
    
    private func setupCoreAudioListeners() {
        // create listener block
        audioObjectPropertyListenerBlock = { [weak self] (numberAddresses, addresses) in
            Task { @MainActor in
                self?.handleCoreAudioPropertyChange(addresses: addresses, count: numberAddresses)
            }
        }
        
        // monitor default input device changes
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let inputResult = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputAddress,
            nil,
            audioObjectPropertyListenerBlock!
        )
        
        if inputResult == noErr {
            print("✅ core audio input device listener registered")
        } else {
            print("❌ failed to register input listener: \(inputResult)")
        }
        
        // monitor default output device changes
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let outputResult = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputAddress,
            nil,
            audioObjectPropertyListenerBlock!
        )
        
        if outputResult == noErr {
            print("✅ core audio output device listener registered")
        } else {
            print("❌ failed to register output listener: \(outputResult)")
        }
        
        // monitor all device list changes (covers hotplug events)
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let devicesResult = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            nil,
            audioObjectPropertyListenerBlock!
        )
        
        if devicesResult == noErr {
            print("✅ core audio device list listener registered")
            propertyListenerAdded = true
        } else {
            print("❌ failed to register device list listener: \(devicesResult)")
        }
    }
    
    private func removeCoreAudioListeners() {
        guard propertyListenerAdded else { return }
        
        // remove all listeners
        let addresses = [
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            ),
            AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDevices,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        ]
        
        for var address in addresses {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                nil,
                audioObjectPropertyListenerBlock!
            )
        }
        
        propertyListenerAdded = false
        print("✅ core audio listeners removed")
    }
    
    @MainActor
    private func handleCoreAudioPropertyChange(addresses: UnsafePointer<AudioObjectPropertyAddress>,
                                              count: UInt32) {
        // CRITICAL: Never call Core Audio functions inside a Core Audio callback!
        // Just schedule the work for later to avoid deadlock
        
        // debounce rapid changes
        let now = Date()
        if now.timeIntervalSince(lastChangeTime) < debounceInterval {
            print("⏱️ debouncing rapid device change")
            return
        }
        lastChangeTime = now
        
        // check what changed and schedule deferred handling
        for i in 0..<Int(count) {
            let address = addresses[i]
            
            switch address.mSelector {
            case kAudioHardwarePropertyDefaultInputDevice:
                print("🎤 default input device changed")
                // Defer the actual work to avoid deadlock
                DispatchQueue.main.async { [weak self] in
                    self?.handleInputDeviceChange(reason: "default input changed")
                    self?.updateCurrentDevices()
                }
                
            case kAudioHardwarePropertyDefaultOutputDevice:
                print("🔊 default output device changed")
                // Defer the actual work to avoid deadlock
                DispatchQueue.main.async { [weak self] in
                    self?.handleOutputDeviceChange(reason: "default output changed")
                    self?.updateCurrentDevices()
                }
                
            case kAudioHardwarePropertyDevices:
                print("📱 device list changed (hotplug event)")
                // Defer the actual work to avoid deadlock
                DispatchQueue.main.async { [weak self] in
                    self?.handleDeviceListChange()
                    self?.updateCurrentDevices()
                }
                
            default:
                break
            }
        }
    }
    
    // MARK: - macos-specific notifications (backup detection)
    
    private func setupAVAudioSessionNotifications() {
        // on macos, we use different notifications
        // AVAudioSession is iOS-only, so we rely on:
        // 1. Core Audio property listeners (primary - already setup)
        // 2. AVAudioEngine notifications (already setup)
        // 3. NSSound notifications (less useful for our needs)
        
        print("✅ macOS audio notifications configured")
        // core audio property listeners are our primary detection method on macOS
    }
    
    // removed @objc handleAudioRouteChange - AVAudioSession is iOS-only
    
    // MARK: - avaudioengine notifications (additional signal)
    
    private func setupAudioEngineNotifications() {
        // monitor configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
        
        print("✅ avaudioengine configuration observer registered")
    }
    
    @objc private func handleEngineConfigurationChange(notification: Notification) {
        Task { @MainActor in
            print("⚙️ audio engine configuration changed")
            handleInputDeviceChange(reason: "engine configuration changed")
        }
    }
    
    // MARK: - device change handlers
    
    private func handleInputDeviceChange(reason: String) {
        print("🎤 input device change: \(reason)")
        
        // get new device info
        let newDevice = getCurrentInputDeviceName()
        if newDevice != currentInputDevice {
            print("🎤 switched from '\(currentInputDevice)' to '\(newDevice)'")
            currentInputDevice = newDevice
            
            // notify mic recorder
            onMicDeviceChange?(reason)
        }
    }
    
    private func handleOutputDeviceChange(reason: String) {
        print("🔊 output device change: \(reason)")
        
        // get new device info
        let newDevice = getCurrentOutputDeviceName()
        if newDevice != currentOutputDevice {
            print("🔊 switched from '\(currentOutputDevice)' to '\(newDevice)'")
            currentOutputDevice = newDevice
            
            // output changes might affect system audio capture
            // but typically screencapturekit handles this internally
        }
    }
    
    private func handleDeviceListChange() {
        // device was added or removed
        // check if it affects current defaults
        updateCurrentDevices()
        
        // notify recorders to check their devices
        onMicDeviceChange?("device list changed")
    }
    
    // MARK: - device info helpers
    
    private func updateCurrentDevices() {
        currentInputDevice = getCurrentInputDeviceName()
        currentOutputDevice = getCurrentOutputDeviceName()
        
        print("📱 current devices - input: \(currentInputDevice), output: \(currentOutputDevice)")
    }
    
    private func getCurrentInputDeviceName() -> String {
        // get default input device id
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        // Check for errors - device might be transitioning
        if result != noErr {
            print("⚠️ couldn't get input device (error: \(result))")
            return "transitioning"
        }
        
        if deviceID != 0 {
            return getDeviceName(deviceID) ?? "unknown"
        }
        
        return "built-in microphone"
    }
    
    private func getCurrentOutputDeviceName() -> String {
        // get default output device id
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        if result == noErr && deviceID != 0 {
            return getDeviceName(deviceID) ?? "unknown"
        }
        
        return "built-in speakers"
    }
    
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &name
        )
        
        if result == noErr {
            return name as String
        }
        
        return nil
    }
    
    deinit {
        // can't call async method from deinit
        // cleanup will happen when listeners are removed
        if propertyListenerAdded {
            // remove listeners synchronously
            let addresses = [
                AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                ),
                AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                ),
                AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDevices,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
            ]
            
            if let listenerBlock = audioObjectPropertyListenerBlock {
                for var address in addresses {
                    AudioObjectRemovePropertyListenerBlock(
                        AudioObjectID(kAudioObjectSystemObject),
                        &address,
                        nil,
                        listenerBlock
                    )
                }
            }
        }
        NotificationCenter.default.removeObserver(self)
    }
}