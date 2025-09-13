//
//  CorrectionView.swift
//  AI-and-I
//
//  user corrections system for improving transcription accuracy
//

import SwiftUI

// MARK: - correction sheet

struct CorrectionView: View {
    @Binding var isPresented: Bool
    let originalText: String
    @State private var correctedText: String = ""
    @State private var correctionType: CorrectionType = .name
    @StateObject private var userDictionary = UserDictionaryManager.shared
    
    enum CorrectionType: String, CaseIterable {
        case name = "name"
        case company = "company"
        case phrase = "phrase"
        case general = "general"
        
        var icon: String {
            switch self {
            case .name: return "person"
            case .company: return "building.2"
            case .phrase: return "quote.bubble"
            case .general: return "pencil"
            }
        }
    }
    
    init(isPresented: Binding<Bool>, text: String) {
        self._isPresented = isPresented
        self.originalText = text
        self._correctedText = State(initialValue: text)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // header
            HStack {
                Text("make correction")
                    .font(Typography.title)
                    .foregroundColor(.sumi)
                    .lowercased()
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.hai)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(Spacing.margins)
            
            Divider()
                .overlay(Color.hai.opacity(0.2))
            
            // content
            VStack(alignment: .leading, spacing: Spacing.gapLarge) {
                // original text
                VStack(alignment: .leading, spacing: Spacing.gapSmall) {
                    Text("original")
                        .font(Typography.metadata)
                        .foregroundColor(.hai)
                        .lowercased()
                    
                    Text(originalText)
                        .font(Typography.transcript)
                        .foregroundColor(.usugrey)
                        .padding(Spacing.gapMedium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gofun)
                        .cornerRadius(6)
                }
                
                // corrected text
                VStack(alignment: .leading, spacing: Spacing.gapSmall) {
                    Text("corrected")
                        .font(Typography.metadata)
                        .foregroundColor(.hai)
                        .lowercased()
                    
                    TextEditor(text: $correctedText)
                        .font(Typography.transcript)
                        .foregroundColor(.sumi)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Color.gofun)
                        .cornerRadius(6)
                        .frame(minHeight: 60)
                }
                
                // correction type
                VStack(alignment: .leading, spacing: Spacing.gapSmall) {
                    Text("what type of correction?")
                        .font(Typography.metadata)
                        .foregroundColor(.hai)
                        .lowercased()
                    
                    HStack(spacing: Spacing.gapSmall) {
                        ForEach(CorrectionType.allCases, id: \.self) { type in
                            CorrectionTypeButton(
                                type: type,
                                isSelected: correctionType == type,
                                action: { correctionType = type }
                            )
                        }
                    }
                }
                
                // learned corrections preview
                if !userDictionary.recentCorrections.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.gapSmall) {
                        Text("recent corrections")
                            .font(Typography.metadata)
                            .foregroundColor(.hai)
                            .lowercased()
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Spacing.gapSmall) {
                                ForEach(Array(userDictionary.recentCorrections.enumerated()), id: \.offset) { _, correction in
                                    CorrectionChip(correction: correction)
                                }
                            }
                        }
                    }
                }
            }
            .padding(Spacing.margins)
            
            Spacer()
            
            // action buttons
            HStack(spacing: Spacing.gapMedium) {
                Button("cancel") {
                    isPresented = false
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("save correction") {
                    saveCorrection()
                    isPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(correctedText == originalText || correctedText.isEmpty)
            }
            .padding(Spacing.margins)
        }
        .frame(width: 500, height: 600)
        .background(Color.kinari)
    }
    
    private func saveCorrection() {
        // extract the specific correction
        let correction = UserCorrection(
            wrong: findDifference(original: originalText, corrected: correctedText).wrong,
            correct: findDifference(original: originalText, corrected: correctedText).correct,
            context: originalText,
            addedAt: Date()
        )
        
        userDictionary.addCorrection(correction)
        
        // add to appropriate category
        switch correctionType {
        case .name:
            userDictionary.addName(correction.correct)
        case .company:
            userDictionary.addCompany(correction.correct)
        case .phrase:
            userDictionary.addPhrase(correction.correct)
        case .general:
            break
        }
    }
    
    private func findDifference(original: String, corrected: String) -> (wrong: String, correct: String) {
        // simple word-by-word comparison
        let originalWords = original.split(separator: " ")
        let correctedWords = corrected.split(separator: " ")
        
        for (index, originalWord) in originalWords.enumerated() {
            if index < correctedWords.count && originalWord != correctedWords[index] {
                return (String(originalWord), String(correctedWords[index]))
            }
        }
        
        // fallback if no specific word difference found
        return (original, corrected)
    }
}

// MARK: - correction type button

struct CorrectionTypeButton: View {
    let type: CorrectionView.CorrectionType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.system(size: 12))
                Text(type.rawValue)
            }
            .font(Typography.metadata)
            .foregroundColor(isSelected ? .sumi : .hai)
            .padding(.horizontal, Spacing.gapMedium)
            .padding(.vertical, Spacing.gapSmall)
            .background(isSelected ? Color.primaryButton : Color.gofun)
            .cornerRadius(6)
            .lowercased()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - correction chip

struct CorrectionChip: View {
    let correction: UserCorrection
    
    var body: some View {
        HStack(spacing: 4) {
            Text(correction.wrong)
                .strikethrough()
                .foregroundColor(.usugrey)
            
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.hai)
            
            Text(correction.correct)
                .foregroundColor(.sumi)
        }
        .font(Typography.metadata)
        .padding(.horizontal, Spacing.gapSmall)
        .padding(.vertical, 4)
        .background(Color.gofun)
        .cornerRadius(4)
    }
}

// MARK: - user dictionary manager

class UserDictionaryManager: ObservableObject {
    static let shared = UserDictionaryManager()
    
    @Published var dictionary: UserDictionary
    @Published var recentCorrections: [UserCorrection] = []
    
    private let saveURL: URL
    
    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        saveURL = documentsPath.appendingPathComponent("ai-and-i").appendingPathComponent("user-dictionary.json")
        
        // load existing dictionary
        if let data = try? Data(contentsOf: saveURL),
           let loaded = try? JSONDecoder().decode(UserDictionary.self, from: data) {
            self.dictionary = loaded
        } else {
            self.dictionary = UserDictionary()
        }
        
        // load recent corrections (last 5)
        recentCorrections = Array(dictionary.corrections.suffix(5))
    }
    
    func addCorrection(_ correction: UserCorrection) {
        dictionary.corrections.append(correction)
        recentCorrections = Array(dictionary.corrections.suffix(5))
        save()
    }
    
    func addName(_ name: String) {
        dictionary.names.insert(name.lowercased())
        save()
    }
    
    func addCompany(_ company: String) {
        dictionary.companies.insert(company.lowercased())
        save()
    }
    
    func addPhrase(_ phrase: String) {
        dictionary.phrases.insert(phrase.lowercased())
        save()
    }
    
    private func save() {
        // ensure directory exists
        try? FileManager.default.createDirectory(
            at: saveURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // save dictionary
        if let data = try? JSONEncoder().encode(dictionary) {
            try? data.write(to: saveURL)
        }
    }
    
    // generate prompt injection for transcription services
    func generatePromptAddition() -> String {
        dictionary.promptInjection
    }
}

// MARK: - preview

#Preview {
    CorrectionView(
        isPresented: .constant(true),
        text: "hi wikus, thanks for joining the meeting about antropic's new features"
    )
}