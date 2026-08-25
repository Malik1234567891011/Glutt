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

    /// Bump when `ensuringLeadingPrep` / setup-step semantics change so a
    /// previously cached plan (e.g. one that dropped cold `kind: prep` steps
    /// and left Crème Brûlée without clip targets) is not reused.
    ///
    /// 3: the prompt learned to schedule rather than transcribe. Every plan
    /// cached before this was compiled under "preserve the recipe's order",
    /// which is exactly what put the potatoes in the oven after the chicken.
    private static let cacheEpoch = 3

    /// Content hash of everything that shapes a plan: title, step texts,
    /// ingredient names, and the serving scale. Stable across launches
    /// (unlike persistentModelID) and changes whenever the recipe does.
    static func cacheKey(recipe: Recipe, scale: Double) -> String {
        let ingredientNames = recipe.ingredients
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.name)
            .joined(separator: "|")
        let material = "v\(cacheEpoch)|"
            + recipe.title
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

    // MARK: - Bundled plans

    /// Recipes whose cook plan ships with the app instead of being compiled.
    ///
    /// Compiling is an LLM call, so the same recipe can produce a different plan
    /// on any two runs: different wording, a different split of steps, and, the
    /// part that matters, a `visualCheck` that may or may not mention the thing
    /// the cook actually needs to look for. That is an acceptable trade for the
    /// library at large and a bad one for a dish being cooked in front of an
    /// audience, where the whole point is that Chef says "they are ready the
    /// moment they float" at the right second.
    ///
    /// So this dish gets a hand-written plan, checked in, used verbatim. Keyed by
    /// recipe title because that is what identifies a bundled dish across
    /// installs; `sourceURL` would be tidier but is re-stamped by content
    /// versions and has gone missing before (see `ChefContent.contentVersion` 5).
    ///
    /// Nothing else changes: the plan is a normal `CookPlan`, it still goes
    /// through `ensuringLeadingPrep`, and the cook has no idea. Delete the entry
    /// and the compiler takes over again.
    static let bundledPlans: [String: String] = [
        "Gnocchi with Brown Butter and Sage": "CookPlan-gnocchi-brown-butter-sage",
    ]

    static func bundledPlan(for recipe: Recipe, bundle: Bundle = .main) -> CookPlan? {
        guard let resource = bundledPlans[recipe.title],
              let url = bundle.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let plan = try? JSONDecoder().decode(CookPlan.self, from: data)
        else { return nil }
        return plan
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
        // Before the cache and before the network: a bundled plan is the answer,
        // every time, offline included.
        if var bundled = bundledPlan(for: recipe) {
            bundled.isFallback = false
            let prepared = bundled.ensuringLeadingPrep(
                ingredients: recipe.ingredients, scale: scale)
            PollyDebugLog.shared.log("plan: bundled plan for \"\(recipe.title)\" (\(prepared.steps.count) steps)")
            return prepared
        }

        let key = cacheKey(recipe: recipe, scale: scale)
        if let cached = cachedPlan(forKey: key) {
            let upgraded = cached.ensuringLeadingPrep(
                ingredients: recipe.ingredients, scale: scale)
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
            plan = plan.ensuringLeadingPrep(ingredients: recipe.ingredients, scale: scale)
            plan = try await repairingSchedule(
                plan, recipe: recipe, scale: scale, llm: llm)
            store(plan, forKey: key)
            PollyDebugLog.shared.log("plan: compiled via LLM, stored (\(plan.steps.count) steps)")
            return plan
        } catch {
            // AI is never load-bearing: the linear plan narrates the raw steps.
            PollyDebugLog.shared.log("plan: LLM compile FAILED (\(error.localizedDescription)) — linear fallback, not cached")
            return CookPlan.linear(from: recipe, scale: scale)
        }
    }

    // MARK: - Schedule repair

    /// One second pass, only when the plan came back with the mistake this is
    /// all about.
    ///
    /// The scheduling rules in the system prompt are the fix; this is how we
    /// know they worked. A prompt instruction is a hope, and "put the slower
    /// dish in first" is exactly the kind of rule a model follows on most
    /// recipes and quietly drops on the one with three things going into an
    /// oven. `CookPlan.schedulingIssues` can see the mistake deterministically,
    /// so the compiler checks its own homework before caching it forever.
    ///
    /// Costs nothing on a correct plan: no issues, no second call. Only
    /// `slowerItemGoesInSecond` triggers it, because that one produces cold
    /// food, while wasted hands-free time only produces a slower cook and is
    /// not worth a round trip or the risk of a worse rewrite.
    private static func repairingSchedule(
        _ plan: CookPlan,
        recipe: Recipe,
        scale: Double,
        llm: (String, String) async throws -> CookPlan
    ) async throws -> CookPlan {
        let conflicts = plan.schedulingIssues.filter {
            if case .slowerItemGoesInSecond = $0.kind { return true }
            return false
        }
        guard !conflicts.isEmpty else { return plan }

        let complaints = conflicts.map { issue -> String in
            guard case .slowerItemGoesInSecond(let appliance) = issue.kind else { return "" }
            return "- Step \"\(issue.earlierStepID)\" and step \"\(issue.laterStepID)\" both use the "
                + "\(appliance.spokenName), and \"\(issue.laterStepID)\" needs longer but is told to "
                + "start second. Put the longer one in first and have the other join it later so "
                + "they finish together."
        }.joined(separator: "\n")

        PollyDebugLog.shared.log("plan: \(conflicts.count) scheduling conflict(s) — repairing")

        let repairPrompt = userPrompt(recipe: recipe, scale: scale) + """


        A first attempt at this plan had these scheduling mistakes:
        \(complaints)

        Produce the plan again, correctly scheduled. Change only the ordering and the timings
        needed to fix the above. Keep every other step, its wording and its ids as they were.
        """

        var repaired = try await llm(systemPrompt, repairPrompt)
        repaired.isFallback = false
        repaired = repaired.ensuringLeadingPrep(ingredients: recipe.ingredients, scale: scale)

        // Keep the repair only if it actually helped. A second pass that trades
        // one conflict for two, or drops half the steps to make the detector
        // happy, is worse than the plan we already had.
        let before = conflicts.count
        let after = repaired.schedulingIssues.filter {
            if case .slowerItemGoesInSecond = $0.kind { return true }
            return false
        }.count
        // Proportional, not a flat tolerance. A fixed "one step" allowance let a
        // rewrite that collapsed a two-step plan into one pass, and losing half
        // the recipe is the worst possible way to score well on the detector.
        // Merging the two appliance steps into one staggered instruction is
        // legitimate, so a small loss on a long plan is allowed.
        let floor = Int((Double(plan.steps.count) * 0.75).rounded(.up))
        let lostSteps = repaired.steps.count < floor
        guard after < before, !lostSteps else {
            PollyDebugLog.shared.log(
                "plan: repair rejected (conflicts \(before) → \(after), steps "
                    + "\(plan.steps.count) → \(repaired.steps.count))")
            return plan
        }
        PollyDebugLog.shared.log("plan: repaired (conflicts \(before) → \(after))")
        return repaired
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
    "measure 1 tsp cumin" in mise. Spices are measured in the cook step when added. \
    Every "prep" MUST say what the food ends up looking like: "dice", "cut into 1-inch \
    cubes", "slice thinly", "cut into florets", "mince". NEVER write a vague prep — no \
    "cut to size", "cut", "prepare", "as needed", "chop as needed". If the recipe does not \
    specify, choose the cut this dish actually wants and say it; a stir fry wants thin \
    slices, a stew wants chunks, a salsa wants fine dice. Deciding is your job. If you \
    genuinely cannot tell, leave the ingredient out of mise entirely rather than guessing \
    in words that mean nothing.
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
    - Preserve the recipe's intent; split run-on instructions into single actions; do NOT \
    invent ingredients or steps that aren't implied by the source.

    Scheduling — this is the difference between a recipe and a plan:
    - You are writing the order the cook should ACTUALLY work in, not the order the source \
    happened to list. Written recipes describe one dish at a time; a cook has one oven, one \
    hob and two hands.
    - SHARED APPLIANCE: when two things go in the same oven, air fryer, grill or slow cooker, \
    the one that needs LONGEST goes in FIRST, and the shorter one joins it later so they \
    finish together. Chicken 20 min and potatoes 30 min is: potatoes in, then chicken in after \
    10 minutes, both out together. Never tell the cook to start the slower item second: \
    followed literally that is 50 minutes and the first thing out is cold.
    - Say the staggering out loud in the instruction ("potatoes in now, they need 30; the \
    chicken joins them in 10"), and set timerSeconds to the wait until the NEXT action, not \
    the total cook time.
    - If two things genuinely cannot share (different temperatures, no room), say which one \
    goes first and that the other waits. Do not silently interleave them.
    - DEAD TIME: hands-on work that does not depend on a wait finishing belongs INSIDE that \
    wait, not queued after it. If something bakes 30 minutes, the sauce, the salad and the \
    washing up happen during it. Order those steps between the start of the wait and its \
    timer, and use dependsOn to say what truly must wait.
    - Only overlap where a real cook would. Do not send them away from a pan that needs \
    stirring, or split a step that needs their full attention.
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
