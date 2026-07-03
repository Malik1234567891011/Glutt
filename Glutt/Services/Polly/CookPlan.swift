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

    /// Deterministic no-AI fallback: one plan step per recipe step, in order,
    /// each depending on the previous. Steps with a detected timer become
    /// passive (Polly starts the timer); everything else is active.
    static func linear(from recipe: Recipe, scale: Double) -> CookPlan {
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
        return CookPlan(
            title: recipe.title,
            servings: max(1, Int((Double(recipe.servings) * scale).rounded())),
            steps: steps,
            isFallback: true
        )
    }

    /// First six words of the step text, with an ellipsis when truncated.
    private static func shortTitle(for text: String) -> String {
        let words = text.split(separator: " ")
        guard words.count > 6 else { return text }
        return words.prefix(6).joined(separator: " ") + "…"
    }
}
