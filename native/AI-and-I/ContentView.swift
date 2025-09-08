import SwiftUI

struct ContentView: View {
    @StateObject private var performanceMonitor = PerformanceMonitor()
    @StateObject private var audioManager = AudioManager()
    @StateObject private var screenCaptureManager = ScreenCaptureManager()
    @State private var showInsights = false
    
    var body: some View {
        VStack(spacing: 20) {
            // app title
            Text("ai & i")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("native mac meeting intelligence")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // recording status
            if audioManager.isRecording {
                VStack {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                        .scaleEffect(audioManager.isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: audioManager.isRecording)
                    
                    Text("recording...")
                        .font(.title2)
                        .fontWeight(.medium)
                }
            } else {
                Image(systemName: "mic.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // system audio capture status
            if screenCaptureManager.isCapturing {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(.green)
                    Text("capturing system audio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Control button
            Button(action: toggleRecording) {
                Text(audioManager.isRecording ? "stop recording" : "start recording")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(audioManager.isRecording ? Color.red : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            
            // admin insights toggle (hidden shortcut)
            Button("") {
                print("🔍 insights shortcut pressed")
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
            // connect performance monitor to audio manager
            audioManager.setPerformanceMonitor(performanceMonitor)
            
            // record actual app launch time when UI is ready
            performanceMonitor.recordAppLaunch()
        }
    }
    
    private func toggleRecording() {
        if audioManager.isRecording {
            // stop recording
            audioManager.stopRecording()
            performanceMonitor.endRecordingMeasurement()
            
            // stop system audio capture
            Task {
                await screenCaptureManager.stopCapture()
            }
        } else {
            // start both recordings - let each handle their own permissions
            print("🎬 starting recording...")
            
            // start mic recording (will prompt for mic permission if needed)
            audioManager.startRecording()
            print("📍 called audioManager.startRecording, isRecording = \(audioManager.isRecording)")
            performanceMonitor.startRecordingMeasurement()
            performanceMonitor.resetAudioDropouts()
            
            // Start screen capture for system audio
            // Now that we've fixed the format conflict, this should work
            screenCaptureManager.audioManager = audioManager
            Task {
                await screenCaptureManager.startCaptureForDisplay()
                print("📍 screen capture started, isCapturing = \(await screenCaptureManager.isCapturing)")
            }
        }
    }
}

#Preview {
    ContentView()
}