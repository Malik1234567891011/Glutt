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
            ingredientNames: [String] = []
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
        }

        // Optional-tolerant decoding (PlateCard pattern): the LLM may omit any
        // non-essential field. Arrays default to empty, scalars to nil, and an
        // unknown kind string degrades to .active instead of failing the plan.
        enum CodingKeys: String, CodingKey {
            case id, index, title, instruction, kind, estimatedSeconds
            case timerSeconds, dependsOn, visualCheck, recovery, ingredientNames
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
        let mise = synthesizeMise(from: recipe.ingredients)
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
        return plan.ensuringLeadingPrep()
    }

    /// Guarantees short leading setup steps before any heat:
    /// 1) Tools (stage gear) when `equipment` is non-empty
    /// 2) Prep (knife/board only) when `mise` has real board work
    /// Spices/oils/measuring never land in Prep — those happen at cook time.
    func ensuringLeadingPrep() -> CookPlan {
        let cleanedMise = Self.boardWorkOnly(mise)
        let gear = equipment
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Drop any existing leading setup steps — we rebuild them cleanly.
        let cookSteps = steps.filter { step in
            step.id != Self.toolsStepID
                && step.id != Self.prepStepID
                && step.kind != .prep
        }

        guard !cleanedMise.isEmpty || !gear.isEmpty else {
            if cleanedMise == mise, cookSteps.count == steps.count { return self }
            return CookPlan(
                title: title,
                servings: servings,
                mise: cleanedMise,
                equipment: gear,
                steps: cookSteps.enumerated().map { i, s in
                    rewrittenStep(s, newIndex: i, ensureDependsOn: nil)
                },
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
            rewrittenStep(
                step,
                newIndex: leading.count + offset,
                ensureDependsOn: offset == 0 ? lastSetupID : nil
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
            if step.kind == .prep
                || step.id == Self.toolsStepID
                || step.id == Self.prepStepID {
                n += 1
            } else {
                break
            }
        }
        return n
    }

    /// Tools or Prep — not numbered cook steps.
    static func isSetupStep(_ step: PlanStep) -> Bool {
        step.kind == .prep
            || step.id == toolsStepID
            || step.id == prepStepID
    }

    // MARK: - Prep helpers

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
            ingredientNames: step.ingredientNames
        )
    }

    /// Coarse mise for the no-AI path: knife/board work for produce & proteins only.
    /// Spices, oils, and "measure X" never belong here — measure when you cook.
    static func synthesizeMise(from ingredients: [RecipeIngredient]) -> [MiseItem] {
        ingredients
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { ingredient -> MiseItem? in
                let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                guard let action = prepAction(for: name) else { return nil }
                return MiseItem(name: name, prep: action)
            }
    }

    /// Drop measure-only / seasoning rows from LLM or stale cache plans.
    static func boardWorkOnly(_ mise: [MiseItem]) -> [MiseItem] {
        mise.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let prep = item.prep.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            if isSeasoningOrPourable(name) { return nil }
            let prepLower = prep.lowercased()
            if prepLower.isEmpty {
                // Bare name with no knife action — keep only if it looks like produce/protein.
                return prepAction(for: name).map { MiseItem(name: name, prep: $0) }
            }
            if prepLower.contains("measure")
                || prepLower.contains("portion")
                || prepLower.contains("tsp")
                || prepLower.contains("tbsp")
                || prepLower.contains("teaspoon")
                || prepLower.contains("tablespoon") {
                return nil
            }
            return MiseItem(name: name, prep: prep)
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

    static func prepInstruction(mise: [MiseItem], equipment: [String] = []) -> String {
        var parts: [String] = []
        if !mise.isEmpty {
            let list = mise.map { item in
                let prep = item.prep.trimmingCharacters(in: .whitespacesAndNewlines)
                if prep.isEmpty { return item.name }
                return "\(prep) the \(item.name)"
            }
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
