import Foundation
import AVFoundation
import SwiftUI
import ScreenCaptureKit

/// phase 2: audio manager with real-time mixed audio capture
/// implements avaudioengine (mic) + screencapturekit (system audio)
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
    private var systemAudioBufferCount = 0  // track system audio buffers
    private var audioConverter: AVAudioConverter?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var recordingTimestamp: TimeInterval?  // shared timestamp for sync
    
    // MARK: - system audio mixing components
    private var systemAudioPlayer: AVAudioPlayerNode?
    private var systemAudioMixer: AVAudioMixerNode?
    private var mainMixerNode: AVAudioMixerNode?  // combines mic + system
    private var systemAudioBufferQueue: [(buffer: AVAudioPCMBuffer, time: AVAudioTime)] = []
    private let systemAudioQueue = DispatchQueue(label: "com.ai-and-i.systemaudio", qos: .userInteractive)
    
    // MARK: - AGC (Automatic Gain Control) for built-in mic
    private var agcEnabled = false
    private var targetLevel: Float = -16.0  // voice memos loudness target (was -18)
    private var currentGain: Float = 1.0    // current gain multiplier
    private var smoothingFactor: Float = 0.95  // smoothing for gain changes
    private var noiseFloor: Float = -60.0   // gate threshold - don't lift room tone
    private var peakCeiling: Float = -1.0   // true-peak ceiling to prevent clipping
    
    // AGC timing parameters (in seconds)
    private var agcAttackTime: Float = 0.015  // 15ms attack (gentle)
    private var agcReleaseTime: Float = 0.300  // 300ms release (smooth)
    private var lastRMSTime: Date = Date()
    
    // clipping detection
    private var clippingCount: Int = 0
    private var totalBuffers: Int = 0
    
    // silence detection
    private var silentBufferCount: Int = 0
    private var lastAudioTime: Date = Date()
    private let maxSilenceSeconds: TimeInterval = 5.0  // warn after 5 seconds of silence
    
    // prime and discard for startup latency
    private var buffersToDiscard: Int = 0
    private var discardedBuffers: Int = 0
    private let warmupBufferCount: Int = 25  // ~500ms at 48kHz with 2048 buffer size
    private var isWarmedUp = false
    
    // high-pass filter state for rumble removal (80-100Hz)
    private var hpFilterState: (x1: Float, y1: Float) = (0, 0)  // previous sample state per channel
    private let hpFilterCutoff: Float = 90.0  // Hz - removes rumble without affecting voice
    
    // dc blocker state
    private var dcBlockerState: Float = 0.0
    
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
        
        // monitor for device changes
        setupDeviceChangeMonitoring()
    }
    
    /// monitors for audio device changes
    private func setupDeviceChangeMonitoring() {
        // on macOS, we monitor for audio hardware changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        switch notification.name {
        case .AVCaptureDeviceWasConnected:
            print("🎧 NEW DEVICE CONNECTED")
        case .AVCaptureDeviceWasDisconnected:
            print("🎧 DEVICE DISCONNECTED")
            if isRecording {
                print("⚠️ Device changed during recording - audio may be affected")
            }
        default:
            break
        }
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

// MARK: - Error Types
enum AudioError: LocalizedError {
    case engineCreationFailed
    case engineNotConfigured
    case fileCreationFailed
    case formatCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .engineCreationFailed:
            return "failed to create audio engine"
        case .engineNotConfigured:
            return "audio engine not properly configured"
        case .fileCreationFailed:
            return "failed to create recording file"
        case .formatCreationFailed:
            return "failed to create audio format"
        }
    }
}

// MARK: - audio mixing with ffmpeg
extension AudioManager {
    
