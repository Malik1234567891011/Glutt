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
        Rule(keywords: ["hollandaise", "emuls"], start: 41, end: 58,
             label: "Watch hollandaise emulsion",
             notice: "Notice how he streams the butter in slowly while whisking so it stays glossy."),
        Rule(keywords: ["poach"], start: 250, end: 275,
             label: "Watch the egg poach",
             notice: "Watch the white wrap the yolk — pull it when the white is set but the yolk still jiggles."),
        Rule(keywords: ["muffin", "toast"], start: 214, end: 226,
             label: "Watch muffin toasting",
             notice: "Toast until the cut face is golden so it holds the sauce."),
        Rule(keywords: ["ham", "bacon", "canadian", "prosciutto", "parma"], start: 147, end: 160,
             label: "Watch the ham in the pan",
             notice: "A quick pan fry gives the ham a bit of colour without drying it out."),
        Rule(keywords: ["plate", "assembl", "serve", "stack"], start: 330, end: 345,
             label: "Watch the plate-up",
             notice: "Muffin, ham, egg, then hollandaise — keep the stack tight."),
        Rule(keywords: ["simmer", "vinegar"], start: 230, end: 248,
             label: "Watch the poaching water",
             notice: "Bring it to a gentle simmer with a splash of vinegar before the eggs go in."),
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

    /// For the pilot video, prefer hand-checked windows over Gemini — Gemini
    /// often attaches the wrong segment (or a near-intro window) to non-hero steps.
    static func merge(indexed: [StepClip], steps: [CookPlan.PlanStep], youtubeURL: String) -> [StepClip] {
        let fallbacks = clips(for: steps, youtubeURL: youtubeURL)
        if YouTubeEmbed.videoId(from: youtubeURL) == eggsBenedictVideoID, !fallbacks.isEmpty {
            var byStep = Dictionary(uniqueKeysWithValues: fallbacks.map { ($0.stepID, $0) })
            // Keep any Gemini clip only when we have no fallback for that step
            // and it isn't an intro junk window.
            for clip in indexed where !(clip.startSeconds <= 5 && clip.durationSeconds <= 10) {
                if byStep[clip.stepID] == nil {
                    byStep[clip.stepID] = clip
                }
            }
            return Array(byStep.values)
        }

        let cleaned = indexed.filter { !($0.startSeconds <= 5 && $0.durationSeconds <= 10) }
        var byStep = Dictionary(uniqueKeysWithValues: cleaned.map { ($0.stepID, $0) })
        for fb in fallbacks where byStep[fb.stepID] == nil {
            byStep[fb.stepID] = fb
        }
        return Array(byStep.values)
    }
}
