//
//  MicRecorder.swift
//  AI-and-I
//
//  handles microphone recording with automatic segmentation on device changes
//  maintains independent pipeline from system audio for maximum reliability
//

import Foundation
import AVFoundation
import CoreAudio

/// manages microphone recording with segment-based approach
@MainActor
class MicRecorder: ObservableObject {
    // MARK: - published state
    @Published var isRecording = false
    @Published var currentDeviceName = "unknown"
    @Published var currentQuality: AudioSegmentMetadata.AudioQuality = .high
    @Published var errorMessage: String?
    
    // MARK: - recording state
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var segmentMetadata: [AudioSegmentMetadata] = []
    private let segmentQueue = DispatchQueue(label: "mic.segment.queue", qos: .userInitiated)
    
    // MARK: - thread safety (production-grade)
    private let controllerQueue = DispatchQueue(label: "mic.controller.queue", qos: .userInitiated)
    private let writerQueue = DispatchQueue(label: "mic.writer.queue", qos: .userInitiated)
    private var needsSwitch = false  // atomic flag for pending switches
    private var debounceTimer: DispatchWorkItem?
    
    // MARK: - state machine
    private enum RecordingState {
        case idle
        case recording
        case switching
    }
    private var state: RecordingState = .idle
    
    // MARK: - session timing
    private var sessionID: String = ""
    private var sessionStartTime: Date = Date()
    private var sessionReferenceTime: TimeInterval = 0  // mach time for precision
    
    /// public accessor for the session timestamp (used for mixing)
    var currentSessionTimestamp: Int {
        Int(sessionReferenceTime)
    }
    private var segmentStartTime: TimeInterval = 0
    private var segmentNumber: Int = 0
    private var segmentFilePath: String = ""
    private var currentDeviceID: String = ""
    private var framesCaptured: Int = 0
    
    // MARK: - warmup management
    private var isWarmedUp = false
    private var discardedFrames: AVAudioFrameCount = 0
    private let warmupFrames: AVAudioFrameCount = 24000  // 0.5s at 48khz
    
    // MARK: - agc (automatic gain control)
    private var agcEnabled = true
    private var currentGain: Float = 2.5  // boost for quiet built-in mics
    private let targetLevel: Float = -12.0  // target dBFS
    
    // MARK: - quality control
    private var lastDeviceChangeTime: Date = Date.distantPast
    private var deviceChangeCount: Int = 0
    private let deviceChangeWindow: TimeInterval = 10.0  // for rate limiting
    private let debounceInterval: TimeInterval = 2.5     // airpods need 2-3s to fully connect
    
    // MARK: - public interface
    
    /// starts a new recording session with shared session id
    func startSession(sharedSessionID: String) async {
        print("🎙️ starting mic recording session with id: \(sharedSessionID)")
        
        // use the shared session id
        sessionID = sharedSessionID
        sessionStartTime = Date()
        sessionReferenceTime = Date().timeIntervalSince1970
        segmentNumber = 0
        segmentMetadata.removeAll()
        deviceChangeCount = 0
        
        // set state first
        state = .recording
        isRecording = true
        
        // start first segment on controller queue
        startNewSegment()
    }
    
    /// ends the recording session and saves metadata
    func endSession() {
        print("🛑 ending mic recording session")
        
        guard isRecording else { return }
        
        // cancel any pending switches
        debounceTimer?.cancel()
        needsSwitch = false
        
        // stop current segment
        stopCurrentSegment()
        
        // save session metadata
        saveSessionMetadata()
        
        state = .idle
        isRecording = false
    }
    