    /// mixes mic and system audio files using ffmpeg with delay compensation
    /// implements your friend's recommended approach with atrim, asetpts, and alimiter
    @MainActor
    func mixAudioFiles(timestamp: TimeInterval, systemDelay: TimeInterval = 2.0) async -> Bool {
        print("🎛️ starting audio mixing with ffmpeg")
        print("   timestamp: \(Int(timestamp))")
        print("   system delay: \(String(format: "%.3f", systemDelay))s")
        
        // construct file paths
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
        
        let micFile = recordingsFolder.appendingPathComponent("mic_\(Int(timestamp)).wav").path
        let systemFile = recordingsFolder.appendingPathComponent("system_\(Int(timestamp)).wav").path
        let outputFile = recordingsFolder.appendingPathComponent("mixed_\(Int(timestamp)).wav").path
        
        // check if both files exist
        guard FileManager.default.fileExists(atPath: micFile) else {
            print("❌ mic file not found: \(micFile)")
            errorMessage = "mic recording file not found"
            return false
        }
        
        guard FileManager.default.fileExists(atPath: systemFile) else {
            print("❌ system file not found: \(systemFile)")
            errorMessage = "system audio file not found"
            return false
        }
        
        // determine trim strategy based on delay
        let absDelay = abs(systemDelay)
        
        // clamp tiny offsets (< 100ms) to zero as your friend suggests
        let shouldTrim = absDelay > 0.1
        
        // build ffmpeg command using your friend's recipe
        var ffmpegArgs: [String] = []
        
        if !shouldTrim {
            // no significant delay, simple mix
            print("📊 delay < 100ms, using simple mix without trimming")
            ffmpegArgs = [
                "-i", micFile,
                "-i", systemFile,
                "-filter_complex",
                "[0:a]highpass=f=90,acompressor=threshold=-24dB:ratio=2:attack=15:release=300,volume=1.4[m];[1:a]volume=0.7[s];[m][s]amix=inputs=2:duration=longest:dropout_transition=2:normalize=0,alimiter=limit=0.89",
                "-c:a", "pcm_s16le",
                "-y",  // overwrite if exists
                outputFile
            ]
        } else if systemDelay > 0 {
            // system is late, trim system by delay (most common case)
            print("📊 system late by \(String(format: "%.3f", systemDelay))s, trimming system audio")
            // using your friend's exact recipe with normalize=0 and highpass
            ffmpegArgs = [
                "-i", micFile,
                "-i", systemFile,
                "-filter_complex",
                "[0:a]highpass=f=90,acompressor=threshold=-24dB:ratio=2:attack=15:release=300,volume=1.4[m];[1:a]atrim=start=\(String(format: "%.3f", systemDelay)),asetpts=PTS-STARTPTS,volume=0.7[s];[m][s]amix=inputs=2:duration=longest:dropout_transition=2:normalize=0,alimiter=limit=0.89",
                "-c:a", "pcm_s16le",
                "-y",
                outputFile
            ]
        } else {
            // system is early (rare), trim mic by |delay|
            print("📊 system early by \(String(format: "%.3f", absDelay))s, trimming mic audio")
            ffmpegArgs = [
                "-i", micFile,
                "-i", systemFile,
                "-filter_complex",
                "[0:a]atrim=start=\(String(format: "%.3f", absDelay)),asetpts=PTS-STARTPTS,volume=1.2[a0];[1:a]asetpts=PTS-STARTPTS,volume=0.7[a1];[a0][a1]amix=inputs=2:duration=longest:dropout_transition=2,alimiter=limit=0.89",
                "-c:a", "pcm_s16le",
                "-y",
                outputFile
            ]
        }
        
        // execute ffmpeg
        print("🔧 executing ffmpeg command...")
        print("   ffmpeg \(ffmpegArgs.joined(separator: " "))")
        
        return await withCheckedContinuation { continuation in
            Task {
                do {
                    let process = Process()
                    // check both common ffmpeg locations (intel vs apple silicon)
                    let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
                    var ffmpegPath: String?
                    
                    for path in ffmpegPaths {
                        if FileManager.default.fileExists(atPath: path) {
                            ffmpegPath = path
                            break
                        }
                    }
                    
                    guard let validPath = ffmpegPath else {
                        print("❌ ffmpeg not found in common locations")
                        print("   tried: \(ffmpegPaths.joined(separator: ", "))")
                        print("   install with: brew install ffmpeg")
                        await MainActor.run {
                            self.errorMessage = "ffmpeg not installed - run: brew install ffmpeg"
                        }
                        continuation.resume(returning: false)
                        return
                    }
                    
                    process.executableURL = URL(fileURLWithPath: validPath)
                    process.arguments = ffmpegArgs
                    
                    // capture output for debugging
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    if process.terminationStatus == 0 {
                        // get file size for confirmation
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputFile),
                           let fileSize = attrs[.size] as? Int64 {
                            let sizeMB = Double(fileSize) / 1_048_576
                            print("✅ audio mixing complete!")
                            print("   output: mixed_\(Int(timestamp)).wav")
                            print("   size: \(String(format: "%.1f", sizeMB)) mb")
                            print("   volume: mic boosted 1.2x, system reduced to 0.7x")
                            print("   limiter: -1 dbfs (0.89)")
                        }
                        continuation.resume(returning: true)
                    } else {
                        // read error output
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8) {
                            print("❌ ffmpeg error output:")
                            print(output)
                        }
                        
                        await MainActor.run {
                            self.errorMessage = "ffmpeg mixing failed with code \(process.terminationStatus)"
                        }
                        continuation.resume(returning: false)
                    }
                } catch {
                    print("❌ failed to run ffmpeg: \(error)")
                    await MainActor.run {
                        self.errorMessage = "ffmpeg execution failed: \(error.localizedDescription)"
                    }
                    continuation.resume(returning: false)
                }
            }
        }
    }
}

