import Foundation

/// LLM pass over an imported draft: fixes mangled OCR lines, extracts real
/// recipes out of chatty TikTok captions, fills in missing structure.
/// Strictly additive — on any failure the original draft is returned untouched.
enum DraftCleanup {

    /// What the model is allowed to return. Decoded strictly; garbage throws.
    private struct CleanedDraft: Decodable {
        var title: String?
        var summary: String?
        var servings: Int?
        var prepMinutes: Int?
        var cookMinutes: Int?
        var ingredients: [String]?
        var steps: [String]?
        var tags: [String]?
        var notes: String?
    }

    /// Heuristic for "is this draft messy enough to be worth a cloud call".
    static func wouldImprove(_ draft: ImportedRecipeDraft) -> Bool {
        guard LLMClient.isConfigured else { return false }
        if draft.ingredientLines.isEmpty || draft.stepTexts.isEmpty { return true }
        if draft.confidence < 0.85 { return true }
        // Captions are prose, not structure — always worth a pass.
        if draft.platform == .tiktok || draft.platform == .instagram || draft.platform == .screenshot {
            return true
        }
        return false
    }

    static func cleanUp(_ draft: ImportedRecipeDraft) async -> ImportedRecipeDraft {
        guard LLMClient.isConfigured else { return draft }

        let system = """
        You clean up recipes extracted from websites, social media captions, and OCR'd screenshots.
        Return JSON only, with this exact shape (all fields optional, omit what you can't determine):
        {"title": str, "summary": str, "servings": int, "prepMinutes": int, "cookMinutes": int,
         "ingredients": [str], "steps": [str], "tags": [str], "notes": str}

        Rules:
        - Extract the ACTUAL recipe. Strip hashtags, emoji spam, "follow me", engagement bait.
        - ingredients: one ingredient per line, format "quantity unit ingredient" when known (e.g. "2 tbsp soy sauce"). Fix OCR errors (e.g. "1OO g" -> "100 g").
        - steps: clear imperative sentences, one action per step, in order. Split run-on paragraphs.
        - Do NOT invent quantities, ingredients, or steps that are not implied by the source.
        - tags: up to 5 lowercase tags like "high-protein", "one-pan", "quick".
        - summary: one appetizing sentence, no hype.
        - If the text contains no recipe at all, return {}.
        """

        var source = ""
        if let title = draft.title { source += "TITLE: \(title)\n" }
        if let caption = draft.caption { source += "CAPTION/TEXT:\n\(caption)\n" }
        if !draft.ingredientLines.isEmpty {
            source += "EXTRACTED INGREDIENTS:\n" + draft.ingredientLines.joined(separator: "\n") + "\n"
        }
        if !draft.stepTexts.isEmpty {
            source += "EXTRACTED STEPS:\n" + draft.stepTexts.joined(separator: "\n") + "\n"
        }
        guard source.count > 20 else { return draft }

        do {
            let cleaned = try await LLMClient.chatJSON(
                CleanedDraft.self,
                system: system,
                user: String(source.prefix(8000))
            )

            // Nothing recipe-shaped came back — keep what the parser found.
            guard (cleaned.ingredients?.count ?? 0) > 0 || (cleaned.steps?.count ?? 0) > 0 else {
                return draft
            }

            var result = draft
            if let title = cleaned.title, !title.isEmpty { result.title = title }
            if let summary = cleaned.summary, !summary.isEmpty { result.summary = summary }
            if let servings = cleaned.servings, servings > 0 { result.servings = servings }
            if let prep = cleaned.prepMinutes, prep >= 0 { result.prepMinutes = prep }
            if let cook = cleaned.cookMinutes, cook >= 0 { result.cookMinutes = cook }
            if let ingredients = cleaned.ingredients, !ingredients.isEmpty {
                result.ingredientLines = ingredients
            }
            if let steps = cleaned.steps, !steps.isEmpty {
                result.stepTexts = steps
            }
            if let tags = cleaned.tags, !tags.isEmpty {
                result.tags = Array(Set(result.tags + tags.map { $0.lowercased() })).sorted()
                result.tags = Array(result.tags.prefix(6))
            }
            // Drop issues the cleanup just resolved — stale warnings above a
            // perfectly good ingredient list make the import look broken.
            if !result.ingredientLines.isEmpty {
                result.issues.removeAll {
                    $0.localizedCaseInsensitiveContains("ingredient")
                        || $0.localizedCaseInsensitiveContains("full recipe")
                }
            }
            if !result.stepTexts.isEmpty {
                result.issues.removeAll { $0.localizedCaseInsensitiveContains("steps") }
            }
            result.issues.removeAll { $0.contains("double-check") }
            result.issues.append("Cleaned up with AI — give it a once-over")
            return result
        } catch {
            // AI is never load-bearing: any failure returns the original.
            return draft
        }
    }

    // MARK: - Reconstruction

    /// Last resort for video imports: the caption was "recipe in comments 👇"
    /// or just vibes, so there is nothing to extract. Draft a standard home
    /// version of the dish from its name — honestly labeled as Glutt's draft,
    /// never passed off as the creator's recipe.
    static func reconstruct(_ draft: ImportedRecipeDraft) async -> ImportedRecipeDraft {
        guard LLMClient.isConfigured, draft.ingredientLines.isEmpty else { return draft }

        let dish = [draft.title, draft.caption].compactMap { $0 }.joined(separator: "\n")
        guard dish.count > 3 else { return draft }

        let system = """
        A user saved a cooking video, but its caption doesn't contain the recipe.
        From the dish name and caption, write a sensible STANDARD HOME version of that dish.
        Return JSON only:
        {"title": str, "summary": str, "servings": int, "prepMinutes": int, "cookMinutes": int,
         "ingredients": [str], "steps": [str], "tags": [str]}

        Rules:
        - This is your best-guess standard version, so keep it simple and classic — no chef flourishes.
        - ingredients: "quantity unit ingredient" per line, realistic home quantities.
        - steps: clear imperative sentences, one action per step.
        - tags: up to 5 lowercase tags.
        - If you cannot tell what dish this is, return {}.
        """

        do {
            let drafted = try await LLMClient.chatJSON(
                CleanedDraft.self,
                system: system,
                user: String(dish.prefix(2000)),
                temperature: 0.3
            )
            guard let ingredients = drafted.ingredients, !ingredients.isEmpty,
                  let steps = drafted.steps, !steps.isEmpty
            else { return draft }

            var result = draft
            if let title = drafted.title, !title.isEmpty { result.title = title }
            if let summary = drafted.summary, !summary.isEmpty { result.summary = summary }
            if let servings = drafted.servings, servings > 0 { result.servings = servings }
            if let prep = drafted.prepMinutes, prep >= 0 { result.prepMinutes = prep }
            if let cook = drafted.cookMinutes, cook >= 0 { result.cookMinutes = cook }
            result.ingredientLines = ingredients
            result.stepTexts = steps
            if let tags = drafted.tags, !tags.isEmpty {
                result.tags = Array(tags.map { $0.lowercased() }.prefix(6))
            }
            result.issues.removeAll()
            result.issues.append("Glutt drafted this from the video — check it against what you watched")
            return result
        } catch {
            return draft
        }
    }
}