    /// handles device change during recording (production-safe)
    func handleDeviceChange(reason: String) {
        guard isRecording else { return }
        
        print("🔄 mic device change: \(reason)")
        
        // NEVER do audio work in the callback - just set flag and schedule
        needsSwitch = true
        
        // if we're already debouncing, don't restart the timer - let it complete
        // this prevents rapid events from constantly resetting the 2.5s delay
        if debounceTimer != nil {
            print("⏱️ already debouncing - ignoring new event to let timer complete")
            return
        }
        
        // schedule new debounce (2.5s for airpods stability - they need time to fully connect)
        let workItem = DispatchWorkItem { [weak self] in
            self?.performDebouncedSwitch()
            self?.debounceTimer = nil  // clear timer after execution
        }
        debounceTimer = workItem
        controllerQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    /// performs the actual switch after debounce (on controller queue)
    private func performDebouncedSwitch() {
        // check conditions
        guard needsSwitch else { return }
        guard state != .switching else {
            print("⏳ already switching - ignoring")
            return
        }
        
        // rate limiting check
        deviceChangeCount += 1
        if deviceChangeCount > 3 {
            let windowStart = Date().addingTimeInterval(-deviceChangeWindow)
            if lastDeviceChangeTime > windowStart {
                print("⚠️ device changes too frequent - holding current mic")
                errorMessage = "devices changing rapidly - holding current mic"
                needsSwitch = false
                return
            }
            deviceChangeCount = 1
        }
        
        lastDeviceChangeTime = Date()
        
        // begin switch
        state = .switching
        needsSwitch = false
        
        print("🔄 performing debounced device switch...")
        
        // safe teardown on controller queue
        stopCurrentSegmentSafely()
        
        // let hardware settle
        Thread.sleep(forTimeInterval: 0.2)
        
        // don't check quality - just switch (checking creates AVAudioEngine which can hang)
        // safe startup on controller queue
        startNewSegmentSafely()
        
        state = .recording
        print("✅ device switch complete")
    }
    
    // MARK: - private implementation
    
    /// starts a new segment (safe version for controller queue)
    private func startNewSegmentSafely() {
        // this runs on controller queue - safe to touch audio
        startNewSegmentInternal()
    }
    
    /// starts a new segment (public interface)
    private func startNewSegment() {
        // dispatch to controller queue for safety
        controllerQueue.async { [weak self] in
            Task { @MainActor in
                self?.startNewSegmentInternal()
            }
        }
    }
    
    /// internal segment start (must be on controller queue)
    private func startNewSegmentInternal() {
        print("📝 starting new mic segment #\(segmentNumber + 1)")
        
        // skip device ID check - it can block during transitions
        // we'll get the device info after engine is created
        
        // create new audio engine (doesn't throw, but can fail)
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            errorMessage = "failed to create audio engine"
            return
        }
        
        // don't try to set device - avaudioengine uses system default automatically
        let inputNode = engine.inputNode  // inputNode is not optional
        
        // get format first (safe to query from engine)
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // defer device name/ID queries until after engine starts
        // for now, use placeholder values
        currentDeviceID = "pending"
        currentDeviceName = "initializing..."
        
        print("📊 input format: \(inputFormat.sampleRate)hz, \(inputFormat.channelCount)ch")
        print("📊 target format: \(recordingFormat.sampleRate)hz, \(recordingFormat.channelCount)ch")
        print("📊 formats equal: \(inputFormat == recordingFormat)")
        
        // assess quality
        currentQuality = AudioSegmentMetadata.assessQuality(sampleRate: inputFormat.sampleRate)
        print("📊 assessed quality: \(currentQuality.rawValue) for \(inputFormat.sampleRate)hz")
        
        // configure agc - will be adjusted after we get device name
        agcEnabled = true  // default to enabled
        currentGain = 2.5
        
        // quality guard - warn on telephony mode
        if currentQuality == .low {
            print("⚠️ low quality detected (\(inputFormat.sampleRate)hz)")
            errorMessage = "mic in low quality mode - recording anyway"
        }
        
        // create segment file
        segmentNumber += 1
        let sessionTimestamp = Int(sessionReferenceTime)
        segmentFilePath = createSegmentFilePath(sessionTimestamp: sessionTimestamp, segmentNumber: segmentNumber)
        
        // create audio file (48khz mono standard, 16-bit PCM)
        let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        
        // use 16-bit PCM format instead of 32-bit float
        var settings = recordingFormat.settings
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMIsBigEndianKey] = false
        
