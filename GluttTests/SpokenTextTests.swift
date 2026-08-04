import XCTest
@testable import Glutt

final class SpokenTextTests: XCTestCase {
    /// The lines that provoked this: a real Beef Wellington session where the
    /// voice said "t-b-s-p" and "k-g" out loud.
    func testUnitsFromARealSession() {
        XCTAssertEqual(
            SpokenText.forSpeech(
                "Get the pan smoking hot, then add 2 tbsp olive oil and roll the fillet."),
            "Get the pan smoking hot, then add 2 tablespoons olive oil and roll the fillet.")
        XCTAssertEqual(
            SpokenText.forSpeech("Season the 1 kg beef fillet all over."),
            "Season the 1 kilogram beef fillet all over.")
        XCTAssertEqual(
            SpokenText.forSpeech("Blitz the 500 g chestnut mushrooms to a coarse paste."),
            "Blitz the 500 grams chestnut mushrooms to a coarse paste.")
    }

    func testSingularAndPlural() {
        XCTAssertEqual(SpokenText.forSpeech("1 tbsp"), "1 tablespoon")
        XCTAssertEqual(SpokenText.forSpeech("3 tbsp"), "3 tablespoons")
        XCTAssertEqual(SpokenText.forSpeech("1.5 tsp"), "1.5 teaspoons")
        XCTAssertEqual(SpokenText.forSpeech("1/2 tsp salt"), "half a teaspoon salt")
    }

    func testAbbreviationsNeedNoSpace() {
        XCTAssertEqual(SpokenText.forSpeech("200g flour"), "200 grams flour")
        XCTAssertEqual(SpokenText.forSpeech("30ml water"), "30 milliliters water")
        XCTAssertEqual(SpokenText.forSpeech("2lbs beef"), "2 pounds beef")
        XCTAssertEqual(SpokenText.forSpeech("Rest for 20 mins"), "Rest for 20 minutes")
    }

    func testTemperatures() {
        XCTAssertEqual(SpokenText.forSpeech("Oven at 200°C"), "Oven at 200 degrees Celsius")
        XCTAssertEqual(SpokenText.forSpeech("Oven at 425 F"), "Oven at 425 degrees Fahrenheit")
        XCTAssertEqual(SpokenText.forSpeech("Bake at 180C"), "Bake at 180 degrees Celsius")
        XCTAssertEqual(SpokenText.forSpeech("Chill to 4°"), "Chill to 4 degrees")
    }

    func testFractions() {
        XCTAssertEqual(SpokenText.forSpeech("½ tsp"), "half a teaspoon")
        XCTAssertEqual(SpokenText.forSpeech("1½ tbsp butter"), "1 and a half tablespoons butter")
        XCTAssertEqual(SpokenText.forSpeech("¾ cup"), "three quarters of a cup")
    }

    /// The dangerous half: a normalizer that mangles ordinary words is worse
    /// than one that misses an abbreviation.
    func testOrdinaryWordsAreLeftAlone() {
        XCTAssertEqual(
            SpokenText.forSpeech("Keep going, the big pan is fine and the mincing is done."),
            "Keep going, the big pan is fine and the mincing is done.")
        XCTAssertEqual(
            SpokenText.forSpeech("Sear it until every side takes colour."),
            "Sear it until every side takes colour.")
        XCTAssertEqual(
            SpokenText.forSpeech("2 c flour"), "2 c flour",
            "lowercase c is cups in an American recipe, not Celsius")
        XCTAssertEqual(
            SpokenText.forSpeech("Cut it 2 in from the edge"), "Cut it 2 in from the edge",
            #""in" is a word far more often than it is inches"#)
    }
}