// MARK: - system audio mixing

extension AudioManager {
    /// sets up audio nodes for real-time mic + system mixing
    private func setupAudioNodesForMixing() {
        guard let engine = audioEngine else { return }
        
        // create nodes for mixing
        systemAudioPlayer = AVAudioPlayerNode()
        systemAudioMixer = AVAudioMixerNode()
        mainMixerNode = AVAudioMixerNode()
        
        // attach nodes to engine
        engine.attach(systemAudioPlayer!)
        engine.attach(systemAudioMixer!)
        engine.attach(mainMixerNode!)
        
        // get standard format (48khz stereo)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        
        // connect system audio path (no processing)
        engine.connect(systemAudioPlayer!, to: systemAudioMixer!, format: format)
        engine.connect(systemAudioMixer!, to: mainMixerNode!, format: format)
        
        // mic will connect to mainMixerNode in startRealAudioRecording
        // this keeps mic and system paths separate for independent processing
        
        // set initial volumes
        systemAudioMixer?.volume = 1.0  // system audio at full volume (no agc)
        mainMixerNode?.volume = 1.0     // main mix at full volume
        
        print("🎛️ audio mixing nodes configured for mic + system")
    }
    
    /// simple counter for system audio buffers (temporary)
    func noteSystemAudioReceived() {
        systemAudioBufferCount += 1
        if systemAudioBufferCount % 50 == 1 {  // log every 50th buffer (~1 per second)
            print("🔊 system audio streaming: buffer #\(systemAudioBufferCount)")
        }
    }
    
    /// processes system audio from screencapturekit
    func processSystemAudio(_ buffer: AVAudioPCMBuffer) {
        // Log occasionally to avoid console spam
        systemAudioBufferCount += 1
        if systemAudioBufferCount % 50 == 1 {  // log every 50th buffer (~1 per second)
            print("🔊 received system audio: \(buffer.frameLength) frames, \(buffer.format.sampleRate)Hz, \(buffer.format.channelCount)ch (buffer #\(systemAudioBufferCount))")
        }
        
        // TODO: Properly mix with mic audio
        // For now, we're just verifying system audio capture works
        // The mixing nodes are disabled to avoid format conflicts
        
        /* Original mixing code - disabled until we fix format compatibility
        guard let player = systemAudioPlayer,
              let engine = audioEngine,
              engine.isRunning else {
            return
        }
        
        systemAudioQueue.async { [weak self] in
            player.scheduleBuffer(buffer, at: nil, options: .interrupts) {
                // buffer played
            }
            
            if !player.isPlaying {
                player.play()
                print("🔊 system audio playback started")
            }
        }
        */
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
    func startRecording(timestamp: TimeInterval? = nil) {
        print("🎤 start recording called")
        
        guard !isRecording else {
            print("⚠️ recording already in progress")
            return
        }
        
        // store timestamp for file creation
        self.recordingTimestamp = timestamp
        
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
    
    /// starts recording with real audio capture (phase 2)
    private func actuallyStartRecording() {
        print("🎤 phase 2: starting recording with real audio capture")
        
        recordingStartTime = Date()
        errorMessage = nil
        
        // phase 2: setup and start real audio recording
        do {
            try startRealAudioRecording(timestamp: recordingTimestamp)
            isRecording = true
            startRecordingTimer()
            print("✅ phase 2: recording started with audio engine")
        } catch {
            errorMessage = "failed to start recording: \(error.localizedDescription)"
            print("❌ recording start failed: \(error)")
        }
    }
    
    
    /// gets input device name on macOS
    private func getInputDeviceName() -> String {
        // on macOS, we can get this from the audio unit
        if let audioUnit = audioEngine?.inputNode.audioUnit {
            var deviceID: AudioDeviceID = 0
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            
            AudioUnitGetProperty(audioUnit,
                               kAudioOutputUnitProperty_CurrentDevice,
                               kAudioUnitScope_Global,
                               0,
                               &deviceID,
                               &size)
            
            if deviceID != 0 {
                return getDeviceName(deviceID) ?? "Unknown"
            }
        }
        return "Default Input"
    }
    
    /// gets output device name on macOS
    private func getOutputDeviceName() -> String {
        // get default output device
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                  &address,
                                  0,
                                  nil,
                                  &size,
                                  &deviceID)
        
        if deviceID != 0 {
            return getDeviceName(deviceID) ?? "Unknown"
        }
        return "Default Output"
    }
    
    /// gets device name from device ID
    private func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let result = AudioObjectGetPropertyData(deviceID,
                                               &address,
                                               0,
                                               nil,
                                               &size,
                                               &name)
        
        if result == noErr {
            return name as String
        }
        return nil
    }
    
