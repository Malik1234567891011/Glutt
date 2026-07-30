import Foundation

/// Hand-checked windows for the Eggs Benedict pilot video while Gemini
/// indexing is flaky / free-tier limited. Matched by step title keywords —
/// CookPlan step ids change between compiles.
enum StepClipFallbacks {
    private static let eggsBenedictVideoID = "gBJjRYk0yC0"

    private struct Rule {
        let keywords: [String]
        let start: Int
        let end: Int
        let label: String
        let notice: String
    }

    private static let eggsBenedictRules: [Rule] = [
        Rule(keywords: ["hollandaise", "emuls"], start: 41, end: 58,
             label: "Watch hollandaise emulsion",
             notice: "Notice how he streams the butter in slowly while whisking so it stays glossy."),
        Rule(keywords: ["poach"], start: 250, end: 275,
             label: "Watch the egg poach",
             notice: "Watch the white wrap the yolk — pull it when the white is set but the yolk still jiggles."),
        Rule(keywords: ["muffin", "toast"], start: 214, end: 226,
             label: "Watch muffin toasting",
             notice: "Toast until the cut face is golden so it holds the sauce."),
        Rule(keywords: ["ham", "bacon", "prosciutto", "parma"], start: 147, end: 160,
             label: "Watch the ham crisp",
             notice: "A quick pan fry gives the ham a bit of colour without drying it out."),
        Rule(keywords: ["plate", "assembl", "serve", "stack"], start: 330, end: 345,
             label: "Watch the plate-up",
             notice: "Muffin, ham, egg, then hollandaise — keep the stack tight."),
    ]

    static func clips(for steps: [CookPlan.PlanStep], youtubeURL: String) -> [StepClip] {
        guard YouTubeEmbed.videoId(from: youtubeURL) == eggsBenedictVideoID else { return [] }
        var out: [StepClip] = []
        for step in steps where !CookPlan.isSetupStep(step) {
            let hay = "\(step.title) \(step.instruction)".lowercased()
            guard let rule = eggsBenedictRules.first(where: { r in
                r.keywords.contains { hay.contains($0) }
            }) else { continue }
            out.append(StepClip(
                stepID: step.id,
                youtubeVideoID: eggsBenedictVideoID,
                startSeconds: rule.start,
                endSeconds: rule.end,
                durationSeconds: rule.end - rule.start,
                matchType: "exact_recipe",
                confidence: 0.99,
                watchLabel: rule.label,
                notice: rule.notice,
                primaryAction: rule.label,
                visualCue: rule.notice
            ))
        }
        return out
    }

    /// Drop nonsense intro windows (the 0:00–0:05 bug) and fill gaps from fallbacks.
    static func merge(indexed: [StepClip], steps: [CookPlan.PlanStep], youtubeURL: String) -> [StepClip] {
        let cleaned = indexed.filter { !($0.startSeconds <= 5 && $0.durationSeconds <= 10) }
        var byStep = Dictionary(uniqueKeysWithValues: cleaned.map { ($0.stepID, $0) })
        for fb in clips(for: steps, youtubeURL: youtubeURL) {
            if byStep[fb.stepID] == nil { byStep[fb.stepID] = fb }
        }
        // If an indexed clip still looks wrong vs a fallback for the same step, prefer fallback.
        for fb in clips(for: steps, youtubeURL: youtubeURL) {
            if let existing = byStep[fb.stepID], existing.startSeconds <= 5 {
                byStep[fb.stepID] = fb
            }
        }
        return Array(byStep.values)
    }
}
