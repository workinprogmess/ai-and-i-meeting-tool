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
    @State private var selectedServiceIndex = 0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // background - silk white kneading
            Color.shironeri
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // header
                headerView
                
                // service selector tabs and metrics
                if !viewModel.allResults.isEmpty {
                    serviceControlsView
                        .padding(.horizontal, Spacing.margins)
                        .padding(.vertical, Spacing.gapMedium)
                }
                
                // transcript content
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
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
            selectedServiceIndex = 0
            viewModel.loadTranscript(for: meeting)
        }
        .sheet(isPresented: $showingCorrection) {
            CorrectionView(isPresented: $showingCorrection, text: selectedText)
        }
    }
    
    // MARK: - subviews
    
    private var serviceControlsView: some View {
        VStack(spacing: Spacing.gapMedium) {
            // service selector tabs - gemini, deepgram, assembly
            HStack(spacing: 0) {
                ForEach(Array(viewModel.allResults.enumerated()), id: \.offset) { index, result in
                    Button(action: {
                        selectedServiceIndex = index
                    }) {
                        Text(result.service.lowercased())
                            .font(.system(size: 14, weight: selectedServiceIndex == index ? .semibold : .regular))
                            .foregroundColor(selectedServiceIndex == index ? .sumi : .hai)
                            .frame(height: 36)
                            .frame(maxWidth: .infinity)
                            .background(selectedServiceIndex == index ? Color.shironeri : Color.clear)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .frame(maxWidth: 400)
            .padding(3)
            .background(Color.nyuhakushoku)
            .cornerRadius(8)
            .onChange(of: selectedServiceIndex) { _, newIndex in
                viewModel.selectService(at: newIndex)
            }
            
            // metrics for selected service
            if selectedServiceIndex < viewModel.allResults.count {
                let result = viewModel.allResults[selectedServiceIndex]
                HStack(spacing: Spacing.gapLarge) {
                    // processing time
                    VStack(spacing: 2) {
                        Text("time")
                            .font(.system(size: 10))
                            .foregroundColor(.usugrey)
                        Text(String(format: "%.1fs", result.processingTime))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.hai)
                    }
                    
                    // cost
                    VStack(spacing: 2) {
                        Text("cost")
                            .font(.system(size: 10))
                            .foregroundColor(.usugrey)
                        Text(String(format: "$%.4f", result.cost))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.hai)
                    }
                    
                    // word count
                    VStack(spacing: 2) {
                        Text("words")
                            .font(.system(size: 10))
                            .foregroundColor(.usugrey)
                        Text("\(result.transcript.wordCount)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.hai)
                    }
                    
                    // confidence if available
                    if let confidence = result.confidence {
                        VStack(spacing: 2) {
                            Text("confidence")
                                .font(.system(size: 10))
                                .foregroundColor(.usugrey)
                            Text(String(format: "%.0f%%", confidence * 100))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(confidence > 0.9 ? .hai : .usugrey)
                        }
                    }
                }
                .frame(maxWidth: 400)
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 0) {
            // thin strip with traffic lights
            Rectangle()
                .fill(Color.nyuhakushoku)
                .frame(height: 28)
                .ignoresSafeArea(edges: .top)
            
            // meeting title as main heading
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: { dismiss() }) {
                        Text("← back to meetings")
                            .font(.system(size: 12))
                            .foregroundColor(.hai)
                            .lowercased()
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(meeting.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.sumi)
                        .lowercased()
                }
                
                Spacer()
            }
            .frame(maxWidth: 800)
            .padding(.horizontal, Spacing.margins)
            .padding(.top, Spacing.gapSmall)
            .padding(.bottom, Spacing.gapMedium)
        }
        .background(Color.shironeri)
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
            
            // service info
            HStack {
                Text("transcribed by")
                    .font(Typography.metadata)
                    .foregroundColor(.usugrey)
                
                Text(viewModel.serviceName)
                    .font(Typography.metadata)
                    .foregroundColor(.hai)
            }
            .lowercased()
        }
    }
    
    private var floatingActionTray: some View {
        HStack(spacing: Spacing.gapLarge) {
            // link/share
            Button(action: { viewModel.shareTranscript() }) {
                Image(systemName: "link")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.hai)
            }
            .buttonStyle(PlainButtonStyle())
            
            // copy
            Button(action: { viewModel.copyTranscript() }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.hai)
            }
            .buttonStyle(PlainButtonStyle())
            
            // export
            Button(action: { viewModel.exportTranscript() }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.hai)
            }
            .buttonStyle(PlainButtonStyle())
            
            // corrections
            Button(action: { showingCorrection = true }) {
                Image(systemName: "pencil")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.hai)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, Spacing.gapLarge)
        .padding(.vertical, Spacing.gapMedium)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.soshoku)
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
                .frame(width: 80, alignment: .trailing)  // increased width to prevent wrapping
                .lineLimit(1)  // prevent wrapping to next line
                .lowercased()
            
            // transcript text (lowercase)
            Text(segment.text.lowercased())
                .font(Typography.transcript)
                .foregroundColor(.sumi)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(4)
                .textSelection(.enabled)
                .onHover { hovering in
                    isHovering = hovering
                }
                .padding(.horizontal, isHovering ? 4 : 0)
                .padding(.vertical, isHovering ? 2 : 0)
                .background(
                    RoundedRectangle(cornerRadius: isHovering ? 4 : 0)
                        .fill(isHovering ? Color.soshoku.opacity(0.3) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: isHovering)
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
    @Published var allResults: [TranscriptionResult] = []
    @Published var serviceName = "gemini"
    @Published var cost: Double?
    
    func loadTranscript(for meeting: Meeting) {
        let sessionDirectory: URL
        if let audioURL = meeting.audioFileURL {
            sessionDirectory = audioURL.deletingLastPathComponent()
        } else {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            sessionDirectory = documentsPath.appendingPathComponent("ai&i-recordings")
        }

        let resultsPath = sessionDirectory.appendingPathComponent("session_\(meeting.sessionID)_transcripts.json")

        guard let data = try? Data(contentsOf: resultsPath),
              let results = try? JSONDecoder().decode([TranscriptionResult].self, from: data),
              !results.isEmpty else {
            allResults = []
            segments = []
            cost = nil
            serviceName = "unknown"
            return
        }

        allResults = results
        let firstResult = results[0]
        segments = firstResult.transcript.segments
        cost = firstResult.cost
        serviceName = firstResult.service
    }
    
    func selectService(at index: Int) {
        guard index < allResults.count else { return }
        
        let selected = allResults[index]
        segments = selected.transcript.segments
        cost = selected.cost
        serviceName = selected.service
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
        transcriptAvailable: true,
        processingStatus: nil,
        sessionID: "preview"
    ))
}
