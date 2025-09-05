import Foundation
import AVFoundation
import SwiftUI

/// high-performance audio manager with hot-standby architecture
/// designed for < 200ms recording start latency and zero audio loss
@MainActor
class AudioManager: NSObject, ObservableObject {
    // MARK: - published state for ui binding
    @Published var isRecording = false
    @Published var recordingLevel: Float = 0.0
    @Published var currentDevices: [AudioDevice] = []
    @Published var selectedMicDevice: AudioDevice?
    @Published var selectedSpeakerDevice: AudioDevice?
    @Published var recordingDuration: TimeInterval = 0
    @Published var errorMessage: String?
    
    // MARK: - core audio components for hot-standby architecture
    private var audioEngine: AVAudioEngine!
    private var micInput: AVAudioInputNode!
    private var mixerNode: AVAudioMixerNode!
    private var outputFile: AVAudioFile?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    // MARK: - hot-standby state management
    private var isEngineReady = false
    private var isPermissionGranted = false
    private var standbyConfigured = false
    
    // MARK: - performance monitoring integration
    private var performanceMonitor: PerformanceMonitor?
    
    // MARK: - professional audio configuration
    private let sampleRate: Double = 44100.0 // cd quality for professional recording
    private let bitDepth: Int = 16 // standard pcm bit depth
    private let channelCount: UInt32 = 2 // stereo for full spatial capture
    
    // MARK: - initialization with hot-standby preparation
    override init() {
        super.init()
        print("🎤 audio manager initializing...")
        
        // prepare non-blocking hot-standby architecture
        prepareBasicHotStandby()
    }
    
    deinit {
        // cleanup audio resources - deinit can't call @MainActor methods
        audioEngine?.stop()
        recordingTimer?.invalidate()
    }
    
    /// connects performance monitor for real-time metrics tracking
    func setPerformanceMonitor(_ monitor: PerformanceMonitor) {
        self.performanceMonitor = monitor
    }
    
    /// prepares hot-standby architecture - NO audio operations during init
    private func prepareBasicHotStandby() {
        print("🔥 preparing hot-standby architecture - no audio operations during init")
        
        // just mark as configured for ui state - no audio operations
        standbyConfigured = true
        
        print("✅ hot-standby architecture prepared - audio operations deferred until user action")
    }
    
    /// requests audio permissions on background thread to avoid main thread blocking
    private func requestBasicAudioPermissions() async {
        print("🔑 requesting audio permissions on background thread...")
        
        return await withCheckedContinuation { continuation in
            // move permission request to background thread
            Task.detached {
                let granted = await withCheckedContinuation { permissionContinuation in
                    DispatchQueue.main.async {
                        AVAudioApplication.requestRecordPermission { granted in
                            permissionContinuation.resume(returning: granted)
                        }
                    }
                }
                
                // update state on main thread
                await MainActor.run {
                    self.isPermissionGranted = granted
                    if granted {
                        print("🔓 audio permissions granted")
                    } else {
                        print("❌ audio permissions denied")
                    }
                }
                
                continuation.resume()
            }
        }
    }
    
    /// phase 1: no audio engine setup to avoid any hanging issues
    private func setupBasicAudioEngine() {
        print("🎚️ phase 1: audio engine setup completely deferred to phase 2")
        
        // phase 1: mark as ready without actual engine creation
        isEngineReady = true
        
        print("🎚️ phase 1: simulated engine ready for ui testing")
    }
}

// MARK: - hot-standby architecture implementation
extension AudioManager {
    
    /// initializes complete hot-standby system for instant recording capability
    private func initializeHotStandby() async {
        print("🔥 initializing hot-standby audio architecture...")
        
        // request permissions first - required for audio engine setup
        await requestAudioPermissions()
        
        guard isPermissionGranted else {
            errorMessage = "audio permissions required for recording"
            return
        }
        
        // configure audio engine for standby mode
        setupAudioEngine()
        
        // start engine in hot-standby mode
        await startHotStandbyMode()
        
        // enumerate available audio devices
        refreshAudioDevices()
        
        print("🎤 hot-standby audio architecture ready - recording latency < 200ms")
    }
    
    /// requests audio recording permissions with async/await
    private func requestAudioPermissions() async {
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isPermissionGranted = granted
                    if granted {
                        print("🔓 audio permissions granted")
                    } else {
                        print("❌ audio permissions denied - recording disabled")
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    /// configures avaudioengine with professional settings for mixed capture
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        micInput = audioEngine.inputNode
        mixerNode = AVAudioMixerNode()
        
        // configure professional audio format (44.1khz, 16-bit, stereo)
        let audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!
        
        // attach mixer node to engine
        audioEngine.attach(mixerNode)
        
        // connect input to mixer for processing
        audioEngine.connect(micInput, to: mixerNode, format: audioFormat)
        
        // connect mixer to main output for monitoring (optional)
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        
        print("🎚️ audio engine configured: \(sampleRate)hz, \(channelCount) channels")
    }
    
    /// starts audio engine in hot-standby mode for instant recording (macos-native)
    private func startHotStandbyMode() async {
        do {
            // macos audio is simpler - no session management needed
            // avaudioengine handles device routing and permissions automatically
            
            // start audio engine in standby mode
            try audioEngine.start()
            
            isEngineReady = true
            standbyConfigured = true
            
            print("🔥 hot-standby mode activated - macos audio engine ready for instant recording")
            
        } catch {
            errorMessage = "failed to initialize hot-standby: \(error.localizedDescription)"
            print("❌ hot-standby initialization failed: \(error)")
            isEngineReady = false
        }
    }
}

// MARK: - recording control with microsecond precision
extension AudioManager {
    
