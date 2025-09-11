import SwiftUI

struct ContentView: View {
    @StateObject private var performanceMonitor = PerformanceMonitor()
    // new segmented recorders replace old AudioManager approach
    @StateObject private var micRecorder = MicRecorder()
    @StateObject private var systemRecorder = SystemAudioRecorder()
    @StateObject private var deviceMonitor = DeviceChangeMonitor()
    // keep old managers temporarily for comparison
    @StateObject private var audioManager = AudioManager()
    @StateObject private var screenCaptureManager = ScreenCaptureManager()
    @State private var showInsights = false
    @State private var useNewRecorders = true  // toggle for testing
    
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
            if (useNewRecorders ? micRecorder.isRecording : audioManager.isRecording) {
                VStack {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                        .scaleEffect(1.1)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), 
                                 value: useNewRecorders ? micRecorder.isRecording : audioManager.isRecording)
                    
                    Text("recording...")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    // show device info with new recorders
                    if useNewRecorders && micRecorder.isRecording {
                        Text(micRecorder.currentDeviceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        // quality indicator
                        HStack {
                            Circle()
                                .fill(micRecorder.currentQuality == .high ? Color.green : 
                                     micRecorder.currentQuality == .medium ? Color.yellow : Color.red)
                                .frame(width: 8, height: 8)
                            Text(micRecorder.currentQuality.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Image(systemName: "mic.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // system audio capture status
            if (useNewRecorders ? systemRecorder.isRecording : screenCaptureManager.isCapturing) {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(.green)
                    Text("capturing system audio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // error messages from new recorders
            if useNewRecorders {
                if let micError = micRecorder.errorMessage {
                    Text(micError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let systemError = systemRecorder.errorMessage {
                    Text(systemError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            // Control button
            Button(action: toggleRecording) {
                Text((useNewRecorders ? micRecorder.isRecording : audioManager.isRecording) ? "stop recording" : "start recording")
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
            if useNewRecorders {
                // setup device monitoring
                deviceMonitor.startMonitoring()
                
                // connect device change callbacks (safe - just sets flags)
                deviceMonitor.onMicDeviceChange = { reason in
                    // safe to call directly - just sets a flag
                    micRecorder.handleDeviceChange(reason: reason)
                }
                deviceMonitor.onSystemDeviceChange = { reason in
                    Task {
                        await systemRecorder.handleDeviceChange(reason: reason)
                    }
                }
                
                print("✅ new segmented recorders initialized")
            } else {
                // connect performance monitor to audio manager
                audioManager.setPerformanceMonitor(performanceMonitor)
            }
            
            // record actual app launch time when UI is ready
            performanceMonitor.recordAppLaunch()
        }
    }
    
    private func toggleRecording() {
        if useNewRecorders {
            // new segmented recording approach
            if micRecorder.isRecording {
                // stop recording
                performanceMonitor.endRecordingMeasurement()
                
                Task {
                    // stop both recorders
                    micRecorder.endSession()
                    await systemRecorder.endSession()
                    
                    print("🎬 recording ended - segments saved")
                    print("📝 todo: implement segment stitching with ffmpeg")
                    
                    // TODO: implement segment stitching
                    // 1. load metadata files
                    // 2. generate ffmpeg concat lists
                    // 3. stitch mic segments
                    // 4. stitch system segments
                    // 5. mix final files
                }
            } else {
                // start recording
                performanceMonitor.startRecordingMeasurement()
                performanceMonitor.resetAudioDropouts()
                
                Task {
                    // start both recorders independently
                    micRecorder.startSession()
                    await systemRecorder.startSession()
                    
                    print("🎬 segmented recording started")
                }
            }
        } else {
            // old approach (for comparison)
            if audioManager.isRecording {
                // stop recording
                audioManager.stopRecording()
                performanceMonitor.endRecordingMeasurement()
                
                // stop system audio capture and get timing info
                Task {
                    let (timestamp, delay) = await screenCaptureManager.stopCapture()
                    
                    // trigger ffmpeg mixing with delay compensation
                    if timestamp > 0 {
                        print("🎬 mixing audio files with timestamp: \(Int(timestamp)), delay: \(delay)s")
                        
                        // use 2.0s as default delay (can be refined based on actual measurements)
                        let systemDelay = delay > 0 ? delay : 2.0
                        
                        // mix the audio files
                        let success = await audioManager.mixAudioFiles(timestamp: timestamp, systemDelay: systemDelay)
                        
                        if success {
                            print("🎉 audio mixing successful! check mixed_\(Int(timestamp)).wav")
                        } else {
                            print("❌ audio mixing failed - check individual files")
                        }
                    }
                }
            } else {
                // generate shared timestamp for both recordings
                let sharedTimestamp = Date().timeIntervalSince1970
                print("🎬 starting recording with shared timestamp: \(Int(sharedTimestamp))")
                
                // start mic recording with timestamp (will prompt for mic permission if needed)
                audioManager.startRecording(timestamp: sharedTimestamp)
                print("📍 called audioManager.startRecording, isRecording = \(audioManager.isRecording)")
                performanceMonitor.startRecordingMeasurement()
                performanceMonitor.resetAudioDropouts()
                
                // Start screen capture for system audio with same timestamp
                // Now that we've fixed the format conflict, this should work
                screenCaptureManager.audioManager = audioManager
                Task {
                    await screenCaptureManager.startCaptureForDisplay(sharedTimestamp: sharedTimestamp)
                    print("📍 screen capture started, isCapturing = \(await screenCaptureManager.isCapturing)")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}