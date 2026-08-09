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
        // Same option, same raw value, renamed in the SDK.
        //
        // Dropped entirely when the cook has taken Chef's audio off the glasses,
        // because leaving it in lets iOS route to HFP anyway and the whole point
        // of that switch is a radio with no voice traffic on it. See
        // `PollyAudioLab.micOnGlasses`.
        guard PollyAudioLab.micOnGlasses else { return [.defaultToSpeaker] }
        return [.allowBluetoothHFP, .defaultToSpeaker]
    }

    /// Port names Meta's glasses present themselves under. Matched loosely and
    /// deliberately: Meta ships several frames under different brands, and the
    /// name a given pair reports is not contractual. This only ever decides
    /// which Bluetooth device we prefer, so a miss costs us the preference, not
    /// the audio.
    private static let glassesNameFragments = ["ray-ban", "rayban", "meta", "oakley"]

    /// True when this port looks like Meta glasses on Bluetooth hands-free.
    ///
    /// HFP specifically, because that is the only Bluetooth profile that carries
    /// a microphone. A2DP would give us Polly's voice in the cook's ears and no
    /// way to hear them answer.
    static func isMetaGlassesPort(_ port: AVAudioSessionPortDescription) -> Bool {
        guard port.portType == .bluetoothHFP else { return false }
        let name = port.portName.lowercased()
        return glassesNameFragments.contains { name.contains($0) }
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

    /// Choose the input rather than accepting whatever iOS picked.
    ///
    /// Until the glasses existed there was only ever one plausible Bluetooth
    /// device on a cook's head, so never calling `setPreferredInput` was fine.
    /// With AirPods in a pocket and glasses on a face, both paired, the system
    /// default is a coin toss, and losing it means Polly listens through the
    /// wrong microphone for the whole session.
    ///
    /// Glasses win when present. Anything else is left alone: overriding the
    /// user's own choice of headset would be worse than the coin toss.
    /// Selecting an HFP input also routes output to the matching HFP output, so
    /// this settles both ends at once.
    static func applyPreferredInput(on session: AVAudioSession = .sharedInstance()) {
        let inputs = session.availableInputs ?? []
        // Route names vary by firmware and pairing. Log the lot: when a pair of
        // glasses is not picked up, this is the only thing that says why.
        if !inputs.isEmpty {
            let described = inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
            PollyDebugLog.shared.log("audio: available inputs [\(described)]")
        }

        guard PollyAudioLab.micOnGlasses else {
            // Pin the phone's own microphone rather than merely declining to
            // prefer the glasses: with a paired headset on the route, "no
            // preference" still lands on the headset often enough to ruin the
            // experiment.
            if let builtIn = inputs.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }
            PollyDebugLog.shared.log("audio: input preference — phone mic (glasses audio off)")
            return
        }

        guard let glasses = inputs.first(where: isMetaGlassesPort) else { return }
        do {
            try session.setPreferredInput(glasses)
            PollyDebugLog.shared.log("audio: input preference — glasses (\(glasses.portName))")
        } catch {
            PollyDebugLog.shared.log("audio: could not prefer glasses input — \(error.localizedDescription)")
        }
    }

    /// Prefer AirPods when present; otherwise force the built-in speaker
    /// (kitchen counter phone — not the earpiece).
    static func applyPreferredOutputPort(
        on session: AVAudioSession = .sharedInstance()
    ) {
        guard PollyAudioLab.micOnGlasses else {
            try? session.overrideOutputAudioPort(.speaker)
            PollyDebugLog.shared.log("audio: output preference — built-in speaker (glasses audio off)")
            return
        }
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
