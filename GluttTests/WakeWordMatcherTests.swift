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
    /// to other people in the kitchen constantly.
    func testBareChefNeverWakes() {
        XCTAssertFalse(WakeWordMatcher.containsWake("chef"))
        XCTAssertFalse(WakeWordMatcher.containsWake("Say that again, chef?"),
                       "her own unclear-audio line must not wake her")
        XCTAssertFalse(WakeWordMatcher.containsWake("Beautiful, chef."),
                       "Ramsay addressing the cook must not wake her")
        XCTAssertFalse(WakeWordMatcher.containsWake("pass me the chef knife"))
        XCTAssertFalse(WakeWordMatcher.containsWake("chef hey"), "order matters")
    }

    func testIgnoresNonWakeChatter() {
        XCTAssertFalse(WakeWordMatcher.containsWake("pass the salt please"))
        XCTAssertFalse(WakeWordMatcher.containsWake("hey there"))
        XCTAssertFalse(WakeWordMatcher.containsWake(""))
    }

    func testStripsWakePhraseForTheLiveCaption() {
        XCTAssertEqual(
            WakeWordMatcher.strippedQuestion("Hey Chef, is the chicken cooked through"),
            "is the chicken cooked through")
        XCTAssertEqual(
            WakeWordMatcher.strippedQuestion("hey chef what's next"),
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
            WakeWordMatcher.wakeCount("hey chef, and later hi chef again, and yo chief once more"), 3)
        XCTAssertEqual(WakeWordMatcher.wakeCount("chef chef chef"), 0,
                       "repeated bare names are not wakes")
    }
}
