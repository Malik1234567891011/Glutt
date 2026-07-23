import SwiftUI

/// App-wide type ramp. **Bricolage Grotesque** for display/headings, **Nunito** for
/// body/UI (see `BrandFont`). The mocks are pixel-spec'd, so these are fixed sizes.
/// Weight modifiers applied on top (e.g. `.gluttCaption.weight(.bold)`) may be soft
/// on a variable custom font — prefer `BrandFont.nunito(size, weight)` directly when
/// an exact weight matters.
extension Font {
    /// Big screen titles ("Your recipes", "Kitchen").
    static let gluttLargeTitle = BrandFont.bricolage(31, 700)
    /// Section / card titles.
    static let gluttTitle = BrandFont.bricolage(22, 600)
    /// Card headings.
    static let gluttHeadline = BrandFont.bricolage(17, 600)
    /// Body copy.
    static let gluttBody = BrandFont.nunito(16, 500)
    /// Secondary metadata (time, source, tags).
    static let gluttCaption = BrandFont.nunito(14, 600)
    /// Cook Mode step text — large and readable from a distance.
    static let gluttCookStep = BrandFont.bricolage(27, 600)
    /// Small uppercase section labels ("FRESH", "PANTRY", category headers).
    static let gluttSectionLabel = BrandFont.nunito(12, 800)
}

/// Uppercase, letter-spaced, herb-green section label (FRESH / PANTRY / category headers).
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.Colors.accent

    var body: some View {
        Text(text.uppercased())
            .font(.gluttSectionLabel)
            .tracking(1.6)
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
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
    }
}
