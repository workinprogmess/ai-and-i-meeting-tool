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
    
    // MARK: - session timing
    private var sessionID: String = ""
    private var sessionStartTime: Date = Date()
    private var sessionReferenceTime: TimeInterval = 0  // mach time for precision
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
    private let debounceInterval: TimeInterval = 1.5     // airpods jitter protection
    
    // MARK: - public interface
    
    /// starts a new recording session
    func startSession() {
        print("🎙️ starting mic recording session")
        
        // initialize session
        sessionID = UUID().uuidString
        sessionStartTime = Date()
        sessionReferenceTime = Date().timeIntervalSince1970
        segmentNumber = 0
        segmentMetadata.removeAll()
        deviceChangeCount = 0
        
        // start first segment
        startNewSegment()
        isRecording = true
    }
    
    /// ends the recording session and saves metadata
    func endSession() {
        print("🛑 ending mic recording session")
        
        guard isRecording else { return }
        
        // stop current segment
        stopCurrentSegment()
        
        // save session metadata
        saveSessionMetadata()
        
        isRecording = false
    }
    
    /// handles device change during recording
    func handleDeviceChange(reason: String) {
        guard isRecording else { return }
        
        print("🔄 mic device change: \(reason)")
        
        // debounce rapid changes
        let timeSinceLastChange = Date().timeIntervalSince(lastDeviceChangeTime)
        if timeSinceLastChange < debounceInterval {
            print("⏱️ debouncing device change (too rapid)")
            return
        }
        
        // rate limiting
        deviceChangeCount += 1
        if deviceChangeCount > 3 {
            let windowStart = Date().addingTimeInterval(-deviceChangeWindow)
            if lastDeviceChangeTime > windowStart {
                print("⚠️ device changes too frequent - ignoring")
                errorMessage = "devices changing rapidly - holding current mic"
                return
            }
            // reset counter if outside window
            deviceChangeCount = 1
        }
        
        lastDeviceChangeTime = Date()
        
        // check new device quality before switching
        if shouldSwitchToNewDevice() {
            stopCurrentSegment()
            startNewSegment()
        }
    }
    
    // MARK: - private implementation
    
    /// starts a new segment
    private func startNewSegment() {
        print("📝 starting new mic segment #\(segmentNumber + 1)")
        
        // create new audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            errorMessage = "failed to create audio engine"
            return
        }
        
        let inputNode = engine.inputNode  // inputNode is not optional
        
        // get device info
        let inputFormat = inputNode.inputFormat(forBus: 0)
        currentDeviceID = getDeviceID()
        currentDeviceName = getDeviceName()
        
        print("🎤 device: \(currentDeviceName)")
        print("📊 format: \(inputFormat.sampleRate)hz, \(inputFormat.channelCount)ch")
        
        // assess quality
        currentQuality = AudioSegmentMetadata.assessQuality(sampleRate: inputFormat.sampleRate)
        
        // configure agc based on device
        if currentDeviceName.lowercased().contains("airpod") {
            agcEnabled = false  // airpods have their own processing
            currentGain = 1.0
            print("🎧 airpods detected - agc disabled")
        } else if currentDeviceName.lowercased().contains("mac") || currentDeviceName.lowercased().contains("built") {
            agcEnabled = true  // built-in mics need boost
            currentGain = 2.5
            print("🎚️ built-in mic - agc enabled with 2.5x gain")
        } else {
            agcEnabled = false  // other external devices
            currentGain = 1.0
        }
        
        // quality guard - warn on telephony mode
        if currentQuality == .low {
            print("⚠️ low quality detected (\(inputFormat.sampleRate)hz)")
            errorMessage = "mic in low quality mode - recording anyway"
        }
        
        // create segment file
        segmentNumber += 1
        let sessionTimestamp = Int(sessionReferenceTime)
        segmentFilePath = createSegmentFilePath(sessionTimestamp: sessionTimestamp, segmentNumber: segmentNumber)
        
        // create audio file (48khz mono standard)
        let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        audioFile = try? AVAudioFile(forWriting: URL(fileURLWithPath: segmentFilePath),
                                     settings: recordingFormat.settings)
        
        // reset warmup
        isWarmedUp = false
        discardedFrames = 0
        framesCaptured = 0
        
        // record segment start time
        segmentStartTime = Date().timeIntervalSince1970 - sessionReferenceTime
        
        // install tap with warmup logic
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, inputFormat: inputFormat, targetFormat: recordingFormat)
        }
        
        // prepare and start engine
        engine.prepare()
        do {
            try engine.start()
            print("✅ mic segment #\(segmentNumber) started")
        } catch {
            errorMessage = "failed to start audio engine: \(error)"
            print("❌ engine start failed: \(error)")
        }
    }
    
    /// stops current segment and saves metadata
    private func stopCurrentSegment() {
        print("⏹️ stopping mic segment #\(segmentNumber)")
        
        // record end time
        let segmentEndTime = Date().timeIntervalSince1970 - sessionReferenceTime
        
        // stop engine
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        
        // close file
        audioFile = nil
        
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
            // need conversion
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat),
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                         frameCapacity: processedBuffer.frameLength) else {
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
        } else {
            bufferToWrite = processedBuffer
        }
        
        // write to file
        do {
            try audioFile?.write(from: bufferToWrite)
            framesCaptured += Int(bufferToWrite.frameLength)
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