import XCTest
@testable import Glutt

final class RedditImportTests: XCTestCase {

    // MARK: - URL detection

    func testCanHandleRedditHosts() {
        XCTAssertTrue(RedditImport.canHandle(URL(string: "https://www.reddit.com/r/recipes/comments/abc/foo/")!))
        XCTAssertTrue(RedditImport.canHandle(URL(string: "https://old.reddit.com/r/recipes/comments/abc/foo/")!))
        XCTAssertTrue(RedditImport.canHandle(URL(string: "https://redd.it/abc123")!))
        XCTAssertTrue(RedditImport.canHandle(URL(string: "https://www.redd.it/abc123")!))
        XCTAssertFalse(RedditImport.canHandle(URL(string: "https://www.tiktok.com/@x/video/1")!))
        XCTAssertFalse(RedditImport.canHandle(URL(string: "https://www.allrecipes.com/recipe/1")!))
    }

    func testPlatformDetection() {
        XCTAssertEqual(
            ImportedRecipeDraft.platform(for: URL(string: "https://www.reddit.com/r/recipes/comments/abc/")!),
            .reddit
        )
        XCTAssertEqual(
            ImportedRecipeDraft.platform(for: URL(string: "https://redd.it/abc")!),
            .reddit
        )
    }

    func testClassifyPostVsSubreddit() {
        XCTAssertEqual(
            RedditImport.classify(URL(string: "https://www.reddit.com/r/recipes/comments/1jyzw2w/sticky/")!),
            .post
        )
        XCTAssertEqual(
            RedditImport.classify(URL(string: "https://www.reddit.com/r/recipes/")!),
            .subreddit
        )
        XCTAssertEqual(
            RedditImport.classify(URL(string: "https://www.reddit.com/r/recipes/hot")!),
            .subreddit
        )
        XCTAssertEqual(
            RedditImport.classify(URL(string: "https://www.reddit.com/r/recipes/top/?t=week")!),
            .subreddit
        )
    }

    func testPostIDAndJSONURL() {
        let url = URL(string: "https://www.reddit.com/r/recipes/comments/1jyzw2w/sticky_sriracha_chicken_noodles/?utm=1")!
        XCTAssertEqual(RedditImport.postID(from: url), "1jyzw2w")
        let json = RedditImport.jsonURL(forPost: url)
        XCTAssertEqual(json?.path, "/r/recipes/comments/1jyzw2w/sticky_sriracha_chicken_noodles.json")
        XCTAssertTrue(json?.query?.contains("raw_json=1") == true)
        XCTAssertEqual(RedditImport.postID(from: URL(string: "https://redd.it/1jyzw2w")!), "1jyzw2w")
        XCTAssertEqual(
            RedditImport.classify(URL(string: "https://redd.it/1jyzw2w")!),
            .post
        )
    }

    // MARK: - Listing → draft

    func testDraftFromSelftextListing() throws {
        let listing = """
        [
          {"kind":"Listing","data":{"children":[{
            "kind":"t3","data":{
              "title":"Sticky Sriracha Chicken Noodles",
              "author":"noodle_chef",
              "selftext":"Ingredients:\\n600g chicken breast\\n2 tbsp cooking oil\\n4 tbsp soy sauce\\n3 tbsp hoisin sauce\\n\\nInstructions:\\n1. Cook the chicken until golden.\\n2. Make the sauce and toss with noodles.",
              "permalink":"/r/recipes/comments/1jyzw2w/sticky/",
              "url":"https://www.reddit.com/r/recipes/comments/1jyzw2w/sticky/",
              "is_self":true,
              "subreddit":"recipes",
              "thumbnail":"self"
            }
          }]}},
          {"kind":"Listing","data":{"children":[
            {"kind":"t1","data":{"author":"helper","body":"Looks great!","score":2,"is_submitter":false,"stickied":false}}
          ]}}
        ]
        """.data(using: .utf8)!

        let payload = try RedditImport.payload(fromRedditListing: listing)
        XCTAssertEqual(payload.title, "Sticky Sriracha Chicken Noodles")
        XCTAssertEqual(payload.author, "noodle_chef")
        XCTAssertTrue(payload.selftext.contains("soy sauce"))

        let draft = RedditImport.draft(
            from: payload,
            sourceURL: URL(string: "https://www.reddit.com/r/recipes/comments/1jyzw2w/sticky/")!
        )
        XCTAssertEqual(draft.platform, .reddit)
        XCTAssertEqual(draft.creator, "u/noodle_chef")
        XCTAssertEqual(draft.title, "Sticky Sriracha Chicken Noodles")
        XCTAssertFalse(draft.ingredientLines.isEmpty, "should parse ingredients from selftext")
        XCTAssertFalse(draft.stepTexts.isEmpty, "should parse steps from selftext")
        XCTAssertTrue(draft.tags.contains("r/recipes"))
    }

