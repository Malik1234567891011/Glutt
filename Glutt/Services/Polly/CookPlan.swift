import Foundation

/// Compiled execution graph for one cook session. Produced by CookPlanCompiler
/// (one-shot LLM call, cached) or by the deterministic `linear(from:scale:)`
/// fallback when AI is unavailable — the session runs either way.
struct CookPlan: Codable, Equatable {
    enum StepKind: String, Codable {
        case prep, active, passive, checkpoint
    }

    struct MiseItem: Codable, Equatable {
        let name: String
        let prep: String
        /// How much, already formatted ("20", "2 tbsp"). Optional because the
        /// LLM does not produce it and older cached plans predate it.
        let amount: String?

        init(name: String, prep: String, amount: String? = nil) {
            self.name = name
            self.prep = prep
            self.amount = amount
        }

        enum CodingKeys: String, CodingKey { case name, prep, amount }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            prep = try c.decodeIfPresent(String.self, forKey: .prep) ?? ""
            amount = try c.decodeIfPresent(String.self, forKey: .amount)
        }
    }

    struct PlanStep: Codable, Equatable, Identifiable {
        let id: String
        let index: Int
        let title: String
        let instruction: String
        let kind: StepKind
        let estimatedSeconds: Int?
        let timerSeconds: Int?
        let dependsOn: [String]
        let visualCheck: String?
        let recovery: String?
        let ingredientNames: [String]
        /// The clip this step must play, when we already know the answer.
        ///
        /// Clip assignment is otherwise keyword-scored against the segment's
        /// `step_keywords`, which is the only option for a plan written by the
        /// model, but it is guesswork and it drifts: rewording a step or a
        /// keyword re-scores every pairing. For a bundled dish being cooked in
        /// front of an audience, guessing is the wrong tool. Naming the segment
        /// makes the pairing a fact, and a step with no name here plays nothing
        /// rather than borrowing someone else's clip.
        let clipSegmentID: String?

        init(
            id: String,
            index: Int,
            title: String,
            instruction: String,
            kind: StepKind,
            estimatedSeconds: Int? = nil,
            timerSeconds: Int? = nil,
            dependsOn: [String] = [],
            visualCheck: String? = nil,
            recovery: String? = nil,
            ingredientNames: [String] = [],
            clipSegmentID: String? = nil
        ) {
            self.id = id
            self.index = index
            self.title = title
            self.instruction = instruction
            self.kind = kind
            self.estimatedSeconds = estimatedSeconds
            self.timerSeconds = timerSeconds
            self.dependsOn = dependsOn
            self.visualCheck = visualCheck
            self.recovery = recovery
            self.ingredientNames = ingredientNames
            self.clipSegmentID = clipSegmentID
        }

        // Optional-tolerant decoding (PlateCard pattern): the LLM may omit any
        // non-essential field. Arrays default to empty, scalars to nil, and an
        // unknown kind string degrades to .active instead of failing the plan.
        enum CodingKeys: String, CodingKey {
            case id, index, title, instruction, kind, estimatedSeconds
            case timerSeconds, dependsOn, visualCheck, recovery, ingredientNames
            case clipSegmentID
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            instruction = try c.decodeIfPresent(String.self, forKey: .instruction) ?? ""
            let kindRaw = try c.decodeIfPresent(String.self, forKey: .kind)
            kind = kindRaw.flatMap(StepKind.init(rawValue:)) ?? .active
            estimatedSeconds = try c.decodeIfPresent(Int.self, forKey: .estimatedSeconds)
            timerSeconds = try c.decodeIfPresent(Int.self, forKey: .timerSeconds)
            dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
            visualCheck = try c.decodeIfPresent(String.self, forKey: .visualCheck)
            recovery = try c.decodeIfPresent(String.self, forKey: .recovery)
            ingredientNames = try c.decodeIfPresent([String].self, forKey: .ingredientNames) ?? []
            clipSegmentID = try c.decodeIfPresent(String.self, forKey: .clipSegmentID)
        }
    }

    let title: String
    let servings: Int
    let mise: [MiseItem]
    let equipment: [String]
    let steps: [PlanStep]
    /// True when this plan was built by `linear(from:scale:)` rather than the compiler.
    var isFallback: Bool

    init(
        title: String,
        servings: Int,
        mise: [MiseItem] = [],
        equipment: [String] = [],
        steps: [PlanStep] = [],
        isFallback: Bool = false
    ) {
        self.title = title
        self.servings = servings
        self.mise = mise
        self.equipment = equipment
        self.steps = steps
        self.isFallback = isFallback
    }

    enum CodingKeys: String, CodingKey {
        case title, servings, mise, equipment, steps, isFallback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        servings = try c.decodeIfPresent(Int.self, forKey: .servings) ?? 0
        mise = try c.decodeIfPresent([MiseItem].self, forKey: .mise) ?? []
        equipment = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        steps = try c.decodeIfPresent([PlanStep].self, forKey: .steps) ?? []
        isFallback = try c.decodeIfPresent(Bool.self, forKey: .isFallback) ?? false
    }

    /// Stable id for the leading tools-staging step (before Prep).
    static let toolsStepID = "tools"
    /// Stable id for the mandatory leading mise-en-place / board-work step.
    static let prepStepID = "prep"

    /// Deterministic no-AI fallback: one plan step per recipe step, in order,
    /// each depending on the previous. Steps with a detected timer become
    /// passive (Polly starts the timer); everything else is active.
    /// Always prepends Tools + Prep when there is gear / board work.
    static func linear(from recipe: Recipe, scale: Double) -> CookPlan {
        let mise = synthesizeMise(from: recipe.ingredients, scale: scale)
        let steps = recipe.sortedSteps.enumerated().map { offset, step in
            PlanStep(
                id: "s\(offset + 1)",
                index: offset,
                title: shortTitle(for: step.text),
                instruction: step.text,
                kind: step.durationSeconds != nil ? .passive : .active,
                estimatedSeconds: step.durationSeconds,
                timerSeconds: step.durationSeconds,
                dependsOn: offset == 0 ? [] : ["s\(offset)"],
                ingredientNames: step.ingredientsUsed(from: recipe.ingredients).map(\.name)
            )
        }
        let plan = CookPlan(
            title: recipe.title,
            servings: max(1, Int((Double(recipe.servings) * scale).rounded())),
            mise: mise,
            steps: steps,
            isFallback: true
        )
        return plan.ensuringLeadingPrep(ingredients: recipe.ingredients, scale: scale)
    }

    /// Guarantees short leading setup steps before any heat:
    /// 1) Tools (stage gear) when `equipment` is non-empty
    /// 2) Prep (knife/board only) when `mise` has real board work
    /// Spices/oils/measuring never land in Prep — those happen at cook time.
    func ensuringLeadingPrep(
        ingredients: [RecipeIngredient] = [], scale: Double = 1
    ) -> CookPlan {
        let cleanedMise = Self.withAmounts(
            Self.boardWorkOnly(mise), from: ingredients, scale: scale)
        let gear = equipment
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Drop only the dedicated Tools/Prep rows — we rebuild those cleanly.
        // Do NOT drop every `kind == .prep` step: the compiler tags cold technique
        // work (scrape vanilla, whisk yolks, strain custard) as prep, and wiping
        // those removed the steps clips are keyed to — Crème Brûlée cooked with
        // a static poster and no video.
        let cookSteps = steps.filter { step in
            step.id != Self.toolsStepID && step.id != Self.prepStepID
        }

        guard !cleanedMise.isEmpty || !gear.isEmpty else {
            let remapped = cookSteps.enumerated().map { i, s in
                promoteColdPrep(
                    rewrittenStep(s, newIndex: i, ensureDependsOn: nil)
                )
            }
            if cleanedMise == mise, remapped == steps { return self }
            return CookPlan(
                title: title,
                servings: servings,
                mise: cleanedMise,
                equipment: gear,
                steps: remapped,
                isFallback: isFallback
            )
        }

        var leading: [PlanStep] = []
        if !gear.isEmpty {
            leading.append(PlanStep(
                id: Self.toolsStepID,
                index: 0,
                title: "Tools",
                instruction: Self.toolsInstruction(gear),
                kind: .prep,
                estimatedSeconds: max(30, gear.count * 12),
                dependsOn: [],
                ingredientNames: []
            ))
        }
        if !cleanedMise.isEmpty {
            let depends = leading.isEmpty ? [] : [Self.toolsStepID]
            leading.append(PlanStep(
                id: Self.prepStepID,
                index: leading.count,
                title: "Prep",
                instruction: Self.prepInstruction(mise: cleanedMise, equipment: []),
                kind: .prep,
                estimatedSeconds: max(60, cleanedMise.count * 40),
                dependsOn: depends,
                ingredientNames: cleanedMise.map(\.name)
            ))
        }

        let lastSetupID = leading.last?.id
        let rest = cookSteps.enumerated().map { offset, step in
            promoteColdPrep(
                rewrittenStep(
                    step,
                    newIndex: leading.count + offset,
                    ensureDependsOn: offset == 0 ? lastSetupID : nil
                )
            )
        }
        return CookPlan(
            title: title,
            servings: servings,
            mise: cleanedMise,
            equipment: gear,
            steps: leading + rest,
            isFallback: isFallback
        )
    }

    /// True when a Prep (board) step exists in the leading setup.
    var hasLeadingPrep: Bool {
        steps.contains { $0.id == Self.prepStepID && $0.kind == .prep }
    }

    /// How many leading Tools/Prep setup steps sit before cook Step 1.
    var leadingSetupCount: Int {
        var n = 0
        for step in steps {
            if step.id == Self.toolsStepID || step.id == Self.prepStepID {
                n += 1
            } else {
                break
            }
        }
        return n
    }

    /// The rebuilt Tools / Prep rows only — not every step the LLM tagged `prep`.
    /// Cold technique steps keep `kind: prep` in the compiler JSON but they are
    /// still real cook steps and must receive clips / numbering.
    static func isSetupStep(_ step: PlanStep) -> Bool {
        step.id == toolsStepID || step.id == prepStepID
    }

    // MARK: - Prep helpers

    /// Cold technique steps arrive from the compiler as `kind: prep`. Promote
    /// them to `.active` so they stay numbered cook steps with clips. The
    /// dedicated Tools/Prep rows keep `.prep` and are identified by id.
    private func promoteColdPrep(_ step: PlanStep) -> PlanStep {
        guard step.kind == .prep,
              step.id != Self.toolsStepID,
              step.id != Self.prepStepID else { return step }
        return PlanStep(
            id: step.id,
            index: step.index,
            title: step.title,
            instruction: step.instruction,
            kind: .active,
            estimatedSeconds: step.estimatedSeconds,
            timerSeconds: step.timerSeconds,
            dependsOn: step.dependsOn,
            visualCheck: step.visualCheck,
            recovery: step.recovery,
            ingredientNames: step.ingredientNames,
            clipSegmentID: step.clipSegmentID
        )
    }

    private func rewrittenStep(
        _ step: PlanStep,
        newIndex: Int,
        ensureDependsOn: String?
    ) -> PlanStep {
        var depends = step.dependsOn.filter {
            $0 != Self.prepStepID && $0 != Self.toolsStepID && $0 != step.id
        }
        if let ensureDependsOn, !depends.contains(ensureDependsOn) {
            depends.insert(ensureDependsOn, at: 0)
        }
        let safeID: String = {
            if step.id == Self.prepStepID || step.id == Self.toolsStepID {
                return "s\(newIndex)"
            }
            return step.id
        }()
        return PlanStep(
            id: safeID,
            index: newIndex,
            title: step.title,
            instruction: step.instruction,
            kind: step.kind,
            estimatedSeconds: step.estimatedSeconds,
            timerSeconds: step.timerSeconds,
            dependsOn: depends,
            visualCheck: step.visualCheck,
            recovery: step.recovery,
            ingredientNames: step.ingredientNames,
            clipSegmentID: step.clipSegmentID
        )
    }

    /// Coarse mise for the no-AI path: knife/board work for produce & proteins only.
    /// Spices, oils, and "measure X" never belong here — measure when you cook.
    static func synthesizeMise(from ingredients: [RecipeIngredient], scale: Double = 1) -> [MiseItem] {
        ingredients
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { ingredient -> MiseItem? in
                let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                guard let action = prepAction(for: name) else { return nil }
                return MiseItem(
                    name: name,
                    prep: action,
                    amount: UnitConverter.display(
                        quantity: ingredient.quantity, unit: ingredient.unit, scale: scale))
            }
    }

    /// Fill in how much, from the recipe's own ingredient list.
    ///
    /// The compiler's mise schema has no quantity field and the LLM was never
    /// asked for one, so every prep row read "pick the fresh sage leaves" and
    /// left the cook to go and look it up. The number is already sitting in the
    /// recipe, so take it from there rather than teaching the model a new field
    /// it would get wrong on cached plans anyway.
    ///
    /// An amount already on the item wins, so a hand-written bundled plan can
    /// still say something the ingredient line cannot ("a handful").
    static func withAmounts(
        _ mise: [MiseItem], from ingredients: [RecipeIngredient], scale: Double = 1
    ) -> [MiseItem] {
        guard !ingredients.isEmpty else { return mise }
        return mise.map { item in
            guard (item.amount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
            else { return item }
            let name = item.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return item }
            let canonical = IngredientCanonicalizer.canonicalize(name)
            let match = ingredients.first { $0.name.lowercased() == name }
                ?? ingredients.first { $0.canonicalName.lowercased() == canonical.lowercased() }
                ?? ingredients.first { $0.name.lowercased().contains(name) || name.contains($0.name.lowercased()) }
            guard let match,
                  let amount = UnitConverter.display(
                    quantity: match.quantity, unit: match.unit, scale: scale)
            else { return item }
            return MiseItem(name: item.name, prep: item.prep, amount: amount)
        }
    }

    /// Drop measure-only / seasoning rows from LLM or stale cache plans.
    /// Prep text that tells the cook nothing.
    ///
    /// "Cut to size the onions" is the real example. It reads like an
    /// instruction and contains no instruction: there is no size, no shape, and
    /// no way to know what the dish wants. The compiler produces these when the
    /// source recipe was vague and it declined to commit, which is exactly the
    /// moment the app should be deciding for the cook instead of passing the
    /// shrug along.
    ///
    /// A prep is vague when it hedges ("as needed") or names an action with no
    /// shape or size attached ("cut", "prepare"). Anything that says what the
    /// food should end up looking like — "dice", "cut into 1-inch cubes", "slice
    /// thinly", "cut into florets" — is specific and left alone.
    static func isVaguePrep(_ prep: String) -> Bool {
        let text = prep.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        let hedges = ["to size", "as needed", "as desired", "as required",
                      "accordingly", "appropriately", "if needed", "to taste"]
        if hedges.contains(where: text.contains) { return true }
        // Bare verbs. "cut" alone is vague; "cut into florets" is not.
        let bareVerbs: Set<String> = ["cut", "cut up", "prepare", "prep", "prepped",
                                      "ready", "clean", "process", "handle", "sort out"]
        return bareVerbs.contains(text)
    }

    static func boardWorkOnly(_ mise: [MiseItem]) -> [MiseItem] {
        mise.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let prep = item.prep.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            if isSeasoningOrPourable(name) { return nil }
            let prepLower = prep.lowercased()
            if prepLower.isEmpty {
                // Bare name with no knife action — keep only if it looks like produce/protein.
                return prepAction(for: name).map { MiseItem(name: name, prep: $0, amount: item.amount) }
            }
            if prepLower.contains("measure")
                || prepLower.contains("portion")
                || prepLower.contains("tsp")
                || prepLower.contains("tbsp")
                || prepLower.contains("teaspoon")
                || prepLower.contains("tablespoon") {
                return nil
            }
            // A vague verb is worse than nothing: it occupies a line on the
            // Prep step and leaves the cook with a whole onion and no decision.
            // Substitute what we know that ingredient wants, and if we do not
            // know, drop it rather than say "cut to size".
            if isVaguePrep(prep) {
                return prepAction(for: name).map { MiseItem(name: name, prep: $0, amount: item.amount) }
            }
            return MiseItem(name: name, prep: prep, amount: item.amount)
        }
    }

    private static func isSeasoningOrPourable(_ rawName: String) -> Bool {
        let name = rawName.lowercased()
        if name.contains("oil") || name.contains("vinegar") { return true }
        if name.contains("stock") || name.contains("broth") { return true }
        // Bottled sauces — not board work. (Keep "apple" etc. out via " sauce" suffix.)
        if name.hasSuffix(" sauce") || name.contains(" sauce ") { return true }
        let exact = [
            "water", "salt", "kosher salt", "sea salt", "butter", "sugar",
            "flour", "baking soda", "baking powder", "soy sauce",
            "black pepper", "white pepper", "pepper", "ground pepper",
        ]
        if exact.contains(name) { return true }
        // Dried spices / powders — measure when the cook step uses them.
        // Fresh herbs are NOT seasonings here (handled as chop work).
        if name.contains("fresh ") { return false }
        let spiceBits = [
            "cumin", "paprika", "chili powder", "chilli powder", "cayenne",
            "turmeric", "coriander powder", "cinnamon", "nutmeg", "clove",
            "cardamom", "garam masala", "curry powder", "italian seasoning",
            "seasoning", "spice blend", "garlic powder", "onion powder",
            "red pepper flake", "pepper flake", "za'atar", "zaatar", "sumac",
            "allspice", "bay leaf", "bay leaves", "dried oregano", "dried thyme",
            "dried rosemary", "dried basil",
        ]
        if spiceBits.contains(where: { name == $0 || name.contains($0) }) { return true }
        // Bare dried herb names (recipe usually means the jar, not a bunch).
        let driedHerbs = ["oregano", "thyme", "rosemary", "basil", "dill", "sage"]
        if driedHerbs.contains(where: { name == $0 || name.hasPrefix("\($0) ") }) {
            return true
        }
        return false
    }

    private static func prepAction(for rawName: String) -> String? {
        let name = rawName.lowercased()
        if isSeasoningOrPourable(name) { return nil }

        let dice = ["onion", "shallot", "scallion", "green onion", "leek",
                    "carrot", "celery", "bell pepper", "chili pepper", "chilli pepper",
                    "jalapeno", "jalapeño", "zucchini", "courgette", "tomato",
                    "potato", "cucumber", "pepper"]
        // Prefer specific peppers; bare "pepper" alone is seasoning (handled above).
        if dice.contains(where: {
            $0 == "pepper"
                ? (name.contains("bell pepper") || name.contains("chili") || name.contains("chilli")
                    || name.contains("jalap"))
                : name.contains($0)
        }) { return "dice" }

        let mince = ["garlic", "ginger"]
        if mince.contains(where: { name.contains($0) }) { return "mince" }

        let florets = ["broccoli", "cauliflower", "romanesco"]
        if florets.contains(where: { name.contains($0) }) { return "cut into florets" }

        let slice = ["mushroom", "aubergine", "eggplant", "fennel", "radish"]
        if slice.contains(where: { name.contains($0) }) { return "slice" }

        let trim = ["green bean", "asparagus", "spring onion", "sugar snap", "mangetout"]
        if trim.contains(where: { name.contains($0) }) { return "trim" }

        let chop = ["parsley", "cilantro", "fresh coriander", "basil", "mint",
                    "fresh thyme", "fresh rosemary", "lettuce", "cabbage", "kale", "spinach"]
        if chop.contains(where: { name.contains($0) }) { return "chop" }

        let patDry = ["chicken", "beef", "pork", "lamb", "turkey", "fish",
                      "salmon", "shrimp", "prawn", "tofu", "steak", "thigh", "breast"]
        if patDry.contains(where: { name.contains($0) }) { return "pat dry" }

        // Unknown dry goods / cans / pasta: nothing for the board.
        return nil
    }

    static func toolsInstruction(_ equipment: [String]) -> String {
        let gear = equipment
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !gear.isEmpty else {
            return "Pull your tools within reach, then we'll do the board work."
        }
        let shown = gear.prefix(5).joined(separator: ", ")
        let extra = gear.count > 5 ? ", and the rest" : ""
        return "Pull out your \(shown)\(extra). Tell me when they're on the counter."
    }

    /// One board instruction, in English a person would say.
    ///
    /// Naive `"\(prep) the \(name)"` was fine while every prep was a single word
    /// ("dice the onion"), and started producing "cut into florets the broccoli"
    /// as soon as real cuts arrived. Splitting the verb off the rest and putting
    /// the ingredient between them handles both, and "pat the chicken dry" reads
    /// better than "pat dry the chicken" too.
    static func phrase(for item: MiseItem) -> String {
        let prep = item.prep.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = midSentence(item.name)
        let trimmedAmount = item.amount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let amount: String? = trimmedAmount.isEmpty ? nil : trimmedAmount
        guard !prep.isEmpty else { return amount.map { "\($0) \(name)" } ?? name }
        var words = prep.split(separator: " ").map(String.init)
        let verb = words.removeFirst()
        // Only rearrange around a verb we recognise. Anything else keeps the
        // old shape rather than risking "at the chicken room temperature".
        guard boardVerbs.contains(verb.lowercased()) else {
            return amount.map { "\(prep) \($0) \(name)" } ?? "\(prep) the \(name)"
        }
        let tail = words.joined(separator: " ")
        // "pick 20 fresh sage leaves", not "pick the fresh sage leaves". Without
        // the number the cook has to stop and ask the one question the app can
        // already answer, which is the opposite of a prep list.
        let object = amount.map { "\($0) \(name)" } ?? "the \(name)"
        return tail.isEmpty
            ? "\(verb) \(object)"
            : "\(verb) \(object) \(tail)"
    }

    /// Ingredient names are stored title-cased for the list UI, which reads as a
    /// typo inside a sentence: "dice the Chicken breast". Only the first letter
    /// is touched, so "Parmesan" mid-name and anything all-caps survive.
    private static func midSentence(_ name: String) -> String {
        guard let first = name.first, first.isUppercase else { return name }
        // An acronym is deliberate, not title case. Tested on the FIRST WORD:
        // checking the rest of the whole string saw the "sauce" in "BBQ sauce"
        // and produced "bBQ sauce".
        let firstWord = name.prefix { !$0.isWhitespace }
        if firstWord.count > 1, !firstWord.contains(where: \.isLowercase) { return name }
        return first.lowercased() + name.dropFirst()
    }

    private static let boardVerbs: Set<String> = [
        "cut", "dice", "slice", "chop", "mince", "mash", "grate", "peel", "trim",
        "halve", "quarter", "julienne", "shred", "crush", "pat", "tear", "segment",
        "zest", "devein", "debone", "butterfly", "crumble", "wash", "rinse", "drain",
        "pick", "stem", "separate",
    ]

    static func prepInstruction(mise: [MiseItem], equipment: [String] = []) -> String {
        var parts: [String] = []
        if !mise.isEmpty {
            let list = mise.map { phrase(for: $0) }
            if list.count == 1 {
                parts.append("Before any heat: \(list[0]).")
            } else if list.count == 2 {
                parts.append("Before any heat: \(list[0]), and \(list[1]).")
            } else {
                let head = list.dropLast().joined(separator: "; ")
                parts.append("Before any heat: \(head); and \(list.last!).")
            }
        }
        let gear = equipment
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !gear.isEmpty {
            let shown = gear.prefix(4).joined(separator: ", ")
            parts.append("Stage your \(shown)\(gear.count > 4 ? ", …" : "").")
        }
        if parts.isEmpty {
            return "Get your board work done before any heat."
        }
        parts.append("Tell me when the board is ready.")
        return parts.joined(separator: " ")
    }

    /// First six words of the step text, with an ellipsis when truncated.
    private static func shortTitle(for text: String) -> String {
        let words = text.split(separator: " ")
        guard words.count > 6 else { return text }
        return words.prefix(6).joined(separator: " ") + "…"
    }
}

