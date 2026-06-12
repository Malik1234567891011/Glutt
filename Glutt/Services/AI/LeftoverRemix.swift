import Foundation

/// "Turn this into something else" — transformation ideas for leftovers.
/// Built-in table covers the common bases offline; the LLM personalizes
/// with the user's actual pantry when configured.
enum LeftoverRemix {

    struct Idea: Decodable, Identifiable, Equatable {
        var id: String { title }
        let title: String
        /// 1–2 sentences a tired person can follow.
        let how: String
        /// Things they'd likely need beyond the leftover itself.
        let needs: [String]
    }

    // MARK: - Entry point

    static func ideas(
        for leftover: Leftover,
        pantry: [PantryItem],
        rules: [DietaryRule],
        allergies: [String]
    ) async -> [Idea] {
        if LLMClient.isConfigured {
            if let ai = try? await llmIdeas(
                for: leftover, pantry: pantry, rules: rules, allergies: allergies
            ), !ai.isEmpty {
                return ai
            }
        }
        return tableIdeas(for: leftover.title)
    }

    // MARK: - Offline table

    /// Keyword → transformations. Deliberately humble: real combinations
    /// people actually make at 7pm, not chef fantasies.
    static func tableIdeas(for title: String) -> [Idea] {
        let lowered = title.lowercased()

        if lowered.contains("chicken") {
            return [
                Idea(title: "Chicken wraps", how: "Shred it, warm it in a pan, roll into tortillas with whatever crunchy vegetables you have.", needs: ["tortillas"]),
                Idea(title: "Chicken fried rice", how: "Dice it and toss into hot rice with soy sauce, egg, and frozen peas.", needs: ["rice", "egg", "soy sauce"]),
                Idea(title: "Chicken salad bowl", how: "Slice it cold over greens with a sharp dressing — done in five minutes.", needs: ["greens", "dressing"]),
            ]
        }
        if lowered.contains("rice") {
            return [
                Idea(title: "Fried rice", how: "Day-old rice is the best fried rice. Hot pan, oil, egg, soy sauce, anything else you find.", needs: ["egg", "soy sauce"]),
                Idea(title: "Rice bowl", how: "Reheat, top with a fried egg and whatever protein or pickles you have.", needs: ["egg"]),
                Idea(title: "Quick rice soup", how: "Simmer in broth with frozen vegetables for ten minutes.", needs: ["broth"]),
            ]
        }
        if lowered.contains("beef") || lowered.contains("steak") {
            return [
                Idea(title: "Beef tacos", how: "Chop, reheat with a little cumin and chili, pile into tortillas.", needs: ["tortillas"]),
                Idea(title: "Steak sandwich", how: "Slice thin, stack on toasted bread with mustard or mayo and something crunchy.", needs: ["bread"]),
                Idea(title: "Beef pasta", how: "Chop into a quick tomato sauce while the pasta boils.", needs: ["pasta", "tomato sauce"]),
            ]
        }
        if lowered.contains("pasta") || lowered.contains("noodle") {
            return [
                Idea(title: "Pasta frittata", how: "Mix with beaten eggs and cheese, fry until golden on both sides. Genuinely great.", needs: ["eggs", "cheese"]),
                Idea(title: "Crispy pan pasta", how: "Fry it in olive oil until the edges crisp, finish with cheese.", needs: ["olive oil"]),
            ]
        }
        if lowered.contains("salmon") || lowered.contains("fish") {
            return [
                Idea(title: "Fish cakes", how: "Flake, mix with mashed potato and an egg, pan-fry until golden.", needs: ["potato", "egg"]),
                Idea(title: "Fish rice bowl", how: "Flake over warm rice with soy sauce, sesame, and cucumber.", needs: ["rice"]),
            ]
        }
        if lowered.contains("soup") || lowered.contains("stew") || lowered.contains("chili") {
            return [
                Idea(title: "Over rice or pasta", how: "Reduce it a little and serve over a fresh starch — feels like a different meal.", needs: ["rice or pasta"]),
                Idea(title: "Loaded baked potato", how: "Spoon it hot over a baked potato with cheese.", needs: ["potato"]),
            ]
        }

        // Generic fallbacks that work for almost anything cooked.
        return [
            Idea(title: "Wrap it", how: "Almost anything cooked becomes lunch inside a warm tortilla with something fresh.", needs: ["tortillas"]),
            Idea(title: "Rice bowl it", how: "Serve it over fresh rice with a fried egg on top.", needs: ["rice", "egg"]),
        ]
    }

    // MARK: - LLM upgrade

    private struct LLMResponse: Decodable {
        let ideas: [Idea]
    }

    private static func llmIdeas(
        for leftover: Leftover,
        pantry: [PantryItem],
        rules: [DietaryRule],
        allergies: [String]
    ) async throws -> [Idea] {
        let system = """
        You suggest ways to transform leftovers into a different meal. Return JSON:
        {"ideas": [{"title": str, "how": str, "needs": [str]}]}
        - 3 ideas, most practical first. The user is tired; keep "how" to 1-2 plain sentences.
        - "needs": only ingredients beyond the leftover itself, lowercase, max 3. Prefer things from their pantry list.
        - Real home cooking, not chef fantasies.
        - Never suggest anything violating the dietary rules or allergies listed.
        """

        var user = "Leftover: \(leftover.title) (\(leftover.servingsRemaining.formatted()) servings, \(leftover.ageInDays) days old)\n"
        let pantryNames = pantry.filter { $0.roughQuantity != .out }.map(\.name).prefix(40)
        if !pantryNames.isEmpty {
            user += "Their pantry: \(pantryNames.joined(separator: ", "))\n"
        }
        if !rules.isEmpty {
            user += "Dietary rules: \(rules.map(\.label).joined(separator: ", "))\n"
        }
        if !allergies.isEmpty {
            user += "Allergies (NEVER include): \(allergies.joined(separator: ", "))\n"
        }

        let response = try await LLMClient.chatJSON(
            LLMResponse.self,
            system: system,
            user: user,
            temperature: 0.6,
            timeout: 20
        )
        return Array(response.ideas.prefix(3))
    }
}
