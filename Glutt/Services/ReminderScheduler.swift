import Foundation
import UserNotifications

/// Detects prep-ahead work hiding in recipes: thawing, marinating, soaking.
enum PrepDetector {

    struct PrepTask: Equatable {
        let keyword: String
        let text: String
    }

    private static let rules: [(keyword: String, message: String)] = [
        ("marinate", "Marinate ahead for"),
        ("thaw", "Thaw ingredients for"),
        ("defrost", "Defrost ingredients for"),
        ("soak", "Soak ingredients for"),
        ("overnight", "Overnight prep needed for"),
        ("proof", "Dough needs time to proof for"),
        ("rest the dough", "Dough needs resting for"),
    ]

    static func tasks(for recipe: Recipe) -> [PrepTask] {
        let haystack = (
            recipe.steps.map(\.text) + recipe.ingredients.compactMap(\.note)
        ).joined(separator: " ").lowercased()

        var found: [PrepTask] = []
        for rule in rules where haystack.contains(rule.keyword) {
            // One task per keyword family (thaw/defrost are the same chore).
            if !found.contains(where: { $0.text == "\(rule.message) \(recipe.title)" }) {
                found.append(PrepTask(keyword: rule.keyword, text: "\(rule.message) \(recipe.title)"))
            }
        }
        return found
    }
}

/// Schedules the daily "today's plate is ready" local notification.
enum ReminderScheduler {

    static func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// A single repeating 07:00-local nudge that the daily deck is ready.
    /// Idempotent: re-scheduling replaces the one pending request.
    static func schedulePlatesDailyReminder() {
        let id = "plates-daily"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Today's Plate is ready 🍳"
        content.body = "12 fresh recipes to swipe through. Tap to explore."
        content.sound = .default
        content.userInfo = ["destination": "plates"]

        var components = DateComponents()
        components.hour = 7
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