// MARK: - Scheduling

/// Whether the plan actually cooks, or merely transcribes.
///
/// A cook reads a recipe as a schedule; most written recipes are not one. The
/// case that prompted this: "chicken in the oven, 20 minutes", then "potatoes in
/// the oven, 30 minutes". Followed literally that is fifty minutes of oven time
/// and cold chicken, when the honest answer is potatoes first and the chicken
/// joining them ten minutes later so both come out together.
///
/// This is deliberately a **detector, not a fixer**. Reordering steps
/// automatically means deciding that two things really can share an oven at one
/// temperature, which is a judgement about the food, and getting it wrong ruins
/// dinner rather than merely reading badly. So the compiler is taught to
/// schedule (see `CookPlanCompiler`) and this exists to prove whether it did.
extension CookPlan {

    /// A thing only one dish can occupy at a time.
    ///
    /// Keyword matching rather than anything the model declares, because it has
    /// to work on the `linear` fallback and on plans cached before any of this
    /// existed. Deliberately narrow: a false "these share an oven" is worse than
    /// a miss, since it would flag correct plans as broken.
    enum Appliance: String, CaseIterable, Sendable {
        case oven, stovetop, grill, airFryer, microwave, slowCooker

        var spokenName: String {
            switch self {
            case .oven: "oven"
            case .stovetop: "hob"
            case .grill: "grill"
            case .airFryer: "air fryer"
            case .microwave: "microwave"
            case .slowCooker: "slow cooker"
            }
        }

