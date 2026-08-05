import SwiftUI
import UIKit

/// Staging hook for the import sheet: `-importScreen importing|saved|failed`.
///
/// The share extension is close to undrivable in the simulator — you can't share
/// an Instagram reel into it — so without this the three states of the screen
/// that ships there could only ever be checked by eye on a device. It renders
/// the real `ImportSheet` against canned pipeline dependencies, so what you see
/// here is what the extension draws.
enum ImportScreenStaging {

    enum Scenario: String {
        case importing
        case saved
        case failed
    }

    static var requested: Scenario? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-importScreen"),
              arguments.indices.contains(flagIndex + 1)
        else { return nil }
        return Scenario(rawValue: arguments[flagIndex + 1])
    }

    /// A view model wired to dependencies that reproduce the scenario without a
    /// network call.
    @MainActor
    static func viewModel(for scenario: Scenario) -> ShareImportViewModel {
        ShareImportViewModel(
            urlString: "https://www.instagram.com/reel/staged",
            deps: dependencies(for: scenario),
            sharedImageData: sampleImageData
        )
    }

    @MainActor
    private static func dependencies(for scenario: Scenario) -> ImportPipeline.Dependencies {
        var deps = ImportPipeline.Dependencies(
            fetch: { _ in sampleDraft },
            wouldImprove: { _ in false },
            cleanUp: { $0 },
            reconstruct: { $0 },
            inferSteps: { $0 },
            transcribe: { _, _ in (nil, nil) },
            compileFromSpeech: { draft, _ in draft },
            verifySpeech: { draft, _ in draft }
        )
        switch scenario {
        case .saved:
            break
        case .failed:
            deps.fetch = { _ in throw ImportError.nothingFound }
        case .importing:
            // Land the dish name after a beat, then hold — so the skeleton
            // bars, the crossfade into the title and a status-line change are
            // all reachable on one launch. The loading screen is the thing
            // being looked at, so it must never resolve.
            deps.fetch = { _ in
                try await Task.sleep(nanoseconds: 2_500_000_000)
                return sampleDraft
            }
            deps.wouldImprove = { _ in true }
            deps.cleanUp = { draft in
                try? await Task.sleep(nanoseconds: .max)
                return draft
            }
        }
        return deps
    }

    private static var sampleDraft: ImportedRecipeDraft {
        var draft = ImportedRecipeDraft()
        draft.title = "Korean Beef Bowl Meal Prep"
        draft.platform = .instagram
        draft.servings = 4
        draft.prepMinutes = 15
        draft.cookMinutes = 20
        draft.ingredientLines = [
            "1 lb ground beef", "2 cups jasmine rice", "3 cloves garlic",
            "2 tbsp soy sauce", "1 tbsp sesame oil", "2 tsp brown sugar",
            "1 cucumber", "2 carrots", "4 eggs", "2 scallions",
            "1 tsp gochujang", "1 tbsp rice vinegar",
        ]
        draft.imageData = sampleImageData
        return draft
    }

    private static var sampleImageData: Data? {
        UIImage(named: "koreanBeefMealPrep")?.jpegData(compressionQuality: 0.9)
    }
}
