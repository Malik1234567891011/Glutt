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
        now: (() -> Date)? = nil
    ) -> PollySessionController {
        let mint: () async throws -> PollySessionToken = mintToken ?? { Self.fixtureToken }
        let deps = PollySessionController.Dependencies(
            mintToken: mint,
            makeTransport: { transport },
            compilePlan: { _, _ in Self.fixturePlan },
            extractMemories: { _, _ in Self.fixtureExtraction },
            reportSessionUsage: { _, _, _ in },
            now: now ?? { Date(timeIntervalSince1970: 1_751_400_000) }
        )
        return PollySessionController(recipe: recipe, scale: 1.0, deps: deps)
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
        XCTAssertEqual(config.tools.count, 15, "all locked tools advertised")
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
        XCTAssertEqual(controller.listeningMode, .dormant, "the session gates the mic until \"Polly\"")
        XCTAssertTrue(controller.audio.isMuted, "dormant means the Realtime input is muted")
        XCTAssertFalse(controller.wakeWordAvailable, "no Speech auth in the test host")

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
        XCTAssertEqual(controller.listeningMode, .listening, "a second \"Polly\" re-opens the mic")
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
}
