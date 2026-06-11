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

    private func actionRow(_ action: CaptureAction) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: action.icon)
                .font(.title3)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 40, height: 40)
                .background(Theme.Colors.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))

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
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
