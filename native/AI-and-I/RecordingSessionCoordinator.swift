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
    var autoStartDeviceMonitor = true
    var autoWarmOnLaunch = true
    var autoWarmOnResume = true
    var autoPauseOnBackground = true
    var autoWarmAfterStop = true
}

actor RecordingSessionCoordinator {
    private let micRecorder: MicRecorder
    private let systemRecorder: SystemAudioRecorder
    private let deviceMonitor: DeviceChangeMonitor
    private var performanceMonitor: PerformanceMonitor?
    private let switchLock = PipelineSwitchLock()

    private enum PipelineKind: String {
        case mic
        case system
    }

    private(set) var currentContext: RecordingSessionContext?
    var debugOptions = RecordingDebugOptions()
    private var isLaunchingSession = false

    private var observers: [NSObjectProtocol] = []

    enum TelemetryEvent: String {
        case warmPrepRequested
        case warmPrepCompleted
        case warmPrepFailed
        case warmPipelineShutdown
        case warmPipelineResume
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
#if canImport(AppKit)
        setupLifecycleObservers()
#endif
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func preparePipeline(kind: PipelineKind) async {
        do {
            let pipelineName = kind.rawValue
            emitTelemetry(.warmPrepRequested, metadata: ["pipeline": pipelineName])
            switch kind {
            case .mic:
                try await micRecorder.prepareWarmPipeline()
            case .system:
                try await systemRecorder.prepareWarmPipeline()
            }
            emitTelemetry(.warmPrepCompleted, metadata: ["pipeline": pipelineName])
            emitTelemetry(.warmPipelineResume, metadata: ["pipeline": pipelineName])
        } catch {
            let pipelineName = kind.rawValue
            print("⚠️ warm pipeline preparation warning (\(pipelineName)): \(error)")
            emitTelemetry(
                .warmPrepFailed,
                metadata: [
                    "pipeline": pipelineName,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    private func shutdownPipeline(kind: PipelineKind) {
        let pipelineName = kind.rawValue
        switch kind {
        case .mic:
            micRecorder.shutdownWarmPipeline()
        case .system:
            systemRecorder.shutdownWarmPipeline()
        }
        emitTelemetry(.warmPipelineShutdown, metadata: ["pipeline": pipelineName])
    }

    func preparePipelinesIfNeeded(trigger: String = "manual") async {
        guard !isLaunchingSession, currentContext == nil else {
            if debugOptions.logLifecycleTransitions {
                print("⚙️ skipping warm prep – session launch in progress or active")
            }
            return
        }
        emitTelemetry(.warmPrepRequested, metadata: ["trigger": trigger])

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.preparePipeline(kind: .mic)
            }
            group.addTask { [weak self] in
                await self?.preparePipeline(kind: .system)
            }
        }

        emitTelemetry(.warmPrepCompleted, metadata: ["trigger": trigger])
    }

    @discardableResult
    func startSession() async throws -> RecordingSessionContext {
        await MainActor.run {
            if debugOptions.autoStartDeviceMonitor, !deviceMonitor.isMonitoring {
                deviceMonitor.startMonitoring()
            } else if debugOptions.logLifecycleTransitions, !debugOptions.autoStartDeviceMonitor {
                print("⚙️ skipping device monitor auto-start – debug option disabled")
            }
        }

        if debugOptions.autoWarmOnLaunch {
            await preparePipelinesIfNeeded(trigger: "session-start")
        } else if debugOptions.logLifecycleTransitions {
            print("⚙️ skipping warm prep on session start – autoWarmOnLaunch disabled")
        }
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
                micRecorder.handleDeviceChange(reason: "debug-telephony")
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
            await pauseWarmPipelines(trigger: "session-stop", force: true)
            if debugOptions.autoWarmAfterStop {
                await preparePipelinesIfNeeded(trigger: "post-stop")
            } else if debugOptions.logLifecycleTransitions {
                print("⚙️ skipping post-stop warm prep – autoWarmAfterStop disabled")
            }
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

    private func pauseWarmPipelines(trigger: String = "manual", force: Bool = false) async {
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
        if !force && !debugOptions.autoPauseOnBackground {
            if debugOptions.logLifecycleTransitions {
                print("⚙️ skipping warm pipeline pause for trigger \(trigger) – autoPauseOnBackground disabled")
            }
            return
        }
        shutdownPipeline(kind: .mic)
        shutdownPipeline(kind: .system)
        emitTelemetry(.warmPipelinesPaused, metadata: ["trigger": trigger])
    }

    private func setupLifecycleObservers() {
#if canImport(AppKit)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                await self.pauseWarmPipelines(trigger: "app-background")
            }
        })

        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { [weak self] in
                guard let self else { return }
                if self.debugOptions.autoWarmOnResume {
                    await self.preparePipelinesIfNeeded(trigger: "app-foreground")
                } else if self.debugOptions.logLifecycleTransitions {
                    print("⚙️ skipping warm prep on resume – autoWarmOnResume disabled")
                }
            }
        })
#endif
    }

    func attachPerformanceMonitor(_ monitor: PerformanceMonitor) {
        performanceMonitor = monitor
        micRecorder.attachPerformanceMonitor(monitor)
        systemRecorder.attachPerformanceMonitor(monitor)
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
