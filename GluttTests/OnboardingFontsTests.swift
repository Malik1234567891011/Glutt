import XCTest
@testable import Glutt

final class OnboardingFontsTests: XCTestCase {
    func testBundledFontFamiliesAreRegistered() {
        XCTAssertTrue(UIFont.familyNames.contains("Bricolage Grotesque"),
                      "Bricolage Grotesque not registered — check UIAppFonts / bundle")
        XCTAssertTrue(UIFont.familyNames.contains("Nunito"),
                      "Nunito not registered — check UIAppFonts / bundle")
    }

    func testHelpersReturnRequestedFamily() {
        XCTAssertEqual(OnboardingFonts.uiBricolage(19, 600).familyName, "Bricolage Grotesque")
        XCTAssertEqual(OnboardingFonts.uiNunito(13, 700).familyName, "Nunito")
    }
}

final class MaterialSymbolTests: XCTestCase {
    func testEveryGlyphAssetExists() {
        for symbol in MS.allCases {
            XCTAssertNotNil(UIImage(named: symbol.rawValue),
                            "Missing imageset for \(symbol.rawValue)")
        }
    }
}
