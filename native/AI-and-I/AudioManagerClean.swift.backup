import Foundation
import AVFoundation
import SwiftUI

/// clean mic-only audio manager - no effects, no monitoring, just pure recording
/// following voice memos approach for consistent quality
@MainActor
class AudioManagerClean: NSObject, ObservableObject {
    // MARK: - Published State
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var currentInputDevice = "Unknown"
    @Published var currentOutputDevice = "Unknown"
    @Published var isUsingAirPodsMic = false
    
    // MARK: - Audio Components
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var recordingStartTime: Date?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    
    // MARK: - Performance Monitoring
    weak var performanceMonitor: PerformanceMonitor?
    
    // MARK: - Target Format (Voice Memos style)
    private let targetSampleRate: Double = 48000
    private let targetChannels: UInt32 = 1  // MONO for clarity
    
    override init() {
        super.init()
        print("🎙️ clean audio manager initialized")
        setupDeviceMonitoring()
    }
    
    deinit {
        audioEngine?.stop()
        recordingTimer?.invalidate()
    }
    
    // MARK: - Device Monitoring
    private func setupDeviceMonitoring() {
        // monitor for device changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceChange),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceChange),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }
    
    @objc private func handleDeviceChange(notification: Notification) {
        updateDeviceInfo()
        if isRecording {
            print("⚠️ Device changed during recording")
        }
    }
    
    // MARK: - Public Methods
    func setPerformanceMonitor(_ monitor: PerformanceMonitor) {
        self.performanceMonitor = monitor
    }
    
    func startRecording() {
        Task {
            await requestPermissionsAndRecord()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        performanceMonitor?.measureOperation("recording_stop") {
            performStopRecording()
        }
    }
    
    // MARK: - Private Recording Methods
    private func requestPermissionsAndRecord() async {
        let permission = AVAudioApplication.shared.recordPermission
        
        switch permission {
        case .granted:
            await startCleanRecording()
        case .denied:
            errorMessage = "microphone access required"
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            if granted {
                await startCleanRecording()
            } else {
                errorMessage = "microphone access denied"
            }
        @unknown default:
            errorMessage = "unable to check permissions"
        }
    }
    
    private func startCleanRecording() async {
        print("\n🎤 STARTING CLEAN MIC-ONLY RECORDING")
        
        do {
            // create fresh engine
            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else {
                throw AudioError.engineCreationFailed
            }
            
            let inputNode = engine.inputNode
            
            // log current devices
            updateDeviceInfo()
            
            // get native input format
            let inputFormat = inputNode.inputFormat(forBus: 0)
            print("📊 INPUT FORMAT: sr=\(inputFormat.sampleRate)Hz ch=\(inputFormat.channelCount) \(inputFormat.commonFormat)")
            
            // check for telephony mode
            if inputFormat.sampleRate <= 16000 {
                print("⚠️ WARNING: Low quality telephony mode detected (HFP/HSP)")
                print("💡 TIP: For better quality, disconnect AirPods or use built-in mic")
                
                // warn user if using AirPods mic
                if isUsingAirPodsMic {
                    await MainActor.run {
                        self.errorMessage = "AirPods in call mode (reduced quality). Use built-in mic for better audio."
                    }
                }
            }
            
            // create target format (mono 48kHz like Voice Memos)
            guard let targetFormat = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, 
                                                   channels: targetChannels) else {
                throw AudioError.formatCreationFailed
            }
            
            print("🎯 TARGET FORMAT: 48kHz mono (Voice Memos style)")
            
            // create converter for format conversion
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw AudioError.converterCreationFailed
            }
            self.converter = converter
            
            // create output file
            let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                         in: .userDomainMask).first!
            recordingURL = documentsPath.appendingPathComponent("recording_clean_\(Date().timeIntervalSince1970).wav")
            
            // create audio file with target format
            audioFile = try AVAudioFile(forWriting: recordingURL!,
                                       settings: targetFormat.settings)
            
            print("📁 Recording to: \(recordingURL!.lastPathComponent)")
            
            // CRITICAL: Do NOT connect to any output - no monitoring!
            // We only tap the input, no mixer, no output
            
            // install tap directly on input node
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer, inputFormat: inputFormat, targetFormat: targetFormat)
            }
            
            // start engine - no connections to output!
            engine.prepare()
            try engine.start()
            
            await MainActor.run {
                self.isRecording = true
                self.recordingStartTime = Date()
                self.startRecordingTimer()
            }
            
            print("✅ CLEAN RECORDING STARTED - No monitoring, pure capture")
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to start: \(error.localizedDescription)"
            }
            print("❌ Start failed: \(error)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, 
                                   inputFormat: AVAudioFormat,
                                   targetFormat: AVAudioFormat) {
        guard let converter = converter else { return }
        
        // calculate output frame capacity
        let outputFrameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (targetFormat.sampleRate / inputFormat.sampleRate)
        )
        
        // create mono buffer
        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, 
                                                frameCapacity: outputFrameCapacity) else {
            return
        }
        
        // convert to mono 48kHz
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        converter.convert(to: monoBuffer, error: &error, withInputFrom: inputBlock)
        
        if let error = error {
            print("❌ Conversion error: \(error)")
            return
        }
        
        // write to file
        do {
            try audioFile?.write(from: monoBuffer)
            
            // occasional RMS logging
            if Int.random(in: 0..<100) < 5 {
                let rms = computeRMS(monoBuffer)
                print("📊 RMS: \(String(format: "%.1f", rms)) dBFS")
            }
        } catch {
            print("❌ Write error: \(error)")
        }
    }
    
    private func performStopRecording() {
        // stop engine
        audioEngine?.stop()
        
        // remove tap
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        // close file
        audioFile = nil
        
        // stop timer
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // update state
        isRecording = false
        
        if let url = recordingURL {
            // verify file
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? Int64 {
                let sizeMB = Double(fileSize) / 1024 / 1024
                print("✅ Recording saved: \(String(format: "%.2f", sizeMB)) MB")
            }
        }
        
        recordingStartTime = nil
        recordingDuration = 0
        
        print("⏹️ CLEAN RECORDING STOPPED")
    }
    
    // MARK: - Helper Methods
    private func updateDeviceInfo() {
        currentInputDevice = getInputDeviceName()
        currentOutputDevice = getOutputDeviceName()
        
        // check if using AirPods mic
        isUsingAirPodsMic = currentInputDevice.lowercased().contains("airpod")
        
        print("🎤 Input: \(currentInputDevice)")
        print("🔊 Output: \(currentOutputDevice)")
        
        if isUsingAirPodsMic {
            print("⚠️ Using AirPods mic - expect reduced quality")
        }
    }
    
    private func getInputDeviceName() -> String {
        // simplified for now
        return "Default Input"
    }
    
    private func getOutputDeviceName() -> String {
        // simplified for now
        return "Default Output"
    }
    
    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return -120 }
        
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let mean = sum / Float(frameLength)
        return 10 * log10(mean + 1e-12)
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let startTime = self?.recordingStartTime {
                    self?.recordingDuration = Date().timeIntervalSince(startTime)
                }
            }
        }
    }
}

// MARK: - Error Types
enum AudioError: LocalizedError {
    case engineCreationFailed
    case formatCreationFailed
    case converterCreationFailed
    case engineNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .converterCreationFailed:
            return "Failed to create audio converter"
        case .engineNotConfigured:
            return "Audio engine not configured"
        }
    }
}