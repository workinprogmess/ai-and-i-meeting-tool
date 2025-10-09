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
        micSegments.sort { $0.startSessionTime < $1.startSessionTime }
        systemSegments.sort { $0.startSessionTime < $1.startSessionTime }

        print("\n🎤 microphone segments: \(micSegments.count)")
        if !micSegments.isEmpty {
            var totalMicAudio: TimeInterval = 0
            
            for (index, segment) in micSegments.enumerated() {
                let duration = segment.endSessionTime - segment.startSessionTime
                totalMicAudio += duration
                
                let isTelephony = segment.quality.lowercased() == "low" || segment.error?.contains("telephony") == true
                let qualityLabel = isTelephony ? " [telephony]" : ""

                print("  segment #\(index + 1):")
                print("    device: \(segment.deviceName)\(qualityLabel)")
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
            print("\n🎬 generating ffmpeg command for perfect mixing (with telephony enhancement)...")
            print("=" * 60)

            let micFilenames = micSegments.map { URL(fileURLWithPath: $0.filePath).lastPathComponent }
            let systemFilenames = systemSegments.map { URL(fileURLWithPath: $0.filePath).lastPathComponent }
            let allFilenames = micFilenames + systemFilenames

            var ffmpegCmd = "ffmpeg"
            for name in allFilenames {
                ffmpegCmd += " -i \(name)"
            }

            let baseStart = min(
                micSegments.map { $0.startSessionTime }.min() ?? 0,
                systemSegments.map { $0.startSessionTime }.min() ?? 0
            )

            var filterParts: [String] = []

            // microphone processing with telephony enhancement
            for (index, segment) in micSegments.enumerated() {
                let isAirPods = segment.deviceName.lowercased().contains("airpods")
                let isTelephony = segment.quality.lowercased() == "low" || segment.error?.contains("telephony") == true

                var micBoost: String
                var filterChain = "[\(index)]aresample=48000"

                if isTelephony {
                    // telephony segment: gentle boost + bandwidth preservation
                    micBoost = "8dB"  // extra boost for telephony compression
                    filterChain += ",volume=\(micBoost),highpass=f=200,lowpass=f=3400"  // preserve telephony bandwidth
                } else {
                    // normal segment processing
                    micBoost = isAirPods ? "4dB" : "6dB"
                    filterChain += ",volume=\(micBoost)"
                }

                filterParts.append("\(filterChain)[m\(index)]")
            }

            if micSegments.count > 1 {
                let micLabels = (0..<micSegments.count).map { "[m\($0)]" }.joined()
                filterParts.append("\(micLabels)concat=n=\(micSegments.count):v=0:a=1[micCombined]")
            } else {
                filterParts.append("[m0]acopy[micCombined]")
            }

            // system audio alignment with delay padding
            let hasBuiltInMic = micSegments.contains { !$0.deviceName.lowercased().contains("airpods") }
            let systemReduction = hasBuiltInMic ? "-8dB" : "-4dB"
            let systemStartIndex = micSegments.count
            for (offset, segment) in systemSegments.enumerated() {
                let absoluteIndex = systemStartIndex + offset
                var chain = "[\(absoluteIndex)]aresample=48000,volume=\(systemReduction)"
                let delayMs = max(0, Int(round((segment.startSessionTime - baseStart) * 1000)))
                if delayMs > 0 {
                    chain += ",adelay=\(delayMs)|\(delayMs)"
                }
                filterParts.append("\(chain)[sys\(offset)]")
            }

            if systemSegments.count > 1 {
                let sysLabels = (0..<systemSegments.count).map { "[sys\($0)]" }.joined()
                filterParts.append("\(sysLabels)amix=inputs=\(systemSegments.count):dropout_transition=0[sysCombined]")
            } else {
                filterParts.append("[sys0]acopy[sysCombined]")
            }

            // final mix
            filterParts.append("[micCombined][sysCombined]amix=inputs=2:duration=longest[out]")

            let filterComplex = filterParts.joined(separator: "; ")
            ffmpegCmd += " -filter_complex \"\(filterComplex)\""

            let outputFile = "mixed_\(sessionTimestamp).wav"
            ffmpegCmd += " -map \"[out]\" -acodec pcm_s16le -ar 48000 \(outputFile)"

            print("\n# copy and run this command:")
            print("cd ~/Documents/ai\\&i-recordings\n")

            print("ffmpeg \\")
            for name in allFilenames {
                print("  -i \(name) \\")
            }
            print("  -filter_complex \"")

            for (index, segment) in micSegments.enumerated() {
                let isAirPods = segment.deviceName.lowercased().contains("airpods")
                let isTelephony = segment.quality.lowercased() == "low" || segment.error?.contains("telephony") == true

                var micBoost: String
                var deviceType: String
                var filterChain = "[\(index)]aresample=48000"

                if isTelephony {
                    micBoost = "8dB"
                    deviceType = "telephony"
                    filterChain += ",volume=\(micBoost),highpass=f=200,lowpass=f=3400"
                } else {
                    micBoost = isAirPods ? "4dB" : "6dB"
                    deviceType = isAirPods ? "airpods" : "built-in"
                    filterChain += ",volume=\(micBoost)"
                }

                print("    \(filterChain)[m\(index)];  # \(deviceType) mic boost \\")
            }

            if micSegments.count > 1 {
                let micLabels = (0..<micSegments.count).map { "[m\($0)]" }.joined()
                print("    \(micLabels)concat=n=\(micSegments.count):v=0:a=1[micCombined];  # concatenate mic segments \\")
            } else {
                print("    [m0]acopy[micCombined]; \\")
            }

            for (offset, segment) in systemSegments.enumerated() {
                let absoluteIndex = systemStartIndex + offset
                let delayMs = max(0, Int(round((segment.startSessionTime - baseStart) * 1000)))
                let delayComment = delayMs > 0 ? " +delay \(Double(delayMs) / 1000)s" : ""
                let delayFilter = delayMs > 0 ? ",adelay=\(delayMs)|\(delayMs)" : ""
                print("    [\(absoluteIndex)]aresample=48000,volume=\(systemReduction)\(delayFilter)[sys\(offset)];  # system seg \(offset + 1)\(delayComment) \\")
            }

            if systemSegments.count > 1 {
                let sysLabels = (0..<systemSegments.count).map { "[sys\($0)]" }.joined()
                print("    \(sysLabels)amix=inputs=\(systemSegments.count):dropout_transition=0[sysCombined];  # align + merge system segments \\")
            } else {
                print("    [sys0]acopy[sysCombined]; \\")
            }

            print("    [micCombined][sysCombined]amix=inputs=2:duration=longest[out]\"  # final mix \\")
            print("  -map \"[out]\" \\")
            print("  -acodec pcm_s16le \\")
            print("  -ar 48000 \\")
            print("  \(outputFile)")

            let telephonyCount = micSegments.filter { $0.quality.lowercased() == "low" || $0.error?.contains("telephony") == true }.count
            let enhancementNote = telephonyCount > 0 ? " (\(telephonyCount) telephony segments enhanced)" : ""
            print("\n✅ command generated successfully!\(enhancementNote)")

            // show timing summary
            print("\n📊 mixing summary:")
            print("  mic segments: \(micSegments.count)")
            print("  devices used: \(Set(micSegments.map { $0.deviceName }).joined(separator: ", "))")

            let telephonySegments = micSegments.filter { $0.quality.lowercased() == "low" || $0.error?.contains("telephony") == true }
            if !telephonySegments.isEmpty {
                print("  telephony segments: \(telephonySegments.count) (enhanced with 8dB boost + bandwidth filter)")
            }

            print("  total mic audio: \(String(format: "%.1f", micSegments.reduce(0) { $0 + ($1.endSessionTime - $1.startSessionTime) }))s")
            print("  system audio: \(String(format: "%.1f", systemSegments.reduce(0) { $0 + ($1.endSessionTime - $1.startSessionTime) }))s")

            let totalGaps = micSegments.enumerated().reduce(0.0) { result, item in
                let (index, segment) = item
                if index > 0 {
                    return result + (segment.startSessionTime - micSegments[index - 1].endSessionTime)
                }
                return result
            }
            print("  total mic gaps: \(String(format: "%.1f", totalGaps))s")
            let timelineEnd = max(
                micSegments.map { $0.endSessionTime }.max() ?? 0,
                systemSegments.map { $0.endSessionTime }.max() ?? 0
            )
            let timelineStart = min(baseStart, 0)
            print("  expected timeline: \(String(format: "%.1f", timelineEnd - timelineStart))s")
            print("  output file: \(outputFile)")

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
    let sortedMicSegments = micSegments.sorted { $0.startSessionTime < $1.startSessionTime }
    let sortedSystemSegments = systemSegments.sorted { $0.startSessionTime < $1.startSessionTime }

    // build ffmpeg arguments
    var args: [String] = []
    
    // add input files
    for segment in sortedMicSegments {
        args.append("-i")
        args.append(segment.filePath)
    }
    
    // add system audio segments (support multiple files)
    let systemInputs = sortedSystemSegments.isEmpty
        ? ["\(recordingsPath)/system_\(sessionTimestamp)_001.wav"]
        : sortedSystemSegments.map { $0.filePath }
    for path in systemInputs {
        args.append("-i")
        args.append(path)
    }
    
    // build filter complex
    var filterParts: [String] = []

    // process mic segments with resampling and telephony enhancement
    for (index, segment) in sortedMicSegments.enumerated() {
        let isAirPods = segment.deviceName.lowercased().contains("airpods")
        let isTelephony = segment.quality.lowercased() == "low" || segment.error?.contains("telephony") == true

        var micBoost: String
        var filterChain = "[\(index)]aresample=48000"

        if isTelephony {
            // telephony segment: gentle boost + bandwidth preservation
            micBoost = "8dB"  // extra boost for telephony compression
            filterChain += ",volume=\(micBoost),highpass=f=200,lowpass=f=3400"  // preserve telephony bandwidth
        } else {
            // normal segment processing
            micBoost = isAirPods ? "4dB" : "6dB"
            filterChain += ",volume=\(micBoost)"
        }

        filterParts.append("\(filterChain)[m\(index)]")
    }

    // concatenate mic segments if multiple
    if sortedMicSegments.count > 1 {
        let concatInputs = (0..<sortedMicSegments.count).map { "[m\($0)]" }.joined()
        filterParts.append("\(concatInputs)concat=n=\(sortedMicSegments.count):v=0:a=1[micCombined]")
    } else {
        filterParts.append("[m0]acopy[micCombined]")
    }

    // process system audio with resampling + timeline alignment
    let hasBuiltInMic = sortedMicSegments.contains { !$0.deviceName.lowercased().contains("airpods") }
    let systemReduction = hasBuiltInMic ? "-8dB" : "-4dB"
    let systemStartIndex = sortedMicSegments.count
    let baseStart = min(
        sortedMicSegments.map { $0.startSessionTime }.min() ?? 0,
        sortedSystemSegments.map { $0.startSessionTime }.min() ?? 0
    )

    if !sortedSystemSegments.isEmpty {
        for (offset, segment) in sortedSystemSegments.enumerated() {
            let absoluteIndex = systemStartIndex + offset
            var chain = "[\(absoluteIndex)]aresample=48000,volume=\(systemReduction)"
            let delayMs = max(0, Int(round((segment.startSessionTime - baseStart) * 1000)))
            if delayMs > 0 {
                chain += ",adelay=\(delayMs)|\(delayMs)"
            }
            filterParts.append("\(chain)[sys\(offset)]")
        }

        if sortedSystemSegments.count > 1 {
            let concatInputs = (0..<sortedSystemSegments.count).map { "[sys\($0)]" }.joined()
            filterParts.append("\(concatInputs)amix=inputs=\(sortedSystemSegments.count):dropout_transition=0[sysCombined]")
        } else {
            filterParts.append("[sys0]acopy[sysCombined]")
        }
    } else if !systemInputs.isEmpty {
        filterParts.append("[\(systemStartIndex)]aresample=48000,volume=\(systemReduction)[sysCombined]")
    }

    // mix together (use 'longest' duration so system audio can cover mic dropouts)
    filterParts.append("[micCombined][sysCombined]amix=inputs=2:duration=longest[out]")
    
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
