import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct RecordingDebugOptions {
    var simulateDeviceChangeOnStart = false
    var simulateTelephonyMode = false
    var logLifecycleTransitions = false
    var disableWarmShutdown = false
}

@MainActor
final class RecordingSessionCoordinator {
    private let micRecorder: MicRecorder
    private let systemRecorder: SystemAudioRecorder
    private let deviceMonitor: DeviceChangeMonitor
    private var performanceMonitor: PerformanceMonitor?

    private(set) var currentContext: RecordingSessionContext?
    var debugOptions = RecordingDebugOptions()

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
        setupLifecycleObservers()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    func preparePipelinesIfNeeded() async {
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
        if !deviceMonitor.isMonitoring {
            deviceMonitor.startMonitoring()
            print("📱 device monitor started via coordinator")
            emitTelemetry(.debugToggleActive, metadata: ["toggle": "deviceMonitorAutoStart"])
        }

        let context = RecordingSessionContext.create()
        do {
            try await micRecorder.startSession(context)
            try await systemRecorder.startSession(context)
            currentContext = context

            if debugOptions.simulateDeviceChangeOnStart {
                emitTelemetry(.debugToggleActive, metadata: ["toggle": "simulateDeviceChangeOnStart"])
                await handleDeviceChange(reason: "debug-simulated")
            }

            if debugOptions.simulateTelephonyMode {
                emitTelemetry(.debugToggleActive, metadata: ["toggle": "simulateTelephonyMode"])
            }

            emitTelemetry(.sessionStarted, metadata: ["context": context.id])

            return context
        } catch {
            micRecorder.endSession()
            await systemRecorder.endSession()
            deviceMonitor.stopMonitoring()
            currentContext = nil
            emitTelemetry(.sessionStartFailed, metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    func stopSession() async {
        micRecorder.endSession()
        await systemRecorder.endSession()
        if deviceMonitor.isMonitoring {
            deviceMonitor.stopMonitoring()
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

    private func pauseWarmPipelines() {
        micRecorder.shutdownWarmPipeline()
        systemRecorder.shutdownWarmPipeline()
        emitTelemetry(.warmPipelinesPaused)
    }

    private func setupLifecycleObservers() {
#if canImport(AppKit)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pauseWarmPipelines()
        })

        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.preparePipelinesIfNeeded()
            }
        })
#endif
    }

    func attachPerformanceMonitor(_ monitor: PerformanceMonitor) {
        performanceMonitor = monitor
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
}
