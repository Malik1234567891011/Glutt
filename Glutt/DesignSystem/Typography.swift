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
