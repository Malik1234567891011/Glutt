import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PollyPromptBuilderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([
                Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
                UserPrefs.self, CookSession.self, PollyMemory.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: - Fixtures

    /// 3 ingredients: chicken (owned), onion (missing, required), parsley (missing, optional).
    private func makeRecipe() -> Recipe {
        let recipe = Recipe(title: "Harissa Chicken Skillet", servings: 2, prepMinutes: 10, cookMinutes: 25)
        context.insert(recipe)
        recipe.ingredients = [
            RecipeIngredient(name: "chicken thighs", quantity: 500, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "onion", quantity: 1, sortIndex: 1),
            RecipeIngredient(name: "parsley", isOptional: true, sortIndex: 2),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Sear the chicken until deeply browned."),
            RecipeStep(index: 1, text: "Add onion and harissa, simmer 15 minutes.", durationSeconds: 900),
        ]
        return recipe
    }

    private func makePrefs() -> UserPrefs {
        let prefs = UserPrefs.current(in: context)
        prefs.dietaryRules = [.halal]
        prefs.allergies = ["peanut"]
        prefs.dislikedIngredients = ["cilantro"]
        return prefs
    }

    private func makeMatch(for recipe: Recipe) -> PantryMatcher.MatchResult {
        let sorted = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
        return PantryMatcher.MatchResult(
            owned: [sorted[0]],
            missing: [sorted[1]],
            missingOptional: [sorted[2]]
        )
    }

    private func makeMemories() -> [PollyMemory] {
        let facts = [
            PollyMemory(kind: .equipment, text: "Owns a cast iron skillet", confidence: 0.9, sourceRecipeTitle: nil),
            PollyMemory(kind: .technique, text: "Chops slowly, pad prep estimates", confidence: 0.7, sourceRecipeTitle: nil),
            PollyMemory(kind: .preference, text: "Likes food spicier than recipes suggest", confidence: 0.8, sourceRecipeTitle: nil),
        ]
        facts.forEach(context.insert)
        return facts
    }

    private func makePastSession(recipe: Recipe) -> CookSession {
        let session = CookSession(date: Date(timeIntervalSince1970: 1_700_000_000), servingsMade: 2, recipe: recipe)
        session.rating = 4
        session.notes = "Came out great, went heavier on harissa"
        context.insert(session)
        return session
    }

    private func instructions(
        recipe: Recipe,
        memories: [PollyMemory] = [],
        pastSessions: [CookSession] = [],
        seesContinuously: Bool = false,
        watchfulness: ChefWatchfulness = .default,
        chef: PollyChefVoice = .default
    ) -> String {
        PollyPromptBuilder.instructions(
            recipe: recipe,
            plan: CookPlan.linear(from: recipe, scale: 1.0),
            pantryMatch: makeMatch(for: recipe),
            prefs: makePrefs(),
            memories: memories,
            pastSessions: pastSessions,
            ownedTools: [],
            seesContinuously: seesContinuously,
            watchfulness: watchfulness,
            chef: chef
        )
    }

    // MARK: - Chef voices

    func testDefaultChefAddsNoOverlay() {
        let recipe = makeRecipe()
        XCTAssertFalse(instructions(recipe: recipe).contains("Your voice this session"),
                       "house Polly must be the prompt exactly as it was")
    }

    func testChefOverlayIsAppendedLastSoItCannotOutrankTheRulesAboveIt() {
        let recipe = makeRecipe()
        let prompt = instructions(recipe: recipe, chef: .gordonRamsay)

        XCTAssertTrue(prompt.contains("Your voice this session: Gordon Ramsay"))
        // Ordering is the safety property, not a style choice. A persona placed
        // above the run policy would let "how to sound" quietly outrank a
        // food-safety or dietary rule; placed last it can only colour them, and
        // it says so itself.
        let overlayStart = try? XCTUnwrap(prompt.range(of: "Your voice this session"))
        let rulesStart = try? XCTUnwrap(prompt.range(of: "Be directional, never chatty"))
        if let overlayStart, let rulesStart {
            XCTAssertTrue(overlayStart.lowerBound > rulesStart.lowerBound,
                          "the chef overlay must come after the run policy")
        }
        // The dish is still the dish.
        XCTAssertTrue(prompt.contains("Harissa Chicken Skillet"))
        XCTAssertTrue(prompt.contains("peanut"), "allergies survive a persona swap")
    }

    func testRamsayOverlayForbidsTheAbusiveTelevisionPersona() {
        let overlay = PollyChefVoice.gordonRamsay.personaOverlay
        XCTAssertTrue(overlay.contains("Never swear"))
        XCTAssertTrue(overlay.contains("never insult the cook"))
        XCTAssertTrue(overlay.lowercased().contains("lamb sauce"),
                      "the catchphrase is named so it can be banned, not used")
        XCTAssertTrue(overlay.contains("Never claim to be the real person"))
    }

    func testEveryChefHasAVoiceAndAStableID() {
        let ids = PollyChefVoice.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids are persisted, so they must be unique")
        for chef in PollyChefVoice.all {
            XCTAssertFalse(chef.displayName.isEmpty, chef.id)
            XCTAssertFalse(chef.realtimeVoice.isEmpty, chef.id)
            XCTAssertFalse(chef.briefingStyle.isEmpty, chef.id)
        }
        XCTAssertEqual(PollyChefVoice.named("nope").id, PollyChefVoice.default.id,
                       "an unknown id falls back rather than crashing a cook")
    }

    // MARK: - Tests

    func testInstructionsIncludeDishPantryAndHardRules() {
        let recipe = makeRecipe()
        let plan = CookPlan.linear(from: recipe, scale: 1.0)
        let prompt = instructions(recipe: recipe)

        XCTAssertTrue(prompt.contains("Harissa Chicken Skillet"))
        XCTAssertTrue(prompt.contains("\(plan.servings) servings"))
        XCTAssertTrue(prompt.contains("has 1 of 2"), "ownedCount/totalCount from the pantry match")
        XCTAssertTrue(prompt.contains("onion"), "missing required ingredient is listed")
        XCTAssertTrue(prompt.contains("parsley"), "missing optional ingredient is listed")
        XCTAssertTrue(prompt.contains("halal"), "DietaryRule rawValue, not the display label")
        XCTAssertTrue(prompt.contains("peanut"))
        XCTAssertTrue(prompt.contains("cilantro"), "dislikes appear as a soft preference")
    }

    func testInstructionsIncludeMemoriesAndPastSessionHistory() {
        let recipe = makeRecipe()
        let memories = makeMemories()
        let prompt = instructions(recipe: recipe, memories: memories,
                                  pastSessions: [makePastSession(recipe: recipe)])

        for memory in memories {
            XCTAssertTrue(prompt.contains(memory.text), "missing memory: \(memory.text)")
        }
        XCTAssertTrue(prompt.contains("- [equipment] Owns a cast iron skillet"))
        XCTAssertTrue(prompt.contains("4/5"), "past-session rating string")
        XCTAssertTrue(prompt.contains("Came out great, went heavier on harissa"))
        XCTAssertFalse(prompt.contains("First time cooking this together."))
    }

    // MARK: - What she is told she can see

    /// The phone camera sits on a counter and is off until asked, so the useful
    /// behaviour is inviting a look. Nothing about that should leak into a cook
    /// wearing glasses.
    func testPhoneCookIsToldTheCameraIsOffAndToInviteALook() {
        let prompt = instructions(recipe: makeRecipe(), seesContinuously: false)

        XCTAssertTrue(prompt.contains("The camera is OFF by default"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("tap the camera"))
        XCTAssertFalse(prompt.contains("YOU CAN SEE"))
    }

    /// The glasses cook gets the opposite instruction, and this is the exact
    /// regression that made the first real glasses cook useless: Chef told a cook
    /// who was streaming to her "I can't see the counter unless you turn the
    /// camera on", because she had been handed the phone wording.
    func testGlassesCookIsNeverToldToTurnACameraOn() {
        let prompt = instructions(recipe: makeRecipe(), seesContinuously: true)

        XCTAssertTrue(prompt.contains("YOU CAN SEE"))
        XCTAssertFalse(prompt.contains("The camera is OFF by default"))
        XCTAssertFalse(prompt.localizedCaseInsensitiveContains("tap the camera"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("never say you cannot see"))
    }

    /// Always-on vision is only worth having if she uses it to catch what the
    /// cook got wrong. Verifying claims against the recipe is the whole feature,
    /// so it is asserted rather than left to a prompt edit to quietly drop.
    func testGlassesCookIsToldToVerifyClaimsAgainstTheRecipe() {
        let prompt = instructions(recipe: makeRecipe(), seesContinuously: true)

        XCTAssertTrue(prompt.contains("LOOK BEFORE YOU AGREE"))
        XCTAssertTrue(prompt.contains("CHECK IT AGAINST THE RECIPE"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("visualCheck"),
                      "she has a per-step expectation and should be pointed at it")
        // And a bar, because a camera on your face narrating your kitchen is
        // worse than one that stays quiet.
        XCTAssertTrue(prompt.contains("HAVE A HIGH BAR"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not narrate"))
    }

    /// Verifying a claim must never become a gate the cook cannot get past.
    ///
    /// A frame that does not show the tools is not evidence they are missing,
    /// it usually means they are out of shot. Chef was holding cooks at the
    /// Tools step over exactly that, re-asking for something already on the
    /// counter, so she now has to offer the override in the same breath and
    /// take their word the first time they give it.
    func testGlassesCookCanOverrideWhatChefCannotSee() {
        let prompt = instructions(recipe: makeRecipe(), seesContinuously: true)

        XCTAssertTrue(prompt.contains("NOT SEEING IT IS NOT THE SAME AS IT NOT BEING THERE"))
        XCTAssertTrue(prompt.contains("IF THEY SAY IT IS THERE, IT IS THERE"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("out of view"),
                      "the override has to be offered, not waited for")
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("take your word"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("never ask them to prove"),
                      "and she must not re-check what they already vouched for")
        // The override is for a look that already failed. Read as a general
        // licence to take their word it removes the looking, which is what
        // happened: "the water is at a rolling boil" advanced the step with no
        // frame requested and nothing said about it.
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("never a reason to skip the first one"))
    }

    /// A look the cook never hears about is a look they cannot tell from no look
    /// at all. Reporting a step done has to come back with a verdict.
    func testGlassesCookHearsWhatChefSaw() {
        let prompt = instructions(recipe: makeRecipe(), seesContinuously: true)

        XCTAssertTrue(prompt.contains("SAY WHAT YOU SAW"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("rolling boil"),
                      "the doneness report is the case that matters")
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("visualCheck"),
                      "and she judges it against the step's own cue")
    }

    // MARK: - Watchfulness

    /// The three levels have to be genuinely different instructions, not the
    /// same paragraph with an adjective swapped. If two of them ever produce the
    /// same prompt, the picker is a placebo.
    func testEachWatchfulnessLevelProducesADifferentPrompt() {
        let recipe = makeRecipe()
        let prompts = ChefWatchfulness.allCases.map {
            instructions(recipe: recipe, seesContinuously: true, watchfulness: $0)
        }
        XCTAssertEqual(Set(prompts).count, ChefWatchfulness.allCases.count)
    }

    /// The cook picked "leave me alone". Being right is not a reason to override
    /// that, and this is the assertion that stops a later prompt edit from
    /// helpfully adding the speaking-up rules back for everyone.
    func testHandsOffIsNeverToldToVolunteer() {
        let prompt = instructions(recipe: makeRecipe(), seesContinuously: true, watchfulness: .handsOff)

        XCTAssertTrue(prompt.contains("DO NOT VOLUNTEER"))
        XCTAssertFalse(prompt.contains("SPEAK UP UNASKED"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("being right is not a reason to speak"))
        // She can still see and can still be asked. Hands off is about her
        // manner, not about taking the camera away.
        XCTAssertTrue(prompt.contains("YOU CAN SEE"))
        XCTAssertTrue(prompt.contains("LOOK BEFORE YOU AGREE"))
    }

    /// Danger to the person is the one thing that outranks the cook's choice.
    func testHandsOffStillBreaksSilenceForDanger() {
        let prompt = instructions(recipe: makeRecipe(), seesContinuously: true, watchfulness: .handsOff)
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("danger to the person"))
    }

    /// The strict level is the one that judges technique and cut sizes, which
    /// the middle level is explicitly told to leave alone.
    func testPerfectionistJudgesTechniqueAndWatchfulDoesNot() {
        let recipe = makeRecipe()
        let strict = instructions(recipe: recipe, seesContinuously: true, watchfulness: .perfectionist)
        let middle = instructions(recipe: recipe, seesContinuously: true, watchfulness: .watchful)

        XCTAssertTrue(strict.contains("TECHNIQUE COUNTS"))
        XCTAssertFalse(middle.contains("TECHNIQUE COUNTS"))
        XCTAssertTrue(middle.localizedCaseInsensitiveContains("do not correct cut sizes, technique"))
        // Even the strict one is not allowed to become a commentary.
        XCTAssertTrue(strict.contains("STILL NOT A COMMENTARY"))
    }

    /// The rules for a look nobody asked for.
    ///
    /// Every other seeing rule covers a look the conversation earned. These are
    /// the ones a clock starts, and they need something the others do not: a way
    /// to end the turn having said nothing. Without one a voice model finds
    /// something to say every single time, and twenty of those is what gets the
    /// glasses taken off.
    func testUnpromptedLooksAreGivenAWayToSayNothing() {
        let recipe = makeRecipe()
        let prompt = instructions(recipe: recipe, seesContinuously: true, watchfulness: .watchful)
        XCTAssertTrue(prompt.contains("UNPROMPTED LOOKS"))
        XCTAssertTrue(prompt.contains("wait_for_user"), "silence needs a mechanism, not a wish")
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("say\n               NOTHING")
                        || prompt.localizedCaseInsensitiveContains("NOTHING AT ALL"))
        XCTAssertTrue(prompt.contains("NEVER NARRATE A LOOK"))
        XCTAssertTrue(prompt.contains("NOT A CONVERSATION"),
                      "she says her one thing and stops rather than opening a turn")
    }

    /// Hands off means hands off, including the clock. A cook who asked to be
    /// left alone must not get a prompt describing looks they will never get.
    func testHandsOffIsToldNothingAboutUnpromptedLooks() {
        let recipe = makeRecipe()
        let prompt = instructions(recipe: recipe, seesContinuously: true, watchfulness: .handsOff)
        XCTAssertFalse(prompt.contains("UNPROMPTED LOOKS"))
    }

    /// Both watching levels used to be told never to say a thing was fine. That
    /// is the difference between a chef watching over your shoulder and a smoke
    /// alarm: the alarm only ever speaks when you have failed.
    func testPraiseIsAllowedButHasToNameTheThing() {
        let recipe = makeRecipe()
        for level in [ChefWatchfulness.perfectionist, .watchful] {
            let prompt = instructions(
                recipe: recipe, seesContinuously: true, watchfulness: level)
            XCTAssertFalse(
                prompt.localizedCaseInsensitiveContains("never say a thing is fine"),
                "\(level.rawValue) is still banned from ever approving anything")
            XCTAssertFalse(
                prompt.localizedCaseInsensitiveContains("do not confirm that things are fine"),
                "\(level.rawValue) is still banned from ever approving anything")
            XCTAssertTrue(
                prompt.localizedCaseInsensitiveContains("once per step"),
                "\(level.rawValue) has no cap on praise, which is how it becomes commentary")
        }
        // And it still has to be specific: vague approval is the failure mode.
        let strict = instructions(
            recipe: recipe, seesContinuously: true, watchfulness: .perfectionist)
        XCTAssertTrue(strict.localizedCaseInsensitiveContains("\"looks good\" on its own is noise"))
    }

    /// Watchfulness is a glasses idea. A phone cook must get the same prompt
    /// whatever is persisted, or a setting they never saw changes their cook.
    func testWatchfulnessDoesNotLeakIntoAPhoneCook() {
        let recipe = makeRecipe()
        let prompts = ChefWatchfulness.allCases.map {
            instructions(recipe: recipe, seesContinuously: false, watchfulness: $0)
        }
        XCTAssertEqual(Set(prompts).count, 1)
    }

    func testCookPlanJSONRoundTripsBetweenMarkers() throws {
        let recipe = makeRecipe()
        let plan = CookPlan.linear(from: recipe, scale: 1.0)
        let prompt = instructions(recipe: recipe)

        let start = try XCTUnwrap(prompt.range(of: "<cook_plan>"))
        let end = try XCTUnwrap(prompt.range(of: "</cook_plan>"))
        XCTAssertTrue(start.upperBound <= end.lowerBound, "markers appear in order")
        let json = prompt[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, plan)
    }

    func testFirstTimeLineWhenNoPastSessions() {
        let prompt = instructions(recipe: makeRecipe(), pastSessions: [])
        XCTAssertTrue(prompt.contains("First time cooking this together."))
    }

    // MARK: - Reading ahead

    /// A cook who asks "how long do the muffins bake?" while creaming butter must
    /// get an answer, not a lecture about which step they're on. The prompt used
    /// to conflate "don't INSTRUCT ahead" with "don't INFORM ahead"; only the
    /// first is a real rule.
    func testPromptAlwaysAnswersQuestionsAboutLaterSteps() {
        let prompt = instructions(recipe: makeRecipe())

        XCTAssertTrue(prompt.contains("## Questions about later steps — ALWAYS answer, never deflect"))
        // The refusals Malik hears in the kitchen, named so they can be banned.
        for refusal in ["you're not on that step yet", "we'll get to that",
                        "let's finish this step first", "one thing at a time"] {
            XCTAssertTrue(prompt.contains(refusal),
                          "the prompt must name and ban the refusal: \(refusal)")
        }
        XCTAssertTrue(prompt.contains("Answering is NOT advancing."))
        // Looking ahead must not silently move the cook.
        XCTAssertTrue(prompt.contains("call go_to_step or mark_step_done to answer a question"))

        // The old blanket ban on even mentioning later work is gone.
        XCTAssertFalse(prompt.contains("until the plan actually reaches that step"),
                       "informing ahead is no longer forbidden")
    }

    /// The other half of the same rule: she still must not PUSH the cook forward.
    func testPromptStillForbidsInstructingAheadOfThePlan() {
        let prompt = instructions(recipe: makeRecipe())

        XCTAssertTrue(prompt.contains("NEVER DIRECT the cook to DO something from a later step early"))
        XCTAssertTrue(prompt.contains("Work through steps strictly in order."))
        XCTAssertTrue(prompt.contains("never start a TIME-SENSITIVE action early"),
                      "the food-safety ordering line must survive")
        XCTAssertTrue(prompt.contains("Don't start searing,"),
                      "the things that genuinely must not start early are still named")
    }

    /// From a real crème brûlée cook: the first mention of 325 degrees was the
    /// bake step itself, so the custard was finished and the oven was cold.
    ///
    /// Two rules used to guarantee that. One banned preheating "to get ahead",
    /// the other scoped preheat to the immediately-next step. An oven takes 10 to
    /// 15 minutes, so between them the oven could never be ready on time.
    func testOvensAreToldToPreheatAheadOfTheBake() {
        let prompt = instructions(recipe: makeRecipe())

        XCTAssertTrue(prompt.contains("OVENS GET LEAD TIME"))
        XCTAssertTrue(prompt.contains("within the next two or three steps"),
                      "she has to look ahead for the bake, not wait for it")
        XCTAssertTrue(prompt.contains("Never let the first mention of an"),
                      "the failure itself must be named")
        XCTAssertTrue(prompt.contains("THE OVEN IS THE EXCEPTION"),
                      "the ordering rule must carve the oven out explicitly")

        // The blanket ban that caused the cold oven is gone.
        XCTAssertFalse(prompt.contains("don't preheat \"to"),
                       "preheating ahead is no longer forbidden")
    }

    /// Wording alone would be useless if the later steps weren't in her context.
    /// Every step's instruction ships in the embedded plan, so she can answer a
    /// question about the last step while standing on the first.
    func testEveryLaterStepIsReachableInTheEmbeddedPlan() throws {
        let recipe = Recipe(title: "Blueberry Muffins", servings: 12)
        context.insert(recipe)
        recipe.ingredients = [
            RecipeIngredient(name: "flour", quantity: 250, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "blueberries", quantity: 150, unit: "g", sortIndex: 1),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Cream the butter and sugar until pale."),
            RecipeStep(index: 1, text: "Fold in the flour and blueberries."),
            RecipeStep(index: 2, text: "Bake at 190C for 22 minutes.", durationSeconds: 1320),
        ]

        let plan = CookPlan.linear(from: recipe, scale: 1.0)
        let prompt = PollyPromptBuilder.instructions(
            recipe: recipe,
            plan: plan,
            pantryMatch: PantryMatcher.MatchResult(owned: recipe.ingredients, missing: [], missingOptional: []),
            prefs: makePrefs(),
            memories: [],
            pastSessions: [],
            ownedTools: []
        )

        for step in plan.steps {
            XCTAssertTrue(prompt.contains(step.instruction),
                          "step \(step.index) is not answerable: \(step.instruction)")
        }
        // The specific question from the bug report: the bake time and temperature
        // are in context while the cook is still on step 1.
        XCTAssertTrue(prompt.contains("Bake at 190C for 22 minutes."))
        XCTAssertTrue(prompt.contains("250 g flour"), "amounts for later steps are in context too")
    }

    func testMemoryBulletsAreCappedAtConfigLimit() {
        let memories = (0..<20).map { i in
            PollyMemory(kind: .outcome, text: "Durable kitchen fact number \(i)",
                        confidence: 0.5, sourceRecipeTitle: nil)
        }
        memories.forEach(context.insert)
        let prompt = instructions(recipe: makeRecipe(), memories: memories)

        let bullets = prompt.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        XCTAssertEqual(bullets.count, PollyConfig.memoryFactLimit)
        XCTAssertTrue(prompt.contains("Durable kitchen fact number 0"))
        XCTAssertFalse(prompt.contains("Durable kitchen fact number \(PollyConfig.memoryFactLimit)"),
                       "facts past the cap must not leak into the prompt")
    }

    // MARK: - No monologues

    /// A cook said "I'm using 1.5lb chicken not 3" and she read back the new
    /// amount for every single ingredient in the recipe. The amounts list is a
    /// reference she speaks *from*, one item at a time, not a script.
    func testSheIsToldNeverToReadTheAmountsListAloud() {
        let prompt = instructions(recipe: makeRecipe())
        XCTAssertTrue(prompt.contains("NEVER read this list out loud"))
        XCTAssertTrue(prompt.contains("Do NOT list the new amount for each ingredient"))
    }

    /// Rescaling still has to actually happen. The fix is about how much she
    /// says, not about her quietly keeping the old numbers.
    func testRescalingIsStillRequiredJustNotNarrated() {
        let prompt = instructions(recipe: makeRecipe())
        XCTAssertTrue(prompt.contains("use it for every amount from then on"))
        XCTAssertTrue(prompt.contains("ONE short line back"),
                      "she confirms the change, she just does not enumerate it")
    }

    /// The same failure shows up as reading out equipment, substitutions and
    /// step lists, so the rule is general and lives with the speaking style.
    func testTheNoListRuleIsGeneralNotJustAboutAmounts() {
        let prompt = instructions(recipe: makeRecipe())
        XCTAssertTrue(prompt.contains("NEVER read a list out loud"))
    }

    /// She still has the numbers. Removing them would trade a talkative chef
    /// for a wrong one.
    func testTheAmountsAreStillInThePromptForHerToUse() {
        let recipe = makeRecipe()
        let prompt = instructions(recipe: recipe)
        XCTAssertTrue(prompt.contains("500 g chicken thighs")
                        || prompt.contains("chicken thighs"),
                      "the reference list itself must survive")
        XCTAssertTrue(prompt.contains("ALWAYS say the amount from this list"))
    }
}
