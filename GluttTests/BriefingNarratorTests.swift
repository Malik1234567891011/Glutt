import XCTest
@testable import Glutt

/// The trailer talking over the live cook session was the worst-sounding bug in
/// the last test cook: two voices reading the same recipe at each other, with no
/// way to shut either up. These pin the rule that fixes it, which is that the
/// session silences every briefing when it starts and does not depend on the
/// view that owns one still being around to be asked.
@MainActor
final class BriefingNarratorTests: XCTestCase {

    /// A speech client that is configured but never answers, so narration parks
    /// on its first `speak` and the narrator stays mid-flight for the whole test.
    private func hangingSpeech() -> PollySpeechClient {
        var client = PollySpeechClient()
        client.baseURL = "https://example.invalid"
        client.clientKey = "test"
        client.transport = { _ in
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw CancellationError()
        }
        return client
    }

    private func briefing() -> CookBriefing {
        CookBriefing(
            dishTitle: "Gnocchi with Brown Butter and Sage",
            timeLabel: "15 min",
            servings: 4,
            beats: [
                .init(id: "b1", title: "Water on", detail: "Salted water, high heat",
                      kind: .active, spokenLine: "Water goes on first."),
                .init(id: "b2", title: "Brown the butter", detail: "Until it smells nutty",
                      kind: .checkpoint, spokenLine: "Then the butter browns."),
            ],
            miseLine: nil,
            gearLine: nil,
            introLine: "Quick look at what you're making.",
            outroLine: "That's the whole cook."
        )
    }

    func testStopAllSilencesANarratorThatIsStillSpeaking() async {
        let narrator = BriefingNarrator(speech: hangingSpeech())
        narrator.narrate(briefing())
        XCTAssertTrue(narrator.isSpeaking, "narration should be in flight")

        BriefingNarrator.stopAll()

        XCTAssertFalse(narrator.isSpeaking, "the session must be able to silence it")
        XCTAssertEqual(narrator.caption, "")
        XCTAssertFalse(narrator.didFinishNaturally,
                       "cut off is not the same as finished, and the difference drives the handoff")
    }

    /// The registry is the point. A briefing is owned by a view being dismissed
    /// at the exact moment the session starts, so the session cannot be relying
    /// on somebody remembering to hand the live narrator along.
    func testStopAllReachesEveryLiveNarrator() async {
        let first = BriefingNarrator(speech: hangingSpeech())
        let second = BriefingNarrator(speech: hangingSpeech())
        first.narrate(briefing())
        second.narrate(briefing())

        BriefingNarrator.stopAll()

        XCTAssertFalse(first.isSpeaking)
        XCTAssertFalse(second.isSpeaking)
    }

    /// Stopping twice, or stopping one that never spoke, must be a no-op rather
    /// than something that throws or re-arms anything.
    func testStopAllIsSafeWhenNothingIsSpeaking() async {
        let narrator = BriefingNarrator(speech: hangingSpeech())
        BriefingNarrator.stopAll()
        BriefingNarrator.stopAll()
        XCTAssertFalse(narrator.isSpeaking)
    }
}
