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
            cleanUp: { $0 }, reconstruct: { $0 }, inferSteps: { $0 },
            transcribe: { _, _ in (nil, nil) },
            compileFromSpeech: { d, _ in d },
            verifySpeech: { d, _ in d }
        )
    }

    private func deps(throwing error: Error) -> ImportPipeline.Dependencies {
        ImportPipeline.Dependencies(
            fetch: { _ in throw error },
            wouldImprove: { _ in false },
            cleanUp: { $0 }, reconstruct: { $0 }, inferSteps: { $0 },
            transcribe: { _, _ in (nil, nil) },
            compileFromSpeech: { d, _ in d },
            verifySpeech: { d, _ in d }
        )
    }

    func testSuccessfulImportLandsInPreviewSeededWithEdits() async {
        var draft = ImportedRecipeDraft()
        draft.title = "Peanut Noodles"
        draft.servings = 4
        let inbox = ImportInbox(defaults: defaults)
        let vm = ShareImportViewModel(urlString: "x", deps: deps(returning: draft), inbox: inbox)
        await vm.start()

        // No review step: a finished import is already in the inbox.
        guard case .saved(let saved) = vm.state else { return XCTFail("expected saved, got \(vm.state)") }
        XCTAssertEqual(saved.title, "Peanut Noodles")
        XCTAssertEqual(vm.dishTitle, "Peanut Noodles")
        let queued = inbox.drain()
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.title, "Peanut Noodles")
        XCTAssertEqual(queued.first?.servings, 4)
        XCTAssertEqual(queued.first?.id, saved.id)
    }

    func testKeepLinkQueuesAStubCarryingTheSourceURL() async {
        let inbox = ImportInbox(defaults: defaults)
        let vm = ShareImportViewModel(urlString: "https://www.instagram.com/reel/abc",
                                      deps: deps(throwing: ImportError.nothingFound), inbox: inbox)
        await vm.start()
        let id = vm.keepLink()

        let queued = inbox.drain()
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.id, id)
        XCTAssertEqual(queued.first?.sourceURL, "https://www.instagram.com/reel/abc")
        XCTAssertEqual(queued.first?.platform, .instagram)
    }

    func testHeaderNeverNamesTheSourceButTheReturnActionDoes() {
        let vm = ShareImportViewModel(urlString: "https://vm.tiktok.com/ZGabc/",
                                      deps: deps(returning: ImportedRecipeDraft()),
                                      inbox: ImportInbox(defaults: defaults))
        XCTAssertEqual(vm.platform, .tiktok)
        XCTAssertEqual(vm.headerLabel, "Saving a recipe")
        XCTAssertEqual(vm.returnActionLabel, "Back to TikTok")
    }

    /// "Back to Website" would name nothing, so a plain link gets a plain label.
    func testReturnActionStaysGenericWhenTheLinkNamesNoApp() {
        let vm = ShareImportViewModel(urlString: "https://smittenkitchen.com/soup",
                                      deps: deps(returning: ImportedRecipeDraft()),
                                      inbox: ImportInbox(defaults: defaults))
        XCTAssertEqual(vm.platform, .website)
        XCTAssertEqual(vm.returnActionLabel, "Done")
    }

    func testFailedImportLandsInFailedState() async {
        let vm = ShareImportViewModel(urlString: "x", deps: deps(throwing: ImportError.fetchFailed),
                                      inbox: ImportInbox(defaults: defaults))
        await vm.start()
        guard case .failed(let reason) = vm.state else { return XCTFail("expected failed, got \(vm.state)") }
        XCTAssertEqual(reason, ImportPipeline.failureReason(for: ImportError.fetchFailed))
        XCTAssertEqual(vm.headerLabel, "Could not read it")
        XCTAssertTrue(inbox().drain().isEmpty, "a failed import must not queue anything on its own")
    }

    private func inbox() -> ImportInbox { ImportInbox(defaults: defaults) }

    func testSharedImageUsedWhenNoScrapedThumbnail() async {
        var draft = ImportedRecipeDraft()
        draft.title = "Reel Recipe"
        draft.imageURL = nil                       // nothing scrapable (e.g. Instagram)
        let shared = Data([0xFF, 0xD8, 0xFF])       // stand-in JPEG bytes
        let vm = ShareImportViewModel(urlString: "x", deps: deps(returning: draft),
                                      inbox: ImportInbox(defaults: defaults), sharedImageData: shared)
        await vm.start()
        XCTAssertEqual(vm.draft?.imageData, shared, "shared image should fill in when no thumbnail was scraped")
    }

    func testSharedImageIgnoredWhenThumbnailScraped() async {
        var draft = ImportedRecipeDraft()
        draft.title = "TikTok Recipe"
        draft.imageURL = "https://cdn.example.com/thumb.jpg"   // oembed/og thumbnail present
        let vm = ShareImportViewModel(urlString: "x", deps: deps(returning: draft),
                                      inbox: ImportInbox(defaults: defaults), sharedImageData: Data([0xFF, 0xD8]))
        await vm.start()
        XCTAssertNil(vm.draft?.imageData, "a scraped thumbnail should win over the shared image")
        XCTAssertEqual(vm.draft?.imageURL, "https://cdn.example.com/thumb.jpg")
    }
}
