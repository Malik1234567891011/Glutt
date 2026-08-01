import Foundation

/// Builds a soft Cook Recap from session telemetry — no LLM required.
/// Scores are observational vibes for a "run", not taste grades.
enum CookRecapBuilder {

    struct Input: Equatable {
        var dishTitle: String
        var cookName: String? = nil
        var durationSeconds: Int
        var expectedMinutes: Int?
        var stepsCompleted: Int
        var stepsTotal: Int
        var endedEarly: Bool
        var pollySaves: [String]
        var substitutions: [String]
        var summary: String?
        /// Soft 1…10 from the cook about how the plate looks (optional).
        var visualSelfScore: Double? = nil
        var previousBestOverall: Double? = nil
    }

    static func build(_ input: Input) -> CookRecap {
        let saves = mergeSaves(explicit: input.pollySaves, substitutions: input.substitutions)
        let timing = timingScore(durationSeconds: input.durationSeconds, expectedMinutes: input.expectedMinutes)
        let technique = techniqueScore(
            stepsCompleted: input.stepsCompleted,
            stepsTotal: input.stepsTotal,
            endedEarly: input.endedEarly,
            saveCount: saves.count
        )
        let visual = input.visualSelfScore.map { clampScore($0) }
        let overall = overallScore(visual: visual, timing: timing.score, technique: technique.score)

        let improvement = oneImprovement(
            summary: input.summary,
            techniqueNote: technique.note,
            visual: visual
        )
        let badge = pickBadge(
            saves: saves,
            endedEarly: input.endedEarly,
            stepsCompleted: input.stepsCompleted,
            stepsTotal: input.stepsTotal,
            overall: overall,
            previousBest: input.previousBestOverall
        )
        let best = saves.first?.moment
            ?? (input.stepsCompleted > 0 ? "Made it through \(input.stepsCompleted) steps with Chef" : nil)

        return CookRecap(
            overallScore: overall,
            visualScore: visual,
            timingScore: timing.score,
            techniqueScore: technique.score,
            visualNote: visual.map { "Looks like about \(fmt($0)) visually — your read on the plate." },
            timingNote: timing.note,
            techniqueNote: technique.note,
            durationSeconds: max(0, input.durationSeconds),
            expectedMinutes: input.expectedMinutes,
            dishTitle: input.dishTitle,
            cookName: input.cookName,
            saves: saves,
            improvement: improvement,
            badge: badge,
            bestMoment: best
        )
    }

    // MARK: - Scores

    private static func timingScore(durationSeconds: Int, expectedMinutes: Int?) -> (score: Double, note: String) {
        guard let expected = expectedMinutes, expected > 0 else {
            let mins = max(1, durationSeconds / 60)
            return (7.5, "Timing: about \(mins) min — no target time on this recipe to compare.")
        }
        let actual = Double(durationSeconds) / 60.0
        let expectedD = Double(expected)
        let ratio = actual / expectedD
        // Ideal: finish near the window. Rushing hard or dragging both ding a bit.
        let score: Double
        let note: String
        if ratio >= 0.85 && ratio <= 1.25 {
            score = 9.0
            note = "Timing: \(fmt(score)) — finished near the \(expected)-min window (\(Int(actual.rounded())) min)."
        } else if ratio < 0.7 {
            score = 7.0
            note = "Timing: \(fmt(score)) — \(Int(actual.rounded())) min, faster than the ~\(expected)-min target. Speed isn't always better if sauce needed longer."
        } else if ratio <= 1.6 {
            score = 7.8
            note = "Timing: \(fmt(score)) — \(Int(actual.rounded())) min vs ~\(expected) min target. A little leisurely, still in the zone."
        } else {
            score = 6.4
            note = "Timing: \(fmt(score)) — \(Int(actual.rounded())) min (target ~\(expected)). Long cook — next time we can tighten the waits."
        }
        return (score, note)
    }

    private static func techniqueScore(
        stepsCompleted: Int,
        stepsTotal: Int,
        endedEarly: Bool,
        saveCount: Int
    ) -> (score: Double, note: String) {
        let total = max(1, stepsTotal)
        let completion = Double(stepsCompleted) / Double(total)
        var score = 5.5 + completion * 3.5
        if endedEarly { score -= 1.2 }
        // Saves mean Polly caught issues — still a good cook, slight technique ding only if many.
        if saveCount >= 3 { score -= 0.4 }
        else if saveCount == 0, completion >= 0.9, !endedEarly { score += 0.5 }
        score = clampScore(score)

        let note: String
        if endedEarly {
            note = "Technique: \(fmt(score)) — ended early at \(stepsCompleted)/\(total) steps."
        } else if completion >= 0.95 {
            note = "Technique: \(fmt(score)) — cleared the plan (\(stepsCompleted)/\(total) steps)."
        } else {
            note = "Technique: \(fmt(score)) — \(stepsCompleted) of \(total) steps done with Chef."
        }
        return (score, note)
    }

    private static func overallScore(visual: Double?, timing: Double, technique: Double) -> Double {
        if let visual {
            return clampScore(visual * 0.4 + timing * 0.3 + technique * 0.3)
        }
        return clampScore(timing * 0.45 + technique * 0.55)
    }

    // MARK: - Narrative

    private static func mergeSaves(explicit: [String], substitutions: [String]) -> [CookRecap.Save] {
        var seen = Set<String>()
        var out: [CookRecap.Save] = []
        func add(_ raw: String) {
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= 8 else { return }
            let key = cleaned.lowercased()
            guard seen.insert(key).inserted else { return }
            out.append(.init(moment: cleaned))
        }
        for s in explicit { add(s) }
        for sub in substitutions {
            if sub.lowercased().hasPrefix("substituted") {
                add(sub)
            } else {
                add("Worked around a missing ingredient — \(sub)")
            }
        }
        return Array(out.prefix(6))
    }

    private static func oneImprovement(summary: String?, techniqueNote: String, visual: Double?) -> String? {
        if let summary {
            let sentence = summary
                .split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { $0.count >= 20 })
            if let sentence {
                return sentence.hasSuffix(".") ? String(sentence) : "\(sentence)."
            }
        }
        if let visual, visual < 7.5 {
            return "Next upgrade: cleaner plating — wipe the rim and add one fresh garnish."
        }
        if techniqueNote.localizedCaseInsensitiveContains("early") {
            return "Next upgrade: finish the remaining steps before hanging up — the last ones usually polish the plate."
        }
        return "Next upgrade: taste and adjust salt/acid right before plating."
    }

    private static func pickBadge(
        saves: [CookRecap.Save],
        endedEarly: Bool,
        stepsCompleted: Int,
        stepsTotal: Int,
        overall: Double,
        previousBest: Double?
    ) -> String? {
        if let previousBest, overall > previousBest + 0.15 {
            return "Beat Your Best"
        }
        if !endedEarly, stepsTotal > 0, stepsCompleted >= stepsTotal, saves.isEmpty {
            return "Clean Run"
        }
        if saves.contains(where: { $0.moment.localizedCaseInsensitiveContains("sauce") }) {
            return "Sauce Saver"
        }
        if saves.count >= 2 {
            return "Chef Saved It"
        }
        if !endedEarly, stepsCompleted >= max(1, stepsTotal) {
            return "First Clear"
        }
        if saves.count == 1 {
            return "Comeback Cook"
        }
        return nil
    }

    private static func clampScore(_ value: Double) -> Double {
        min(10, max(1, (value * 10).rounded() / 10))
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
