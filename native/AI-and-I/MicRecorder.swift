//
//  MicRecorder.swift
//  AI-and-I
//
//  handles microphone recording with automatic segmentation on device changes
//  maintains independent pipeline from system audio for maximum reliability
//

import Foundation
@preconcurrency import AVFoundation
import CoreAudio

struct RecordingSessionContext {
    let id: String
    let startDate: Date
    let timestamp: TimeInterval

    static func create() -> RecordingSessionContext {
        let now = Date()
        return RecordingSessionContext(
            id: UUID().uuidString,
            startDate: now,
            timestamp: now.timeIntervalSince1970
        )
    }

    var timestampInt: Int {
        Int(timestamp)
    }
}

extension AVAudioPCMBuffer: @unchecked Sendable {}

/// manages microphone recording with segment-based approach
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

    // MARK: - output preservation
    private var preferredOutputDeviceID: AudioDeviceID?
    private var preferredOutputDeviceName: String = "unknown"

    /// public accessor for the session timestamp (used for mixing)
    var currentSessionTimestamp: Int {
        Int(sessionReferenceTime)
    }
    private var segmentStartTime: TimeInterval = 0
    private var segmentNumber: Int = 0
    private var segmentFilePath: String = ""
    private var currentDeviceID: String = ""
    private var currentDeviceAudioID: AudioDeviceID = 0
    private var framesCaptured: Int = 0
    private var hasLoggedFormatMatch = false
    private var lastConversionLogTime = Date.distantPast
    private var currentSampleRate: Double = 48000
    private var latestDeviceName: String = "unknown"
    private var latestQuality: AudioSegmentMetadata.AudioQuality = .high
    private var warmEngine: AVAudioEngine?
    private var tapInstalled = false
    private let warmRetryLimit = 3
    private let warmRetryDelayNanoseconds: UInt64 = 300_000_000 // 300ms

    enum RecorderError: Error, LocalizedError {
        case warmPreparationFailed(String)

        var errorDescription: String? {
            switch self {
            case .warmPreparationFailed(let message):
                return message
            }
        }
    }

    // MARK: - helpers
    private func updateOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    private func setIsRecording(_ value: Bool) {
        updateOnMain { self.isRecording = value }
    }
    
    private func setCurrentDeviceName(_ value: String) {
        latestDeviceName = value
        updateOnMain { self.currentDeviceName = value }
    }
    
    private func setCurrentQuality(_ value: AudioSegmentMetadata.AudioQuality) {
        latestQuality = value
        updateOnMain { self.currentQuality = value }
    }
    
    private func setErrorMessage(_ value: String?) {
        updateOnMain { self.errorMessage = value }
    }

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
    func startSession(_ context: RecordingSessionContext) async throws {
        print("🎙️ starting mic recording session with context id: \(context.id)")
        capturePreferredOutputDeviceSnapshot()
        try await prepareWarmPipelineIfNeeded()

        // use the shared session context
        sessionID = context.id
        sessionStartTime = context.startDate
        sessionReferenceTime = context.timestamp
        segmentNumber = 0
        segmentMetadata.removeAll()
        deviceChangeCount = 0
        
        // set state first
        state = .recording
        setIsRecording(true)
        
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
        setIsRecording(false)
        preferredOutputDeviceID = nil
        preferredOutputDeviceName = "unknown"
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
            setErrorMessage("devices changing rapidly - holding current mic")
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
        
        prepareOutputRoutingForCurrentInputDevice()

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
            self?.startNewSegmentInternal()
        }
    }
    
    /// internal segment start (must be on controller queue)
    private func startNewSegmentInternal() {
        print("📝 starting new mic segment #\(segmentNumber + 1)")
        hasLoggedFormatMatch = false
        lastConversionLogTime = Date.distantPast

        do {
            try setupWarmEngineIfNeeded(startImmediately: false)
        } catch {
            setErrorMessage("failed to warm audio engine: \(error.localizedDescription)")
            return
        }

        guard let engine = warmEngine else {
            setErrorMessage("warm audio engine unavailable")
            return
        }

        audioEngine = engine
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!

        currentDeviceID = "pending"
        setCurrentDeviceName("initializing...")

        let negotiatedSampleRate = inputFormat.sampleRate
        print("📊 input format: \(negotiatedSampleRate)hz, \(inputFormat.channelCount)ch")
        print("📊 target format: \(recordingFormat.sampleRate)hz, \(recordingFormat.channelCount)ch")
        print("📊 formats equal: \(inputFormat == recordingFormat)")

        let assessedQuality = AudioSegmentMetadata.assessQuality(sampleRate: inputFormat.sampleRate)
        setCurrentQuality(assessedQuality)
        if negotiatedSampleRate < 44100 {
            print("⚠️ telephony sample rate detected: \(negotiatedSampleRate)hz (continuing with low-quality segment)")
        }

        currentSampleRate = negotiatedSampleRate
        agcEnabled = true
        currentGain = 2.5
        if assessedQuality == .low {
            setErrorMessage("mic in low quality mode - recording anyway")
        }

        segmentNumber += 1
        let sessionTimestamp = Int(sessionReferenceTime)
        segmentFilePath = createSegmentFilePath(sessionTimestamp: sessionTimestamp, segmentNumber: segmentNumber)

        var settings = recordingFormat.settings
        settings[AVFormatIDKey] = kAudioFormatLinearPCM
        settings[AVLinearPCMBitDepthKey] = 16
        settings[AVLinearPCMIsFloatKey] = false
        settings[AVLinearPCMIsBigEndianKey] = false

        do {
            audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: segmentFilePath), settings: settings)
            print("📁 created audio file: \(segmentFilePath)")
        } catch {
            setErrorMessage("failed to create audio file: \(error.localizedDescription)")
            return
        }

        isWarmedUp = false
        discardedFrames = 0
        framesCaptured = 0
        segmentStartTime = Date().timeIntervalSince1970 - sessionReferenceTime

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.writerQueue.async {
                self?.processAudioBuffer(buffer, inputFormat: inputFormat, targetFormat: recordingFormat)
            }
        }
        tapInstalled = true

        let deviceName: String
        if let deviceInfo = fetchDefaultInputDeviceInfo() {
            currentDeviceAudioID = deviceInfo.id
            currentDeviceID = String(deviceInfo.id)
            deviceName = deviceInfo.name
            setCurrentDeviceName(deviceName)
            enforceSampleRateIfNeeded(for: deviceInfo.id)
        } else {
            currentDeviceAudioID = 0
            currentDeviceID = "unknown"
            deviceName = "unknown"
            setCurrentDeviceName(deviceName)
        }

        if deviceName.lowercased().contains("airpod") {
            agcEnabled = false
            currentGain = 1.0
            print("🎧 airpods detected - agc disabled")
            print("🎧 airpods format: \(inputFormat.sampleRate)hz reported")
            print("🎧 airpods quality: \(assessedQuality.rawValue)")
        } else if deviceName.lowercased().contains("mac") || deviceName.lowercased().contains("built") {
            agcEnabled = true
            currentGain = 2.5
            print("🎚️ built-in mic - agc enabled with 2.5x gain")
        } else {
            agcEnabled = false
            currentGain = 1.0
        }

        print("✅ mic segment #\(segmentNumber) started - recording with \(deviceName)")
        let runningFormat = inputNode.outputFormat(forBus: 0)
        print("🎚️ engine running sample rate: \(runningFormat.sampleRate)hz")

        do {
            try setupWarmEngineIfNeeded(startImmediately: true)
        } catch {
            setErrorMessage("failed to start audio engine: \(error.localizedDescription)")
            return
        }

        if !deviceName.lowercased().contains("airpod") {
            print("🔊 monitoring continues on \(deviceName)")
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
        
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            print("✅ tap removed")
        }

        audioEngine?.stop()
        print("🛑 audio engine stopped for mic segment")

        // close file
        print("🔧 closing file...")
        audioFile = nil
        print("✅ file closed")
        
        // save segment metadata
        let metadata = AudioSegmentMetadata(
            segmentID: UUID().uuidString,
            filePath: segmentFilePath,
            deviceName: latestDeviceName,
            deviceID: currentDeviceID,
            sampleRate: 48000,
            channels: 1,
            startSessionTime: segmentStartTime,
            endSessionTime: segmentEndTime,
            frameCount: framesCaptured,
            quality: latestQuality,
            error: nil
        )
        
        segmentQueue.sync {
            segmentMetadata.append(metadata)
        }
        
        print("📊 segment #\(segmentNumber): \(String(format: "%.1f", segmentEndTime - segmentStartTime))s, \(framesCaptured) frames")
    }

    func prepareWarmPipeline() async throws {
        try await prepareWarmPipelineIfNeeded()
    }

    func shutdownWarmPipeline() {
        controllerQueue.async { [weak self] in
            self?.resetWarmEngine()
        }
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
        if agcEnabled && latestDeviceName.lowercased().contains("mac") {
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
            let now = Date()
            if now.timeIntervalSince(lastConversionLogTime) > 2 {
                print("   converted frames: \(convertedBuffer.frameLength) (telephony input \(inputFormat.sampleRate)hz → 48khz)")
                lastConversionLogTime = now
            }
        } else {
            bufferToWrite = processedBuffer
            if !hasLoggedFormatMatch {
                print("📊 no conversion needed - formats match")
                hasLoggedFormatMatch = true
            }
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
            setErrorMessage("failed to write audio: \(error.localizedDescription)")
        }
    }
    
    /// checks if we should switch to new device
    private func shouldSwitchToNewDevice() -> Bool {
        // get new device info
        let newDevice = AVAudioEngine().inputNode  // inputNode is not optional
        let newFormat = newDevice.inputFormat(forBus: 0)
        let newQuality = AudioSegmentMetadata.assessQuality(sampleRate: newFormat.sampleRate)
        
        return true
    }
    
    private func fetchDefaultInputDeviceInfo() -> (id: AudioDeviceID, name: String)? {
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

        guard result == noErr, deviceID != 0 else { return nil }

        let name = DeviceChangeMonitor.deviceName(for: deviceID) ?? "unknown"
        return (deviceID, name)
    }

    private func enforceSampleRateIfNeeded(for deviceID: AudioDeviceID) {
        var desiredRate = 48_000.0
        var size = UInt32(MemoryLayout<Double>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: 0
        )

        let setResult = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &desiredRate
        )

        if setResult != noErr {
            print("⚠️ unable to force sample rate on device \(deviceID): \(setResult)")
        }

        if let actual = querySampleRate(for: deviceID) {
            print("🎚️ input device sample rate now \(Int(actual))hz")
        }
    }

    private func querySampleRate(for deviceID: AudioDeviceID) -> Double? {
        var currentRate = Double(0)
        var size = UInt32(MemoryLayout<Double>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: 0
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &currentRate
        )

        return status == noErr ? currentRate : nil
    }

    private func prepareOutputRoutingForCurrentInputDevice() {
        refreshPreferredOutputSnapshotIfNeeded(force: true)
    }

    private func capturePreferredOutputDeviceSnapshot() {
        guard let outputID = DeviceChangeMonitor.currentOutputDeviceID() else {
            print("⚠️ unable to detect current output device for preservation")
            return
        }

        preferredOutputDeviceID = outputID
        preferredOutputDeviceName = DeviceChangeMonitor.deviceName(for: outputID) ?? "unknown"
        print("💾 preserved output device: \(preferredOutputDeviceName)")
    }

    private func refreshPreferredOutputSnapshotIfNeeded(force: Bool = false) {
        guard let currentOutputID = DeviceChangeMonitor.currentOutputDeviceID() else { return }
        let currentName = DeviceChangeMonitor.deviceName(for: currentOutputID) ?? "unknown"

        if force || preferredOutputDeviceID != currentOutputID {
            preferredOutputDeviceID = currentOutputID
            preferredOutputDeviceName = currentName
            print("💾 updated preferred output device: \(preferredOutputDeviceName)")
        }
    }

    private func prepareWarmPipelineIfNeeded() async throws {
#if canImport(AppKit)
        let permission = AVAudioApplication.shared.recordPermission
        guard permission == .granted else {
            let state: String
            switch permission {
            case .granted: state = "granted"
            case .denied: state = "denied"
            case .undetermined: state = "undetermined"
            @unknown default: state = "unknown"
            }
            print("🎧 skipping mic warm prep – record permission not granted yet (current: \(state))")
            return
        }
#endif

        guard fetchDefaultInputDeviceInfo() != nil else {
            print("🎧 skipping mic warm prep – no default input device available")
            return
        }

        try await setupWarmEngineAsync(startImmediately: false)
    }

    private func setupWarmEngineIfNeeded(startImmediately: Bool = true) throws {
        let execute = {
            if let engine = self.warmEngine {
                if startImmediately, !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
                return
            }

            let engine = AVAudioEngine()
            if startImmediately {
                engine.prepare()
                try engine.start()
            }
            self.warmEngine = engine
            print(startImmediately ? "🔥 mic warm pipeline ready" : "🔥 mic warm engine primed (will start on first segment)")
        }

        if Thread.isMainThread {
            try execute()
        } else {
            var capturedError: Error?
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                do {
                    try execute()
                } catch {
                    capturedError = error
                }
                semaphore.signal()
            }
            semaphore.wait()
            if let error = capturedError {
                throw error
            }
        }
    }

    private func setupWarmEngineAsync(startImmediately: Bool) async throws {
        var attempt = 0
        var lastError: Error?
        while attempt < warmRetryLimit {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    controllerQueue.async { [weak self] in
                        guard let self else {
                            continuation.resume(throwing: RecorderError.warmPreparationFailed("mic recorder unavailable"))
                            return
                        }
                        do {
                            try self.setupWarmEngineIfNeeded(startImmediately: startImmediately)
                            continuation.resume(returning: ())
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                return
            } catch {
                lastError = error
                attempt += 1
                print("⚠️ mic warm pipeline attempt \(attempt) failed: \(error.localizedDescription)")
                controllerQueue.async { [weak self] in
                    self?.resetWarmEngine()
                }
                if attempt < warmRetryLimit {
                    try? await Task.sleep(nanoseconds: warmRetryDelayNanoseconds)
                }
            }
        }
        throw RecorderError.warmPreparationFailed(lastError?.localizedDescription ?? "unknown warm pipeline error")
    }

    private func resetWarmEngine() {
        warmEngine?.stop()
        warmEngine = nil
        tapInstalled = false
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
