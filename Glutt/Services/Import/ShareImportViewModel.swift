import Foundation
import Observation

/// Drives the share-sheet import UI: run the pipeline, show an editable preview,
/// then write the finished recipe to the app-group inbox on save.
@MainActor
@Observable
final class ShareImportViewModel {

    enum State {
        case importing(String)
        case preview
        case saved
        case failed(String)
    }

    private(set) var state: State = .importing("Reading the recipe…")
    private(set) var draft: ImportedRecipeDraft?

    /// Quick edits, seeded from the draft once it's ready.
    var editableTitle: String = ""
    var editableServings: Int = 2

    private let urlString: String
    private let deps: ImportPipeline.Dependencies
    private let inbox: ImportInbox

    init(urlString: String,
         deps: ImportPipeline.Dependencies = .live,
         inbox: ImportInbox = ImportInbox()) {
        self.urlString = urlString
        self.deps = deps
        self.inbox = inbox
    }

    func start() async {
        do {
            let draft = try await ImportPipeline.run(urlString: urlString, deps: deps) { [weak self] message in
                guard let self, case .importing = self.state else { return }
                self.state = .importing(message)
            }
            self.draft = draft
            self.editableTitle = draft.title ?? ""
            self.editableServings = draft.servings ?? 2
            self.state = .preview
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    /// Applies the quick edits and queues the recipe. Returns the draft id so the
    /// host controller can build the `glutt://recipe?import=` link for "View recipe".
    @discardableResult
    func save() -> UUID? {
        guard var draft else { return nil }
        let trimmed = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { draft.title = trimmed }
        draft.servings = editableServings
        inbox.append(draft)
        self.draft = draft
        state = .saved
        return draft.id
    }
}
