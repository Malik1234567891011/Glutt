import Foundation

/// Intermediate result of any import pipeline (link, screenshot, share extension).
/// The Import Review screen edits this before it becomes a saved `Recipe`.
struct ImportedRecipeDraft: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String?
    var summary: String?
    var imageURL: String?
    var creator: String?
    var sourceURL: String?
    var platform: SourcePlatform = .website
    var caption: String?
    var servings: Int?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var ingredientLines: [String] = []
    var stepTexts: [String] = []
    var tags: [String] = []
    var calories: Int?
    var proteinGrams: Int?

    /// Human-readable problems found during extraction, shown on the review screen.
    var issues: [String] = []

    /// True when the steps were drafted by AI because the source had none.
    /// Surfaced honestly in the review screen, right above the steps.
    var stepsAreAISuggested = false

    /// True when the whole recipe was invented by Glutt from the user's pantry
    /// (not imported from a source). Shown as a friendly banner in review.
    var isAIGenerated = false

    /// 0–1 score based on how complete and parseable the extraction was.
    var confidence: Double {
        var score = 0.0
        if let title, !title.isEmpty { score += 0.15 } 
        if imageURL != nil { score += 0.1 }
        if !ingredientLines.isEmpty {
            score += 0.3
            // Bonus when most ingredient lines have a recognizable quantity.
            let parsed = ingredientLines.map(IngredientLineParser.parse)
            let withQuantity = parsed.filter { $0.quantity != nil }.count
            if Double(withQuantity) >= Double(ingredientLines.count) * 0.6 { score += 0.05 }
        }
        if !stepTexts.isEmpty { score += 0.3 }
        if prepMinutes != nil || cookMinutes != nil { score += 0.05 }
        if servings != nil { score += 0.05 }
        return min(score, 1.0)
    }

    /// Video/social sources where "draft the dish from its name" is a fair
    /// fallback — the user clearly wants THIS dish, we just can't see the video.
    var isSocialVideo: Bool {
        platform == .tiktok || platform == .instagram || platform == .youtube
    }

    static func platform(for url: URL) -> SourcePlatform {
        let host = (url.host ?? "").lowercased()
        if host.contains("tiktok") { return .tiktok }
        if host.contains("instagram") { return .instagram }
        if host.contains("youtube") || host.contains("youtu.be") { return .youtube }
        return .website
    }
}
