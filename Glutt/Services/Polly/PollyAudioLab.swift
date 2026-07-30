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

    /// One line for the debug dump, so a pasted log says which experiment
    /// produced it. A log without this is unattributable.
    static var summary: String {
        "audioLab: stackedAEC=\(stackedAEC ? 1 : 0) fullDuplex=\(fullDuplex ? 1 : 0)"
    }

    private enum Keys {
        static let stackedAEC = "glutt.polly.audioLab.stackedAEC"
        static let fullDuplex = "glutt.polly.audioLab.fullDuplex"
    }
}
