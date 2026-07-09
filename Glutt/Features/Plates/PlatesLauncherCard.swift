import SwiftUI

/// The Today-tab entry into Plates: a hero "Today's Plate is ready" card.
struct PlatesLauncherCard: View {
    var onOpen: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.medium)
            onOpen()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.accent.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Ph.forkKnife.fill.resizable().scaledToFit().frame(width: 26, height: 26)
                        .foregroundStyle(Theme.Colors.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discover new recipes 🍳")
                        .font(.gluttHeadline).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Swipe endless dishes — flip & save")
                        .font(.gluttCaption).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Ph.caretRight.bold.resizable().scaledToFit().frame(width: 14, height: 14)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