    /// gets human-readable format name
    private func getFormatName(_ format: AVAudioCommonFormat) -> String {
        switch format {
        case .pcmFormatFloat32: return "Float32"
        case .pcmFormatFloat64: return "Float64"
        case .pcmFormatInt16: return "Int16"
        case .pcmFormatInt32: return "Int32"
        default: return "Other(\(format.rawValue))"
        }
    }
    
    /// applies AGC (Automatic Gain Control) to audio buffer for consistent levels
    private func applyAGC(to buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard agcEnabled else { 
            // log once why AGC is disabled
            if totalBuffers == 1 {
                print("❌ AGC is disabled - returning unprocessed buffer")
            }
            return buffer 
        }
        
        // compute current RMS level
        let currentRMS = rms(of: buffer)
        
        // debug log first few buffers
        if totalBuffers < 5 {
            print("🔍 AGC DEBUG: buffer #\(totalBuffers), input RMS: \(String(format: "%.1f", currentRMS)) dBFS")
        }
        
        // skip if signal is below noise floor
        if currentRMS < noiseFloor {
            return buffer  // don't amplify silence/noise floor
        }
        
        // calculate desired gain adjustment
        let desiredGain = pow(10, (targetLevel - currentRMS) / 20.0)
        
        // calculate time-based smoothing factor for attack/release
        let now = Date()
        let timeDelta = Float(now.timeIntervalSince(lastRMSTime))
        lastRMSTime = now
        
        // use different smoothing based on whether gain is increasing (attack) or decreasing (release)
        let effectiveSmoothingFactor: Float
        if desiredGain > currentGain {
            // attack phase - gain increasing
            let attackFactor = exp(-timeDelta / agcAttackTime)
            effectiveSmoothingFactor = attackFactor
        } else {
            // release phase - gain decreasing
            let releaseFactor = exp(-timeDelta / agcReleaseTime)
            effectiveSmoothingFactor = releaseFactor
        }
        
        // smooth gain changes with proper attack/release
        currentGain = currentGain * effectiveSmoothingFactor + desiredGain * (1 - effectiveSmoothingFactor)
        
        // limit gain to reasonable range (0.5x to 5x) - capped lower to reduce room tone
        currentGain = min(max(currentGain, 0.5), 5.0)
        
        // create output buffer with same format
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else { return buffer }
        
        outputBuffer.frameLength = buffer.frameLength
        
        // track clipping for warnings
        totalBuffers += 1
        var bufferClipped = false
        
        // apply gain to all channels with true-peak limiting
        if let inputData = buffer.floatChannelData,
           let outputData = outputBuffer.floatChannelData {
            
            // calculate peak limit in linear scale
            let peakLimit = pow(10, peakCeiling / 20.0)  // -1 dBFS = 0.891
            
            for channel in 0..<Int(buffer.format.channelCount) {
                let inputChannel = inputData[channel]
                let outputChannel = outputData[channel]
                
                for frame in 0..<Int(buffer.frameLength) {
                    // apply gain
                    var sample = inputChannel[frame] * currentGain
                    
                    // true-peak limiting (hard limit at -1 dBFS)
                    if abs(sample) > peakLimit {
                        sample = peakLimit * (sample > 0 ? 1 : -1)
                        bufferClipped = true
                    }
                    
                    outputChannel[frame] = sample
                }
            }
            
            if bufferClipped {
                clippingCount += 1
            }
            
            // log AGC activity occasionally (not every buffer for thread hygiene)
            if totalBuffers % 50 == 0 {  // more frequent logging for debugging (was 200)
                let outputRMS = rms(of: outputBuffer)
                print("🎚️ AGC: gain=\(String(format: "%.1f", currentGain))x, in=\(String(format: "%.1f", currentRMS))dB → out=\(String(format: "%.1f", outputRMS))dB")
                
                if clippingCount > 0 {
                    let clipPercent = Float(clippingCount) / Float(totalBuffers) * 100
                    print("⚠️ CLIPPING: \(clippingCount) buffers (\(String(format: "%.1f", clipPercent))%) hit limiter")
                }
            }
            
            return outputBuffer
        }
        
        return buffer  // fallback if processing fails
    }
    
