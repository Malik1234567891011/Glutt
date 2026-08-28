import AVFAudio
import SwiftData
import XCTest
@testable import Glutt

/// The turn loop, which broke twice in a row in a way no unit test could catch
/// because there was no unit test.
///
/// Both failures looked identical from outside the app — "she is not listening"
/// — and were nothing of the sort. She heard perfectly well both times. The
/// first time the event stream was blocked behind a five second hold; the second
/// time the transcript arrived and nothing ever asked her to answer it. These
/// assert the plumbing that makes a heard sentence into a spoken one.
@MainActor
final class SkillCoachSessionTests: XCTestCase {

    private var container: ModelContainer!
    /// Every session started by a test, so none is left holding a camera, a
    /// transport and a sleeping assessor into the next one. A leaked session was
    /// taking the whole test host down two tests later, which reads as a crash
    /// in whichever test happened to be next.
    private var started: [SkillCoachSession] = []

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([SkillProgress.self, SkillAttempt.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDown() async throws {
        for session in started { await session.end() }
        started = []
        container = nil
    }

    // MARK: - Doubles

    private final class SilentWakeWord: WakeWordListening {
        var onWake: (() -> Void)?
        var onPartialTranscript: ((String) -> Void)?
        var onListeningChange: ((Bool) -> Void)?
        var isAvailable = true
        var suppressed = false
        func requestAuthorization() async -> Bool { true }
        func start() { onListeningChange?(true) }
        func stop() {}
        func restart() {}
        func setSuppressed(_ value: Bool) { suppressed = value }
        nonisolated func append(_ buffer: AVAudioPCMBuffer) {}
    }

    private func makeSession(
        assess: @escaping (SkillVisualCheck, [Data]) async throws -> SkillVisualAssessment = { _, _ in
            .init(
                equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
                overall: .cannotAssess, confidence: 0)
        }
    ) -> (SkillCoachSession, FakeRealtimeTransport, SilentWakeWord) {
        let transport = FakeRealtimeTransport()
        let wake = SilentWakeWord()
        let skill = SkillCatalog.skill("knife.grip")!
        let session = SkillCoachSession(
            skill: skill,
            check: .chefKnifeGrip,
            visuals: PollyVisualSourceCoordinator(
                phone: PhoneCameraVisualSource(camera: PollyCameraController())),
            wakeWord: wake,
            deps: .init(
                mintToken: { _, _ in
                    PollySessionToken(
                        value: "ek_test", expiresAt: 1_751_500_000,
                        model: "gpt-realtime-2", voice: "marin")
                },
                makeTransport: { transport },
                assess: assess,
                now: { Date(timeIntervalSince1970: 1_751_500_000) }))
        return (session, transport, wake)
    }

    /// Drives the session far enough to be live without needing a microphone.
    private func start(_ session: SkillCoachSession) async {
        started.append(session)
        await session.start(context: container.mainContext)
    }

    // MARK: - The bug

    /// The one that shipped. She heard two questions in a row and answered
    /// neither, because a transcript is not a turn until the client says so:
    /// the audio plane is pinned at mint and never creates the response itself.
    func testHearingTheCookAsksHerToAnswer() async throws {
        let (session, transport, _) = makeSession()
        await start(session)
        guard session.phase == .live else {
            throw XCTSkip("no microphone in this test host")
        }
        let before = transport.sentNonAudio.count

        transport.push(.inputTranscript(itemId: "1", text: "How does this look?"))
        await settle()

        let created = transport.sentNonAudio.dropFirst(before).contains { event in
            if case .responseCreate = event { return true }
            return false
        }
        XCTAssertTrue(created, "a heard sentence must become a turn she answers")
    }

    /// Asking for a second response while the first is generating is rejected by
    /// the server, and the turn is lost rather than doubled.
    func testASecondTranscriptDoesNotStackAResponse() async throws {
        let (session, transport, _) = makeSession()
        await start(session)
        guard session.phase == .live else { throw XCTSkip("no microphone in this test host") }

        transport.push(.responseCreated)
        await settle()
        let before = transport.sentNonAudio.count
        transport.push(.inputTranscript(itemId: "1", text: "and what about now"))
        await settle()

        let created = transport.sentNonAudio.dropFirst(before).contains { event in
            if case .responseCreate = event { return true }
            return false
        }
        XCTAssertFalse(created, "a response was already in flight")
    }

    /// The first failure: awaiting the five second hold inside the event loop
    /// stopped every other event being read, so the session went deaf for the
    /// duration of its own check.
    func testAToolCallDoesNotBlockTheEventStream() async throws {
        let (session, transport, _) = makeSession(assess: { _, _ in
            try await Task.sleep(for: .seconds(30))   // still running when we assert
            throw CancellationError()
        })
        await start(session)
        guard session.phase == .live else { throw XCTSkip("no microphone in this test host") }

        // A check begins, and takes its five seconds of holding before it even
        // reaches the assessor.
        transport.push(.responseDone(
            status: "completed",
            calls: [.init(name: "check_the_hold", callId: "c1", argumentsJSON: "{}")]))
        let before = transport.sentNonAudio.count

        // Events arriving WHILE that is in progress must still be read. Before
        // the fix they sat unread in the stream until the whole check finished,
        // so the session was deaf for its own five second hold.
        _ = before
        transport.push(.outputAudioStarted)
        await settle(seconds: 1)
        XCTAssertTrue(session.isSpeaking, "an event arriving mid check must still be processed")

        transport.push(.outputAudioStopped)
        await settle()
        XCTAssertFalse(session.isSpeaking)
    }

    /// A cancelled response can carry partial calls; running them talks over
    /// whoever just interrupted.
    func testCallsFromACancelledResponseAreIgnored() async throws {
        // A lock rather than a captured `var`: the assessor closure runs off the
        // main actor, and mutating a local from it took the whole test host down.
        let reached = Counter()
        let (session, transport, _) = makeSession(assess: { _, _ in
            reached.bump()
            return .init(
                equipment: .init(reading: "chef's knife", supported: true, confidence: 0.9),
                overall: .ready, confidence: 0.9)
        })
        await start(session)
        guard session.phase == .live else { throw XCTSkip("no microphone in this test host") }

        transport.push(.responseDone(
            status: "cancelled",
            calls: [.init(name: "check_the_hold", callId: "c1", argumentsJSON: "{}")]))
        await settle(seconds: 1)

        XCTAssertEqual(reached.value, 0)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    // MARK: - Wake word

    /// The mic is shut until she is spoken to, which is the whole reason a
    /// kitchen full of other conversations does not become a turn every time.
    func testTheSessionStartsDormant() async throws {
        let (session, _, _) = makeSession()
        await start(session)
        guard session.phase == .live else { throw XCTSkip("no microphone in this test host") }

        XCTAssertFalse(session.isAwake)
        XCTAssertFalse(session.isListening)
    }

    func testTheWakeWordOpensTheMic() async throws {
        let (session, _, wake) = makeSession()
        await start(session)
        guard session.phase == .live else { throw XCTSkip("no microphone in this test host") }

        wake.onWake?()
        await settle()

        XCTAssertTrue(session.isAwake)
    }

    /// She must not wake herself on her own voice saying the word.
    func testSheDoesNotWakeHerself() async throws {
        let (session, transport, wake) = makeSession()
        await start(session)
        guard session.phase == .live else { throw XCTSkip("no microphone in this test host") }

        transport.push(.outputAudioStarted)
        transport.push(.outputTranscriptDelta(itemId: "a", delta: "say Chef when you are ready"))
        await settle()
        wake.onWake?()
        await settle()

        XCTAssertFalse(session.isAwake)
    }

    /// The listener is muted while she talks so her own words are never
    /// captioned as the cook's.
    func testTheListenerIsSuppressedWhileSheSpeaks() async throws {
        let (session, transport, wake) = makeSession()
        await start(session)
        guard session.phase == .live else { throw XCTSkip("no microphone in this test host") }

        transport.push(.outputAudioStarted)
        await settle()
        XCTAssertTrue(wake.suppressed)

        transport.push(.outputAudioStopped)
        await settle()
        XCTAssertFalse(wake.suppressed)
    }

    // MARK: - Helpers

    private func settle(seconds: Double = 0.35) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
