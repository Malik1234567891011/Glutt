import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class HowToGeneratorTests: XCTestCase {

    func testGenerateBuildsBasicsLessonFromJSON() async throws {
        let fake = FakeLLMTransport(replyJSON: """
        {
          "ok": true,
          "title": "How to Cook Rice",
          "summary": "Fluffy separate grains, not mush.",
          "servings": 2,
          "prepMinutes": 2,
          "cookMinutes": 20,
          "ingredients": ["1 cup white rice", "1.5 cups water", "pinch of salt (optional)"],
          "steps": [
            "Rinse the rice in a bowl until the water runs mostly clear — look for cloudy water turning clearer.",
            "Add rice, water, and salt to a pot with a lid. Medium-high until you see a lively boil at the edges.",
            "When it boils, lid on, heat to low. Listen for a quiet simmer, not a hard rattle.",
            "About 15 minutes: peek once — water should be absorbed, surface steamy with little steam vents.",
            "Off heat, lid on 5 more minutes. Fluff with a fork — grains should separate, not gluey.",
            "Taste: tender with a tiny bite. If still hard and wet, low heat 2 more minutes lid on."
          ],
          "notes": "Too mushy usually means too much water or lid lifted too often. Leftover rice: cool fast, fridge within 1 hour.",
          "tags": ["rice", "technique"],
          "calories": 200,
          "proteinGrams": 4,
          "carbGrams": 44,
          "fatGrams": 0
        }
        """)

        let recipe = try await HowToGenerator.generate(
            request: "how to cook rice",
            client: fake.client()
        )

        XCTAssertTrue(recipe.isCookingBasic)
        XCTAssertEqual(recipe.title, "How to Cook Rice")
        XCTAssertEqual(recipe.sourceCreator, "Glutt Basics")
        XCTAssertEqual(recipe.steps.count, 6)
        XCTAssertTrue(fake.system.contains("LOOK FOR") || fake.system.contains("visual cues")
                      || fake.system.localizedCaseInsensitiveContains("sensory"))
        XCTAssertTrue(fake.user.contains("how to cook rice"))
        XCTAssertTrue(recipe.ingredients.contains { $0.isOptional })
    }

    func testRejectsNonCookingRequest() async throws {
        let fake = FakeLLMTransport(replyJSON: """
        {"ok": false, "rejectReason": "That’s not a cooking skill — try “how to scramble eggs.”"}
        """)

        do {
            _ = try await HowToGenerator.generate(request: "how to fix my car", client: fake.client())
            XCTFail("expected reject")
        } catch let error as HowToGenerator.GenerateError {
            if case .rejected(let reason) = error {
                XCTAssertTrue(reason.localizedCaseInsensitiveContains("cooking"))
            } else {
                XCTFail("wrong error \(error)")
            }
        }
    }

    func testEmptyRequestFails() async {
        do {
            _ = try await HowToGenerator.generate(request: "   ", client: FakeLLMTransport().client())
            XCTFail("expected empty")
        } catch let error as HowToGenerator.GenerateError {
            XCTAssertEqual(error, .emptyRequest)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

extension HowToGenerator.GenerateError: Equatable {
    public static func == (lhs: HowToGenerator.GenerateError, rhs: HowToGenerator.GenerateError) -> Bool {
        switch (lhs, rhs) {
        case (.notConfigured, .notConfigured),
             (.emptyRequest, .emptyRequest),
             (.failed, .failed):
            return true
        case (.rejected(let a), .rejected(let b)):
            return a == b
        default:
            return false
        }
    }
}
