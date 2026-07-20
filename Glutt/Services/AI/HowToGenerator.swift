import Foundation
import SwiftData

/// Turns a user's free-text request ("how to cook rice", "grilled cheese") into a
/// Cooking Basics lesson — chef-beside-you steps, not a thin recipe card.
enum HowToGenerator {

    enum GenerateError: LocalizedError {
        case notConfigured
        case emptyRequest
        case rejected(String)
        case failed

        var errorDescription: String? {
            switch self {
            case .notConfigured: "AI isn’t available in this build."
            case .emptyRequest: "Tell me what you want to learn how to do."
            case .rejected(let reason): reason
            case .failed: "Couldn’t build that how-to. Try again in a moment."
            }
        }
    }

    private struct Draft: Decodable {
        var ok: Bool?
        var rejectReason: String?
        var title: String?
        var summary: String?
        var servings: Int?
        var prepMinutes: Int?
        var cookMinutes: Int?
        var ingredients: [String]?
        var steps: [String]?
        var notes: String?
        var tags: [String]?
        var calories: Int?
        var proteinGrams: Int?
        var carbGrams: Int?
        var fatGrams: Int?
    }

    /// Generates a basics `Recipe` ready to insert. Does not save.
    static func generate(
        request: String,
        prefs: UserPrefs? = nil,
        client: LLMClient = .live
    ) async throws -> Recipe {
        guard client.isConfigured else { throw GenerateError.notConfigured }
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GenerateError.emptyRequest }

        let system = """
        You write Glutt “Cooking Basics” lessons — technique how-tos that feel like a \
        patient pro chef standing at the stove next to a first-timer who has never done this.

        This is NOT a plated dinner recipe dump and NOT a short TikTok caption. It is coaching \
        for one fundamental skill (fry an egg, cook rice, grilled cheese, boil pasta, scramble \
        eggs, cook bacon, toast in a pan, etc.).

        Return JSON only with this shape:
        {"ok": true,
         "title": str,
         "summary": str,
         "servings": int,
         "prepMinutes": int,
         "cookMinutes": int,
         "ingredients": [str],
         "steps": [str],
         "notes": str,
         "tags": [str],
         "calories": int|null,
         "proteinGrams": int|null,
         "carbGrams": int|null,
         "fatGrams": int|null}

        Or if the request is NOT a cooking / food technique:
        {"ok": false, "rejectReason": "short friendly explanation"}

        GOLD STANDARD — match the depth of a fried-egg coaching lesson:
        - Title: "How to …" when it fits (e.g. "How to Cook Rice", "How to Make a Grilled Cheese").
        - summary: one honest sentence about what “good” looks/tastes like when finished.
        - ingredients: "quantity unit ingredient" lines when amounts matter; append "(optional)" for optional. \
          Only the basic version. Include water/salt/oil/butter when actually used.
        - steps: 6–10 steps. EACH step MUST be spoken coaching with sensory checkpoints. Required in nearly every step:
            • ACTION — what to do with hands/heat/gear (pan size/type when it matters: nonstick, pot+lid, etc.)
            • LOOK FOR — concrete visual cues (“butter fully melts and coats the pan”, “foam bubbles then settles \
              to a calm glossy film — not smoking, not browning”, “white goes clear → cloudy → opaque from the edges”, \
              “steam rising”, “golden-brown spots on bread”, “water at a rolling boil vs gentle simmer”)
            • LISTEN / FEEL when useful (“soft sizzle not angry spit”, “hiss when lid goes on”, “spatula slides under easily”)
            • DONE CHECK — how they know this stage is finished (not only “wait 3 minutes”). Times as “about X minutes” \
              with “stoves vary — trust the cue.”
          Write in second person (“Tip the…”, “Watch for…”, “You’re ready when…”). Ban vague lines like “cook until done” \
          or “heat the pan” with no cue. If heat/fat is involved, dedicate a step (or half a step) to reading the fat/pan readiness.
        - notes: short paragraph with (1) common failure recovery, (2) one useful variant if natural, \
          (3) brief food-safety callout when relevant (runny eggs, undercooked meat, rice leftover cooling). Don’t lecture.
        - tags: up to 5 lowercase tags like "rice", "technique", "breakfast". Do NOT include "basics" — we add that.
        - Nutrition: rough per-serving estimates when obvious; null if you can’t estimate honestly.
        - Beginner-safe defaults when techniques disagree (forgiving pan + moderate heat over advanced methods).
        - Never invent dangerous advice. Prefer “approximately” over false precision.
        - Keep ONE focused technique. If they ask for a full multi-course meal, reject and ask for a single basic skill.
        """

        var user = "USER REQUEST: \(trimmed)"
        if let prefs {
            if !prefs.dietaryRules.isEmpty {
                user += "\nDIETARY RULES (respect): \(prefs.dietaryRules.map(\.label).joined(separator: ", "))"
            }
            if !prefs.allergies.isEmpty {
                user += "\nALLERGIES (never include): \(prefs.allergies.joined(separator: ", "))"
            }
        }

        let draft: Draft
        do {
            draft = try await client.chatJSON(
                Draft.self,
                system: system,
                user: user,
                temperature: 0.45,
                timeout: 60
            )
        } catch {
            throw GenerateError.failed
        }

        if draft.ok == false {
            throw GenerateError.rejected(
                draft.rejectReason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "That doesn’t look like a cooking how-to. Try something like “how to cook rice.”"
            )
        }

        guard let steps = draft.steps?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }),
              steps.count >= 4,
              let ingredientLines = draft.ingredients?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }),
              !ingredientLines.isEmpty
        else { throw GenerateError.failed }

        var title = (draft.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = trimmed.hasPrefix("How to") || trimmed.hasPrefix("how to")
                ? trimmed.prefix(1).uppercased() + trimmed.dropFirst()
                : "How to \(trimmed)"
        }

        var recipeDraft = ImportedRecipeDraft()
        recipeDraft.title = title
        recipeDraft.summary = draft.summary
        recipeDraft.creator = "Glutt Basics"
        recipeDraft.platform = .manual
        recipeDraft.servings = max(1, draft.servings ?? 1)
        recipeDraft.prepMinutes = max(0, draft.prepMinutes ?? 0)
        recipeDraft.cookMinutes = max(0, draft.cookMinutes ?? 0)
        recipeDraft.ingredientLines = ingredientLines
        recipeDraft.stepTexts = steps
        recipeDraft.calories = draft.calories
        recipeDraft.proteinGrams = draft.proteinGrams
        recipeDraft.carbGrams = draft.carbGrams
        recipeDraft.fatGrams = draft.fatGrams
        recipeDraft.nutritionIsEstimated = true
        recipeDraft.isAIGenerated = true

        var tags = (draft.tags ?? []).map { $0.lowercased() }
            .filter { !$0.isEmpty && $0 != CookingBasics.tag }
        tags.insert(CookingBasics.tag, at: 0)
        if !tags.contains("technique") { tags.append("technique") }
        recipeDraft.tags = Array(tags.prefix(6))

        let recipe = RecipeFactory.make(from: recipeDraft)
        recipe.notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        recipe.sourceCreator = "Glutt Basics"
        if !recipe.tags.contains(CookingBasics.tag) {
            recipe.tags.insert(CookingBasics.tag, at: 0)
        }
        // Parser doesn't always catch "(optional)" — mark those ingredients.
        for ingredient in recipe.ingredients {
            let blob = "\(ingredient.name) \(ingredient.note ?? "")".lowercased()
            if blob.contains("optional") { ingredient.isOptional = true }
        }
        return recipe
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
