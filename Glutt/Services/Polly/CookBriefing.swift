import Foundation

/// A short pre-cook "trailer" — visual storyboard beats + a shallow spoken rundown
/// so cooks aren't going in blind when they hit Cook with Polly.
struct CookBriefing: Equatable {
    struct Beat: Identifiable, Equatable {
        let id: String
        let title: String
        /// One glanceable line (what happens in this phase).
        let detail: String
        let kind: CookPlan.StepKind
        /// The sentence Polly/narrator says for this beat.
        let spokenLine: String
    }

    let dishTitle: String
    let timeLabel: String
    let servings: Int
    let beats: [Beat]
    /// Optional prep teaser shown under the reel ("Mince garlic · Dice onion").
    let miseLine: String?
    /// Optional gear teaser ("Skillet · Pot").
    let gearLine: String?
    /// Full narration in order: intro → beats → outro. Used when speaking
    /// as one continuous script (beat highlighting still advances by index).
    var spokenChunks: [String] {
        var chunks: [String] = []
        chunks.append(introLine)
        chunks.append(contentsOf: beats.map(\.spokenLine))
        chunks.append(outroLine)
        return chunks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    let introLine: String
    let outroLine: String
}
