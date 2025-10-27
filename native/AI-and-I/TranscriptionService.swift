//
//  TranscriptionService.swift
//  AI-and-I
//
//  abstraction layer for multiple transcription services
//  enables parallel processing and easy service switching
//

import Foundation

// MARK: - ffmpeg discovery helper

private func locateFFmpegExecutable() -> URL? {
    let fileManager = FileManager.default
    var candidates: [String] = []
    var seen = Set<String>()

    func appendCandidate(_ path: String) {
        guard !path.isEmpty, !seen.contains(path) else { return }
        seen.insert(path)
        candidates.append(path)
    }

    // explicit override via environment (binary or directory)
    if let override = ProcessInfo.processInfo.environment["FFMPEG_PATH"] {
        appendCandidate(override)
    }

    // common install locations
    ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].forEach { appendCandidate($0) }

    // search PATH entries
    if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
        pathEnv.split(separator: ":").map(String.init).forEach { appendCandidate($0) }
    }

    for candidate in candidates {
        // handle override that points directly to the ffmpeg binary
        if fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        let binaryPath = (candidate as NSString).appendingPathComponent("ffmpeg")
        if fileManager.isExecutableFile(atPath: binaryPath) {
            return URL(fileURLWithPath: binaryPath)
        }
    }

    return nil
}

private func determineBitrate(for wavURL: URL) -> String {
    let defaultBitrate = "128k"
    guard
        let attributes = try? FileManager.default.attributesOfItem(atPath: wavURL.path),
        let fileSize = attributes[.size] as? NSNumber
    else {
        return defaultBitrate
    }

    let sizeMB = fileSize.doubleValue / (1024 * 1024)

    if sizeMB >= 600 { // roughly ≥60 minutes at 44.1khz 16-bit stereo
        return "64k"
    } else if sizeMB >= 300 {
        return "96k"
    } else {
        return defaultBitrate
    }
}

// MARK: - transcript formatting + context helpers

enum TranscriptFormat {
    /// condensed instructions derived from `shared/transcript-format-sample.md`
    static let instructions: String = """
    FORMAT EXPECTATIONS (match ai&i sample):
    - Begin with "MEETING TRANSCRIPT" and an underline of '=' characters on the next line.
    - Provide a concise `TITLE: ...` line (4-7 words) before the transcript body.
    - Every spoken line uses `@speaker: [emotion-intensity emotion] [topic-tags] text`.
      * Emotion intensity must be one of: mildly, somewhat, very, extremely (or omit intensity for neutral).
      * Include up to 3 lowercase, hyphenated topic tags per line (e.g., [payment-flow] [user-feedback]).
    - Capture acoustic cues in parentheses, e.g., `(typing)`, `(door opens)`; place them on their own line when best.
    - Capture meeting or technical events in square brackets, e.g., `[audio cutting out]`, `[multiple people talking]`.
    - Use `@me` for the recorder's local mic, `@me-2` etc. for additional local voices, `@speaker1`, `@speaker2`... for remote/system participants, and `@system` for non-human/system playback.
    - Preserve code-switching and multilingual phrases exactly as spoken; add clarifying English in brackets only when helpful.
    - Include personal or casual conversation using the same format—do not omit or editorialize.
    - End with a `---` separator followed by a `CONSISTENCY CHECK APPLIED:` block that lists the key normalization steps performed.
    """
}

struct TranscriptionRequestContext {
    var sessionID: String?
    var duration: TimeInterval?
    var languages: [String]
    var expectedSpeakers: Int?
    var microphoneDevices: [String]
    var systemDevices: [String]
    var deviceNotes: [String]
    var userDictionary: UserDictionary
    var formatInstructions: String

