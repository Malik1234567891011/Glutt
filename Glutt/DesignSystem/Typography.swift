import SwiftUI

extension Font {
    /// Big screen titles ("Good afternoon, Malik").
    static let gluttLargeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    /// Section/card titles.
    static let gluttTitle = Font.system(.title2, design: .rounded).weight(.semibold)
    /// Card headings.
    static let gluttHeadline = Font.system(.headline, design: .rounded)
    /// Body copy.
    static let gluttBody = Font.system(.body, design: .rounded)
    /// Secondary metadata (time, source, tags).
    static let gluttCaption = Font.system(.subheadline, design: .rounded)
    /// Cook Mode step text — large and readable from a distance.
    static let gluttCookStep = Font.system(size: 28, weight: .medium, design: .rounded)
    /// Small uppercase section labels ("FRESH", "PANTRY", category headers).
    static let gluttSectionLabel = Font.system(size: 12, weight: .heavy, design: .rounded)
}

/// Uppercase, letter-spaced, herb-green section label (FRESH / PANTRY / category headers).
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.Colors.accent

    var body: some View {
        Text(text.uppercased())
            .font(.gluttSectionLabel)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

#Preview("SectionLabel") {
    VStack(alignment: .leading, spacing: 12) {
        SectionLabel(text: "Fresh")
        SectionLabel(text: "Pantry")
    }
    .padding()
    .background(Theme.Colors.background)
}

struct SectionHeader: View {
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.gluttTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .font(.gluttCaption.weight(.medium))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
    }
}