        fileprivate var keywords: [String] {
            switch self {
            case .oven: ["oven", "bake", "baking", "roast", "roasting", "sheet pan", "tray bake"]
            case .stovetop: ["hob", "stovetop", "stove top", "burner", "saucepan", "skillet", "frying pan"]
            case .grill: ["grill", "griddle", "broil", "broiler", "barbecue", "bbq"]
            case .airFryer: ["air fryer", "air-fry", "airfry"]
            case .microwave: ["microwave"]
            case .slowCooker: ["slow cooker", "crock pot", "crockpot"]
            }
        }
    }

    /// Something a good chef would have said and this plan does not.
    struct SchedulingIssue: Equatable {
        enum Kind: Equatable {
            /// Two things go into one appliance one after the other, and the one
            /// told to go in second needs longer. The cook ends up waiting out
            /// both in series, and whatever went in first is cold or overdone.
            case slowerItemGoesInSecond(Appliance)
            /// Hands-on work queued after a long unattended wait it could have
            /// happened during. Not wrong, just slow, so it is a weaker signal
            /// than the one above.
            case handsFreeTimeWasted(seconds: Int)
        }

        let kind: Kind
        let earlierStepID: String
        let laterStepID: String
    }

    /// How long a step ties up an appliance. `timerSeconds` is the unattended
    /// wait and is what matters here; `estimatedSeconds` is hands-on time.
    private static func occupancySeconds(_ step: PlanStep) -> Int? {
        step.timerSeconds ?? (step.kind == .passive ? step.estimatedSeconds : nil)
    }

