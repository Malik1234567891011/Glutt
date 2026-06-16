import SwiftUI

/// Full-width selectable row used by onboarding goal/nutrition pickers:
/// leading emoji or SF Symbol, a title (+ optional subtitle), trailing check.
struct OptionRow: View {
    var emoji: String? = nil
    var systemImage: String? = nil
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                leading
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.border)
                    .font(.title3)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Colors.accent : Theme.Colors.border.opacity(0.55),
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var leading: some View {
        if let emoji {
            Text(emoji).font(.title2)
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.Colors.accent)
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        OptionRow(emoji: "🥗", title: "Eat healthier", isSelected: true) {}
        OptionRow(systemImage: "dumbbell", title: "Gym mode", subtitle: "Calories & protein", isSelected: false) {}
    }
    .padding()
    .background(Theme.Colors.background)
}
