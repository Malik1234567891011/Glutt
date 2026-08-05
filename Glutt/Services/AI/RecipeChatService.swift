import Foundation
import SwiftData

/// A rewrite the chef offered mid-conversation. Nothing here has touched the
/// library yet — it becomes a recipe version only when the cook taps Apply.
struct RecipeChatProposal: Codable {
    /// Short name for the version this would create ("No-pork version").
    var versionLabel: String
    /// Ingredient lines as plain text ("2 tbsp olive oil"), parsed on apply.
    var ingredients: [String]
    var steps: [String]
    /// Human-readable change list, shown on the card before the cook commits.
    var changes: [String]
    var summary: String?
    var servings: Int?

    /// `"pantry"` for the local swap plan, which owns its own apply path and
    /// carries no rewritten text. Absent (the LLM's own output never sets it)
    /// means a normal rewrite.
    var kind: String?

    /// Whether this came from `RecipeOptimizer` rather than the chef, and so
    /// must be re-planned and applied through `RecipeOptimizer.apply` — that
    /// path preserves quantities, units, and optional flags instead of
    /// round-tripping every ingredient through text.
    var isPantryPlan: Bool { kind == "pantry" }

    /// Bridges to the existing version-creation path, so chat, "Make it…", and
    /// anything later all mint versions the same way.
    func adjustment(defaultServings: Int) -> RecipeAdjuster.Adjustment {
        RecipeAdjuster.Adjustment(
            ingredients: ingredients,
            steps: steps,
            changes: changes,
            summary: summary,
            servings: servings ?? defaultServings
        )
    }
}

extension RecipeChatProposal {
    /// Hand-written so a proposal missing an array decodes to an empty one
    /// instead of throwing. The synthesized decoder would take the whole turn
    /// down over a dropped key, losing a perfectly good answer along with the
    /// half-formed rewrite — and `RecipeChatService.reply` already discards a
    /// proposal that came back unusable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        versionLabel = (try? container.decode(String.self, forKey: .versionLabel)) ?? "My version"
        ingredients = (try? container.decode([String].self, forKey: .ingredients)) ?? []
        steps = (try? container.decode([String].self, forKey: .steps)) ?? []
        changes = (try? container.decode([String].self, forKey: .changes)) ?? []
        summary = try? container.decode(String.self, forKey: .summary)
        servings = try? container.decode(Int.self, forKey: .servings)
        kind = try? container.decode(String.self, forKey: .kind)
    }
}

/// The text chef. Same Polly, different mode: this one answers questions about
/// a dish before you cook it, and offers a rewrite when the answer amounts to
/// one.
///
/// A sibling of `PollyPromptBuilder` rather than a reuse of it. That prompt is
/// most of the way built out of things that only exist in a live voice session
/// (wake phrase, tool-call silence, "who was that audio for"), so sharing it
/// would mean teaching a text chat to ignore rules it can't break.
enum RecipeChatService {

    /// Tags the proxy's `ai_usage` row. Every one-shot feature shares
    /// `/chat/completions`, so without this the spend is unreadable.
    static let usageFeature = "recipe_chat"

    struct Envelope: Decodable {
        let reply: String
        let proposal: RecipeChatProposal?
    }

    struct Context {
        let recipe: Recipe
        let servings: Int
        let pantryMatch: PantryMatcher.MatchResult
        let prefs: UserPrefs
        let ownedTools: [KitchenTool]
    }

    // MARK: - Opening chips

    /// A tap that starts the conversation for you. An empty chat with a blinking
    /// cursor is the version of this feature nobody uses.
    struct Suggestion: Identifiable {
        enum Action {
            /// Sends this text as if the cook had typed it.
            case ask(String)
            /// Runs `RecipeOptimizer` on device: instant, free, and the only
            /// thing here that actually knows what is in their fridge.
            case pantryPlan
        }

        let id: String
        let label: String
        let action: Action
    }

