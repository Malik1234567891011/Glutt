import AVFoundation
import Foundation

/// Speaks Polly's words in a cloned voice during a LIVE cook.
///
/// Only used when the picked chef has an ElevenLabs voice. The Realtime session
/// is then minted with `output_modalities: ["text"]`, so the model stops
/// producing audio and emits words instead; this turns those words back into
/// speech. Her ears stay OpenAI's (audio in, far-field noise reduction,
/// semantic VAD, transcription all unchanged) and only her mouth becomes ours.
///
/// ## The echo problem, and why this is deliberately the simple version
///
/// libWebRTC normally owns playback, which is what lets Apple's voice-processing
/// unit treat her voice as a known reference and subtract it from the mic. Audio
/// played by us sits outside that path, so the honest question is whether VPIO
/// still cancels it. A device log has now confirmed VPIO is active
/// (`AEC[avail=1 req=1 ACTIVE=1]`), and VPIO cancels what leaves the shared
/// session's output — so playing on that same session has a real chance of
/// staying cancelled.
///
/// "A real chance" is not "proven". This uses `AVAudioPlayer` on the existing
/// session rather than building a second engine, because the measurement matters
/// more than the machinery: if phantom `input_audio_buffer.speech_started`
/// events appear during her turns, the echo is not being cancelled and no amount
/// of cleverness here fixes it — that is the point where server-side rendering
/// becomes the answer. Watch the debug log for `voice: phantom speech during
/// playback`.
@MainActor
@Observable
final class PollyVoicePlayer: NSObject, AVAudioPlayerDelegate {
    /// True while her voice is physically coming out of the speaker. Stands in
    /// for the `output_audio_buffer.started/stopped` events that speech-to-speech
    /// gives us for free and text-only mode does not.
    private(set) var isSpeaking = false

    /// Fired when playback starts and stops, so the controller can drive the
    /// same half-duplex governor it used for model audio.
    var onSpeakingChange: ((Bool) -> Void)?

    private let speech: PollySpeechClient
    private var player: AVAudioPlayer?
    private var currentTask: Task<Void, Never>?
    /// Bumped on every stop; a synthesis that finishes after being cancelled
    /// checks this and throws its audio away instead of talking over the cook.
    private var generation = 0

    init(speech: PollySpeechClient = .live) {
        self.speech = speech
        super.init()
    }

    /// Synthesise `text` in `voiceID` and play it. Replaces anything in flight.
    ///
    /// Synthesis is per response rather than per sentence. Her replies are one
    /// or two sentences by design, so sentence-level pipelining would add
    /// complexity for a few hundred milliseconds. If replies get longer, split
    /// on sentence boundaries and queue.
    func speak(_ text: String, voiceID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()

        let gen = generation
        currentTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            let audio = try? await speech.speak(trimmed, elevenLabsVoiceID: voiceID)
            guard !Task.isCancelled, gen == self.generation else { return }
            guard let audio, !audio.isEmpty else {
                // Silence is the one outcome a cooking assistant must never
                // produce, so say so loudly in the log rather than just stopping.
                PollyDebugLog.shared.log("voice: SYNTHESIS FAILED — she will be silent this turn")
                return
            }
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
            PollyDebugLog.shared.log("voice: synthesised \(audio.count) bytes in \(ms) ms")
            self.play(audio)
        }
    }

    /// Cut her off. Called on barge-in and on teardown.
    func stop() {
        generation &+= 1
        currentTask?.cancel()
        currentTask = nil
        player?.stop()
        player = nil
        setSpeaking(false)
    }

    // MARK: - Playback

    private func play(_ data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            setSpeaking(true)
            if !player.play() {
                PollyDebugLog.shared.log("voice: play() refused")
                setSpeaking(false)
            }
        } catch {
            PollyDebugLog.shared.log("voice: unplayable audio — \(error.localizedDescription)")
            setSpeaking(false)
        }
    }

    private func setSpeaking(_ speaking: Bool) {
        guard speaking != isSpeaking else { return }
        isSpeaking = speaking
        PollyDebugLog.shared.log("voice: playback \(speaking ? "START" : "STOP")")
        onSpeakingChange?(speaking)
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.setSpeaking(false)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.player = nil
            self.setSpeaking(false)
        }
    }
}
