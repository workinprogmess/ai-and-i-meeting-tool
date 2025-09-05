import SwiftUI

struct ContentView: View {
    @StateObject private var performanceMonitor = PerformanceMonitor()
    @State private var isRecording = false
    @State private var showInsights = false
    
    var body: some View {
        VStack(spacing: 20) {
            // App title
            Text("AI & I")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Native Mac Meeting Intelligence")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Recording status
            if isRecording {
                VStack {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                        .scaleEffect(isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                    
                    Text("Recording...")
                        .font(.title2)
                        .fontWeight(.medium)
                }
            } else {
                Image(systemName: "mic.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Control button
            Button(action: toggleRecording) {
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isRecording ? Color.red : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            
            // Admin insights toggle (hidden shortcut)
            Button("") {
                showInsights.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .hidden()
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
        .sheet(isPresented: $showInsights) {
            InsightsDashboard()
                .environmentObject(performanceMonitor)
        }
        .onAppear {
            // Measure app readiness time
            performanceMonitor.measureOperation("app_ready") {
                print("📱 App ready for user interaction")
            }
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            // Measure recording stop time
            performanceMonitor.measureOperation("recording_stop") {
                isRecording = false
                performanceMonitor.endRecordingMeasurement()
                print("Recording stopped")
            }
        } else {
            // Measure recording start time
            performanceMonitor.measureOperation("recording_start") {
                isRecording = true
                performanceMonitor.startRecordingMeasurement()
                performanceMonitor.resetAudioDropouts()
                print("Recording started")
            }
        }
    }
}

#Preview {
    ContentView()
}