    static func appliance(for step: PlanStep) -> Appliance? {
        let haystack = (step.title + " " + step.instruction).lowercased()
        // Longest keyword first so "air fryer" is not read as a stovetop "fryer"
        // and "slow cooker" is not lost to a bare "cooker".
        let matches = Appliance.allCases
            .flatMap { appliance in appliance.keywords.map { (appliance, $0) } }
            .filter { haystack.contains($0.1) }
            .sorted { $0.1.count > $1.1.count }
        return matches.first?.0
    }

    /// Everything questionable about this plan's timing, in step order.
    var schedulingIssues: [SchedulingIssue] {
        var issues: [SchedulingIssue] = []
        let cookSteps = steps.filter { !Self.isSetupStep($0) }

        // Same appliance, later step waits longer. Compared pairwise across the
        // whole plan rather than only adjacent steps, because a stir or a
        // seasoning step routinely sits between the two oven instructions.
        for (offset, earlier) in cookSteps.enumerated() {
            guard let appliance = Self.appliance(for: earlier),
                  let earlierWait = Self.occupancySeconds(earlier), earlierWait > 0
            else { continue }
            for later in cookSteps.dropFirst(offset + 1) {
                guard Self.appliance(for: later) == appliance,
                      let laterWait = Self.occupancySeconds(later), laterWait > 0
                else { continue }
                if laterWait > earlierWait {
                    issues.append(SchedulingIssue(
                        kind: .slowerItemGoesInSecond(appliance),
                        earlierStepID: earlier.id,
                        laterStepID: later.id))
                }
                // One pairing per earlier step. Chaining every later step onto
                // it turns one mistake into a pile of duplicates.
                break
            }
        }

        // Hands-on work stuck behind a long wait.
        for (offset, wait) in cookSteps.enumerated() {
            guard wait.kind == .passive,
                  let seconds = Self.occupancySeconds(wait),
                  seconds >= Self.wastedTimeThresholdSeconds,
                  let next = cookSteps.dropFirst(offset + 1).first,
                  next.kind == .active,
                  // Only when it genuinely could run in parallel: a step that
                  // depends on the wait finishing obviously cannot.
                  !next.dependsOn.contains(wait.id)
            else { continue }
            issues.append(SchedulingIssue(
                kind: .handsFreeTimeWasted(seconds: seconds),
                earlierStepID: wait.id,
                laterStepID: next.id))
        }

        return issues
    }

    /// Below this a wait is not worth interrupting to do something else.
    static let wastedTimeThresholdSeconds = 8 * 60
}
