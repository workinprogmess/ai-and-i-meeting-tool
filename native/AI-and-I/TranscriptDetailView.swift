//
//  TranscriptDetailView.swift
//  AI-and-I
//
//  beautiful minimal transcript view with speaker attribution
//

import SwiftUI

// MARK: - transcript detail view

struct TranscriptDetailView: View {
    let meeting: Meeting
    @StateObject private var viewModel = TranscriptDetailViewModel()
    @State private var selectedText: String = ""
    @State private var showingActions = false
    @State private var showingCorrection = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // background
            Color.kinari
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // header
                headerView
                
                // transcript content
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // meeting metadata
                            metadataView
                            
                            Divider()
                                .overlay(Color.hai.opacity(0.2))
                                .padding(.vertical, Spacing.gapMedium)
                            
                            // transcript segments
                            ForEach(viewModel.segments) { segment in
                                TranscriptSegmentView(
                                    segment: segment,
                                    onTextSelected: { text in
                                        selectedText = text
                                        showingCorrection = true
                                    }
                                )
                            }
                        }
                        .padding(Spacing.margins)
                    }
                }
                
                // floating action tray
                if showingActions {
                    floatingActionTray
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .onAppear {
            viewModel.loadTranscript(for: meeting)
        }
        .sheet(isPresented: $showingCorrection) {
            CorrectionView(isPresented: $showingCorrection, text: selectedText)
        }
    }
    
    // MARK: - subviews
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("back")
                }
                .foregroundColor(.hai)
                .lowercased()
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            Text(meeting.title)
                .font(Typography.title)
                .foregroundColor(.sumi)
                .lowercased()
            
            Spacer()
            
            // actions button
            Button(action: { 
                withAnimation(.standard) {
                    showingActions.toggle()
                }
            }) {
                Image(systemName: showingActions ? "xmark" : "ellipsis")
                    .foregroundColor(.hai)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, Spacing.margins)
        .padding(.vertical, Spacing.gapMedium)
        .background(Color.kinari)
    }
    
    private var metadataView: some View {
        VStack(alignment: .leading, spacing: Spacing.gapSmall) {
            // date and duration
            HStack {
                Text(meeting.formattedDate)
                    .font(Typography.metadata)
                    .foregroundColor(.hai)
                
                Text("•")
                    .foregroundColor(.usugrey)
                
                Text(meeting.formattedDuration)
                    .font(Typography.metadata)
                    .foregroundColor(.hai)
                
                if meeting.speakerCount > 0 {
                    Text("•")
                        .foregroundColor(.usugrey)
                    
                    Text("\(meeting.speakerCount) speakers")
                        .font(Typography.metadata)
                        .foregroundColor(.hai)
                }
            }
            .lowercased()
            
            // service info (if admin mode)
            if viewModel.isAdminMode {
                HStack {
                    Text("transcribed by")
                        .font(Typography.metadata)
                        .foregroundColor(.usugrey)
                    
                    Text(viewModel.serviceName)
                        .font(Typography.metadata)
                        .foregroundColor(.hai)
                    
                    if let cost = viewModel.cost {
                        Text("•")
                            .foregroundColor(.usugrey)
                        
                        Text(String(format: "$%.3f", cost))
                            .font(Typography.metadata)
                            .foregroundColor(.hai)
                    }
                }
                .lowercased()
            }
        }
    }
    
    private var floatingActionTray: some View {
        HStack(spacing: Spacing.gapLarge) {
            // link/share
            FloatingActionButton(icon: "link") {
                viewModel.shareTranscript()
            }
            
            // copy
            FloatingActionButton(icon: "doc.on.doc") {
                viewModel.copyTranscript()
            }
            
            // export
            FloatingActionButton(icon: "square.and.arrow.up") {
                viewModel.exportTranscript()
            }
            
            // corrections
            FloatingActionButton(icon: "pencil") {
                showingCorrection = true
            }
        }
        .padding(Spacing.gapMedium)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gofun)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        )
        .padding(.bottom, Spacing.margins)
    }
}

// MARK: - segment view

struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let onTextSelected: (String) -> Void
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.gapMedium) {
            // speaker label
            Text(segment.speakerLabel)
                .font(Typography.speakerLabel)
                .foregroundColor(segment.speaker == .me ? .hai : .sumi)
                .frame(width: 80, alignment: .trailing)
                .lowercased()
            
            // transcript text
            Text(segment.text)
                .font(Typography.transcript)
                .foregroundColor(.sumi)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(4)
                .textSelection(.enabled)
                .onHover { hovering in
                    isHovering = hovering
                }
                .background(
                    isHovering ? Color.hover : Color.clear
                )
                .onTapGesture {
                    onTextSelected(segment.text)
                }
            
            // timestamp (if available)
            if let timestamp = segment.timestamp {
                Text(formatTimestamp(timestamp))
                    .font(Typography.timestamp)
                    .foregroundColor(.usugrey)
                    .lowercased()
            }
        }
        .padding(.vertical, Spacing.gapSmall)
    }
    
    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - view model

@MainActor
class TranscriptDetailViewModel: ObservableObject {
    @Published var segments: [TranscriptSegment] = []
    @Published var isAdminMode = false
    @Published var serviceName = "gemini"
    @Published var cost: Double?
    
    func loadTranscript(for meeting: Meeting) {
        // load from saved transcript files
        // for now, use mock data
        segments = [
            TranscriptSegment(
                speaker: .me,
                text: "hey everyone, thanks for joining the standup. let's go around and share updates.",
                timestamp: 0,
                confidence: 0.95
            ),
            TranscriptSegment(
                speaker: .other("sarah"),
                text: "sure! i finished the authentication flow yesterday. the login and signup are both working with email verification.",
                timestamp: 8,
                confidence: 0.92
            ),
            TranscriptSegment(
                speaker: .other("sarah"),
                text: "today i'm starting on the password reset functionality. should have that done by end of day.",
                timestamp: 18,
                confidence: 0.94
            ),
            TranscriptSegment(
                speaker: .me,
                text: "awesome, that's great progress. any blockers?",
                timestamp: 25,
                confidence: 0.96
            ),
            TranscriptSegment(
                speaker: .other("sarah"),
                text: "nope, all good on my end.",
                timestamp: 28,
                confidence: 0.93
            ),
            TranscriptSegment(
                speaker: .other("alex"),
                text: "i've been working on the api integration. ran into some cors issues yesterday but got them resolved.",
                timestamp: 32,
                confidence: 0.91
            ),
            TranscriptSegment(
                speaker: .other("alex"),
                text: "the endpoints for user data and settings are complete. working on the analytics endpoints today.",
                timestamp: 40,
                confidence: 0.90
            ),
            TranscriptSegment(
                speaker: .me,
                text: "nice. make sure to add proper error handling for those analytics calls.",
                timestamp: 48,
                confidence: 0.95
            ),
            TranscriptSegment(
                speaker: .other("alex"),
                text: "will do. i'll add retry logic and fallback behavior.",
                timestamp: 52,
                confidence: 0.92
            )
        ]
        
        // calculate cost based on duration
        cost = meeting.duration * 0.002 / 60 // $0.002 per minute for gemini
    }
    
    func shareTranscript() {
        // implement share functionality
        print("sharing transcript...")
    }
    
    func copyTranscript() {
        // copy all transcript text to clipboard
        let fullText = segments.map { segment in
            "\(segment.speakerLabel): \(segment.text)"
        }.joined(separator: "\n\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)
    }
    
    func exportTranscript() {
        // export as markdown or text file
        print("exporting transcript...")
    }
}

// MARK: - transcript segment model extension

extension TranscriptSegment {
    var speakerLabel: String {
        switch speaker {
        case .me:
            return "@me"
        case .other(let name):
            return "@\(name)"
        }
    }
}

// MARK: - preview

#Preview {
    TranscriptDetailView(meeting: Meeting(
        timestamp: Date(),
        duration: 45 * 60,
        title: "team standup",
        speakerCount: 3,
        audioFileURL: nil,
        transcriptAvailable: true
    ))
}