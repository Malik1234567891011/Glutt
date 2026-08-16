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

    /// The transport half, and it guards the App Store submission rather than the
    /// picture.
    ///
    /// Declaring `com.meta.ar.wearable` selects the Bluetooth Classic camera,
    /// which is the better transport by every measure we have: first frame in
    /// 1.8s against fifteen, and the phone keeps its own network. It is also an
    /// MFi protocol, so App Review requires Meta to authorise this bundle id on
    /// their Product Plan, and Meta answered our issue #266 on 2026-08-10 saying
    /// they will not and there is no waitlist. Four other apps were rejected for
    /// exactly this string (#74, #83, #149, #217).
    ///
    /// So the key is worth more than it costs only if you never ship. The one
    /// third-party DAT app we found on the App Store, `Keepers`
    /// (com.ggaswint.keepers), runs the Wi-Fi path, which is confirmation from
    /// someone else's shipping build rather than from our reading of a thread.
    ///
    /// Re-add the key the day Meta open publishing, and delete this test with it.
    func testGluttDoesNotDeclareTheMFiProtocol() throws {
        XCTAssertFalse(
            try flow().declaresMFiAccessory,
            "UISupportedExternalAccessoryProtocols declares com.meta.ar.wearable again. That is the MFi "
                + "trigger, and App Review will reject the build with \"the app has not been authorized by "
                + "the accessory manufacturer\" until Meta authorises the bundle id, which they have "
                + "declined to do. The Bluetooth configuration lives on spike/dat-0.8-external-accessory.")
    }
}
