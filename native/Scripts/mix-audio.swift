#!/usr/bin/env swift

//
// mix-audio.swift
// creates perfectly mixed audio from segmented recordings using metadata
//

import Foundation
import AVFoundation

// MARK: - Data Models

struct AudioSegmentMetadata: Codable {
    let segmentID: String
    let filePath: String
    let deviceName: String
    let deviceID: String
    let sampleRate: Double
    let channels: Int
    let startSessionTime: TimeInterval
    let endSessionTime: TimeInterval
    let frameCount: Int
    let quality: String
    let error: String?
}

struct RecordingSessionMetadata: Codable {
    let sessionID: String
    let sessionStartTime: Date
    let sessionEndTime: Date?
    let micSegments: [AudioSegmentMetadata]
    let systemSegments: [AudioSegmentMetadata]
}

// MARK: - Main Script

let arguments = CommandLine.arguments.dropFirst()
let targetTimestampArgument = arguments.first

let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let recordingsFolder = documentsPath.appendingPathComponent("ai&i-recordings")

print("🎬 audio mixer for ai&i")
print("=" * 60)

// find all metadata files
let fileManager = FileManager.default
guard let files = try? fileManager.contentsOfDirectory(at: recordingsFolder, 
                                                       includingPropertiesForKeys: nil) else {
    print("❌ couldn't read recordings directory")
    exit(1)
}

let metadataFiles = files.filter { 
                             $0.pathExtension == "json" && 
                             $0.lastPathComponent.contains("session_") &&
                             $0.lastPathComponent.contains("metadata.json")
                         }
                         .sorted { $0.lastPathComponent > $1.lastPathComponent }

if metadataFiles.isEmpty {
    print("❌ no metadata files found")
    print("💡 record something with device switches first!")
    exit(1)
}

func metadataFile(for timestamp: String, from files: [URL]) -> URL? {
    let preferredSuffixes = ["_metadata.json", "_mic_metadata.json", "_system_metadata.json"]
    for suffix in preferredSuffixes {
        let expectedName = "session_\(timestamp)\(suffix)"
        if let match = files.first(where: { $0.lastPathComponent == expectedName }) {
            return match
        }
    }
    return files.first(where: { $0.lastPathComponent.contains("session_\(timestamp)") })
}

let selectedMetadata: URL
if let target = targetTimestampArgument {
    guard let match = metadataFile(for: target, from: metadataFiles) else {
        print("❌ no metadata found for session \(target)")
        exit(1)
    }
    selectedMetadata = match
    print("📁 found \(metadataFiles.count) metadata file(s)")
    print("🎯 targeting session \(target)\n")
} else {
    selectedMetadata = metadataFiles.first!
    print("📁 found \(metadataFiles.count) metadata file(s)\n")
}

// process selected session
let targetDescription = targetTimestampArgument ?? "latest"
print("📄 processing: \(selectedMetadata.lastPathComponent) (requested: \(targetDescription))")
print("-" * 40)

