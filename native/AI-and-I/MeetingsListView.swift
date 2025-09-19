//
//  MeetingsListView.swift
//  AI-and-I
//
//  main landing page showing all past meetings
//

import SwiftUI

// MARK: - data models

struct Meeting: Identifiable, Codable, Hashable {
    var id = UUID()
    let timestamp: Date
    let duration: TimeInterval
    var title: String  // changed to var for updating
    let speakerCount: Int
    let audioFileURL: URL?
    var transcriptAvailable: Bool  // changed to var
    var processingStatus: String?  // "gemini done, waiting for deepgram..."
    
    // computed properties
    var formattedDuration: String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
    
    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
    
    var daySection: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) {
            return "today"
        } else if calendar.isDateInYesterday(timestamp) {
            return "yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d"
            return formatter.string(from: timestamp).lowercased()
        }
    }
}

// MARK: - view model

@MainActor
class MeetingsListViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var searchText = ""
    
    // recording components - need to be persistent objects
    let micRecorder = MicRecorder()
    let systemRecorder = SystemAudioRecorder()
    let deviceMonitor = DeviceChangeMonitor()
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var processingMeetingID: UUID?
    
    init() {
        loadMeetings()
        setupDeviceMonitoring()
    }
    
    private func setupDeviceMonitoring() {
        print("🔧 setupDeviceMonitoring called")
        
        // start monitoring for device changes
        deviceMonitor.startMonitoring()
        print("📱 device monitor started: \(deviceMonitor.isMonitoring)")
        
        // connect device change callbacks
        deviceMonitor.onMicDeviceChange = { [weak self] reason in
            Task { @MainActor in
                print("🎤 mic device change detected: \(reason)")
                // handle mic device changes (airpods connect/disconnect)
                self?.micRecorder.handleDeviceChange(reason: reason)
            }
        }
        
        deviceMonitor.onSystemDeviceChange = { [weak self] reason in
            Task { @MainActor in
                print("🔊 system device change detected: \(reason)")
                // handle system audio device changes
                await self?.systemRecorder.handleDeviceChange(reason: reason)
            }
        }
        
        print("📱 device monitoring callbacks connected - will handle airpods switching")
    }
    
    func loadMeetings() {
        // load from recordings folder (where files are actually saved)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sessionsPath = documentsPath.appendingPathComponent("ai&i-recordings")
        
        print("📂 loading meetings from: \(sessionsPath.path)")
        
        var loadedMeetings: [Meeting] = []
        
        // load all session metadata files (each recording creates one)
        if let files = try? FileManager.default.contentsOfDirectory(at: sessionsPath, 
                                                                   includingPropertiesForKeys: nil) {
            
            print("📁 found \(files.count) total files")
            
            // find all session metadata files (not system metadata)
            let metadataFiles = files.filter { 
                $0.lastPathComponent.contains("session_") && 
                $0.lastPathComponent.contains("_metadata.json") &&
                !$0.lastPathComponent.contains("_system_")
            }
            
            print("📋 found \(metadataFiles.count) session metadata files")
            
            for metadataFile in metadataFiles {
                // extract session timestamp from filename
                let filename = metadataFile.lastPathComponent
                let sessionTimestamp = filename
                    .replacingOccurrences(of: "session_", with: "")
                    .replacingOccurrences(of: "_metadata.json", with: "")
                    .replacingOccurrences(of: "_mic", with: "")
                
                // load metadata to get duration and other info
                do {
                    let data = try Data(contentsOf: metadataFile)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let metadata = try decoder.decode(RecordingSessionMetadata.self, from: data)
                    print("✅ loaded metadata for session \(sessionTimestamp)")
                    
                    // calculate duration from metadata
                    let duration: TimeInterval
                    if let endTime = metadata.sessionEndTime {
                        duration = endTime.timeIntervalSince(metadata.sessionStartTime)
                    } else {
                        // if no end time, use segment durations
                        let micDuration = metadata.micSegments.last?.endSessionTime ?? 0
                        let systemDuration = metadata.systemSegments.last?.endSessionTime ?? 0
                        duration = max(micDuration, systemDuration)
                    }
                    
                    // check if transcription exists for this session
                    let transcriptPath = sessionsPath.appendingPathComponent("session_\(sessionTimestamp)_transcripts.json")
                    let hasTranscript = FileManager.default.fileExists(atPath: transcriptPath.path)
                    
                    // check for audio files
                    let mp3Path = sessionsPath.appendingPathComponent("mixed_\(sessionTimestamp).mp3")
                    let wavPath = sessionsPath.appendingPathComponent("mixed_\(sessionTimestamp).wav")
                    let audioURL = FileManager.default.fileExists(atPath: mp3Path.path) ? mp3Path :
                                  FileManager.default.fileExists(atPath: wavPath.path) ? wavPath : nil
                    
                    // create meeting entry with better title formatting
                    let sessionDate = metadata.sessionStartTime
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "MMM d, h:mm a"
                    let formattedDate = dateFormatter.string(from: sessionDate).lowercased()
                    
                    // if transcript exists, try to load it for better title
                    var title = hasTranscript ? "meeting \(formattedDate)" : "recording \(formattedDate)"
                    if hasTranscript {
                        if let transcriptData = try? Data(contentsOf: transcriptPath),
                           let transcripts = try? JSONDecoder().decode([TranscriptionResult].self, from: transcriptData),
                           let bestResult = transcripts.first {
                            // use AI-generated title if available
                            if let aiTitle = bestResult.transcript.title, !aiTitle.isEmpty {
                                title = aiTitle.lowercased()
                            }
                        }
                    }
                    
                    let meeting = Meeting(
                        timestamp: metadata.sessionStartTime,
                        duration: duration,
                        title: title,
                        speakerCount: metadata.micSegments.isEmpty ? 0 : 1,
                        audioFileURL: audioURL,
                        transcriptAvailable: hasTranscript
                    )
                    loadedMeetings.append(meeting)
                } catch {
                    // skip files with sandbox/authenticator issues silently
                    let nsError = error as NSError
                    if nsError.code == 81 || nsError.domain == "NSPOSIXErrorDomain" {
                        // code 81 = "Need authenticator" - sandbox issue, skip silently
                        continue
                    }
                    print("❌ failed to load \(metadataFile.lastPathComponent): \(error)")
                }
            }
        }
        
        // no longer load from legacy transcription-results.json since it gets overwritten
        // all meetings are now loaded from session-specific metadata files above
        
        // remove duplicates (in case a meeting was added during recording)
        var uniqueMeetings: [Date: Meeting] = [:]
        for meeting in loadedMeetings {
            uniqueMeetings[meeting.timestamp] = meeting
        }
        
        // sort by most recent first
        meetings = uniqueMeetings.values.sorted { $0.timestamp > $1.timestamp }
    }
    
    func startNewMeeting() {
        print("🚀 startNewMeeting called")
        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0
        
        // start timer immediately (before async recording setup)
        print("⏰ creating timer on thread: \(Thread.current)")
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if let start = self.recordingStartTime {
                    let duration = Date().timeIntervalSince(start)
                    self.logTimerUpdateIfNeeded(duration)
                    self.recordingDuration = duration
                }
            }
        }
        print("⏰ timer created: \(recordingTimer != nil)")
        
        // start recording
        Task { @MainActor in
            print("🎙️ starting recorders...")
            print("📱 device monitor active: \(deviceMonitor.isMonitoring)")
            
            // device monitoring is already running from init, no need to restart
            
            // generate shared session id for both recorders
            let sharedSessionID = UUID().uuidString
            print("🎬 starting recording with shared session id: \(sharedSessionID)")
            
            // start both recorders with same session id
            // CRITICAL: both MUST be awaited to maintain proper async context
            // missing await causes timing issues and robotic audio with AirPods
            await micRecorder.startSession(sharedSessionID: sharedSessionID)
            print("🎙️ mic recorder started: \(micRecorder.isRecording)")
            
            await systemRecorder.startSession(sharedSessionID: sharedSessionID)
            print("🔊 system recorder started: \(systemRecorder.isRecording)")
            
            print("🎬 segmented recording started")
        }
    }

    private var lastLoggedSeconds: Int = -1

    private func logTimerUpdateIfNeeded(_ duration: TimeInterval) {
        let seconds = Int(duration)
        guard seconds != lastLoggedSeconds, seconds % 15 == 0 else { return }
        lastLoggedSeconds = seconds
        print("⏱️ timer update: \(duration)s")
    }
    
    func endMeeting() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        Task {
            // stop both recorders
            micRecorder.endSession()
            await systemRecorder.endSession()
            print("🎬 recording ended - segments saved")
            
            // stop device monitoring after recording
            deviceMonitor.stopMonitoring()
            print("📱 device monitoring stopped")
            
            // reload meetings to show the new recording
            loadMeetings()

            // capture the current meeting for status updates
            if let start = recordingStartTime {
                processingMeetingID = meetings.first { abs($0.timestamp.timeIntervalSince(start)) < 1 }?.id
                if let processingMeetingID,
                   let index = meetings.firstIndex(where: { $0.id == processingMeetingID }) {
                    meetings[index].title = "mixing audio..."
                    meetings[index].processingStatus = "mixing audio segments"
                } else {
                    print("⚠️ unable to locate meeting entry for live status updates")
                }
            }

            // get the session timestamp for mixing
            let sessionTimestamp = micRecorder.currentSessionTimestamp

            guard sessionTimestamp > 0 else {
                print("❌ no valid session timestamp - recording may have failed")
                if let processingMeetingID,
                   let index = meetings.firstIndex(where: { $0.id == processingMeetingID }) {
                    meetings[index].processingStatus = "error: no session timestamp"
                }
                processingMeetingID = nil
                return
            }

            print("🎵 starting audio mixing for session \(sessionTimestamp)")
            let mixingSucceeded = await runMixingScript(timestamp: sessionTimestamp)

            if mixingSucceeded {
                updateProcessingTitle("transcribing...")
                updateProcessingStatus("starting transcription")
                await processRecording(sessionTimestamp: sessionTimestamp)
            } else {
                updateProcessingStatus("error: mixing failed")
            }
        }
    }

    private func runMixingScript(timestamp: Int) async -> Bool {
        guard let scriptURL = resolveMixingScriptURL() else {
            print("❌ mixing script not found")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [scriptURL.path, String(timestamp)]

        // capture output
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // read output
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("mixing output:\n\(output)")
            }

            if process.terminationStatus == 0 {
                print("✅ audio mixing completed successfully")
                return true
            } else {
                print("❌ mixing failed with status: \(process.terminationStatus)")
            }
        } catch {
            print("❌ failed to run mixing script: \(error)")
        }

        return false
    }

    @MainActor
    private func processRecording(sessionTimestamp: Int) async {
        // get the recordings directory (where files are actually saved)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsPath = documentsPath.appendingPathComponent("ai&i-recordings")

        // for now, all files are in the root recordings folder, not in session subdirectories
        let sessionDir = recordingsPath
        
        guard FileManager.default.fileExists(atPath: sessionDir.path) else {
            print("❌ session directory not found: \(sessionDir.path)")
            return
        }
        
        // wait for mixed audio file (named mixed_<sessionTimestamp>.wav)
        let mixedPath = sessionDir.appendingPathComponent("mixed_\(sessionTimestamp).wav")
        var attempts = 0
        while !FileManager.default.fileExists(atPath: mixedPath.path) && attempts < 30 {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            attempts += 1
        }
        
        // run transcription
        if FileManager.default.fileExists(atPath: mixedPath.path) {
            // convert to mp3 first (required for transcription services!)
            updateProcessingStatus("converting to mp3...")

            let mp3URL = mixedPath.deletingPathExtension().appendingPathExtension("mp3")

            // find ffmpeg (check both Apple Silicon and Intel paths)
            let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            guard let ffmpegPath = ffmpegPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                print("❌ ffmpeg not found")
                updateProcessingStatus("error: ffmpeg not installed")
                return
            }
            
            // use ffmpeg to convert wav to mp3
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = [
                "-i", mixedPath.path,
                "-b:a", "128k",     // 128kbps bitrate
                "-ar", "16000",     // 16khz sample rate (optimal for speech)
                "-ac", "1",         // mono
                "-y",               // overwrite if exists
                mp3URL.path
            ]
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    print("✅ converted to mp3: \(mp3URL.lastPathComponent)")
                    // use transcription with individual service updates
                    await transcribeWithProgress(audioURL: mp3URL, sessionDir: sessionDir, sessionTimestamp: sessionTimestamp)
                } else {
                    print("❌ mp3 conversion failed")
                    updateProcessingStatus("error: mp3 conversion failed")
                }
            } catch {
                print("❌ failed to convert to mp3: \(error)")
                updateProcessingStatus("error: mp3 conversion failed")
            }
        } else {
            updateProcessingStatus("error: no mixed audio")
        }

        processingMeetingID = nil
    }

    private func transcribeWithProgress(audioURL: URL, sessionDir: URL, sessionTimestamp: Int) async {
        // create services
        let serviceFactories: [(name: String, loader: () -> TranscriptionService?)] = [
            ("gemini", { GeminiTranscriptionService.createFromEnvironment() }),
            ("deepgram", { DeepgramTranscriptionService.createFromEnvironment() }),
            ("assembly", { AssemblyAITranscriptionService.createFromEnvironment() })
        ]
        
        var configuredServices: [(name: String, service: TranscriptionService)] = []
        var unavailableServices: [String] = []
        
        for entry in serviceFactories {
            if let service = entry.loader() {
                configuredServices.append((entry.name, service))
            } else {
                unavailableServices.append(entry.name)
            }
        }

        if !unavailableServices.isEmpty {
            let missingList = unavailableServices.joined(separator: ", ")
            await MainActor.run {
                self.updateProcessingStatus("missing keys for \(missingList)")
            }
        }

        guard !configuredServices.isEmpty else {
            await MainActor.run {
                self.updateProcessingStatus("no transcription services configured")
            }
            return
        }

        await MainActor.run {
            self.updateProcessingStatus("transcribing with \(configuredServices.map { $0.name }.joined(separator: ", "))")
        }

        var results: [TranscriptionResult] = []
        var completedServices: [String] = []

        await withTaskGroup(of: (String, TranscriptionResult?).self) { group in
            for entry in configuredServices {
                group.addTask {
                    do {
                        let result = try await entry.service.transcribe(audioURL: audioURL)
                        print("✅ \(entry.name) transcription complete")
                        return (entry.name, result)
                    } catch {
                        print("❌ \(entry.name) transcription failed: \(error)")
                        return (entry.name, nil)
                    }
                }
            }
            
            for await (service, result) in group {
                if let result = result {
                    results.append(result)
                    completedServices.append(service)

                    let statusText = completedServices.joined(separator: ", ") + " done"
                    let remainingCount = configuredServices.count - completedServices.count
                    let finalStatus = remainingCount > 0
                        ? "\(statusText), waiting for \(remainingCount) more..."
                        : "all services complete!"

                    await MainActor.run {
                        self.updateProcessingStatus(finalStatus)
                    }
                } else {
                    await MainActor.run {
                        self.updateProcessingStatus("\(service) failed, continuing...")
                    }
                }
            }
        }

        // save results with session-specific filename to prevent data loss
        if !results.isEmpty {
            // save with session timestamp to prevent overwriting
            let sessionSpecificPath = sessionDir.appendingPathComponent("session_\(sessionTimestamp)_transcripts.json")
            if let data = try? JSONEncoder().encode(results) {
                try? data.write(to: sessionSpecificPath)
                print("💾 saved \(results.count) transcription results to \(sessionSpecificPath.lastPathComponent)")
            }
            
            // no longer saving to legacy transcription-results.json to prevent overwrites
            
            // reload to show completed transcript
            await MainActor.run {
                loadMeetings()
            }
        } else {
            print("❌ all transcription services failed!")
            await MainActor.run {
                self.updateProcessingStatus("transcription failed - check console")
            }
        }

        await MainActor.run {
            self.processingMeetingID = nil
        }
    }

    private func resolveMixingScriptURL() -> URL? {
        let fileManager = FileManager.default
        let env = ProcessInfo.processInfo.environment

        if let envPath = env["AI_AND_I_MIX_SCRIPT"], !envPath.isEmpty {
            let candidate = URL(fileURLWithPath: envPath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        let homeScript = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("ai-and-i/native/Scripts/mix-audio.swift")
        if fileManager.fileExists(atPath: homeScript.path) {
            return homeScript
        }

        let currentDirectoryScript = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("native/Scripts/mix-audio.swift")
        if fileManager.fileExists(atPath: currentDirectoryScript.path) {
            return currentDirectoryScript
        }

        if let bundleScript = Bundle.main.url(forResource: "mix-audio", withExtension: "swift"),
           fileManager.fileExists(atPath: bundleScript.path) {
            return bundleScript
        }

        return nil
    }

    private func updateProcessingStatus(_ status: String) {
        guard let processingMeetingID,
              let index = meetings.firstIndex(where: { $0.id == processingMeetingID }) else { return }
        meetings[index].processingStatus = status
    }

    private func updateProcessingTitle(_ title: String) {
        guard let processingMeetingID,
              let index = meetings.firstIndex(where: { $0.id == processingMeetingID }) else { return }
        meetings[index].title = title
    }
    
    var filteredMeetings: [Meeting] {
        if searchText.isEmpty {
            return meetings
        }
        return meetings.filter { 
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var groupedMeetings: [(String, [Meeting])] {
        let grouped = Dictionary(grouping: filteredMeetings) { $0.daySection }
        return grouped.sorted { first, second in
            // sort by most recent first
            guard let firstMeeting = first.value.first,
                  let secondMeeting = second.value.first else { return false }
            return firstMeeting.timestamp > secondMeeting.timestamp
        }
    }
}

// MARK: - main view

struct MeetingsListView: View {
    @StateObject private var viewModel = MeetingsListViewModel()
    @State private var showingRecordingView = false
    @State private var selectedMeeting: Meeting?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // background
                Color.nyuhakushoku
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // header
                    headerView
                    
                    // content
                    ScrollView {
                        VStack(spacing: Spacing.gapLarge) {
                            // start meeting button
                            startMeetingButton
                                .frame(maxWidth: 400)
                            
                            // meetings list
                            meetingsList
                        }
                        .frame(maxWidth: 600)
                        .padding(Spacing.margins)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationDestination(item: $selectedMeeting) { meeting in
                TranscriptDetailView(meeting: meeting)
            }
            .sheet(isPresented: $showingRecordingView) {
                RecordingView(viewModel: viewModel)
            }
        }
    }
    
    // MARK: - subviews
    
    private var headerView: some View {
        // thin strip with traffic lights
        Rectangle()
            .fill(Color.nyuhakushoku)
            .frame(height: 28)
            .overlay(
                HStack {
                    Text("⌘+s to save locally")
                        .font(.system(size: 11))
                        .foregroundColor(.usugrey)
                        .lowercased()
                    Spacer()
                }
                .padding(.horizontal, Spacing.margins)
            )
    }
    
    private var startMeetingButton: some View {
        Button(action: {
            showingRecordingView = true
            viewModel.startNewMeeting()
        }) {
            HStack {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                Text("start a new meeting")
                    .lowercased()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
    
    private var meetingsList: some View {
        VStack(alignment: .leading, spacing: Spacing.gapLarge) {
            ForEach(viewModel.groupedMeetings, id: \.0) { section, meetings in
                VStack(alignment: .leading, spacing: Spacing.gapSmall) {
                    // section header
                    Text(section)
                        .font(Typography.metadata)
                        .foregroundColor(.hai)
                        .lowercased()
                    
                    Divider()
                        .overlay(Color.hai.opacity(0.2))
                    
                    // meetings in section
                    ForEach(meetings) { meeting in
                        meetingRow(meeting)
                    }
                }
            }
        }
    }
    
    private func meetingRow(_ meeting: Meeting) -> some View {
        Button(action: {
            if meeting.transcriptAvailable {
                selectedMeeting = meeting
            }
        }) {
            HStack {
                Text("&i")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(meeting.transcriptAvailable ? Color.hai : Color.usugrey)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(Typography.transcript)
                        .foregroundColor(.sumi)
                        .lowercased()
                    
                    if let status = meeting.processingStatus {
                        Text(status)
                            .font(Typography.timestamp)
                            .foregroundColor(.hai)
                            .lowercased()
                    } else if meeting.speakerCount > 0 {
                        Text("\(meeting.speakerCount) speakers")
                            .font(Typography.timestamp)
                            .foregroundColor(.hai)
                            .lowercased()
                    }
                }
                
                Spacer()
                
                Text(meeting.formattedDuration)
                    .font(Typography.metadata)
                    .foregroundColor(.hai)
                    .lowercased()
            }
            .padding(.vertical, Spacing.gapSmall)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            if hovering && meeting.transcriptAvailable {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - recording view

struct RecordingView: View {
    @ObservedObject var viewModel: MeetingsListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEndConfirmation = false
    
    var formattedDuration: String {
        let minutes = Int(viewModel.recordingDuration / 60)
        let seconds = Int(viewModel.recordingDuration.truncatingRemainder(dividingBy: 60))
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ZStack {
            Color.kinari
                .ignoresSafeArea()
            
            VStack(spacing: Spacing.gapLarge * 2) {
                // header
                HStack {
                    Button("← back") {
                        // don't stop recording, just dismiss view
                        dismiss()
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.hai)
                    .lowercased()
                    
                    Spacer()
                    
                    Text("ai & i")
                        .font(Typography.title)
                        .foregroundColor(.sumi)
                        .lowercased()
                    
                    Spacer()
                    
                    // invisible spacer for balance
                    Text("← back")
                        .opacity(0)
                }
                .padding(.horizontal, Spacing.margins)
                .padding(.top, Spacing.margins)
                
                Spacer()
                
                // recording indicator
                VStack(spacing: Spacing.gapLarge) {
                    Text("recording")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.hai)
                        .lowercased()
                    
                    Text(formattedDuration)
                        .font(.system(size: 36, weight: .light, design: .monospaced))
                        .foregroundColor(.hai.opacity(0.8))
                    
                    // audio wave animation
                    AudioWaveView()
                        .frame(height: 60)
                        .padding(.horizontal, 60)
                }
                
                Spacer()
                
                // end meeting button
                Button(action: {
                    showingEndConfirmation = true
                }) {
                    Text("end meeting")
                        .lowercased()
                        .frame(width: 200)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, Spacing.margins * 2)
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .alert("end meeting?", isPresented: $showingEndConfirmation) {
            Button("cancel", role: .cancel) {}
            Button("end meeting", role: .destructive) {
                viewModel.endMeeting()
                dismiss()
                // TODO: trigger transcription
            }
        } message: {
            Text("are you sure you want to end this recording?")
                .lowercased()
        }
    }
}

// MARK: - audio wave animation

struct AudioWaveView: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<20) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.hai.opacity(0.3))
                    .frame(width: 2)
                    .scaleEffect(y: animating ? Double.random(in: 0.3...1.0) : 0.5)
                    .animation(
                        .easeInOut(duration: Double.random(in: 0.4...0.8))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.05),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - preview

#Preview {
    MeetingsListView()
}
