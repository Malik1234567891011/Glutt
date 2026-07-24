import XCTest
@testable import Glutt

@MainActor
final class ImportPipelineTests: XCTestCase {

    private func fakeDeps(
        fetched: ImportedRecipeDraft,
        cleanUp: @escaping (ImportedRecipeDraft) -> ImportedRecipeDraft = { $0 },
        reconstruct: @escaping (ImportedRecipeDraft) -> ImportedRecipeDraft = { $0 },
        inferSteps: @escaping (ImportedRecipeDraft) -> ImportedRecipeDraft = { $0 },
        wouldImprove: @escaping (ImportedRecipeDraft) -> Bool = { _ in true },
        transcript: VideoTranscript? = nil,
        compileFromSpeech: @escaping (ImportedRecipeDraft, VideoTranscript) -> ImportedRecipeDraft = { d, _ in d }
    ) -> ImportPipeline.Dependencies {
        ImportPipeline.Dependencies(
            fetch: { _ in fetched },
            wouldImprove: wouldImprove,
            cleanUp: { cleanUp($0) },
            reconstruct: { reconstruct($0) },
            inferSteps: { inferSteps($0) },
            transcribe: { _, _ in transcript },
            compileFromSpeech: { d, t in compileFromSpeech(d, t) },
            verifySpeech: { d, _ in d }
        )
    }

    func testReadingMessageAlwaysComesFirst() async throws {
        var messages: [String] = []
        var fetched = ImportedRecipeDraft()
        fetched.platform = .website
        let deps = fakeDeps(fetched: fetched, wouldImprove: { _ in false })
        _ = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertEqual(messages.first, "Reading the recipe…")
    }

    func testCleanupRunsAndIsReflectedInResult() async throws {
        var fetched = ImportedRecipeDraft()
        fetched.platform = .website
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

    func testSpeechPathCompilesBeforeReconstruct() async throws {
        var fetched = ImportedRecipeDraft()
        fetched.platform = .tiktok
        fetched.caption = "Creamiest garlic pasta ever #pasta"
        fetched.title = "Garlic pasta"

        let words = "Start with half a pound of rigatoni cook four cloves of garlic"
            .split(separator: " ")
            .enumerated()
            .map { i, w in
                TranscriptWord(text: String(w), start: Double(i) * 0.3, end: Double(i) * 0.3 + 0.2, type: "word")
            }
        let transcript = VideoTranscript(text: words.map(\.text).joined(separator: " "), words: words)

        var reconstructCalled = false
        let deps = fakeDeps(
            fetched: fetched,
            reconstruct: { d in
                reconstructCalled = true
                return d
            },
            wouldImprove: { _ in false },
            transcript: transcript,
            compileFromSpeech: { d, _ in
                var c = d
                c.ingredientLines = ["0.5 lb rigatoni", "4 cloves garlic"]
                c.stepTexts = ["Boil the pasta.", "Cook the garlic."]
                c.usedSpeechTranscript = true
                return c
            }
        )

        var messages: [String] = []
        let result = try await ImportPipeline.run(urlString: "https://tiktok.com/x", deps: deps) {
            messages.append($0)
        }

        XCTAssertTrue(messages.contains("Listening to the video…"))
        XCTAssertTrue(messages.contains("Building the recipe from what was said…"))
        XCTAssertFalse(reconstructCalled, "speech extraction should skip freestyle reconstruct")
        XCTAssertEqual(result.ingredientLines.first, "0.5 lb rigatoni")
        XCTAssertTrue(result.usedSpeechTranscript)
    }

    func testReconstructFiresForCaptionlessSocialVideoWithoutSpeech() async throws {
        var fetched = ImportedRecipeDraft()
        fetched.platform = .tiktok            // isSocialVideo == true, no ingredients
        let deps = fakeDeps(
            fetched: fetched,
            reconstruct: { d in
                var r = d
                r.ingredientLines = ["2 eggs"]
                r.stepTexts = ["Fry the eggs."]
                return r
            },
            wouldImprove: { _ in false },
            transcript: nil
        )
        var messages: [String] = []
        let result = try await ImportPipeline.run(urlString: "x", deps: deps) { messages.append($0) }
        XCTAssertTrue(messages.contains("No recipe in the video — drafting the dish…"))
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
