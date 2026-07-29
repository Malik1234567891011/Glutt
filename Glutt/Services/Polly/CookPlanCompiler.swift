import CryptoKit
import Foundation

/// Compiles a Recipe into a `CookPlan` execution graph with one LLM call,
/// cached on disk so repeat cooks are instant and work offline. Any failure —
/// proxy unconfigured, network down, malformed JSON — degrades to the
/// deterministic `CookPlan.linear(from:scale:)` so a session can always run.
enum CookPlanCompiler {

    /// Where compiled plans live between launches. `var` so tests can point
    /// it at a throwaway temp directory; created on demand by `store`.
    static var cacheDirectory: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PollyPlans", isDirectory: true)
    }()

    // MARK: - Cache

    /// Content hash of everything that shapes a plan: title, step texts,
    /// ingredient names, and the serving scale. Stable across launches
    /// (unlike persistentModelID) and changes whenever the recipe does.
    static func cacheKey(recipe: Recipe, scale: Double) -> String {
        let ingredientNames = recipe.ingredients
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
            .joined(separator: "|")
        let material = recipe.title
            + "|" + recipe.sortedSteps.map(\.text).joined(separator: "|")
            + "|" + ingredientNames
            + "|" + String(format: "%.2f", scale)
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func cachedPlan(forKey key: String) -> CookPlan? {
        let url = cacheDirectory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CookPlan.self, from: data)
    }

    static func store(_ plan: CookPlan, forKey key: String) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true
        )
        try? data.write(
            to: cacheDirectory.appendingPathComponent("\(key).json"),
            options: .atomic
        )
    }

    // MARK: - Compile

    /// Cache hit → cached plan. Otherwise one LLM call; success is stored
    /// for next time, ANY failure returns the linear fallback — never
    /// cached, so the next attempt retries the real compile.
    static func compile(
        recipe: Recipe,
        scale: Double,
        llm: (String, String) async throws -> CookPlan = { system, user in
            try await LLMClient.live.chatJSON(CookPlan.self, system: system, user: user,
                                              temperature: 0.2, timeout: 45)
        }
    ) async -> CookPlan {
        let key = cacheKey(recipe: recipe, scale: scale)
        if let cached = cachedPlan(forKey: key) {
            let upgraded = cached.ensuringLeadingPrep()
            if upgraded != cached {
                store(upgraded, forKey: key)
                PollyDebugLog.shared.log("plan: cache HIT, upgraded with Prep (\(key.prefix(8)))")
            } else {
                PollyDebugLog.shared.log("plan: cache HIT (\(key.prefix(8)))")
            }
            return upgraded
        }
        PollyDebugLog.shared.log("plan: cache MISS (\(key.prefix(8)))")
        guard LLMClient.isConfigured else {
            return CookPlan.linear(from: recipe, scale: scale)
        }
        do {
            var plan = try await llm(systemPrompt, userPrompt(recipe: recipe, scale: scale))
            plan.isFallback = false
            plan = plan.ensuringLeadingPrep()
            store(plan, forKey: key)
            PollyDebugLog.shared.log("plan: compiled via LLM, stored (\(plan.steps.count) steps)")
            return plan
        } catch {
            // AI is never load-bearing: the linear plan narrates the raw steps.
            PollyDebugLog.shared.log("plan: LLM compile FAILED (\(error.localizedDescription)) — linear fallback, not cached")
            return CookPlan.linear(from: recipe, scale: scale)
        }
    }

    // MARK: - Prompts

    private static let systemPrompt = """
    You are an expert chef converting a home recipe into a strict JSON execution graph
    that a live cooking assistant will follow step by step, out loud, in a real kitchen.
    Return JSON only, with this exact shape:
    {"title": str, "servings": int,
     "mise": [{"name": str, "prep": str}],
     "equipment": [str],
     "steps": [{"id": str, "index": int, "title": str, "instruction": str,
                "kind": "prep"|"active"|"passive"|"checkpoint",
                "estimatedSeconds": int|null, "timerSeconds": int|null,
                "dependsOn": [str], "visualCheck": str|null, "recovery": str|null,
                "ingredientNames": [str]}]}

    Field docs:
    - title: the dish name, unchanged.
    - servings: the scaled serving count you were given.
    - mise: KNIFE / BOARD work only — wash, peel, dice, slice, chop, mince, pat dry, \
    room-temp proteins. Do NOT put spices, salt, pepper, oils, vinegars, stocks, or \
    "measure 1 tsp cumin" in mise. Spices are measured in the cook step when added.
    - equipment: the pans, trays, knives, boards, and tools to pull out before starting.
    - steps: the recipe as an ordered graph. "id" is a short stable slug like "tools", \
    "prep", "s1", "s2"; "index" is the 0-based order.
    - kind: "prep" = Tools or board Prep only (no heat), "active" = hands-on heat work, \
    "passive" = unattended waiting (simmer, bake, rest, marinate), "checkpoint" = a \
    judgement moment (taste, doneness test).
    - timerSeconds: REQUIRED on every "passive" step — the unattended wait in seconds. \
    null on other kinds unless a precise timer genuinely helps.
    - estimatedSeconds: your realistic hands-on estimate for the step, null if unknowable.
    - dependsOn: ids of steps that must be finished first; [] when only the previous \
    step matters.
    - visualCheck: REQUIRED on browning, searing, caramelizing, and doneness-critical \
    steps — one sentence describing exactly what the food should look like. null otherwise.
    - recovery: for common failure points (burning, sticking, breaking, over-salting), \
    one sentence on how to rescue the dish. null otherwise.
    - ingredientNames: the ingredient names this step touches, matching the given list.

    Rules:
    - ALWAYS start with short setup steps BEFORE heat:
      1) id "tools", kind "prep", title "Tools" — only if equipment is non-empty. \
         Instruction: pull those tools onto the counter. dependsOn [].
      2) id "prep", kind "prep", title "Prep" — only if mise has board work. \
         Instruction lists knife work ONLY (dice onion; mince garlic; pat chicken dry). \
         dependsOn ["tools"] when a tools step exists, else [].
    - First heat step (oil in pan, boil water, etc.) dependsOn the last setup step \
      ("prep" if present, else "tools").
    - After Prep is done, cooking steps assume board work is finished: say "add the diced \
      onion", NOT "dice the onion and add it". Do not bury knife work inside heat steps.
    - Keep setup checklists SHORT — never dump spices, measuring, and tools into Prep.
    - Preserve the recipe's intent and order; split run-on instructions into single \
    actions; do NOT invent ingredients or steps that aren't implied by the source.
    - Keep instructions short, imperative, and natural to speak aloud.
    - Keep amounts IN the cook instruction: "add 1 tbsp salt", not "add the salt". If the \
    recipe gives no amount for an ingredient, don't invent a precise number — say "to \
    taste" or "a pinch".
    """

    private static func userPrompt(recipe: Recipe, scale: Double) -> String {
        let scaledServings = max(1, Int((Double(recipe.servings) * scale).rounded()))
        let ingredientLines = recipe.ingredients
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { ingredient in
                if let amount = UnitConverter.display(
                    quantity: ingredient.quantity, unit: ingredient.unit, scale: scale
                ) {
                    return "- \(amount) \(ingredient.name)"
                }
                return "- \(ingredient.name)"
            }
            .joined(separator: "\n")
        let stepLines = recipe.sortedSteps
            .enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")
        return """
        RECIPE: \(recipe.title)
        SERVINGS: \(scaledServings)
        PREP MINUTES: \(recipe.prepMinutes)
        COOK MINUTES: \(recipe.cookMinutes)
        INGREDIENTS:
        \(ingredientLines)
        STEPS:
        \(stepLines)
        """
    }
}
