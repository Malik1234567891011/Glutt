import SwiftUI

/// Empty state that teaches — every empty screen suggests the next action.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Theme.Colors.accent.opacity(0.5))
            Text(title)
                .font(.gluttHeadline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(message)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.gluttPill)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}
