import AVFoundation

/// Shared AVAudioSession setup for Polly live cook (WebSocket engine + WebRTC).
///
/// AirPods / Bluetooth headsets need `.allowBluetooth` (HFP) for duplex mic+speaker.
/// We used to omit that and force `.speaker`, which made BT "not work." Now we:
/// - allow HFP so AirPods can own both ends
/// - only override to the built-in speaker when no BT headset is on the route
/// - re-apply that preference on every route change (connect / disconnect)
enum PollyAudioSession {

    /// Category options for a live Polly call.
    /// `.allowBluetooth` = HFP duplex (AirPods mic + speakers).
    /// `.defaultToSpeaker` = prefer loudspeaker over earpiece when on built-in I/O
    /// (ignored once a BT headset is the active route).
    static var categoryOptions: AVAudioSession.CategoryOptions {
        [.allowBluetooth, .defaultToSpeaker]
    }

    /// True when a Bluetooth headset/headphones port is on the current route
    /// (output or input). Used to decide whether to force the phone speaker.
    static func isBluetoothHeadsetConnected(
        route: AVAudioSessionRouteDescription = AVAudioSession.sharedInstance().currentRoute
    ) -> Bool {
        let ports = route.outputs.map(\.portType) + route.inputs.map(\.portType)
        return ports.contains { isBluetoothPort($0) }
    }

    static func isBluetoothPort(_ port: AVAudioSession.Port) -> Bool {
        switch port {
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            return true
        default:
            return false
        }
    }

    /// Apply Polly's playAndRecord + videoChat session. Throws on category/active failure.
    static func configure(active: Bool = true) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .videoChat, options: categoryOptions)
        if active {
            try session.setActive(true)
        }
        applyPreferredOutputPort(on: session)
    }

    /// Prefer AirPods when present; otherwise force the built-in speaker
    /// (kitchen counter phone — not the earpiece).
    static func applyPreferredOutputPort(
        on session: AVAudioSession = .sharedInstance()
    ) {
        if isBluetoothHeadsetConnected(route: session.currentRoute) {
            try? session.overrideOutputAudioPort(.none)
            PollyDebugLog.shared.log("audio: output preference — Bluetooth headset (no speaker override)")
        } else {
            try? session.overrideOutputAudioPort(.speaker)
            PollyDebugLog.shared.log("audio: output preference — built-in speaker")
        }
    }

    /// Compact route string for debug dumps.
    static func routeSummary(
        _ route: AVAudioSessionRouteDescription = AVAudioSession.sharedInstance().currentRoute
    ) -> String {
        let out = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        let inn = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        return "out=[\(out)] in=[\(inn)]"
    }
}
