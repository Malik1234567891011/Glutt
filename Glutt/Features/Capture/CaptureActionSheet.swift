import SwiftUI

/// The universal action sheet behind the floating + button.
/// All five capture flows route through here; flows themselves land in later phases.
struct CaptureActionSheet: View {
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("What do you want to add?")
                .font(.gluttTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.top, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(CaptureAction.allCases) { action in
                    Button {
                        Haptics.impact(.medium)
                        router.perform(action)
                    } label: {
                        actionRow(action)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.background)
    }

    /// Map each capture action to a verified Phosphor icon (keeps Router's SF strings intact).
    private func phosphorIcon(for action: CaptureAction) -> Image {
        switch action {
        case .importRecipe:    return Ph.link.regular
        case .scanPantry:      return Ph.scan.regular
        case .logFood:         return Ph.forkKnife.regular
        case .addGroceryItem:  return Ph.shoppingCart.regular
        case .askWhatToCook:   return Ph.sparkle.regular
        }
    }

    private func actionRow(_ action: CaptureAction) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            IconChip(
                icon: phosphorIcon(for: action),
                foreground: Theme.Colors.accent,
                background: Theme.Colors.accent.opacity(0.1)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(action.label)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(action.subtitle)
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Ph.caretRight.regular
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
