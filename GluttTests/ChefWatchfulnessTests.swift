import XCTest
@testable import Glutt

final class ChefWatchfulnessTests: XCTestCase {
    private let key = "glutt.polly.watchfulness"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    /// The default has to be the middle one. A cook who never opens the picker
    /// gets a chef who stays quiet unless the dish is at risk, which is the
    /// behaviour that is hardest to be annoyed by.
    func testDefaultIsWatchful() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(ChefWatchfulness.selected, .watchful)
    }

    func testSelectionSurvivesARoundTrip() {
        ChefWatchfulness.selectedID = ChefWatchfulness.perfectionist.rawValue
        XCTAssertEqual(ChefWatchfulness.selected, .perfectionist)
        ChefWatchfulness.selectedID = ChefWatchfulness.handsOff.rawValue
        XCTAssertEqual(ChefWatchfulness.selected, .handsOff)
    }

    /// A level dropped in a later version must not crash every cook of anyone
    /// who had it selected.
    func testAnUnknownStoredLevelFallsBack() {
        UserDefaults.standard.set("michelin-inspector", forKey: key)
        XCTAssertEqual(ChefWatchfulness.selected, .default)
    }

    func testOnlyHandsOffDeclinesToWatch() {
        XCTAssertFalse(ChefWatchfulness.handsOff.watchesUnprompted)
        XCTAssertNil(ChefWatchfulness.handsOff.glanceInterval)
        for level in ChefWatchfulness.allCases where level != .handsOff {
            XCTAssertTrue(level.watchesUnprompted, "\(level.rawValue) should watch")
        }
    }

    /// The stricter the chef, the more often she has to look. If this ever
    /// inverts, the level names stop describing the behaviour.
    func testStricterLevelsLookMoreOften() throws {
        let perfectionist = try XCTUnwrap(ChefWatchfulness.perfectionist.glanceInterval)
        let watchful = try XCTUnwrap(ChefWatchfulness.watchful.glanceInterval)
        XCTAssertLessThan(perfectionist, watchful)
    }

    /// UI copy rule: no dashes as punctuation anywhere a cook can read it.
    func testCopyAvoidsDashPunctuation() {
        for level in ChefWatchfulness.allCases {
            for copy in [level.displayName, level.tagline] {
                XCTAssertFalse(copy.contains("—"), "em dash in \"\(copy)\"")
                XCTAssertFalse(copy.contains("–"), "en dash in \"\(copy)\"")
                XCTAssertFalse(copy.contains(" - "), "spaced hyphen in \"\(copy)\"")
            }
        }
    }
}
