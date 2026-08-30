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
        // `.allowBluetoothHFP` is the current spelling of `.allowBluetooth`.
        // Same option, same raw value, renamed in the SDK. HFP is the only
        // Bluetooth profile that carries a microphone, so it is what AirPods
        // need to own both ends of the call.
        return [.allowBluetoothHFP, .defaultToSpeaker]
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
        applyPreferredInput(on: session)
        applyPreferredOutputPort(on: session)
    }

    /// Log what iOS is offering, and otherwise leave the input alone.
    ///
    /// This used to pick a preferred input by matching port names, so that one
    /// particular headset won over whatever else was paired. Nothing does that
    /// now: overriding somebody's own choice of headset is worse than accepting
    /// the system default, and the device it was written for is not part of
    /// this build.
    static func applyPreferredInput(on session: AVAudioSession = .sharedInstance()) {
        let inputs = session.availableInputs ?? []
        guard !inputs.isEmpty else { return }
        let described = inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        PollyDebugLog.shared.log("audio: available inputs [\(described)]")
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
