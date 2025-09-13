//
//  TranscriptionTester.swift
//  AI-and-I
//
//  test harness for comparing transcription services
//  runs all three services on the same audio file
//

import Foundation
import SwiftUI
import AVFoundation

// hex color extension for this file only
extension Color {
    fileprivate init(hexString hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// view model for testing transcription services
@MainActor
class TranscriptionTester: ObservableObject {
    @Published var isProcessing = false
    @Published var results: [TranscriptionResult] = []
    @Published var errorMessage: String?
    @Published var testStatus = "ready to test"
    @Published var comparison: TranscriptionComparison?
    
    private let coordinator: TranscriptionCoordinator
    
    init() {
        // create all three services
        var services: [TranscriptionService] = []
        
        if let gemini = GeminiTranscriptionService.createFromEnvironment() {
            services.append(gemini)
            print("✅ gemini service ready")
        } else {
            print("⚠️ gemini service not available")
        }
        
        if let deepgram = DeepgramTranscriptionService.createFromEnvironment() {
            services.append(deepgram)
            print("✅ deepgram service ready")
        } else {
            print("⚠️ deepgram service not available")
        }
        
        if let assembly = AssemblyAITranscriptionService.createFromEnvironment() {
            services.append(assembly)
            print("✅ assembly ai service ready")
        } else {
            print("⚠️ assembly ai service not available")
        }
        
        coordinator = TranscriptionCoordinator(services: services)
    }
    
    /// test with the most recent mixed audio file
    func testWithLatestRecording() async {
        testStatus = "finding latest recording..."
        
        // find the most recent mixed audio file
        guard let audioURL = findLatestMixedAudio() else {
            errorMessage = "no mixed audio files found. record something first!"
            testStatus = "no recordings found"
            return
        }
        
        testStatus = "testing with: \(audioURL.lastPathComponent)"
        
        // run transcription
        await coordinator.transcribeWithAllServices(audioURL: audioURL)
        
        // update results
        results = coordinator.results
        errorMessage = coordinator.errorMessage
        
        if results.isEmpty {
            testStatus = "all services failed"
        } else {
            testStatus = "completed - \(results.count) services succeeded"
            
            // analyze quality metrics
            comparison = TranscriptionComparison()
            
            // get audio duration for quality analysis
            if let duration = getAudioDuration(url: audioURL) {
                comparison?.compareResults(results, audioDuration: duration)
            } else {
                comparison?.compareResults(results)
            }
        }
    }
    
    /// find the most recent mixed audio file
    private func findLatestMixedAudio() -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: recordingsFolder,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
            
            // find mixed audio files (start with "mixed_")
            let mixedFiles = files.filter { url in
                let filename = url.lastPathComponent
                return filename.hasPrefix("mixed_") && 
                       (filename.hasSuffix(".wav") || filename.hasSuffix(".mp3"))
            }
            
            // sort by creation date (newest first)
            let sortedFiles = mixedFiles.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 > date2
            }
            
            return sortedFiles.first
            
        } catch {
            print("error finding recordings: \(error)")
            return nil
        }
    }
    
    /// get audio file duration
    private func getAudioDuration(url: URL) -> TimeInterval? {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let frames = audioFile.length
            let sampleRate = audioFile.processingFormat.sampleRate
            return Double(frames) / sampleRate
        } catch {
            print("couldn't get audio duration: \(error)")
            return nil
        }
    }
}

/// test view for transcription services
struct TranscriptionTestView: View {
    @StateObject private var tester = TranscriptionTester()
    @State private var selectedResult: TranscriptionResult?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // header
            HStack {
                Text("transcription service test")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("test latest recording") {
                    Task {
                        await tester.testWithLatestRecording()
                    }
                }
                .disabled(tester.isProcessing)
            }
            
            // status
            HStack {
                Text("status:")
                    .foregroundColor(.secondary)
                Text(tester.testStatus)
                    .fontWeight(.medium)
            }
            
            if let error = tester.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            // results
            if !tester.results.isEmpty {
                Divider()
                
                Text("results")
                    .font(.headline)
                
                // comparison table with quality metrics
                VStack(alignment: .leading, spacing: 10) {
                    if let comparison = tester.comparison {
                        ForEach(comparison.metrics, id: \.serviceName) { metric in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    // service name with quality score
                                    VStack(alignment: .leading) {
                                        Text(metric.serviceName)
                                            .fontWeight(.medium)
                                        if let score = metric.qualityScore {
                                            Text("quality: \(Int(score))%")
                                                .font(.caption2)
                                                .foregroundColor(score > 80 ? .green : score > 60 ? .yellow : .red)
                                        }
                                    }
                                    .frame(width: 100, alignment: .leading)
                                    
                                    // processing time
                                    Text("\(String(format: "%.1f", metric.processingTime))s")
                                        .frame(width: 60, alignment: .trailing)
                                        .foregroundColor(.secondary)
                                    
                                    // cost
                                    Text("$\(String(format: "%.4f", metric.cost))")
                                        .frame(width: 80, alignment: .trailing)
                                        .foregroundColor(.secondary)
                                    
                                    // word count
                                    Text("\(metric.wordCount) words")
                                        .frame(width: 100, alignment: .trailing)
                                        .foregroundColor(.secondary)
                                    
                                    // coverage
                                    if let coverage = metric.coveragePercentage {
                                        Text("\(Int(coverage * 100))% coverage")
                                            .frame(width: 100, alignment: .trailing)
                                            .foregroundColor(coverage > 0.9 ? .green : .orange)
                                    }
                                    
                                    Spacer()
                                    
                                    // view button
                                    if let result = tester.results.first(where: { $0.service == metric.serviceName }) {
                                        Button("view") {
                                            selectedResult = result
                                        }
                                        .font(.caption)
                                    }
                                }
                                
                                // show issues if any
                                if let issues = metric.issues {
                                    ForEach(issues, id: \.description) { issue in
                                        HStack {
                                            Circle()
                                                .fill(issue.severity == .critical ? Color.red : 
                                                     issue.severity == .warning ? Color.orange : Color.blue)
                                                .frame(width: 6, height: 6)
                                            Text(issue.description)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.leading, 20)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            
                            Divider()
                        }
                    } else {
                        // fallback to simple display
                        ForEach(tester.results, id: \.id) { result in
                            HStack {
                                Text(result.service)
                                    .frame(width: 100, alignment: .leading)
                                    .fontWeight(.medium)
                                
                                Text("\(String(format: "%.1f", result.processingTime))s")
                                    .frame(width: 60, alignment: .trailing)
                                    .foregroundColor(.secondary)
                                
                                Text("$\(String(format: "%.4f", result.cost))")
                                    .frame(width: 80, alignment: .trailing)
                                    .foregroundColor(.secondary)
                                
                                Text("\(result.transcript.wordCount) words")
                                    .frame(width: 100, alignment: .trailing)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("view") {
                                    selectedResult = result
                                }
                                .font(.caption)
                            }
                            .padding(.vertical, 4)
                            
                            Divider()
                        }
                    }
                }
                
                // selected transcript
                if let selected = selectedResult {
                    Text("\(selected.service) transcript")
                        .font(.headline)
                        .padding(.top)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(selected.transcript.segments, id: \.id) { segment in
                                HStack(alignment: .top) {
                                    Text(segment.speaker.label)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color(hexString: segment.speaker.color))
                                        .frame(width: 80, alignment: .leading)
                                    
                                    Text(segment.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(8)
                    }
                    .frame(maxHeight: 300)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// helper for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}