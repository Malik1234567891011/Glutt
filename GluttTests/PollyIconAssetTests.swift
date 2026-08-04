import UIKit
import XCTest
@testable import Glutt

/// Guards the vendored Polly icon subset: every imageset the Polly UI references
/// must exist in the app's asset catalog. Catches a forgotten copy step or a
/// renamed imageset before it becomes an invisible button on device.
final class PollyIconAssetTests: XCTestCase {

    /// Tests run hosted inside the Glutt app, so the app's compiled asset
    /// catalog lives in the app bundle — not in the test bundle.
    private let appBundle = Bundle(identifier: "com.malik.glutt") ?? .main

    private let expectedImagesets = [
        "chef-hat", "chef-hat-fill",
        "microphone", "microphone-fill",
        "microphone-slash",
        "video-camera", "video-camera-fill",
        "video-camera-slash",
        "eye", "eye-fill",
        "eye-slash",
        "camera-rotate",
    ]

    func testAllPollyIconAssetsExist() {
        for name in expectedImagesets {
            XCTAssertNotNil(
                UIImage(named: name, in: appBundle, compatibleWith: nil),
                "Missing Phosphor imageset '\(name)' in Assets.xcassets/Phosphor"
            )
        }
    }
}
