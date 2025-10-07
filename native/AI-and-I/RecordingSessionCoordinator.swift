import Foundation
#if canImport(AppKit)
import AppKit
#endif

final class PipelineSwitchLock {
    private let semaphore = DispatchSemaphore(value: 1)

    func acquire(for pipeline: String, reason: String) -> () -> Void {
        semaphore.wait()
        let semaphore = self.semaphore
        return {
            semaphore.signal()
        }
    }
}

struct RecordingDebugOptions {
    var simulateDeviceChangeOnStart = false
    var simulateTelephonyMode = false
    var logLifecycleTransitions = false
    var disableWarmShutdown = false
}

actor RecordingSessionCoordinator {
    private let micRecorder: MicRecorder
    private let systemRecorder: SystemAudioRecorder
    private let deviceMonitor: DeviceChangeMonitor
    private var performanceMonitor: PerformanceMonitor?
    private let switchLock = PipelineSwitchLock()

    private(set) var currentContext: RecordingSessionContext?
    var debugOptions = RecordingDebugOptions()
    private var isLaunchingSession = false

    private var observers: [NSObjectProtocol] = []

    enum TelemetryEvent: String {
        case warmPrepRequested
        case warmPrepCompleted
        case warmPrepFailed
        case sessionStartRequested
        case sessionStarted
        case sessionStartFailed
        case sessionStopped
        case deviceChangeHandled
        case warmPipelinesPaused
        case warmShutdownSkipped
        case debugToggleActive
    }

    init(micRecorder: MicRecorder,
         systemRecorder: SystemAudioRecorder,
         deviceMonitor: DeviceChangeMonitor,
         performanceMonitor: PerformanceMonitor? = nil) {
        self.micRecorder = micRecorder
        self.systemRecorder = systemRecorder
        self.deviceMonitor = deviceMonitor
        self.performanceMonitor = performanceMonitor
        self.micRecorder.attachSwitchLock(switchLock)
        self.systemRecorder.attachSwitchLock(switchLock)
        // TODO: lifecycle observers temporarily disabled while debugging startup deadlock
        //setupLifecycleObservers()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    func preparePipelinesIfNeeded() async {
        guard !isLaunchingSession, currentContext == nil else {
            if debugOptions.logLifecycleTransitions {
                print("⚙️ skipping warm prep – session launch in progress or active")
            }
            return
        }
        emitTelemetry(.warmPrepRequested)
        do {
            try await micRecorder.prepareWarmPipeline()
            try await systemRecorder.prepareWarmPipeline()
            emitTelemetry(.warmPrepCompleted)
        } catch {
            print("⚠️ warm pipeline preparation warning: \(error)")
            emitTelemetry(.warmPrepFailed, metadata: ["error": error.localizedDescription])
        }
    }

    @discardableResult
    func startSession() async throws -> RecordingSessionContext {
        emitTelemetry(.sessionStartRequested)
        print("🎛️ coordinator: preparing session context...")
        print("🎛️ coordinator: creating session context")
        let now = Date()
        let contextID = StableIDGenerator.make(prefix: "session")
        let context = RecordingSessionContext(id: contextID, startDate: now, timestamp: now.timeIntervalSince1970)
        print("🎛️ coordinator: context created")
        isLaunchingSession = true
        defer { isLaunchingSession = false }
        do {
            print("🎛️ coordinator: starting mic pipeline")
            print("🎛️ coordinator: invoking micRecorder.startSession (thread: \(Thread.isMainThread ? "main" : "background"))")
            try await micRecorder.startSession(context)
            print("🎛️ coordinator: micRecorder.startSession completed")
            print("🎛️ coordinator: starting system pipeline")
            print("🎛️ coordinator: invoking systemRecorder.startSession (thread: \(Thread.isMainThread ? "main" : "background"))")
            try await systemRecorder.startSession(context)
            print("🎛️ coordinator: systemRecorder.startSession completed")
            currentContext = context

            if debugOptions.simulateDeviceChangeOnStart {
                emitTelemetry(.debugToggleActive, metadata: ["toggle": "simulateDeviceChangeOnStart"])
                await handleDeviceChange(reason: "debug-simulated")
            }

            if debugOptions.simulateTelephonyMode {
                emitTelemetry(.debugToggleActive, metadata: ["toggle": "simulateTelephonyMode"])
            }

            recordTelemetryAsync(.sessionStarted, metadata: ["context": context.id])

            return context
        } catch {
            print("❌ coordinator: startSession failed before pipelines ready: \(error)")
            micRecorder.endSession()
            await systemRecorder.endSession()
            if await deviceMonitor.isMonitoring {
                await deviceMonitor.stopMonitoring()
                print("📱 device monitor stopped after start failure")
            }
            currentContext = nil
            recordTelemetryAsync(.sessionStartFailed, metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    func stopSession() async {
        micRecorder.endSession()
        await systemRecorder.endSession()
        let wasMonitoring = await deviceMonitor.isMonitoring
        if wasMonitoring {
            await deviceMonitor.stopMonitoring()
            print("📱 device monitor stopped via coordinator")
        }
        currentContext = nil
        if debugOptions.disableWarmShutdown {
            emitTelemetry(.warmShutdownSkipped)
        } else {
            await preparePipelinesIfNeeded()
        }
        emitTelemetry(.sessionStopped)
    }

    func handleMicDeviceChange(reason: String) async {
        micRecorder.handleDeviceChange(reason: reason)
        emitTelemetry(.deviceChangeHandled, metadata: ["pipeline": "mic", "reason": reason])
    }

    func handleSystemDeviceChange(reason: String) async {
        await systemRecorder.handleDeviceChange(reason: reason)
        emitTelemetry(.deviceChangeHandled, metadata: ["pipeline": "system", "reason": reason])
    }

    func handleDeviceChange(reason: String) async {
        await handleMicDeviceChange(reason: reason)
        await handleSystemDeviceChange(reason: reason)
    }

    func simulateDeviceChange(reason: String = "debug-trigger") async {
        await handleDeviceChange(reason: reason)
    }

    private func pauseWarmPipelines() async {
        guard !isLaunchingSession else {
            if debugOptions.logLifecycleTransitions {
                print("⚙️ skipping warm pipeline pause – launch in progress")
            }
            return
        }
        let micActive = await MainActor.run { micRecorder.isRecording }
        let systemActive = await MainActor.run { systemRecorder.isRecording }
        guard !micActive, !systemActive else {
            if debugOptions.logLifecycleTransitions {
                print("⚙️ skip warm pipeline pause – recording active")
            }
            return
        }
        micRecorder.shutdownWarmPipeline()
        systemRecorder.shutdownWarmPipeline()
        emitTelemetry(.warmPipelinesPaused)
    }

    private func setupLifecycleObservers() {
#if canImport(AppKit)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                await self.pauseWarmPipelines()
            }
        })

        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                await self.preparePipelinesIfNeeded()
            }
        })
#endif
    }

    func attachPerformanceMonitor(_ monitor: PerformanceMonitor) {
        performanceMonitor = monitor
        micRecorder.attachPerformanceMonitor(monitor)
    }

    private func emitTelemetry(_ event: TelemetryEvent, metadata: [String: String] = [:]) {
        performanceMonitor?.recordRecordingEvent(event.rawValue, metadata: metadata)

        if debugOptions.logLifecycleTransitions {
            if metadata.isEmpty {
                print("📡 telemetry: \(event.rawValue)")
            } else {
                print("📡 telemetry: \(event.rawValue) :: \(metadata)")
            }
        }
    }

    private func recordTelemetryAsync(_ event: TelemetryEvent, metadata: [String: String] = [:]) {
        performanceMonitor?.recordRecordingEvent(event.rawValue, metadata: metadata)
    }
}
