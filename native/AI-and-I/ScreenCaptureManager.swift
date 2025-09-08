import Foundation
import ScreenCaptureKit
import AVFoundation

/// manages screencapturekit for system audio capture from meeting apps
/// follows production best practices: app-level filtering, warmup discard, clean audio path
@MainActor
class ScreenCaptureManager: NSObject, ObservableObject {
    // MARK: - published state
    @Published var isCapturing = false
    @Published var errorMessage: String?
    
    // MARK: - capture components
    private var stream: SCStream?
    private var streamOutput: StreamOutput?  // strong reference to prevent deallocation
    private var filter: SCContentFilter?
    
    // MARK: - audio processing
    weak var audioManager: AudioManager?  // delegate audio to main manager
    
    // MARK: - format configuration
    private let targetSampleRate = 48000  // int for SCStreamConfiguration
    private let targetChannels = 2  // stereo for system audio
    
    override init() {
        super.init()
        print("🖥️ screencapture manager initialized")
    }
    
    // MARK: - public methods
    
    /// starts capturing all system audio from the main display
    func startCaptureForDisplay() async {
        print("🎬 starting display audio capture")
        
        do {
            // this will trigger screen recording permission dialog if not granted
            // the system handles it automatically - no need for preflight checks
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                errorMessage = "no display found"
                print("❌ no display found")
                return
            }
            
            // create filter for entire display (excludes only our app to prevent feedback)
            let excludedApps = content.applications.filter { app in
                app.applicationName.lowercased().contains("ai&i") || 
                app.applicationName.lowercased().contains("ai-and-i")
            }
            let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
            self.filter = filter
            
            // configure stream for audio only
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.sampleRate = targetSampleRate
            config.channelCount = targetChannels
            
            // exclude our own app's audio to prevent feedback
            config.excludesCurrentProcessAudio = true
            
            // set minimal but valid video config (required even for audio-only)
            // SCStream requires valid video dimensions even when we only want audio
            config.width = 16  // minimum valid width
            config.height = 16  // minimum valid height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 fps (minimum to reduce overhead)
            
            print("📊 stream config: \(targetSampleRate)hz, \(targetChannels)ch, display-wide capture")
            
            // create stream
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            // create output handler
            streamOutput = StreamOutput(manager: self)
            
            // add audio output handler with dedicated queue
            let audioQueue = DispatchQueue(label: "com.ai-and-i.audio.capture", qos: .userInteractive)
            try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: audioQueue)
            
            // start capture
            try await stream?.startCapture()
            
            isCapturing = true
            print("✅ display audio capture started - recording all system audio")
            
        } catch {
            errorMessage = "capture start failed: \(error)"
            print("❌ capture start failed: \(error)")
        }
    }
    
    
    /// stops capturing and cleans up
    func stopCapture() async {
        guard isCapturing else { return }
        
        print("⏹️ stopping system audio capture")
        
        do {
            try await stream?.stopCapture()
            stream = nil
            streamOutput = nil
            filter = nil
            
            isCapturing = false
            
            print("✅ system audio capture stopped")
            
        } catch {
            print("❌ stop capture error: \(error)")
        }
    }
    
    // MARK: - audio processing
    
    /// processes audio buffer from the stream output handler (nonisolated for performance)
    nonisolated func processAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        // for now, just count the buffers to verify we're receiving them
        // the conversion and processing will be optimized later
        // this avoids the "dropping frame" errors by processing quickly
        
        // only convert and send every 10th buffer to reduce load
        // this is temporary until we implement proper buffering
        Task { @MainActor in
            audioManager?.noteSystemAudioReceived()
        }
    }
    
    
    /// converts cmsamplebuffer to avaudiopcmbuffer for avaudioengine
    nonisolated private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        // get format description
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return nil
        }
        
        // create avaudio format
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: asbd.mSampleRate,
                                         channels: asbd.mChannelsPerFrame,
                                         interleaved: false) else {
            return nil
        }
        
        // get sample data
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        
        // create pcm buffer
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        // copy data to pcm buffer
        var dataPointer: UnsafeMutablePointer<Int8>?
        var dataLength = 0
        
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                    totalLengthOut: &dataLength,
                                    dataPointerOut: &dataPointer)
        
        if let dataPointer = dataPointer,
           let channelData = pcmBuffer.floatChannelData {
            // convert data to float32
            let channelCount = Int(asbd.mChannelsPerFrame)
            
            dataPointer.withMemoryRebound(to: Float.self, capacity: dataLength / MemoryLayout<Float>.size) { floatPointer in
                for channel in 0..<channelCount {
                    for frame in 0..<Int(frameCount) {
                        let sourceIndex = frame * channelCount + channel
                        channelData[channel][frame] = floatPointer[sourceIndex]
                    }
                }
            }
        }
        
        return pcmBuffer
    }
}

// MARK: - stream output handler

/// handles audio output from screencapturekit stream
/// this class is NOT MainActor isolated, allowing it to process on the audio queue
private class StreamOutput: NSObject, SCStreamOutput {
    weak var manager: ScreenCaptureManager?
    private var warmupBuffersToDiscard = 25
    private var discardedBuffers = 0
    private var isWarmedUp = false
    
    init(manager: ScreenCaptureManager) {
        self.manager = manager
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        // handle warmup period directly here to avoid actor isolation issues
        if !isWarmedUp {
            discardedBuffers += 1
            if discardedBuffers < warmupBuffersToDiscard {
                if discardedBuffers % 10 == 0 {
                    print("🔄 system audio warming up... discarded \(discardedBuffers)")
                }
                return
            } else {
                isWarmedUp = true
                print("✅ system audio warmup complete")
            }
        }
        
        // log format once after warmup
        if discardedBuffers == warmupBuffersToDiscard {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let desc = audioDesc?.pointee {
                    print("📊 system audio format: \(desc.mSampleRate)hz, \(desc.mChannelsPerFrame)ch")
                    print("📊 system audio is now streaming successfully")
                }
            }
        }
        
        // process the audio buffer
        manager?.processAudioBuffer(sampleBuffer)
    }
}

// extension removed - processSystemAudio already exists in AudioManager.swift