    func testRecipeTextPrefersOPCommentWhenSelftextThin() {
        let payload = RedditImport.Payload(
            title: "My grandma's chili (photo)",
            author: "cook",
            selftext: "Recipe in comments!",
            permalink: "/r/recipes/comments/abc/chili/",
            url: "https://i.redd.it/x.jpg",
            isSelf: false,
            imageURL: "https://i.redd.it/x.jpg",
            subreddit: "recipes",
            comments: [
                RedditImport.Comment(
                    author: "rando",
                    body: "Looks tasty",
                    score: 50,
                    isSubmitter: false,
                    stickied: false
                ),
                RedditImport.Comment(
                    author: "cook",
                    body: """
                    Ingredients:
                    1 lb ground beef
                    1 onion, diced
                    2 tbsp chili powder
                    1 can tomatoes

                    Instructions:
                    1. Brown the beef with the onion.
                    2. Stir in chili powder and tomatoes. Simmer 20 minutes.
                    """,
                    score: 12,
                    isSubmitter: true,
                    stickied: true
                ),
            ]
        )
        let text = RedditImport.recipeText(from: payload)
        XCTAssertTrue(text.contains("ground beef"))
        XCTAssertTrue(text.contains("[OP]"))

        let draft = RedditImport.draft(
            from: payload,
            sourceURL: URL(string: "https://www.reddit.com/r/recipes/comments/abc/chili/")!
        )
        XCTAssertGreaterThanOrEqual(draft.ingredientLines.count, 3)
    }

    func testProxyJSONDecoding() throws {
        let json = """
        {"title":"Easy Soup","author":"a","selftext":"Ingredients:\\n1 onion\\n2 cups stock\\n\\nInstructions:\\n1. Simmer.","permalink":"/r/x/comments/1/","url":"https://reddit.com","is_self":true,"image_url":null,"subreddit":"recipes","comments":[]}
        """.data(using: .utf8)!
        let payload = try RedditImport.payload(fromProxyJSON: json)
        XCTAssertEqual(payload.title, "Easy Soup")
        let draft = RedditImport.draft(
            from: payload,
            sourceURL: URL(string: "https://www.reddit.com/r/recipes/comments/1/easy/")!
        )
        XCTAssertEqual(draft.platform, .reddit)
    }

    func testImportFromUsesFetchedJSONAndRejectsSubreddit() async throws {
        let listing = """
        [{"kind":"Listing","data":{"children":[{"kind":"t3","data":{
          "title":"Garlic Pasta","author":"chef","selftext":"Ingredients:\\n200g pasta\\n4 cloves garlic\\n2 tbsp butter\\n\\nInstructions:\\n1. Boil pasta.\\n2. Saute garlic in butter and toss.",
          "permalink":"/r/recipes/comments/zzz/garlic/","url":"https://www.reddit.com/r/recipes/comments/zzz/garlic/",
          "is_self":true,"subreddit":"recipes"
        }}]}},{"kind":"Listing","data":{"children":[]}}]
        """.data(using: .utf8)!

        let transport: RedditImport.Transport = { request in
            let url = request.url!.absoluteString
            if url.contains(".json") {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (listing, response)
            }
            XCTFail("unexpected request \(url)")
            throw URLError(.badURL)
        }

        let draft = try await RedditImport.importFrom(
            url: URL(string: "https://www.reddit.com/r/recipes/comments/zzz/garlic_pasta/")!,
            transport: transport,
            followExternal: { _ in throw ImportError.fetchFailed }
        )
        XCTAssertEqual(draft.platform, .reddit)
        XCTAssertEqual(draft.title, "Garlic Pasta")
        XCTAssertFalse(draft.ingredientLines.isEmpty)

        do {
            _ = try await RedditImport.importFrom(
                url: URL(string: "https://www.reddit.com/r/recipes/")!,
                transport: transport
            )
            XCTFail("subreddit should fail")
        } catch ImportError.redditNeedsPost {
            // expected
        }
    }

    func testFollowsExternalRecipeLinkWhenSelftextEmpty() async throws {
        let listing = """
        [{"kind":"Listing","data":{"children":[{"kind":"t3","data":{
          "title":"Best Carbonara","author":"linky","selftext":"",
          "permalink":"/r/recipes/comments/eee/carbonara/",
          "url":"https://www.example.com/carbonara","is_self":false,"subreddit":"recipes"
        }}]}},{"kind":"Listing","data":{"children":[]}}]
        """.data(using: .utf8)!

        let transport: RedditImport.Transport = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (listing, response)
        }

        let draft = try await RedditImport.importFrom(
            url: URL(string: "https://www.reddit.com/r/recipes/comments/eee/carbonara/")!,
            transport: transport,
            followExternal: { url in
                XCTAssertEqual(url.host, "www.example.com")
                var linked = ImportedRecipeDraft()
                linked.title = "Carbonara from site"
                linked.ingredientLines = ["100g spaghetti", "2 eggs", "50g pecorino"]
                linked.stepTexts = ["Boil pasta", "Toss with egg and cheese"]
                linked.platform = .website
                return linked
            }
        )
        XCTAssertEqual(draft.platform, .reddit, "keep Reddit as the share source")
        XCTAssertEqual(draft.ingredientLines.count, 3)
        XCTAssertTrue(draft.issues.contains(where: { $0.contains("linked page") }))
    }
}
