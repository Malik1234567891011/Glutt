import Foundation

/// Did the cook just ask to be looked at?
///
/// Used to start looking BEFORE she answers. The model takes a second or two to
/// decide to call the tool and another second or two to say "let me have a
/// look", and all of that is dead time the cook spends holding a knife up at
/// nothing. Reading the request ourselves and starting the assessment
/// immediately means her line and the looking happen at the same time, and the
/// verdict lands roughly when she finishes speaking.
///
/// Deliberately not a gate. Nothing here decides whether she looks; the tool
/// call still does that. This only decides whether the work starts early, so a
/// false positive costs one vision call and a false negative costs nothing but
/// the old timing. That asymmetry is why the matching is generous.
enum SkillLookRequest {

    /// Verbs that mean "use your eyes", which are unambiguous on their own.
    private static let lookVerbs = [
        "look", "see", "check", "watch", "tell me how", "what do you think",
    ]

    /// Ways of presenting something without naming the looking. These need the
    /// utterance to be short, because "this is how my grandmother taught me and
    /// she cooked for six people every night" is a story, not a request.
    private static let showingPhrases = [
        "like this", "this look", "does this", "is this", "is that", "how about",
        "how does this", "how is this", "what about this", "better now", "is it better",
        "i fixed", "i changed", "i moved", "try again", "again now", "how about now",
        "am i doing", "am i holding", "right now",
    ]

    /// Longest an utterance can be and still count as showing something.
    private static let showingMaxWords = 12

    static func isAskingToBeSeen(_ raw: String) -> Bool {
        let text = normalize(raw)
        guard !text.isEmpty else { return false }

        // A look verb is enough on its own, at any length: "can you look at my
        // hand and tell me if the thumb is in the right place" is long and is
        // very obviously a request.
        if lookVerbs.contains(where: { text.contains($0) }) { return true }

        let words = text.split(separator: " ").count
        guard words <= showingMaxWords else { return false }
        return showingPhrases.contains { text.contains($0) }
    }

    /// Lowercased, punctuation stripped, apostrophes removed so "doesn't" and
    /// "doesnt" match the same way.
    private static func normalize(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
