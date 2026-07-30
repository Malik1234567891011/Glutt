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

    /// Grounded AV pass (2026-07-29) with spoken evidence quotes + duration cap 274s.
    private static let eggsBenedictRules: [Rule] = [
        Rule(keywords: ["hollandaise", "emuls"], start: 40, end: 65,
             label: "Watch hollandaise emulsion",
             notice: "Butter goes in slowly while whisking so the sauce stays glossy and doesn’t split."),
        Rule(keywords: ["poach"], start: 251, end: 274,
             label: "Watch the egg poach",
             notice: "Whirlpool the water, drop the egg from a cup, and pull when the white is set."),
        Rule(keywords: ["muffin", "toast"], start: 215, end: 228,
             label: "Watch muffin toasting",
             notice: "Muffins go into the pan to suck up the Parma ham fat and toast golden."),
        Rule(keywords: ["ham", "bacon", "canadian", "prosciutto", "parma"], start: 146, end: 176,
             label: "Watch the Parma ham crisp",
             notice: "Hot pan — he fries the Parma ham until crisp (‘posh rashers of bacon’)."),
        Rule(keywords: ["simmer", "vinegar"], start: 240, end: 255,
             label: "Watch the poaching water",
             notice: "Turn the water down and spin a whirlpool before the eggs go in."),
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
