//
//  TranscriptionService.swift
//  AI-and-I
//
//  abstraction layer for multiple transcription services
//  enables parallel processing and easy service switching
//

import Foundation

// MARK: - core protocol

/// defines the interface all transcription services must implement
protocol TranscriptionService {
    /// service identifier for ui and logging
    var serviceName: String { get }
    
    /// transcribe audio file to text with speaker attribution
    func transcribe(audioURL: URL) async throws -> TranscriptionResult
    
    /// calculate cost for given audio duration
    func calculateCost(duration: TimeInterval) -> Double
    
    /// check if service is available and configured
    func isAvailable() -> Bool
}

// MARK: - data models

/// result from a transcription service
struct TranscriptionResult: Codable {
    let id = UUID()
    let service: String
    let transcript: Transcript
    let cost: Double
    let processingTime: TimeInterval
    let confidence: Float?
    let createdAt = Date()
}

/// main transcript structure
struct Transcript: Codable, Identifiable {
    let id = UUID()
    let sessionID: String
    let segments: [TranscriptSegment]
    let metadata: TranscriptMetadata
    let duration: TimeInterval
    
    /// total word count
    var wordCount: Int {
        segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }
    
    /// full text without speaker labels
    var fullText: String {
        segments.map { $0.text }.joined(separator: " ")
    }
}

/// individual segment of transcript
struct TranscriptSegment: Codable, Identifiable {
    let id = UUID()
    let speaker: Speaker
    let text: String
    let timestamp: TimeInterval?
    let confidence: Float?
}

/// speaker identification
enum Speaker: Codable {
    case me
    case other(String) // "speaker1", "speaker2", etc.
    
    var label: String {
        switch self {
        case .me:
            return "@me"
        case .other(let name):
            return "@\(name)"
        }
    }
    
    var color: String {
        switch self {
        case .me:
            return "#2563eb" // blue
        case .other:
            return "#059669" // green
        }
    }
}

/// transcript metadata
struct TranscriptMetadata: Codable {
    let recordingDate: Date
    let audioFileURL: String
    let mixingMethod: MixingMethod
    let deviceInfo: String
}

/// how the audio was mixed
enum MixingMethod: String, Codable {
    case mixed = "mixed"        // normal mixing succeeded
    case reconstructed = "reconstructed" // fallback, transcribed separately
}

// MARK: - user corrections

/// tracks user vocabulary and corrections
struct UserDictionary: Codable {
    var corrections: [UserCorrection] = []
    var names: Set<String> = []
    var companies: Set<String> = []
    var phrases: Set<String> = []
    
    /// get prompt injection for ai services
    var promptInjection: String {
        var parts: [String] = []
        
        if !names.isEmpty {
            parts.append("names: \(names.joined(separator: ", "))")
        }
        
        if !companies.isEmpty {
            parts.append("companies: \(companies.joined(separator: ", "))")
        }
        
        if !phrases.isEmpty {
            parts.append("common phrases: \(phrases.joined(separator: ", "))")
        }
        
        if !corrections.isEmpty {
            let correctionList = corrections.map { "'\($0.wrong)' should be '\($0.correct)'" }
            parts.append("corrections: \(correctionList.joined(separator: ", "))")
        }
        
        if parts.isEmpty {
            return ""
        }
        
        return """
        note: user vocabulary includes:
        \(parts.joined(separator: "\n"))
        """
    }
    
    /// add a new correction
    mutating func addCorrection(wrong: String, correct: String, context: String? = nil) {
        // remove any existing correction for the same wrong word
        corrections.removeAll { $0.wrong.lowercased() == wrong.lowercased() }
        
        // add new correction
        corrections.append(UserCorrection(
            wrong: wrong,
            correct: correct,
            context: context,
            addedAt: Date()
        ))
        
        // also add correct word to appropriate category
        if correct.capitalized == correct {
            names.insert(correct)
        } else {
            phrases.insert(correct)
        }
    }
}

/// individual correction entry
struct UserCorrection: Codable {
    let wrong: String      // what ai heard
    let correct: String    // what user meant
    let context: String?   // optional surrounding text
    let addedAt: Date
}

// MARK: - service coordinator

/// manages parallel transcription across multiple services
@MainActor
class TranscriptionCoordinator: ObservableObject {
    @Published var isProcessing = false
    @Published var results: [TranscriptionResult] = []
    @Published var bestResult: TranscriptionResult?
    @Published var errorMessage: String?
    