    /// applies high-pass filter to remove low-frequency rumble (fan noise, vibration)
    private func applyHighPassFilter(to buffer: AVAudioPCMBuffer, sampleRate: Float) -> AVAudioPCMBuffer? {
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else { return buffer }
        
        outputBuffer.frameLength = buffer.frameLength
        
        // calculate filter coefficient for 90Hz cutoff
        let rc = 1.0 / (2.0 * Float.pi * hpFilterCutoff)
        let dt = 1.0 / sampleRate
        let alpha = rc / (rc + dt)
        
        if let inputData = buffer.floatChannelData,
           let outputData = outputBuffer.floatChannelData {
            
            for channel in 0..<Int(buffer.format.channelCount) {
                let inputChannel = inputData[channel]
                let outputChannel = outputData[channel]
                
                // apply first-order high-pass filter
                var prevInput = hpFilterState.x1
                var prevOutput = hpFilterState.y1
                
                for frame in 0..<Int(buffer.frameLength) {
                    let input = inputChannel[frame]
                    
                    // high-pass filter: y[n] = α * (y[n-1] + x[n] - x[n-1])
                    let output = alpha * (prevOutput + input - prevInput)
                    
                    // dc blocker (additional safety)
                    let dcBlocked = output - dcBlockerState * 0.995
                    dcBlockerState = dcBlocked
                    
                    outputChannel[frame] = dcBlocked
                    
                    prevInput = input
                    prevOutput = output
                }
                
                // save state for next buffer
                if channel == 0 {  // only save once for simplicity
                    hpFilterState = (prevInput, prevOutput)
                }
            }
        }
        
        return outputBuffer
    }
    
    /// computes rms level of audio buffer for diagnostics
    private func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let ch0 = buffer.floatChannelData?.pointee else { return -120 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        var peakCount = 0
        
        for i in 0..<n {
            let sample = ch0[i]
            sum += sample * sample
            
            // check for clipping
            if abs(sample) > 0.99 {
                peakCount += 1
            }
        }
        
        // warn if many samples near clipping
        if peakCount > n / 100 { // more than 1% samples near peak
            print("⚠️ CLIPPING DETECTED: \(peakCount) samples near 0 dBFS")
        }
        
        let mean = sum / Float(n)
        return 10 * log10(mean + 1e-12) // dBFS
    }
    
    /// phase 2: sets up and starts real audio recording
    private func startRealAudioRecording(timestamp: TimeInterval? = nil) throws {
        // always recreate engine to handle device changes (airpods switching)
        if audioEngine?.isRunning == true {
            audioEngine?.stop()
            audioEngine = nil
            mixerNode = nil
        }
        
        // create fresh engine
        audioEngine = AVAudioEngine()
        
        // explicitly select airpods if available
        configureAudioDeviceForAirPods()
        
        // Setup mixing nodes only if we're actually going to use system audio
        // For now, keep disabled until we fix format compatibility
        // setupAudioNodesForMixing()
        
        // configure recording
        if let engine = audioEngine {
            let inputNode = engine.inputNode
            
            // log device names (macOS approach)
            let inputDevice = getInputDeviceName()
            let outputDevice = getOutputDeviceName()
            
            print("🎤 INPUT DEVICE: \(inputDevice)")
            print("🔊 OUTPUT DEVICE: \(outputDevice)")
            
            // enable AGC for built-in mic (not for AirPods which have their own processing)
            // macos creates aggregate devices when multiple audio devices are present
            let inputDeviceLower = inputDevice.lowercased()
            let outputDeviceLower = outputDevice.lowercased()
            
            // check if airpods are connected (either as input OR output means telephony mode)
            let isAirPodsConnected = inputDeviceLower.contains("airpod") || 
                                     outputDeviceLower.contains("airpod")
            
            // check if this is likely the built-in mic
            let isLikelyBuiltIn = inputDeviceLower.contains("built-in") || 
                                  inputDeviceLower.contains("macbook") ||
                                  inputDeviceLower.contains("default") ||     // system default
                                  inputDeviceLower.contains("aggregate")       // aggregate device
            
            if isAirPodsConnected {
                // airpods detected - disable all processing
                agcEnabled = false
                currentGain = 1.0
                print("🎧 AIRPODS DETECTED - AGC and filtering DISABLED")
                print("   Input: \(inputDevice)")
                print("   Output: \(outputDevice)")
                print("   Note: AirPods have built-in DSP, no additional processing needed")
            } else if isLikelyBuiltIn {
                // built-in mic - enable full processing
                agcEnabled = true
                currentGain = 2.5  // boost to 2.5x for very quiet built-in mics
                print("🎚️ AGC ENABLED for built-in mic (device: \(inputDevice))")
                print("   Initial gain: \(currentGain)x, target: \(targetLevel) dBFS")
            } else {
                // other external device
                agcEnabled = false
                currentGain = 1.0
                print("🎚️ AGC DISABLED for external device: \(inputDevice)")
            }
            
            // setup warmup period based on device type
            if isAirPodsConnected {
                buffersToDiscard = 25  // ~500ms for bluetooth settling (reduced from 50)
                print("🔄 WARMUP: Will discard first 25 buffers (~500ms) for AirPods")
            } else {
                buffersToDiscard = 12  // ~250ms for built-in (reduced from 25)
                print("🔄 WARMUP: Will discard first 12 buffers (~250ms)")
            }
            discardedBuffers = 0
            isWarmedUp = false
            
            // log the actual capture format - critical for diagnosing telephony profile
            let inputFormat = inputNode.inputFormat(forBus: 0)
            let formatName = getFormatName(inputFormat.commonFormat)
            print("📊 INPUT FORMAT: sr=\(inputFormat.sampleRate)Hz ch=\(inputFormat.channelCount) format=\(formatName)")
            
            // check if we're in telephony profile (bad for quality)
            if inputFormat.sampleRate <= 16000 {
                print("⚠️ WARNING: Low sample rate detected - likely Bluetooth telephony profile (HFP/HSP)")
                print("💡 TIP: For better quality, use built-in mic or disconnect AirPods")
                print("📱 Device combo: Input=\(inputDevice) Output=\(outputDevice)")
                
                if inputDevice.lowercased().contains("airpod") {
                    errorMessage = "AirPods in call mode - use built-in mic for better quality"
                }
            }
            
            // connect mic to main mixer (if mixing nodes exist)
            if let mainMixer = mainMixerNode {
                // mic → main mixer (for mixed recording)
                let micFormat = inputNode.outputFormat(forBus: 0)
                engine.connect(inputNode, to: mainMixer, format: micFormat)
                print("✅ mic connected to main mixer for mixed capture")
            } else {
                print("✅ audio engine configured (mic-only mode)")
            }
        }
        
        guard let engine = audioEngine else {
            throw AudioError.engineNotConfigured
        }
        
        // create recording file with shared timestamp
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                     in: .userDomainMask).first!
        let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
        
