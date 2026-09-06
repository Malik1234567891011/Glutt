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
