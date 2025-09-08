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
    private var streamOutput: StreamOutput?
    private var filter: SCContentFilter?
    
    // MARK: - audio processing
    weak var audioManager: AudioManager?  // delegate audio to main manager
    private var warmupBuffersToDiscard = 25  // ~500ms at 48khz
    private var discardedBuffers = 0
    private var isWarmedUp = false
    
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
            
            // exclude our own app's audio
            config.excludesCurrentProcessAudio = true
            
            print("📊 stream config: \(targetSampleRate)hz, \(targetChannels)ch, display-wide capture")
            
            // create stream
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            // create output handler
            streamOutput = StreamOutput(manager: self)
            
            // add audio output handler with dedicated queue
            let audioQueue = DispatchQueue(label: "com.ai-and-i.audio.capture", qos: .userInteractive)
            try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: audioQueue)
            
            // reset warmup state
            discardedBuffers = 0
            isWarmedUp = false
            
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
            isWarmedUp = false
            
            print("✅ system audio capture stopped")
            
        } catch {
            print("❌ stop capture error: \(error)")
        }
    }
    
    // MARK: - audio processing
    
    /// processes captured audio buffer from screencapturekit (direct, non-MainActor)
    func processCapturedAudioDirect(_ sampleBuffer: CMSampleBuffer) {
        // handle warmup period
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
        
        // log format once
        if discardedBuffers == warmupBuffersToDiscard {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let desc = audioDesc?.pointee {
                    print("📊 system audio format: \(desc.mSampleRate)hz, \(desc.mChannelsPerFrame)ch")
                }
            }
        }
        
        // convert cmsamplebuffer to avaudiopcmbuffer
        guard let pcmBuffer = convertToAudioBuffer(sampleBuffer) else {
            print("❌ failed to convert system audio buffer")
            return
        }
        
        // send to audio manager for mixing/recording on main thread
        Task { @MainActor in
            audioManager?.processSystemAudio(pcmBuffer)
        }
    }
    
    /// processes captured audio buffer from screencapturekit (MainActor version - deprecated)
    @MainActor
    fileprivate func processCapturedAudio(_ sampleBuffer: CMSampleBuffer) {
        // handle warmup period
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
        
        // log format once
        if discardedBuffers == warmupBuffersToDiscard {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let desc = audioDesc?.pointee {
                    print("📊 system audio format: \(desc.mSampleRate)hz, \(desc.mChannelsPerFrame)ch")
                }
            }
        }
        
        // convert cmsamplebuffer to avaudiopcmbuffer
        guard let pcmBuffer = convertToAudioBuffer(sampleBuffer) else {
            print("❌ failed to convert system audio buffer")
            return
        }
        
        // send to audio manager for mixing/recording
        audioManager?.processSystemAudio(pcmBuffer)
    }
    
    /// converts cmsamplebuffer to avaudiopcmbuffer for avaudioengine
    private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
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
            let bytesPerFrame = Int(asbd.mBytesPerFrame)
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
private class StreamOutput: NSObject, SCStreamOutput {
    weak var manager: ScreenCaptureManager?
    
    init(manager: ScreenCaptureManager) {
        self.manager = manager
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        // retain the buffer and process synchronously to avoid dropping
        let retainedBuffer = sampleBuffer
        DispatchQueue.main.async { [weak manager] in
            manager?.processCapturedAudioDirect(retainedBuffer)
        }
    }
}

// extension removed - processSystemAudio already exists in AudioManager.swift