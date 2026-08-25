import AVFoundation
import XCTest
import SwiftData
@testable import Glutt

// MARK: - FakeRealtimeTransport

/// Push-based scripted transport (test-only). `connect` records token/model and
/// hands out a *fresh* event stream; tests control interleaving exactly by
/// calling `push(_:)` at the moments they choose. Every client send is
/// recorded. The fresh-stream-per-connect design lets the controller's single
/// silent reconnect (which receives this same instance again from
/// `makeTransport`) re-consume the events cleanly — `AsyncStream` is
/// single-consumer, so reusing one stream across connects would drop events.
final class FakeRealtimeTransport: RealtimeTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var sentEvents: [RealtimeClientEvent] = []
    private var tokens: [String] = []
    private var models: [String] = []
    private var closeCount = 0
    private var stream: AsyncStream<RealtimeServerEvent>
    private var continuation: AsyncStream<RealtimeServerEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeServerEvent.self)
        self.stream = stream
        self.continuation = continuation
    }

    var events: AsyncStream<RealtimeServerEvent> { lock.withLock { stream } }
    var sent: [RealtimeClientEvent] { lock.withLock { sentEvents } }
    var connectedToken: String? { lock.withLock { tokens.last } }
    var connectedModel: String? { lock.withLock { models.last } }
    var connectCount: Int { lock.withLock { tokens.count } }
    var isClosed: Bool { lock.withLock { closeCount > 0 } }
    /// How many times close() was called. A reconnect must close the dying
    /// transport before standing up its replacement — skipping that leaked a
    /// whole WebRTC stack, mic claim included, on every hiccup.
    var closes: Int { lock.withLock { closeCount } }

    /// Sends minus mic audio. The sim test host may or may not deliver mic
    /// chunks — tests must never assert on their presence or absence.
    var sentNonAudio: [RealtimeClientEvent] {
        sent.filter { if case .appendAudio = $0 { return false }; return true }
    }

    func connect(token: String, model: String) async throws {
        lock.withLock {
            tokens.append(token)
            models.append(model)
            continuation.finish()   // ends any previous consumer's loop
            let (stream, continuation) = AsyncStream.makeStream(of: RealtimeServerEvent.self)
            self.stream = stream
            self.continuation = continuation
        }
    }

    func send(_ event: RealtimeClientEvent) async throws {
        lock.withLock { sentEvents.append(event) }
    }

    /// Deliver a scripted server event to whoever is consuming `events`.
    func push(_ event: RealtimeServerEvent) {
        lock.withLock { continuation }.yield(event)
    }

    func close() async {
        lock.withLock {
            closeCount += 1
            continuation.finish()
        }
    }
}

// MARK: - Tests

/// Stands in for the on-device recogniser, which needs Speech authorization and
/// a real mic. Lets a test say "Chef" at an exact moment.
@MainActor
final class FakeWakeWordListener: WakeWordListening {
    var onWake: (() -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onListeningChange: ((Bool) -> Void)?
    var isAvailable: Bool { true }

    private(set) var isSuppressed = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func requestAuthorization() async -> Bool { true }
    func start() { startCount += 1; onListeningChange?(true) }
    func stop() { stopCount += 1; onListeningChange?(false) }
    func restart() {}
    func setSuppressed(_ suppressed: Bool) { isSuppressed = suppressed }
    nonisolated func append(_ buffer: AVAudioPCMBuffer) {}

    /// The cook says the word.
    func say() { onWake?() }

    /// The recognizer's running transcript, which is what the listening ceiling
    /// reads when it decides whether anything was actually asked of her.
    func hear(_ text: String) { onPartialTranscript?(text) }
}

@MainActor
final class PollySessionControllerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Full graph: the controller fetches PantryItem/UserPrefs/CookSession,
        // hands the registry the ModelContext, and end() writes PollyCookLog +
        // PollyMemory — so every connected model rides along.
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
            PantryItem.self, GroceryItem.self, KitchenTool.self,
            CookSession.self, UserPrefs.self,
            PollyMemory.self, PollyCookLog.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    // MARK: Fixtures

    private static let fixtureToken = PollySessionToken(
        value: "ek_test", expiresAt: 1_751_500_000, model: "gpt-realtime-2", voice: "marin")

    private static func planStep(_ id: String, _ index: Int, _ title: String) -> CookPlan.PlanStep {
        CookPlan.PlanStep(
            id: id, index: index, title: title, instruction: "\(title) until done.",
            kind: .active, estimatedSeconds: 120, timerSeconds: nil,
            dependsOn: [], visualCheck: nil, recovery: nil, ingredientNames: [])
    }

