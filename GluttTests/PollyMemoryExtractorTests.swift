import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PollyMemoryExtractorTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([PollyMemory.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }
    override func tearDownWithError() throws { container = nil; try super.tearDownWithError() }

    /// Wire-shaped fixture: two facts, the second with a kind the model made up.
    private let fixtureJSON = """
    { "facts": [
        { "kind": "equipment", "text": "Their stove runs hot on the front-left burner.", "confidence": 0.9 },
        { "kind": "stove-vibes", "text": "They like to taste as they go.", "confidence": 1.4 }
      ],
      "summary": "Cooked lemon chicken for four. The sear ran long because the pan was crowded. They were happy with the final dish." }
    """

    // MARK: - Decode contract

    func testExtractionDecodesFromFixture() throws {
        let extraction = try JSONDecoder().decode(PollyMemoryExtractor.Extraction.self, from: Data(fixtureJSON.utf8))
        XCTAssertEqual(extraction.facts.count, 2)
        XCTAssertEqual(extraction.facts[0].kind, "equipment")
        XCTAssertEqual(extraction.facts[0].text, "Their stove runs hot on the front-left burner.")
        XCTAssertEqual(extraction.facts[0].confidence, 0.9, accuracy: 0.0001)
        // Unknown kind strings survive decode untouched; apply() maps them later.
        XCTAssertEqual(extraction.facts[1].kind, "stove-vibes")
        XCTAssertEqual(extraction.facts[1].confidence, 1.4, accuracy: 0.0001)
        XCTAssertFalse(extraction.summary.isEmpty)
    }

    // MARK: - apply

    func testApplyMapsKindsClampsConfidenceAndSkipsShortText() throws {
        let context = container.mainContext
        let extraction = PollyMemoryExtractor.Extraction(
            facts: [
                .init(kind: "equipment", text: "Their stove runs hot on the front-left burner.", confidence: 0.9),
                .init(kind: "stove-vibes", text: "They like to taste as they go.", confidence: 1.4),
                .init(kind: "technique", text: "They chop vegetables slowly and carefully.", confidence: -0.3),
                .init(kind: "preference", text: "Salty.", confidence: 0.5),
            ],
            summary: "A calm, tidy cook."
        )

        PollyMemoryExtractor.apply(extraction, recipeTitle: "Lemon Chicken", in: context)

        let rows = try context.fetch(FetchDescriptor<PollyMemory>())
        XCTAssertEqual(rows.count, 3, "the 6-char fact must be skipped (min 8 chars)")

        let stove = try XCTUnwrap(rows.first { $0.text == "Their stove runs hot on the front-left burner." })
        XCTAssertEqual(stove.kind, .equipment)
        XCTAssertEqual(stove.confidence, 0.9, accuracy: 0.0001)
        XCTAssertEqual(stove.sourceRecipeTitle, "Lemon Chicken")

        let taste = try XCTUnwrap(rows.first { $0.text == "They like to taste as they go." })
        XCTAssertEqual(taste.kind, .outcome, "invalid kind string falls back to .outcome")
        XCTAssertEqual(taste.confidence, 1.0, accuracy: 0.0001, "confidence clamps to 1")

        let chop = try XCTUnwrap(rows.first { $0.text == "They chop vegetables slowly and carefully." })
        XCTAssertEqual(chop.kind, .technique)
        XCTAssertEqual(chop.confidence, 0.0, accuracy: 0.0001, "confidence clamps to 0")

        XCTAssertNil(rows.first { $0.text == "Salty." })
    }

    // MARK: - extract (stubbed llm, no network)

    func testExtractUsesInjectedLLMAndBuildsPrompts() async throws {
        let fixture = try JSONDecoder().decode(PollyMemoryExtractor.Extraction.self, from: Data(fixtureJSON.utf8))
        var capturedSystem = ""
        var capturedUser = ""

        let result = try await PollyMemoryExtractor.extract(
            transcript: "Polly: How did the sear go?\nUser: Pan was crowded, took forever.",
            recipeTitle: "Lemon Chicken",
            llm: { system, user in
                capturedSystem = system
                capturedUser = user
                return fixture
            }
        )

        XCTAssertEqual(result, fixture)
        XCTAssertTrue(capturedSystem.contains("DURABLE"))
        // All five kinds must be offered to the model by rawValue.
        for kind in MemoryKind.allCases {
            XCTAssertTrue(capturedSystem.contains(kind.rawValue), "system prompt missing kind \(kind.rawValue)")
        }
        XCTAssertTrue(capturedSystem.contains("third person"))
        XCTAssertTrue(capturedUser.contains("Lemon Chicken"))
        XCTAssertTrue(capturedUser.contains("Pan was crowded"))
    }
}
