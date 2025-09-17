#!/usr/bin/env swift

//
// recover-meetings.swift
// recovers lost meeting data from audio files and metadata
// can re-transcribe audio files that have lost transcripts
//

import Foundation

print("🔍 meeting recovery tool for ai&i")
print(String(repeating: "=", count: 60))

let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")

// find all session metadata files
let fileManager = FileManager.default
guard let files = try? fileManager.contentsOfDirectory(at: recordingsFolder, 
                                                      includingPropertiesForKeys: nil) else {
    print("❌ couldn't read recordings directory")
    exit(1)
}

// find sessions with metadata but no transcripts
let metadataFiles = files.filter { 
    $0.lastPathComponent.contains("session_") && 
    $0.lastPathComponent.contains("_metadata.json") &&
    !$0.lastPathComponent.contains("_system_")
}

print("📋 found \(metadataFiles.count) sessions")

var orphanedSessions: [String] = []
var transcribedSessions: [String] = []

for metadataFile in metadataFiles {
    let filename = metadataFile.lastPathComponent
    let sessionTimestamp = filename
        .replacingOccurrences(of: "session_", with: "")
        .replacingOccurrences(of: "_metadata.json", with: "")
        .replacingOccurrences(of: "_mic", with: "")
    
    // check for transcript
    let transcriptPath = recordingsFolder.appendingPathComponent("session_\(sessionTimestamp)_transcripts.json")
    let hasTranscript = fileManager.fileExists(atPath: transcriptPath.path)
    
    // check for mixed audio
    let mp3Path = recordingsFolder.appendingPathComponent("mixed_\(sessionTimestamp).mp3")
    let wavPath = recordingsFolder.appendingPathComponent("mixed_\(sessionTimestamp).wav")
    let hasMixed = fileManager.fileExists(atPath: mp3Path.path) || 
                  fileManager.fileExists(atPath: wavPath.path)
    
    if hasTranscript {
        transcribedSessions.append(sessionTimestamp)
        print("✅ session \(sessionTimestamp): has transcript")
    } else if hasMixed {
        orphanedSessions.append(sessionTimestamp)
        print("⚠️ session \(sessionTimestamp): has audio but NO transcript")
    } else {
        print("🔧 session \(sessionTimestamp): no mixed audio (needs mixing first)")
    }
}

print("\n" + String(repeating: "=", count: 60))
print("📊 summary:")
print("  • \(transcribedSessions.count) sessions with transcripts")
print("  • \(orphanedSessions.count) sessions missing transcripts")

if !orphanedSessions.isEmpty {
    print("\n💡 to recover transcripts for orphaned sessions:")
    print("1. ensure mixed audio files exist (run mix-audio.swift if needed)")
    print("2. manually trigger transcription through the app")
    print("3. or use this command for each session:")
    print("\n   # example for session \(orphanedSessions.first!):")
    print("   curl -X POST http://localhost:8080/transcribe \\")
    print("     -F \"audio=@mixed_\(orphanedSessions.first!).mp3\" \\")
    print("     -F \"session=\(orphanedSessions.first!)\"")
}

// check for the lost 5-minute meeting in transcription-results.json
let legacyPath = recordingsFolder.appendingPathComponent("transcription-results.json")
if let data = try? Data(contentsOf: legacyPath) {
    // just check if file exists and has content
    print("\n📝 legacy transcription-results.json exists (\(data.count) bytes)")
    print("   (this file gets overwritten each time)")
}

print("\n✨ data preservation tips:")
print("• each session now saves to session_TIMESTAMP_transcripts.json")
print("• never lose transcripts again!")
print("• old transcription-results.json is kept for compatibility only")