import SwiftUI
import UserNotifications

/// Screen 9 — the designed mock alert + ring + arrow stays visible; the CTA
/// fires the REAL OS prompt, which lands centered over the mock so the arrow
/// points at the real Allow button. Any outcome advances.
struct NotificationPermissionScreen: View {
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("We'll remind you to cook so it becomes a habit", size: 27)
            OnboardingSubhead("Only cooking reminders, never spam").padding(.top, 8)
            VStack(spacing: 14) {
                mockAlert
                MS.arrowUpwardFill.sized(36)
                    .foregroundStyle(OnboardingTheme.greenDeep)
                    .modifier(FloatEffect(duration: 1.5, delay: 0, enabled: !reduceMotion))
                    .frame(maxWidth: 272, alignment: .center)
                    .offset(x: 272 * 0.25) // left:75% of the alert width
            }
            .frame(maxHeight: .infinity)
            OnboardingPrimaryButton(title: "Allow Notifications", action: requestPermission)
            OnboardingTextLink(title: "Not now", action: onDone).padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 10)
    }

    private func requestPermission() {
        guard !requesting else { return }
        requesting = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted { ReminderScheduler.schedulePlatesDailyReminder() }
                onDone()
            }
        }
    }

    /// Visual mock of the iOS alert (SF system font on purpose — it imitates the OS).
    private var mockAlert: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("\u{201C}Glutt\u{201D} Would Like to Send You Notifications")
                    .font(.system(size: 16, weight: .semibold)).kerning(-0.2)
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text("Just gentle reminders to cook. No spam, ever.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0x6B6B70))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 20).padding(.horizontal, 18).padding(.bottom, 15)

            Divider().overlay(Color(hex: 0x3C3C43).opacity(0.16))
            HStack(spacing: 0) {
                Text("Don't Allow").font(.system(size: 16))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Rectangle().fill(Color(hex: 0x3C3C43).opacity(0.16)).frame(width: 1)
                Text("Allow").font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background( // green teaching highlight over the Allow half
                        UnevenRoundedRectangle(bottomTrailingRadius: 14)
                            .fill(OnboardingTheme.greenDeep.opacity(0.08))
                    )
                    .overlay(
                        UnevenRoundedRectangle(bottomTrailingRadius: 14)
                            .strokeBorder(OnboardingTheme.greenDeep.opacity(0.85), lineWidth: 2)
                    )
            }
            .foregroundStyle(Color(hex: 0x0A84FF))
            .frame(height: 44)
        }
        .frame(width: 272)
        .background(Color(hex: 0xF9F9FA).opacity(0.97),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: OnboardingTheme.warmBlack(0.28), radius: 30, y: 24)
    }
}
