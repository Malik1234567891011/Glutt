import Foundation

/// Lightweight addressee / intent gate for Polly follow-ups.
/// Runs on the client before we ask the Realtime model to speak — so kitchen
/// chatter, self-talk, and bare "okay"s never become committed spoken turns.
enum ConversationalGate {
    enum Decision: String, Equatable {
        case directFollowUp
        case acknowledgment
        case background
        case selfTalk
        case uncertain
        case explicitEnd
        /// Just the wake name while already engaged — extend listen, don't speak,
        /// and do NOT count as a reject toward dormancy.
        case nameOnly
    }

    struct Context: Equatable {
        /// Polly's previous line asked something that expects an answer.
        var expectsAnswer: Bool
        /// Polly finished speaking within the last ~12s (session still warm).
        var pollySpokeRecently: Bool
        /// Cook is on Tools or Prep — readiness phrases are clearly for Polly.
        var onSetupStep: Bool
        /// Active recipe / step / timer words for soft topical match.
        var topicWords: [String]
    }

    /// Clear stop / leave-me-alone phrases (normalized: no apostrophes).
    private static let explicitEndPhrases: [String] = [
        "stop listening", "thats all", "thanks chef", "thank you chef",
        "go away", "never mind", "nevermind", "im good", "were good", "were good",
        "all good", "that is all", "bye chef", "sleep", "shut up",
    ]

    /// Bare acks — normally no spoken reply unless Polly asked a question.
    private static let acknowledgmentExact: Set<String> = [
        "ok", "okay", "k", "kk", "alright", "all right", "got it", "gotcha",
        "perfect", "thanks", "thank you", "cool", "great", "nice", "yep", "yup",
        "yeah", "yea", "yes", "sure", "mm", "mmm", "mmhmm", "uh huh", "uh-huh",
        "right", "sounds good", "will do", "copy", "roger", "bet", "done",
    ]

    /// Strong openers that almost always mean the cook is talking to Polly.
    private static let directPrefixes: [String] = [
        "should i", "can i", "could i", "what if", "what is", "whats",
        "what are", "how much", "how long", "how many", "do i", "did i", "why",
        "wait", "what about", "whats left", "what left",
        "whats next", "when do", "when should", "is it", "is the",
        "are the", "are my", "am i", "no i meant", "actually",
        "hold on", "hang on", "tell me", "remind me", "check", "look at", "look",
        "i finished", "i just finished", "im done", "im ready",
        "we can start", "lets start", "let us start",
        "i have everything", "ive got everything",
        "we can go", "lets go", "go ahead", "after i",
    ]

    /// Interrupt-while-speaking commands (stricter barge-in).
    private static let interruptPhrases: [String] = [
        "chef wait", "wait chef", "stop", "hold on", "hang on", "no stop",
        "cancel", "shut up", "quiet",
    ]

    /// How the cook addresses her mid-sentence, plus the mis-hears ASR returns.
    /// Bare "chef" is fine to list here because these only classify a turn that
    /// already reached the gate; waking her still needs the full "hey chef".
    private static let nameMishears: Set<String> = [
        "chef", "chefs", "shef", "sheff", "chief",
    ]

    static func classify(_ raw: String, context: Context) -> Decision {
        // Preserve "?" before normalize strips punctuation — otherwise every
        // real question ("what's left?") collapses to uncertain.
        let hadQuestionMark = raw.contains("?")
        let text = normalize(raw)
        guard !text.isEmpty else { return .uncertain }

        if matchesAnyPhrase(text, explicitEndPhrases) { return .explicitEnd }

        // Wake-only / name alone — keep listening, don't speak, don't reject.
        if isNameOnly(text) { return .nameOnly }

        if context.expectsAnswer, isShortAnswer(text) {
            return .directFollowUp
        }

        if isAcknowledgment(text) {
            return context.expectsAnswer ? .directFollowUp : .acknowledgment
        }

        // "Tools are on the counter" / "board is ready" while on Tools/Prep.
        if looksLikeSetupComplete(text) {
            return .directFollowUp
        }

        if looksLikeCookProgress(text) { return .directFollowUp }

        // Questions / commands: only auto-accept when they look cook-related.
        // Bare "why is the sky blue?" must NOT steal the session.
        if hadQuestionMark || looksLikeDirectFollowUp(text) {
            if looksLikeCookRelated(text, context: context) {
                return .directFollowUp
            }
            return .uncertain
        }

        if looksLikeSelfTalk(text) { return .selfTalk }

        if looksLikeBackground(text, topicWords: context.topicWords) {
            return .background
        }

        // Soft topical / pronoun continuation right after Polly spoke.
        if context.pollySpokeRecently, hasContinuityCue(text) {
            return .directFollowUp
        }

        if overlapsTopic(text, topicWords: context.topicWords),
           looksLikeCookProgress(text) || hasContinuityCue(text) {
            return .directFollowUp
        }

        if context.pollySpokeRecently, overlapsTopic(text, topicWords: context.topicWords) {
            return .directFollowUp
        }

        // Prefer false silence over interrupting private conversation.
        return .uncertain
    }

