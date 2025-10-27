//
//  GeminiTranscriptionService.swift
//  AI-and-I
//
//  gemini 2.5 flash transcription service implementation
//  leverages google's latest ai model for accurate transcription
//

import Foundation

/// gemini transcription service using google ai
class GeminiTranscriptionService: TranscriptionService {
    
    // MARK: - properties
    
    let serviceName = "gemini"
    private let apiKey: String
    private let userDictionary: UserDictionary
    
    // gemini api endpoint
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-exp:generateContent"
    
    // pricing: $0.002 per minute of audio
    private let costPerMinute = 0.002
    
    // MARK: - initialization
    
    init(apiKey: String, userDictionary: UserDictionary = UserDictionary()) {
        self.apiKey = apiKey
        self.userDictionary = userDictionary
    }
    
    // MARK: - TranscriptionService protocol
    
    func isAvailable() -> Bool {
        return !apiKey.isEmpty
    }
    
    func calculateCost(duration: TimeInterval) -> Double {
        let minutes = duration / 60.0
        return minutes * costPerMinute
    }
    
    func transcribe(audioURL: URL, context: TranscriptionRequestContext) async throws -> TranscriptionResult {
        guard isAvailable() else {
            throw TranscriptionError.apiKeyMissing
        }

        let startTime = Date()

        let effectiveDictionary = context.userDictionary.isEmpty ? userDictionary : context.userDictionary

        // read audio file
        let audioData = try Data(contentsOf: audioURL)

        // check file size (gemini limit is 20mb)
        let maxSize = 20 * 1024 * 1024 // 20mb
        guard audioData.count <= maxSize else {
            throw TranscriptionError.fileTooLarge
        }

        // prepare request
        let request = try buildRequest(audioData: audioData, context: context, dictionary: effectiveDictionary)
        
        // send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // check response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TranscriptionError.apiError("http \(statusCode)")
        }
        
        // parse response
        let transcript = try parseResponse(data, context: context)

        // calculate cost based on audio duration
        let duration = context.duration ?? getAudioDuration(audioURL: audioURL)
        let cost = calculateCost(duration: duration)
        
        // create result
        let processingTime = Date().timeIntervalSince(startTime)
        