    private static let fixturePlan = CookPlan(
        title: "Creamy Lemon Chicken", servings: 2, mise: [], equipment: [],
        steps: [
            planStep("s1", 0, "Sear the chicken"),
            planStep("s2", 1, "Make the sauce"),
            planStep("s3", 2, "Finish and rest"),
        ],
        isFallback: false)

    private static let fixtureExtraction = PollyMemoryExtractor.Extraction(
        facts: [PollyMemoryExtractor.Fact(
            kind: "equipment", text: "Owns a cast iron skillet", confidence: 0.8)],
        summary: "great cook")

    private func insertRecipe() -> Recipe {
        let recipe = Recipe(title: "Creamy Lemon Chicken", servings: 2)
        context.insert(recipe)
        recipe.ingredients = [RecipeIngredient(name: "chicken thighs", sortIndex: 0)]
        recipe.steps = [RecipeStep(index: 0, text: "Sear the chicken, make the sauce, rest.")]
        return recipe
    }

    private func makeController(
        recipe: Recipe,
        transport: FakeRealtimeTransport,
        mintToken: (() async throws -> PollySessionToken)? = nil,
        now: (() -> Date)? = nil,
        wakeWord: WakeWordListening? = nil
    ) -> PollySessionController {
        let mint: () async throws -> PollySessionToken = mintToken ?? { Self.fixtureToken }
        let deps = PollySessionController.Dependencies(
            // The chef's voice now rides the mint, since Realtime pins `voice` at
            // session creation. Tests don't assert on it, so swallow the argument.
            mintToken: { _, _ in try await mint() },
            makeTransport: { transport },
            compilePlan: { _, _ in Self.fixturePlan },
            extractMemories: { _, _ in Self.fixtureExtraction },
            reportSessionUsage: { _, _, _ in },
            now: now ?? { Date(timeIntervalSince1970: 1_751_400_000) }
        )
        return PollySessionController(
            recipe: recipe, scale: 1.0, deps: deps, wakeWord: wakeWord)
    }