    /// True when the utterance is a clear barge-in while Polly is talking.
    static func isClearInterruption(_ raw: String) -> Bool {
        let hadQuestionMark = raw.contains("?")
        let text = normalize(raw)
        guard !text.isEmpty else { return false }
        if matchesAnyPhrase(text, interruptPhrases) { return true }
        // The full wake phrase, not a bare "chef": she calls the cook "chef"
        // herself, and speaker leak must not read as the cook barging in.
        if WakeWordMatcher.containsWake(text) { return true }
        if hadQuestionMark || looksLikeDirectFollowUp(text) { return true }
        return false
    }

    /// Trailing words that usually mean the cook is still thinking — hold before
    /// committing a response so a continuation can land.
    private static let unfinishedTrailers: Set<String> = [
        "and", "or", "but", "because", "so", "then", "if", "when", "uh", "um",
        "uhh", "umm", "like", "wait", "the", "a", "an", "to", "for", "with",
        "of", "my", "some",
    ]

    static func looksUnfinished(_ raw: String) -> Bool {
        if raw.contains("?") { return false }
        let text = normalize(raw)
        guard !text.isEmpty else { return true }
        let tokens = text.split(separator: " ").map(String.init)
        guard let last = tokens.last else { return true }
        if unfinishedTrailers.contains(last) { return true }
        // Bare quantity with no unit/noun yet: "two", "half", "a cup of"
        if tokens.count <= 2, ["one", "two", "three", "half", "quarter"].contains(last) {
            return true
        }
        return false
    }

    // MARK: - Helpers

