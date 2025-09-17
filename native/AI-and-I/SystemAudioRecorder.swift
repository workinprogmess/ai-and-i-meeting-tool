//
//  SystemAudioRecorder.swift
//  AI-and-I
//
//  handles system audio recording with automatic segmentation
//  operates independently from mic recording for maximum reliability
//

import Foundation
import ScreenCaptureKit
@preconcurrency import AVFoundation

/// manages system audio recording with segment-based approach
@MainActor
class SystemAudioRecorder: NSObject, ObservableObject {
    // MARK: - published state
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var currentQuality: AudioSegmentMetadata.AudioQuality = .high
    
    // MARK: - capture components
    private var stream: SCStream?
    private var streamOutput: SystemStreamOutput?
    private var filter: SCContentFilter?
    
    // MARK: - recording state
    private var audioFile: AVAudioFile?
    private var segmentMetadata: [AudioSegmentMetadata] = []
    private let segmentQueue = DispatchQueue(label: "system.segment.queue", qos: .userInitiated)
    private let fileWriteQueue = DispatchQueue(label: "system.file.write", qos: .userInitiated)
    
    // MARK: - thread safety (production-grade)
    private let controllerQueue = DispatchQueue(label: "system.controller.queue", qos: .userInitiated)
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
    private var sessionReferenceTime: TimeInterval = 0
    private var segmentStartTime: TimeInterval = 0
    private var segmentNumber: Int = 0
    private var segmentFilePath: String = ""
    private var framesCaptured: Int = 0
    
    // MARK: - device info (system audio is display-based)
    private let deviceName = "system audio"
    private let deviceID = "system"
    
    // MARK: - public interface
    
    /// starts a new recording session with shared session id
    func startSession(sharedSessionID: String) async {
        print("🔊 starting system audio recording session with id: \(sharedSessionID)")
        
        // use the shared session id
        sessionID = sharedSessionID
        sessionStartTime = Date()
        sessionReferenceTime = Date().timeIntervalSince1970
        segmentNumber = 0
        segmentMetadata.removeAll()
        
        // set state first
        state = .recording
        isRecording = true
        
        // start first segment
        await startNewSegment()
    }
    
    /// ends the recording session and saves metadata
    func endSession() async {
        print("🛑 ending system audio recording session")
        
        guard isRecording else { return }
        
        // cancel any pending switches
        await MainActor.run {
            debounceTimer?.cancel()
        }
        needsSwitch = false
        
        // stop current segment
        await stopCurrentSegment()
        
        // save session metadata
        saveSessionMetadata()
        
        state = .idle
        isRecording = false
    }
    
