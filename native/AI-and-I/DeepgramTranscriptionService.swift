//
//  DeepgramTranscriptionService.swift
//  AI-and-I
//
//  deepgram nova-2 transcription service implementation
//  industry-leading accuracy with speaker diarization
//

import Foundation

/// deepgram transcription service
class DeepgramTranscriptionService: TranscriptionService {
    
    // MARK: - properties
    
    let serviceName = "deepgram"
    private let apiKey: String
    private let userDictionary: UserDictionary
    
    // deepgram api endpoint
    private let baseURL = "https://api.deepgram.com/v1/listen"
    
    // pricing: $0.0043 per minute
    private let costPerMinute = 0.0043
    
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
        
        // build url with parameters
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "utterances", value: "true")
        ]
        
        // add custom vocabulary if available
        if !userDictionary.names.isEmpty || !userDictionary.companies.isEmpty {
            let keywords = Array(userDictionary.names) + Array(userDictionary.companies)
            if !keywords.isEmpty {
                let keywordsParam = keywords.map { "\($0):2" }.joined(separator: ",")
                components.queryItems?.append(URLQueryItem(name: "keywords", value: keywordsParam))
            }
        }
        
        // create request
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(detectContentType(audioURL: audioURL), forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        
        // send request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // check response
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TranscriptionError.apiError("deepgram http \(statusCode)")
        }
        
        // parse response
        let transcript = try parseResponse(data)
        
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
    
    private func detectContentType(audioURL: URL) -> String {
        switch audioURL.pathExtension.lowercased() {
        case "mp3":
            return "audio/mp3"
        case "wav":
            return "audio/wav"
        case "m4a":
            return "audio/mp4"
        default:
            return "audio/mpeg"
        }
    }
    
    private func parseResponse(_ data: Data) throws -> Transcript {
        // parse deepgram response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any] else {
            throw TranscriptionError.apiError("invalid deepgram response")
        }
        
        // get duration
        let metadata = json["metadata"] as? [String: Any]
        let duration = metadata?["duration"] as? TimeInterval ?? 0
        
        var segments: [TranscriptSegment] = []
        
        // parse utterances if available (has speaker info)
        if let utterances = results["utterances"] as? [[String: Any]] {
            for utterance in utterances {
                guard let transcript = utterance["transcript"] as? String,
                      let speaker = utterance["speaker"] as? Int else { continue }
                
                // map speaker 0 to @me (primary speaker), others to speaker1, speaker2, etc.
                let speakerLabel: Speaker = speaker == 0 ? .me : .other("speaker\(speaker)")
                
                segments.append(TranscriptSegment(
                    speaker: speakerLabel,
                    text: transcript,
                    timestamp: utterance["start"] as? TimeInterval,
                    confidence: utterance["confidence"] as? Float
                ))
            }
        } else if let channels = results["channels"] as? [[String: Any]],
                  let firstChannel = channels.first,
                  let alternatives = firstChannel["alternatives"] as? [[String: Any]],
                  let firstAlternative = alternatives.first,
                  let transcript = firstAlternative["transcript"] as? String {
            // fallback to non-diarized transcript
            segments.append(TranscriptSegment(
                speaker: .me,
                text: transcript,
                timestamp: nil,
                confidence: firstAlternative["confidence"] as? Float
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
            duration: duration
        )
    }
    
    // MARK: - configuration
    
    static func createFromEnvironment(userDictionary: UserDictionary = UserDictionary()) -> DeepgramTranscriptionService? {
        // hardcoded for now, will move to secure storage
        let apiKey = "ea1942496aa5a53bed2c7f5641fecf0ba1646963"
        
        return DeepgramTranscriptionService(apiKey: apiKey, userDictionary: userDictionary)
    }
}