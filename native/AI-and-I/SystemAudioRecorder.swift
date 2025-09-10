//
//  SystemAudioRecorder.swift
//  AI-and-I
//
//  handles system audio recording with automatic segmentation
//  operates independently from mic recording for maximum reliability
//

import Foundation
import ScreenCaptureKit
import AVFoundation

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
    
    /// starts a new recording session
    func startSession() async {
        print("🔊 starting system audio recording session")
        
        // initialize session
        sessionID = UUID().uuidString
        sessionStartTime = Date()
        sessionReferenceTime = Date().timeIntervalSince1970
        segmentNumber = 0
        segmentMetadata.removeAll()
        
        // start first segment
        await startNewSegment()
        isRecording = true
    }
    
    /// ends the recording session and saves metadata
    func endSession() async {
        print("🛑 ending system audio recording session")
        
        guard isRecording else { return }
        
        // stop current segment
        await stopCurrentSegment()
        
        // save session metadata
        saveSessionMetadata()
        
        isRecording = false
    }
    
    /// handles display/system audio device changes
    func handleDeviceChange(reason: String) async {
        guard isRecording else { return }
        
        print("🔄 system audio change: \(reason)")
        
        // system audio changes are less frequent, no debouncing needed
        await stopCurrentSegment()
        await startNewSegment()
    }
    
    // MARK: - private implementation
    
    /// starts a new segment
    private func startNewSegment() async {
        print("📝 starting new system segment #\(segmentNumber + 1)")
        
        do {
            // get shareable content
            print("🔍 requesting shareable content...")
            let content = try await SCShareableContent.current
            print("✅ got shareable content")
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
            
            // set minimal video settings to avoid errors
            config.width = 1
            config.height = 1
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            
            print("📊 stream config: 48000hz, 2ch, display-wide capture")
            
            // create segment file
            segmentNumber += 1
            let sessionTimestamp = Int(sessionReferenceTime)
            segmentFilePath = createSegmentFilePath(sessionTimestamp: sessionTimestamp,
                                                   segmentNumber: segmentNumber)
            
            // create audio file (48khz stereo for system)
            let audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: segmentFilePath),
                                       settings: audioFormat.settings)
            
            // record segment start time
            segmentStartTime = Date().timeIntervalSince1970 - sessionReferenceTime
            framesCaptured = 0
            
            // create stream
            stream = SCStream(filter: filter!, configuration: config, delegate: nil)
            print("✅ stream created")
            
            // create output handler
            streamOutput = SystemStreamOutput(recorder: self)
            print("✅ output handler created")
            
            // add audio output handler
            let audioQueue = DispatchQueue(label: "system.audio.capture", qos: .userInteractive)
            
            guard let stream = stream else {
                print("❌ stream is nil after creation")
                errorMessage = "stream creation failed"
                return
            }
            
            try stream.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: audioQueue)
            print("✅ audio output handler added")
            
            // start capture
            try await stream.startCapture()
            print("✅ stream capture started")
            
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
        
        // stop stream
        do {
            try await stream?.stopCapture()
        } catch {
            print("⚠️ stream stop error: \(error)")
        }
        
        // close file
        audioFile = nil
        
        // cleanup
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