    init(
        sessionID: String? = nil,
        duration: TimeInterval? = nil,
        languages: [String] = TranscriptionRequestContext.defaultLanguageHints(),
        expectedSpeakers: Int? = nil,
        microphoneDevices: [String] = [],
        systemDevices: [String] = [],
        deviceNotes: [String] = [],
        userDictionary: UserDictionary = UserDictionary(),
        formatInstructions: String = TranscriptFormat.instructions
    ) {
        self.sessionID = sessionID
        self.duration = duration
        self.languages = languages
        self.expectedSpeakers = expectedSpeakers
        self.microphoneDevices = microphoneDevices
        self.systemDevices = systemDevices
        self.deviceNotes = deviceNotes
        self.userDictionary = userDictionary
        self.formatInstructions = formatInstructions
    }

    static func defaultLanguageHints() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        if let rawHints = environment["AI_AND_I_LANGUAGE_HINTS"], !rawHints.isEmpty {
            return rawHints
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // default hints target common english+hindi+spanish mixing for ai&i sessions
        return ["en", "en-IN", "hi", "es"]
    }
}

struct CanonicalTranscriptStore: Codable {
    static let currentVersion = 1

    let version: Int
    let sessionID: String
    let createdAt: Date
    let duration: TimeInterval?
    let bestService: String
    let services: [String: TranscriptionResult]
}

// MARK: - core protocol

/// defines the interface all transcription services must implement
protocol TranscriptionService {
    /// service identifier for ui and logging
    var serviceName: String { get }
    
    /// transcribe audio file to text with speaker attribution
    func transcribe(audioURL: URL, context: TranscriptionRequestContext) async throws -> TranscriptionResult
    
    /// calculate cost for given audio duration
    func calculateCost(duration: TimeInterval) -> Double
    
    /// check if service is available and configured
    func isAvailable() -> Bool
}

// MARK: - data models

/// result from a transcription service
struct TranscriptionResult: Codable {
    var id = UUID()
    let service: String
    let transcript: Transcript
    let cost: Double
    var processingTime: TimeInterval  // changed to var
    let confidence: Float?
    let createdAt = Date()
}

/// main transcript structure
struct Transcript: Codable, Identifiable {
    var id = UUID()
    let sessionID: String
    let segments: [TranscriptSegment]
    let metadata: TranscriptMetadata
    let duration: TimeInterval
    let title: String?  // optional ai-generated title
    
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
    var id = UUID()
    let speaker: Speaker
    let text: String
    let timestamp: TimeInterval?
    let confidence: Float?
}

/// speaker identification
enum Speaker: Codable, Equatable, Hashable {
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

    var isEmpty: Bool {
        corrections.isEmpty && names.isEmpty && companies.isEmpty && phrases.isEmpty
    }
    
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

    static func loadFromDisk() -> UserDictionary {
        let fileManager = FileManager.default
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return UserDictionary()
        }

        let storageDirectory = documentsDirectory.appendingPathComponent("ai-and-i")
        let fileURL = storageDirectory.appendingPathComponent("user-dictionary.json")

        guard let data = try? Data(contentsOf: fileURL) else {
            return UserDictionary()
        }

        let decoder = JSONDecoder()
        if let dictionary = try? decoder.decode(UserDictionary.self, from: data) {
            return dictionary
        }

