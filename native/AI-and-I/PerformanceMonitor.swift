import Foundation
import SwiftUI
import Combine

/// Real-time performance monitoring system for AI & I
/// Tracks microsecond-precision metrics for performance-first development
@MainActor
class PerformanceMonitor: ObservableObject {
    struct RecordingTelemetryEntry: Identifiable {
        let id = UUID()
        let event: String
        let timestamp: Date
        let metadata: [String: String]
    }

    // MARK: - Published Metrics
    @Published var appLaunchTime: TimeInterval = 0
    @Published var recordingStartLatency: TimeInterval = 0
    @Published var recordingStopLatency: TimeInterval = 0
    @Published var memoryUsage: Double = 0
    @Published var audioDropouts: Int = 0
    @Published var deviceSwitchTime: TimeInterval = 0
    @Published var audioQuality: AudioQualityMetrics = AudioQualityMetrics()
    @Published var recordingTelemetry: [RecordingTelemetryEntry] = []
    
    // MARK: - Performance History
    @Published var recentLaunchTimes: [TimeInterval] = []
    @Published var recentRecordingLatencies: [TimeInterval] = []
    @Published var isRecording = false
    
    // MARK: - Private Properties
    private var measurements: [String: [TimeInterval]] = [:]
    private var memoryTimer: Timer?
    private let maxHistoryCount = 10
    private let appStartTime = CFAbsoluteTimeGetCurrent() // precise app launch time tracking
    
    // MARK: - Initialization
    init() {
        startMemoryMonitoring()
        // don't record app launch here - wait for UI ready signal
    }
    
    deinit {
        memoryTimer?.invalidate()
    }
}

// MARK: - Core Measurement Functions
extension PerformanceMonitor {
    
    /// Measures execution time of any operation with microsecond precision
    /// - Parameters:
    ///   - operation: Name of the operation being measured
    ///   - block: The operation to measure
    /// - Returns: The result of the operation
    func measureOperation<T>(_ operation: String, _ block: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to milliseconds
        
        recordMeasurement(operation, duration)
        return result
    }
    
    /// Measures async operations with precision timing
    func measureAsyncOperation<T>(_ operation: String, _ block: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        recordMeasurement(operation, duration)
        return result
    }
    
    /// Records a measurement and updates published properties
    private func recordMeasurement(_ operation: String, _ duration: TimeInterval) {
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            self?.updatePublishedProperties(operation, duration)
        }
    }
    
    /// Updates published properties on main thread
    private func updatePublishedProperties(_ operation: String, _ duration: TimeInterval) {
        // Store in history
        if measurements[operation] == nil {
            measurements[operation] = []
        }
        measurements[operation]?.append(duration)
        
        // Keep only recent measurements
        if measurements[operation]?.count ?? 0 > maxHistoryCount {
            measurements[operation]?.removeFirst()
        }
        
        // Update specific published properties
        switch operation {
        case "app_launch":
            appLaunchTime = duration
            recentLaunchTimes.append(duration)
            if recentLaunchTimes.count > maxHistoryCount {
                recentLaunchTimes.removeFirst()
            }
            
        case "recording_start":
            recordingStartLatency = duration
            recentRecordingLatencies.append(duration)
            if recentRecordingLatencies.count > maxHistoryCount {
                recentRecordingLatencies.removeFirst()
            }
            
        case "recording_stop":
            recordingStopLatency = duration
            
        case "device_switch":
            deviceSwitchTime = duration
            
        default:
            break
        }
        
        print("📊 Performance: \(operation) = \(String(format: "%.1f", duration))ms")
    }
}

// MARK: - Specific Measurements
extension PerformanceMonitor {
    
    /// records actual app launch time from initialization to ui ready
    func recordAppLaunch() {
        // calculate precise time from app start to ui ready
        let launchTime = (CFAbsoluteTimeGetCurrent() - appStartTime) * 1000 // convert to milliseconds
        
        // update on main thread immediately for UI
        DispatchQueue.main.async { [weak self] in
            self?.appLaunchTime = launchTime
            self?.recentLaunchTimes.append(launchTime)
            if self?.recentLaunchTimes.count ?? 0 > self?.maxHistoryCount ?? 10 {
                self?.recentLaunchTimes.removeFirst()
            }
        }
        
        // also record through normal measurement flow
        recordMeasurement("app_launch", launchTime)
        print("📱 app launch measured: \(String(format: "%.1f", launchTime))ms")
    }
    
    /// Starts recording session timing
    func startRecordingMeasurement() {
        isRecording = true
    }
    
