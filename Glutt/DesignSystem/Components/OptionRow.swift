import SwiftUI
import PhosphorSwift

/// Full-width selectable row used by onboarding goal/nutrition pickers:
/// leading emoji, Phosphor icon, or a custom view; a title (+ optional subtitle); trailing check.
struct OptionRow<LeadingIcon: View>: View {
    var emoji: String? = nil
    var leadingIcon: LeadingIcon? = nil
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.impact(.light)
            action()
        }) {
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
                if isSelected {
                    Ph.checkCircle.fill
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    Ph.circle.regular
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.Colors.border)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.Colors.successTint.opacity(0.35) : Theme.Colors.card)
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
        } else if let leadingIcon {
            leadingIcon
        }
    }
}

// MARK: - Convenience initialisers

extension OptionRow where LeadingIcon == EmptyView {
    /// Emoji-only row (GoalsScreen).
    init(
        emoji: String,
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.emoji = emoji
        self.leadingIcon = nil
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
    }

    /// No leading icon.
    init(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.emoji = nil
        self.leadingIcon = nil
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.action = action
    }
}

#Preview {
    VStack(spacing: 8) {
        OptionRow(emoji: "🥗", title: "Eat healthier", isSelected: true) {}
        OptionRow(
            leadingIcon: Ph.barbell.regular
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Theme.Colors.accent),
            title: "Gym mode",
            subtitle: "Calories & protein",
            isSelected: false
        ) {}
    }
    .padding()
    .background(Theme.Colors.background)
}