    /// starts recording with lazy permissions and engine setup
    func startRecording() {
        print("🎤 start recording called")
        
        guard !isRecording else {
            print("⚠️ recording already in progress")
            return
        }
        
        // measure recording start latency with performance monitor
        Task { @MainActor in
            await performanceMonitor?.measureAsyncOperation("recording_start") { [weak self] in
                print("📊 measuring recording start...")
                await self?.ensureAudioPermissionsAndStartRecording()
            }
        }
    }
    
    /// user-initiated permission and recording flow
    private func ensureAudioPermissionsAndStartRecording() async {
        print("🎤 user initiated recording - checking audio system readiness...")
        
        // check current permission status without triggering any audio operations
        let currentPermissionStatus = AVAudioApplication.shared.recordPermission
        
        switch currentPermissionStatus {
        case .granted:
            print("🔓 audio permissions already granted")
            isPermissionGranted = true
            await startRecordingWithPermissions()
            
        case .denied:
            print("❌ audio permissions previously denied")
            errorMessage = "microphone access required - please enable in system preferences"
            
        case .undetermined:
            print("🔑 requesting audio permissions for first time...")
            await requestAudioPermissionsFromUser()
            
        @unknown default:
            print("⚠️ unknown permission status")
            errorMessage = "unable to determine microphone permissions"
        }
    }
    
    /// requests permissions only when user explicitly tries to record
    private func requestAudioPermissionsFromUser() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
            
        await MainActor.run {
            self.isPermissionGranted = granted
            if granted {
                print("🔓 user granted audio permissions")
                Task {
                    await self.startRecordingWithPermissions()
                }
            } else {
                print("❌ user denied audio permissions")
                self.errorMessage = "microphone access required for recording"
            }
        }
    }
    
    /// starts recording after permissions are confirmed (phase 1: no audio engine)
    private func startRecordingWithPermissions() async {
        print("🎚️ phase 1: skipping audio engine setup - state management only...")
        
        await MainActor.run {
            // phase 1: just start recording state without audio engine
            self.actuallyStartRecording()
        }
    }
    
    /// starts recording state management (phase 1: no actual audio capture)
    private func actuallyStartRecording() {
        print("🎤 phase 1: starting recording state management (no audio capture)...")
        
        // update recording state
        isRecording = true
        recordingStartTime = Date()
        errorMessage = nil
        
        // start ui update timer for recording duration display
        startRecordingTimer()
        
        print("✅ phase 1: recording state started successfully (ui simulation)")
    }
    
    
    /// internal recording start implementation - optimized for speed
    private func performStartRecording() {
        do {
            // create output file with timestamp
            let outputFile = try createRecordingFile()
            self.outputFile = outputFile
            
            // configure audio format matching engine format
            let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!
            
            // install tap on mixer node for real-time audio capture
            mixerNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer, at: time)
            }
            
            // update recording state
            isRecording = true
            recordingStartTime = Date()
            errorMessage = nil
            
            // start ui update timer for recording duration and levels
            startRecordingTimer()
            
