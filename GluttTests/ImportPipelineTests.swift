import XCTest
@testable import Glutt

@MainActor
final class ImportPipelineTests: XCTestCase {

    private func fakeDeps(
        fetched: ImportedRecipeDraft,
        cleanUp: @escaping (ImportedRecipeDraft) -> ImportedRecipeDraft = { $0 },
        reconstruct: @escaping (ImportedRecipeDraft) -> ImportedRecipeDraft = { $0 },
        inferSteps: @escaping (ImportedRecipeDraft) -> ImportedRecipeDraft = { $0 },
        wouldImprove: @escaping (ImportedRecipeDraft) -> Bool = { _ in true }
    ) -> ImportPipeline.Dependencies {
        ImportPipeline.Dependencies(
            fetch: { _ in fetched },
            wouldImprove: wouldImprove,
            cleanUp: { cleanUp($0) },
            reconstruct: { reconstruct($0) },
            inferSteps: { inferSteps($0) }
        )
    }

    func testReadingMessageAlwaysComesFirst() async throws {
        var messages: [String] = []
        let deps = fakeDeps(fetched: ImportedRecipeDraft(), wouldImprove: { _ in false })
        _ = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertEqual(messages.first, "Reading the recipe…")
    }

    func testCleanupRunsAndIsReflectedInResult() async throws {
        var fetched = ImportedRecipeDraft()
        fetched.platform = .tiktok
        let deps = fakeDeps(fetched: fetched, cleanUp: { d in
            var c = d
            c.ingredientLines = ["1 cup rice"]
            c.stepTexts = ["Cook the rice."]
            return c
        })
        var messages: [String] = []
        let result = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertTrue(messages.contains("Cleaning it up with AI…"))
        XCTAssertEqual(result.ingredientLines, ["1 cup rice"])
        XCTAssertEqual(result.stepTexts, ["Cook the rice."])
    }

    func testReconstructFiresForCaptionlessSocialVideo() async throws {
        var fetched = ImportedRecipeDraft()
        fetched.platform = .tiktok            // isSocialVideo == true, no ingredients
        let deps = fakeDeps(fetched: fetched, reconstruct: { d in
            var r = d
            r.ingredientLines = ["2 eggs"]
            r.stepTexts = ["Fry the eggs."]
            return r
        })
        var messages: [String] = []
        let result = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertTrue(messages.contains("No recipe in the caption — drafting the dish…"))
        XCTAssertEqual(result.ingredientLines, ["2 eggs"])
    }

    func testInferStepsFiresWhenIngredientsButNoSteps() async throws {
        var fetched = ImportedRecipeDraft()
        fetched.platform = .website
        fetched.ingredientLines = ["1 cup rice"]   // has ingredients, no steps
        let deps = fakeDeps(fetched: fetched, inferSteps: { d in
            var r = d
            r.stepTexts = ["Cook the rice."]
            r.stepsAreAISuggested = true
            return r
        })
        var messages: [String] = []
        let result = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertTrue(messages.contains("No method listed — drafting the steps…"))
        XCTAssertEqual(result.stepTexts, ["Cook the rice."])
        XCTAssertTrue(result.stepsAreAISuggested)
    }
}
