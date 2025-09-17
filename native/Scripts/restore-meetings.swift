#!/usr/bin/env swift

//
// restore-meetings.swift  
// restore meetings from backup
//

import Foundation

print("🔄 meeting restore system for ai&i")
print(String(repeating: "=", count: 60))

let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")
let backupFolder = documentsPath.appendingPathComponent("ai&i-backups")

let fileManager = FileManager.default

// list available backups
guard let backups = try? fileManager.contentsOfDirectory(at: backupFolder, 
                                                        includingPropertiesForKeys: [.creationDateKey])
    .filter({ $0.lastPathComponent.starts(with: "backup_") })
    .sorted(by: { 
        let date1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
        let date2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
        return date1 > date2
    }), !backups.isEmpty else {
    print("❌ no backups found in \(backupFolder.path)")
    exit(1)
}

print("📦 available backups:")
for (index, backup) in backups.enumerated() {
    let manifestPath = backup.appendingPathComponent("backup_manifest.json")
    if let data = try? Data(contentsOf: manifestPath),
       let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        let sessions = manifest["totalSessions"] as? Int ?? 0
        let files = manifest["totalFiles"] as? Int ?? 0
        let size = manifest["totalSize"] as? Int64 ?? 0
        let date = manifest["backupDate"] as? String ?? "unknown"
        
        print("  \(index + 1). \(backup.lastPathComponent)")
        print("     date: \(date)")
        print("     sessions: \(sessions), files: \(files), size: \(formatBytes(size))")
    } else {
        print("  \(index + 1). \(backup.lastPathComponent) (no manifest)")
    }
}

print("\nwhich backup to restore? (enter number, or 'latest' for most recent):")
let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "latest"

let selectedBackup: URL
if input.lowercased() == "latest" || input == "1" {
    selectedBackup = backups[0]
} else if let index = Int(input), index > 0, index <= backups.count {
    selectedBackup = backups[index - 1]
} else {
    print("❌ invalid selection")
    exit(1)
}

print("\n🎯 selected: \(selectedBackup.lastPathComponent)")

// load manifest
let manifestPath = selectedBackup.appendingPathComponent("backup_manifest.json")
guard let manifestData = try? Data(contentsOf: manifestPath),
      let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
      let sessions = manifest["sessions"] as? [[String: Any]] else {
    print("❌ couldn't read backup manifest")
    exit(1)
}

print("\n⚠️ restore will copy files to recordings folder")
print("existing files with same names will be skipped")
print("continue? (y/n):")

let confirm = readLine()?.lowercased() ?? "n"
if confirm != "y" {
    print("❌ restore cancelled")
    exit(0)
}

print("\n🔄 restoring...")
print(String(repeating: "-", count: 60))

var restoredCount = 0
var skippedCount = 0
var errorCount = 0

// restore each file
for session in sessions {
    guard let sessionId = session["sessionId"] as? String,
          let files = session["files"] as? [[String: String]] else { continue }
    
    print("\n📦 session \(sessionId):")
    
    for fileInfo in files {
        guard let filename = fileInfo["filename"] else { continue }
        
        let sourcePath = selectedBackup.appendingPathComponent(filename)
        let destPath = recordingsFolder.appendingPathComponent(filename)
        
        // check if file exists
        if fileManager.fileExists(atPath: destPath.path) {
            print("  ⏭️ skipped \(filename) (already exists)")
            skippedCount += 1
        } else {
            do {
                try fileManager.copyItem(at: sourcePath, to: destPath)
                print("  ✅ restored \(filename)")
                restoredCount += 1
            } catch {
                print("  ❌ failed \(filename): \(error)")
                errorCount += 1
            }
        }
    }
}

print("\n" + String(repeating: "=", count: 60))
print("✅ restore complete!")
print("  📄 files restored: \(restoredCount)")
print("  ⏭️ files skipped: \(skippedCount)")
if errorCount > 0 {
    print("  ❌ errors: \(errorCount)")
}

print("\n💡 next steps:")
print("  1. restart the ai&i app")
print("  2. check meetings list - restored meetings should appear")
print("  3. run recover-meetings.swift if any meetings need re-transcription")

func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}