        do {
            audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: segmentFilePath),
                                       settings: settings)
            print("📁 created audio file: \(segmentFilePath)")
        } catch {
            print("❌ failed to create audio file: \(error)")
            errorMessage = "failed to create audio file: \(error.localizedDescription)"
            // clean up engine if file creation fails
            audioEngine = nil
            return
        }
        
        // reset warmup
        isWarmedUp = false
        discardedFrames = 0
        framesCaptured = 0
        
        // record segment start time
        segmentStartTime = Date().timeIntervalSince1970 - sessionReferenceTime
        
        // install tap with warmup logic (NEVER do heavy work in tap callback)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            // enqueue to writer queue - don't process in callback
            self?.writerQueue.async {
                Task { @MainActor in
                    self?.processAudioBuffer(buffer, inputFormat: inputFormat, targetFormat: recordingFormat)
                }
            }
        }
        
        // prepare and start engine (with retry for -10851)
        engine.prepare()
        do {
            try engine.start()
            
            // NOW it's safe to query device info after engine is running
            currentDeviceID = getDeviceID()
            currentDeviceName = getDeviceName()
            
            // adjust AGC based on actual device
            if currentDeviceName.lowercased().contains("airpod") {
                agcEnabled = false  // airpods have their own processing
                currentGain = 1.0
                print("🎧 airpods detected - agc disabled")
                print("🎧 airpods format: \(inputFormat.sampleRate)hz reported")
                print("🎧 airpods quality: \(currentQuality.rawValue)")
            } else if currentDeviceName.lowercased().contains("mac") || currentDeviceName.lowercased().contains("built") {
                agcEnabled = true  // built-in mics need boost
                currentGain = 2.5
                print("🎚️ built-in mic - agc enabled with 2.5x gain")
            } else {
                agcEnabled = false  // other external devices
                currentGain = 1.0
            }
            
            print("✅ mic segment #\(segmentNumber) started - recording with \(currentDeviceName)")
        } catch {
            let nsError = error as NSError
            if nsError.code == -10851 {
                // device still transitioning - need to retry
                print("⚠️ engine start failed with -10851 (device transitioning)")
                errorMessage = "device still transitioning - retrying..."
                
                // clean up this attempt
                engine.inputNode.removeTap(onBus: 0)
                audioEngine = nil
                audioFile = nil
                
                // retry after delay
                controllerQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    Task { @MainActor in
                        guard let self = self else { return }
                        if self.state == .switching || self.state == .recording {
                            print("🔄 retrying segment start after -10851 error...")
                            self.startNewSegmentInternal()
                        }
                    }
                }
            } else {
                errorMessage = "failed to start audio engine: \(error)"
                print("❌ engine start failed: \(error)")
                // clean up on failure
                engine.inputNode.removeTap(onBus: 0)
                audioEngine = nil
                audioFile = nil
            }
        }
    }
    
    /// stops current segment safely (for controller queue)
    private func stopCurrentSegmentSafely() {
        // this runs on controller queue - safe to touch audio
        stopCurrentSegmentInternal()
    }
    
    /// stops current segment (public interface)
    private func stopCurrentSegment() {
        // dispatch to controller queue for safety
        controllerQueue.sync {
            stopCurrentSegmentInternal()
        }
    }
    
    /// internal segment stop (must be on controller queue)
    private func stopCurrentSegmentInternal() {
        print("⏹️ stopping mic segment #\(segmentNumber)")
        
        // record end time
        let segmentEndTime = Date().timeIntervalSince1970 - sessionReferenceTime
        
        // stop engine (non-blocking approach to prevent hangs)
        if let engine = audioEngine {
            print("🔧 removing tap...")
            // remove tap first to stop audio flow
            engine.inputNode.removeTap(onBus: 0)
            print("✅ tap removed")
            
            // DON'T call engine.stop() - it can block during device transitions
            // instead, just abandon the engine and let ARC clean it up
            // this prevents the app from hanging when airpods connect
            print("🔧 abandoning engine (non-blocking)...")
        }
        
        // clear engine reference immediately - let ARC handle cleanup
        audioEngine = nil
        print("✅ engine released")
        
        // close file
        print("🔧 closing file...")
        audioFile = nil
        print("✅ file closed")
        
        // save segment metadata
        let metadata = AudioSegmentMetadata(
            segmentID: UUID().uuidString,
            filePath: segmentFilePath,
            deviceName: currentDeviceName,
            deviceID: currentDeviceID,
            sampleRate: 48000,
            channels: 1,
            startSessionTime: segmentStartTime,
            endSessionTime: segmentEndTime,
            frameCount: framesCaptured,
            quality: currentQuality,
            error: nil
        )
        
        segmentQueue.sync {
            segmentMetadata.append(metadata)
        }
        
        print("📊 segment #\(segmentNumber): \(String(format: "%.1f", segmentEndTime - segmentStartTime))s, \(framesCaptured) frames")
    }
    
    /// processes audio buffer with warmup and conversion
    @MainActor
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer,
                                   inputFormat: AVAudioFormat,
                                   targetFormat: AVAudioFormat) {
        // warmup period - discard initial frames
        if !isWarmedUp {
            discardedFrames += buffer.frameLength
            if discardedFrames >= warmupFrames {
                isWarmedUp = true
                print("🔥 warmup complete - starting actual capture")
            }
            return  // discard this buffer
        }
        
        // apply agc if enabled (for built-in mic)
        let processedBuffer: AVAudioPCMBuffer
        if agcEnabled && currentDeviceName.lowercased().contains("mac") {
            processedBuffer = applyAGC(to: buffer) ?? buffer
        } else {
            processedBuffer = buffer
        }
        
        // convert format if needed
        let bufferToWrite: AVAudioPCMBuffer
        if inputFormat != targetFormat {
            print("🔄 format conversion needed:")
            print("   input: \(inputFormat.sampleRate)hz, \(inputFormat.channelCount)ch")
            print("   target: \(targetFormat.sampleRate)hz, \(targetFormat.channelCount)ch")
            print("   input frames: \(processedBuffer.frameLength)")
            
            // calculate proper output frame capacity for sample rate conversion
            let sampleRateRatio = targetFormat.sampleRate / inputFormat.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(processedBuffer.frameLength) * sampleRateRatio)
            print("   rate ratio: \(sampleRateRatio), output capacity: \(outputFrameCapacity)")
            
            // need conversion
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat),
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                         frameCapacity: outputFrameCapacity) else {
                print("⚠️ format conversion failed")
                return
            }
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return processedBuffer
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                print("⚠️ conversion error: \(error)")
                return
            }
            
            bufferToWrite = convertedBuffer
            print("   converted frames: \(convertedBuffer.frameLength)")
        } else {
            bufferToWrite = processedBuffer
            print("📊 no conversion needed - formats match")
        }
        
        // write to file
        do {
            try audioFile?.write(from: bufferToWrite)
            framesCaptured += Int(bufferToWrite.frameLength)
            
            // log every 10th write to avoid spam
            if framesCaptured % (48000 * 10) < Int(bufferToWrite.frameLength) {
                print("📝 written \(framesCaptured) frames (~\(framesCaptured/48000)s at 48khz)")
            }
        } catch {
            print("❌ write error: \(error)")
            errorMessage = "failed to write audio: \(error.localizedDescription)"
        }
    }
    
    /// checks if we should switch to new device
    private func shouldSwitchToNewDevice() -> Bool {
        // get new device info
        let newDevice = AVAudioEngine().inputNode  // inputNode is not optional
        let newFormat = newDevice.inputFormat(forBus: 0)
        let newQuality = AudioSegmentMetadata.assessQuality(sampleRate: newFormat.sampleRate)
        
        // block auto-switch to telephony mode
        if newQuality == .low && currentQuality != .low {
            print("🚫 blocking switch to low quality device")
            errorMessage = "new device is low quality - staying with current"
            return false
        }
        
        return true
    }
    
    /// gets current input device name
    private func getDeviceName() -> String {
        // on macos, get from audio hardware
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
        
        if result == noErr && deviceID != 0 {
            // get device name
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            let nameResult = AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                &name
            )
            
            if nameResult == noErr {
                return name as String
            }
        }
        
        return "built-in microphone"
    }
    
    /// gets current input device id
    private func getDeviceID() -> String {
        // on macos, use the device ID as string
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        return deviceID != 0 ? String(deviceID) : "built-in"
    }
    
    /// creates segment file path
    private func createSegmentFilePath(sessionTimestamp: Int, segmentNumber: Int) -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
        
        let fileName = SegmentFileNaming.segmentFileName(
            type: .microphone,
            sessionTimestamp: TimeInterval(sessionTimestamp),
            segmentNumber: segmentNumber
        )
        
        return recordingsFolder.appendingPathComponent(fileName).path
    }
    
    /// applies automatic gain control to boost quiet mics
    private func applyAGC(to buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let floatData = buffer.floatChannelData else { return buffer }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // calculate current level (rms)
        var sum: Float = 0
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                let sample = floatData[channel][frame]
                sum += sample * sample
            }
        }
        let rms = sqrt(sum / Float(frameLength * channelCount))
        let currentDB = 20 * log10(max(rms, 0.00001))
        
        // adjust gain to reach target level
        if currentDB < targetLevel - 3 {
            // increase gain (up to 4x)
            currentGain = min(currentGain * 1.1, 4.0)
        } else if currentDB > targetLevel + 3 {
            // decrease gain (down to 1x)
            currentGain = max(currentGain * 0.9, 1.0)
        }
        
        // apply gain
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                floatData[channel][frame] *= currentGain
                // prevent clipping
                floatData[channel][frame] = max(-1.0, min(1.0, floatData[channel][frame]))
            }
        }
        
        return buffer
    }
    
    /// saves session metadata to disk
    private func saveSessionMetadata() {
        let metadata = RecordingSessionMetadata(
            sessionID: sessionID,
            sessionStartTime: sessionStartTime,
            sessionEndTime: Date(),
            micSegments: segmentMetadata,
            systemSegments: []  // will be filled by SystemAudioRecorder
        )
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
        let metadataURL = recordingsFolder.appendingPathComponent("session_\(Int(sessionReferenceTime))_metadata.json")
        
        do {
            try metadata.save(to: metadataURL)
            print("💾 session metadata saved")
        } catch {
            print("❌ failed to save metadata: \(error)")
        }
    }
}