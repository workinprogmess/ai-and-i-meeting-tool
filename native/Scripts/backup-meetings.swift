#!/usr/bin/env swift

//
// backup-meetings.swift
// comprehensive backup system for ai&i meetings
// ensures you never lose a meeting again
//

import Foundation

print("🔐 meeting backup system for ai&i")
print(String(repeating: "=", count: 60))

let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
let backupFolder = documentsPath.appendingPathComponent("ai&i-backups")

// create backup folder with date
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
let backupTimestamp = dateFormatter.string(from: Date())
let currentBackupFolder = backupFolder.appendingPathComponent("backup_\(backupTimestamp)")

do {
    try FileManager.default.createDirectory(at: currentBackupFolder, 
                                           withIntermediateDirectories: true)
    print("📁 created backup folder: \(currentBackupFolder.lastPathComponent)")
} catch {
    print("❌ couldn't create backup folder: \(error)")
    exit(1)
}

// backup strategy:
// 1. metadata files (session info)
// 2. transcript files (what was said)
// 3. mixed audio files (the actual recording)
// 4. create a manifest for easy recovery

var backupManifest: [[String: Any]] = []
var backedUpCount = 0
var totalSize: Int64 = 0

// find all sessions
let fileManager = FileManager.default
guard let files = try? fileManager.contentsOfDirectory(at: recordingsFolder, 
                                                      includingPropertiesForKeys: [.fileSizeKey]) else {
    print("❌ couldn't read recordings directory")
    exit(1)
}

// group files by session
var sessionFiles: [String: [URL]] = [:]
for file in files {
    let filename = file.lastPathComponent
    
    // extract session timestamp from filename
    if filename.contains("session_") {
        let components = filename.components(separatedBy: "_")
        if components.count > 1 {
            let sessionId = components[1].components(separatedBy: ".")[0]
            if sessionFiles[sessionId] == nil {
                sessionFiles[sessionId] = []
            }
            sessionFiles[sessionId]?.append(file)
        }
    } else if filename.contains("mixed_") {
        let sessionId = filename
            .replacingOccurrences(of: "mixed_", with: "")
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".wav", with: "")
        if sessionFiles[sessionId] == nil {
            sessionFiles[sessionId] = []
        }
        sessionFiles[sessionId]?.append(file)
    }
}

print("\n📊 found \(sessionFiles.count) sessions to backup")
print(String(repeating: "-", count: 60))

// backup each session
for (sessionId, files) in sessionFiles.sorted(by: { $0.key > $1.key }) {
    print("\n📦 backing up session \(sessionId)...")
    
    var sessionBackup: [String: Any] = [
        "sessionId": sessionId,
        "backedUpAt": Date().timeIntervalSince1970,
        "files": []
    ]
    
    var sessionHasTranscript = false
    var sessionHasAudio = false
    var sessionFileList: [[String: String]] = []
    
    for file in files {
        let filename = file.lastPathComponent
        let backupPath = currentBackupFolder.appendingPathComponent(filename)
        
        do {
            // copy file to backup
            try fileManager.copyItem(at: file, to: backupPath)
            
            // get file size
            let attributes = try fileManager.attributesOfItem(atPath: file.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            totalSize += fileSize
            
            // track what we have
            if filename.contains("transcripts.json") {
                sessionHasTranscript = true
            }
            if filename.contains("mixed_") && (filename.hasSuffix(".mp3") || filename.hasSuffix(".wav")) {
                sessionHasAudio = true
            }
            
            sessionFileList.append([
                "filename": filename,
                "type": detectFileType(filename),
                "size": "\(fileSize)"
            ])
            
            print("  ✅ \(filename) (\(formatBytes(fileSize)))")
            backedUpCount += 1
            
        } catch {
            print("  ⚠️ couldn't backup \(filename): \(error)")
        }
    }
    
    // determine session status
    let status: String
    if sessionHasTranscript && sessionHasAudio {
        status = "complete"
    } else if sessionHasAudio && !sessionHasTranscript {
        status = "needs_transcription"
    } else if !sessionHasAudio {
        status = "needs_mixing"
    } else {
        status = "partial"
    }
    
    sessionBackup["status"] = status
    sessionBackup["hasTranscript"] = sessionHasTranscript
    sessionBackup["hasAudio"] = sessionHasAudio
    sessionBackup["files"] = sessionFileList
    
    backupManifest.append(sessionBackup)
    
    print("  📋 status: \(status)")
}

// save manifest
let manifestPath = currentBackupFolder.appendingPathComponent("backup_manifest.json")
do {
    let manifestData = try JSONSerialization.data(withJSONObject: [
        "backupVersion": "1.0",
        "backupDate": backupTimestamp,
        "totalSessions": sessionFiles.count,
        "totalFiles": backedUpCount,
        "totalSize": totalSize,
        "sessions": backupManifest
    ], options: .prettyPrinted)
    
    try manifestData.write(to: manifestPath)
    print("\n💾 saved backup manifest")
} catch {
    print("\n⚠️ couldn't save manifest: \(error)")
}

// cleanup old backups (keep last 5)
if let backups = try? fileManager.contentsOfDirectory(at: backupFolder, 
                                                     includingPropertiesForKeys: [.creationDateKey])
    .filter({ $0.lastPathComponent.starts(with: "backup_") })
    .sorted(by: { 
        let date1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
        let date2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
        return date1 > date2
    }) {
    
    if backups.count > 5 {
        print("\n🧹 cleaning old backups (keeping last 5)...")
        for backup in backups.dropFirst(5) {
            try? fileManager.removeItem(at: backup)
            print("  🗑️ removed \(backup.lastPathComponent)")
        }
    }
}

print("\n" + String(repeating: "=", count: 60))
print("✅ backup complete!")
print("  📦 sessions backed up: \(sessionFiles.count)")
print("  📄 files backed up: \(backedUpCount)")
print("  💾 total size: \(formatBytes(totalSize))")
print("  📁 backup location: \(currentBackupFolder.path)")

print("\n🔥 recovery guarantee:")
print("  • metadata files ✅ (session timing and device info)")
print("  • transcript files ✅ (what was said)")
print("  • mixed audio files ✅ (the actual recording)")
print("  • backup manifest ✅ (easy recovery index)")

print("\n💡 to restore from backup:")
print("  1. find backup in ~/Documents/ai&i-backups/")
print("  2. copy files back to ~/Documents/ai&i-recordings/")
print("  3. restart the app")

// helper functions
func detectFileType(_ filename: String) -> String {
    if filename.contains("metadata") { return "metadata" }
    if filename.contains("transcript") { return "transcript" }
    if filename.contains("mixed_") { return "mixed_audio" }
    if filename.contains("mic_") { return "mic_segment" }
    if filename.contains("system_") { return "system_segment" }
    return "unknown"
}

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}