        return UserDictionary()
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
    func transcribeWithAllServices(
        audioURL: URL,
        context: TranscriptionRequestContext? = nil
    ) async {
        isProcessing = true
        results = []
        bestResult = nil
        errorMessage = nil

        let requestContext: TranscriptionRequestContext = {
            if let context {
                var merged = context
                if merged.userDictionary.isEmpty, !userDictionary.isEmpty {
                    merged.userDictionary = userDictionary
                }
                return merged
            } else {
                return TranscriptionRequestContext(userDictionary: userDictionary)
            }
        }()
        
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
                        let result = try await service.transcribe(audioURL: mp3URL, context: requestContext)
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
    func convertToMP3(_ wavURL: URL) async throws -> URL {
        let mp3URL = wavURL.deletingPathExtension().appendingPathExtension("mp3")

        // if already mp3, return as is
        if wavURL.pathExtension.lowercased() == "mp3" {
            return wavURL
        }

        guard let ffmpegURL = locateFFmpegExecutable() else {
            throw TranscriptionError.ffmpegNotFound
        }

        // clean up stale output if present
        if FileManager.default.fileExists(atPath: mp3URL.path) {
            try? FileManager.default.removeItem(at: mp3URL)
        }

        let bitrate = determineBitrate(for: wavURL)

        let maxAttempts = 2
        var attempt = 0
        var lastStatus: Int32 = 0
        var lastMessage = ""

        while attempt < maxAttempts {
            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = [
                "-i", wavURL.path,
                "-b:a", bitrate,
                "-ar", "16000",
                "-ac", "1",
                "-y",
                mp3URL.path
            ]

            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = stdoutPipe

            do {
                try process.run()
            } catch {
                throw TranscriptionError.conversionFailed(status: -1, message: error.localizedDescription)
            }

            process.waitUntilExit()

            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                lastMessage = message
            }
            lastStatus = process.terminationStatus

            if lastStatus == 0 {
                return mp3URL
            }

            attempt += 1

            // remove partial output before retrying
            if FileManager.default.fileExists(atPath: mp3URL.path) {
                try? FileManager.default.removeItem(at: mp3URL)
            }

            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            }
        }

        throw TranscriptionError.conversionFailed(status: lastStatus, message: lastMessage)
    }
}

// MARK: - errors

enum TranscriptionError: LocalizedError {
    case serviceUnavailable
    case apiKeyMissing
    case fileTooLarge
    case conversionFailed(status: Int32, message: String)
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
        case .conversionFailed(let status, let message):
            if message.isEmpty {
                return "failed to convert audio format (exit \(status))"
            }
            return "failed to convert audio format (exit \(status)): \(message)"
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

/// tracks metrics for admin comparison with quality analysis
struct ServiceMetrics: Codable {
    let serviceName: String
    let processingTime: TimeInterval
    let cost: Double
    let wordCount: Int
    let confidence: Float?
    let timestamp: Date
    
    // quality metrics (populated during comparison)
    var coveragePercentage: Double?      // % of audio transcribed
    var missingSegments: [MissingSegment]? // gaps in transcription
    var qualityScore: Double?            // calculated quality score (0-100)
    var issues: [QualityIssue]?          // identified problems
}

/// represents a gap in the transcription
struct MissingSegment: Codable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let duration: TimeInterval
    let description: String  // e.g., "missed last 15 seconds"
}

/// identified quality issue
struct QualityIssue: Codable {
    let type: IssueType
    let severity: Severity
    let description: String
    
    enum IssueType: String, Codable {
        case incompleteCoverage = "incomplete_coverage"
        case missingContent = "missing_content"  
        case lowWordCount = "low_word_count"
        case lowConfidence = "low_confidence"
    }
    
    enum Severity: String, Codable {
        case info = "info"
        case warning = "warning"
        case critical = "critical"
    }
}

/// comparison view model for admin mode with quality analysis
@MainActor
class TranscriptionComparison: ObservableObject {
    @Published var metrics: [ServiceMetrics] = []
    @Published var selectedService: String = ""
    @Published var showDifferences = false
    @Published var qualityIssuesFound = false
    
    func compareResults(_ results: [TranscriptionResult], audioDuration: TimeInterval? = nil) {
        // create basic metrics
        var allMetrics = results.map { result in
            ServiceMetrics(
                serviceName: result.service,
                processingTime: result.processingTime,
                cost: result.cost,
                wordCount: result.transcript.wordCount,
                confidence: result.confidence,
                timestamp: result.createdAt,
                coveragePercentage: nil,
                missingSegments: nil,
                qualityScore: nil,
                issues: nil
            )
        }
        
        // analyze quality if we have audio duration
        if let duration = audioDuration {
            analyzeQuality(&allMetrics, results: results, audioDuration: duration)
        }
        
        // sort by quality score (if available) or processing time
        allMetrics.sort { 
            if let score1 = $0.qualityScore, let score2 = $1.qualityScore {
                return score1 > score2
            }
            return $0.processingTime < $1.processingTime
        }
        
        self.metrics = allMetrics
        
        // select best service (highest quality or fastest)
        if let best = allMetrics.first {
            selectedService = best.serviceName
        }
        
        // check if any critical issues found
        qualityIssuesFound = allMetrics.contains { metric in
            metric.issues?.contains { $0.severity == .critical } ?? false
        }
    }
    
