import Foundation

/// "Send this to my roommate" — recipe sharing as clean text.
/// No accounts, no links to a service that doesn't exist yet. The text IS
/// the product: a recipe anyone can cook from, with Glutt's name at the end.
enum RecipeShareService {

    static func shareText(for recipe: Recipe, servings: Int? = nil) -> String {
        var lines: [String] = []

        lines.append("🍳 \(recipe.title)")

        var metaParts: [String] = []
        let displayServings = servings ?? recipe.servings
        if displayServings > 0 { metaParts.append("serves \(displayServings)") }
        if recipe.totalMinutes > 0 { metaParts.append("\(recipe.totalMinutes) min") }
        if !metaParts.isEmpty {
            lines.append(metaParts.joined(separator: " · "))
        }
        if let summary = recipe.summary, !summary.isEmpty {
            lines.append(summary)
        }
        lines.append("")

        let ingredients = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
        if !ingredients.isEmpty {
            lines.append("INGREDIENTS")
            for ingredient in ingredients {
                var line = "• "
                if let display = UnitConverter.display(
                    quantity: ingredient.quantity,
                    unit: ingredient.unit,
                    scale: 1,
                    system: .original
                ) {
                    line += "\(display) "
                }
                line += ingredient.name
                if ingredient.isOptional { line += " (optional)" }
                lines.append(line)
            }
            lines.append("")
        }

        let steps = recipe.sortedSteps
        if !steps.isEmpty {
            lines.append("STEPS")
            for step in steps {
                lines.append("\(step.index + 1). \(step.text)")
            }
            lines.append("")
        }

        if let source = recipe.sourceURL, !source.isEmpty {
            lines.append("Original: \(source)")
        }
        lines.append("Shared from Glutt 🥘")

        return lines.joined(separator: "\n")
    }
}
