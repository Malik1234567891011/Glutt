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
            ConversationalGate.classify("Thanks Polly", context: warm),
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
            ConversationalGate.classify("Polly", context: warm),
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

    func testContinuityAfterPollySpeaks() {
        XCTAssertEqual(
            ConversationalGate.classify("what about the sauce then", context: warm),
            .directFollowUp)
    }

    func testClearInterruption() {
        XCTAssertTrue(ConversationalGate.isClearInterruption("Polly, wait"))
        XCTAssertTrue(ConversationalGate.isClearInterruption("stop"))
        XCTAssertTrue(ConversationalGate.isClearInterruption("Should I flip it now?"))
        XCTAssertFalse(ConversationalGate.isClearInterruption("hmm"))
    }

    func testLooksUnfinished() {
        XCTAssertTrue(ConversationalGate.looksUnfinished("I need to add the"))
        XCTAssertTrue(ConversationalGate.looksUnfinished("should I flip and"))
        XCTAssertTrue(ConversationalGate.looksUnfinished("uh"))
        XCTAssertFalse(ConversationalGate.looksUnfinished("Should I flip the chicken?"))
        XCTAssertFalse(ConversationalGate.looksUnfinished("lower the heat"))
    }
}
