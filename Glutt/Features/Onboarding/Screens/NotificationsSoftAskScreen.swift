import SwiftUI
import UserNotifications

/// Screen 8 — the single notifications page: three floating example
/// notifications, then the ask. Content only; the coordinator owns the fixed
/// `NotificationsFooter` + chrome.
struct NotificationsSoftAskScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let notes: [(title: String, body: String, time: String, duration: Double, delay: Double)] = [
        ("Tonight's dinner is 20 minutes away", "You've got everything for Creamy Tomato Rigatoni.", "now", 5.0, 0),
        ("Plan this week in 2 minutes", "Pick a few meals and Glutt builds your list.", "8:00 AM", 5.4, 0.55),
        ("Use it before it turns", "Your spinach and mushrooms expire Sunday.", "Sun", 5.8, 1.05),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeadline("Turn on gentle nudges", size: 27, maxWidth: 280)
            OnboardingSubhead("Cook on rhythm, never nagging").padding(.top, 8)
            VStack(spacing: 12) {
                ForEach(Self.notes, id: \.title) { note in
                    card(note)
                        .modifier(FloatEffect(duration: note.duration, delay: note.delay, enabled: !reduceMotion))
                }
            }
            .frame(maxWidth: 344).frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 50)
    }

    private func card(_ note: (title: String, body: String, time: String, duration: Double, delay: Double)) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x3C6B4B), Color(hex: 0x244430)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                MS.skilletFill.sized(23).foregroundStyle(OnboardingTheme.creamText)
            }
            .frame(width: 40, height: 40)
            .shadow(color: OnboardingTheme.greenDeep.opacity(0.3), radius: 4, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("GLUTT").font(OnboardingFonts.nunito(11, 800)).kerning(0.7)
                        .foregroundStyle(OnboardingTheme.muted)
                    Spacer()
                    Text(note.time).font(OnboardingFonts.nunito(11, 600))
                        .foregroundStyle(OnboardingTheme.timestamp)
                }
                .padding(.bottom, 1)
                Text(note.title).font(OnboardingFonts.bricolage(14.5, 600))
                    .foregroundStyle(OnboardingTheme.textHeading)
                Text(note.body).font(OnboardingFonts.nunito(12.5, 600))
                    .foregroundStyle(OnboardingTheme.mutedDeep)
            }
        }
        .padding(.vertical, 13).padding(.horizontal, 15)
        .background(OnboardingTheme.surface.opacity(0.95),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(OnboardingTheme.warmBlack(0.05), lineWidth: 1))
        .shadow(color: OnboardingTheme.warmBlack(0.1), radius: 15, y: 12)
    }
}

/// Screen 8's fixed footer. "Turn on notifications" fires the real OS prompt
/// (any outcome advances); "Maybe later" skips — both land on the tutorial.
struct NotificationsFooter: View {
    let onDone: () -> Void
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            OnboardingPrimaryButton(title: "Turn on notifications", action: requestPermission)
            OnboardingTextLink(title: "Maybe later", action: skip).padding(.top, 16)
        }
        .padding(.horizontal, 24).padding(.bottom, 10)
    }

    private func skip() {
        Analytics.capture(.onboardingNotifications, ["outcome": "skipped"])
        onDone()
    }

    private func requestPermission() {
        guard !requesting else { return }
        requesting = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                Analytics.capture(.onboardingNotifications, ["outcome": granted ? "granted" : "denied"])
                if granted { ReminderScheduler.schedulePlatesDailyReminder() }
                onDone()
            }
        }
    }
}

/// gluttOrb: gentle infinite Y float, staggered per card.
struct FloatEffect: ViewModifier {
    let duration: Double
    let delay: Double
    let enabled: Bool
    @State private var up = false

    func body(content: Content) -> some View {
        content
            .offset(y: enabled && up ? -6 : 0)
            .onAppear {
                guard enabled else { return }
                withAnimation(.easeInOut(duration: duration / 2).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}
