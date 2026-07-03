import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PollyMemoryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // PollyCookLog references Recipe, so the whole Recipe graph rides along.
        let schema = Schema([
            PollyMemory.self, PollyCookLog.self,
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws { container = nil; try super.tearDownWithError() }

    // MARK: - upsert

    func testUpsertInsertsNewFact() throws {
        let memory = PollyMemoryStore.upsert(
            kind: .equipment, text: "Owns a cast iron skillet", confidence: 0.8,
            sourceRecipeTitle: "Smash Burgers", in: context
        )
        XCTAssertEqual(memory.kind, .equipment)
        XCTAssertEqual(memory.kindRaw, "equipment")
        XCTAssertEqual(memory.timesReinforced, 1)
        XCTAssertEqual(memory.confidence, 0.8)
        XCTAssertEqual(memory.sourceRecipeTitle, "Smash Burgers")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PollyMemory>()).count, 1)
    }

    func testNearDuplicateSameKindReinforcesInsteadOfDuplicating() throws {
        // Word sets: {chops, onions, slowly} vs {chops, onions, slowly, and, carefully}
        // -> Jaccard 3/5 = 0.6, at the threshold, so it must reinforce.
        let original = PollyMemoryStore.upsert(
            kind: .technique, text: "chops onions slowly", confidence: 0.5,
            sourceRecipeTitle: nil, in: context
        )
        let updatedAtBefore = original.updatedAt

        let result = PollyMemoryStore.upsert(
            kind: .technique, text: "Chops onions slowly and carefully", confidence: 0.9,
            sourceRecipeTitle: "French Onion Soup", in: context
        )

        XCTAssertEqual(result.persistentModelID, original.persistentModelID, "should reinforce, not insert")
        XCTAssertEqual(result.timesReinforced, 2)
        XCTAssertEqual(result.confidence, 0.9, "confidence takes the max of old and new")
        XCTAssertEqual(result.text, "Chops onions slowly and carefully", "keeps the longer text")
        XCTAssertGreaterThanOrEqual(result.updatedAt, updatedAtBefore)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PollyMemory>()).count, 1)
    }

    func testDistinctTextSameKindInsertsSecondRow() throws {
        // Word sets share nothing -> Jaccard 0 -> new row.
        PollyMemoryStore.upsert(kind: .equipment, text: "Owns a cast iron skillet",
                                confidence: 0.8, sourceRecipeTitle: nil, in: context)
        PollyMemoryStore.upsert(kind: .equipment, text: "Stove runs hot on medium",
                                confidence: 0.7, sourceRecipeTitle: nil, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PollyMemory>()).count, 2)
    }

    func testSameTextDifferentKindInsertsTwoRows() throws {
        PollyMemoryStore.upsert(kind: .equipment, text: "Owns a rice cooker",
                                confidence: 0.8, sourceRecipeTitle: nil, in: context)
        PollyMemoryStore.upsert(kind: .preference, text: "Owns a rice cooker",
                                confidence: 0.8, sourceRecipeTitle: nil, in: context)
        let all = try context.fetch(FetchDescriptor<PollyMemory>())
        XCTAssertEqual(all.count, 2, "dedup only applies within the same kind")
        XCTAssertEqual(all.allSatisfy { $0.timesReinforced == 1 }, true)
    }

    // MARK: - topFacts

    func testTopFactsOrdersByReinforcementThenRecencyAndAppliesLimit() throws {
        let wok = PollyMemory(kind: .equipment, text: "Owns a wok", confidence: 0.7, sourceRecipeTitle: nil)
        wok.timesReinforced = 3
        wok.updatedAt = Date(timeIntervalSince1970: 1_000)
        let heat = PollyMemory(kind: .technique, text: "Prefers medium heat", confidence: 0.6, sourceRecipeTitle: nil)
        heat.timesReinforced = 1
        heat.updatedAt = Date(timeIntervalSince1970: 3_000)
        let rice = PollyMemory(kind: .outcome, text: "Rice came out sticky last time", confidence: 0.5, sourceRecipeTitle: nil)
        rice.timesReinforced = 1
        rice.updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(wok)
        context.insert(heat)
        context.insert(rice)

        let top2 = PollyMemoryStore.topFacts(limit: 2, in: context)
        XCTAssertEqual(top2.map(\.text), ["Owns a wok", "Prefers medium heat"],
                       "timesReinforced desc, then updatedAt desc")

        let all = PollyMemoryStore.topFacts(limit: 10, in: context)
        XCTAssertEqual(all.count, 3, "limit beyond the row count returns everything")
    }

    // MARK: - Model behavior

    func testGarbageKindRawFallsBackToOutcome() {
        let memory = PollyMemory(kind: .equipment, text: "Owns a blender", confidence: 0.5, sourceRecipeTitle: nil)
        memory.kindRaw = "vibes"
        XCTAssertEqual(memory.kind, .outcome)
    }

    func testCookLogInitDefaultsAndRecipeRelationship() throws {
        let recipe = Recipe(title: "Shakshuka")
        context.insert(recipe)
        let log = PollyCookLog(startedAt: Date(timeIntervalSince1970: 500), recipe: recipe)
        context.insert(log)

        XCTAssertEqual(log.startedAt, Date(timeIntervalSince1970: 500))
        XCTAssertNil(log.endedAt)
        XCTAssertEqual(log.summary, "")
        XCTAssertEqual(log.stepsCompleted, 0)
        XCTAssertEqual(log.stepsTotal, 0)
        XCTAssertEqual(log.substitutions, [])
        XCTAssertFalse(log.endedEarly)
        XCTAssertEqual(log.recipe?.title, "Shakshuka")
    }
}
