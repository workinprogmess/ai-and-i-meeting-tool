import SwiftUI

/// Minimal insights dashboard for admin performance monitoring
/// Hidden feature accessible via Cmd+Shift+I
struct InsightsDashboard: View {
    @EnvironmentObject var performanceMonitor: PerformanceMonitor
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("performance insights")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("admin only")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.warningBackground)
                            .cornerRadius(4)
                    }
                    
                    // Performance Targets Status
                    performanceStatusSection
                    
                    // Core Metrics
                    coreMetricsSection
                    
                    // Memory Usage
                    memoryUsageSection
                    
                    // Performance History
                    if !performanceMonitor.recentLaunchTimes.isEmpty || !performanceMonitor.recentRecordingLatencies.isEmpty {
                        performanceHistorySection
                    }
                    
                    // Raw Performance Summary
                    rawDataSection
                }
                .padding()
            }
            .navigationTitle("ai & i insights")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    // MARK: - Performance Status Section
    private var performanceStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Status")
                .font(.headline)
            
            let status = performanceMonitor.meetsPerformanceTargets()
            
            HStack {
                Image(systemName: status.allTargetsMet ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(status.allTargetsMet ? .green : .orange)
                Text(status.allTargetsMet ? "All Targets Met" : "Needs Optimization")
                    .fontWeight(.medium)
            }
            
            Text(status.summary)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Core Metrics Section
    private var coreMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Core Metrics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                
                MetricCard(
                    title: "App Launch",
                    value: formatTime(performanceMonitor.appLaunchTime),
                    target: "< 1000ms",
                    isGood: performanceMonitor.appLaunchTime < 1000 && performanceMonitor.appLaunchTime > 0
                )
                
                MetricCard(
                    title: "Recording Start",
                    value: formatTime(performanceMonitor.recordingStartLatency),
                    target: "< 200ms",
                    isGood: performanceMonitor.recordingStartLatency < 200 && performanceMonitor.recordingStartLatency > 0
                )
                
                MetricCard(
                    title: "Recording Stop",
                    value: formatTime(performanceMonitor.recordingStopLatency),
                    target: "< 100ms",
                    isGood: performanceMonitor.recordingStopLatency < 100 && performanceMonitor.recordingStopLatency > 0
                )
                
                MetricCard(
                    title: "Device Switch",
                    value: formatTime(performanceMonitor.deviceSwitchTime),
                    target: "< 500ms",
                    isGood: performanceMonitor.deviceSwitchTime < 500 && performanceMonitor.deviceSwitchTime > 0
                )
            }
        }
    }
    
    // MARK: - Memory Usage Section
    private var memoryUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Memory Usage")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("\(String(format: "%.1f", performanceMonitor.memoryUsage)) MB")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(performanceMonitor.memoryUsage < 30 ? .primary : .orange)
                    
                    Text("Target: < 30 MB during recording")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Simple memory usage indicator
                Circle()
                    .fill(performanceMonitor.memoryUsage < 30 ? Color.green : Color.orange)
                    .frame(width: 12, height: 12)
            }
            
            if performanceMonitor.audioDropouts > 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("\(performanceMonitor.audioDropouts) audio dropouts detected")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Performance History Section
    private var performanceHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance History")
                .font(.headline)
            
            if !performanceMonitor.recentLaunchTimes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Launch Times")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(Array(performanceMonitor.recentLaunchTimes.enumerated().suffix(5)), id: \.offset) { _, time in
                        HStack {
                            Text(formatTime(time))
                            Spacer()
                            Image(systemName: time < 1000 ? "checkmark" : "xmark")
                                .foregroundColor(time < 1000 ? .green : .red)
                        }
                        .font(.caption)
                    }
                }
            }
            
            if !performanceMonitor.recentRecordingLatencies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent Recording Latencies")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(Array(performanceMonitor.recentRecordingLatencies.enumerated().suffix(5)), id: \.offset) { _, time in
                        HStack {
                            Text(formatTime(time))
                            Spacer()
                            Image(systemName: time < 200 ? "checkmark" : "xmark")
                                .foregroundColor(time < 200 ? .green : .red)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Raw Data Section
    private var rawDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Performance Data")
                .font(.headline)
            
            Text(performanceMonitor.performanceSummary())
                .font(.system(.caption, design: .monospaced))
                .padding()
                .background(Color(.textBackgroundColor))
                .cornerRadius(4)
        }
    }
    
    // MARK: - Helper Functions
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        if timeInterval <= 0 {
            return "—"
        }
        return String(format: "%.1f ms", timeInterval)
    }
}

// MARK: - Metric Card Component
struct MetricCard: View {
    let title: String
    let value: String
    let target: String
    let isGood: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: isGood ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isGood ? .green : .secondary)
                    .font(.caption)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(isGood ? .primary : .orange)
            
            Text(target)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Preview
struct InsightsDashboard_Previews: PreviewProvider {
    static var previews: some View {
        InsightsDashboard()
            .environmentObject(PerformanceMonitor())
    }
}