    /// Deterministically waits for the controller's main-actor event task to
    /// process pushed events: polls `condition` (bounded, max 2 s), then
    /// asserts it. Sleeping yields the main actor so the event loop can run.
    private func waitUntil(
        _ condition: () -> Bool,
        _ message: String = "condition not met in time",
        timeout: TimeInterval = 2,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)   // 10 ms
        }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    // MARK: (1) start -> session.update + greeting + .live

    func testStartSendsSessionUpdateThenGreetingAndGoesLive() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)

        await controller.start(context: context, requireMic: false)

        XCTAssertEqual(controller.phase, .live)
        XCTAssertTrue(controller.isThinking, "the greeting response is in flight")
        XCTAssertEqual(controller.missingIngredients, ["chicken thighs"],
                       "empty pantry -> the one ingredient is missing")
        XCTAssertEqual(transport.connectedToken, "ek_test")
        XCTAssertEqual(transport.connectedModel, "gpt-realtime-2")
        XCTAssertEqual(controller.plan?.steps.count, 3)
        XCTAssertNotNil(controller.registry)

        let sent = transport.sentNonAudio
        XCTAssertGreaterThanOrEqual(sent.count, 2)
        guard case .sessionUpdate(let config) = sent[0] else {
            return XCTFail("first send must be session.update, got \(sent[0])")
        }
        XCTAssertTrue(config.instructions.contains("Creamy Lemon Chicken"),
                      "instructions must embed the recipe")
        XCTAssertEqual(config.tools.count, 19, "all locked tools advertised")
        XCTAssertEqual(config.voice, "marin")
        XCTAssertEqual(config.model, "gpt-realtime-2")
        XCTAssertTrue(config.transcribeInput)
        XCTAssertEqual(sent[1], .responseCreateSpeechOnly,
                       "Polly greets first without tools (avoids re-speaking the opening)")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (2) tool round-trip

    func testFunctionCallRoundTripSendsOutputThenResponseCreate() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        XCTAssertEqual(controller.phase, .live)
        let countBefore = transport.sentNonAudio.count

        transport.push(.responseDone(status: "completed", calls: [
            RealtimeFunctionCall(name: "get_current_step", callId: "call_1", argumentsJSON: "{}"),
        ]))
        await waitUntil({ transport.sentNonAudio.count >= countBefore + 2 },
                        "expected function output + response.create")

        let newSends = Array(transport.sentNonAudio.dropFirst(countBefore))
        guard case .createFunctionOutput(let callId, let output) = newSends[0] else {
            return XCTFail("expected createFunctionOutput first, got \(newSends[0])")
        }
        XCTAssertEqual(callId, "call_1")
        XCTAssertTrue(output.contains("Sear the chicken"), "tool result carries plan step 1")
        XCTAssertEqual(newSends[1], .responseCreate)

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (3) barge-in (v2: server-side truncation over WebRTC)

    /// v2 contract: on barge-in the CLIENT sends nothing — the server clears
    /// its own output buffer and truncates the item (device-proven; the v1
    /// client-side truncate math died with the audio engine).
    ///
    /// Barge-in is two-stage: raw VAD does **not** cancel Polly. `speechStarted`
    /// marks a candidate and opens listening while she keeps talking; the
    /// conversational gate decides once there is a transcript. Asserting that
    /// `isPollySpeaking` went false here would be re-encoding the one-stage
    /// contract that cut her off on echo and background noise.
    func testBargeInMarksCandidateAndSendsNoClientTruncate() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        transport.push(.outputAudioStarted)
        await waitUntil({ controller.isPollySpeaking }, "audio start marks Polly speaking")

        transport.push(.speechStarted)
        await waitUntil({ controller.isListening }, "speech_started marks listening")

        XCTAssertTrue(controller.isPollySpeaking,
                      "raw VAD must not cancel Polly — the gate decides after the transcript")
        let truncates = transport.sent.filter {
            if case .truncateItem = $0 { return true }
            return false
        }
        XCTAssertTrue(truncates.isEmpty, "v2 must not send client-side truncates")

        transport.push(.outputAudioStopped)
        await waitUntil({ !controller.isPollySpeaking }, "audio stop clears speaking flag")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (4) end_session tool + end() persistence

    func testEndSessionToolThenEndWritesCookLogAndMemories() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        XCTAssertFalse(controller.wantsEnd)

        transport.push(.responseDone(status: "completed", calls: [
            RealtimeFunctionCall(name: "end_session", callId: "call_9", argumentsJSON: "{}"),
        ]))
        await waitUntil({ controller.wantsEnd }, "end_session tool must set wantsEnd")

        await controller.end(context: context, endedEarly: false)

        XCTAssertEqual(controller.phase, .ended)
        XCTAssertTrue(transport.isClosed)

        let logs = try context.fetch(FetchDescriptor<PollyCookLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].stepsTotal, 3)
        XCTAssertEqual(logs[0].summary, "great cook")
        XCTAssertFalse(logs[0].endedEarly)
        XCTAssertNotNil(logs[0].endedAt)
        XCTAssertEqual(logs[0].recipe?.title, "Creamy Lemon Chicken")

        let memories = try context.fetch(FetchDescriptor<PollyMemory>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].kind, .equipment)
        XCTAssertEqual(memories[0].text, "Owns a cast iron skillet")

        // Idempotent: a second end() must not write a second log.
        await controller.end(context: context, endedEarly: false)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PollyCookLog>()).count, 1)
    }

    // MARK: (5) mint failure

    func testMintTokenFailureFailsThePhase() async throws {
        struct MintBoom: LocalizedError {
            var errorDescription: String? { "token mint exploded" }
        }
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport,
                                        mintToken: { throw MintBoom() })

        await controller.start(context: context, requireMic: false)

        guard case .failed(let message) = controller.phase else {
            return XCTFail("expected .failed, got \(controller.phase)")
        }
        XCTAssertTrue(message.contains("token mint exploded"))
        XCTAssertEqual(transport.connectCount, 0, "must not connect without a token")
        XCTAssertTrue(transport.sent.isEmpty)
    }

    // MARK: (6) one silent reconnect

    func testTransportErrorWhileLiveReconnectsOnce() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        XCTAssertEqual(transport.connectCount, 1)

        transport.push(.error(code: "transport", message: "socket dropped"))
        await waitUntil({ transport.connectCount == 2 }, "exactly one silent reconnect")
        await waitUntil({ controller.phase == .live }, "phase returns to .live")

        // The dying transport must be released, not merely dropped on the floor.
        // Before this, self.transport was overwritten while the old peer
        // connection, its audio device module and its claim on the microphone
        // stayed alive, so every reconnect stacked another one on top.
        XCTAssertEqual(transport.closes, 1, "the dead transport is closed before the new one connects")

        XCTAssertTrue(controller.captionText.localizedCaseInsensitiveContains("hiccup"))
        let sessionUpdates = transport.sent.filter {
            if case .sessionUpdate = $0 { return true }
            return false
        }
        XCTAssertEqual(sessionUpdates.count, 2, "session.update re-sent on the new socket")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (7) protocol errors don't kill a live session

    func testProtocolErrorWhileLiveDoesNotKillTheSession() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        transport.push(.error(code: "invalid_request_error", message: "item not found"))
        // The stream is ordered: once this later event lands, the error was processed.
        transport.push(.speechStarted)
        await waitUntil({ controller.isListening }, "follow-up event processed")

        XCTAssertEqual(controller.phase, .live, "a protocol error must not fail a live session")
        XCTAssertEqual(transport.connectCount, 1, "and must not trigger a reconnect")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (8) wrap-up warning + honest hard stop

    func testTickSendsWrapUpWarningOnceThenHardStops() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        var nowValue = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(recipe: recipe, transport: transport, now: { nowValue })
        await controller.start(context: context, requireMic: false)
        let before = transport.sentNonAudio.count

        nowValue = nowValue.addingTimeInterval(Double(PollyConfig.wrapUpWarningMinutes * 60) + 1)
        await controller.tick(context: context)
        let warning = Array(transport.sentNonAudio.dropFirst(before))
        XCTAssertEqual(warning.count, 2, "wrap-up note + response.create")
        guard case .createUserText(let text) = warning[0] else {
            return XCTFail("expected the wrap-up system note, got \(warning[0])")
        }
        XCTAssertTrue(text.localizedCaseInsensitiveContains("wrapping up"))
        XCTAssertEqual(warning[1], .responseCreate)

        await controller.tick(context: context)
        XCTAssertEqual(transport.sentNonAudio.count, before + 2, "the warning is sent exactly once")

        nowValue = nowValue.addingTimeInterval(
            Double((PollyConfig.maxSessionMinutes - PollyConfig.wrapUpWarningMinutes) * 60) + 1)
        await controller.tick(context: context)
        XCTAssertEqual(controller.phase, .ended, "the session cap ends the session")
        let logs = try context.fetch(FetchDescriptor<PollyCookLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].endedEarly, "no steps were completed — honest endedEarly")
    }

    // MARK: (9) tool batches answer with ONE response, not one per call

    func testMultipleToolCallsProduceOutputsThenSingleResponseCreate() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        let countBefore = transport.sentNonAudio.count

        transport.push(.responseDone(status: "completed", calls: [
            RealtimeFunctionCall(name: "get_current_step", callId: "call_a", argumentsJSON: "{}"),
            RealtimeFunctionCall(name: "check_pantry", callId: "call_b", argumentsJSON: "{}"),
        ]))
        await waitUntil({ transport.sentNonAudio.count >= countBefore + 3 },
                        "expected two function outputs + one response.create")

        let newSends = Array(transport.sentNonAudio.dropFirst(countBefore))
        XCTAssertEqual(newSends.count, 3, "exactly 2 outputs + 1 response.create — never one create per call")
        guard case .createFunctionOutput(let id1, _) = newSends[0],
              case .createFunctionOutput(let id2, _) = newSends[1] else {
            return XCTFail("first two sends must be the function outputs, got \(newSends)")
        }
        XCTAssertEqual(id1, "call_a")
        XCTAssertEqual(id2, "call_b")
        XCTAssertEqual(newSends[2], .responseCreate)

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (10) cancelled responses never trigger tool execution

    func testCancelledResponseCallsAreIgnored() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        let countBefore = transport.sentNonAudio.count

        transport.push(.responseDone(status: "cancelled", calls: [
            RealtimeFunctionCall(name: "get_current_step", callId: "call_x", argumentsJSON: "{}"),
        ]))
        // Ordered stream: once this later event lands, the cancelled one was processed.
        transport.push(.speechStarted)
        await waitUntil({ controller.isListening }, "follow-up event processed")

        XCTAssertEqual(transport.sentNonAudio.count, countBefore,
                       "a cancelled response's partial calls must not be executed or answered")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (11) wake-word gate — starts dormant + muted

    func testStartLeavesSessionDormantAndMuted() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        XCTAssertEqual(controller.phase, .live)
        XCTAssertEqual(controller.listeningMode, .dormant, "the session gates the mic until \"Hey Chef\"")
        XCTAssertTrue(controller.audio.isMuted, "dormant means the Realtime input is muted")
        // This used to assert wakeWordAvailable == false, "no Speech auth in the
        // test host". It passed for the wrong reason: SFSpeechRecognizer reports
        // unavailable for a moment after init, and the old code read that once
        // and believed it for the whole session. Now that availability is
        // retried the flag settles on whatever the host actually supports, which
        // is environment, not contract. What matters here is that the session
        // starts gated either way — a cook with no wake word gets tap-to-talk,
        // not an open microphone.
        XCTAssertEqual(controller.listeningMode, .dormant,
                       "dormant regardless of whether the wake word is available")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (12) wakeUp un-gates the input; returnToDormant re-gates

    func testWakeUpUnmutesAndReturnToDormantRemutes() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        controller.wakeUp()
        XCTAssertEqual(controller.listeningMode, .listening)
        XCTAssertTrue(controller.isEngaged)
        XCTAssertFalse(controller.audio.isMuted, "listening opens the mic to Polly")

        controller.returnToDormant()
        XCTAssertEqual(controller.listeningMode, .dormant)
        XCTAssertFalse(controller.isEngaged)
        XCTAssertTrue(controller.audio.isMuted, "the follow-up window closing re-gates the input")

        // She must wake AGAIN after the window closed — not just the first time.
        controller.wakeUp()
        XCTAssertEqual(controller.listeningMode, .listening, "a second \"Hey Chef\" re-opens the mic")
        XCTAssertFalse(controller.audio.isMuted)

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (12b) gated follow-up commits response.create; ack does not

    func testDirectFollowUpRequestsResponseAndAckDoesNot() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        controller.wakeUp()
        let before = transport.sentNonAudio.count

        transport.push(.inputTranscript(itemId: "u1", text: "Should I flip the chicken?"))
        await waitUntil({
            transport.sentNonAudio.dropFirst(before).contains { $0 == .responseCreate }
        }, "direct follow-up must response.create")

        let afterAsk = transport.sentNonAudio.count
        transport.push(.inputTranscript(itemId: "u2", text: "Okay"))
        // Give the event loop a beat — ack must NOT add response.create.
        try? await Task.sleep(nanoseconds: 80_000_000)
        let newSends = Array(transport.sentNonAudio.dropFirst(afterAsk))
        XCTAssertFalse(newSends.contains { $0 == .responseCreate },
                       "acknowledgment must not trigger a spoken reply")
        XCTAssertTrue(
            newSends.contains {
                if case .deleteItem(let id) = $0 { return id == "u2" }
                return false
            },
            "ack should drop the user item so it doesn't pollute history")

        await controller.end(context: context, endedEarly: true)
    }

    func testExplicitEndReturnsToDormant() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        controller.wakeUp()
        XCTAssertTrue(controller.isEngaged)

        transport.push(.inputTranscript(itemId: "u3", text: "that's all"))
        await waitUntil({ controller.listeningMode == .dormant }, "explicit end closes session")
        XCTAssertTrue(controller.audio.isMuted)

        await controller.end(context: context, endedEarly: true)
    }

    func testAcknowledgmentDoesNotRequestResponse() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        controller.wakeUp()
        let before = transport.sentNonAudio.count

        transport.push(.inputTranscript(itemId: "u4", text: "Okay, thank you."))
        try? await Task.sleep(nanoseconds: 80_000_000)
        let newSends = Array(transport.sentNonAudio.dropFirst(before))
        XCTAssertFalse(newSends.contains { $0 == .responseCreate },
                       "acknowledgment must not trigger a spoken reply")

        await controller.end(context: context, endedEarly: true)
    }

    func testLeaveCookScreenClosesFollowUp() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        controller.wakeUp()
        controller.leaveCookScreen()
        XCTAssertEqual(controller.listeningMode, .dormant)
        XCTAssertTrue(controller.audio.isMuted)

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (13) hard mute silences everything and blocks waking

    func testHardMuteSilencesAndBlocksWake() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        controller.toggleHardMute()
        XCTAssertTrue(controller.isHardMuted)
        XCTAssertTrue(controller.audio.isMuted)
        XCTAssertEqual(controller.listeningMode, .dormant)

        controller.forceListen()   // tap-to-talk must be ignored while hard-muted
        XCTAssertEqual(controller.listeningMode, .dormant, "hard mute blocks tap-to-talk")
        controller.wakeUp()        // voice wake must be ignored too
        XCTAssertEqual(controller.listeningMode, .dormant, "hard mute blocks voice wake")

        controller.toggleHardMute()   // un-mute returns to dormant (armed), not open
        XCTAssertFalse(controller.isHardMuted)
        XCTAssertEqual(controller.listeningMode, .dormant)
        controller.forceListen()
        XCTAssertEqual(controller.listeningMode, .listening, "tap-to-talk works once un-muted")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: an uncertain transcript goes to Polly, not to the bin

    /// Verbatim from a real cook. Polly asked "tell me when they're set", the
    /// cook said exactly that, and the gate scored it `uncertain` and deleted it
    /// — no cook word, no overlap with "Broccolini Quinoa Pilaf". Four seconds
    /// later the watchdog made her apologise for missing something she had
    /// transcribed perfectly. Three turns in a row went that way.
    func testUncertainTranscriptIsAnsweredRatherThanDiscarded() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        controller.wakeUp()

        let before = transport.sentNonAudio.count
        transport.push(.inputTranscript(itemId: "item-1", text: "Everything is set like everything is on my table."))
        await waitUntil({ transport.sentNonAudio.count > before }, "the turn is acted on")
        try? await Task.sleep(for: .milliseconds(120))

        let after = Array(transport.sentNonAudio.dropFirst(before))
        XCTAssertTrue(after.contains { $0 == .responseCreate },
                      "an uncertain turn must reach Polly, who can decline with wait_for_user")
        XCTAssertFalse(after.contains { if case .deleteItem = $0 { return true }; return false },
                       "and must not be deleted unheard")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: wait_for_user is a silence, not a failure

    /// Every other tool round-trip ends with a response.create so Polly speaks
    /// the result. wait_for_user must not: she calls it precisely to say "that
    /// audio was not for me", and answering anyway would put her back to
    /// replying to the extractor fan. It must also not count toward the reject
    /// tally that ends the session, because deciding correctly is not a failure.
    func testWaitForUserStaysSilentAndDoesNotCountAsAReject() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        let before = transport.sentNonAudio.count
        transport.push(.responseDone(
            status: "completed",
            calls: [RealtimeFunctionCall(name: "wait_for_user", callId: "c1", argumentsJSON: "{}")],
            usage: nil))
        await waitUntil({ transport.sentNonAudio.count > before }, "tool output sent")
        // Let any (incorrect) follow-up response.create land before asserting.
        try? await Task.sleep(for: .milliseconds(120))

        let after = transport.sentNonAudio.dropFirst(before)
        XCTAssertTrue(after.contains { if case .createFunctionOutput = $0 { return true }; return false },
                      "the tool result is still reported")
        XCTAssertFalse(after.contains { $0 == .responseCreate },
                       "wait_for_user must not be followed by a spoken response")
        XCTAssertFalse(controller.isThinking, "and must not leave her stuck thinking")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: an unmuted technique clip must never strand the mic

    /// Advancing a step while an unmuted clip plays tears the player down, and
    /// teardown reports `.idle`. That case used to be an unconditional no-op, so
    /// the mic hold taken for the clip's audio was never released and the cook
    /// spent the rest of the session talking into a dead microphone with the UI
    /// still showing Polly as listening.
    func testUnmutedClipDoesNotStrandTheMicWhenThePlayerIsTornDown() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        controller.updateMediaState(.playing(segmentID: "seg-1", muted: false))
        XCTAssertTrue(controller.micHeldForClipAudio, "clip audio takes the mic")

        controller.updateMediaState(.idle)          // what player teardown emits
        XCTAssertFalse(controller.micHeldForClipAudio, "teardown gives the mic back")

        await controller.end(context: context, endedEarly: true)
    }

    /// The ordinary paths must release it too, and a muted clip must never take
    /// it in the first place.
    func testClipMicHoldIsReleasedOnFinishAndNeverTakenWhenMuted() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        controller.updateMediaState(.playing(segmentID: "seg-1", muted: true))
        XCTAssertFalse(controller.micHeldForClipAudio, "a silent clip needs no mic hold")

        controller.updateMediaState(.playing(segmentID: "seg-1", muted: false))
        XCTAssertTrue(controller.micHeldForClipAudio)

        controller.updateMediaState(.finished(segmentID: "seg-1"))
        XCTAssertFalse(controller.micHeldForClipAudio, "finishing gives the mic back")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: Saying "Chef" over her

    /// The bug: she could not be interrupted by voice. `isPollySpeaking` muted
    /// the wake listener, so "Chef" spoken over her never reached `onWake`, and
    /// the cancel path in `wakeUp()` never ran. The only way out was shouting
    /// past the transport's RMS gate or waiting her out.
    func testSayingChefWhileSheIsSpeakingCutsHerOff() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        let controller = makeController(recipe: recipe, transport: transport, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        transport.push(.outputAudioStarted)
        await waitUntil({ controller.isPollySpeaking }, "she is speaking")

        wake.say()

        await waitUntil({
            transport.sent.contains { if case .responseCancel = $0 { return true }; return false }
        }, "saying Chef over her must cancel her response")
        XCTAssertTrue(
            transport.sent.contains { if case .outputAudioBufferClear = $0 { return true }; return false },
            "the audio already buffered must be cleared, or she keeps talking after the cancel")
        XCTAssertEqual(controller.listeningMode, .listening,
                       "having just silenced her, the mic must be open for what comes next")

        await controller.end(context: context, endedEarly: true)
    }

    /// The listener is told she is speaking so her own voice is not captioned as
    /// the cook's words. That must not go back to swallowing the wake.
    func testSuppressionStillLetsTheCookInterrupt() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        let controller = makeController(recipe: recipe, transport: transport, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        transport.push(.outputAudioStarted)
        await waitUntil({ controller.isPollySpeaking }, "she is speaking")
        let suppressed = wake.isSuppressed
        XCTAssertTrue(suppressed, "captions from her own voice are still suppressed")

        wake.say()
        await waitUntil({
            transport.sent.contains { if case .responseCancel = $0 { return true }; return false }
        }, "a suppressed listener must still be able to interrupt her")

        await controller.end(context: context, endedEarly: true)
    }

    /// Her prompt forbids the word and the wake feed is post-AEC, but if she ever
    /// does say "chef" and it leaks back through the speaker, she must not
    /// interrupt herself mid-sentence.
    func testSheDoesNotWakeHerselfOnHerOwnVoice() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        let controller = makeController(recipe: recipe, transport: transport, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        transport.push(.outputAudioStarted)
        transport.push(.outputTranscriptDelta(itemId: "a1", delta: "Nice work, chef."))
        await waitUntil({ controller.pollyCaption.contains("chef") }, "her caption carries the word")

        wake.say()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(
            transport.sent.contains { if case .responseCancel = $0 { return true }; return false },
            "her own voice saying the word must never cancel her")

        await controller.end(context: context, endedEarly: true)
    }

    /// The cook can still interrupt on a later utterance in the same turn: the
    /// veto is scoped to what she is saying, not to the whole session.
    func testInterruptWorksOnceHerCaptionMovesOn() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        let controller = makeController(recipe: recipe, transport: transport, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        transport.push(.outputAudioStarted)
        transport.push(.outputTranscriptDelta(itemId: "a1", delta: "Nice work, chef."))
        await waitUntil({ controller.pollyCaption.contains("chef") }, "her caption carries the word")
        transport.push(.outputTranscriptDelta(itemId: "a2", delta: "Now add the garlic."))
        await waitUntil({ !controller.pollyCaption.contains("chef") }, "her caption moved on")

        wake.say()
        await waitUntil({
            transport.sent.contains { if case .responseCancel = $0 { return true }; return false }
        }, "the cook must be able to cut in once she is no longer saying the word")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: Listening discipline (from the 2026-08 test session)

    /// She stops talking, she stops listening. The mic used to stay open for 7
    /// seconds after every answer, which in a real kitchen mostly caught the
    /// cook talking to somebody else in the room.
    func testSheGoesDormantAsSoonAsSheFinishesSpeaking() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        let controller = makeController(recipe: recipe, transport: transport, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        wake.say()
        await waitUntil({ controller.listeningMode == .listening }, "wake opens the mic")

        transport.push(.outputAudioStarted)
        await waitUntil({ controller.isPollySpeaking }, "she is speaking")
        transport.push(.responseDone(status: "completed", calls: []))
        transport.push(.outputAudioStopped)

        await waitUntil({ controller.listeningMode == .dormant },
                        "the mic must close with her mouth, not linger")
        await controller.end(context: context, endedEarly: true)
    }

    /// And the way back in is the wake word, still.
    func testChefStillWakesAfterSheHasFinished() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        let controller = makeController(recipe: recipe, transport: transport, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        transport.push(.outputAudioStarted)
        await waitUntil({ controller.isPollySpeaking }, "she is speaking")
        transport.push(.responseDone(status: "completed", calls: []))
        transport.push(.outputAudioStopped)
        await waitUntil({ controller.listeningMode == .dormant }, "dormant after speaking")

        wake.say()
        await waitUntil({ controller.listeningMode == .listening },
                        "\"Chef\" must still open the mic from dormant")
        await controller.end(context: context, endedEarly: true)
    }

    /// The cook asks a question and then turns to talk to family. Every sentence
    /// they say used to push the deadline out, so the mic stayed open for the
    /// length of the conversation.
    func testListeningIsCappedRegardlessOfHowMuchTheRoomTalks() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        var clock = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(
            recipe: recipe, transport: transport, now: { clock }, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        wake.say()
        await waitUntil({ controller.listeningMode == .listening }, "wake opens the mic")

        // Somebody keeps talking, well past the ceiling.
        clock = clock.addingTimeInterval(PollyConfig.maxListeningSeconds + 5)
        transport.push(.speechStarted)

        await waitUntil({ controller.listeningMode == .dormant },
                        "the ceiling must close the turn even while speech continues",
                        timeout: 5)
        await controller.end(context: context, endedEarly: true)
    }

    /// The other half of the ceiling. "How long should the butter brown" then two
    /// minutes of talking to a family member: the question WAS asked, so closing
    /// silently would be the app ignoring it. It answers what it actually heard.
    func testCeilingStillAnswersAQuestionThatWasGenuinelyAsked() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        var clock = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(
            recipe: recipe, transport: transport, now: { clock }, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        wake.say()
        await waitUntil({ controller.listeningMode == .listening }, "wake opens the mic")

        let before = transport.sent.filter { if case .responseCreate = $0 { return true }; return false }.count
        wake.hear("how long should the butter brown?")
        await waitUntil({ !controller.liveTranscript.isEmpty }, "the question landed")

        clock = clock.addingTimeInterval(PollyConfig.maxListeningSeconds + 5)
        transport.push(.speechStarted)

        await waitUntil({
            transport.sent.filter { if case .responseCreate = $0 { return true }; return false }.count > before
        }, "she must answer the question she actually heard", timeout: 5)
        await controller.end(context: context, endedEarly: true)
    }

    /// Skip summary, then the session starts, and the trailer keeps reading the
    /// recipe over the top of Chef. The rule is the session silences it, so this
    /// starts one that is genuinely mid-sentence and checks `start` shuts it up.
    func testStartingASessionSilencesALiveBriefing() async throws {
        var speech = PollySpeechClient()
        speech.baseURL = "https://example.invalid"
        speech.clientKey = "test"
        speech.transport = { _ in
            try await Task.sleep(nanoseconds: 30_000_000_000)
            throw CancellationError()
        }
        let narrator = BriefingNarrator(speech: speech)
        narrator.narrate(CookBriefing(
            dishTitle: "Gnocchi with Brown Butter and Sage",
            timeLabel: "15 min",
            servings: 4,
            beats: [.init(id: "b1", title: "Water on", detail: "Salted water",
                          kind: .active, spokenLine: "Water goes on first.")],
            miseLine: nil, gearLine: nil,
            introLine: "Quick look at what you're making.",
            outroLine: "That's the whole cook."))
        XCTAssertTrue(narrator.isSpeaking, "the trailer is mid-sentence")

        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        XCTAssertFalse(narrator.isSpeaking,
                       "the trailer must not still be reading the recipe over her")
        await controller.end(context: context, endedEarly: true)
    }

    /// The late-transcript re-open was a second way in that needed no "Chef".
    /// Any sentence the room produced while she was dormant re-engaged her and
    /// got an answer, which is the whole thing this rule exists to stop.
    func testRoomTalkWithNoRecentWakeDoesNotOpenATurn() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        let controller = makeController(recipe: recipe, transport: transport, wakeWord: wake)
        await controller.start(context: context, requireMic: false)
        await waitUntil({ controller.listeningMode == .dormant }, "she starts dormant")

        let before = transport.sent.filter { if case .responseCreate = $0 { return true }; return false }.count
        transport.push(.speechStarted)
        transport.push(.inputTranscript(itemId: "i1", text: "Can you pass me the salt?"))
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertEqual(controller.listeningMode, .dormant,
                       "nobody said Chef, so nothing should have opened")
        let after = transport.sent.filter { if case .responseCreate = $0 { return true }; return false }.count
        XCTAssertEqual(after, before,
                       "she must not answer a question that was asked of somebody else")
        await controller.end(context: context, endedEarly: true)
    }

    /// Talking over her must NOT cut her off. Only "Chef" does that.
    func testSpeechDuringHerTurnDoesNotInterruptHer() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        let controller = makeController(recipe: recipe, transport: transport, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        transport.push(.outputAudioStarted)
        await waitUntil({ controller.isPollySpeaking }, "she is speaking")

        transport.push(.speechStarted)
        transport.push(.inputTranscript(itemId: "i1", text: "Should I flip it now?"))
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertFalse(
            transport.sent.contains { if case .responseCancel = $0 { return true }; return false },
            "a confident question from the room must not stop her mid-sentence")
        XCTAssertTrue(controller.isPollySpeaking)
        await controller.end(context: context, endedEarly: true)
    }

    /// The escape hatch closes the turn without taking the wake word with it,
    /// which is what separates it from the mic button.
    func testStopListeningClosesTheTurnButLeavesTheWakeWordWorking() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let wake = FakeWakeWordListener()
        let controller = makeController(recipe: recipe, transport: transport, wakeWord: wake)
        await controller.start(context: context, requireMic: false)

        wake.say()
        await waitUntil({ controller.listeningMode == .listening }, "wake opens the mic")

        controller.stopListening()
        XCTAssertEqual(controller.listeningMode, .dormant)
        XCTAssertFalse(controller.isHardMuted, "this is not the mic button")

        wake.say()
        await waitUntil({ controller.listeningMode == .listening },
                        "\"Chef\" must still work after stopping listening")
        await controller.end(context: context, endedEarly: true)
    }
}
