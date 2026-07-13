import XCTest
@testable import Glutt

final class DietaryRuleTests: XCTestCase {
    func testNewCasesExistWithLabels() {
        XCTAssertEqual(DietaryRule.nutFree.label, "Nut-free")
        XCTAssertEqual(DietaryRule.keto.label, "Keto")
        XCTAssertEqual(DietaryRule.nutFree.rawValue, "nutFree")
        XCTAssertEqual(DietaryRule.keto.rawValue, "keto")
    }
}