        return TranscriptionResult(
            service: serviceName,
            transcript: transcript,
            cost: cost,
            processingTime: processingTime,
            confidence: nil // gemini doesn't provide confidence scores
        )
    }
    
    // MARK: - private methods
    
    private func buildRequest(
        audioData: Data,
        context: TranscriptionRequestContext,
        dictionary: UserDictionary
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let prompt = buildPrompt(context: context, dictionary: dictionary)

        // build request body
        let requestBody: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    [
                        "inline_data": [
                            "mime_type": detectMimeType(audioData: audioData),
                            "data": audioData.base64EncodedString()
                        ]
                    ]
                ]
            ]],
            "generationConfig": [
                "temperature": 0.1,      // low temperature for accuracy
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 32768,
                "responseMimeType": "text/plain"
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        return request
    }

    private func buildPrompt(context: TranscriptionRequestContext, dictionary: UserDictionary) -> String {
        var metadataLines: [String] = []

        if let sessionID = context.sessionID {
            metadataLines.append("session id: \(sessionID)")
        }

        if let duration = context.duration {
            let minutes = duration / 60.0
            metadataLines.append(String(format: "approx duration: %.1f minutes", minutes))
        }

        let languages = context.languages
        if !languages.isEmpty {
            metadataLines.append("language hints: \(languages.joined(separator: ", "))")
        }

        if let expected = context.expectedSpeakers {
            metadataLines.append("expected participants: \(expected) (recorder + remote)")
        }

        if !context.microphoneDevices.isEmpty {
            metadataLines.append("microphone devices: \(context.microphoneDevices.joined(separator: ", "))")
        }

        if !context.systemDevices.isEmpty {
            metadataLines.append("system routes: \(context.systemDevices.joined(separator: ", "))")
        }

        if !context.deviceNotes.isEmpty {
            metadataLines.append("device notes: \(context.deviceNotes.joined(separator: " | "))")
        }

        if metadataLines.isEmpty {
            metadataLines.append("no additional session metadata provided")
        }

        let contextBlock = metadataLines.map { "- \($0)" }.joined(separator: "\n")

        var prompt = """
        You are the ai&i meeting transcription engine. Convert the supplied audio into a transcript that strictly follows the ai&i transcript format.

        FORMAT RULES:
        \(context.formatInstructions)

        SESSION CONTEXT:
        \(contextBlock)

        OUTPUT REQUIREMENTS:
        - Preserve speaker diarization faithfully; use @me for the recorder, @speaker1/@speaker2/etc. for remote participants, and @system for non-human/system playback.
        - Capture acoustic cues in parentheses and meeting/technical events in square brackets exactly where they occur.
        - Support code-switching across all hinted languages without translating unless adding a short clarification in brackets is essential.
        - Keep topic tags consistent; reuse existing tags when the conversation stays on the same subject and cap at three tags per line.
        - If wording is unclear, include your best guess with a trailing "(?)" but do not omit the line.
        - End with a `---` separator and a `CONSISTENCY CHECK APPLIED:` section summarizing the key normalization steps you followed (topics, naming, intensity, etc.).
        """

        if !dictionary.promptInjection.isEmpty {
            prompt += "\n\nUSER DICTIONARY HINTS:\n\(dictionary.promptInjection)"
        }

        return prompt
    }
    
    private func parseResponse(_ data: Data, context: TranscriptionRequestContext) throws -> Transcript {
        // parse gemini response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw TranscriptionError.apiError("invalid response format")
        }
        
        // parse transcript text into segments and extract title
        let (title, segments) = parseTranscriptText(text)

        // create transcript
        return Transcript(
            sessionID: context.sessionID ?? UUID().uuidString,
            segments: segments,
            metadata: TranscriptMetadata(
                recordingDate: Date(),
                audioFileURL: "",
                mixingMethod: .mixed,
                deviceInfo: context.deviceNotes.isEmpty
                    ? "ai&i native"
                    : context.deviceNotes.joined(separator: " | ")
            ),
            duration: context.duration ?? 0,
            title: title
        )
    }
    
    private func parseTranscriptText(_ text: String) -> (title: String?, segments: [TranscriptSegment]) {
        var segments: [TranscriptSegment] = []
        var title: String?
        let lines = text.components(separatedBy: .newlines)

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.uppercased() == "MEETING TRANSCRIPT" {
                continue
            }

            if trimmed.allSatisfy({ $0 == "=" }) {
                continue
            }

            if trimmed.hasPrefix("TITLE:") {
                title = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if trimmed == "---" {
                segments.append(TranscriptSegment(
                    speaker: .other("system"),
                    text: trimmed,
                    timestamp: nil,
                    confidence: nil
                ))
                continue
            }

            if let colonIndex = trimmed.firstIndex(of: ":"), trimmed.first == "@" {
                let speakerToken = trimmed[..<colonIndex]
                let textStart = trimmed.index(after: colonIndex)
                let textPart = String(trimmed[textStart...]).trimmingCharacters(in: .whitespaces)

                let rawSpeaker = speakerToken.dropFirst() // remove '@'
                let speaker: Speaker = rawSpeaker.lowercased() == "me"
                    ? .me
                    : .other(String(rawSpeaker))

                segments.append(TranscriptSegment(
                    speaker: speaker,
                    text: textPart,
                    timestamp: nil,
                    confidence: nil
                ))
            } else {
                segments.append(TranscriptSegment(
                    speaker: .other("system"),
                    text: trimmed,
                    timestamp: nil,
                    confidence: nil
                ))
            }
        }

        return (title, segments)
    }
    
    private func detectMimeType(audioData: Data) -> String {
        // check for mp3 signature
        if audioData.count >= 3 {
            let firstBytes = audioData.prefix(3)
            if firstBytes.elementsEqual([0xFF, 0xFB, 0x90]) || // mp3 with ID3
               firstBytes.elementsEqual([0x49, 0x44, 0x33]) {   // ID3 tag
                return "audio/mp3"
            }
        }
        
        // check for wav signature
        if audioData.count >= 4 {
            let firstBytes = audioData.prefix(4)
            if firstBytes.elementsEqual([0x52, 0x49, 0x46, 0x46]) { // "RIFF"
                return "audio/wav"
            }
        }
        
        // default to mp3
        return "audio/mp3"
    }
    
    private func getAudioDuration(audioURL: URL) -> TimeInterval {
        // for now, estimate based on file size
        // mp3 at 128kbps = ~1mb per minute
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
            if let fileSize = attributes[.size] as? Int64 {
                let sizeInMB = Double(fileSize) / (1024 * 1024)
                return sizeInMB * 60 // rough estimate
            }
        } catch {
            print("couldn't get file size: \(error)")
        }
        
        // default to 1 minute if we can't determine
        return 60
    }
}

// MARK: - configuration

extension GeminiTranscriptionService {
    /// create service from environment or stored api key
    static func createFromEnvironment(userDictionary: UserDictionary = UserDictionary()) -> GeminiTranscriptionService? {
        let environment = ProcessInfo.processInfo.environment
        let rawKey = environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey = rawKey, !apiKey.isEmpty else {
            return nil
        }
        
        return GeminiTranscriptionService(apiKey: apiKey, userDictionary: userDictionary)
    }
}