    /// handles display/system audio device changes (production-safe)
    func handleDeviceChange(reason: String) async {
        guard isRecording else { return }
        
        print("🔄 system audio change: \(reason)")
        
        // CRITICAL: Never do any work in device change callbacks
        // Just set flag and schedule deferred work to avoid deadlock
        needsSwitch = true
        
        // if we're already debouncing, don't restart the timer - let it complete
        // this prevents rapid events from constantly resetting the delay
        let timerExists = await MainActor.run { debounceTimer != nil }
        if timerExists {
            print("⏱️ already debouncing - ignoring new event to let timer complete")
            return
        }
        
        // schedule new debounce (1s for system audio stability)
        // this gives hardware time to settle and prevents rapid switches
        let workItem = DispatchWorkItem { [weak self] in
            Task {
                await self?.performDebouncedSwitch()
                await MainActor.run {
                    self?.debounceTimer = nil  // clear timer after execution
                }
            }
        }
        
        await MainActor.run {
            debounceTimer = workItem
            controllerQueue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }
    
    /// performs the actual switch after debounce
    private func performDebouncedSwitch() async {
        guard needsSwitch else { return }
        guard state != .switching else {
            print("⏳ already switching - ignoring")
            return
        }
        
        state = .switching
        needsSwitch = false
        
        print("🔄 performing debounced system audio switch...")
        
        // safe teardown
        await stopCurrentSegment()
        
        // let hardware settle
        try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2s
        
        // safe restart
        await startNewSegment()
        
        state = .recording
        print("✅ system audio switch complete")
    }
    
    // MARK: - private implementation
    
    /// starts a new segment
    private func startNewSegment() async {
        print("📝 starting new system segment #\(segmentNumber + 1)")
        
        do {
            // get shareable content (may fail during display changes)
            print("🔍 requesting shareable content...")
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.current
                print("✅ got shareable content")
            } catch {
                // display might be transitioning (external monitor plug/unplug)
                errorMessage = "display transitioning: \(error.localizedDescription)"
                print("⚠️ can't get shareable content (display transitioning): \(error)")
                return
            }
            
            guard let display = content.displays.first else {
                errorMessage = "no display found"
                print("❌ no display found for system audio")
                return
            }
            
            // create filter (exclude our app to prevent feedback)
            let excludedApps = content.applications.filter { app in
                app.applicationName.lowercased().contains("ai&i") ||
                app.applicationName.lowercased().contains("ai-and-i")
            }
            filter = SCContentFilter(display: display,
                                    excludingApplications: excludedApps,
                                    exceptingWindows: [])
            
            // configure stream for audio only
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2  // stereo for system audio
            config.excludesCurrentProcessAudio = true
            
            // set minimal video settings to avoid errors (match working config)
            config.width = 1920
            config.height = 1080
            config.minimumFrameInterval = CMTime(value: 600, timescale: 1)
            config.scalesToFit = false
            
            print("📊 stream config: 48000hz, 2ch, display-wide capture")
            
            // create segment file
            segmentNumber += 1
            let sessionTimestamp = Int(sessionReferenceTime)
            segmentFilePath = createSegmentFilePath(sessionTimestamp: sessionTimestamp,
                                                   segmentNumber: segmentNumber)
            
            // create audio file (48khz stereo for system, 32-bit float)
            let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            
            // keep 32-bit float for system audio (better dynamic range)
            var settings = audioFormat.settings
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 32
            settings[AVLinearPCMIsFloatKey] = true
            settings[AVLinearPCMIsBigEndianKey] = false
            
            audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: segmentFilePath),
                                       settings: settings)
            print("📁 created system audio file: \(segmentFilePath)")
            
            // record segment start time
            segmentStartTime = Date().timeIntervalSince1970 - sessionReferenceTime
            framesCaptured = 0
            
            // create stream (match working ScreenCaptureManager pattern)
            stream = SCStream(filter: filter!, configuration: config, delegate: nil)
            
            // create output handler
            streamOutput = SystemStreamOutput(recorder: self)
            
