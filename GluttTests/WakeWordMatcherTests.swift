import XCTest
@testable import Glutt

/// The pure core of the wake-word gate: detecting "Hey Chef" in a transcript and
/// stripping it for the live caption. No Speech/audio, so it runs headless.
final class WakeWordMatcherTests: XCTestCase {

    func testDetectsHeyChefAndCommonMisHears() {
        XCTAssertTrue(WakeWordMatcher.containsWake("Hey Chef is the chicken done"))
        XCTAssertTrue(WakeWordMatcher.containsWake("hey chef"))
        XCTAssertTrue(WakeWordMatcher.containsWake("HEY CHEF!"))
        XCTAssertTrue(WakeWordMatcher.containsWake("hi chef can you help"))
        XCTAssertTrue(WakeWordMatcher.containsWake("yo chef what next"))
        XCTAssertTrue(WakeWordMatcher.containsWake("hey shef whats next"), "ASR mis-hear")
        XCTAssertTrue(WakeWordMatcher.containsWake("hey chief how long"), "ASR mis-hear")
    }

    /// The reason the phrase is two words. She calls the cook "chef" herself, so a
    /// bare "chef" would wake her off her own speaker output — and the cook says it
    /// Saying "hey" before every request got annoying, so the name alone wakes
    /// her. What keeps that safe is elsewhere: nothing in her prompt says the
    /// word, and the listener goes deaf while she is audibly speaking.
    func testBareNameWakes() {
        XCTAssertTrue(WakeWordMatcher.containsWake("chef"))
        XCTAssertTrue(WakeWordMatcher.containsWake("Chef, is the chicken done?"))
        XCTAssertTrue(WakeWordMatcher.containsWake("chef hey"), "order no longer matters")
        XCTAssertFalse(WakeWordMatcher.containsWake("pass me the chef knife"),
                       "a chef knife is a tool, not a summons")
    }

    /// Barge-in keeps the stricter test: waking her by mistake is cheap, cutting
    /// her off mid-sentence is not.
    func testWakePhraseStillRequiresALeadIn() {
        XCTAssertTrue(WakeWordMatcher.containsWakePhrase("hey chef whats next"))
        XCTAssertTrue(WakeWordMatcher.containsWakePhrase("yo chief how long"))
        XCTAssertFalse(WakeWordMatcher.containsWakePhrase("chef"))
        XCTAssertFalse(WakeWordMatcher.containsWakePhrase("Beautiful, chef."),
                       "her own praise off the speaker is not the cook interrupting")
        XCTAssertFalse(WakeWordMatcher.containsWakePhrase("chef hey"), "order matters")
    }

    func testIgnoresNonWakeChatter() {
        XCTAssertFalse(WakeWordMatcher.containsWake("pass the salt please"))
        XCTAssertFalse(WakeWordMatcher.containsWake("hey there"))
        XCTAssertFalse(WakeWordMatcher.containsWake(""))
    }

    func testStripsWakeWordForTheLiveCaption() {
        XCTAssertEqual(
            WakeWordMatcher.strippedQuestion("Hey Chef, is the chicken cooked through"),
            "is the chicken cooked through")
        XCTAssertEqual(
            WakeWordMatcher.strippedQuestion("hey chef what's next"),
            "what's next")
        XCTAssertEqual(
            WakeWordMatcher.strippedQuestion("Chef, what's next"),
            "what's next")
    }

    func testKeepsWholeTranscriptWhenNothingFollowsTheWake() {
        XCTAssertEqual(WakeWordMatcher.strippedQuestion("Hey Chef"), "Hey Chef")
        XCTAssertEqual(WakeWordMatcher.strippedQuestion("no wake phrase here"), "no wake phrase here")
    }

    /// The continuous recognizer keeps every past "Hey Chef" in its transcript, so
    /// the gate wakes on a *new* one by watching this count rise (not by "contains").
    /// This is what makes her wake on the 2nd, 3rd… ask, not just the first.
    func testWakeCountRisesWithEachNewWake() {
        XCTAssertEqual(WakeWordMatcher.wakeCount("nothing here yet"), 0)
        XCTAssertEqual(WakeWordMatcher.wakeCount("hey chef is it done"), 1)
        XCTAssertEqual(
            WakeWordMatcher.wakeCount("hey chef is it done. okay. hey chef is the sauce ready"), 2)
        XCTAssertEqual(
            WakeWordMatcher.wakeCount("hey chef, and later hi chef again, and yo chief once more"), 3,
            "a lead-in plus the name is still one wake, not two")
        XCTAssertEqual(WakeWordMatcher.wakeCount("chef chef chef"), 3,
                       "each bare name is its own ask")
    }
}

// MARK: - Barge-in gate

/// The rule that made her impossible to interrupt: while she was speaking the
/// listener dropped the whole transcript, so a wake never reached the session
/// and the cancel path never ran.
final class WakeGateOutcomeTests: XCTestCase {

    func testChefOverHerStillWakes() {
        let (decision, _) = WakeWordMatcher.outcome(
            transcript: "chef", alreadyFired: 0, sheIsSpeaking: true)
        XCTAssertTrue(decision.wake, "saying Chef over her is how the cook cuts her off")
    }

    func testHerVoiceIsNeverCaptionedAsTheCook() {
        let (decision, _) = WakeWordMatcher.outcome(
            transcript: "add the garlic now", alreadyFired: 0, sheIsSpeaking: true)
        XCTAssertFalse(decision.caption,
                       "her own voice off the speaker must not show as the cook's words")
        XCTAssertFalse(decision.wake, "no wake word, no wake")
    }

    func testNormalTranscriptCaptionsAndWakes() {
        let (decision, count) = WakeWordMatcher.outcome(
            transcript: "chef how long", alreadyFired: 0, sheIsSpeaking: false)
        XCTAssertTrue(decision.caption)
        XCTAssertTrue(decision.wake)
        XCTAssertEqual(count, 1)
    }

    /// A continuous recogniser keeps every past "Chef" in its running
    /// transcript, so one summons must not fire on every later partial.
    func testTheSameWakeDoesNotFireTwice() {
        let (decision, count) = WakeWordMatcher.outcome(
            transcript: "chef how long do I leave it",
            alreadyFired: 1,
            sheIsSpeaking: false)
        XCTAssertFalse(decision.wake, "already acted on this one")
        XCTAssertEqual(count, 1)
    }

    /// Interrupting twice in one of her turns has to work: she keeps talking
    /// through the first if the cancel loses a race.
    func testASecondChefInTheSameSegmentWakesAgain() {
        let (decision, count) = WakeWordMatcher.outcome(
            transcript: "chef wait chef",
            alreadyFired: 1,
            sheIsSpeaking: true)
        XCTAssertTrue(decision.wake)
        XCTAssertEqual(count, 2)
    }
}
