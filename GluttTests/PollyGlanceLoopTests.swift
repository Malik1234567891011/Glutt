import XCTest
import SwiftData
@testable import Glutt

/// The unprompted look, wired into the session clock.
///
/// `ChefGlanceTests` covers when a look is due. This covers the half that only
/// exists inside a live session: that the clock actually hands her a turn, that
/// the turn carries the step's own words, and that it stays off entirely when
/// the cook is not wearing the glasses.
///
/// It has to be driven rather than observed, because there is no way to put a
/// pair of glasses on a simulator: `-fakeGlasses` fakes the answer to "are they
/// paired", not a camera that delivers frames. `Dependencies.seesContinuously`
/// is the seam.
@MainActor
final class PollyGlanceLoopTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: Schema([
                Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
                PantryItem.self, GroceryItem.self, KitchenTool.self,
                CookSession.self, UserPrefs.self,
                PollyMemory.self, PollyCookLog.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        ChefWatchfulness.selectedID = ChefWatchfulness.watchful.rawValue
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "glutt.polly.watchfulness")
        container = nil
        try super.tearDownWithError()
    }

    /// Two steps: one worth looking at, one that a look could not judge.
    private static let plan = CookPlan(
        title: "Butter Chicken", servings: 4, mise: [], equipment: [],
        steps: [
            CookPlan.PlanStep(
                id: "s1", index: 0, title: "Sear the chicken",
                instruction: "Lay them down with a gap around every one.",
                kind: .checkpoint,
                visualCheck: "Deep brown with black at the edges, still raw in the middle.",
                recovery: "Sitting in its own liquid means the pan is crowded."),
            CookPlan.PlanStep(
                id: "s2", index: 1, title: "Rice on",
                instruction: "Get the rice on now.", kind: .active),
        ],
        isFallback: false)

    private func makeController(
        transport: FakeRealtimeTransport,
        now: @escaping () -> Date,
        sees: Bool
    ) -> PollySessionController {
        let recipe = Recipe(title: "Butter Chicken", servings: 4)
        context.insert(recipe)
        recipe.steps = [RecipeStep(index: 0, text: "Sear the chicken in batches.")]
        var deps = PollySessionController.Dependencies(
            mintToken: { _, _ in
                PollySessionToken(value: "ek_test", expiresAt: 1_751_500_000,
                                  model: "gpt-realtime-2", voice: "marin")
            },
            makeTransport: { transport },
            compilePlan: { _, _ in Self.plan },
            extractMemories: { _, _ in
                PollyMemoryExtractor.Extraction(facts: [], summary: "")
            },
            reportSessionUsage: { _, _, _ in },
            now: now
        )
        deps.seesContinuously = { _ in sees }
        return PollySessionController(recipe: recipe, scale: 1.0, deps: deps)
    }

    /// The greeting response is in flight the moment `start` returns, and an
    /// unprompted look must never land on top of one. Settling it is what a real
    /// session does within a second or two of connecting.
    private func settleGreeting(
        _ controller: PollySessionController,
        _ transport: FakeRealtimeTransport
    ) async {
        transport.push(.responseDone(status: "completed", calls: []))
        let deadline = Date().addingTimeInterval(2)
        while controller.isThinking && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(controller.isThinking, "the greeting never settled")
    }

    /// Every look sends the brief and then asks for a turn, in that order. The
    /// brief has to be a conversation item rather than response instructions:
    /// she looks first, and the follow-up response after the tool result would
    /// not carry instructions attached to this one.
    private func looks(in sent: [RealtimeClientEvent]) -> [String] {
        sent.compactMap {
            guard case .createUserText(let text) = $0, text.contains("Unprompted look") else {
                return nil
            }
            return text
        }
    }

    private func glance(in sent: [RealtimeClientEvent]) -> String? {
        for (index, event) in sent.enumerated() {
            guard case .createUserText(let text) = event,
                  text.contains("Unprompted look") else { continue }
            guard index + 1 < sent.count, sent[index + 1] == .responseCreate else { return nil }
            return text
        }
        return nil
    }

    func testAQuietStepWithGlassesOnGetsAnUnpromptedLook() async throws {
        let transport = FakeRealtimeTransport()
        var clock = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(transport: transport, now: { clock }, sees: true)
        await controller.start(context: context, requireMic: false)
        await settleGreeting(controller, transport)

        // First tick only opens the step's clock; nothing is owed yet.
        await controller.tick(context: context)
        XCTAssertNil(glance(in: transport.sentNonAudio), "she looked before the step had settled")

        clock = clock.addingTimeInterval(ChefWatchfulness.watchful.glanceInterval! + 1)
        await controller.tick(context: context)

        let brief = try XCTUnwrap(glance(in: transport.sentNonAudio),
                                  "the clock never handed her a turn")
        XCTAssertTrue(brief.contains("Sear the chicken"))
        XCTAssertTrue(brief.contains("Deep brown"), "the step's own target, not a generic look")
        XCTAssertTrue(brief.contains("crowded"), "and its own failure")

        await controller.end(context: context, endedEarly: true)
    }

    /// The one that would be worst to get wrong. A phone face down on the
    /// counter cannot support a look nobody asked for, so no amount of quiet may
    /// produce one.
    func testWithoutGlassesSheNeverLooksUnasked() async throws {
        let transport = FakeRealtimeTransport()
        var clock = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(transport: transport, now: { clock }, sees: false)
        await controller.start(context: context, requireMic: false)
        await settleGreeting(controller, transport)

        for _ in 0..<10 {
            clock = clock.addingTimeInterval(60)
            await controller.tick(context: context)
        }
        XCTAssertNil(glance(in: transport.sentNonAudio))

        await controller.end(context: context, endedEarly: true)
    }

    func testHandsOffNeverLooksEvenWithGlassesOn() async throws {
        ChefWatchfulness.selectedID = ChefWatchfulness.handsOff.rawValue
        let transport = FakeRealtimeTransport()
        var clock = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(transport: transport, now: { clock }, sees: true)
        await controller.start(context: context, requireMic: false)
        await settleGreeting(controller, transport)

        for _ in 0..<10 {
            clock = clock.addingTimeInterval(60)
            await controller.tick(context: context)
        }
        XCTAssertNil(glance(in: transport.sentNonAudio))

        await controller.end(context: context, endedEarly: true)
    }

    /// A six minute step must not spend every look the cook gets all cook.
    ///
    /// Each look is settled before the next tick, the way a real one is: she
    /// will not start a second look while the first is still in flight, so
    /// without settling this would stop at one for the wrong reason.
    func testOneStepCannotSpendMoreThanItsBudget() async throws {
        let transport = FakeRealtimeTransport()
        var clock = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(transport: transport, now: { clock }, sees: true)
        await controller.start(context: context, requireMic: false)
        await settleGreeting(controller, transport)

        for _ in 0..<20 {
            clock = clock.addingTimeInterval(60)
            await controller.tick(context: context)
            if controller.isThinking { await settleGreeting(controller, transport) }
        }
        XCTAssertEqual(looks(in: transport.sentNonAudio).count,
                       ChefWatchfulness.watchful.glanceBudgetPerStep,
                       "twenty minutes on one step produced \(looks(in: transport.sentNonAudio).count) looks")

        await controller.end(context: context, endedEarly: true)
    }

    /// Moving on is what buys the next step its own looks. Otherwise the first
    /// long step spends the budget and Chef goes quiet for the rest of the cook.
    func testANewStepGetsItsOwnBudget() async throws {
        let transport = FakeRealtimeTransport()
        var clock = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(transport: transport, now: { clock }, sees: true)
        await controller.start(context: context, requireMic: false)
        await settleGreeting(controller, transport)

        for _ in 0..<10 {
            clock = clock.addingTimeInterval(60)
            await controller.tick(context: context)
            if controller.isThinking { await settleGreeting(controller, transport) }
        }
        let spent = looks(in: transport.sentNonAudio).count
        XCTAssertEqual(spent, ChefWatchfulness.watchful.glanceBudgetPerStep)

        // Back to the same step by way of another. The clock lives on the 1 Hz
        // tick, so the move away has to be seen before the move back, exactly as
        // it would be in a session.
        controller.goToStep(1)
        clock = clock.addingTimeInterval(60)
        await controller.tick(context: context)
        controller.goToStep(0)
        for _ in 0..<10 {
            clock = clock.addingTimeInterval(60)
            await controller.tick(context: context)
            if controller.isThinking { await settleGreeting(controller, transport) }
        }
        XCTAssertEqual(looks(in: transport.sentNonAudio).count, spent * 2,
                       "the step came back around and got nothing")

        await controller.end(context: context, endedEarly: true)
    }

    /// Tools, Prep and "put the rice on" have nothing a look could be right or
    /// wrong about, and the only possible outcome there is noise.
    func testAStepWithNothingToJudgeIsNeverLookedAt() async throws {
        let transport = FakeRealtimeTransport()
        var clock = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(transport: transport, now: { clock }, sees: true)
        await controller.start(context: context, requireMic: false)
        await settleGreeting(controller, transport)
        controller.goToStep(1)   // "Rice on" — no visualCheck

        for _ in 0..<10 {
            clock = clock.addingTimeInterval(60)
            await controller.tick(context: context)
        }
        XCTAssertNil(glance(in: transport.sentNonAudio))

        await controller.end(context: context, endedEarly: true)
    }
}