// load and parse metadata
do {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // try both mic and system metadata files
        var micSegments: [AudioSegmentMetadata] = []
        var systemSegments: [AudioSegmentMetadata] = []
        var sessionTimestamp: String = ""
        
        // extract timestamp from filename
        let filename = selectedMetadata.lastPathComponent
        if filename.contains("session_") {
            let components = filename.split(separator: "_")
            if components.count >= 2 {
                sessionTimestamp = String(components[1])
            }
        }

        if let target = targetTimestampArgument {
            sessionTimestamp = target
        }
        
        // check if it's a mic or system metadata file
        // load microphone metadata from the core session file
        let micMetadataURL = recordingsFolder.appendingPathComponent("session_\(sessionTimestamp)_metadata.json")
        if let micData = try? Data(contentsOf: micMetadataURL) {
            let micMetadata = try decoder.decode(RecordingSessionMetadata.self, from: micData)
            micSegments = micMetadata.micSegments
        }

        // load system metadata from the dedicated file
        let systemMetadataURL = recordingsFolder.appendingPathComponent("session_\(sessionTimestamp)_system_metadata.json")
        if let systemData = try? Data(contentsOf: systemMetadataURL) {
            let systemMetadata = try decoder.decode(RecordingSessionMetadata.self, from: systemData)
            systemSegments = systemMetadata.systemSegments
            print("📄 also loaded: session_\(sessionTimestamp)_system_metadata.json")
        } else {
            print("⚠️ system metadata not found for session \(sessionTimestamp)")
        }
        
        // analyze segments
        print("\n🎤 microphone segments: \(micSegments.count)")
        if !micSegments.isEmpty {
            var totalMicAudio: TimeInterval = 0
            
            for (index, segment) in micSegments.enumerated() {
                let duration = segment.endSessionTime - segment.startSessionTime
                totalMicAudio += duration
                
                print("  segment #\(index + 1):")
                print("    device: \(segment.deviceName)")
                print("    timing: \(String(format: "%.3f", segment.startSessionTime))s - \(String(format: "%.3f", segment.endSessionTime))s")
                print("    duration: \(String(format: "%.3f", duration))s")
                
                if index > 0 {
                    let prevSegment = micSegments[index - 1]
                    let gap = segment.startSessionTime - prevSegment.endSessionTime
                    if gap > 0.1 {
                        print("    🔇 gap: \(String(format: "%.3f", gap))s")
                    }
                }
            }
            
            print("  total audio: \(String(format: "%.3f", totalMicAudio))s")
            
            if micSegments.count > 1 {
                let firstStart = micSegments.first!.startSessionTime
                let lastEnd = micSegments.last!.endSessionTime
                let totalTimeline = lastEnd - firstStart
                let totalGaps = totalTimeline - totalMicAudio
                print("  total gaps: \(String(format: "%.3f", totalGaps))s")
                print("  timeline span: \(String(format: "%.3f", totalTimeline))s")
            }
        }
        
        print("\n🔊 system audio segments: \(systemSegments.count)")
        if !systemSegments.isEmpty {
            for (index, segment) in systemSegments.enumerated() {
                let duration = segment.endSessionTime - segment.startSessionTime
                print("  segment #\(index + 1):")
                print("    timing: \(String(format: "%.3f", segment.startSessionTime))s - \(String(format: "%.3f", segment.endSessionTime))s")
                print("    duration: \(String(format: "%.3f", duration))s")
            }
        }
        
        // generate ffmpeg command for perfect mixing
        if !micSegments.isEmpty && !systemSegments.isEmpty {
            print("\n🎬 generating ffmpeg command for perfect mixing...")
            print("=" * 60)
            
            // build the command step by step for clarity
            var ffmpegCmd = "ffmpeg"
            
            // add all mic segment inputs
            for (index, segment) in micSegments.enumerated() {
                let filename = URL(fileURLWithPath: segment.filePath).lastPathComponent
                ffmpegCmd += " -i \(filename)"
            }

            // add system audio input
            let systemFilename = systemSegments.first.map { URL(fileURLWithPath: $0.filePath).lastPathComponent } ?? "system_\(sessionTimestamp)_001.wav"
            ffmpegCmd += " -i \(systemFilename)"
            
            // build filter complex
            ffmpegCmd += " -filter_complex \""
            
            // IMPORTANT: mic segments are sequential (stop/restart), not overlapping
            // so we concatenate them, not mix with delays
            var micFilters: [String] = []
            for (index, segment) in micSegments.enumerated() {
                // detect if using airpods or built-in mic
                let isAirPods = segment.deviceName.lowercased().contains("airpods")
                let micBoost = isAirPods ? "8dB" : "12dB"  // more boost for built-in mic
                
                // resample to 48khz (fixes robotic audio) and apply volume boost
                micFilters.append("[\(index)]aresample=48000,volume=\(micBoost)[m\(index)]")
            }
            
            // join mic filters
            ffmpegCmd += micFilters.joined(separator: "; ")
            
            // concatenate mic segments sequentially (not mix!)
            if micSegments.count > 1 {
                let micLabels = (0..<micSegments.count).map { "[m\($0)]" }.joined()
                ffmpegCmd += "; \(micLabels)concat=n=\(micSegments.count):v=0:a=1[mic]"
            } else {
                ffmpegCmd += "; [m0]acopy[mic]"
            }
            
            // process system audio with resampling and volume reduction
            // check if any segments use built-in mic (need more aggressive reduction)
            let hasBuiltInMic = micSegments.contains { !$0.deviceName.lowercased().contains("airpods") }
            let systemReduction = hasBuiltInMic ? "-10dB" : "-6dB"  // more reduction if built-in mic used
            
            let systemIndex = micSegments.count
            // resample system audio to 48khz and reduce volume
            ffmpegCmd += "; [\(systemIndex)]aresample=48000,volume=\(systemReduction)[sys]"
            
            // final mix of concatenated mic with system audio
            // use 'longest' duration so the mix survives mic dropouts
            ffmpegCmd += "; [mic][sys]amix=inputs=2:duration=longest[out]\""
            
            // output settings
            let outputFile = "mixed_\(sessionTimestamp).wav"
            ffmpegCmd += " -map \"[out]\" -acodec pcm_s16le -ar 48000 \(outputFile)"
            
            // print the command in a copy-friendly format
            print("\n# copy and run this command:")
            print("cd ~/Documents/ai\\&i-recordings")
            print("")
            
            // pretty print for readability
            print("ffmpeg \\")
            for (index, segment) in micSegments.enumerated() {
                let filename = URL(fileURLWithPath: segment.filePath).lastPathComponent
                print("  -i \(filename) \\")
            }
            print("  -i \(systemFilename) \\")
            print("  -filter_complex \"")
            
            // pretty print filters with dynamic volume adjustments
            for (index, segment) in micSegments.enumerated() {
                let isAirPods = segment.deviceName.lowercased().contains("airpods")
                let micBoost = isAirPods ? "8dB" : "12dB"
                let deviceType = isAirPods ? "airpods" : "built-in"
                let comment = "  # \(deviceType) mic resampled +\(micBoost)"
                print("    [\(index)]aresample=48000,volume=\(micBoost)[m\(index)];\(comment) \\")
            }
            
            if micSegments.count > 1 {
                let micLabels = (0..<micSegments.count).map { "[m\($0)]" }.joined()
                print("    \(micLabels)concat=n=\(micSegments.count):v=0:a=1[mic];  # concatenate segments \\")
            } else {
                print("    [m0]acopy[mic]; \\")
            }
            
            // use the systemReduction already calculated above
            print("    [\(systemIndex)]aresample=48000,volume=\(systemReduction)[sys];  # system resampled and \(systemReduction) \\")
            
            print("    [mic][sys]amix=inputs=2:duration=longest[out]\"  # mix with 'longest' duration \\")
            print("  -map \"[out]\" \\")
            print("  -acodec pcm_s16le \\")
            print("  -ar 48000 \\")
            print("  \(outputFile)")
            
            print("\n✅ command generated successfully!")
            
            // show timing summary
            print("\n📊 mixing summary:")
            print("  mic segments: \(micSegments.count)")
            print("  devices used: \(Set(micSegments.map { $0.deviceName }).joined(separator: ", "))")
            print("  total mic audio: \(String(format: "%.1f", micSegments.reduce(0) { $0 + ($1.endSessionTime - $1.startSessionTime) }))s")
            print("  system audio: \(String(format: "%.1f", systemSegments.reduce(0) { $0 + ($1.endSessionTime - $1.startSessionTime) }))s")
            
            let totalGaps = micSegments.enumerated().reduce(0.0) { result, item in
                let (index, segment) = item
                if index > 0 {
                    return result + (segment.startSessionTime - micSegments[index - 1].endSessionTime)
                }
                return result
            }
            print("  total gaps: \(String(format: "%.1f", totalGaps))s")
            print("  output file: \(outputFile)")
            
            // actually execute the ffmpeg command
            print("\n🚀 executing ffmpeg command...")
            let recordingsPath = recordingsFolder.path
            let result = executeFFmpegMixing(
                micSegments: micSegments,
                systemSegments: systemSegments,
                sessionTimestamp: Int(sessionTimestamp) ?? 0,
                recordingsPath: recordingsPath
            )
            
            if result {
                print("✅ mixing completed successfully!")
                print("📍 output: \(recordingsPath)/\(outputFile)")
            } else {
                print("❌ mixing failed - check the command above")
            }
        } else if !micSegments.isEmpty {
            print("\n⚠️ only mic segments found - no system audio to mix")
        } else if !systemSegments.isEmpty {
            print("\n⚠️ only system segments found - no mic audio to mix")
        }
        
    } catch {
        print("❌ error reading metadata: \(error)")
        
        // try simple JSON parsing as fallback
        if let data = try? Data(contentsOf: selectedMetadata),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("\n📋 falling back to simple JSON parsing...")
            
            if let micSegments = json["micSegments"] as? [[String: Any]] {
                print("\nmic segments found: \(micSegments.count)")
                
                for (index, segment) in micSegments.enumerated() {
                    if let start = segment["startSessionTime"] as? Double,
                       let end = segment["endSessionTime"] as? Double,
                       let device = segment["deviceName"] as? String {
                        print("  #\(index + 1): \(String(format: "%.1f", start))s - \(String(format: "%.1f", end))s (\(device))")
                    }
                }
            }
        }
    }

