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

    /// Ordered most-specific first so "poach" wins over generic "egg".
    private static let eggsBenedictRules: [Rule] = [
        Rule(keywords: ["hollandaise", "emuls"], start: 40, end: 58,
             label: "Watch hollandaise emulsion",
             notice: "Notice how he streams the butter in slowly while whisking so it stays glossy."),
        Rule(keywords: ["poach"], start: 230, end: 255,
             label: "Watch the egg poach setup",
             notice: "Seasoned simmering water, then the egg goes in — pull when the white is set."),
        Rule(keywords: ["muffin", "toast"], start: 214, end: 226,
             label: "Watch muffin toasting",
             notice: "Toast until the cut face is golden so it holds the sauce."),
        Rule(keywords: ["ham", "bacon", "canadian", "prosciutto", "parma"], start: 134, end: 155,
             label: "Watch the Parma ham crisp",
             notice: "He fries thin Parma ham until crisp, then uses that fat to toast the muffins."),
        Rule(keywords: ["simmer", "vinegar"], start: 230, end: 245,
             label: "Watch the poaching water",
             notice: "Bring it to a gentle simmer with a splash of vinegar before the eggs go in."),
        Rule(keywords: ["plate", "assembl", "serve", "stack"], start: 255, end: 274,
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

    /// Prefer grounded Gemini clips when they look valid; fill gaps from
    /// hand-checked pilot windows. Never let intro junk (0:00–0:05) win.
    static func merge(indexed: [StepClip], steps: [CookPlan.PlanStep], youtubeURL: String) -> [StepClip] {
        let fallbacks = clips(for: steps, youtubeURL: youtubeURL)
        let cleaned = indexed.filter { !($0.startSeconds <= 5 && $0.durationSeconds <= 10) }

        var byStep: [String: StepClip] = [:]
        for clip in cleaned where clip.confidence >= 0.8 {
            byStep[clip.stepID] = clip
        }
        for fb in fallbacks {
            if let existing = byStep[fb.stepID] {
                // Keep grounded/indexed unless it's still an implausible short intro.
                if existing.startSeconds <= 5 { byStep[fb.stepID] = fb }
            } else {
                byStep[fb.stepID] = fb
            }
        }
        return Array(byStep.values)
    }
}
