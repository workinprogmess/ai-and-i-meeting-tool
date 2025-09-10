//
//  AudioSegmentMetadata.swift
//  AI-and-I
//
//  tracks metadata for audio segments to enable perfect timeline reconstruction
//  even with device switches and gaps
//

import Foundation

/// metadata for a single audio segment (portion of recording)
struct AudioSegmentMetadata: Codable {
    let segmentID: String              // unique identifier
    let filePath: String               // path to audio file
    let deviceName: String             // "AirPods Pro" vs "MacBook Pro Microphone"
    let deviceID: String               // unique device identifier
    let sampleRate: Double             // 48000, 16000, etc
    let channels: Int                  // 1 for mono, 2 for stereo
    let startSessionTime: TimeInterval // offset from session start (seconds)
    let endSessionTime: TimeInterval   // offset from session end (seconds)
    let frameCount: Int                // exact number of audio frames
    let quality: AudioQuality          // quality assessment
    let error: String?                 // error if segment failed
    
    /// quality assessment for segment
    enum AudioQuality: String, Codable {
        case high = "high"              // 48khz+
        case medium = "medium"          // 24-44.1khz
        case low = "low"                // 16khz or below (telephony)
        case failed = "failed"          // write error
    }
    
    /// computed duration in seconds
    var duration: TimeInterval {
        return endSessionTime - startSessionTime
    }
    
    /// assess quality based on sample rate
    static func assessQuality(sampleRate: Double) -> AudioQuality {
        switch sampleRate {
        case 48000...:
            return .high
        case 24000..<48000:
            return .medium
        case 0..<24000:
            return .low
        default:
            return .failed
        }
    }
}

/// session metadata containing all segments
struct RecordingSessionMetadata: Codable {
    let sessionID: String               // unique session identifier
    let sessionStartTime: Date          // wall clock time when started
    let sessionEndTime: Date?           // wall clock time when ended
    let micSegments: [AudioSegmentMetadata]
    let systemSegments: [AudioSegmentMetadata]
    
    /// total duration of session
    var duration: TimeInterval? {
        guard let endTime = sessionEndTime else { return nil }
        return endTime.timeIntervalSince(sessionStartTime)
    }
    
    /// save metadata to disk
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
    
    /// load metadata from disk
    static func load(from url: URL) throws -> RecordingSessionMetadata {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingSessionMetadata.self, from: data)
    }
}

/// helper for generating segment file names
struct SegmentFileNaming {
    /// generate segment filename
    /// format: mic_[sessionTimestamp]_[segmentNumber].wav
    static func segmentFileName(
        type: AudioType,
        sessionTimestamp: TimeInterval,
        segmentNumber: Int
    ) -> String {
        let prefix = type == .microphone ? "mic" : "system"
        return "\(prefix)_\(Int(sessionTimestamp))_\(String(format: "%03d", segmentNumber)).wav"
    }
    
    enum AudioType {
        case microphone
        case system
    }
}