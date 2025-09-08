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
            
            // try to disable video capture completely
            // these "dropping frame" errors are about video frames, not audio
            config.width = 1920  // standard size to avoid errors
            config.height = 1080  
            config.minimumFrameInterval = CMTime(value: 600, timescale: 1)  // extremely low fps (0.0016 fps)
            config.scalesToFit = false
            
            print("📊 stream config: \(targetSampleRate)hz, \(targetChannels)ch, display-wide capture")
            
            // create stream
            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            
            // create output handler
            streamOutput = StreamOutput(manager: self)
            
            // add ONLY audio output handler - no video handler
            // this should prevent video frame dropping errors
            let audioQueue = DispatchQueue(label: "com.ai-and-i.audio.capture", qos: .userInteractive)
            try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: audioQueue)
            // explicitly NOT adding a video output handler
            
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
    private var bufferCount = 0
    private var hasLoggedFormat = false
    private var maxAudioLevel: Float = 0.0
    
    init(manager: ScreenCaptureManager) {
        self.manager = manager
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        bufferCount += 1
        
        // log format only once at the beginning
        if !hasLoggedFormat && bufferCount == 25 {  // after ~0.5 seconds
            hasLoggedFormat = true
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                if let desc = audioDesc?.pointee {
                    print("📊 system audio format: \(desc.mSampleRate)hz, \(desc.mChannelsPerFrame)ch")
                    print("✅ system audio is now streaming successfully")
                }
            }
        }
        
        // calculate audio level to prove we're getting real audio
        if bufferCount % 50 == 0 {  // check every ~1 second
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                var dataLength = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &dataLength,
                                          dataPointerOut: &dataPointer)
                
                if let dataPointer = dataPointer {
                    // calculate RMS (root mean square) for audio level
                    dataPointer.withMemoryRebound(to: Float.self, capacity: dataLength / MemoryLayout<Float>.size) { floatPointer in
                        let sampleCount = dataLength / MemoryLayout<Float>.size
                        var sum: Float = 0
                        for i in 0..<min(sampleCount, 1000) {  // sample first 1000 values
                            let sample = floatPointer[i]
                            sum += sample * sample
                        }
                        let rms = sqrt(sum / Float(min(sampleCount, 1000)))
                        let dbLevel = 20 * log10(max(rms, 0.00001))  // convert to dB
                        
                        // track max level
                        if rms > maxAudioLevel {
                            maxAudioLevel = rms
                        }
                        
                        // log audio levels
                        if bufferCount % 100 == 0 {  // every ~2 seconds
                            if rms > 0.001 {  // if there's actual audio
                                print("🎵 SYSTEM AUDIO DETECTED: level = \(String(format: "%.1f", dbLevel)) dB, RMS = \(String(format: "%.4f", rms))")
                                print("   ✅ Real audio content confirmed! Max level seen: \(String(format: "%.4f", maxAudioLevel))")
                            } else {
                                print("🔇 System audio is silent (level = \(String(format: "%.1f", dbLevel)) dB)")
                            }
                            print("📊 \(bufferCount) buffers received")
                        }
                    }
                }
            }
        }
    }
}

// extension removed - processSystemAudio already exists in AudioManager.swift