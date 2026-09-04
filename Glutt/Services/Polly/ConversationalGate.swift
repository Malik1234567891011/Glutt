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
        /// The cook said the wake word and this is what they said next.
        ///
        /// Addressing her by name is the least ambiguous signal there is, and it
        /// has to outrank every heuristic that guesses at addressee. "Chef, go
        /// back to step one" was being read as self-talk and deleted, twice in a
        /// row, which looks exactly like the assistant has stopped working.
        var wokenByWakeWord: Bool = false
    }

    /// Clear stop / leave-me-alone phrases (normalized: no apostrophes).
    /// `matchesAnyPhrase` matches these anywhere in the utterance, so every entry
    /// has to be something nobody says in the middle of a sentence about food.
    ///
    /// A bare "sleep" used to be here and it cost a real cook their session: the
    /// transcriber heard "steep cream" as "sleep screen", the substring matched,
    /// and Chef hung up on someone asking a question. "steep" and "sleep" are one
    /// phoneme apart and "steep" is a cooking word, so this now needs the whole
    /// command.
    private static let explicitEndPhrases: [String] = [
        "stop listening", "thats all", "thanks chef", "thank you chef",
        "go away", "never mind", "nevermind", "im good", "were good", "were good",
        "all good", "that is all", "bye chef", "go to sleep", "go back to sleep",
        "shut up",
    ]

    /// Longest an utterance can be and still be read as "leave me alone".
    ///
    /// Real goodbyes are short. Anything rambling that happens to contain "all
    /// good" or "im good" is a cook narrating their food, and ending the session
    /// on it is the most expensive mistake this gate can make: they have to
    /// notice Chef left, say the wake word, and start the thought again.
    private static let explicitEndMaxWords = 6

    /// Bare acks — normally no spoken reply unless Polly asked a question.
    ///
    /// "done" is deliberately NOT here. At a stove it is a progress report — the
    /// cook's way of saying they finished the step and want the next one — and
    /// treating it as a throwaway "mhm" deleted the turn and left them waiting on
    /// an assistant that had decided their news was not worth answering.
    private static let acknowledgmentExact: Set<String> = [
        "ok", "okay", "k", "kk", "alright", "all right", "got it", "gotcha",
        "perfect", "thanks", "thank you", "cool", "great", "nice", "yep", "yup",
        "yeah", "yea", "yes", "sure", "mm", "mmm", "mmhmm", "uh huh", "uh-huh",
        "right", "sounds good", "will do", "copy", "roger", "bet",
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
        "go back", "back to step", "go to step", "take me back", "repeat",
    ]

    /// Interrupt-while-speaking commands (stricter barge-in).
    private static let interruptPhrases: [String] = [
        "chef wait", "wait chef", "stop", "hold on", "hang on", "no stop",
        "cancel", "shut up", "quiet",
    ]

    /// How the cook addresses her mid-sentence, plus the mis-hears ASR returns.
    /// These only classify a turn that already reached the gate.
    private static let nameMishears: Set<String> = [
        "chef", "chefs", "shef", "sheff", "chief",
    ]

    static func classify(_ raw: String, context: Context) -> Decision {
        // Preserve "?" before normalize strips punctuation — otherwise every
        // real question ("what's left?") collapses to uncertain.
        let hadQuestionMark = raw.contains("?")
        let text = normalize(raw)
        guard !text.isEmpty else { return .uncertain }

        // A question is never a goodbye. This check runs before everything else,
        // so without the guard any sentence containing an end phrase ends the
        // session, including the one that asks why the screen is wrong.
        //
        // Deliberately narrower than `looksLikeDirectFollowUp`, which also
        // matches imperatives: that treats "go to sleep" as a question, because
        // it starts with "go to".
        if !isQuestion(raw: raw, text: text),
           text.split(separator: " ").count <= explicitEndMaxWords,
           matchesAnyPhrase(text, explicitEndPhrases) {
            return .explicitEnd
        }

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

        // Everything below here is addressee guesswork, and guesswork must not
        // overrule the cook saying her name. Muttering "okay so, step one" to
        // yourself and telling her "go back to step one" are the same words; the
        // wake word is what separates them, so once it has been said, commit.
        if looksLikeSelfTalk(text) {
            return context.wokenByWakeWord ? .directFollowUp : .selfTalk
        }

        if looksLikeBackground(text, topicWords: context.topicWords) {
            return context.wokenByWakeWord ? .directFollowUp : .background
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
    /// NO LONGER CONSULTED FOR BARGE-IN, as of the 2026-08 test session.
    ///
    /// Cutting Chef off mid-sentence is the wake word's job and nothing else:
    /// this judged a transcript confident enough to interrupt on, which meant
    /// somebody else in the room could stop her talking. Kept, with its tests,
    /// because the judgement itself is sound and the next thing that wants
    /// "is this addressed to us" should start here rather than reinvent it.
    static func isClearInterruption(_ raw: String) -> Bool {
        let hadQuestionMark = raw.contains("?")
        let text = normalize(raw)
        guard !text.isEmpty else { return false }
        if matchesAnyPhrase(text, interruptPhrases) { return true }
        // A bare "chef" counts, same as everywhere else.
        //
        // This used to demand the full "hey chef" to interrupt, on the grounds
        // that cutting her off mid-sentence is expensive to get wrong. Watching
        // somebody cook showed the other side of that trade and it is worse:
        // they said "chef", nothing happened because she was still talking,
        // and they said it again, and again. The moment a person most wants to
        // interrupt is mid-sentence, and that was the one moment the short form
        // did not work.
        //
        // A bare "chef" is allowed, but only where a cook would put it: at the
        // front. Her own praise leaking through the speaker trails it instead,
        // "beautiful, chef", and an existing test caught that the moment this
        // was relaxed too far. See `containsSummons`.
        if WakeWordMatcher.containsSummons(text) { return true }
        if hadQuestionMark || looksLikeDirectFollowUp(text) { return true }
        return false
    }

    /// Whether what we heard reads as something asked of Chef, rather than a
    /// scrap of a conversation with somebody else in the room.
    ///
    /// Used at the listening ceiling, where the choice is between answering a
    /// real question the cook asked before turning away, and staying out of a
    /// conversation that was never ours. Deliberately stricter than the ordinary
    /// turn gate: by the time this runs the cook has been talking for
    /// twenty-five seconds, so most of the transcript is likely to be the other
    /// conversation, and answering the wrong half is worse than saying nothing.
    static func looksAddressedToChef(_ raw: String) -> Bool {
        let text = normalize(raw)
        guard !text.isEmpty else { return false }
        // Two words is not a question, it is an offcut.
        guard text.split(separator: " ").count >= 3 else { return false }
        if WakeWordMatcher.containsWake(text) { return true }
        if raw.contains("?") { return true }
        return looksLikeDirectFollowUp(text)
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

    /// Is the cook asking something, rather than telling Chef to go away?
    ///
    /// Only used to protect a turn from being read as a goodbye, so it errs
    /// toward "yes, a question": staying listening one turn too long costs
    /// nothing, and hanging up on a question costs the cook their place.
    private static let questionOpeners: [String] = [
        "what", "whats", "why", "how", "when", "where", "which", "who",
        "can", "could", "should", "shall", "do", "does", "did", "is", "are",
        "am", "was", "were", "will", "would",
    ]

    private static func isQuestion(raw: String, text: String) -> Bool {
        if raw.contains("?") { return true }
        return questionOpeners.contains { text == $0 || text.hasPrefix($0 + " ") }
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
    ///
    /// The advancement cues ("move on", "keep going") are here because a real
    /// cook said "That's perfect. Alright, I got the color on it, let's move on."
    /// and the gate called it `background`: it is exactly 12 words, so it hit the
    /// long-chatter rule in `looksLikeBackground` while matching nothing here.
    /// Asking to advance is the single least ambiguous thing a cook says to her.
    private static let cookProgressCues = [
        "finished", "whats left", "what left", "whats next",
        "what next", "ready", "we can start", "lets start",
        "i have everything", "have everything", "can start",
        "can go into", "go into it", "cutting the", "cut the", "done with",
        "done cutting", "all set", "missing", "on the counter", "tools are",
        "got my tools", "tools ready", "board is ready", "prep is done",
        "done prep", "knife work", "mise",
        "move on", "moving on", "keep going", "carry on", "next step",
        "got the color", "got the colour",
    ]

    private static func looksLikeCookProgress(_ text: String) -> Bool {
        cookProgressCues.contains { text.contains($0) }
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
            // Both spellings: the British personas coach in "colour", and the
            // cook echoes back whichever one ASR heard.
            "color", "colour",
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
