import XCTest
@testable import Glutt

final class ConversationalGateTests: XCTestCase {
    private let warm = ConversationalGate.Context(
        expectsAnswer: false,
        pollySpokeRecently: true,
        onSetupStep: false,
        topicWords: ["chicken", "heat", "flip", "sauce"]
    )
    private let cold = ConversationalGate.Context(
        expectsAnswer: false,
        pollySpokeRecently: false,
        onSetupStep: false,
        topicWords: ["chicken"]
    )
    private let awaiting = ConversationalGate.Context(
        expectsAnswer: true,
        pollySpokeRecently: true,
        onSetupStep: false,
        topicWords: ["onions"]
    )
    private let onTools = ConversationalGate.Context(
        expectsAnswer: false,
        pollySpokeRecently: true,
        onSetupStep: true,
        topicWords: ["skillet", "tools"]
    )

    func testDirectFollowUpQuestions() {
        XCTAssertEqual(
            ConversationalGate.classify("Should I flip the chicken?", context: warm),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify("How long on the other side?", context: warm),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify("Wait, lower the heat?", context: warm),
            .directFollowUp)
    }

    func testAcknowledgmentsSuppressedUnlessExpectingAnswer() {
        XCTAssertEqual(
            ConversationalGate.classify("Okay", context: warm),
            .acknowledgment)
        XCTAssertEqual(
            ConversationalGate.classify("got it", context: warm),
            .acknowledgment)
        XCTAssertEqual(
            ConversationalGate.classify("Okay, thank you.", context: warm),
            .acknowledgment)
        XCTAssertEqual(
            ConversationalGate.classify("yeah", context: awaiting),
            .directFollowUp,
            "short answers count when Polly asked a question")
    }

