import Foundation

/// Last-resort gap-fill when Gemini returns nothing usable.
/// Intentionally empty of per-video timestamp tables — clip windows must come
/// from the grounded AV pipeline, not human-hardcoded ranges.
enum StepClipFallbacks {
    static func clips(for steps: [CookPlan.PlanStep], youtubeURL: String) -> [StepClip] {
        _ = steps
        _ = youtubeURL
        return []
    }

    /// AI clips win. Only drops classic junk intro windows (0–5s).
    static func merge(indexed: [StepClip], steps: [CookPlan.PlanStep], youtubeURL: String) -> [StepClip] {
        _ = steps
        _ = youtubeURL
        return indexed.filter { !($0.startSeconds <= 5 && $0.durationSeconds <= 10) }
    }
}
