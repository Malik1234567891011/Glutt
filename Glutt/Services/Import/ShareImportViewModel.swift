import Foundation
import Observation

/// Drives the share-sheet import UI.
///
/// There is no review step: parsing and saving both happen without input, so the
/// recipe is written to the app-group inbox the moment the pipeline finishes and
/// the user only ever sees it land. Anything they want to change, they change in
/// the app, on a screen built for it.
@MainActor
@Observable
final class ShareImportViewModel {

    enum State {
        case importing(ImportPipeline.Progress)
        case saved(ImportedRecipeDraft)
        case failed(String)
    }

    private(set) var state: State = .importing(ImportPipeline.Progress(stage: .reading))
    private(set) var draft: ImportedRecipeDraft?

    /// Where the link came from, known before the fetch so the header can name
    /// it straight away.
    let platform: SourcePlatform

    /// Preview image the share sheet handed us, if any. Used as the recipe image
    /// only when the import couldn't scrape a thumbnail (e.g. Instagram reels),
    /// and as the failure screen's visual when there's no recipe to show.
    let sharedImageData: Data?

    private let urlString: String
    private let deps: ImportPipeline.Dependencies
    private let inbox: ImportInbox

    init(urlString: String,
         deps: ImportPipeline.Dependencies = .live,
         inbox: ImportInbox = ImportInbox(),
         sharedImageData: Data? = nil) {
        self.urlString = urlString
        self.deps = deps
        self.inbox = inbox
        self.sharedImageData = sharedImageData
        self.platform = SourcePlatform(urlString: urlString)
    }

    func start() async {
        state = .importing(ImportPipeline.Progress(stage: .reading))
        do {
            var draft = try await ImportPipeline.run(urlString: urlString, deps: deps) { [weak self] progress in
                guard let self, case .importing = self.state else { return }
                self.state = .importing(progress)
            }
            if draft.imageURL == nil, let sharedImageData {
                draft.imageData = sharedImageData
            }
            inbox.append(draft)
            self.draft = draft
            self.state = .saved(draft)
        } catch {
            self.draft = nil
            self.state = .failed(ImportPipeline.failureReason(for: error))
        }
    }

    /// "Keep the link anyway" — the read failed, but the link is still worth
    /// something. Queues a stub the app can ask about later.
    @discardableResult
    func keepLink() -> UUID {
        var stub = ImportedRecipeDraft()
        stub.sourceURL = urlString
        stub.platform = platform
        stub.imageData = sharedImageData
        stub.issues.append("Couldn’t read a recipe from this link — kept for later")
        inbox.append(stub)
        draft = stub
        return stub.id
    }

    /// The user closed the sheet mid-import. The extension is about to be torn
    /// down and the pipeline with it, so hand the link to the app rather than
    /// lose it.
    func abandon() {
        guard case .importing = state else { return }
        PendingImportStore.save(urlString: urlString)
    }

    // MARK: - Copy

    /// Header label. Sentence here, uppercased by the header itself.
    ///
    /// Deliberately does not name the source. The platform is inferred from the
    /// link, so it can be wrong, and "saved from Instagram" reads as a claim
    /// about where the recipe came from rather than what is happening.
    var headerLabel: String {
        switch state {
        case .importing: "Saving a recipe"
        case .saved:     "Saved to Glutt"
        case .failed:    "Could not read it"
        }
    }

    /// The primary action on the saved screen. It names the app you came from
    /// because it describes where tapping sends you — but only when the link
    /// actually identifies one. "Back to Website" would name nothing.
    var returnActionLabel: String {
        switch platform {
        case .instagram, .tiktok, .youtube, .reddit, .pinterest: "Back to \(platform.label)"
        case .website, .manual, .screenshot:                     "Done"
        }
    }

    /// The dish name so far. `nil` shows skeleton bars.
    var dishTitle: String? {
        switch state {
        case .importing(let progress): progress.title?.trimmedOrNil
        case .saved(let draft):        draft.title?.trimmedOrNil
        case .failed:                  nil
        }
    }

    /// "In your recipes. 35 min, 4 servings, 8 of the 12 ingredients already in
    /// your kitchen." Every clause is dropped unless it's actually known, so the
    /// line never pads itself with zeroes.
    func savedSummary(for draft: ImportedRecipeDraft) -> String {
        var parts: [String] = []
        let minutes = (draft.prepMinutes ?? 0) + (draft.cookMinutes ?? 0)
        if minutes > 0 { parts.append("\(minutes) min") }
        if let servings = draft.servings, servings > 0 {
            parts.append("\(servings) serving\(servings == 1 ? "" : "s")")
        }
        if let coverage = PantrySnapshot.coverage(forIngredientLines: draft.ingredientLines),
           coverage.owned > 0 {
            parts.append("\(coverage.owned) of the \(coverage.total) ingredients already in your kitchen")
        } else if !draft.ingredientLines.isEmpty {
            parts.append("\(draft.ingredientLines.count) ingredients")
        }

        guard !parts.isEmpty else { return "In your recipes." }
        return "In your recipes. " + parts.joined(separator: ", ") + "."
    }
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
