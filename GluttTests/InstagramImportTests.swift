import XCTest
@testable import Glutt

/// Instagram's embed route is the only unauthenticated surface that carries a
/// post's full caption and a live image URL. The fixture is a trimmed capture of
/// a real response, kept because the payload is triple-escaped — JSON inside a
/// JSON string inside HTML — and that escaping is the part most likely to break
/// silently and take the cover image with it.
final class InstagramImportTests: XCTestCase {

    private func embedFixture() throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "instagramEmbed", withExtension: "html"),
            "instagramEmbed.html missing from the test bundle")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Shortcode

    func testShortcodeFromEveryPermalinkShape() {
        let cases = [
            "https://www.instagram.com/p/CfwXgNprcSA/": "CfwXgNprcSA",
            "https://www.instagram.com/reel/CfwXgNprcSA/": "CfwXgNprcSA",
            "https://www.instagram.com/reels/CfwXgNprcSA/": "CfwXgNprcSA",
            "https://www.instagram.com/tv/CfwXgNprcSA/": "CfwXgNprcSA",
            "https://instagram.com/p/Ab-1_cD/": "Ab-1_cD",
            "https://www.instagram.com/reel/CfwXgNprcSA/?igshid=abc123": "CfwXgNprcSA",
        ]
        for (link, expected) in cases {
            XCTAssertEqual(
                InstagramImport.shortcode(from: URL(string: link)!), expected, link)
        }
    }

    func testShortcodeIsNilForProfilesAndTheFeed() {
        for link in [
            "https://www.instagram.com/nike/",
            "https://www.instagram.com/",
            "https://www.instagram.com/explore/tags/food/",
        ] {
            XCTAssertNil(InstagramImport.shortcode(from: URL(string: link)!), link)
        }
    }

    func testCanHandleRequiresAPostNotJustTheDomain() {
        XCTAssertTrue(
            InstagramImport.canHandle(URL(string: "https://www.instagram.com/p/CfwXgNprcSA/")!))
        XCTAssertFalse(
            InstagramImport.canHandle(URL(string: "https://www.instagram.com/nike/")!))
        XCTAssertFalse(
            InstagramImport.canHandle(URL(string: "https://www.tiktok.com/@a/video/1")!))
    }

    // MARK: - Parsing the embed page

    func testParsesCaptionAndImageFromRealEmbedCapture() throws {
        let parsed = try XCTUnwrap(InstagramImport.parse(embedHTML: try embedFixture()))

        let caption = try XCTUnwrap(parsed.caption, "caption not extracted")
        XCTAssertTrue(
            caption.contains("Circa 72"),
            "Expected the real caption text, got: \(caption.prefix(120))")
        XCTAssertFalse(caption.contains("\\n"), "Escapes should be decoded, not literal")

        let image = try XCTUnwrap(parsed.imageURL, "image not extracted")
        XCTAssertTrue(image.hasPrefix("https://"), image)
        XCTAssertTrue(image.contains("cdninstagram.com"), image)
        XCTAssertFalse(image.contains("\\"), "Escaped slashes should be decoded: \(image)")
    }

    func testParseReturnsNilForAPageWithNeitherCaptionNorImage() {
        XCTAssertNil(InstagramImport.parse(embedHTML: "<html><body>nope</body></html>"))
    }

    // MARK: - Draft mapping

    func testDraftCarriesInstagramPlatformImageAndSource() throws {
        let parsed = try XCTUnwrap(InstagramImport.parse(embedHTML: try embedFixture()))
        let source = URL(string: "https://www.instagram.com/p/CfwXgNprcSA/")!
        let draft = InstagramImport.draft(from: parsed, sourceURL: source)

        XCTAssertEqual(draft.platform, .instagram)
        XCTAssertEqual(draft.sourceURL, source.absoluteString)
        XCTAssertNotNil(draft.title)
        XCTAssertNotNil(
            draft.imageURL,
            "An Instagram import with no cover image is the bug this path exists to fix")
    }

    /// A caption with a real ingredient list should parse into lines, the same
    /// way the TikTok path does.
    func testCaptionWithIngredientsBecomesIngredientLines() {
        var embed = InstagramImport.Embed()
        embed.author = "somecook"
        embed.imageURL = "https://scontent.cdninstagram.com/a.jpg"
        embed.caption = """
        Garlic butter salmon 🐟 my go-to weeknight dinner

        Ingredients
        2 salmon fillets
        3 tablespoons butter
        4 cloves garlic
        1 lemon

        Method
        Sear the salmon skin side down for 4 minutes.
        Add the butter and garlic and baste.
        Finish with lemon.
        """
        let draft = InstagramImport.draft(
            from: embed, sourceURL: URL(string: "https://www.instagram.com/p/A/")!)

        XCTAssertFalse(draft.ingredientLines.isEmpty)
        XCTAssertEqual(draft.creator, "somecook")
        XCTAssertEqual(draft.imageURL, "https://scontent.cdninstagram.com/a.jpg")
    }

    /// The image and title still land even when there's no recipe in the caption,
    /// because a picture and a name beat a blank card.
    func testThinCaptionStillKeepsImageAndFlagsTheGap() {
        var embed = InstagramImport.Embed()
        embed.caption = "dinner tonight 😋"
        embed.imageURL = "https://scontent.cdninstagram.com/b.jpg"
        let draft = InstagramImport.draft(
            from: embed, sourceURL: URL(string: "https://www.instagram.com/reel/B/")!)

        XCTAssertEqual(draft.imageURL, "https://scontent.cdninstagram.com/b.jpg")
        XCTAssertFalse(draft.issues.isEmpty)
    }
}
