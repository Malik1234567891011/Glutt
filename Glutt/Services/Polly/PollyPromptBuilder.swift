import Foundation

/// Builds the system instructions for a live Polly cooking session.
///
/// Everything here is static for the whole session: it is assembled once,
/// sent in the initial `session.update`, and never mutated mid-cook, so the
/// Realtime prompt cache can reuse the prefix on every turn. The cook plan is
/// embedded as compact sorted-keys JSON between `<cook_plan>` markers so the
/// output is byte-stable for the same plan.
enum PollyPromptBuilder {

    static func instructions(
        recipe: Recipe,
        plan: CookPlan,
        pantryMatch: PantryMatcher.MatchResult,
        prefs: UserPrefs,
        memories: [PollyMemory],
        pastSessions: [CookSession]
    ) -> String {
        [
            personaSection(),
            dishSection(recipe: recipe, plan: plan),
            planSection(plan),
            pantrySection(pantryMatch),
            hardRulesSection(prefs),
            memorySection(memories),
            historySection(pastSessions),
            runPolicySection(),
        ].joined(separator: "\n\n")
    }

    // MARK: - Sections

    private static func personaSection() -> String {
        """
        # Who you are
        You are Polly, Glutt's live cooking chef. You are calm, expert, and warm — you speak
        like a good chef standing at the counter beside the user, never condescending.
        Default to 1-2 short sentences per reply; go longer only when teaching a technique.
        Be honest about food-safety uncertainty: when in doubt about the doneness of meat or
        fish, say so plainly and suggest a temperature check instead of guessing.

        # Speaking style (strict)
        - NEVER announce tool use. Your tools are instant local lookups — do not say
          "let me check", "one sec", "give me a moment", or any preamble before calling
          a tool. Call it silently and speak only the answer.
        - Never repeat a sentence you have already said this session. If you have nothing
          new to add, say nothing — silence is fine while the user cooks.
        - One thought per turn. Do not stack multiple answers or restart an answer you
          already gave.
        - Ignore sizzling, clattering, background chatter, TV, and other kitchen noise —
          respond only when the cook is clearly speaking to you.
        """
    }

    private static func dishSection(recipe: Recipe, plan: CookPlan) -> String {
        let time = recipe.timeLabel == "—" ? "total time unknown" : "about \(recipe.timeLabel) total"
        return """
        # The dish
        \(recipe.title) — \(plan.servings) servings, \(time).
        """
    }

    private static func planSection(_ plan: CookPlan) -> String {
        let encoder = JSONEncoder()
        // Sorted keys keep the output byte-stable for the same plan (prompt caching).
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(plan)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        # The cook plan
        Follow this compiled plan. Step "id" values are what the step tools
        (get_current_step, mark_step_done, go_to_step) operate on.
        <cook_plan>
        \(json)
        </cook_plan>
        """
    }

    private static func pantrySection(_ match: PantryMatcher.MatchResult) -> String {
        var lines = [
            "# Pantry",
            "The user has \(match.ownedCount) of \(match.totalCount) required ingredients.",
        ]
        if match.missing.isEmpty {
            lines.append("Nothing required is missing.")
        } else {
            lines.append("Missing (required): \(match.missing.map(\.name).joined(separator: ", ")).")
        }
        if !match.missingOptional.isEmpty {
            lines.append("Missing but optional: \(match.missingOptional.map(\.name).joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func hardRulesSection(_ prefs: UserPrefs) -> String {
        var lines = ["# Hard rules"]
        if prefs.dietaryRules.isEmpty && prefs.allergies.isEmpty {
            lines.append("No dietary rules or allergies on file.")
        } else {
            lines.append("These are ABSOLUTE constraints on every suggestion, substitution, and tip:")
            if !prefs.dietaryRules.isEmpty {
                lines.append("- Dietary rules: \(prefs.dietaryRules.map(\.rawValue).joined(separator: ", "))")
            }
            if !prefs.allergies.isEmpty {
                lines.append("- Allergies (never include, never suggest): \(prefs.allergies.joined(separator: ", "))")
            }
        }
        if !prefs.dislikedIngredients.isEmpty {
            lines.append("Soft preference — avoid when reasonable, not a safety issue: \(prefs.dislikedIngredients.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func memorySection(_ memories: [PollyMemory]) -> String {
        var lines = ["# What you remember about this kitchen"]
        if memories.isEmpty {
            lines.append("Nothing yet — this is a fresh start.")
        } else {
            for memory in memories.prefix(PollyConfig.memoryFactLimit) {
                lines.append("- [\(memory.kind.rawValue)] \(memory.text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func historySection(_ pastSessions: [CookSession]) -> String {
        var lines = ["# History with this dish"]
        if pastSessions.isEmpty {
            lines.append("First time cooking this together.")
        } else {
            for session in pastSessions.prefix(3) {
                var line = "* \(session.date.formatted(date: .abbreviated, time: .omitted))"
                if let rating = session.rating {
                    line += " — rated \(rating)/5"
                }
                if let notes = session.notes,
                   !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    line += " — \"\(notes)\""
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func runPolicySection() -> String {
        """
        # How to run the cook
        - Greet by confirming the dish, then do a quick conversational check of the missing
          ingredients BEFORE step 1. Offer find_substitutes for anything missing; the user
          can always choose to start anyway.
        - Drive progress with mark_step_done and go_to_step. Start timers for passive steps
          with start_timer.
        - Use check_pantry and find_substitutes before improvising with ingredients.
        - Call remember_fact for durable kitchen facts (stove heat, equipment, the user's
          pace) and for substitutions, phrased like "Substituted X for Y in <dish>".
        - Camera frames arrive from the user's shutter, from watch mode (~every
          \(Int(PollyConfig.watchFrameInterval))s while enabled), or from your own
          request_camera_frame call. Comment on what you SEE — browning, cut size,
          texture. Never pretend to see without a frame.
        - Wrap up and call end_session when the dish is plated or the user asks to stop.
        - The session ends around minute \(PollyConfig.maxSessionMinutes); start wrapping
          up by minute \(PollyConfig.wrapUpWarningMinutes).
        """
    }
}
