//
//  DesignSystem.swift
//  AI-and-I
//
//  japanese-inspired design system with colors, typography, and spacing
//

import SwiftUI

// MARK: - colors

extension Color {
    // japanese-inspired palette
    static let kinari = Color(red: 0.984, green: 0.980, blue: 0.961)      // #fbfaf5 - natural/dough - background
    static let gofun = Color(red: 1.0, green: 1.0, blue: 0.988)          // #fffffc - chalk white - surface
    static let sumi = Color(red: 0.173, green: 0.173, blue: 0.173)       // #2c2c2c - charcoal - primary text
    static let hai = Color(red: 0.420, green: 0.420, blue: 0.420)        // #6b6b6b - ash grey - secondary text
    static let usugrey = Color(red: 0.616, green: 0.616, blue: 0.616)    // #9d9d9d - light grey - disabled
    
    // speaker colors - subtle earthy japanese tones
    static let speakerMe = Color(red: 0.827, green: 0.576, blue: 0.439)     // #d39370 - warm terracotta
    static let speakerOther = Color(red: 0.584, green: 0.647, blue: 0.651)  // #9595a6 - sage grey
    
    // actions
    static let primaryButton = Color(red: 0.918, green: 0.898, blue: 0.890)     // #eae5e3
    static let secondaryButton = Color(red: 0.953, green: 0.953, blue: 0.953)   // #f3f3f3
    static let successBackground = Color(red: 0.910, green: 0.961, blue: 0.910) // #e8f5e8
    static let warningBackground = Color(red: 1.0, green: 0.957, blue: 0.902)   // #fff4e6
    static let errorBackground = Color(red: 1.0, green: 0.910, blue: 0.910)     // #ffe8e8
    
    // selection and hover
    static let selection = Color(red: 0.918, green: 0.898, blue: 0.890)  // #eae5e3
    static let hover = Color(red: 0.961, green: 0.941, blue: 0.933)      // #f5f0ee
}

// MARK: - typography

struct Typography {
    // font sizes
    static let titleSize: CGFloat = 20
    static let metadataSize: CGFloat = 12
    static let speakerLabelSize: CGFloat = 16
    static let transcriptSize: CGFloat = 16
    static let timestampSize: CGFloat = 12
    static let buttonSize: CGFloat = 14
    
    // font weights
    static let titleWeight: Font.Weight = .bold
    static let metadataWeight: Font.Weight = .medium
    static let speakerWeight: Font.Weight = .medium
    static let transcriptWeight: Font.Weight = .regular
    static let buttonWeight: Font.Weight = .medium
    
    // font styles
    static var title: Font {
        Font.system(size: titleSize, weight: titleWeight, design: .default)
    }
    
    static var metadata: Font {
        Font.system(size: metadataSize, weight: metadataWeight, design: .default)
    }
    
    static var speakerLabel: Font {
        Font.system(size: speakerLabelSize, weight: speakerWeight, design: .default)
    }
    
    static var transcript: Font {
        Font.system(size: transcriptSize, weight: transcriptWeight, design: .default)
    }
    
    static var timestamp: Font {
        Font.system(size: timestampSize, weight: .regular, design: .default)
    }
    
    static var button: Font {
        Font.system(size: buttonSize, weight: buttonWeight, design: .default)
    }
}

// MARK: - spacing

struct Spacing {
    static let margins: CGFloat = 24
    static let padding: CGFloat = 16
    static let gapLarge: CGFloat = 24
    static let gapMedium: CGFloat = 16
    static let gapSmall: CGFloat = 8
    static let lineHeight: CGFloat = 1.6
}

// MARK: - animations

extension Animation {
    static let standard = Animation.easeInOut(duration: 0.2)
    static let recording = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
}

// MARK: - view modifiers

// lowercase text modifier
struct LowercaseModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textCase(.lowercase)
    }
}

extension View {
    func lowercased() -> some View {
        modifier(LowercaseModifier())
    }
}

// card style
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Spacing.padding)
            .background(Color.gofun)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}

// primary button style
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.button)
            .foregroundColor(.hai)
            .padding(.horizontal, Spacing.gapLarge)
            .padding(.vertical, Spacing.gapSmall + 2)
            .background(Color.primaryButton)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.standard, value: configuration.isPressed)
    }
}

// secondary button style
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.button)
            .foregroundColor(.hai)
            .padding(.horizontal, Spacing.gapMedium)
            .padding(.vertical, Spacing.gapSmall)
            .background(Color.secondaryButton)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.standard, value: configuration.isPressed)
    }
}

// floating action button
struct FloatingActionButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.sumi)
                .frame(width: 40, height: 40)
                .background(Color.kinari)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.usugrey.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}