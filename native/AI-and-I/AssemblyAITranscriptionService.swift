//
//  AssemblyAITranscriptionService.swift
//  AI-and-I
//
//  assembly ai transcription service implementation
//  high accuracy with advanced speaker diarization
//

import Foundation

/// assembly ai transcription service
class AssemblyAITranscriptionService: TranscriptionService {
    
    // MARK: - properties
    
    let serviceName = "assembly"
    private let apiKey: String
    private let userDictionary: UserDictionary
    
    // assembly ai endpoints
    private let uploadURL = "https://api.assemblyai.com/v2/upload"
    private let transcriptURL = "https://api.assemblyai.com/v2/transcript"
    
    // pricing: $0.01 per minute (most expensive but potentially highest quality)
    private let costPerMinute = 0.01
    
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
        
        // step 1: upload audio file
        let uploadedURL = try await uploadAudioFile(audioURL: audioURL)
        
        // step 2: request transcription
        let transcriptID = try await requestTranscription(audioURL: uploadedURL)
        
        // step 3: poll for completion
        let transcriptData = try await pollForCompletion(transcriptID: transcriptID)
        
        // step 4: parse transcript
        let transcript = try parseTranscript(transcriptData)
        
        // calculate cost
        let duration = transcript.duration
        let cost = calculateCost(duration: duration)
        
        // create result
        let processingTime = Date().timeIntervalSince(startTime)
        
        return TranscriptionResult(
            service: serviceName,
            transcript: transcript,
            cost: cost,
            processingTime: processingTime,
            confidence: nil
        )
    }
    
    // MARK: - private methods
    
    private func uploadAudioFile(audioURL: URL) async throws -> String {
        // read audio file
        let audioData = try Data(contentsOf: audioURL)
        
        // create upload request
        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        
        // send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // check response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TranscriptionError.apiError("upload failed")
        }
        
        // parse upload url
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uploadURL = json["upload_url"] as? String else {
            throw TranscriptionError.apiError("no upload url in response")
        }
        
        return uploadURL
    }
    
    private func requestTranscription(audioURL: String) async throws -> String {
        // build request body with custom vocabulary
        var requestBody: [String: Any] = [
            "audio_url": audioURL,
            "speaker_labels": true,
            "language_detection": true,
            "punctuate": true,
            "format_text": true,
            "disfluencies": false
        ]
        
        // add custom vocabulary
        if !userDictionary.names.isEmpty || !userDictionary.companies.isEmpty {
            var wordBoost: [String] = []
            wordBoost.append(contentsOf: userDictionary.names)
            wordBoost.append(contentsOf: userDictionary.companies)
            wordBoost.append(contentsOf: userDictionary.phrases)
            
            if !wordBoost.isEmpty {
                requestBody["word_boost"] = wordBoost
            }
        }
        
        // add custom spelling if we have corrections
        if !userDictionary.corrections.isEmpty {
            var customSpelling: [[String: String]] = []
            for correction in userDictionary.corrections {
                customSpelling.append([
                    "from": [correction.wrong],
                    "to": correction.correct
                ])
            }
            requestBody["custom_spelling"] = customSpelling
        }
        
        // create request
        var request = URLRequest(url: URL(string: transcriptURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // check response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TranscriptionError.apiError("transcription request failed")
        }
        
        // parse transcript id
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transcriptID = json["id"] as? String else {
            throw TranscriptionError.apiError("no transcript id in response")
        }
        
        return transcriptID
    }
    
    private func pollForCompletion(transcriptID: String, maxAttempts: Int = 60) async throws -> [String: Any] {
        let pollURL = "\(transcriptURL)/\(transcriptID)"
        
        for _ in 0..<maxAttempts {
            // create request
            var request = URLRequest(url: URL(string: pollURL)!)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "authorization")
            
            // send request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // check response
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw TranscriptionError.apiError("polling failed")
            }
            
            // parse status
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                throw TranscriptionError.apiError("no status in response")
            }
            
            switch status {
            case "completed":
                return json
            case "error":
                let error = json["error"] as? String ?? "unknown error"
                throw TranscriptionError.apiError("transcription failed: \(error)")
            default:
                // still processing, wait and retry
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
        }
        
        throw TranscriptionError.apiError("transcription timeout")
    }
    
    private func parseTranscript(_ json: [String: Any]) throws -> Transcript {
        var segments: [TranscriptSegment] = []
        
        // get duration
        let audioDuration = (json["audio_duration"] as? Double ?? 0) / 1000 // convert ms to seconds
        
        // parse utterances with speaker labels
        if let utterances = json["utterances"] as? [[String: Any]] {
            for utterance in utterances {
                guard let text = utterance["text"] as? String,
                      let speaker = utterance["speaker"] as? String else { continue }
                
                // map speaker A to @me (primary speaker), others to speaker1, speaker2, etc.
                let speakerLabel: Speaker
                if speaker == "A" {
                    speakerLabel = .me
                } else {
                    // convert B, C, D to speaker1, speaker2, speaker3
                    let speakerNumber = Int(speaker.unicodeScalars.first!.value) - 65 // A=0, B=1, C=2
                    speakerLabel = .other("speaker\(speakerNumber)")
                }
                
                segments.append(TranscriptSegment(
                    speaker: speakerLabel,
                    text: text,
                    timestamp: (utterance["start"] as? Double).map { $0 / 1000 }, // convert ms to seconds
                    confidence: utterance["confidence"] as? Float
                ))
            }
        } else if let text = json["text"] as? String {
            // fallback to non-diarized transcript
            segments.append(TranscriptSegment(
                speaker: .me,
                text: text,
                timestamp: nil,
                confidence: json["confidence"] as? Float
            ))
        }
        
        return Transcript(
            sessionID: UUID().uuidString,
            segments: segments,
            metadata: TranscriptMetadata(
                recordingDate: Date(),
                audioFileURL: "",
                mixingMethod: .mixed,
                deviceInfo: "ai&i native"
            ),
            duration: audioDuration
        )
    }
    
    // MARK: - configuration
    
    static func createFromEnvironment(userDictionary: UserDictionary = UserDictionary()) -> AssemblyAITranscriptionService? {
        // hardcoded for now, will move to secure storage
        let apiKey = "789a50c24ad24f29beb085339c29bce2"
        
        return AssemblyAITranscriptionService(apiKey: apiKey, userDictionary: userDictionary)
    }
}