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

private extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        copy.frameLength = frameLength

        let srcBuffers = UnsafeMutableAudioBufferListPointer(mutating: audioBufferList)
        let dstBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)

        for index in 0..<srcBuffers.count {
            guard let srcData = srcBuffers[index].mData,
                  let dstData = dstBuffers[index].mData else { continue }
            let byteCount = Int(srcBuffers[index].mDataByteSize)
            memcpy(dstData, srcData, byteCount)
            dstBuffers[index].mDataByteSize = srcBuffers[index].mDataByteSize
        }

        return copy
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
    
    // MARK: - state machine
    private enum RecordingState {
        case idle
        case recording
        case switching
    }
    private var state: RecordingState = .idle
    private var pendingSwitchReason: String?
    private var switchWorkItem: DispatchWorkItem?
    private let settleDelayNanoseconds: UInt64 = 400_000_000 // 400ms settle between teardown/start
    private let readinessRetryLimit = 10
    private let readinessRetryDelayNanoseconds: UInt64 = 100_000_000 // 100ms between readiness polls
    
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
    private var recordingEnabled = false
    private let bufferCounterQueue = DispatchQueue(label: "mic.buffer.counter")
    private var pendingBufferCount = 0
    private var droppedBufferCount = 0
    private let maxPendingBuffers = 8

    // MARK: - stall detection
    private var stallMonitor: DispatchSourceTimer?
    private var lastStallFrameCount: Int = 0
    private var stallDetectionStart: Date?
    private let stallCheckInterval: TimeInterval = 1.0
    private let stallDetectionWindow: TimeInterval = 3.0
    private var stallRecoveryInProgress = false
    private var stallRecoveryAttempts = 0
    private let stallRecoveryAttemptLimit = 3

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
        stallRecoveryAttempts = 0
        stallRecoveryInProgress = false
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
        
        controllerQueue.async { [weak self] in
            guard let self else { return }
            self.resetWarmEngine()
            if !self.startNewSegmentInternal(reason: "initial-start") {
                self.setErrorMessage("failed to prepare audio pipelines")
            }
        }
    }
    
    /// ends the recording session and saves metadata
    func endSession() {
        print("🛑 ending mic recording session")

        guard isRecording else { return }

        // cancel any pending switches
        switchWorkItem?.cancel()
        pendingSwitchReason = nil

        // stop current segment
        controllerQueue.sync { [self] in
            stopCurrentSegmentInternal(reason: "session-end")
        }

        // save session metadata
        saveSessionMetadata()

        restorePreferredOutputDeviceIfNeeded()

        state = .idle
        setIsRecording(false)
        preferredOutputDeviceID = nil
        preferredOutputDeviceName = "unknown"
    }
    
    /// handles device change during recording (production-safe)
    func handleDeviceChange(reason: String) {
        guard isRecording else { return }

        print("🔄 mic device change: \(reason)")

        controllerQueue.async { [weak self] in
            self?.enqueueDeviceSwitchLocked(reason: reason)
        }
    }

    private func enqueueDeviceSwitchLocked(reason: String) {
        // rate limiting: allow at most 3 changes per window
        let now = Date()
        let windowStart = now.addingTimeInterval(-deviceChangeWindow)
        if lastDeviceChangeTime < windowStart {
            deviceChangeCount = 0
        }
        deviceChangeCount += 1
        lastDeviceChangeTime = now

        if deviceChangeCount > 3 {
            print("⚠️ device changes too frequent - holding current mic")
            setErrorMessage("devices changing rapidly - holding current mic")
            return
        }

        pendingSwitchReason = reason
        schedulePendingSwitchLocked()
    }

    private func schedulePendingSwitchLocked() {
        guard state != .switching else {
            // switch in progress; latest reason already stored
            return
        }

        switchWorkItem?.cancel()
        let reason = pendingSwitchReason ?? "device-change"

        let workItem = DispatchWorkItem { [weak self] in
            self?.performSwitchLocked(reason: reason)
        }
        switchWorkItem = workItem
        controllerQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func performSwitchLocked(reason: String) {
        guard isRecording else { return }

        if state == .switching {
            pendingSwitchReason = reason
            return
        }

        state = .switching
        pendingSwitchReason = nil
        switchWorkItem = nil

        print("🔄 performing device switch (reason: \(reason))")

        prepareOutputRoutingForCurrentInputDevice()

        stopCurrentSegmentInternal(reason: reason)

        if settleDelayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(settleDelayNanoseconds) / 1_000_000_000)
        }

        resetWarmEngine()

        guard startNewSegmentInternal(reason: reason) else {
            state = .recording
            return
        }

        state = .recording
        print("✅ device switch complete (reason: \(reason))")
    }

    private func waitForStableInputFormat(_ engine: AVAudioEngine) -> AVAudioFormat? {
        for attempt in 0..<readinessRetryLimit {
            let format = engine.inputNode.inputFormat(forBus: 0)
            if format.sampleRate > 0 && format.channelCount > 0 {
                if attempt > 0 {
                    print("ℹ️ input format stabilized after \(attempt + 1) checks")
                }
                return format
            }
            Thread.sleep(forTimeInterval: Double(readinessRetryDelayNanoseconds) / 1_000_000_000)
        }
        print("⚠️ input format did not stabilize after \(readinessRetryLimit) attempts")
        return nil
    }

    // MARK: - private implementation

    /// internal segment start (must be on controller queue)
    @discardableResult
    private func startNewSegmentInternal(reason: String, allowFallback: Bool = true) -> Bool {
        print("📝 starting new mic segment #\(segmentNumber + 1)")
        hasLoggedFormatMatch = false
        lastConversionLogTime = Date.distantPast

        do {
            try setupWarmEngineIfNeeded(startImmediately: false)
        } catch {
            setErrorMessage("failed to warm audio engine: \(error.localizedDescription)")
            return false
        }

        guard let engine = warmEngine else {
            setErrorMessage("warm audio engine unavailable")
            return false
        }

        audioEngine = engine

        if settleDelayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(settleDelayNanoseconds) / 1_000_000_000)
        }

        guard let inputFormat = waitForStableInputFormat(engine) else {
            setErrorMessage("audio device not ready - holding current mic")
            return false
        }

        let inputNode = engine.inputNode
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
            return false
        }

        isWarmedUp = false
        discardedFrames = 0
        framesCaptured = 0
        segmentStartTime = Date().timeIntervalSince1970 - sessionReferenceTime

        bufferCounterQueue.sync {
            self.pendingBufferCount = 0
            self.droppedBufferCount = 0
        }

        recordingEnabled = false

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.enqueueAudioBuffer(buffer, inputFormat: inputFormat, targetFormat: recordingFormat)
        }
        tapInstalled = true

        startStallMonitor()

        let deviceName: String
        if let deviceInfo = fetchDefaultInputDeviceInfo() {
            currentDeviceAudioID = deviceInfo.id
            currentDeviceID = String(deviceInfo.id)
            deviceName = deviceInfo.name
            setCurrentDeviceName(deviceName)
            if allowFallback,
               DeviceChangeMonitor.isAirPods(deviceID: deviceInfo.id),
               negotiatedSampleRate < 44_100 {
                print("⚠️ airpods reported telephony sample rate (\(negotiatedSampleRate)hz) – falling back to built-in microphone")
                setErrorMessage("airpods mic in call mode – using mac microphone")
                if let fallbackID = DeviceChangeMonitor.builtInInputDeviceID(),
                   DeviceChangeMonitor.setDefaultInputDevice(fallbackID) {
                    Thread.sleep(forTimeInterval: Double(settleDelayNanoseconds) / 1_000_000_000)
                    return startNewSegmentInternal(reason: reason + "-fallback", allowFallback: false)
                } else {
                    print("⚠️ failed to switch input back to built-in microphone; continuing with current device")
                }
            }
            if DeviceChangeMonitor.isAirPods(deviceID: deviceInfo.id) {
                print("🎧 airpods detected – skipping sample rate enforcement to avoid telephony conflicts")
            } else if negotiatedSampleRate < 44_100 {
                print("⚠️ low sample rate (\(negotiatedSampleRate)hz) – leaving device as is to prevent Core Audio errors")
            } else {
                enforceSampleRateIfNeeded(for: deviceInfo.id)
            }
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
            return false
        }

        recordingEnabled = true

        if !deviceName.lowercased().contains("airpod") {
            print("🔊 monitoring continues on \(deviceName)")
        }

        stallRecoveryAttempts = 0

        return true
    }
    
    /// internal segment stop (must be on controller queue)
    private func stopCurrentSegmentInternal(reason: String = "manual") {
        print("⏹️ stopping mic segment #\(segmentNumber) (reason: \(reason))")

        // record end time
        let segmentEndTime = Date().timeIntervalSince1970 - sessionReferenceTime

        recordingEnabled = false

        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            print("✅ tap removed")
        }

        writerQueue.sync { }

        let dropped = bufferCounterQueue.sync { () -> Int in
            let dropped = self.droppedBufferCount
            self.droppedBufferCount = 0
            self.pendingBufferCount = 0
            return dropped
        }

        audioEngine?.stop()
        print("🛑 audio engine stopped for mic segment")
        audioEngine = nil

        stopStallMonitor()

        // close file
        print("🔧 closing file...")
        audioFile = nil
        print("✅ file closed")
        
        if framesCaptured == 0 {
            try? FileManager.default.removeItem(atPath: segmentFilePath)
            print("⚠️ discarding zero-length mic segment #\(segmentNumber)")
        } else {
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

        if dropped > 0 {
            print("⚠️ dropped \(dropped) audio buffer(s) due to backpressure")
        }

        if settleDelayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(settleDelayNanoseconds) / 1_000_000_000)
        }
    }

    private func startStallMonitor() {
        stallMonitor?.cancel()
        stallMonitor = nil
        stallDetectionStart = nil
        lastStallFrameCount = 0

        let timer = DispatchSource.makeTimerSource(queue: controllerQueue)
        timer.schedule(deadline: .now() + stallCheckInterval, repeating: stallCheckInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.state == .recording else { return }

            let currentFrames = self.writerQueue.sync { self.framesCaptured }
            if currentFrames == self.lastStallFrameCount {
                if self.stallDetectionStart == nil {
                    self.stallDetectionStart = Date()
                } else if let start = self.stallDetectionStart,
                          Date().timeIntervalSince(start) >= self.stallDetectionWindow {
                    let idleDuration = Date().timeIntervalSince(start)
                    print("⚠️ mic writer stalled – no frames written for \(String(format: "%.1f", idleDuration))s")
                    self.handleStallDetected(idleDuration: idleDuration)
                }
            } else {
                self.stallDetectionStart = nil
            }

            self.lastStallFrameCount = currentFrames
        }
        timer.resume()
        stallMonitor = timer
    }

    private func stopStallMonitor() {
        stallMonitor?.cancel()
        stallMonitor = nil
        stallDetectionStart = nil
        lastStallFrameCount = 0
    }

    private func handleStallDetected(idleDuration: TimeInterval) {
        guard !stallRecoveryInProgress else { return }

        if stallRecoveryAttempts >= stallRecoveryAttemptLimit {
            print("❌ mic stall persists after \(stallRecoveryAttempts) recovery attempts – please stop and restart recording")
            setErrorMessage("microphone stalled – stop and restart")
            return
        }

        stallRecoveryInProgress = true
        stallDetectionStart = Date()

        controllerQueue.async { [weak self] in
            self?.recoverFromStall(idleDuration: idleDuration)
        }
    }

    private func recoverFromStall(idleDuration: TimeInterval) {
        defer { stallRecoveryInProgress = false }

        guard state == .recording else { return }

        stallRecoveryAttempts += 1
        let attempt = stallRecoveryAttempts
        print("🛠️ mic stall recovery attempt #\(attempt) (idle \(String(format: "%.1f", idleDuration))s)")

        state = .switching
        pendingSwitchReason = nil

        let reason = "stall-recovery"

        stopCurrentSegmentInternal(reason: reason)

        if settleDelayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(settleDelayNanoseconds) / 1_000_000_000)
        }

        resetWarmEngine()

        guard startNewSegmentInternal(reason: reason) else {
            state = .recording
            return
        }

        state = .recording
        stallDetectionStart = nil
        lastStallFrameCount = 0
    }

    func prepareWarmPipeline() async throws {
        try await prepareWarmPipelineIfNeeded()
    }

    func shutdownWarmPipeline() {
        controllerQueue.async { [weak self] in
            self?.resetWarmEngine()
        }
    }
    
    private func enqueueAudioBuffer(_ buffer: AVAudioPCMBuffer,
                                     inputFormat: AVAudioFormat,
                                     targetFormat: AVAudioFormat) {
        var shouldDrop = false
        bufferCounterQueue.sync {
            if self.pendingBufferCount >= self.maxPendingBuffers {
                self.droppedBufferCount += 1
                shouldDrop = true
            } else {
                self.pendingBufferCount += 1
            }
        }

        guard !shouldDrop else { return }
        guard let copy = buffer.deepCopy() else {
            bufferCounterQueue.sync {
                self.pendingBufferCount = max(self.pendingBufferCount - 1, 0)
            }
            return
        }

        writerQueue.async { [weak self] in
            guard let self else { return }
            self.processAudioBuffer(copy, inputFormat: inputFormat, targetFormat: targetFormat)
            self.bufferCounterQueue.sync {
                self.pendingBufferCount = max(self.pendingBufferCount - 1, 0)
            }
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
                recordingEnabled = true
            }
            return  // discard this buffer
        }

        guard recordingEnabled else { return }
        
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
        if let current = querySampleRate(for: deviceID), abs(current - desiredRate) < 1 {
            print("🎚️ input device already at 48000hz – no enforcement needed")
            return
        }
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
        // no-op: we preserve the originally captured output device and restore it when the session ends
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

    private func restorePreferredOutputDeviceIfNeeded() {
        guard let preservedID = preferredOutputDeviceID else { return }
        guard let currentID = DeviceChangeMonitor.currentOutputDeviceID() else { return }
        guard currentID != preservedID else { return }

        print("🎧 restoring user output device after recording: \(preferredOutputDeviceName)")
        if !DeviceChangeMonitor.setDefaultOutputDevice(preservedID) {
            print("⚠️ failed to restore output device on session end")
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
