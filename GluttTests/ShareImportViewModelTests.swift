import XCTest
@testable import Glutt

@MainActor
final class ShareImportViewModelTests: XCTestCase {

    private let suiteName = "test.glutt.sharevm"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func deps(returning draft: ImportedRecipeDraft) -> ImportPipeline.Dependencies {
        ImportPipeline.Dependencies(
            fetch: { _ in draft },
            wouldImprove: { _ in false },
            cleanUp: { $0 }, reconstruct: { $0 }, inferSteps: { $0 }
        )
    }

    private func deps(throwing error: Error) -> ImportPipeline.Dependencies {
        ImportPipeline.Dependencies(
            fetch: { _ in throw error },
            wouldImprove: { _ in false },
            cleanUp: { $0 }, reconstruct: { $0 }, inferSteps: { $0 }
        )
    }

    func testSuccessfulImportLandsInPreviewSeededWithEdits() async {
        var draft = ImportedRecipeDraft()
        draft.title = "Peanut Noodles"
        draft.servings = 4
        let vm = ShareImportViewModel(urlString: "x", deps: deps(returning: draft),
                                      inbox: ImportInbox(defaults: defaults))
        await vm.start()

        guard case .preview = vm.state else { return XCTFail("expected preview, got \(vm.state)") }
        XCTAssertEqual(vm.editableTitle, "Peanut Noodles")
        XCTAssertEqual(vm.editableServings, 4)
    }

    func testSaveAppliesEditsWritesToInboxAndReturnsID() async {
        var draft = ImportedRecipeDraft()
        draft.title = "Original"
        draft.servings = 2
        let inbox = ImportInbox(defaults: defaults)
        let vm = ShareImportViewModel(urlString: "x", deps: deps(returning: draft), inbox: inbox)
        await vm.start()

        vm.editableTitle = "My Better Title"
        vm.editableServings = 6
        let id = vm.save()

        guard case .saved = vm.state else { return XCTFail("expected saved, got \(vm.state)") }
        XCTAssertNotNil(id)
        let queued = inbox.drain()
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.title, "My Better Title")
        XCTAssertEqual(queued.first?.servings, 6)
        XCTAssertEqual(queued.first?.id, id)
    }

    func testFailedImportLandsInFailedState() async {
        let vm = ShareImportViewModel(urlString: "x", deps: deps(throwing: ImportError.fetchFailed),
                                      inbox: ImportInbox(defaults: defaults))
        await vm.start()
        guard case .failed(let message) = vm.state else { return XCTFail("expected failed, got \(vm.state)") }
        XCTAssertEqual(message, ImportError.fetchFailed.errorDescription)
    }
}
