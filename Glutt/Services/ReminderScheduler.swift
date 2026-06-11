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

/// Schedules local notifications for planned meals:
/// "start cooking at 6:45" and morning prep-ahead nudges.
enum ReminderScheduler {

    static func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// (Re)schedules reminders for a meal. Call after insert or edit.
    static func schedule(for meal: PlannedMeal) {
        cancel(for: meal)

        guard let recipe = meal.recipe else { return }
        let id = reminderID(for: meal)

        // 1. Cooking start reminder, if the meal has an exact time in the future.
        if let startTime = meal.suggestedStartTime, startTime > .now {
            let content = UNMutableNotificationContent()
            content.title = "Time to start cooking"
            content.body = "\(recipe.title) — \(meal.mealType.label.lowercased()) at \(meal.exactTime!.formatted(date: .omitted, time: .shortened)). Start now to be ready."
            content.sound = .default
            content.userInfo = ["destination": "plan"]
            add(content: content, at: startTime, identifier: "\(id)-start")
        }

        // 2. Prep-ahead reminder the morning of the meal (9 AM).
        let prepTasks = PrepDetector.tasks(for: recipe)
        if let firstTask = prepTasks.first {
            var morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: meal.date)!
            // If planning for today after 9 AM, fire in 5 minutes instead.
            if morning <= .now {
                morning = .now.addingTimeInterval(300)
            }
            // Only schedule if the meal itself is still ahead of the reminder.
            if meal.exactTime == nil || meal.exactTime! > morning {
                let content = UNMutableNotificationContent()
                content.title = "Prep ahead"
                content.body = firstTask.text
                content.sound = .default
                content.userInfo = ["destination": "plan"]
                add(content: content, at: morning, identifier: "\(id)-prep")
            }
        }
    }

    static func cancel(for meal: PlannedMeal) {
        let id = reminderID(for: meal)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["\(id)-start", "\(id)-prep"]
        )
    }

    private static func reminderID(for meal: PlannedMeal) -> String {
        if meal.reminderID == nil {
            meal.reminderID = UUID()
        }
        return meal.reminderID!.uuidString
    }

    private static func add(content: UNMutableNotificationContent, at date: Date, identifier: String) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
