import XCTest
@testable import Glutt

/// Pinterest's web API is undocumented, so the payload shape is not a contract.
/// The fixture is a real `PinResource` response, trimmed to the fields the
/// parser reads, so that when Pinterest moves something the failure points at
/// the field instead of at "import is broken".
final class PinterestImportTests: XCTestCase {

    private func fixture() throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "pinterestPin", withExtension: "json"),
            "pinterestPin.json missing from the test bundle")
        return try Data(contentsOf: url)
    }

    // MARK: - canHandle

    func testHandlesPinterestDomainsIncludingCountryVariants() {
        for link in [
            "https://www.pinterest.com/pin/364932376102173088/",
            "https://pinterest.ca/pin/364932376102173088/",
            "https://br.pinterest.com/pin/364932376102173088/",
            "https://www.pinterest.co.uk/pin/364932376102173088/",
            "https://pin.it/2xKp9Qm",
        ] {
            XCTAssertTrue(PinterestImport.canHandle(URL(string: link)!), link)
        }
    }

    func testDoesNotHandleOtherHosts() {
        for link in ["https://www.tiktok.com/@a/video/1", "https://seriouseats.com/x"] {
            XCTAssertFalse(PinterestImport.canHandle(URL(string: link)!), link)
        }
    }

    // MARK: - Pin id

    func testPinIDFromPlainPinURL() {
        let url = URL(string: "https://www.pinterest.com/pin/364932376102173088/")!
        XCTAssertEqual(PinterestImport.pinID(from: url), "364932376102173088")
    }

    /// Some shares produce `/pin/<slug>--<id>/`.
    func testPinIDFromSluggedPinURL() {
        let url = URL(string: "https://www.pinterest.com/pin/chicken-tikka-masala--364932376102173088/")!
        XCTAssertEqual(PinterestImport.pinID(from: url), "364932376102173088")
    }

    func testPinIDIsNilForBoardsAndProfiles() {
        for link in [
            "https://www.pinterest.com/someone/dinner-ideas/",
            "https://www.pinterest.com/someone/",
            "https://www.pinterest.com/",
        ] {
            XCTAssertNil(PinterestImport.pinID(from: URL(string: link)!), link)
        }
    }

    /// A short link has no id in it at all — it has to be redirected first, and
    /// reporting one anyway would send a garbage id to the API.
    func testShortLinkCarriesNoPinID() {
        let url = URL(string: "https://pin.it/2xKp9Qm")!
        XCTAssertTrue(PinterestImport.isShortLink(url))
        XCTAssertNil(PinterestImport.pinID(from: url))
    }

    // MARK: - Payload parsing

    func testParsesTitleDescriptionAndImageFromRealPayload() throws {
        let pin = try XCTUnwrap(PinterestImport.parsePin(json: try fixture()))
        XCTAssertEqual(pin.title, "Best Ever Chicken Tikka Masala – Better Than Takeout")
        XCTAssertNotNil(pin.description)
        XCTAssertTrue(pin.description!.contains("yogurt"), "Expected the ingredient list in the description")
        XCTAssertEqual(pin.imageURL?.hasPrefix("https://i.pinimg.com/"), true)
    }

    func testParseReturnsNilForUnrelatedJSON() {
        XCTAssertNil(PinterestImport.parsePin(json: Data(#"{"hello":"world"}"#.utf8)))
        XCTAssertNil(PinterestImport.parsePin(json: Data("not json".utf8)))
    }

    /// `orig` is the full-resolution rendition and often omits `width`, so
    /// picking by measured width alone would quietly settle for a thumbnail.
    func testBestImagePrefersOriginalOverSizedRenditions() {
        let images: [String: Any] = [
            "236x": ["url": "https://i.pinimg.com/236x/a.jpg", "width": 236],
            "1200x": ["url": "https://i.pinimg.com/1200x/a.jpg", "width": 1200],
            "orig": ["url": "https://i.pinimg.com/originals/a.png"],
        ]
        XCTAssertEqual(
            PinterestImport.bestImageURL(images), "https://i.pinimg.com/originals/a.png")
    }

    func testBestImageFallsBackToWidestWhenNoOriginal() {
        let images: [String: Any] = [
            "236x": ["url": "https://i.pinimg.com/236x/a.jpg", "width": 236],
            "736x": ["url": "https://i.pinimg.com/736x/a.jpg", "width": 736],
        ]
        XCTAssertEqual(PinterestImport.bestImageURL(images), "https://i.pinimg.com/736x/a.jpg")
    }

    func testBestImageIsNilWhenAbsent() {
        XCTAssertNil(PinterestImport.bestImageURL(nil))
        XCTAssertNil(PinterestImport.bestImageURL([String: Any]()))
    }

    // MARK: - Draft mapping

    func testDraftCarriesPlatformSourceAndParsedIngredients() throws {
        let pin = try XCTUnwrap(PinterestImport.parsePin(json: try fixture()))
        let source = URL(string: "https://www.pinterest.com/pin/364932376102173088/")!
        let draft = PinterestImport.draft(from: pin, sourceURL: source)

        XCTAssertEqual(draft.platform, .pinterest)
        XCTAssertEqual(draft.sourceURL, source.absoluteString)
        XCTAssertEqual(draft.title, "Best Ever Chicken Tikka Masala – Better Than Takeout")
        XCTAssertNotNil(draft.imageURL)
        XCTAssertFalse(
            draft.ingredientLines.isEmpty,
            "A pin description with a full ingredient list should parse into lines")
    }

    /// A pin whose description is a one-liner still imports — it just says so,
    /// rather than failing and losing the picture and the title.
    func testThinDescriptionStillProducesAUsableDraftWithAnIssue() {
        var pin = PinterestImport.Pin()
        pin.title = "Sunday Roast"
        pin.description = "So good!"
        pin.imageURL = "https://i.pinimg.com/originals/a.jpg"
        let draft = PinterestImport.draft(
            from: pin, sourceURL: URL(string: "https://www.pinterest.com/pin/1/")!)

        XCTAssertEqual(draft.title, "Sunday Roast")
        XCTAssertEqual(draft.imageURL, "https://i.pinimg.com/originals/a.jpg")
        XCTAssertTrue(draft.ingredientLines.isEmpty)
        XCTAssertFalse(draft.issues.isEmpty, "The user should be told the pin had no recipe")
    }

    func testPlatformDetectionRoutesPinterestURLs() {
        XCTAssertEqual(
            ImportedRecipeDraft.platform(for: URL(string: "https://www.pinterest.com/pin/1/")!),
            .pinterest)
        XCTAssertEqual(
            ImportedRecipeDraft.platform(for: URL(string: "https://pin.it/abc")!), .pinterest)
    }
}
