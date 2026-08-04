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

    func testLooksUnfinished() {
        XCTAssertTrue(ConversationalGate.looksUnfinished("I need to add the"))
        XCTAssertTrue(ConversationalGate.looksUnfinished("should I flip and"))
        XCTAssertTrue(ConversationalGate.looksUnfinished("uh"))
        XCTAssertFalse(ConversationalGate.looksUnfinished("Should I flip the chicken?"))
        XCTAssertFalse(ConversationalGate.looksUnfinished("lower the heat"))
    }
}
