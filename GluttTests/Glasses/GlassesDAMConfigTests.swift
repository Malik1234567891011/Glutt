import XCTest
@testable import Glutt

/// What camera flow and transport Glutt actually ships, asserted rather than
/// believed.
///
/// This file exists because of a wrong answer that was expensive. `project.yml`
/// carried a comment saying `MWDAT > DAMEnabled` "is not read at all in 0.8.0
/// (the string does not appear in either framework binary)", and the product was
/// configured around that. The evidence was `strings` run over the xcframework,
/// which does not enumerate Swift string literals and so cannot demonstrate a
/// key's absence. An empty grep and a key that genuinely is not read look
/// identical, and only one of those was true.
///
/// The version note was backwards too. 0.9's changelog removes support for
/// opting out of DAM and says the key "is ignored" — which is a statement that
/// it was honoured in 0.8, the version we link.
///
/// What it cost: on discussion #226 a Meta engineer named Bluetooth Classic
/// **with DAM enabled** as a frame-dropping combination, and BTC plus DAM is
/// precisely what an app inherits by upgrading from 0.7 to 0.8 without touching
/// its plist. Glutt sat in that combination through every stalled cook.
///
/// Both facts are decided by Info.plist keys that no Swift file mentions, so
/// nothing in a code review would ever surface a regression. These assertions
/// are the only thing that would.
final class GlassesDAMConfigTests: XCTestCase {
    private func flow() throws -> GlassesSupport.CameraFlow {
        try XCTUnwrap(GlassesSupport.shared.cameraFlow, "Configuration could not parse the app's own bundle.")
    }

    private func usesDAM(_ mwdat: [String: Any]) throws -> Bool {
        try XCTUnwrap(GlassesSupport.usesDAM(infoDictionary: [
            "CFBundleIdentifier": "com.omarlahmimi.glutt",
            "CFBundleName": "Glutt",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "MWDAT": mwdat,
        ]))
    }

    /// The control, and the assertion that actually carries the weight. An SDK
    /// that ignores the key would pass `testGluttShipsWithDAMOff` and fail this.
    func testTheToolkitActuallyReadsTheKey() throws {
        XCTAssertTrue(
            try usesDAM(["AppLinkURLScheme": "glutt-wearables://"]),
            "DAM is meant to default to on in 0.8 when the key is absent. If this is false the SDK is not "
                + "reading the key at all and the opt-out below is decorative.")
        XCTAssertFalse(try usesDAM(["AppLinkURLScheme": "glutt-wearables://", "DAMEnabled": false]))
        XCTAssertTrue(try usesDAM(["AppLinkURLScheme": "glutt-wearables://", "DAMEnabled": true]))
    }

    /// The claim, stated so it can fail.
    func testGluttShipsWithDAMOff() throws {
        XCTAssertFalse(
            try flow().usesDAM,
            "Glutt is running the DAM camera flow. Over Bluetooth that is Meta's own named cause of silent "
                + "frame-delivery death (discussion #226). Restore MWDAT > DAMEnabled = false in project.yml. "
                + "If the SDK was bumped to 0.9 the opt-out is gone entirely and the stall comes back with it.")
    }

    /// The transport half. Removing the MFi keys is what hands the camera to the
    /// glasses' softAP, which takes the cook's phone off Wi-Fi for the whole
    /// session and puts Chef's voice on cellular.
    func testGluttHoldsTheCameraOnBluetooth() throws {
        XCTAssertTrue(
            try flow().declaresMFiAccessory,
            "UISupportedExternalAccessoryProtocols no longer declares com.meta.ar.wearable, so the camera "
                + "will fall back to the glasses' Wi-Fi network and the phone loses its internet mid-cook.")
    }
}
