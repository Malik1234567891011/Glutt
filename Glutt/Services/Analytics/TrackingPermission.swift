import AppTrackingTransparency
import Foundation

/// The App Tracking Transparency ask, and the only place in Glutt that touches
/// it.
///
/// What the answer actually buys: authorized means Meta gets the IDFA and can
/// say which ad set and which creative produced a trial. Anything else and the
/// Facebook SDK falls back to SKAdNetwork plus Aggregated Event Measurement,
/// which is real but campaign-level, delayed and modeled. Nothing inside the
/// app changes either way, which is what the Info.plist string promises.
///
/// Nobody has to answer twice: iOS stores the decision, so every call after the
/// first returns the stored status without showing anything. Users who
/// onboarded before this shipped are never asked, deliberately. They were not
/// acquired by an ad, so there is no campaign for their answer to inform.
enum TrackingPermission {
    /// Shows the prompt if it has never been answered, and returns once it has.
    ///
    /// Callers should `await` this before anything that reports a conversion.
    /// Meta cannot retroactively attribute an event that was logged while the
    /// answer was still unknown, so asking after the paywall would cost the
    /// attribution on the very purchase the campaign is optimizing for.
    static func requestIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }

        let status = await ATTrackingManager.requestTrackingAuthorization()
        Analytics.capture(.trackingPermission, ["status": label(for: status)])
    }

    private static func label(for status: ATTrackingManager.AuthorizationStatus) -> String {
        switch status {
        case .authorized: "authorized"
        case .denied: "denied"
        // Set by a device-level restriction (Screen Time, MDM), not by the user.
        case .restricted: "restricted"
        case .notDetermined: "not_determined"
        @unknown default: "unknown"
        }
    }
}
