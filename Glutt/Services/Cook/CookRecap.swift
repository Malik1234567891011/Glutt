import Foundation

/// One finished Polly cook framed as a "run" — soft scores, Polly Saves, and
/// a shareable next-upgrade. Not a judgment of taste (AI can't taste).
struct CookRecap: Equatable {
    struct Save: Equatable, Identifiable {
        var id: String { moment }
        let moment: String
    }

    /// Soft overall vibe, 1.0…10.0 — presented as "about an 8.2", never absolute.
    var overallScore: Double
    var visualScore: Double?
    var timingScore: Double?
    var techniqueScore: Double?

    var visualNote: String?
    var timingNote: String?
    var techniqueNote: String?

    var durationSeconds: Int
    var expectedMinutes: Int?
    var dishTitle: String
    var cookName: String?

    var saves: [Save]
    var improvement: String?
    var badge: String?
    var bestMoment: String?

    /// Soft one-liner under the score.
    var headline: String {
        if overallScore >= 8.5 { return "Strong run — this plate has presence." }
        if overallScore >= 7.0 { return "Solid cook. A couple upgrades and it's a clear." }
        if overallScore >= 5.5 { return "Honest first pass — next time gets cleaner." }
        return "Tough run, but you finished. That counts."
    }

    var timeLabel: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        if m >= 60 {
            let h = m / 60
            let rm = m % 60
            return String(format: "%dh %02dm", h, rm)
        }
        return String(format: "%d:%02d", m, s)
    }

    var runTitle: String {
        let who = (cookName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        if let who { return "\(who)'s \(dishTitle) Run" }
        return "\(dishTitle) Run"
    }
}