    /// A cook reporting progress must never be filed as a throwaway "mhm" — an
    /// acknowledgment gets its turn deleted, so nothing advances and she looks
    /// deaf to the one thing the cook most wants a reply to.
    func testProgressReportsAreNotThrowawayAcknowledgments() {
        XCTAssertNotEqual(
            ConversationalGate.classify("done", context: warm),
            .acknowledgment,
            #""done" at a stove means the step is finished, not "mhm""#)
        XCTAssertNotEqual(
            ConversationalGate.classify("okay done", context: warm),
            .acknowledgment)
    }

    /// Every phrasing of "give me the next step". These are the least ambiguous
    /// things a cook says, and each one must reach the model.
    func testAdvancementRequestsAlwaysReachHer() {
        for phrase in [
            "whats next", "what's next?", "okay whats next", "next step",
            "lets move on", "moving on", "keep going", "im ready",
            "alright I got the color on it, lets move on",
        ] {
            XCTAssertEqual(
                ConversationalGate.classify(phrase, context: warm),
                .directFollowUp,
                "\"\(phrase)\" must not be dropped")
        }
    }

    func testToolsReadyIsDirectOnSetup() {
        XCTAssertEqual(
            ConversationalGate.classify("All the tools are on the counter.", context: onTools),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify("All the tools are on the counter.", context: warm),
            .directFollowUp,
            "counter / tools phrase is cook progress even off setup")
    }

    func testOffTopicQuestionIgnored() {
        XCTAssertEqual(
            ConversationalGate.classify("Why is the sky blue?", context: warm),
            .uncertain)
    }

    func testExplicitEnd() {
        XCTAssertEqual(
            ConversationalGate.classify("that's all", context: warm),
            .explicitEnd)
        XCTAssertEqual(
            ConversationalGate.classify("Thanks Chef", context: warm),
            .explicitEnd)
        XCTAssertEqual(
            ConversationalGate.classify("stop listening", context: warm),
            .explicitEnd)
    }

    /// From a real crème brûlée cook: the transcriber heard "steep cream" as
    /// "sleep screen", the bare "sleep" end-phrase matched mid-sentence, and Chef
    /// went dormant on someone asking why their screen was wrong. They had to
    /// wake her and ask again.
    func testQuestionContainingAnEndPhraseNeverEndsTheSession() {
        XCTAssertEqual(
            ConversationalGate.classify(
                "Why am I still here on the sleep screen?", context: warm),
            .directFollowUp,
            "a question is never a goodbye")

        XCTAssertNotEqual(
            ConversationalGate.classify(
                "Can you bring me to that step? Why am I still here on the sleep screen?",
                context: warm),
            .explicitEnd)
    }

    /// "steep" and "sleep" are one phoneme apart and "steep" is a cooking word,
    /// so ending a session needs the whole command now.
    func testBareSleepIsNoLongerAnEndPhrase() {
        XCTAssertNotEqual(
            ConversationalGate.classify("let the cream sleep for a bit", context: warm),
            .explicitEnd)
        XCTAssertEqual(
            ConversationalGate.classify("go to sleep", context: warm),
            .explicitEnd,
            "the actual command still works")
    }

    /// Real goodbyes are short. A cook narrating their food must not trip an end
    /// phrase buried in the middle of a sentence.
    func testRamblingSentenceContainingAnEndPhraseKeepsTheSession() {
        XCTAssertNotEqual(
            ConversationalGate.classify(
                "the custard looks all good so I am pouring it into the ramekins now",
                context: warm),
            .explicitEnd)
    }

    func testUncertainPreferredOverGuessing() {
        XCTAssertEqual(
            ConversationalGate.classify("hmm interesting", context: cold),
            .uncertain)
        XCTAssertEqual(
            ConversationalGate.classify("Chef", context: warm),
            .nameOnly,
            "wake-only should extend listen, not speak or reject")
    }

    func testKitchenPhrasesFromSessionLogAreDirect() {
        XCTAssertEqual(
            ConversationalGate.classify(
                "I just finished cutting the chicken thighs, what's left?",
                context: warm),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify("What's left?", context: warm),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify(
                "Yeah, I have everything, Paula, we can start.",
                context: awaiting),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify("Yeah, but we can go into it.", context: awaiting),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify(
                "After I finish cutting the chicken thighs what's left?",
                context: cold),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify(
                "What's the point of doing all this ahead of time, can't I just do it during the recipe?",
                context: warm),
            .directFollowUp)
    }

    /// From a real Beef Wellington session: the cook confirmed progress and
    /// asked to advance, and the gate answered `background` because the line is
    /// exactly 12 words with no topic overlap. She then said nothing, and the
    /// watchdog made her apologise for not hearing it.
    func testAdvancementRequestIsNotBackgroundChatter() {
        let searing = ConversationalGate.Context(
            expectsAnswer: false,
            pollySpokeRecently: true,
            onSetupStep: false,
            topicWords: ["beef", "wellington", "fillet", "prosciutto"]
        )
        XCTAssertEqual(
            ConversationalGate.classify(
                "That's perfect. Alright, I got the color on it, let's move on.",
                context: searing),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify("Alright, keep going.", context: searing),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify("I'm ready for the next step.", context: searing),
            .directFollowUp)
        XCTAssertEqual(
            ConversationalGate.classify("Is that enough colour?", context: cold),
            .directFollowUp,
            "the British spelling has to read as cook-related too")
        XCTAssertEqual(
            ConversationalGate.classify(
                "Did you see what happened at the game last night with my brother and his friends",
                context: searing),
            .background,
            "long chatter with no kitchen words is still not for her")
    }

    func testContinuityAfterPollySpeaks() {
        XCTAssertEqual(
            ConversationalGate.classify("what about the sauce then", context: warm),
            .directFollowUp)
    }

    func testClearInterruption() {
        XCTAssertTrue(ConversationalGate.isClearInterruption("Chef, wait"))
        XCTAssertTrue(ConversationalGate.isClearInterruption("Hey Chef"))
        XCTAssertTrue(ConversationalGate.isClearInterruption("stop"))
        XCTAssertTrue(ConversationalGate.isClearInterruption("Should I flip it now?"))
        XCTAssertFalse(ConversationalGate.isClearInterruption("hmm"))
        XCTAssertFalse(ConversationalGate.isClearInterruption("Beautiful, chef."),
                       "her own praise leaking through the speaker is not a barge-in")
    }

    /// A bare "chef" interrupts her, but only where a cook would actually put
    /// it: at the front.
    ///
    /// Barge-in used to demand the full "hey chef", which is safe and cost too
    /// much. Watching somebody cook the butter chicken, they said "chef"
    /// mid-sentence, nothing happened, and they said it again and again. The
    /// moment a person most wants to interrupt is mid-sentence, and that was
    /// the one moment the short form did not work.
    ///
    /// Position is what separates the two speakers. A cook leads with the name;
    /// her own praise trails it.
    func testABareChefInterruptsButHerOwnAddressDoesNot() {
        for summons in ["chef", "chef wait", "chef stop", "hey chef", "ok chef what now"] {
            XCTAssertTrue(
                ConversationalGate.isClearInterruption(summons),
                "\(summons) is the cook calling her")
        }
        // "that looks great chef" is deliberately NOT here. It trips an
        // unrelated path: `directPrefixes` contains "look", and " look" matches
        // inside "looks", so the sentence reads as "look at this" before the
        // name is ever considered. That is a pre-existing loose match, it is
        // reasonable for what it does, and it is not what this test is about.
        for address in ["beautiful chef", "nice one chef", "perfect chef"] {
            XCTAssertFalse(
                ConversationalGate.isClearInterruption(address),
                "\(address) is her talking to the cook, coming back through the speaker")
        }
    }

    func testLooksUnfinished() {
        XCTAssertTrue(ConversationalGate.looksUnfinished("I need to add the"))
        XCTAssertTrue(ConversationalGate.looksUnfinished("should I flip and"))
        XCTAssertTrue(ConversationalGate.looksUnfinished("uh"))
        XCTAssertFalse(ConversationalGate.looksUnfinished("Should I flip the chicken?"))
        XCTAssertFalse(ConversationalGate.looksUnfinished("lower the heat"))
    }
}
