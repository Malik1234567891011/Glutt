import Foundation
import Observation
import UserNotifications

struct CookTimer: Identifiable {
    let id = UUID()
    let label: String
    let totalSeconds: Int
    let endDate: Date

    func remainingSeconds(at now: Date = .now) -> Int {
        max(0, Int(endDate.timeIntervalSince(now).rounded()))
    }

    func isFinished(at now: Date = .now) -> Bool {
        remainingSeconds(at: now) == 0
    }
}

/// Runs multiple concurrent cooking timers and fires a local notification
/// when each one ends (so backgrounding the app doesn't lose the timer).
@Observable
final class TimerManager {
    private(set) var timers: [CookTimer] = []
    /// Updated every second while timers run; views read it to refresh countdowns.
    private(set) var now: Date = .now

    @ObservationIgnored private var ticker: Timer?

    func start(label: String, seconds: Int) {
        let timer = CookTimer(label: label, totalSeconds: seconds, endDate: .now.addingTimeInterval(TimeInterval(seconds)))
        timers.append(timer)
        scheduleNotification(for: timer)
        startTickingIfNeeded()
    }

    func cancel(_ timer: CookTimer) {
        timers.removeAll { $0.id == timer.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
        stopTickingIfIdle()
    }

    func dismissFinished() {
        timers.removeAll { $0.isFinished(at: now) }
        stopTickingIfIdle()
    }

    func cancelAll() {
        let ids = timers.map { $0.id.uuidString }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        timers.removeAll()
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - Ticking

    private func startTickingIfNeeded() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.now = .now
        }
    }

    private func stopTickingIfIdle() {
        if timers.isEmpty {
            ticker?.invalidate()
            ticker = nil
        }
    }

    // MARK: - Notifications

    private func scheduleNotification(for timer: CookTimer) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Timer done"
            content.body = timer.label
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, TimeInterval(timer.totalSeconds)),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: timer.id.uuidString,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    // MARK: - Formatting

    static func format(seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
