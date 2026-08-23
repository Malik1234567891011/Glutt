import Foundation

/// Breaks a cook-plan step into short, tappable actions for the live Polly UI.
/// Deterministic — no LLM — so the guide can appear instantly as the step opens.
enum StepActionChecklist {

    struct Item: Equatable, Identifiable, Hashable {
        let id: String
        let text: String
        /// Visual doneness cue ("Done when…") — styled differently in the UI.
        let isVisualCheck: Bool

        init(id: String, text: String, isVisualCheck: Bool = false) {
            self.id = id
            self.text = text
            self.isVisualCheck = isVisualCheck
        }
    }

    /// Full checklist for one step. Tools and Prep are split on purpose so
    /// cooks never get a 30-row wall of gear + spices + knife work.
    static func items(
        for step: CookPlan.PlanStep,
        plan: CookPlan
    ) -> [Item] {
        var rows: [Item] = []

        if step.id == CookPlan.toolsStepID {
            for (i, gear) in plan.equipment.enumerated() {
                let g = gear.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !g.isEmpty else { continue }
                rows.append(Item(id: "gear-\(i)", text: "Grab \(g)"))
            }
        } else if step.id == CookPlan.prepStepID || step.kind == .prep {
            // Board work only — never mix tools or spice measuring in here.
            for (i, mise) in plan.mise.enumerated() {
                let prep = mise.prep.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = mise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let text: String
                // Same phrasing rule as the Prep step's own sentence, so the
                // checklist does not read "Slice finely the garlic" beside an
                // instruction that says "slice the garlic finely".
                if prep.isEmpty {
                    text = "Ready: \(name)"
                } else {
                    let phrase = CookPlan.phrase(for: mise)
                    text = phrase.prefix(1).uppercased() + phrase.dropFirst()
                }
                rows.append(Item(id: "mise-\(i)", text: text))
            }
        }

        if rows.isEmpty {
            rows.append(contentsOf: splitInstruction(step.instruction, stepID: step.id))
        }

        // Ingredient touches for cook steps only (not Tools/Prep).
        if !CookPlan.isSetupStep(step) {
            for (i, name) in step.ingredientNames.enumerated() {
                let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !n.isEmpty else { continue }
                let id = "ing-\(step.id)-\(i)"
                if !rows.contains(where: { $0.text.localizedCaseInsensitiveContains(n) }) {
                    rows.append(Item(id: id, text: "Use: \(n)"))
                }
            }
        }

        if let check = step.visualCheck?.trimmingCharacters(in: .whitespacesAndNewlines),
           !check.isEmpty {
            rows.append(Item(id: "visual-\(step.id)", text: "Done when: \(check)", isVisualCheck: true))
        }

        var seen = Set<String>()
        var unique: [Item] = []
        for row in rows {
            let key = row.text.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(row)
        }

        if unique.isEmpty {
            let fallback = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                unique = [Item(id: "full-\(step.id)", text: fallback)]
            }
        }
        return unique
    }

    /// Resolve fuzzy cook speech ("tomatoes", "cucumber") to checklist item ids.
    static func matchingIDs(matches: [String], in items: [Item]) -> [String] {
        var found: [String] = []
        for raw in matches {
            let query = normalize(raw)
            guard query.count >= 3 else { continue }
            if let hit = items.first(where: { itemMatches($0, query: query) }) {
                if !found.contains(hit.id) { found.append(hit.id) }
            }
        }
        return found
    }

    /// Split an instruction into short imperative bites.
    static func splitInstruction(_ instruction: String, stepID: String) -> [Item] {
        let trimmed = instruction
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var parts = trimmed
            .components(separatedBy: CharacterSet(charactersIn: ";."))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.count <= 1 {
            let lower = trimmed.lowercased()
            for sep in [" and then ", ", then ", " then "] {
                if lower.contains(sep) {
                    parts = trimmed
                        .components(separatedBy: sep)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    break
                }
            }
        }

        if parts.count <= 1, trimmed.count > 90 {
            let commaParts = trimmed
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.split(separator: " ").count >= 3 }
            if commaParts.count >= 2 { parts = commaParts }
        }

        return parts.enumerated().map { i, part in
            var text = part
            if let first = text.first, first.isLowercase {
                text = text.prefix(1).uppercased() + text.dropFirst()
            }
            return Item(id: "\(stepID)-\(i)", text: text)
        }
    }

    // MARK: - Matching

    private static func itemMatches(_ item: Item, query: String) -> Bool {
        let hay = normalize(item.text)
        if hay.contains(query) { return true }
        // Word-level: "tomato" hits "dice the tomatoes"
        let words = hay.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains { word in
            word == query
                || word.hasPrefix(query)
                || query.hasPrefix(word) && word.count >= 4
        }
    }

    private static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Light plural fold so "tomatoes" ↔ "tomato".
        if s.hasSuffix("oes"), s.count > 4 {
            s = String(s.dropLast(2)) // tomatoes → tomato
        } else if s.hasSuffix("ies"), s.count > 4 {
            s = String(s.dropLast(3)) + "y"
        } else if s.hasSuffix("s"), !s.hasSuffix("ss"), s.count > 3 {
            s = String(s.dropLast())
        }
        return s
    }
}
