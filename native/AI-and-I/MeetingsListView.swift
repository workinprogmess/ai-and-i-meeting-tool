//
//  MeetingsListView.swift
//  AI-and-I
//
//  main landing page showing all past meetings
//

import SwiftUI

// MARK: - data models

struct Meeting: Identifiable, Codable, Hashable {
    let id = UUID()
    let timestamp: Date
    let duration: TimeInterval
    let title: String
    let speakerCount: Int
    let audioFileURL: URL?
    let transcriptAvailable: Bool
    
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
    
    // recording components from ContentView
    private let micRecorder = MicRecorder()
    private let systemRecorder = SystemAudioRecorder()
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    init() {
        loadMeetings()
    }
    
    func loadMeetings() {
        // load from documents folder
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let aiAndIPath = documentsPath.appendingPathComponent("ai-and-i")
        let sessionsPath = aiAndIPath.appendingPathComponent("sessions")
        
        // find all session folders
        guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
            at: sessionsPath,
            includingPropertiesForKeys: nil
        ) else {
            meetings = []
            return
        }
        
        // load transcripts from each session
        var loadedMeetings: [Meeting] = []
        for sessionDir in sessionDirs {
            // look for transcription results
            let resultsPath = sessionDir.appendingPathComponent("transcription-results.json")
            if let data = try? Data(contentsOf: resultsPath),
               let results = try? JSONDecoder().decode([TranscriptionResult].self, from: data),
               let bestResult = results.first {
                
                // extract title from first few words or use "untitled"
                let title = bestResult.transcript.segments.first?.text
                    .split(separator: " ")
                    .prefix(4)
                    .joined(separator: " ")
                    .lowercased() ?? "untitled meeting"
                
                // count unique speakers
                let speakers = Set(bestResult.transcript.segments.map { $0.speaker })
                
                let meeting = Meeting(
                    timestamp: bestResult.createdAt,
                    duration: bestResult.transcript.duration,
                    title: title,
                    speakerCount: speakers.count,
                    audioFileURL: sessionDir.appendingPathComponent("mixed.mp3"),
                    transcriptAvailable: true
                )
                loadedMeetings.append(meeting)
            }
        }
        
        // sort by most recent first
        meetings = loadedMeetings.sorted { $0.timestamp > $1.timestamp }
    }
    
    func startNewMeeting() {
        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0
        
        // start timer to update duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let start = self.recordingStartTime {
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
        
        // start both recorders (from ContentView logic)
        Task {
            micRecorder.startSession()
            await systemRecorder.startSession()
            print("🎬 segmented recording started")
        }
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
            
            // get the session timestamp for mixing
            let sessionTimestamp = micRecorder.currentSessionTimestamp
            
            // run the mixing script
            print("🎵 starting audio mixing for session \(sessionTimestamp)")
            await runMixingScript(timestamp: sessionTimestamp)
            
            // create new meeting entry
            if let start = recordingStartTime {
                let meeting = Meeting(
                    timestamp: start,
                    duration: recordingDuration,
                    title: "processing...",
                    speakerCount: 0,
                    audioFileURL: nil,
                    transcriptAvailable: false
                )
                await MainActor.run {
                    meetings.insert(meeting, at: 0)
                }
                
                // wait for mixing to complete, then transcribe
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await processRecording(for: meeting)
            }
        }
    }
    
    private func runMixingScript(timestamp: Int) async {
        // path to the mixing script
        let scriptPath = "/Users/workinprogmess/ai-and-i/native/AI-and-I/mix-audio.swift"
        
        // run the swift script with the timestamp
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = [scriptPath, String(timestamp)]
        
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
            } else {
                print("❌ mixing failed with status: \(process.terminationStatus)")
            }
        } catch {
            print("❌ failed to run mixing script: \(error)")
        }
    }
    
    @MainActor
    private func processRecording(for meeting: Meeting) async {
        // get the latest session directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sessionsPath = documentsPath.appendingPathComponent("ai-and-i").appendingPathComponent("sessions")
        
        // find the most recent session folder
        guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
            at: sessionsPath,
            includingPropertiesForKeys: [.creationDateKey]
        ).sorted(by: { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return date1 > date2
        }).first else { return }
        
        // wait for mixed audio file
        let mixedPath = sessionDirs.appendingPathComponent("mixed.wav")
        var attempts = 0
        while !FileManager.default.fileExists(atPath: mixedPath.path) && attempts < 30 {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            attempts += 1
        }
        
        // run transcription
        if FileManager.default.fileExists(atPath: mixedPath.path) {
            // use transcription coordinator to transcribe
            let coordinator = TranscriptionCoordinator()
            let results = await coordinator.transcribeWithAllServices(audioURL: mixedPath)
            
            // save results
            if !results.isEmpty {
                let resultsPath = sessionDirs.appendingPathComponent("transcription-results.json")
                if let data = try? JSONEncoder().encode(results) {
                    try? data.write(to: resultsPath)
                }
                
                // reload meetings to show the new transcript
                loadMeetings()
            }
        }
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
                Color.kinari
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
        HStack {
            // search on left
            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.hai)
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // logo centered
            Text("ai&i")
                .font(Typography.title)
                .foregroundColor(.sumi)
                .lowercased()
            
            Spacer()
            
            // settings on right
            Button(action: {}) {
                Image(systemName: "gearshape")
                    .foregroundColor(.hai)
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: 800)
        .padding(.horizontal, Spacing.margins)
        .padding(.vertical, Spacing.gapMedium)
        .background(Color.kinari)
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
                    
                    if meeting.speakerCount > 0 {
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