    private func analyzeQuality(_ metrics: inout [ServiceMetrics], results: [TranscriptionResult], audioDuration: TimeInterval) {
        // calculate median word count for comparison
        let wordCounts = metrics.map { $0.wordCount }.sorted()
        let medianWordCount = wordCounts.isEmpty ? 0 : wordCounts[wordCounts.count / 2]
        
        // analyze each service
        for i in 0..<metrics.count {
            let result = results[i]
            var issues: [QualityIssue] = []
            var missingSegments: [MissingSegment] = []
            
            // check coverage using timestamps
            let segments = result.transcript.segments
            let firstTime = segments.compactMap { $0.timestamp }.min() ?? 0
            let lastTime = segments.compactMap { $0.timestamp }.max() ?? audioDuration
            let transcribedDuration = lastTime - firstTime
            let coverage = audioDuration > 0 ? transcribedDuration / audioDuration : 1.0
            
            metrics[i].coveragePercentage = coverage
            
            // check for missing end content (like deepgram missing 30-45s)
            if audioDuration - lastTime > 5.0 {
                let missingDuration = audioDuration - lastTime
                missingSegments.append(MissingSegment(
                    startTime: lastTime,
                    endTime: audioDuration,
                    duration: missingDuration,
                    description: "missed last \(Int(missingDuration)) seconds"
                ))
                
                issues.append(QualityIssue(
                    type: .missingContent,
                    severity: missingDuration > 10 ? .critical : .warning,
                    description: "\(result.service) missed last \(Int(missingDuration)) seconds of audio"
                ))
            }
            
            // check for missing beginning
            if firstTime > 5.0 {
                missingSegments.append(MissingSegment(
                    startTime: 0,
                    endTime: firstTime,
                    duration: firstTime,
                    description: "missed first \(Int(firstTime)) seconds"
                ))
                
                issues.append(QualityIssue(
                    type: .missingContent,
                    severity: .warning,
                    description: "\(result.service) missed first \(Int(firstTime)) seconds"
                ))
            }
            
            // check for low word count compared to median
            let wordDeviation = medianWordCount > 0 ? 
                Double(abs(metrics[i].wordCount - medianWordCount)) / Double(medianWordCount) : 0
            
            if wordDeviation > 0.3 {  // more than 30% deviation
                issues.append(QualityIssue(
                    type: .lowWordCount,
                    severity: wordDeviation > 0.5 ? .critical : .warning,
                    description: "\(result.service) has \(Int(wordDeviation * 100))% word count deviation"
                ))
            }
            
            // check coverage percentage
            if coverage < 0.9 {
                issues.append(QualityIssue(
                    type: .incompleteCoverage,
                    severity: coverage < 0.7 ? .critical : .warning,
                    description: "\(result.service) only covered \(Int(coverage * 100))% of audio"
                ))
            }
            
            // calculate quality score
            var score = 100.0
            score -= (1.0 - coverage) * 40  // coverage penalty
            score -= min(wordDeviation * 20, 20)  // word count penalty
            score -= Double(missingSegments.count) * 10  // missing segments penalty
            
            metrics[i].qualityScore = max(0, min(100, score))
            metrics[i].missingSegments = missingSegments.isEmpty ? nil : missingSegments
            metrics[i].issues = issues.isEmpty ? nil : issues
        }
    }
}
