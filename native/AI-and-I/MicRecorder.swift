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

        let srcBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
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
    private let writerQueue = DispatchQueue(
        label: "mic.writer.queue",
        qos: .userInitiated,
        attributes: .concurrent
    )
    
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

    // MARK: - telephony guard
    private var lastTelephonyGuardPrompt: Date?
    private let telephonyGuardWindow: TimeInterval = 8.0
    
    // MARK: - quality control
    private var routeChangeTimestamps: [Date] = []
    private var significantRouteChangeTimes: [Date] = []
    private var routeUnstableUntil: Date?
    private var pinnedUntil: Date?
    private var pinnedActivations: Int = 0
    private var lastRouteChangeDeviceID: AudioDeviceID = 0
    private let routeCoalesceInterval: TimeInterval = 2.0
    private let routeChangeWindow: TimeInterval = 10.0
    private let pinnedSwitchThreshold = 3
    private let pinnedHoldDuration: TimeInterval = 15.0
    private var lowQualityAirPodsAttempts: Int = 0
    private let airPodsRecoveryRetryLimit: Int = 2
    private let airPodsRecoveryDelay: TimeInterval = 2.5
    private let minimumSegmentDuration: TimeInterval = 20.0
    private var readinessFailureCount = 0
    private let readinessFailureLimit = 5
    private var routeChangeRequestCount = 0
    private var executedSwitchCount = 0
    private var readinessAttemptLog: [Int] = []
    private var totalWarmupDiscardedFrames: AVAudioFrameCount = 0
    private var totalDroppedBuffers = 0
    private var stallSuppressionUntil: Date = .distantPast
    private var lastSuppressedStallLog = Date.distantPast
    private weak var performanceMonitor: PerformanceMonitor?
    private var switchLock: PipelineSwitchLock?
    private var lastKnownDeviceAudioID: AudioDeviceID = 0
    private var lastKnownSampleRate: Double = 0
    
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
        routeChangeTimestamps.removeAll()
        significantRouteChangeTimes.removeAll()
        pinnedUntil = nil
        routeUnstableUntil = nil
        pinnedActivations = 0
        lastRouteChangeDeviceID = 0
        lowQualityAirPodsAttempts = 0
        lastTelephonyGuardPrompt = nil
        readinessFailureCount = 0
        routeChangeRequestCount = 0
        executedSwitchCount = 0
        readinessAttemptLog.removeAll()
        totalWarmupDiscardedFrames = 0
        totalDroppedBuffers = 0
        stallSuppressionUntil = .distantPast
        lastSuppressedStallLog = .distantPast
        lastKnownDeviceAudioID = 0
        lastKnownSampleRate = 0
        
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
        logSessionDiagnostics()

        restorePreferredOutputDeviceIfNeeded()

        state = .idle
        setIsRecording(false)
        preferredOutputDeviceID = nil
        preferredOutputDeviceName = "unknown"
    }

    func attachPerformanceMonitor(_ monitor: PerformanceMonitor?) {
        controllerQueue.async { [weak self] in
            self?.performanceMonitor = monitor
        }
    }

    func attachSwitchLock(_ lock: PipelineSwitchLock?) {
        controllerQueue.async { [weak self] in
            self?.switchLock = lock
        }
    }
    
    /// handles device change during recording (production-safe)
    func handleDeviceChange(reason: String) {
        guard isRecording else { return }

        print("🔄 mic device change: \(reason)")

        controllerQueue.async { [weak self] in
            guard let self else { return }
            self.routeChangeRequestCount += 1
            self.enqueueDeviceSwitchLocked(reason: reason)
        }
    }

    private func enqueueDeviceSwitchLocked(reason: String) {
        let now = Date()

        if let pinnedUntil, now < pinnedUntil {
            let remaining = Int(pinnedUntil.timeIntervalSince(now))
            print("🛑 pinned mode active – ignoring device change (remaining: \(remaining)s)")
            setErrorMessage("holding mic for stability (\(max(remaining, 1))s)")
            return
        }

        // trim history to 10s window and append latest change
        routeChangeTimestamps = routeChangeTimestamps.filter { now.timeIntervalSince($0) <= routeChangeWindow }
        routeChangeTimestamps.append(now)

        let currentDefaultDeviceID = fetchDefaultInputDeviceInfo()?.id ?? 0
        significantRouteChangeTimes = significantRouteChangeTimes.filter { now.timeIntervalSince($0) <= routeChangeWindow }

        let isSignificantChange: Bool
        if currentDefaultDeviceID == 0 {
            isSignificantChange = lastRouteChangeDeviceID != 0
        } else if lastRouteChangeDeviceID == 0 {
            isSignificantChange = true
        } else {
            isSignificantChange = currentDefaultDeviceID != lastRouteChangeDeviceID
        }

        if isSignificantChange {
            significantRouteChangeTimes.append(now)
            lastRouteChangeDeviceID = currentDefaultDeviceID
        } else if currentDefaultDeviceID != 0 {
            lastRouteChangeDeviceID = currentDefaultDeviceID
        }

        // coalesce rapid changes within 2s window
        let recentRapidChanges = routeChangeTimestamps.filter { now.timeIntervalSince($0) <= routeCoalesceInterval }
        if recentRapidChanges.count >= 2 {
            routeUnstableUntil = now.addingTimeInterval(routeCoalesceInterval)
            print("⚠️ route unstable – waiting \(routeCoalesceInterval)s before switching")
            setErrorMessage("devices still switching – waiting to settle")
            extendStallSuppression(by: routeCoalesceInterval + stallDetectionWindow, reason: "route-unstable")
        }

        // pin when we cross threshold within 10 seconds
        if significantRouteChangeTimes.count >= pinnedSwitchThreshold {
            pinnedUntil = now.addingTimeInterval(pinnedHoldDuration)
            pinnedActivations += 1
            routeChangeTimestamps.removeAll()
            significantRouteChangeTimes.removeAll()
            print("🧷 pinned mic for stability for \(Int(pinnedHoldDuration))s")
            setErrorMessage("holding mic for stability (\(Int(pinnedHoldDuration))s)")
            extendStallSuppression(until: pinnedUntil ?? now, reason: "pinned")
            return
        }

        pendingSwitchReason = reason
        schedulePendingSwitchLocked(after: routeCoalesceInterval)
    }

    private func schedulePendingSwitchLocked(after delay: TimeInterval? = nil) {
        guard state != .switching else {
            return
        }

        switchWorkItem?.cancel()
        let reason = pendingSwitchReason ?? "device-change"
        let wait = delay ?? routeCoalesceInterval

        let workItem = DispatchWorkItem { [weak self] in
            self?.performSwitchLocked(reason: reason)
        }
        switchWorkItem = workItem
        controllerQueue.asyncAfter(deadline: .now() + wait, execute: workItem)
    }

    private func extendStallSuppression(by interval: TimeInterval, reason: String) {
        guard interval > 0 else { return }
        extendStallSuppression(until: Date().addingTimeInterval(interval), reason: reason)
    }

    private func extendStallSuppression(until newUntil: Date, reason: String) {
        guard newUntil > stallSuppressionUntil else { return }
        stallSuppressionUntil = newUntil
        let remaining = max(0, newUntil.timeIntervalSinceNow)
        print("⏳ stall suppression extended to +\(String(format: "%.2f", remaining))s (reason: \(reason))")
    }

    private func stallSuppressionState() -> (active: Bool, reason: String, remaining: TimeInterval) {
        let now = Date()
        if let pinnedUntil, now < pinnedUntil {
            return (true, "pinned", pinnedUntil.timeIntervalSince(now))
        }
        if let routeUnstableUntil, now < routeUnstableUntil {
            return (true, "route-unstable", routeUnstableUntil.timeIntervalSince(now))
        }
        if now < stallSuppressionUntil {
            return (true, "cooldown", stallSuppressionUntil.timeIntervalSince(now))
        }
        return (false, "", 0)
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

        let now = Date()

        if let routeUnstableUntil, now < routeUnstableUntil {
            let remaining = routeUnstableUntil.timeIntervalSince(now)
            print("⚠️ route still unstable for \(String(format: "%.2f", remaining))s – deferring switch")
            pendingSwitchReason = reason
            state = .recording
            extendStallSuppression(until: routeUnstableUntil, reason: "route-unstable")
            schedulePendingSwitchLocked(after: remaining)
            return
        }

        if let pinnedUntil, now < pinnedUntil {
            let remaining = pinnedUntil.timeIntervalSince(now)
            print("🧷 pinned mode active during switch request – rescheduling")
            pendingSwitchReason = reason
            state = .recording
            extendStallSuppression(until: pinnedUntil, reason: "pinned")
            schedulePendingSwitchLocked(after: remaining)
            return
        }

        print("🔄 performing device switch (reason: \(reason))")

        if shouldValidateDeviceChange(reason: reason) && !hasDeviceOrFormatChanged() {
            print("ℹ️ device and format unchanged – skipping mic switch")
            state = .recording
            extendStallSuppression(by: routeCoalesceInterval, reason: "unchanged-device")
            return
        }

        prepareOutputRoutingForCurrentInputDevice()

        if shouldDeferForMinimumSegment(reason: reason) {
            let remaining = remainingSegmentTime()
            print("⏱️ segment shorter than minimum – delaying switch by \(String(format: "%.2f", remaining))s")
            pendingSwitchReason = reason
            state = .recording
            extendStallSuppression(by: remaining + stallDetectionWindow, reason: "min-segment")
            schedulePendingSwitchLocked(after: remaining)
            return
        }

        routeUnstableUntil = nil
        extendStallSuppression(by: Double(settleDelayNanoseconds) / 1_000_000_000 + 1.0, reason: "switch-teardown")

        let releaseLock = switchLock?.acquire(for: "mic", reason: reason)
        defer { releaseLock?() }

        stopCurrentSegmentInternal(reason: reason)

        if settleDelayNanoseconds > 0 {
            Thread.sleep(forTimeInterval: Double(settleDelayNanoseconds) / 1_000_000_000)
        }

        resetWarmEngine()

        guard startNewSegmentInternal(reason: reason) else {
            readinessFailureCount += 1
            if readinessFailureCount >= readinessFailureLimit {
                print("❌ device never became ready after \(readinessFailureCount) attempts – holding current mic")
                setErrorMessage("device not ready – holding mic")
                readinessFailureCount = 0
                state = .recording
                return
            }
            pendingSwitchReason = reason
            state = .recording
            schedulePendingSwitchLocked(after: routeCoalesceInterval)
            return
        }

        readinessFailureCount = 0
        state = .recording
        executedSwitchCount += 1
        print("✅ device switch complete (reason: \(reason))")
    }

    private func shouldDeferForMinimumSegment(reason: String) -> Bool {
        guard !shouldBypassMinimumDuration(reason: reason) else { return false }
        return currentSegmentDuration() < minimumSegmentDuration
    }

    private func shouldBypassMinimumDuration(reason: String) -> Bool {
        let lowered = reason.lowercased()
        return lowered.contains("stall") ||
               lowered.contains("fail") ||
               lowered.contains("error") ||
               lowered.contains("session-end") ||
               lowered.contains("manual") ||
               lowered.contains("stop")
    }

    private func currentSegmentDuration() -> TimeInterval {
        let nowOffset = Date().timeIntervalSince1970 - sessionReferenceTime
        return max(0, nowOffset - segmentStartTime)
    }

    private func remainingSegmentTime() -> TimeInterval {
        let remaining = minimumSegmentDuration - currentSegmentDuration()
        return max(0.25, remaining)
    }

    private func shouldAllowTelephonyOverride() -> Bool {
        guard let prompt = lastTelephonyGuardPrompt else { return false }
        let elapsed = Date().timeIntervalSince(prompt)
        if elapsed <= telephonyGuardWindow {
            lastTelephonyGuardPrompt = nil
            return true
        }
        return false
    }

    private func shouldValidateDeviceChange(reason: String) -> Bool {
        shouldBypassMinimumDuration(reason: reason) == false
    }

    private func hasDeviceOrFormatChanged() -> Bool {
        guard lastKnownDeviceAudioID != 0 else { return true }
        guard let info = fetchDefaultInputDeviceInfo() else { return true }
        if info.id != lastKnownDeviceAudioID {
            return true
        }

        if lastKnownSampleRate == 0 {
            return true
        }

        if let currentRate = querySampleRate(for: info.id), abs(currentRate - lastKnownSampleRate) >= 1 {
            return true
        }

        return false
    }

    private func waitForStableInputFormat(_ engine: AVAudioEngine) -> (format: AVAudioFormat?, attempts: Int) {
        for attempt in 0..<readinessRetryLimit {
            let format = engine.inputNode.inputFormat(forBus: 0)
            if format.sampleRate > 0 && format.channelCount > 0 {
                if attempt > 0 {
                    print("ℹ️ input format stabilized after \(attempt + 1) checks")
                }
                return (format, attempt + 1)
            }
            Thread.sleep(forTimeInterval: Double(readinessRetryDelayNanoseconds) / 1_000_000_000)
        }
        print("⚠️ input format did not stabilize after \(readinessRetryLimit) attempts")
        return (nil, readinessRetryLimit)
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

        let readiness = waitForStableInputFormat(engine)
        readinessAttemptLog.append(readiness.attempts)
        guard let inputFormat = readiness.format else {
            setErrorMessage("audio device not ready - holding current mic")
            return false
        }

        let inputNode = engine.inputNode
        let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!

        currentDeviceID = "pending"
        setCurrentDeviceName("initializing...")

        let negotiatedSampleRate = inputFormat.sampleRate
        let fetchedDeviceInfo = fetchDefaultInputDeviceInfo()
        let isAirPodsDevice = fetchedDeviceInfo.map { DeviceChangeMonitor.isAirPods(deviceID: $0.id) } ?? false
        print("📊 input format: \(negotiatedSampleRate)hz, \(inputFormat.channelCount)ch")
        print("📊 target format: \(recordingFormat.sampleRate)hz, \(recordingFormat.channelCount)ch")
        print("📊 formats equal: \(inputFormat == recordingFormat)")

        let assessedQuality = AudioSegmentMetadata.assessQuality(sampleRate: inputFormat.sampleRate)
        setCurrentQuality(assessedQuality)
        if negotiatedSampleRate < 44_100 {
            print("⚠️ telephony sample rate detected: \(negotiatedSampleRate)hz (continuing with low-quality segment)")

            if isAirPodsDevice {
                if allowFallback && lowQualityAirPodsAttempts < airPodsRecoveryRetryLimit {
                    lowQualityAirPodsAttempts += 1
                    let holdUntil = Date().addingTimeInterval(airPodsRecoveryDelay)
                    pinnedUntil = holdUntil
                    extendStallSuppression(until: holdUntil, reason: "airpods-settle")
                    setErrorMessage("airpods mic settling – retrying shortly")
                    let retryMessage = Int(ceil(airPodsRecoveryDelay))
                    print("⚠️ airpods in low-quality mode – retrying (\(retryMessage)s)")
                    Thread.sleep(forTimeInterval: airPodsRecoveryDelay)
                    return false
                }

                if allowFallback && lowQualityAirPodsAttempts >= airPodsRecoveryRetryLimit {
                    if let fallbackID = DeviceChangeMonitor.builtInInputDeviceID(),
                       DeviceChangeMonitor.setDefaultInputDevice(fallbackID) {
                        lowQualityAirPodsAttempts = 0
                        setErrorMessage("airpods mic unstable – using mac microphone")
                        print("⚠️ airpods still low quality after retries – reverting to built-in mic")
                        Thread.sleep(forTimeInterval: Double(settleDelayNanoseconds) / 1_000_000_000)
                        return startNewSegmentInternal(reason: reason + "-airpods-fallback", allowFallback: false)
                    } else {
                        print("⚠️ failed to revert to built-in mic; recording with current device")
                    }
                }
            }
        } else {
            lowQualityAirPodsAttempts = 0
            if pinnedUntil != nil {
                pinnedUntil = nil
                print("🔓 cleared pinned mic – stable input at \(Int(negotiatedSampleRate))hz")
            }
            if routeUnstableUntil != nil {
                routeUnstableUntil = nil
            }
            if stallSuppressionUntil.timeIntervalSinceNow > 0 {
                stallSuppressionUntil = Date()
                print("⏳ stall suppression cleared after stable input")
            }
            routeChangeTimestamps.removeAll()
            significantRouteChangeTimes.removeAll()
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
        if let deviceInfo = fetchedDeviceInfo {
            currentDeviceAudioID = deviceInfo.id
            currentDeviceID = String(deviceInfo.id)
            deviceName = deviceInfo.name
            lastRouteChangeDeviceID = deviceInfo.id
            setCurrentDeviceName(deviceName)
            if DeviceChangeMonitor.isAirPods(deviceID: deviceInfo.id) {
                if negotiatedSampleRate <= 16_000 {
                    if allowFallback {
                        if shouldAllowTelephonyOverride() {
                            print("⚠️ telephony guard override accepted – recording with airpods at \(negotiatedSampleRate)hz")
                            setErrorMessage("airpods mic in call mode (lower quality) – recording as requested")
                        } else {
                            print("⚠️ airpods reported telephony sample rate (\(negotiatedSampleRate)hz) – holding mac microphone")
                            setErrorMessage("airpods mic in call mode (lower quality). holding mac mic – switch anyway?")
                            lastTelephonyGuardPrompt = Date()
                            if let fallbackID = DeviceChangeMonitor.builtInInputDeviceID(),
                               DeviceChangeMonitor.setDefaultInputDevice(fallbackID) {
                                Thread.sleep(forTimeInterval: Double(settleDelayNanoseconds) / 1_000_000_000)
                                return startNewSegmentInternal(reason: reason + "-telephony-guard", allowFallback: false)
                            } else {
                                print("⚠️ failed to switch input back to built-in microphone; continuing with current device")
                            }
                        }
                    } else {
                        print("⚠️ telephony guard override active – recording with low-quality airpods mic")
                        setErrorMessage("airpods mic in call mode (lower quality) – recording as requested")
                    }
                }
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
        let warmupDurationSeconds = Double(warmupFrames) / recordingFormat.sampleRate
        extendStallSuppression(by: warmupDurationSeconds + stallDetectionWindow, reason: "segment-warmup")

        lastKnownDeviceAudioID = currentDeviceAudioID
        lastKnownSampleRate = currentSampleRate

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

        writerQueue.sync(flags: .barrier) { }

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
            totalDroppedBuffers += dropped
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

        let suppression = stallSuppressionState()
        if suppression.active {
            if Date().timeIntervalSince(lastSuppressedStallLog) > 1.5 {
                print("⏳ mic stall suppressed (idle \(String(format: "%.1f", idleDuration))s, reason: \(suppression.reason), remaining: \(String(format: "%.2f", suppression.remaining))s)")
                lastSuppressedStallLog = Date()
            }
            stallDetectionStart = nil
            return
        }

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

        extendStallSuppression(by: idleDuration + Double(settleDelayNanoseconds) / 1_000_000_000 + stallDetectionWindow, reason: "stall-recovery")

        let releaseLock = switchLock?.acquire(for: "mic", reason: reason)
        defer { releaseLock?() }

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
        executedSwitchCount += 1
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

        writerQueue.async(flags: .barrier) { [weak self] in
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
                let warmupFramesDiscarded = discardedFrames
                controllerQueue.async { [weak self] in
                    guard let self else { return }
                    self.totalWarmupDiscardedFrames += warmupFramesDiscarded
                }
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
        guard let preservedID = preferredOutputDeviceID else { return }
        guard let currentID = DeviceChangeMonitor.currentOutputDeviceID() else { return }
        guard currentID != preservedID else { return }

        if DeviceChangeMonitor.isAirPods(deviceID: currentID) {
            let preservedName = DeviceChangeMonitor.deviceName(for: preservedID) ?? "previous device"
            if DeviceChangeMonitor.setDefaultOutputDevice(preservedID) {
                print("🎧 restored preserved output device mid-session: \(preservedName)")
            } else {
                print("⚠️ failed to restore preserved output device mid-session")
            }
        }
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

    private func logSessionDiagnostics() {
        let segments = segmentQueue.sync { segmentMetadata }
        let sortedSegments = segments.sorted { $0.startSessionTime < $1.startSessionTime }

        let totalMicDuration = sortedSegments.reduce(0.0) { partial, segment in
            let duration = max(0, segment.endSessionTime - segment.startSessionTime)
            return partial + duration
        }

        var totalGap: TimeInterval = 0
        if sortedSegments.count > 1 {
            for idx in 1..<sortedSegments.count {
                let previous = sortedSegments[idx - 1]
                let current = sortedSegments[idx]
                let gap = max(0, current.startSessionTime - previous.endSessionTime)
                totalGap += gap
            }
        }
        let gapCount = max(sortedSegments.count - 1, 0)
        let averageGap = gapCount > 0 ? totalGap / Double(gapCount) : 0

        let readinessAverage = readinessAttemptLog.isEmpty
            ? 0
            : Double(readinessAttemptLog.reduce(0, +)) / Double(readinessAttemptLog.count)

        let warmupSeconds = Double(totalWarmupDiscardedFrames) / 48_000.0

        let diagnostics = PerformanceMonitor.MicSessionDiagnostics(
            routeChanges: routeChangeRequestCount,
            executedSwitches: executedSwitchCount,
            pinnedActivations: pinnedActivations,
            averageReadinessAttempts: readinessAverage,
            readinessSamples: readinessAttemptLog.count,
            warmupDiscardSeconds: warmupSeconds,
            segmentCount: sortedSegments.count,
            totalMicDuration: totalMicDuration,
            averageGap: averageGap,
            writerDrops: totalDroppedBuffers,
            lossiness: "unknown"
        )

        print("📈 mic diagnostics:")
        print("   route changes observed: \(routeChangeRequestCount)")
        print("   switches executed: \(executedSwitchCount)")
        print("   pinned activations: \(pinnedActivations)")
        print("   readiness attempts avg: \(String(format: "%.2f", readinessAverage))")
        print("   warmup discard: \(String(format: "%.2f", warmupSeconds))s")
        print("   total mic duration: \(String(format: "%.2f", totalMicDuration))s across \(sortedSegments.count) segment(s)")
        print("   average gap between segments: \(String(format: "%.2f", averageGap))s")
        print("   writer drops: \(totalDroppedBuffers)")

        let monitor = controllerQueue.sync { self.performanceMonitor }

        if let monitor {
            Task { @MainActor in
                monitor.recordMicDiagnostics(diagnostics)
            }
        } else {
            print("📡 telemetry (mic diagnostics missing monitor): \(diagnostics.metadata)")
        }
    }
}