    /// At most five, most specific first. Beyond that it stops reading as
    /// "here is what I can do" and starts reading as a menu.
    static func suggestions(_ context: Context) -> [Suggestion] {
        var chips: [Suggestion] = []

        if !context.pantryMatch.missing.isEmpty {
            chips.append(Suggestion(id: "pantry", label: "Use what I have", action: .pantryPlan))
        }

        let conflicts = DietGuard.conflicts(
            in: context.recipe,
            rules: context.prefs.dietaryRules,
            allergies: context.prefs.allergies,
            dislikes: context.prefs.dislikedIngredients
        )
        if let conflict = conflicts.first(where: { $0.severity != .dislike }) {
            chips.append(Suggestion(
                id: "conflict",
                label: "Swap the \(conflict.ingredientName)",
                action: .ask("I can't use \(conflict.ingredientName). What should I use instead?")
            ))
        } else if !context.prefs.dietaryRules.isEmpty {
            chips.append(Suggestion(
                id: "rules",
                label: "Match my food rules",
                action: .ask("Rewrite this so it matches my food rules.")
            ))
        }

        chips.append(Suggestion(id: "protein", label: "Higher protein",
                                action: .ask("Make it higher protein.")))
        chips.append(Suggestion(id: "lighter", label: "Lighter",
                                action: .ask("Make it lighter.")))
        chips.append(Suggestion(id: "cheaper", label: "Cheaper",
                                action: .ask("Make it cheaper.")))

        return Array(chips.prefix(5))
    }

    /// The local pantry plan, dressed as a proposal so it lands in the thread
    /// looking like every other offer. Nil when there is nothing worth swapping.
    static func pantryProposal(for recipe: Recipe, plan: RecipeOptimizer.Plan) -> RecipeChatProposal? {
        guard plan.isWorthIt else { return nil }
        return RecipeChatProposal(
            versionLabel: "Pantry version",
            // Empty on purpose: this proposal is re-planned against the pantry
            // at the moment Apply is tapped, and applied through
            // `RecipeOptimizer`, which keeps quantities and units intact.
            ingredients: [],
            steps: [],
            changes: plan.swaps.map { "\($0.original.name) becomes \($0.substituteName)" },
            summary: nil,
            servings: nil,
            kind: "pantry"
        )
    }