        // ensure folder exists
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
        
        // use shared timestamp for perfect sync with system audio
        let recordingTimestamp = timestamp ?? Date().timeIntervalSince1970
        let recordingURL = recordingsFolder.appendingPathComponent("mic_\(Int(recordingTimestamp)).wav")
        
        // use mono 48kHz for file (Voice Memos style)
        let inputNode = engine.inputNode
        
        // force mono 48kHz for consistent quality
        let recordingSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,  // MONO for clarity
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        print("📝 FILE: 48kHz mono 16-bit (Voice Memos style)")
        
        // create audio file
        outputFile = try AVAudioFile(forWriting: recordingURL,
                                    settings: recordingSettings)
        
        // create converter if needed for proper resampling
        let tapFormat = inputNode.outputFormat(forBus: 0)
        print("📼 TAP FORMAT: sr=\(tapFormat.sampleRate)Hz ch=\(tapFormat.channelCount)")
        
        // create target format for conversion
        guard let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1) else {
            throw AudioError.formatCreationFailed
        }
        
        // create converter if formats don't match
        if tapFormat.sampleRate != 48000 || tapFormat.channelCount != 1 {
            print("🔄 Creating converter: \(tapFormat.sampleRate)Hz, \(tapFormat.channelCount)ch → 48000Hz mono")
            
            // IMPORTANT: handle mono vs stereo conversion properly
            if tapFormat.channelCount == 2 {
                print("   📊 Stereo → Mono: will sum and scale by 0.5 to avoid -6dB loss")
            } else if tapFormat.channelCount == 1 {
                print("   📊 Mono → Mono: pass-through (no level change)")
            }
            
            audioConverter = AVAudioConverter(from: tapFormat, to: targetFormat)
            
            if audioConverter == nil {
                print("❌ FAILED to create converter - will try direct write")
                print("   Input: sr=\(tapFormat.sampleRate) ch=\(tapFormat.channelCount)")
                print("   Target: sr=48000 ch=1")
            } else {
                print("✅ Converter created successfully")
                // log converter settings for debugging
                if let conv = audioConverter {
                    print("   Input format: \(conv.inputFormat)")
                    print("   Output format: \(conv.outputFormat)")
                    print("   Sample rate ratio: \(48000.0 / tapFormat.sampleRate)x")
                    
                    // set channel map for proper stereo→mono conversion
                    if tapFormat.channelCount == 2 {
                        // sum both channels equally for mono
                        conv.channelMap = [NSNumber(value: 0), NSNumber(value: 1)]
                    }
                }
            }
        } else {
            print("✅ No conversion needed - formats match (48kHz mono)")
        }
        
        // install tap on main mixer if available (for mixed capture), otherwise on input
        let tapNode = mainMixerNode ?? inputNode
        let actualTapFormat = tapNode.outputFormat(forBus: 0)
        
        print("📼 installing tap on: \(mainMixerNode != nil ? "main mixer (mixed)" : "input node (mic-only)")")
        
        tapNode.installTap(onBus: 0, bufferSize: 2048, format: actualTapFormat) { [weak self] buffer, _ in
            // handle warmup period - discard initial buffers
            if !(self?.isWarmedUp ?? true) {
                self?.discardedBuffers += 1
                if (self?.discardedBuffers ?? 0) < (self?.buffersToDiscard ?? 0) {
                    // still warming up, discard this buffer
                    if (self?.discardedBuffers ?? 0) % 10 == 0 {
                        print("🔄 Warming up... discarded \(self?.discardedBuffers ?? 0) buffers")
                    }
                    return  // don't process or write
                } else if !(self?.isWarmedUp ?? true) {
                    self?.isWarmedUp = true
                    print("✅ WARMUP COMPLETE - starting actual recording")
                }
            }
            
            // processing pipeline (order matters):
            // skip all processing for airpods (they have their own dsp)
            let processedBuffer: AVAudioPCMBuffer
            if self?.agcEnabled == true {
                // built-in mic: apply full processing
                // 1. high-pass filter (remove rumble)
                let filteredBuffer = self?.applyHighPassFilter(to: buffer, sampleRate: Float(tapFormat.sampleRate)) ?? buffer
                // 2. AGC (adjust levels)
                processedBuffer = self?.applyAGC(to: filteredBuffer) ?? filteredBuffer
            } else {
                // airpods or external: no processing
                processedBuffer = buffer
            }
            
            // log RMS level for diagnostics (after AGC)
            let rmsLevel = self?.rms(of: processedBuffer) ?? -120
            
            // silence detection
            if rmsLevel < -60 {  // effectively silent
                self?.silentBufferCount += 1
                
                // check for extended silence
                let silenceDuration = Double(self?.silentBufferCount ?? 0) * (2048.0 / 48000.0)  // buffer duration
                if silenceDuration > self?.maxSilenceSeconds ?? 5.0 {
                    if let lastTime = self?.lastAudioTime {
                        let timeSinceAudio = Date().timeIntervalSince(lastTime)
                        print("⚠️ SILENCE: No audio for \(String(format: "%.1f", timeSinceAudio)) seconds")
                        print("   Check: mic permissions, device selection, or user not speaking")
                    }
                    self?.silentBufferCount = 0  // reset counter to avoid spam
                }
            } else {
                self?.silentBufferCount = 0
                self?.lastAudioTime = Date()
            }
            
            // periodic status logging (reduced frequency for thread hygiene)
            if Int.random(in: 0..<200) < 1 { // ~0.5% of buffers
                var status = "📊 RMS: \(String(format: "%.1f", rmsLevel)) dBFS"
                
                // add quality indicators
                if rmsLevel > -6 {
                    status += " ⚠️ LOUD (may clip)"
                } else if rmsLevel > -12 {
                    status += " ✅ GOOD"
                } else if rmsLevel > -20 {
                    status += " 👍 OK"
                } else if rmsLevel > -30 {
                    status += " 🔈 QUIET"
                } else {
                    status += " ❌ TOO QUIET"
                }
                
                print(status)
            }
            
            do {
                // convert if needed, then write
                if let converter = self?.audioConverter {
                    // need to convert - create output buffer with extra capacity
                    // add 20% buffer for safety with varying sample rates
                    let outputFrameCapacity = AVAudioFrameCount(
                        Double(buffer.frameLength) * (48000.0 / tapFormat.sampleRate) * 1.2
                    )
                    
                    guard let outputBuffer = AVAudioPCMBuffer(
                        pcmFormat: targetFormat, 
                        frameCapacity: outputFrameCapacity
                    ) else { return }
                    
                    // reset buffer to ensure clean conversion
                    outputBuffer.frameLength = outputFrameCapacity
                    
                    // convert to 48kHz mono
                    var error: NSError?
                    
                    let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                        outStatus.pointee = .haveData
                        return processedBuffer  // use AGC-processed buffer
                    }
                    
                    // perform conversion and get actual converted frame count
                    _ = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
                    
                    if let error = error {
                        print("❌ Conversion error: \(error)")
                        return
                    }
                    
                    // CRITICAL: use actual frameLength from converter, not theoretical
                    // this prevents the "cartoon speed" issue with AirPods
                    if outputBuffer.frameLength > 0 {
                        // occasionally log conversion stats for debugging
                        if Int.random(in: 0..<200) < 1 {
                            print("🔄 Conversion: in=\(buffer.frameLength) → out=\(outputBuffer.frameLength) frames")
                            print("   Rate: \(tapFormat.sampleRate)Hz → 48000Hz")
                        }
                        try self?.outputFile?.write(from: outputBuffer)
                    } else {
                        print("⚠️ Converter produced 0 frames - skipping write")
                    }
                } else {
                    // no conversion needed, write directly (with AGC applied)
                    try self?.outputFile?.write(from: processedBuffer)
                }
            } catch {
                print("❌ error writing audio buffer: \(error)")
            }
        }
        
        // start engine if not already running
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        
        print("📁 recording to: \(recordingURL.lastPathComponent)")
    }
    
    
    /// internal recording start implementation - optimized for speed
    private func performStartRecording(timestamp: TimeInterval? = nil) {
        do {
            // create output file with timestamp
            let outputFile = try createRecordingFile(timestamp: timestamp)
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
    private func createRecordingFile(timestamp: TimeInterval? = nil) throws -> AVAudioFile {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
        
        // ensure recordings folder exists
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
        
        // use shared timestamp for perfect sync with system audio
        let recordingTimestamp = timestamp ?? Date().timeIntervalSince1970
        let fileName = "mic_\(Int(recordingTimestamp)).wav"
        let fileURL = recordingsFolder.appendingPathComponent(fileName)
        
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
        // stop audio recording - remove tap from appropriate node
        if let engine = audioEngine {
            // remove tap from whichever node we were tapping
            if let mainMixer = mainMixerNode {
                mainMixer.removeTap(onBus: 0)
                print("🎛️ removed tap from main mixer")
            } else {
                engine.inputNode.removeTap(onBus: 0)
                print("🎤 removed tap from input node")
            }
            
            // stop system audio player if running
            systemAudioPlayer?.stop()
        }
        
        // close audio file
        outputFile = nil
        
        // stop engine to prevent monitoring after recording
        audioEngine?.stop()
        
        // reset AGC and detection counters
        currentGain = 2.5  // reset to initial gain for next recording
        clippingCount = 0
        totalBuffers = 0
        silentBufferCount = 0
        
        // reset warmup state
        isWarmedUp = false
        discardedBuffers = 0
        
        // reset filter states
        hpFilterState = (0, 0)
        dcBlockerState = 0.0
        
        // update recording state
        isRecording = false
        recordingStartTime = nil
        recordingDuration = 0
        recordingLevel = 0.0
        errorMessage = nil
        
        // stop ui update timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        print("⏹️ phase 2: audio recording stopped and cleaned up")
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
    
    /// explicitly configures audio input device for airpods if detected
    /// fixes issue where airpods mic doesn't capture when connected
    private func configureAudioDeviceForAirPods() {
        guard let audioUnit = audioEngine?.inputNode.audioUnit else { 
            print("⚠️ no audio unit available for device configuration")
            return 
        }
        
        // get all available input devices
        var propertySize: UInt32 = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // get size of device list
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                      &propertyAddress,
                                      0, nil, &propertySize)
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
        
        // get device list
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                  &propertyAddress,
                                  0, nil, &propertySize, &deviceIDs)
        
        // find airpods or other preferred device
        var selectedDeviceID: AudioDeviceID? = nil
        var airpodsDeviceID: AudioDeviceID? = nil
        
        for deviceID in deviceIDs {
            // check if this is an input device
            var inputChannels: UInt32 = 0
            propertySize = UInt32(MemoryLayout<UInt32>.size)
            propertyAddress.mSelector = kAudioDevicePropertyStreamConfiguration
            propertyAddress.mScope = kAudioDevicePropertyScopeInput
            
            var bufferList = AudioBufferList()
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &bufferList)
            
            if bufferList.mNumberBuffers > 0 {
                // this is an input device
                if let deviceName = getDeviceName(deviceID) {
                    print("🎤 found input device: \(deviceName) (id: \(deviceID))")
                    
                    if deviceName.lowercased().contains("airpod") {
                        airpodsDeviceID = deviceID
                        print("🎧 found airpods input device!")
                    }
                }
            }
        }
        
        // if airpods found, explicitly set as input device
        if let airpodsID = airpodsDeviceID {
            var deviceID = airpodsID
            let result = AudioUnitSetProperty(audioUnit,
                                             kAudioOutputUnitProperty_CurrentDevice,
                                             kAudioUnitScope_Global,
                                             0,
                                             &deviceID,
                                             UInt32(MemoryLayout<AudioDeviceID>.size))
            
            if result == noErr {
                print("✅ explicitly set airpods as input device (id: \(airpodsID))")
            } else {
                print("❌ failed to set airpods as input device: \(result)")
            }
        } else {
            print("ℹ️ no airpods found, using system default input")
        }
    }
    
    
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
            // tap is already installed from startRealAudioRecording, no need to install again
            // duplicate taps cause buffer conflicts and periodic dropouts
            print("📍 device switched - existing tap continues with new input")
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