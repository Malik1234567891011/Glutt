import SwiftUI

/// Per-word styling for the onboarding headline.
enum HeadlineWordStyle {
    case green, amber, tomato, plain

    var foreground: Color {
        switch self {
        case .green:  return Theme.Colors.accent
        case .amber:  return Theme.Colors.warning
        case .tomato: return Theme.Colors.tomato
        case .plain:  return Theme.Colors.textPrimary
        }
    }

    /// Pill fill, or `nil` for a plain (pill-less) word.
    var background: Color? {
        switch self {
        case .green:  return Theme.Colors.successTint
        case .amber:  return Theme.Colors.warningTint
        case .tomato: return Theme.Colors.tomatoTint
        case .plain:  return nil
        }
    }
}

struct HeadlineWord: Identifiable {
    let id = UUID()
    let text: String
    let style: HeadlineWordStyle
}

/// A bold headline whose words wrap as individually tinted pills
/// (e.g. "Cook" green · "smarter" amber · "not" plain · "harder" tomato).
struct HighlightHeadline: View {
    let words: [HeadlineWord]

    var body: some View {
        FlowLayout(hSpacing: 8, vSpacing: 8) {
            ForEach(words) { word in
                Text(word.text)
                    .font(BrandFont.bricolage(31, 700))
                    .foregroundColor(word.style.foreground)
                    .padding(.horizontal, word.style.background == nil ? 0 : 15)
                    .padding(.vertical, word.style.background == nil ? 0 : 5)
                    .background {
                        if let bg = word.style.background {
                            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(bg)
                        }
                    }
            }
        }
    }
}

#Preview("HighlightHeadline") {
    HighlightHeadline(words: [
        HeadlineWord(text: "Cook", style: .green),
        HeadlineWord(text: "smarter", style: .amber),
        HeadlineWord(text: "not", style: .plain),
        HeadlineWord(text: "harder", style: .tomato),
    ])
    .padding()
    .frame(width: 320, alignment: .leading)
    .background(Theme.Colors.background)
}
