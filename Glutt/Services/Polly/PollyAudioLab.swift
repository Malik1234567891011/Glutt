import Foundation

/// The two device-only audio experiments, flippable from the cook session's
/// overflow menu while a session is live.
///
/// These ship in Release on purpose. Neither behaviour can be reproduced in the
/// simulator or judged honestly from a Debug build, so the only test worth
/// running is a real cook in a real kitchen on the build that will actually
/// ship, with the ability to flip and hear the difference inside one session
/// rather than across two installs.
///
/// Backed by `UserDefaults` rather than `@AppStorage` because the transport
/// reads them from the audio thread, nowhere near a SwiftUI view.
enum PollyAudioLab {
    /// Stack libwebrtc's AEC3 on top of Apple's VPIO rather than relying on VPIO
    /// alone.
    ///
    /// Until now production ran with NO software echo cancellation whatsoever:
    /// `enableSoftwareAEC()` existed, but its only caller was a screen gated
    /// behind the `-pollyV2Spike` launch argument, so a shipping cook never
    /// reached it. If VPIO declined to engage on a given device or route there
    /// was no fallback and no way to find out. Defaults ON because "some echo
    /// cancellation" beats "none, silently".
    ///
    /// Off is worth trying if her voice sounds over-suppressed or clipped: two
    /// cancellers in series can chew into speech as well as echo.
    static var stackedAEC: Bool {
        get { UserDefaults.standard.object(forKey: Keys.stackedAEC) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.stackedAEC) }
    }

    /// Keep the mic track open while Polly is speaking, instead of closing it
    /// for her entire utterance.
    ///
    /// Half-duplex is why interrupting her takes a raised voice: with the track
    /// closed, getting back in means clearing an RMS gate rather than simply
    /// talking. Defaults OFF because it is the genuinely experimental one — it
    /// hands the echo canceller the job the closed track was doing for it.
    static var fullDuplex: Bool {
        get { UserDefaults.standard.object(forKey: Keys.fullDuplex) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Keys.fullDuplex) }
    }

    /// Use the glasses for Chef's voice, or leave the audio on the phone.
    ///
    /// This is here because the glasses can apparently do voice or video over
    /// Bluetooth, but not obviously both. Measured across two real cooks: the
    /// camera streams cleanly, the HFP voice link comes up, and a few seconds
    /// later frame delivery stops dead for a minute or more while the stream
    /// still reports itself as `.streaming`. Standing the same camera up with no
    /// Polly session at all delivered 409 frames over a minute without a single
    /// drop. HFP is a reserved-slot synchronous link and the camera is fighting
    /// it for the same radio, which is the whole reason Meta moved video to
    /// Wi-Fi in the first place.
    ///
    /// Off means no Bluetooth audio whatsoever: built-in mic, built-in speaker,
    /// and the category loses the Bluetooth options entirely. Deliberately the
    /// blunt version rather than A2DP-out, because the point is to answer
    /// "does Bluetooth audio cost us the camera" without leaving a second
    /// Bluetooth profile in the picture to argue about. If it does, A2DP-out
    /// with the phone's mic is the obvious next rung.
    ///
    /// Defaults ON: her voice in your ears while your hands are covered in flour
    /// is most of the point of wearing the things.
    static var micOnGlasses: Bool {
        get { UserDefaults.standard.object(forKey: Keys.micOnGlasses) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.micOnGlasses) }
    }

    /// One line for the debug dump, so a pasted log says which experiment
    /// produced it. A log without this is unattributable.
    static var summary: String {
        "audioLab: stackedAEC=\(stackedAEC ? 1 : 0) fullDuplex=\(fullDuplex ? 1 : 0) "
            + "micOnGlasses=\(micOnGlasses ? 1 : 0)"
    }

    private enum Keys {
        static let stackedAEC = "glutt.polly.audioLab.stackedAEC"
        static let fullDuplex = "glutt.polly.audioLab.fullDuplex"
        static let micOnGlasses = "glutt.polly.audioLab.micOnGlasses"
    }
}
