import XCTest
@testable import Glutt

/// The one rule dictation has to obey, tested without a microphone.
///
/// A cook listing their fridge watched the box empty itself partway through and
/// had to start over. The cause was mirroring one recognition request's
/// hypothesis straight into the UI: a request covers about a minute of audio,
/// and when it ends and the next begins, its hypothesis starts from nothing.
final class DictationTranscriptTests: XCTestCase {
    func testLiveHypothesisReplacesOnlyTheTail() {
        var t = DictationTranscript()
        t.updateLive("eggs")
        t.updateLive("eggs, milk")
        t.updateLive("eggs, milk, half an onion")
        XCTAssertEqual(t.text, "eggs, milk, half an onion")
    }

    /// The actual bug. The first request ends after roughly a minute, the next
    /// one opens on "soy sauce", and everything before it used to disappear.
    func testANewRequestDoesNotEraseTheOldOne() {
        var t = DictationTranscript()
        t.updateLive("eggs, milk, half an onion")
        t.bankLive()
        t.updateLive("soy sauce")
        XCTAssertEqual(t.text, "eggs, milk, half an onion soy sauce")
    }

    /// The recognizer is also free to revise a hypothesis downward inside one
    /// request. Whatever it does to the tail, banked text is untouchable.
    func testBankedTextSurvivesAShrinkingHypothesis() {
        var t = DictationTranscript()
        t.updateLive("eggs, milk, half an onion")
        t.bankLive()
        t.updateLive("soy sauce and rice")
        t.updateLive("soy")
        XCTAssertEqual(t.text, "eggs, milk, half an onion soy")
        XCTAssertTrue(t.text.hasPrefix("eggs, milk, half an onion"))
    }

    func testManySegmentsAccumulateInOrder() {
        var t = DictationTranscript()
        for chunk in ["eggs", "milk", "rice", "soy sauce"] {
            t.updateLive(chunk)
            t.bankLive()
        }
        XCTAssertEqual(t.text, "eggs milk rice soy sauce")
    }

    /// A request that ends before anyone speaks must not pad the list with
    /// blanks, which would show up as stray spaces in the text field.
    func testAnEmptySegmentIsNotBanked() {
        var t = DictationTranscript()
        t.updateLive("eggs")
        t.bankLive()
        t.updateLive("   ")
        t.bankLive()
        t.updateLive("")
        t.bankLive()
        XCTAssertEqual(t.text, "eggs")
    }

    /// A restarted request sometimes re-reports the tail of the one before it.
    func testARepeatedSegmentIsNotBankedTwice() {
        var t = DictationTranscript()
        t.updateLive("half an onion")
        t.bankLive()
        t.updateLive("half an onion")
        t.bankLive()
        XCTAssertEqual(t.text, "half an onion")
    }

    // MARK: - Hesitation

    /// The one a cook actually reported: pause about two seconds mid-list, carry
    /// on, and everything before the pause was gone.
    ///
    /// The recognizer treats the silence as the end of an utterance and opens a
    /// **new hypothesis** for what follows, without ending the request and
    /// without reporting anything final. So the callback after the pause carries
    /// only the new words. Nothing had been banked, because banking only
    /// happened when a request finished.
    func testAPauseMidListDoesNotWipeWhatCameBefore() {
        var t = DictationTranscript()
        t.updateLive("eggs")
        t.updateLive("eggs, milk")
        t.updateLive("eggs, milk, half an onion")
        // …two seconds of hesitation, then the recognizer starts over.
        t.updateLive("soy sauce")
        XCTAssertEqual(t.text, "eggs, milk, half an onion soy sauce")
    }

    func testSeveralHesitationsInOneListAllSurvive() {
        var t = DictationTranscript()
        t.updateLive("rice")
        t.updateLive("chicken thighs")
        t.updateLive("a bag of spinach")
        t.updateLive("two lemons")
        XCTAssertEqual(t.text, "rice chicken thighs a bag of spinach two lemons")
    }

    /// The opposite mistake, and the reason this cannot simply bank on every
    /// shrink: a recognizer walking its own guess back mid-word must not be
    /// treated as a new utterance, or the cook gets it twice.
    func testARevisionOfTheSameUtteranceIsNotBanked() {
        var t = DictationTranscript()
        t.updateLive("half an onion")
        t.updateLive("half an")
        t.updateLive("half an onion and garlic")
        XCTAssertEqual(t.text, "half an onion and garlic")
    }

    /// Punctuation and capitalisation move around between hypotheses of the same
    /// words, and must not read as a new utterance.
    func testRepunctuationIsNotANewUtterance() {
        var t = DictationTranscript()
        t.updateLive("eggs milk and rice")
        t.updateLive("Eggs, milk")
        XCTAssertEqual(t.text, "Eggs, milk")
    }

    /// Growth is always a revision, however large the jump.
    func testGrowthNeverBanks() {
        var t = DictationTranscript()
        t.updateLive("a")
        t.updateLive("a whole lot of things in my fridge right now")
        XCTAssertEqual(t.text, "a whole lot of things in my fridge right now")
    }

    /// Banking reports whether it kept anything, which is what stops the session
    /// counting an ordinary pause as a failed recognizer.
    func testBankLiveReportsWhetherItKeptAnything() {
        var t = DictationTranscript()
        t.updateLive("eggs")
        XCTAssertTrue(t.bankLive())
        XCTAssertFalse(t.bankLive(), "nothing left to bank")
        t.updateLive("eggs")
        XCTAssertFalse(t.bankLive(), "a repeat of the last segment is not new")
    }

    func testResetClearsEverything() {
        var t = DictationTranscript()
        t.updateLive("eggs")
        t.bankLive()
        t.updateLive("milk")
        t.reset()
        XCTAssertTrue(t.isEmpty)
        XCTAssertEqual(t.text, "")
    }

    /// Whatever order the callbacks arrive in, the visible text may never get
    /// shorter than what has already been banked.
    func testTextNeverLosesBankedContent() {
        var t = DictationTranscript()
        t.updateLive("eggs, milk, rice, soy sauce, half an onion")
        t.bankLive()
        let banked = t.text
        for hypothesis in ["a", "ab", "", "abc", "", "a"] {
            t.updateLive(hypothesis)
            XCTAssertTrue(t.text.hasPrefix(banked), "banked text was lost by \"\(hypothesis)\"")
        }
    }
}
