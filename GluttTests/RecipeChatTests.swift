import SwiftData
import XCTest
@testable import Glutt

@MainActor
final class RecipeChatTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([
                Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
                UserPrefs.self, PantryItem.self, KitchenTool.self, RecipeChatMessage.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: - Fixtures

    private func makeRecipe() -> Recipe {
        let recipe = Recipe(title: "Prosciutto Pasta", servings: 2, prepMinutes: 5, cookMinutes: 15)
        context.insert(recipe)
        recipe.ingredients = [
            RecipeIngredient(name: "prosciutto", quantity: 120, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "pasta", quantity: 200, unit: "g", sortIndex: 1),
        ]
        recipe.steps = [RecipeStep(index: 0, text: "Render the prosciutto, toss with pasta.")]
        return recipe
    }

    private func makeContext(_ recipe: Recipe, servings: Int = 2) -> RecipeChatService.Context {
        let prefs = UserPrefs.current(in: context)
        prefs.dietaryRules = [.halal]
        prefs.allergies = ["peanut"]
        return RecipeChatService.Context(
            recipe: recipe,
            servings: servings,
            pantryMatch: PantryMatcher.match(recipe: recipe, pantry: []),
            prefs: prefs,
            ownedTools: []
        )
    }

    // MARK: - Thread identity

    /// The whole "your conversation follows you" promise: apply a change, land
    /// on the new version, and the thread is still there.
    func testVersionSharesTheParentsThread() throws {
        let original = makeRecipe()
        let version = Recipe(title: "Prosciutto Pasta", servings: 2)
        context.insert(version)
        version.parentRecipe = original
        version.versionLabel = "No-pork version"

        XCTAssertEqual(
            RecipeChatStore.familyKey(for: version),
            RecipeChatStore.familyKey(for: original)
        )
    }

    func testTwoRecipesDoNotShareAThread() throws {
        let first = makeRecipe()
        let second = makeRecipe()
        second.title = "Something Else"
        XCTAssertNotEqual(
            RecipeChatStore.familyKey(for: first),
            RecipeChatStore.familyKey(for: second)
        )
    }

    // MARK: - Store

    func testAppendsInTheSameTickKeepATotalOrder() throws {
        let family = "family-1"
        RecipeChatStore.append(role: .user, text: "Use what I have", family: family, in: context)
        RecipeChatStore.append(role: .assistant, text: "Here you go", family: family, in: context)

        let stored = RecipeChatStore.messages(family: family, in: context)
        XCTAssertEqual(stored.map(\.text), ["Use what I have", "Here you go"])
        XCTAssertLessThan(stored[0].createdAt, stored[1].createdAt)
    }

    func testHistoryIsCappedOldestFirst() throws {
        let family = "family-2"
        for index in 0..<(RecipeChatStore.historyCap + 5) {
            RecipeChatStore.append(role: .user, text: "turn \(index)", family: family, in: context)
        }
        let stored = RecipeChatStore.messages(family: family, in: context)
        XCTAssertEqual(stored.count, RecipeChatStore.historyCap)
        XCTAssertEqual(stored.first?.text, "turn 5")
        XCTAssertEqual(stored.last?.text, "turn \(RecipeChatStore.historyCap + 4)")
    }

    func testProposalSurvivesTheRoundTripThroughStorage() throws {
        let family = "family-3"
        let proposal = RecipeChatProposal(
            versionLabel: "No-pork version",
            ingredients: ["120 g beef bacon"],
            steps: ["Render it."],
            changes: ["Prosciutto becomes beef bacon"],
            summary: nil,
            servings: 4
        )
        RecipeChatStore.append(role: .assistant, text: "Done", proposal: proposal,
                               family: family, in: context)

        let stored = try XCTUnwrap(RecipeChatStore.messages(family: family, in: context).first)
        let decoded = try XCTUnwrap(stored.proposal)
        XCTAssertEqual(decoded.versionLabel, "No-pork version")
        XCTAssertEqual(decoded.servings, 4)
        XCTAssertFalse(decoded.isPantryPlan)
    }

    // MARK: - Wire shape

    func testHistoryReplaysAsRolesAndTagsTheFeature() async throws {
        let recipe = makeRecipe()
        let family = RecipeChatStore.familyKey(for: recipe)
        RecipeChatStore.append(role: .user, text: "Can I freeze it?", family: family, in: context)
        RecipeChatStore.append(role: .assistant, text: "Yes, up to a month.", family: family, in: context)
        let history = RecipeChatStore.messages(family: family, in: context)

        let fake = FakeLLMTransport(replyJSON: #"{"reply": "Sure.", "proposal": null}"#)
        _ = try await RecipeChatService.reply(
            to: "And reheating?",
            context: makeContext(recipe),
            history: history,
            client: fake.client()
        )

        let request = try XCTUnwrap(fake.lastRequest)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-glutt-feature"),
            RecipeChatService.usageFeature
        )
        let body = try JSONSerialization.jsonObject(
            with: XCTUnwrap(request.httpBody)) as! [String: Any]
        let messages = body["messages"] as! [[String: Any]]
        XCTAssertEqual(messages.map { $0["role"] as? String },
                       ["system", "user", "assistant", "user"])
        XCTAssertEqual(messages.last?["content"] as? String, "And reheating?")
        XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_object")
    }

    func testOnlyTheTailOfALongThreadIsResent() async throws {
        let recipe = makeRecipe()
        let family = RecipeChatStore.familyKey(for: recipe)
        for index in 0..<20 {
            RecipeChatStore.append(role: index.isMultiple(of: 2) ? .user : .assistant,
                                   text: "turn \(index)", family: family, in: context)
        }
        let history = RecipeChatStore.messages(family: family, in: context)

        let fake = FakeLLMTransport(replyJSON: #"{"reply": "Sure.", "proposal": null}"#)
        _ = try await RecipeChatService.reply(
            to: "one more",
            context: makeContext(recipe),
            history: history,
            client: fake.client()
        )

        let body = try JSONSerialization.jsonObject(
            with: XCTUnwrap(fake.lastRequest?.httpBody)) as! [String: Any]
        let messages = body["messages"] as! [[String: Any]]
        // system + the replayed tail + the new question.
        XCTAssertEqual(messages.count, RecipeChatStore.contextTurns + 2)
    }

    // MARK: - Prompt

    func testPromptCarriesRulesAllergiesAndMissingIngredients() throws {
        let recipe = makeRecipe()
        let prompt = RecipeChatService.systemPrompt(makeContext(recipe))

        XCTAssertTrue(prompt.contains("halal"))
        XCTAssertTrue(prompt.contains("peanut"))
        XCTAssertTrue(prompt.contains("prosciutto"))
        XCTAssertTrue(prompt.contains("Render the prosciutto"))
        // Amounts must be written for the servings the screen is showing.
        XCTAssertTrue(prompt.contains("for 2 servings"))
    }

    func testPromptScalesAmountsToTheDisplayedServings() throws {
        let recipe = makeRecipe()
        let prompt = RecipeChatService.systemPrompt(makeContext(recipe, servings: 4))
        XCTAssertTrue(prompt.contains("for 4 servings"))
        XCTAssertTrue(prompt.contains("240"), "120 g of prosciutto should double for 4 servings")
    }

    // MARK: - Parsing

    func testAnswerWithoutAProposalParses() async throws {
        let recipe = makeRecipe()
        let fake = FakeLLMTransport(
            replyJSON: #"{"reply": "About 200C for 20 minutes.", "proposal": null}"#)
        let envelope = try await RecipeChatService.reply(
            to: "What temperature?", context: makeContext(recipe), history: [],
            client: fake.client())

        XCTAssertEqual(envelope.reply, "About 200C for 20 minutes.")
        XCTAssertNil(envelope.proposal)
    }

    /// A dropped key must not take the whole turn down with it: the cook still
    /// gets their answer.
    func testProposalMissingAKeyStillDecodes() async throws {
        let recipe = makeRecipe()
        let json = """
        {"reply": "Here you go.",
         "proposal": {"versionLabel": "No-pork version",
                      "ingredients": ["120 g beef bacon", "200 g pasta"],
                      "steps": ["Render the beef bacon."]}}
        """
        let fake = FakeLLMTransport(replyJSON: json)
        let envelope = try await RecipeChatService.reply(
            to: "no pork please", context: makeContext(recipe), history: [],
            client: fake.client())

        let proposal = try XCTUnwrap(envelope.proposal)
        XCTAssertEqual(proposal.changes, [])
        XCTAssertNil(proposal.servings)
    }

    /// Half a rewrite is worse than none, but the answer is still worth showing.
    func testUnusableProposalIsDroppedAndTheReplyKept() async throws {
        let recipe = makeRecipe()
        let json = """
        {"reply": "Swap it for beef bacon.",
         "proposal": {"versionLabel": "No-pork version", "ingredients": [], "steps": [],
                      "changes": ["Prosciutto becomes beef bacon"]}}
        """
        let fake = FakeLLMTransport(replyJSON: json)
        let envelope = try await RecipeChatService.reply(
            to: "no pork please", context: makeContext(recipe), history: [],
            client: fake.client())

        XCTAssertEqual(envelope.reply, "Swap it for beef bacon.")
        XCTAssertNil(envelope.proposal)
    }

    func testEmptyReplyThrows() async throws {
        let recipe = makeRecipe()
        let fake = FakeLLMTransport(replyJSON: #"{"reply": "   ", "proposal": null}"#)
        do {
            _ = try await RecipeChatService.reply(
                to: "hello", context: makeContext(recipe), history: [], client: fake.client())
            XCTFail("Expected a bad-response error")
        } catch {
            // Expected.
        }
    }

    // MARK: - Apply

    private func rewriteProposal() -> RecipeChatProposal {
        RecipeChatProposal(
            versionLabel: "No-pork version",
            ingredients: ["120 g beef bacon", "200 g pasta"],
            steps: ["Render the beef bacon, toss with pasta."],
            changes: ["Prosciutto becomes beef bacon"],
            summary: "The same dish without pork.",
            servings: nil
        )
    }

    private func apply(
        _ proposal: RecipeChatProposal,
        on message: RecipeChatMessage? = nil,
        recipe: Recipe,
        pantry: [PantryItem] = []
    ) -> RecipeChatApply.Outcome {
        RecipeChatApply.run(
            proposal,
            on: message,
            recipe: recipe,
            servings: 2,
            pantry: pantry,
            prefs: UserPrefs.current(in: context),
            context: context
        )
    }

    func testApplyingARewriteMakesAVersionAndLeavesTheOriginalAlone() throws {
        let recipe = makeRecipe()
        let message = RecipeChatStore.append(
            role: .assistant, text: "Here you go", proposal: rewriteProposal(),
            family: RecipeChatStore.familyKey(for: recipe), in: context)

        let created = try XCTUnwrap(
            apply(rewriteProposal(), on: message, recipe: recipe).recipe)

        XCTAssertEqual(created.versionLabel, "No-pork version")
        XCTAssertTrue(created.parentRecipe === recipe)
        XCTAssertEqual(created.servings, 2)
        XCTAssertTrue(created.ingredients.contains { $0.name.contains("beef bacon") })
        // What the detail screen pushes you to.
        XCTAssertEqual(message.appliedLabel, "No-pork version")
        // The original is untouched.
        XCTAssertTrue(recipe.ingredients.contains { $0.name.contains("prosciutto") })
    }

    /// The reason the pantry path is not routed through text: a round trip
    /// through "120 g beef bacon" and back loses the unit on anything the
    /// parser doesn't recognise. `RecipeOptimizer.apply` never parses.
    func testApplyingAPantryPlanKeepsQuantitiesAndUnits() throws {
        let recipe = Recipe(title: "Buttered Pasta", servings: 2)
        context.insert(recipe)
        recipe.ingredients = [
            RecipeIngredient(name: "butter", quantity: 200, unit: "g", sortIndex: 0),
        ]
        recipe.steps = [RecipeStep(index: 0, text: "Melt the butter.")]

        let oliveOil = PantryItem(name: "olive oil")
        context.insert(oliveOil)

        let plan = RecipeOptimizer.plan(for: recipe, pantry: [oliveOil])
        let proposal = try XCTUnwrap(RecipeChatService.pantryProposal(for: recipe, plan: plan))
        XCTAssertTrue(proposal.isPantryPlan)

        let created = try XCTUnwrap(
            apply(proposal, recipe: recipe, pantry: [oliveOil]).recipe)

        let swapped = try XCTUnwrap(created.ingredients.first)
        XCTAssertEqual(swapped.name, "olive oil")
        XCTAssertEqual(swapped.quantity, 200)
        XCTAssertEqual(swapped.unit, "g")
        XCTAssertEqual(created.versionLabel, "Pantry version")
        XCTAssertTrue(created.parentRecipe === recipe)
    }

    /// The offer is re-planned at tap time, not replayed. An emptied pantry must
    /// not mint a version that swaps nothing.
    func testStalePantryPlanCreatesNothingAndLeavesTheCardOffering() throws {
        let recipe = makeRecipe()
        let family = RecipeChatStore.familyKey(for: recipe)
        let stalePlan = RecipeChatProposal(
            versionLabel: "Pantry version",
            ingredients: [], steps: [],
            changes: ["prosciutto becomes beef bacon"],
            summary: nil, servings: nil, kind: "pantry"
        )
        let message = RecipeChatStore.append(
            role: .assistant, text: "Here you go", proposal: stalePlan,
            family: family, in: context)

        let before = try context.fetchCount(FetchDescriptor<Recipe>())
        let outcome = apply(stalePlan, on: message, recipe: recipe, pantry: [])

        guard case .pantryPlanWentStale = outcome else {
            return XCTFail("Expected the stale-plan outcome, got \(outcome)")
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), before)
        XCTAssertNil(message.appliedLabel, "A card that created nothing must still offer")
    }

    // MARK: - Chips

    func testPantryChipOnlyAppearsWhenSomethingIsMissing() throws {
        let recipe = makeRecipe()
        let missing = RecipeChatService.suggestions(makeContext(recipe))
        XCTAssertTrue(missing.contains { $0.id == "pantry" })

        let stocked = RecipeChatService.Context(
            recipe: recipe,
            servings: 2,
            pantryMatch: PantryMatcher.MatchResult(owned: Array(recipe.ingredients)),
            prefs: UserPrefs.current(in: context),
            ownedTools: []
        )
        XCTAssertFalse(RecipeChatService.suggestions(stocked).contains { $0.id == "pantry" })
    }

    func testSuggestionsAreCappedAtFive() throws {
        let recipe = makeRecipe()
        XCTAssertLessThanOrEqual(RecipeChatService.suggestions(makeContext(recipe)).count, 5)
    }

    func testPantryProposalIsNilWhenThereIsNothingToSwap() throws {
        let recipe = makeRecipe()
        let plan = RecipeOptimizer.plan(for: recipe, pantry: [])
        XCTAssertNil(RecipeChatService.pantryProposal(for: recipe, plan: plan))
    }
}
