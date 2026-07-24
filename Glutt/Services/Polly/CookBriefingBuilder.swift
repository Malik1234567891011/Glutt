import Foundation

/// Builds a shallow cook-trailer briefing from a `CookPlan` + recipe metadata.
/// Deterministic and offline — no LLM required — so the rundown appears instantly.
enum CookBriefingBuilder {

    /// Caps how many storyboard beats we show/speak. Enough to get the gist;
    /// not a full step read-through.
    static let maxBeats = 4

    static func build(recipe: Recipe, plan: CookPlan) -> CookBriefing {
        let beats = makeBeats(from: plan)
        let time = recipe.timeLabel == "—"
            ? estimateTimeLabel(plan: plan, recipe: recipe)
            : recipe.timeLabel

        let intro: String
        if recipe.isCookingBasic {
            intro = "Quick look — you're learning \(plan.title)."
        } else {
            intro = "Quick look — you're making \(plan.title)."
        }

        let outro: String
        if beats.isEmpty {
            outro = "About \(time). Say let's cook when you're ready."
        } else {
            outro = "About \(time) total. Say let's cook when you're ready."
        }

        return CookBriefing(
            dishTitle: plan.title,
            timeLabel: time,
            servings: plan.servings,
            beats: beats,
            miseLine: miseLine(plan.mise),
            gearLine: gearLine(plan.equipment),
            introLine: intro,
            outroLine: outro
        )
    }

    // MARK: - Beats

    /// Pick a sparse storyboard from the plan: first / mid / late moments so
    /// the cook sees the arc without hearing every step.
    static func makeBeats(from plan: CookPlan) -> [CookBriefing.Beat] {
        let steps = plan.steps.sorted { $0.index < $1.index }
        guard !steps.isEmpty else { return [] }

        let picked = pickSteps(steps)
        return picked.enumerated().map { offset, step in
            let title = cleanTitle(step.title, fallbackIndex: step.index)
            let detail = cleanDetail(step.instruction)
            return CookBriefing.Beat(
                id: step.id.isEmpty ? "beat-\(offset)" : step.id,
                title: title,
                detail: detail,
                kind: step.kind,
                spokenLine: spokenLine(for: step, title: title, position: offset, total: picked.count)
            )
        }
    }

    static func pickSteps(_ steps: [CookPlan.PlanStep]) -> [CookPlan.PlanStep] {
        guard steps.count > maxBeats else { return steps }
        // Evenly sample across the cook, always including first and last.
        var indices: [Int] = [0]
        let inner = maxBeats - 2
        if inner > 0 {
            for i in 1...inner {
                let t = Double(i) / Double(inner + 1)
                let idx = Int((t * Double(steps.count - 1)).rounded())
                indices.append(idx)
            }
        }
        indices.append(steps.count - 1)
        var seen = Set<Int>()
        return indices.compactMap { idx in
            guard seen.insert(idx).inserted else { return nil }
            return steps[idx]
        }
    }

    private static func spokenLine(
        for step: CookPlan.PlanStep,
        title: String,
        position: Int,
        total: Int
    ) -> String {
        let verb: String
        switch (position, total) {
        case (0, _): verb = "Start by"
        case let (p, t) where p == t - 1 && t > 1: verb = "Finish with"
        default: verb = "Then"
        }

        let focus = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if focus.isEmpty {
            return "\(verb) \(shortClause(step.instruction))."
        }
        // "Start by boiling the pasta." — title often already verb-y.
        let lowered = focus.prefix(1).lowercased() + focus.dropFirst()
        return "\(verb) \(lowered)."
    }

    // MARK: - Copy helpers

    private static func cleanTitle(_ raw: String, fallbackIndex: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Step \(fallbackIndex + 1)" }
        // Keep beat titles short for the storyboard cards.
        if trimmed.count <= 42 { return trimmed }
        return String(trimmed.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func cleanDetail(_ instruction: String) -> String {
        let trimmed = instruction
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Follow along with Polly" }
        if trimmed.count <= 72 { return trimmed }
        // Break on a word boundary near 70 chars.
        let limit = trimmed.index(trimmed.startIndex, offsetBy: 70, limitedBy: trimmed.endIndex)
            ?? trimmed.endIndex
        var end = limit
        while end > trimmed.startIndex, trimmed[trimmed.index(before: end)] != " " {
            end = trimmed.index(before: end)
        }
        if end == trimmed.startIndex { end = limit }
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func shortClause(_ instruction: String) -> String {
        let first = instruction
            .split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ?? instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.count <= 60 { return first.prefix(1).lowercased() + first.dropFirst() }
        return String(first.prefix(58)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "…"
    }

    private static func miseLine(_ mise: [CookPlan.MiseItem]) -> String? {
        guard !mise.isEmpty else { return nil }
        let bits = mise.prefix(4).map { item in
            let prep = item.prep.trimmingCharacters(in: .whitespacesAndNewlines)
            if prep.isEmpty { return item.name }
            return "\(prep.prefix(1).uppercased() + prep.dropFirst()) \(item.name)".trimmingCharacters(in: .whitespaces)
        }
        let joined = bits.joined(separator: " · ")
        if mise.count > 4 { return joined + " · …" }
        return joined
    }

    private static func gearLine(_ equipment: [String]) -> String? {
        let cleaned = equipment
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        let shown = cleaned.prefix(3).joined(separator: " · ")
        return cleaned.count > 3 ? shown + " · …" : shown
    }

    private static func estimateTimeLabel(plan: CookPlan, recipe: Recipe) -> String {
        if recipe.estimatedMinutes > 0 {
            return recipe.minutesAreEstimated
                ? "~\(recipe.estimatedMinutes) min"
                : "\(recipe.estimatedMinutes) min"
        }
        let seconds = plan.steps.compactMap(\.estimatedSeconds).reduce(0, +)
        if seconds > 0 {
            return "~\(max(1, seconds / 60)) min"
        }
        return "a little while"
    }
}
