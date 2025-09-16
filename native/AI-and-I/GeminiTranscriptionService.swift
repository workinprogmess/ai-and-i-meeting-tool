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
    
    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        guard isAvailable() else {
            throw TranscriptionError.apiKeyMissing
        }
        
        let startTime = Date()
        
        // read audio file
        let audioData = try Data(contentsOf: audioURL)
        
        // check file size (gemini limit is 20mb)
        let maxSize = 20 * 1024 * 1024 // 20mb
        guard audioData.count <= maxSize else {
            throw TranscriptionError.fileTooLarge
        }
        
        // prepare request
        let request = try buildRequest(audioData: audioData)
        
        // send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // check response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TranscriptionError.apiError("http \(statusCode)")
        }
        
        // parse response
        let transcript = try parseResponse(data)
        
        // calculate cost based on audio duration
        let duration = getAudioDuration(audioURL: audioURL)
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
    
    private func buildRequest(audioData: Data) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // build prompt with user dictionary
        var prompt = """
        transcribe this audio recording into a conversation format.
        
        first, provide a title (4-7 words) that captures the essence of the meeting.
        format as: TITLE: [your title]
        
        then provide the transcript.
        format each line as:
        @speaker: what they said
        
        use @me for the person who is recording (the main speaker)
        use @speaker1, @speaker2, etc. for other participants
        
        focus on accuracy and natural conversation flow.
        do not include timestamps.
        transcribe any non-english phrases as spoken, with english translation in brackets if helpful.
        """
        
        // add user dictionary if available
        if !userDictionary.promptInjection.isEmpty {
            prompt += "\n\n\(userDictionary.promptInjection)"
        }
        
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
    
    private func parseResponse(_ data: Data) throws -> Transcript {
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
            sessionID: UUID().uuidString,
            segments: segments,
            metadata: TranscriptMetadata(
                recordingDate: Date(),
                audioFileURL: "",
                mixingMethod: .mixed,
                deviceInfo: "ai&i native"
            ),
            duration: 0, // will be set by coordinator
            title: title
        )
    }
    
    private func parseTranscriptText(_ text: String) -> (title: String?, segments: [TranscriptSegment]) {
        var segments: [TranscriptSegment] = []
        var title: String?
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            // extract title if present
            if trimmed.hasPrefix("TITLE:") {
                title = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            
            // parse speaker and text
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let speakerPart = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let textPart = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                
                // determine speaker
                let speaker: Speaker
                if speakerPart.lowercased() == "@me" || speakerPart.lowercased() == "me" {
                    speaker = .me
                } else if speakerPart.hasPrefix("@") {
                    let name = String(speakerPart.dropFirst())
                    speaker = .other(name)
                } else {
                    speaker = .other(speakerPart)
                }
                
                segments.append(TranscriptSegment(
                    speaker: speaker,
                    text: textPart,
                    timestamp: nil,
                    confidence: nil
                ))
            } else {
                // no speaker label, assume continuation of previous
                if let lastSegment = segments.last {
                    segments[segments.count - 1] = TranscriptSegment(
                        speaker: lastSegment.speaker,
                        text: lastSegment.text + " " + trimmed,
                        timestamp: nil,
                        confidence: nil
                    )
                } else {
                    // first segment without speaker, assume @me
                    segments.append(TranscriptSegment(
                        speaker: .me,
                        text: trimmed,
                        timestamp: nil,
                        confidence: nil
                    ))
                }
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
        // hardcoded for now, will move to secure storage
        let apiKey = "AIzaSyD2nK_WzdVoXvxVbnu9lMhm2dO6MZ5P-FA"
        
        return GeminiTranscriptionService(apiKey: apiKey, userDictionary: userDictionary)
    }
}