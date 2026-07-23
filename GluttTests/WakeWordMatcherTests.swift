import XCTest
@testable import Glutt

/// The pure core of the wake-word gate: detecting "Polly" in a transcript and
/// stripping it for the live caption. No Speech/audio, so it runs headless.
final class WakeWordMatcherTests: XCTestCase {

    func testDetectsPollyAndCommonMisHears() {
        XCTAssertTrue(WakeWordMatcher.containsWake("Polly is the chicken done"))
        XCTAssertTrue(WakeWordMatcher.containsWake("hey polly"))
        XCTAssertTrue(WakeWordMatcher.containsWake("POLLY!"))
        XCTAssertTrue(WakeWordMatcher.containsWake("pollie can you help"))
        XCTAssertTrue(WakeWordMatcher.containsWake("okay poly what next"))
    }

    func testIgnoresNonWakeChatter() {
        XCTAssertFalse(WakeWordMatcher.containsWake("pass the salt please"))
        XCTAssertFalse(WakeWordMatcher.containsWake("the holly bush is nice"), "near-words are excluded")
        XCTAssertFalse(WakeWordMatcher.containsWake("apollo eleven"), "substring of a real word must not fire")
        XCTAssertFalse(WakeWordMatcher.containsWake(""))
    }

    func testStripsWakeWordForTheLiveCaption() {
        XCTAssertEqual(
            WakeWordMatcher.strippedQuestion("Polly, is the chicken cooked through"),
            "is the chicken cooked through")
        XCTAssertEqual(
            WakeWordMatcher.strippedQuestion("hey polly what's next"),
            "what's next")
    }

    func testKeepsWholeTranscriptWhenNothingFollowsTheWake() {
        XCTAssertEqual(WakeWordMatcher.strippedQuestion("Polly"), "Polly")
        XCTAssertEqual(WakeWordMatcher.strippedQuestion("no wake word here"), "no wake word here")
    }

    /// The continuous recognizer keeps every past "Polly" in its transcript, so the
    /// gate wakes on a *new* one by watching this count rise (not by "contains").
    /// This is what makes her wake on the 2nd, 3rd… "Polly", not just the first.
    func testWakeCountRisesWithEachNewPolly() {
        XCTAssertEqual(WakeWordMatcher.wakeCount("nothing here yet"), 0)
        XCTAssertEqual(WakeWordMatcher.wakeCount("polly is it done"), 1)
        XCTAssertEqual(WakeWordMatcher.wakeCount("polly is it done. okay. polly is the sauce ready"), 2)
        XCTAssertEqual(WakeWordMatcher.wakeCount("hey polly, and later pollie again, and poly once more"), 3)
    }
}
