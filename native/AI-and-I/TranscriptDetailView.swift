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
                        .frame(maxWidth: 800)
                        .padding(Spacing.margins)
                    }
                    .frame(maxWidth: .infinity)
                }
                
            }
            
            // floating action tray - always visible
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    floatingActionTray
                        .padding(.trailing, Spacing.margins * 2)
                        .padding(.bottom, Spacing.margins * 2)
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
            // breadcrumb
            HStack(spacing: 4) {
                Button(action: { dismiss() }) {
                    Text("meetings")
                        .font(.system(size: 12))
                        .foregroundColor(.hai)
                        .lowercased()
                }
                .buttonStyle(PlainButtonStyle())
                
                Text("/")
                    .font(.system(size: 12))
                    .foregroundColor(.usugrey)
                
                Text(meeting.title)
                    .font(.system(size: 12))
                    .foregroundColor(.sumi)
                    .lowercased()
            }
            
            Spacer()
        }
        .frame(maxWidth: 800)
        .padding(.horizontal, Spacing.margins)
        .padding(.vertical, Spacing.gapSmall)
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
        VStack(spacing: Spacing.gapSmall) {
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
        .padding(Spacing.gapSmall)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.gofun)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
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
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(segment.speaker == .me ? .speakerMe : .speakerOther)
                .frame(width: 60, alignment: .trailing)
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
        guard let audioURL = meeting.audioFileURL else { return }
        
        // get session directory from audio path
        let sessionDir = audioURL.deletingLastPathComponent()
        let resultsPath = sessionDir.appendingPathComponent("transcription-results.json")
        
        // load transcription results
        if let data = try? Data(contentsOf: resultsPath),
           let results = try? JSONDecoder().decode([TranscriptionResult].self, from: data),
           let bestResult = results.first {
            
            // load segments from best result
            segments = bestResult.transcript.segments
            cost = bestResult.cost
            serviceName = bestResult.service
            
            // check for admin mode
            isAdminMode = UserDefaults.standard.bool(forKey: "adminMode")
        } else {
            // fallback to empty
            segments = []
            cost = nil
            serviceName = "unknown"
        }
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