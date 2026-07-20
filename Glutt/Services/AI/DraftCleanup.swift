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

    /// Shared instruction that pushes the model to actually reason about how
    /// many people a recipe feeds, instead of lazily defaulting to "2". Reused
    /// by every prompt that produces a `servings` value.
    private static let servingsGuidance = """
        - servings: estimate the REAL number of adult servings by reading the ingredient quantities — do NOT just default to 2. Reason it out using rough per-adult portions: ~150–225 g (⅓–½ lb) raw meat/fish, ~75–100 g dry rice/pasta (about ½–¾ cup dry rice) or 1 cup cooked grains, 1–2 eggs when eggs are the base, ~1 cup chopped vegetables, ~115 g (¼ lb) cheese as a main. Add up the mains and divide. Examples: 1 kg / 2 lb ground beef ≈ 5–6 servings; 4 chicken thighs ≈ 4 servings; a single salmon fillet ≈ 1. Only fall back to 2–4 when quantities are genuinely missing or unclear.
        """

    /// Rules for filling gaps like a careful chef: supply standard amounts,
    /// times, and temperatures when the source omits them — but mark estimates
    /// clearly and lean on doneness cues so a wrong guess can't ruin a dish.
    /// Accuracy matters more than completeness; when unsure, hedge.
    private static let chefGuidance = """
        - When an ingredient has NO quantity, REASON OUT a sensible amount for THIS specific dish — do not use a one-size-fits-all default (never output the same amount for an ingredient regardless of context). Scale every amount to the main ingredient and the serving count, and keep the whole dish in BALANCE: cooking is chemistry. Before adding salty things (soy sauce, fish sauce, stock, miso, cheese, cured meats) account for the salt already present; keep acid (vinegar, citrus), fat, sweetness, and heat (chili, pepper) in proportion so nothing overwhelms the dish. A marinade for 1 lb of chicken needs far less soy than one for 3 lb. Prefix every amount you infer with "~" so it reads as approximate, and never present an estimate as exact.
        - When a step is missing a time or temperature, give an approximate one hedged with "about"/"approximately" AND always pair it with a sensory doneness cue (e.g. "sear about 4–5 min per side, until golden and the internal temp reaches 165°F/74°C"; "simmer about 10 minutes, until thickened"). Prefer doneness cues over exact numbers. Use SAFE internal temperatures for meats: chicken/poultry 165°F/74°C, ground meat 160°F/71°C, fish 145°F/63°C.
        - For ratio-sensitive mixes (marinades, dressings, batters, brines, sauces), use classic ratios proven for that dish, scale them to the quantity being made, keep them approximate, and tell the user to taste and adjust. Never guess a precise ratio you aren't confident about — when unsure, give a conservative amount and say "add more to taste".
        """

    /// Duplicate-ingredient consolidation: captions often list the same
    /// ingredient in two places (marinade + garnish). The shopping-style
    /// ingredient list must show ONE line with the summed total; the steps
    /// carry the per-stage split so nothing gets lost.
    private static let mergeGuidance = """
        - MERGE DUPLICATES: if the same ingredient is listed more than once (e.g. "3 tbsp smoked paprika" for the marinade and "3 tbsp smoked paprika" to garnish), it must appear ONCE in "ingredients" with the TOTAL combined amount ("6 tbsp smoked paprika"). Then in the relevant "steps", state how much to use at each stage ("add 3 tbsp of the smoked paprika to the marinade", "sprinkle the remaining 3 tbsp on top to finish"). The amounts across the steps must add up to the ingredient-list total. Only merge the SAME ingredient in the same form — keep e.g. "lime juice" and "lime zest" separate.
        """

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

    static func cleanUp(_ draft: ImportedRecipeDraft, client: LLMClient = .live) async -> ImportedRecipeDraft {
        guard client.isConfigured else { return draft }

        let system = """
        You clean up recipes extracted from websites, social media captions, and OCR'd screenshots.
        Return JSON only, with this exact shape (all fields optional, omit what you can't determine):
        {"title": str, "summary": str, "servings": int, "prepMinutes": int, "cookMinutes": int,
         "ingredients": [str], "steps": [str], "tags": [str], "notes": str}

        Rules:
        - Extract the ACTUAL recipe. Strip hashtags, emoji spam, "follow me", engagement bait.
        - ingredients: one ingredient per line, format "quantity unit ingredient" when known (e.g. "2 tbsp soy sauce"). Fix OCR errors (e.g. "1OO g" -> "100 g").
        - KEEP BOTH UNITS when the source gives them: if a line has an imperial and a metric amount (e.g. "0.8 lb (400 g) ground pork" or "1 cup / 240 ml milk"), preserve them as "0.8 lb (400 g) ground pork" — primary amount first, the other in parentheses. Never drop one; cooks in different regions rely on each.
        - steps: clear imperative sentences, one action per step, in order. Split run-on paragraphs.
        - Do NOT invent ingredients or steps that aren't implied by the source.
        \(chefGuidance)
        \(mergeGuidance)
        \(servingsGuidance)
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
            let cleaned = try await client.chatJSON(
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
            if result.ingredientLines.contains(where: { $0.contains("~") }) {
                result.issues.append("Amounts marked ~ are Glutt's estimates — taste and adjust as you go.")
            }
            return result
        } catch {
            // AI is never load-bearing: any failure returns the original.
            return draft
        }
    }

    // MARK: - Step inference

    /// We have the dish and its ingredients, but the source listed no method
    /// (common with TikTok/IG captions and screenshots of ingredient lists).
    /// Rather than show a dead-end "No steps detected", draft plausible steps
    /// from the title + ingredients — and flag them honestly as AI-suggested.
    static func inferSteps(_ draft: ImportedRecipeDraft, client: LLMClient = .live) async -> ImportedRecipeDraft {
        guard client.isConfigured,
              draft.stepTexts.isEmpty,
              !draft.ingredientLines.isEmpty
        else { return draft }

        let dish = draft.title ?? "this dish"
        let system = """
        You write cooking method steps for a dish when only its name and ingredient
        list are known (the original source had no instructions).
        Return JSON only: {"steps": [str]}

        Rules:
        - Write a sensible STANDARD home method for the dish using ONLY the given ingredients.
        - Clear imperative sentences, one action per step, in a logical order (prep → cook → finish/plate).
        - Realistic, not fancy. Do NOT introduce ingredients that aren't in the list.
        \(chefGuidance)
        - 3 to 8 steps. If you genuinely cannot infer a method, return {"steps": []}.
        """
        let user = """
        DISH: \(dish)
        INGREDIENTS:
        \(draft.ingredientLines.joined(separator: "\n"))
        """

        do {
            let drafted = try await client.chatJSON(
                CleanedDraft.self,
                system: system,
                user: String(user.prefix(4000)),
                temperature: 0.3
            )
            guard let steps = drafted.steps, !steps.isEmpty else { return draft }

            var result = draft
            result.stepTexts = steps
            result.stepsAreAISuggested = true
            // The "no steps" warning is now resolved; replace it with an honest label.
            result.issues.removeAll { $0.localizedCaseInsensitiveContains("steps") }
            return result
        } catch {
            return draft
        }
    }

    // MARK: - Reconstruction

    /// Last resort for video imports: the caption was "recipe in comments 👇"
    /// or just vibes, so there is nothing to extract. Draft a standard home
    /// version of the dish from its name — honestly labeled as Glutt's draft,
    /// never passed off as the creator's recipe.
    static func reconstruct(_ draft: ImportedRecipeDraft, client: LLMClient = .live) async -> ImportedRecipeDraft {
        guard client.isConfigured, draft.ingredientLines.isEmpty else { return draft }

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
        \(chefGuidance)
        \(mergeGuidance)
        \(servingsGuidance)
        - tags: up to 5 lowercase tags.
        - If you cannot tell what dish this is, return {}.
        """

        do {
            let drafted = try await client.chatJSON(
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
