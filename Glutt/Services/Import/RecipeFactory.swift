import Foundation

/// Builds a SwiftData `Recipe` from an `ImportedRecipeDraft`. One source of
/// truth for both the in-app review screen and the share-extension inbox drain.
enum RecipeFactory {

    static func make(from draft: ImportedRecipeDraft) -> Recipe {
        let recipe = Recipe(
            title: (draft.title ?? "").trimmingCharacters(in: .whitespaces),
            summary: draft.summary,
            sourceCreator: draft.creator,
            sourceURL: draft.sourceURL,
            sourcePlatform: draft.platform,
            sourceCaption: draft.caption,
            importedAt: .now,
            importConfidence: draft.confidence,
            imageURL: draft.imageURL,
            servings: draft.servings ?? 2,
            prepMinutes: draft.prepMinutes ?? 0,
            cookMinutes: draft.cookMinutes ?? 0,
            tags: draft.tags
        )
        recipe.calories = draft.calories
        recipe.proteinGrams = draft.proteinGrams

        recipe.ingredients = draft.ingredientLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in
                let parsed = IngredientLineParser.parse(line)
                return RecipeIngredient(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    note: parsed.note,
                    sortIndex: index
                )
            }

        recipe.steps = draft.stepTexts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, text in
                RecipeStep(index: index, text: text, durationSeconds: detectDuration(in: text))
            }

        return recipe
    }

    /// "simmer for 10 minutes" -> 600 seconds. Powers Cook Mode timers later.
    static func detectDuration(in text: String) -> Int? {
        let pattern = #"(\d+)\s*(?:-\s*\d+\s*)?(minutes|minute|mins|min|hours|hour|hrs|hr)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Int(text[numberRange])
        else { return nil }
        let unit = text[unitRange].lowercased()
        return unit.hasPrefix("h") ? value * 3600 : value * 60
    }
}