            // add audio output handler
            let audioQueue = DispatchQueue(label: "system.audio.capture", qos: .userInteractive)
            try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: audioQueue)
            
            // start capture (use optional chaining like working version)
            try await stream?.startCapture()
            
            print("✅ system segment #\(segmentNumber) started")
            
        } catch {
            errorMessage = "system capture failed: \(error.localizedDescription)"
            print("❌ system capture start failed: \(error)")
        }
    }
    
    /// stops current segment and saves metadata
    private func stopCurrentSegment() async {
        print("⏹️ stopping system segment #\(segmentNumber)")
        
        // record end time
        let segmentEndTime = Date().timeIntervalSince1970 - sessionReferenceTime
        
        // stop stream (may fail if device is disconnected)
        if let activeStream = stream {
            do {
                try await activeStream.stopCapture()
                print("✅ stream stopped cleanly")
            } catch {
                // this is expected during device disconnection
                print("⚠️ stream stop error (expected during transition): \(error)")
            }
        }
        
        // close file
        audioFile = nil
        
        // cleanup - nil out references immediately
        stream = nil
        streamOutput = nil
        filter = nil
        
        // save segment metadata
        let metadata = AudioSegmentMetadata(
            segmentID: UUID().uuidString,
            filePath: segmentFilePath,
            deviceName: deviceName,
            deviceID: deviceID,
            sampleRate: 48000,
            channels: 2,
            startSessionTime: segmentStartTime,
            endSessionTime: segmentEndTime,
            frameCount: framesCaptured,
            quality: .high,  // system audio is always high quality
            error: nil
        )
        
        segmentQueue.sync {
            segmentMetadata.append(metadata)
        }
        
        print("📊 segment #\(segmentNumber): \(String(format: "%.1f", segmentEndTime - segmentStartTime))s, \(framesCaptured) frames")
    }
    
    /// writes system audio buffer to file (called from stream output)
    nonisolated func writeSystemAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        // convert to pcm buffer
        guard let pcmBuffer = convertToAudioBuffer(sampleBuffer) else {
            print("⚠️ failed to convert system audio buffer")
            return
        }
        
        // write on dedicated queue
        fileWriteQueue.async { [weak self] in
            Task { @MainActor in
                guard let audioFile = self?.audioFile else { return }
                
                do {
                    try audioFile.write(from: pcmBuffer)
                    self?.framesCaptured += Int(pcmBuffer.frameLength)
                } catch {
                    print("❌ system audio write error: \(error)")
                }
            }
        }
    }
    
    /// converts CMSampleBuffer to AVAudioPCMBuffer
    nonisolated private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return nil
        }
        
        // create format matching the buffer
        let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: asbd.mSampleRate,
                                         channels: asbd.mChannelsPerFrame,
                                         interleaved: isInterleaved) else {
            return nil
        }
        
        // get sample data
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        
        // create pcm buffer
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                               frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        // copy data
        var dataPointer: UnsafeMutablePointer<Int8>?
        var dataLength = 0
        
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                   totalLengthOut: &dataLength,
                                   dataPointerOut: &dataPointer)
        
        if let dataPointer = dataPointer,
           let channelData = pcmBuffer.floatChannelData {
            let channelCount = Int(asbd.mChannelsPerFrame)
            
            dataPointer.withMemoryRebound(to: Float.self,
                                         capacity: dataLength / MemoryLayout<Float>.size) { floatPointer in
                if isInterleaved {
                    // interleaved: samples alternate between channels
                    for channel in 0..<channelCount {
                        for frame in 0..<Int(frameCount) {
                            let sourceIndex = frame * channelCount + channel
                            channelData[channel][frame] = floatPointer[sourceIndex]
                        }
                    }
                } else {
                    // non-interleaved: channels are consecutive blocks
                    for channel in 0..<channelCount {
                        let channelOffset = channel * Int(frameCount)
                        for frame in 0..<Int(frameCount) {
                            channelData[channel][frame] = floatPointer[channelOffset + frame]
                        }
                    }
                }
            }
        }
        
        return pcmBuffer
    }
    
    /// creates segment file path
    private func createSegmentFilePath(sessionTimestamp: Int, segmentNumber: Int) -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
        
        let fileName = SegmentFileNaming.segmentFileName(
            type: .system,
            sessionTimestamp: TimeInterval(sessionTimestamp),
            segmentNumber: segmentNumber
        )
        
        return recordingsFolder.appendingPathComponent(fileName).path
    }
    
    /// saves session metadata to disk
    private func saveSessionMetadata() {
        let metadata = RecordingSessionMetadata(
            sessionID: sessionID,
            sessionStartTime: sessionStartTime,
            sessionEndTime: Date(),
            micSegments: [],  // will be filled by MicRecorder
            systemSegments: segmentMetadata
        )
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
        let metadataURL = recordingsFolder.appendingPathComponent("session_\(Int(sessionReferenceTime))_system_metadata.json")
        
        do {
            try metadata.save(to: metadataURL)
            print("💾 system session metadata saved")
        } catch {
            print("❌ failed to save system metadata: \(error)")
        }
    }
}

// MARK: - stream output handler

/// handles audio output from screencapturekit stream
private class SystemStreamOutput: NSObject, SCStreamOutput {
    weak var recorder: SystemAudioRecorder?
    private var bufferCount = 0
    private var hasLoggedFormat = false
    private var isWarmedUp = false
    private var warmupBuffers = 25  // ~0.5s warmup
    
    init(recorder: SystemAudioRecorder) {
        self.recorder = recorder
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        bufferCount += 1
        
        // warmup period - discard initial buffers
        if !isWarmedUp {
            if bufferCount >= warmupBuffers {
                isWarmedUp = true
                print("🔥 system audio warmup complete")
            } else {
                if bufferCount % 10 == 0 {
                    print("🔄 system warmup: \(bufferCount)/\(warmupBuffers)")
                }
                return  // discard
            }
        }
        
        // log format once
        if !hasLoggedFormat && bufferCount == warmupBuffers + 10 {
            hasLoggedFormat = true
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let desc = audioDesc?.pointee {
                    print("📊 system audio streaming: \(desc.mSampleRate)hz, \(desc.mChannelsPerFrame)ch")
                }
            }
        }
        
        // write buffer to file
        recorder?.writeSystemAudioBuffer(sampleBuffer)
    }
}