    private static func normalize(_ raw: String) -> String {
        // Drop apostrophes *before* the punctuation wipe — otherwise "that's"
        // becomes "that s" and every what's/that's phrase misses the gate.
        // (Raw-string #"\u{2019}"# does NOT expand; use real characters.)
        raw.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            // Keep letters/digits/spaces only.
            .replacingOccurrences(of: #"[^a-z0-9\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isNameOnly(_ text: String) -> Bool {
        let tokens = text.split(separator: " ").map(String.init)
        guard tokens.count <= 2 else { return false }
        return tokens.allSatisfy { nameMishears.contains($0) || WakeWordMatcher.leadIns.contains($0) }
    }

    private static func isAcknowledgment(_ text: String) -> Bool {
        if acknowledgmentExact.contains(text) { return true }
        // Multi-word thanks / okay variants.
        let phrases = [
            "okay thank you", "ok thank you", "okay thanks", "ok thanks",
            "thanks a lot", "thank you so much", "thanks so much",
        ]
        if phrases.contains(where: { text == $0 || text.hasPrefix($0 + " ") }) {
            return true
        }
        // "okay thanks", "alright cool"
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty, tokens.count <= 5 else { return false }
        let soft = acknowledgmentExact.union(["thank", "you", "thanks"])
        return tokens.allSatisfy { soft.contains($0) || nameMishears.contains($0) }
    }

    private static func isShortAnswer(_ text: String) -> Bool {
        let tokens = text.split(separator: " ")
        return tokens.count <= 6
    }

    private static func looksLikeDirectFollowUp(_ text: String) -> Bool {
        if directPrefixes.contains(where: { text.hasPrefix($0) || text.contains(" " + $0) }) {
            return true
        }
        // Imperatives common at the stove.
        let commandStarts = ["flip", "lower", "raise", "turn", "stir", "add", "take",
                             "remove", "start", "set", "show", "next", "go to", "skip",
                             "cut", "chop", "mix", "season"]
        if commandStarts.contains(where: { text.hasPrefix($0) }) { return true }
        return false
    }

    /// Progress / readiness reports cooks say mid-recipe.
    private static func looksLikeCookProgress(_ text: String) -> Bool {
        let cues = [
            "finished", "whats left", "what left", "whats next",
            "what next", "ready", "we can start", "lets start",
            "i have everything", "have everything", "can start",
            "can go into", "go into it", "cutting the", "cut the", "done with",
            "done cutting", "all set", "missing", "on the counter", "tools are",
            "got my tools", "tools ready", "board is ready", "prep is done",
            "done prep", "knife work", "mise",
        ]
        return cues.contains { text.contains($0) }
    }

    private static func looksLikeSetupComplete(_ text: String) -> Bool {
        let cues = [
            "on the counter", "tools are", "got my tools", "tools ready",
            "pulled out", "i have the", "board is ready", "im set",
            "all set", "ready for prep", "prep is done", "done prep",
            "finished prep", "knife work done", "everythings out",
        ]
        return cues.contains { text.contains($0) }
    }

    private static func looksLikeCookRelated(_ text: String, context: Context) -> Bool {
        if context.onSetupStep { return true }
        if context.expectsAnswer { return true }
        if looksLikeCookProgress(text) || looksLikeSetupComplete(text) { return true }
        if overlapsTopic(text, topicWords: context.topicWords) { return true }
        let cookWords = [
            "cook", "recipe", "step", "prep", "heat", "pan", "skillet", "oven",
            "chicken", "onion", "garlic", "timer", "flip", "stir", "salt",
            "ahead", "mise", "board", "knife", "tools", "ingredient", "spice",
            "rice", "sauce", "oil", "simmer", "sear", "boil", "bake",
        ]
        if cookWords.contains(where: { text.contains($0) }) { return true }
        // Strong cook-shaped openers even without a recipe noun.
        let cookOpeners = [
            "should i", "can i", "how long", "how much", "whats next",
            "whats left", "do i", "is it done", "am i",
        ]
        return cookOpeners.contains(where: { text.hasPrefix($0) || text.contains($0) })
    }

    private static func hasContinuityCue(_ text: String) -> Bool {
        let cues = [" it ", " that ", " then ", " this ", " there ", " again ",
                    "how long", "what about", "whats left",
                    "why ", "still ", " left"]
        let padded = " \(text) "
        return cues.contains { padded.contains($0) }
            || text.hasPrefix("it ") || text.hasPrefix("that ")
            || text.hasPrefix("then ") || text.hasPrefix("this ")
    }

    private static func looksLikeSelfTalk(_ text: String) -> Bool {
        let cues = ["let me see", "where was i", "okay so", "alright so",
                    "one cup", "two cups", "tablespoon", "teaspoon",
                    "step one", "step two", "step three"]
        return cues.contains { text.contains($0) } && !looksLikeDirectFollowUp(text)
            && !looksLikeCookProgress(text)
    }

    private static func looksLikeBackground(_ text: String, topicWords: [String]) -> Bool {
        // Another person being addressed by name (not Polly).
        let names = ["honey", "babe", "dude", "guys", "mom", "dad", "bro"]
        if names.contains(where: { text.hasPrefix($0 + " ") || text.contains(" " + $0 + " ") }) {
            return !overlapsTopic(text, topicWords: topicWords)
        }
        // Long side chatter with no kitchen/topic overlap.
        let tokens = text.split(separator: " ")
        if tokens.count >= 12, !overlapsTopic(text, topicWords: topicWords),
           !looksLikeDirectFollowUp(text), !looksLikeCookProgress(text) {
            return true
        }
        return false
    }

    private static func overlapsTopic(_ text: String, topicWords: [String]) -> Bool {
        let words = Set(text.split(separator: " ").map { String($0) })
        for topic in topicWords {
            let t = topic.lowercased()
            if t.count >= 3, words.contains(t) || text.contains(t) { return true }
        }
        return false
    }

    private static func matchesAnyPhrase(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text == $0 || text.hasPrefix($0 + " ") || text.contains(" " + $0) }
    }
}