    /// What the chef "says" alongside the local plan. Written here rather than
    /// in the view so the two apply paths read the same in the transcript.
    static func pantryReply(for plan: RecipeOptimizer.Plan) -> String {
        var lines: [String] = []
        if plan.swaps.isEmpty {
            lines.append("There is nothing in your kitchen I can swap in for what's missing.")
        } else {
            let count = plan.swaps.count
            lines.append("I can cover \(count) missing \(count == 1 ? "ingredient" : "ingredients") with what you already have.")
        }
        if !plan.essentialWarnings.isEmpty {
            let names = plan.essentialWarnings.map(\.name).joined(separator: ", ")
            lines.append("Worth grabbing rather than swapping: \(names). Substituting those changes the dish.")
        }
        if !plan.unresolved.isEmpty {
            let names = plan.unresolved.map(\.name).joined(separator: ", ")
            lines.append("No good stand in for: \(names). Ask me and I'll think of something.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: - The call

    static func reply(
        to question: String,
        context: Context,
        history: [RecipeChatMessage],
        client: LLMClient = .live
    ) async throws -> Envelope {
        var messages: [LLMClient.Message] = [.system(systemPrompt(context))]
        messages.append(contentsOf: replayable(history))
        messages.append(.user(String(question.prefix(2000))))

        let envelope = try await client.chatJSON(
            Envelope.self,
            messages: messages,
            temperature: 0.4,
            feature: usageFeature,
            timeout: 45
        )
        guard !envelope.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMClient.LLMError.badResponse("Empty reply")
        }
        // A proposal missing either half can't be applied, and a half-applied
        // rewrite is worse than none. Drop it and keep the answer.
        if let proposal = envelope.proposal, proposal.ingredients.isEmpty || proposal.steps.isEmpty {
            return Envelope(reply: envelope.reply, proposal: nil)
        }
        return envelope
    }

    /// The tail of the thread, as wire messages.
    ///
    /// Only the last `contextTurns` go: the whole recipe context rides along
    /// with every single turn, so history is the cheapest thing to cut and the
    /// least missed.
    private static func replayable(_ history: [RecipeChatMessage]) -> [LLMClient.Message] {
        history.suffix(RecipeChatStore.contextTurns).map { message in
            switch message.role {
            case .user:
                return .user(message.text)
            case .assistant:
                // The proposal itself is not re-sent (hundreds of tokens of
                // ingredients and steps the cook may never have applied), but a
                // one-line trace of it is, so "make that one 4 servings" still
                // has something to point at.
                guard let proposal = message.proposal else { return .assistant(message.text) }
                let trace = "[offered a version: \(proposal.versionLabel) — \(proposal.changes.joined(separator: "; "))]"
                return .assistant("\(message.text)\n\(trace)")
            }
        }
    }

    // MARK: - Prompt

    static func systemPrompt(_ context: Context) -> String {
        [
            personaSection(),
            dishSection(context),
            ingredientsSection(context),
            stepsSection(context),
            pantrySection(context.pantryMatch),
            toolsSection(context.ownedTools),
            hardRulesSection(context.prefs),
            outputSection(context),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func personaSection() -> String {
        """
        # Who you are
        You are Glutt's chef, answering questions about one specific dish by text before the
        cook starts cooking. You are calm, expert, and warm, like a good chef reading the recipe
        over their shoulder. Never condescending.

        # How you write
        - 1 to 3 short sentences. Go longer only when genuinely teaching a technique.
        - Answer the question that was asked. Do not re-narrate the recipe.
        - Never use dashes of any kind in your reply text. Use commas, full stops, or rewrite
          the sentence. This is a house style rule and it has no exceptions.
        - Be honest about food safety. When doneness is uncertain, say so and point at a
          temperature rather than guessing.
        - If something is outside cooking entirely, say so in one line and steer back.

        # Substitutions: be honest, not agreeable
        - FLEXIBLE (a spice, a herb, a garnish, citrus, anything optional): reassure them. The
          dish is still good without it or with a swap.
        - ESSENTIAL with no clean substitute (the thing the dish is built on, the chicken in a
          chicken dish, the pasta in a pasta dish): say plainly that it will not turn out well
          and there is no good swap, so it is worth grabbing or picking another recipe. Never
          pretend a core swap is fine when it isn't.
        - If they have a close cousin of a missing item (thighs when the recipe wants breast,
          one chili for another), use it.
        - The cook's word about what they have always wins over the pantry list below.
        """
    }

    private static func dishSection(_ context: Context) -> String {
        let recipe = context.recipe
        let time = recipe.timeLabel == "—" ? "total time unknown" : "about \(recipe.timeLabel) total"
        var lines = [
            "# The dish",
            "\(recipe.title) — \(context.servings) servings, \(time), \(recipe.difficulty.label.lowercased()).",
        ]
        if let summary = recipe.summary, !summary.isEmpty {
            lines.append(summary)
        }
        if recipe.isCookingBasic {
            lines.append("This is a technique lesson, not a plated dinner recipe. Teach it as one.")
        }
        return lines.joined(separator: "\n")
    }

    private static func ingredientsSection(_ context: Context) -> String {
        let recipe = context.recipe
        let base = max(1, recipe.servings)
        let scale = Double(context.servings) / Double(base)
        var lines = ["# Ingredients (for \(context.servings) servings)"]
        for ingredient in recipe.ingredients.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            if let amount = UnitConverter.display(
                quantity: ingredient.quantity, unit: ingredient.unit, scale: scale) {
                lines.append("- \(amount) \(ingredient.name)")
            } else {
                lines.append("- \(ingredient.name) (no amount given)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func stepsSection(_ context: Context) -> String {
        let steps = context.recipe.steps.sorted { $0.index < $1.index }
        guard !steps.isEmpty else { return "" }
        var lines = ["# Method"]
        for (offset, step) in steps.enumerated() {
            lines.append("\(offset + 1). \(step.text)")
        }
        return lines.joined(separator: "\n")
    }

    private static func pantrySection(_ match: PantryMatcher.MatchResult) -> String {
        var lines = [
            "# Their pantry",
            "They have \(match.ownedCount) of \(match.totalCount) required ingredients.",
        ]
        if match.missing.isEmpty {
            lines.append("Nothing required is missing.")
        } else {
            lines.append("Missing (required): \(match.missing.map(\.name).joined(separator: ", ")).")
        }
        if !match.missingOptional.isEmpty {
            lines.append("Missing but optional: \(match.missingOptional.map(\.name).joined(separator: ", ")).")
        }
        lines.append("""
        This list is often stale or empty, because many cooks never fill it in. Never \
        contradict the cook with it.
        """)
        return lines.joined(separator: "\n")
    }

    private static func toolsSection(_ tools: [KitchenTool]) -> String {
        var lines = ["# Their equipment"]
        if tools.isEmpty {
            lines.append("""
            Not listed. Assume a basic kitchen (stove, oven, a knife, everyday pans and bowls) \
            and ask before relying on anything specialized.
            """)
        } else {
            lines.append("They own: \(tools.sorted { $0.name < $1.name }.map(\.name).joined(separator: ", ")).")
            lines.append("Work with that. Offer a workaround rather than assuming gear they haven't listed.")
        }
        return lines.joined(separator: "\n")
    }

    private static func hardRulesSection(_ prefs: UserPrefs) -> String {
        var lines = ["# Hard rules"]
        if prefs.dietaryRules.isEmpty && prefs.allergies.isEmpty {
            lines.append("No dietary rules or allergies on file.")
        } else {
            lines.append("ABSOLUTE constraints on every answer, suggestion, and rewrite:")
            if !prefs.dietaryRules.isEmpty {
                lines.append("- Dietary rules: \(prefs.dietaryRules.map(\.rawValue).joined(separator: ", "))")
            }
            if !prefs.allergies.isEmpty {
                lines.append("- Allergies (never include, never suggest): \(prefs.allergies.joined(separator: ", "))")
            }
        }
        if !prefs.dislikedIngredients.isEmpty {
            lines.append("Soft preference, avoid when reasonable: \(prefs.dislikedIngredients.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func outputSection(_ context: Context) -> String {
        """
        # What you return
        JSON only, this exact shape:
        {"reply": "what you say to the cook",
         "proposal": null}

        Set "proposal" to null for anything that is only a question: temperatures, timings,
        storage, why a sauce splits, whether they can freeze it. Most turns are this.

        Set "proposal" to a full rewrite when the cook asks you to change the recipe, or names
        a constraint that makes it unusable as written (an ingredient they don't have, a rule it
        breaks, a piece of equipment they lack). Then it looks like this:
        {"reply": "short line saying what you changed and why",
         "proposal": {
           "versionLabel": "2 to 3 words, e.g. No-pork version",
           "changes": ["Swapped X for Y", "..."],
           "summary": "one sentence, or null",
           "servings": \(context.servings),
           "ingredients": ["2 tbsp olive oil", "..."],
           "steps": ["...", "..."]
         }}

        Rules for a proposal:
        - "ingredients" and "steps" are the COMPLETE new recipe, not just the changed lines.
        - Write amounts for \(context.servings) servings and set "servings" to \(context.servings),
          unless the change itself alters how many it feeds.
        - Keep everything the cook didn't ask you to touch exactly as it is.
        - "changes" is what a person would want to read before accepting. Be specific.
        - Never propose something that breaks a hard rule above.
        - Do not use dashes in "reply", "summary", "changes", or "versionLabel".
        """
    }
}
