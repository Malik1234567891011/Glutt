import Foundation

/// Heuristic parser for plain recipe text: OCR output from screenshots,
/// social media captions, pasted notes. Finds the title, ingredient
/// section, and step section without any AI.
enum TextRecipeParser {

    private static let ingredientHeaders = ["ingredients", "what you need", "you'll need", "you will need"]
    private static let stepHeaders = ["instructions", "directions", "method", "steps", "how to make", "preparation"]

    static func parse(text: String) -> ImportedRecipeDraft {
        var draft = ImportedRecipeDraft()

        let lines = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            draft.issues.append("No readable text found")
            return draft
        }

        let ingredientHeaderIndex = lines.firstIndex { isHeader($0, matching: ingredientHeaders) }
        let stepHeaderIndex = lines.firstIndex { isHeader($0, matching: stepHeaders) }

        // Title: first line that isn't a section header (skip hashtag/emoji-only lines).
        draft.title = lines.first {
            !isHeader($0, matching: ingredientHeaders + stepHeaders)
                && !$0.hasPrefix("#")
                && $0.count >= 4
        }

        if let start = ingredientHeaderIndex {
            let end = (stepHeaderIndex.map { $0 > start ? $0 : lines.count }) ?? lines.count
            draft.ingredientLines = Array(lines[(start + 1)..<end]).filter { looksLikeIngredient($0) || $0.count < 60 }
        } else {
            // No header — collect lines that strongly look like ingredients.
            draft.ingredientLines = lines.dropFirst().filter { looksLikeIngredient($0) }
            if !draft.ingredientLines.isEmpty {
                draft.issues.append("Ingredient section was guessed")
            }
        }

        if let start = stepHeaderIndex {
            draft.stepTexts = Array(lines[(start + 1)...])
                .filter { !isHeader($0, matching: ingredientHeaders) && !isServingLine($0) }
                .map(stripStepNumber)
        } else {
            // Numbered lines anywhere are probably steps.
            draft.stepTexts = lines.filter { startsWithStepNumber($0) }.map(stripStepNumber)
            if !draft.stepTexts.isEmpty {
                draft.issues.append("Step section was guessed")
            }
        }

        // Servings: "serves 4", "makes 6", "4 servings"
        for line in lines {
            let lower = line.lowercased()
            if let match = firstInt(after: ["serves", "makes"], in: lower) {
                draft.servings = match
                break
            }
            if lower.contains("serving"), let count = Int(lower.prefix(while: \.isNumber)) {
                draft.servings = count
                break
            }
        }

        if draft.ingredientLines.isEmpty { draft.issues.append("No ingredients detected") }
        if draft.stepTexts.isEmpty { draft.issues.append("No steps detected") }

        return draft
    }

    // MARK: - Heuristics

    private static func isHeader(_ line: String, matching headers: [String]) -> Bool {
        let normalized = line.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ":*#-• \t"))
        return headers.contains { normalized == $0 || normalized.hasPrefix($0 + ":") }
    }

    private static func looksLikeIngredient(_ line: String) -> Bool {
        let parsed = IngredientLineParser.parse(line)
        if parsed.quantity != nil { return true }
        return line.hasPrefix("-") || line.hasPrefix("•") || line.hasPrefix("*")
    }

    private static func isServingLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.hasPrefix("serves ") || lower.hasPrefix("makes ") || lower.contains("serving")
    }

    private static func startsWithStepNumber(_ line: String) -> Bool {
        let prefix = line.prefix { $0.isNumber }
        guard !prefix.isEmpty, prefix.count <= 2 else { return false }
        let rest = line.dropFirst(prefix.count)
        return rest.hasPrefix(".") || rest.hasPrefix(")") || rest.hasPrefix(":")
    }

    private static func stripStepNumber(_ line: String) -> String {
        guard startsWithStepNumber(line) else { return line }
        let withoutNumber = line.drop { $0.isNumber }
        return String(withoutNumber.drop { $0 == "." || $0 == ")" || $0 == ":" || $0 == " " })
    }

    private static func firstInt(after keywords: [String], in text: String) -> Int? {
        for keyword in keywords {
            guard let range = text.range(of: keyword + " ") else { continue }
            let after = text[range.upperBound...].prefix(while: \.isNumber)
            if let value = Int(after) { return value }
        }
        return nil
    }
}
