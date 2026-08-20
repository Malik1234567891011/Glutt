import Foundation
import NetworkExtension

/// Which Wi-Fi network the phone is actually on.
///
/// Exists because the glasses take it. Since 0.8 the toolkit reaches the camera
/// by making the phone join an access point the glasses host, which has no route
/// to the internet, so iOS moves everything else to cellular for the duration.
/// That is not a bug to fix — there is no transport option anywhere in the SDK,
/// and `capturePhoto` hangs off a `Stream` so even a single still needs the link
/// — but it decides the design, because Polly's voice session needs the network
/// the camera just took, and plenty of kitchens have poor signal.
///
/// The question that matters is therefore not *whether* the phone leaves home
/// Wi-Fi but *how long for*: if closing the camera hands the network straight
/// back, vision can be something Chef opens when she needs it. Watching Settings
/// during a run is unreliable and unrecordable, so the app reports it instead.
///
/// Needs `com.apple.developer.networking.wifi-info`, which the app already
/// carries for the join itself.
enum NetworkProbe {
    /// The current SSID, or nil when there is no Wi-Fi association at all
    /// (which, mid-look, is a perfectly normal answer).
    static func currentSSID() async -> String? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network?.ssid)
            }
        }
    }

    /// "wifi: Malik's Wi-Fi" / "wifi: none (cellular)".
    ///
    /// Named for a log line rather than a UI string: this is diagnostic and is
    /// never shown to a cook.
    static func describeCurrent() async -> String {
        guard let ssid = await currentSSID() else { return "wifi: none (cellular)" }
        return "wifi: \(ssid)"
    }

    /// Whether the phone is sitting on an access point hosted by the glasses.
    ///
    /// Matched by name because there is nothing else to match on: the SDK does
    /// not say which network it joined, and the SSID is the only thing it
    /// leaves behind.
    static func isOnGlassesNetwork(_ ssid: String?) -> Bool {
        guard let ssid = ssid?.lowercased() else { return false }
        return ["meta", "ray-ban", "rayban", "oakley"].contains { ssid.contains($0) }
    }
}