    /// Ends recording session timing
    func endRecordingMeasurement() {
        isRecording = false
    }
    
    /// Records audio dropout event
    func recordAudioDropout() {
        audioDropouts += 1
    }
    
    /// Resets dropout counter (e.g., when starting new recording)
    func resetAudioDropouts() {
        audioDropouts = 0
    }
}

// MARK: - Recording Telemetry
extension PerformanceMonitor {

    func recordRecordingEvent(_ event: String, metadata: [String: String] = [:]) {
        let entry = RecordingTelemetryEntry(event: event, timestamp: Date(), metadata: metadata)
        recordingTelemetry.append(entry)

        if recordingTelemetry.count > maxHistoryCount {
            recordingTelemetry.removeFirst()
        }

        if metadata.isEmpty {
            print("📡 RecordingEvent: \(event)")
        } else {
            print("📡 RecordingEvent: \(event) :: \(metadata)")
        }
    }
}

// MARK: - Memory Monitoring
extension PerformanceMonitor {
    
    /// Starts continuous memory monitoring
    private func startMemoryMonitoring() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateMemoryUsage()
            }
        }
    }
    
    /// Updates current memory usage
    private func updateMemoryUsage() {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryUsageMB = Double(memoryInfo.resident_size) / 1024 / 1024
            memoryUsage = memoryUsageMB
        }
    }
}

// MARK: - Performance Analysis
extension PerformanceMonitor {
    
    /// Average performance for an operation
    func averagePerformance(for operation: String) -> TimeInterval? {
        guard let measurements = measurements[operation], !measurements.isEmpty else {
            return nil
        }
        return measurements.reduce(0, +) / Double(measurements.count)
    }
    
    /// Best (fastest) performance for an operation
    func bestPerformance(for operation: String) -> TimeInterval? {
        return measurements[operation]?.min()
    }
    
    /// Worst (slowest) performance for an operation
    func worstPerformance(for operation: String) -> TimeInterval? {
        return measurements[operation]?.max()
    }
    
    /// Performance summary for logging or dashboard
    func performanceSummary() -> String {
        var summary = "📊 Performance Summary:\n"
        
        if appLaunchTime > 0 {
            summary += "App Launch: \(String(format: "%.1f", appLaunchTime))ms\n"
        }
        
        if recordingStartLatency > 0 {
            summary += "Recording Start: \(String(format: "%.1f", recordingStartLatency))ms\n"
        }
        
        if deviceSwitchTime > 0 {
            summary += "Device Switch: \(String(format: "%.1f", deviceSwitchTime))ms\n"
        }
        
        summary += "Memory Usage: \(String(format: "%.1f", memoryUsage))MB\n"
        summary += "Audio Dropouts: \(audioDropouts)"
        
        return summary
    }
    
    /// Check if performance meets targets
    func meetsPerformanceTargets() -> PerformanceStatus {
        var status = PerformanceStatus()
        
        // App launch target: < 1000ms
        status.appLaunchOK = appLaunchTime < 1000
        
        // Recording start target: < 200ms
        status.recordingStartOK = recordingStartLatency < 200
        
        // Memory target: < 30MB during recording
        status.memoryOK = !isRecording || memoryUsage < 30
        
        // Device switch target: < 500ms
        status.deviceSwitchOK = deviceSwitchTime < 500
        
        // No audio dropouts
        status.audioQualityOK = audioDropouts == 0
        
        return status
    }
}

// MARK: - Supporting Types
struct AudioQualityMetrics {
    var sampleRate: Double = 44100
    var bitDepth: Int = 16
    var channels: Int = 2
    var dropouts: Int = 0
}

struct PerformanceStatus {
    var appLaunchOK: Bool = false
    var recordingStartOK: Bool = false
    var memoryOK: Bool = false
    var deviceSwitchOK: Bool = false
    var audioQualityOK: Bool = false
    
    var allTargetsMet: Bool {
        return appLaunchOK && recordingStartOK && memoryOK && deviceSwitchOK && audioQualityOK
    }
    
    var summary: String {
        let indicators = [
            ("🚀 Launch", appLaunchOK),
            ("⚡ Record", recordingStartOK),
            ("💾 Memory", memoryOK),
            ("🎧 Switch", deviceSwitchOK),
            ("🎵 Audio", audioQualityOK)
        ]
        
        return indicators.map { name, ok in
            "\(name): \(ok ? "✅" : "❌")"
        }.joined(separator: " ")
    }
}
