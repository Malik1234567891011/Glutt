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

    init(speech: PollySpeechClient = .live) {
        self.speech = speech
        super.init()
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
            pendingAudio = try? await speech.speak(first, instructions: Self.styleInstructions)
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
                return Task { try? await self.speech.speak(text, instructions: Self.styleInstructions) }
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

    private static let styleInstructions = """
    You are Polly, Glutt's cooking chef. Warm and expert, but brisk — this is a short \
    trailer, not a lecture. Keep energy up, minimal pauses, clear and conversational. \
    Not slow, not chirpy, not salesy.
    """

    // MARK: - Playback

    private func playMP3(_ data: Data) async {
        finishPlayWait()
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.playContinuation = cont
                if !player.play() {
                    self.finishPlayWait()
                }
            }
        } catch {
            // Skip unreadable audio; caller will move on.
        }
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