print("\n" + "=" * 60)
print("💡 tip: run this script after recording with device switches")
print("📝 note: the generated command assumes you're in ~/Documents/ai&i-recordings")

// helper to repeat string
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}

// MARK: - ffmpeg execution

func executeFFmpegMixing(
    micSegments: [AudioSegmentMetadata],
    systemSegments: [AudioSegmentMetadata],
    sessionTimestamp: Int,
    recordingsPath: String
) -> Bool {
    // build ffmpeg arguments
    var args: [String] = []
    
    // add input files
    for segment in micSegments {
        args.append("-i")
        args.append(segment.filePath)
    }
    
    // add system audio (use first segment path; future work can concatenate if needed)
    let systemPath = systemSegments.first?.filePath ?? "\(recordingsPath)/system_\(sessionTimestamp)_001.wav"
    args.append("-i")
    args.append(systemPath)
    
    // build filter complex
    var filterParts: [String] = []
    
    // process mic segments with resampling
    for (index, segment) in micSegments.enumerated() {
        let isAirPods = segment.deviceName.lowercased().contains("airpods")
        let micBoost = isAirPods ? "8dB" : "12dB"
        
        filterParts.append("[\(index)]aresample=48000,volume=\(micBoost)[m\(index)]")
    }
    
    // concatenate mic segments if multiple
    if micSegments.count > 1 {
        let concatInputs = (0..<micSegments.count).map { "[m\($0)]" }.joined()
        filterParts.append("\(concatInputs)concat=n=\(micSegments.count):v=0:a=1[mic]")
    } else {
        filterParts.append("[m0]acopy[mic]")
    }
    
    // process system audio with resampling
    let hasBuiltInMic = micSegments.contains { !$0.deviceName.lowercased().contains("airpods") }
    let systemReduction = hasBuiltInMic ? "-10dB" : "-6dB"
    filterParts.append("[\(micSegments.count)]aresample=48000,volume=\(systemReduction)[sys]")
    
    // mix together (use 'longest' duration so system audio can cover mic dropouts)
    filterParts.append("[mic][sys]amix=inputs=2:duration=longest[out]")
    
    let filterComplex = filterParts.joined(separator: ";")
    args.append("-filter_complex")
    args.append(filterComplex)
    
    // output options
    args.append("-map")
    args.append("[out]")
    args.append("-acodec")
    args.append("pcm_s16le")
    args.append("-ar")
    args.append("48000")
    args.append("\(recordingsPath)/mixed_\(sessionTimestamp).wav")
    
    // find ffmpeg
    let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
    guard let ffmpegPath = ffmpegPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
        print("❌ ffmpeg not found")
        return false
    }
    
    // execute ffmpeg
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpegPath)
    process.arguments = args
    
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        print("❌ failed to run ffmpeg: \(error)")
        return false
    }
}
