import AVFoundation
import Foundation
import Observation

/// Speaks a `CookBriefing` in Polly's real voice (OpenAI TTS via proxy — same
/// `marin` / `POLLY_VOICE` as the live session). Falls back to silent captions
/// if the proxy isn't available; never uses Apple system TTS.
@MainActor
@Observable
final class BriefingNarrator: NSObject, AVAudioPlayerDelegate {
    private(set) var isSpeaking = false
    /// True when audio is coming from Polly TTS (vs silent caption-only mode).
    private(set) var isUsingPollyVoice = false
    /// Index into `CookBriefing.spokenChunks` currently active.
    private(set) var chunkIndex: Int?
    /// Beat index in `briefing.beats` for UI highlight.
    private(set) var beatIndex: Int?
    /// Line currently being spoken (or shown silently).
    private(set) var caption = ""
    /// Becomes true once when the full trailer finishes without stop/mute.
    private(set) var didFinishNaturally = false

    private let speech: PollySpeechClient
    private var chunks: [String] = []
    private var beatCount = 0
    private var playTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var playContinuation: CheckedContinuation<Void, Never>?
    private var cancelled = false
    /// The chef picked before this cook. Snapshotted when narration starts so
    /// the whole briefing speaks in one voice even if the picker changes
    /// underneath it, and so the briefing matches the live session that follows.
    private var chef: PollyChefVoice = .default

    /// Every narrator that has started speaking, so a cook session can silence
    /// the lot without having to be handed the one that happens to be alive.
    ///
    /// A briefing is owned by a view that is being dismissed at the exact moment
    /// the session starts, which is the worst possible time to be relying on
    /// somebody remembering to pass a reference along. The requirement is that
    /// the trailer stops when the session starts, no matter which path got
    /// there, so it is enforced from the session rather than from the view.
    private static var liveNarrators: [WeakNarrator] = []
    private struct WeakNarrator { weak var value: BriefingNarrator? }

    /// Silence every briefing. Called by `PollySessionController.start`.
    static func stopAll() {
        let live = liveNarrators.compactMap(\.value)
        liveNarrators.removeAll()
        guard !live.isEmpty else { return }
        for narrator in live { narrator.stop() }
        PollyDebugLog.shared.log("briefing: stopped \(live.count) narrator(s) for the session")
    }

    init(speech: PollySpeechClient = .live) {
        self.speech = speech
        super.init()
        Self.liveNarrators.removeAll { $0.value == nil }
        Self.liveNarrators.append(WeakNarrator(value: self))
    }

    /// Speak the briefing chunk-by-chunk. Cancels any in-flight narration first.
    func narrate(_ briefing: CookBriefing) {
        stop()
        chunks = briefing.spokenChunks
        beatCount = briefing.beats.count
        guard !chunks.isEmpty else { return }

        cancelled = false
        didFinishNaturally = false
        isSpeaking = true
        isUsingPollyVoice = speech.isConfigured
        chef = PollyChefVoice.selected
        playTask = Task { [weak self] in
            await self?.runNarration()
        }
    }

    /// Cancels narration. Does **not** set `didFinishNaturally`.
    func stop() {
        cancelled = true
        playTask?.cancel()
        playTask = nil
        player?.stop()
        player = nil
        finishPlayWait()
        isSpeaking = false
        chunkIndex = nil
        beatIndex = nil
        caption = ""
        releaseAudioSession()
    }

    /// Hand the audio session back rather than leaving `.playback` installed and
    /// active for the next owner to inherit.
    ///
    /// The briefing is the doorway into every Polly session: it plays, it stops,
    /// and moments later the WebRTC transport asks for `.playAndRecord` +
    /// `.videoChat`. Swapping category on a still-active session forces an IO
    /// unit teardown and rebuild and a route change right as the voice-processing
    /// unit is trying to come up, which is a plausible cause of the "she misses
    /// the first thing I say" complaint. Deactivating first makes the handover
    /// explicit. Failure is logged, never thrown: a session we could not release
    /// must not stop the cook from starting.
    private func releaseAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            PollyDebugLog.shared.log("briefing: audio session released")
        } catch {
            PollyDebugLog.shared.log("briefing: audio session release failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Narration loop

    private func runNarration() async {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        // Prefetch chunk N+1 while N plays so the trailer doesn't stall between beats.
        var pendingAudio: Data?
        if speech.isConfigured, let first = chunks.first {
            pendingAudio = try? await speech.speak(
                first, instructions: chef.briefingStyle,
                elevenLabsVoiceID: chef.elevenLabsVoiceID)
        }

        for index in chunks.indices {
            if cancelled || Task.isCancelled { break }

            chunkIndex = index
            updateBeatIndex(forChunk: index)
            caption = chunks[index]

            let audio = pendingAudio
            pendingAudio = nil

            let next = index + 1
            let prefetch: Task<Data?, Never>? = {
                guard speech.isConfigured, next < chunks.count else { return nil }
                let text = chunks[next]
                return Task {
                    try? await self.speech.speak(
                        text, instructions: chef.briefingStyle,
                        elevenLabsVoiceID: chef.elevenLabsVoiceID)
                }
            }()

            if let audio, !cancelled {
                isUsingPollyVoice = true
                await playMP3(audio)
            } else if !cancelled {
                // Soft fail / offline: pace through captions without system TTS.
                isUsingPollyVoice = false
                try? await Task.sleep(for: .milliseconds(captionDwellMs(chunks[index])))
            }

            if cancelled {
                prefetch?.cancel()
            } else {
                pendingAudio = await prefetch?.value
            }
        }

        if !cancelled, !Task.isCancelled {
            isSpeaking = false
            chunkIndex = nil
            didFinishNaturally = true
        }
    }

    private func updateBeatIndex(forChunk index: Int) {
        // chunks: [intro, beat0…, outro]
        if beatCount > 0, index >= 1, index <= beatCount {
            beatIndex = index - 1
        } else if index == 0 {
            beatIndex = beatCount > 0 ? 0 : nil
        } else {
            beatIndex = beatCount > 0 ? beatCount - 1 : nil
        }
    }

    private func captionDwellMs(_ text: String) -> UInt64 {
        let words = max(1, text.split(whereSeparator: \.isWhitespace).count)
        return UInt64(min(6_000, max(1_400, words * 320)))
    }

    // MARK: - Playback

    private func playMP3(_ data: Data) async {
        // Checked here, not only by the caller.
        //
        // This is what talked over the live cook session. `stop()` nils
        // `self.player` and releases the audio session, but a stop landing
        // between building this player and calling `play()` was invisible from
        // in here: the method carried on, assigned the fresh player over the nil
        // and started it, so "Skip summary" handed the trailer a brand new
        // player a fraction of a second after cancelling the old one. Chef and
        // her own trailer then read the recipe at each other.
        guard !cancelled else { return }
        finishPlayWait()
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            // The await above and the work below both yield, so re-check rather
            // than trusting the guard at the top.
            guard !cancelled else { return }
            self.player = player
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.playContinuation = cont
                if cancelled || !player.play() {
                    self.finishPlayWait()
                }
            }
        } catch {
            // Skip unreadable audio; caller will move on.
        }
        player?.stop()
        player = nil
    }

    private func finishPlayWait() {
        playContinuation?.resume()
        playContinuation = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finishPlayWait()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.finishPlayWait()
        }
    }
}
