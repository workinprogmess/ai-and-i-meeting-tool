//
//  MeetingsListView.swift
//  AI-and-I
//
//  main landing page showing all past meetings
//

import SwiftUI

// MARK: - data models

struct Meeting: Identifiable, Codable {
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
    
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    
    init() {
        loadMeetings()
    }
    
    func loadMeetings() {
        // load from documents folder
        // for now, use mock data
        meetings = [
            Meeting(
                timestamp: Date(),
                duration: 45 * 60,
                title: "team standup",
                speakerCount: 3,
                audioFileURL: nil,
                transcriptAvailable: true
            ),
            Meeting(
                timestamp: Date().addingTimeInterval(-3600),
                duration: 23 * 60,
                title: "1:1 with sarah",
                speakerCount: 2,
                audioFileURL: nil,
                transcriptAvailable: true
            ),
            Meeting(
                timestamp: Date().addingTimeInterval(-86400),
                duration: 67 * 60,
                title: "design review",
                speakerCount: 5,
                audioFileURL: nil,
                transcriptAvailable: true
            ),
            Meeting(
                timestamp: Date().addingTimeInterval(-86400 * 2),
                duration: 52 * 60,
                title: "all hands",
                speakerCount: 12,
                audioFileURL: nil,
                transcriptAvailable: true
            )
        ]
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
    }
    
    func endMeeting() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
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
            meetings.insert(meeting, at: 0)
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
                            
                            // meetings list
                            meetingsList
                        }
                        .padding(Spacing.margins)
                    }
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
            Text("ai & i")
                .font(Typography.title)
                .foregroundColor(.sumi)
                .lowercased()
            
            Spacer()
            
            // search field (future)
            if !viewModel.meetings.isEmpty {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.hai)
                    .padding(.trailing, Spacing.gapSmall)
            }
            
            // settings
            Button(action: {}) {
                Image(systemName: "gearshape")
                    .foregroundColor(.hai)
            }
            .buttonStyle(PlainButtonStyle())
        }
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
                Circle()
                    .fill(meeting.transcriptAvailable ? Color.hai : Color.usugrey)
                    .frame(width: 6, height: 6)
                
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
                    Text("recording in progress")
                        .font(Typography.title)
                        .foregroundColor(.sumi)
                        .lowercased()
                    
                    Text(formattedDuration)
                        .font(.system(size: 48, weight: .light, design: .monospaced))
                        .foregroundColor(.sumi)
                    
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
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.hai.opacity(0.6))
                    .frame(width: 3)
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