            print("🎤 recording started successfully")
            
        } catch {
            errorMessage = "recording start failed: \(error.localizedDescription)"
            print("❌ recording start failed: \(error)")
        }
    }
    
    /// creates timestamped recording file in documents directory
    private func createRecordingFile() throws -> AVAudioFile {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileName = "ai-and-i-recording-\(timestamp).wav"
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        print("📁 creating recording file: \(fileName)")
        
        // create wav file with professional settings
        guard let audioFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount) else {
            throw AudioManagerError.fileCreationFailed("failed to create audio format")
        }
        
        return try AVAudioFile(forWriting: fileURL, settings: audioFormat.settings)
    }
    
    /// stops recording and cleans up state
    func stopRecording() {
        print("⏹️ stop recording called")
        
        guard isRecording else {
            print("⚠️ no recording in progress")
            return
        }
        
        // measure recording stop latency
        performanceMonitor?.measureOperation("recording_stop") { [weak self] in
            print("📊 measuring recording stop...")
            self?.actuallyStopRecording()
            print("✅ recording stopped")
        }
    }
    
    /// actually stops the recording and cleans up state
    private func actuallyStopRecording() {
        // update recording state
        isRecording = false
        recordingStartTime = nil
        recordingDuration = 0
        recordingLevel = 0.0
        errorMessage = nil
        
        // stop ui update timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        print("⏹️ recording stopped and state cleaned up")
    }
    
    /// internal recording stop implementation
    private func performStopRecording() {
        // remove audio tap to stop recording
        mixerNode.removeTap(onBus: 0)
        
        // close output file
        outputFile = nil
        
        // update recording state
        isRecording = false
        recordingStartTime = nil
        recordingDuration = 0
        recordingLevel = 0.0
        
        // stop ui update timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        print("⏹️ recording stopped successfully")
    }
    
    /// processes real-time audio buffer and writes to file
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        do {
            // write audio buffer to file immediately
            try outputFile?.write(from: buffer)
            
            // calculate recording level for ui feedback
            updateRecordingLevel(from: buffer)
            
        } catch {
            print("❌ audio buffer write failed: \(error)")
            performanceMonitor?.recordAudioDropout()
            
            // set error message for ui
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "audio dropout detected - check system performance"
            }
        }
    }
    
    /// calculates audio level from buffer for visual feedback
    private func updateRecordingLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let channelDataPointer = UnsafeBufferPointer(start: channelDataValue, count: Int(buffer.frameLength))
        
        // calculate rms level for meter display
        let rms = sqrt(channelDataPointer.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        
        DispatchQueue.main.async { [weak self] in
            self?.recordingLevel = rms
        }
    }
    
    /// starts timer for recording duration and ui updates
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRecordingMetrics()
            }
        }
    }
    
    /// updates recording duration and other real-time metrics
    private func updateRecordingMetrics() {
        guard let startTime = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)
    }
}

// MARK: - device management for airpods and other audio devices
extension AudioManager {
    
    /// refreshes list of available audio input/output devices
    func refreshAudioDevices() {
        var devices: [AudioDevice] = []
        
        // query all audio hardware devices using core audio
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        
        guard status == noErr else {
            print("❌ failed to get audio device count")
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        
        guard status == noErr else {
            print("❌ failed to get audio device list")
            return
        }
        
        // create audiodevice objects for each hardware device
        for deviceID in deviceIDs {
            if let device = createAudioDevice(from: deviceID) {
                devices.append(device)
            }
        }
        
        currentDevices = devices
        print("🎧 discovered \(devices.count) audio devices")
        
        // auto-select default devices if none selected
        if selectedMicDevice == nil {
            selectedMicDevice = devices.first { $0.isInput }
        }
    }
    
    /// creates AudioDevice object from core audio device id
    private func createAudioDevice(from deviceID: AudioDeviceID) -> AudioDevice? {
        // get device name
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        
        guard status == noErr else { return nil }
        
        var name: CFString?
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        
        guard status == noErr, let deviceName = name as String? else { return nil }
        
        return AudioDevice(
            id: deviceID,
            name: deviceName,
            isInput: hasInputStreams(deviceID: deviceID),
            isOutput: hasOutputStreams(deviceID: deviceID)
        )
    }
    
    /// checks if device supports audio input (microphone capability)
    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: 0
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }
    
    /// checks if device supports audio output (speaker capability)
    private func hasOutputStreams(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: 0
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }
    
    /// switches to different audio device during recording (airpods support)
    func switchToDevice(_ device: AudioDevice) {
        guard device != selectedMicDevice else {
            print("⚠️ device already selected: \(device.name)")
            return
        }
        
        // measure device switch latency for performance tracking
        performanceMonitor?.measureOperation("device_switch") { [weak self] in
            self?.performDeviceSwitch(device)
        }
    }
    
    /// internal device switch implementation
    private func performDeviceSwitch(_ device: AudioDevice) {
        let wasRecording = isRecording
        
        // temporarily pause recording if active
        if wasRecording {
            mixerNode.removeTap(onBus: 0)
        }
        
        // update selected device
        selectedMicDevice = device
        
        // resume recording with new device if it was active
        if wasRecording {
            let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)!
            mixerNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer, at: time)
            }
        }
        
        print("🎧 switched to device: \(device.displayName)")
    }
}

// MARK: - supporting types for audio device management
struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let isInput: Bool
    let isOutput: Bool
    
    /// user-friendly display name with appropriate icons
    var displayName: String {
        if name.lowercased().contains("airpods") {
            return "🎧 \(name)"
        } else if isInput {
            return "🎤 \(name)"
        } else {
            return "🔊 \(name)"
        }
    }
}

// MARK: - error handling for audio operations
enum AudioManagerError: Error, LocalizedError {
    case permissionDenied
    case engineNotReady
    case deviceNotAvailable
    case recordingInProgress
    case fileCreationFailed(String)
    case audioSessionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "audio recording permission denied"
        case .engineNotReady:
            return "audio engine not ready for recording"
        case .deviceNotAvailable:
            return "selected audio device not available"
        case .recordingInProgress:
            return "recording already in progress"
        case .fileCreationFailed(let reason):
            return "failed to create recording file: \(reason)"
        case .audioSessionFailed(let reason):
            return "audio session configuration failed: \(reason)"
        }
    }
}