    private let services: [TranscriptionService]
    private let userDictionary: UserDictionary
    
    init(services: [TranscriptionService], userDictionary: UserDictionary = UserDictionary()) {
        self.services = services
        self.userDictionary = userDictionary
    }
    
    /// transcribe with all available services in parallel
    func transcribeWithAllServices(audioURL: URL) async {
        isProcessing = true
        results = []
        bestResult = nil
        errorMessage = nil
        
        // convert to mp3 first for smaller file size
        let mp3URL: URL
        do {
            mp3URL = try await convertToMP3(audioURL)
        } catch {
            errorMessage = "failed to convert audio: \(error.localizedDescription)"
            isProcessing = false
            return
        }
        
        // run all services in parallel
        await withTaskGroup(of: TranscriptionResult?.self) { group in
            for service in services where service.isAvailable() {
                group.addTask {
                    do {
                        let startTime = Date()
                        let result = try await service.transcribe(audioURL: mp3URL)
                        let processingTime = Date().timeIntervalSince(startTime)
                        
                        var updatedResult = result
                        updatedResult.processingTime = processingTime
                        
                        return updatedResult
                    } catch {
                        print("❌ \(service.serviceName) failed: \(error)")
                        return nil
                    }
                }
            }
            
            // collect results as they complete
            for await result in group {
                if let result = result {
                    await MainActor.run {
                        self.results.append(result)
                        
                        // update best result (fastest or highest confidence)
                        if self.bestResult == nil {
                            self.bestResult = result
                        }
                    }
                }
            }
        }
        
        isProcessing = false
        
        // if no results, set error
        if results.isEmpty {
            errorMessage = "all transcription services failed"
        }
    }
    
    /// convert wav to mp3 for smaller file size
    private func convertToMP3(_ wavURL: URL) async throws -> URL {
        let mp3URL = wavURL.deletingPathExtension().appendingPathExtension("mp3")
        
        // if already mp3, return as is
        if wavURL.pathExtension.lowercased() == "mp3" {
            return wavURL
        }
        
        // check if ffmpeg exists
        let ffmpegPath = "/usr/local/bin/ffmpeg"
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            throw TranscriptionError.ffmpegNotFound
        }
        
        // run ffmpeg conversion
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", wavURL.path,
            "-b:a", "128k",     // 128kbps bitrate
            "-ar", "16000",     // 16khz sample rate (optimal for speech)
            "-ac", "1",         // mono
            "-y",               // overwrite if exists
            mp3URL.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw TranscriptionError.conversionFailed
        }
        
        return mp3URL
    }
}

// MARK: - errors

enum TranscriptionError: LocalizedError {
    case serviceUnavailable
    case apiKeyMissing
    case fileTooLarge
    case conversionFailed
    case ffmpegNotFound
    case networkError(String)
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "transcription service is not available"
        case .apiKeyMissing:
            return "api key not configured"
        case .fileTooLarge:
            return "audio file exceeds size limit"
        case .conversionFailed:
            return "failed to convert audio format"
        case .ffmpegNotFound:
            return "ffmpeg not installed"
        case .networkError(let message):
            return "network error: \(message)"
        case .apiError(let message):
            return "api error: \(message)"
        }
    }
}

// MARK: - admin mode support

/// tracks metrics for admin comparison
struct ServiceMetrics: Codable {
    let serviceName: String
    let processingTime: TimeInterval
    let cost: Double
    let wordCount: Int
    let confidence: Float?
    let timestamp: Date
}

/// comparison view model for admin mode
@MainActor
class TranscriptionComparison: ObservableObject {
    @Published var metrics: [ServiceMetrics] = []
    @Published var selectedService: String = ""
    @Published var showDifferences = false
    
    func compareResults(_ results: [TranscriptionResult]) {
        metrics = results.map { result in
            ServiceMetrics(
                serviceName: result.service,
                processingTime: result.processingTime,
                cost: result.cost,
                wordCount: result.transcript.wordCount,
                confidence: result.confidence,
                timestamp: result.createdAt
            )
        }
        
        // select fastest by default
        if let fastest = metrics.min(by: { $0.processingTime < $1.processingTime }) {
            selectedService = fastest.serviceName
        }
    }
}