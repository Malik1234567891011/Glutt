import SwiftUI
import UserNotifications

/// Soft pre-prompt before the iOS notification permission dialog.
struct NotificationPrimerScreen: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            GlowBackground()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()
                Image(systemName: "bell.badge")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Want a nudge at dinnertime?")
                        .font(.gluttLargeTitle)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("We'll remind you what you planned to cook — and when something's about to go off. Off by default; change it anytime.")
                        .font(.gluttBody)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.md)
                }
                Spacer()
                VStack(spacing: Theme.Spacing.sm) {
                    Button("Enable nudges", action: requestThenDone)
                        .buttonStyle(.gluttPrimary)
                    Button("Not now", action: onDone)
                        .buttonStyle(.gluttSecondary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
    }

    private func requestThenDone() {
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await MainActor.run { onDone() }
        }
    }
}

#Preview {
    NotificationPrimerScreen(onDone: {})
}
