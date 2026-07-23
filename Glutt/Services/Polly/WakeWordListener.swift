import AVFoundation
import Foundation
import Observation
import Speech

// MARK: - Pure wake-word matching (unit-testable, no audio/Speech deps)

/// Detects the "Polly" wake word in a transcript and strips it for display.
/// Pure string logic so the gate's core can be tested without Speech/audio.
enum WakeWordMatcher {
    /// "Polly" plus the mis-hears an on-device recognizer commonly returns for it.
    /// Deliberately excludes near-words that are real English (e.g. "holly") to
    /// keep false wakes down.
    static let variants: Set<String> = ["polly", "pollie", "poly", "paulie", "pauly", "pally"]

    private static func words(_ transcript: String) -> [String] {
        transcript.lowercased().split { !$0.isLetter }.map(String.init)
    }

    /// True if any token is a wake-word variant.
    static func containsWake(_ transcript: String) -> Bool {
        words(transcript).contains { variants.contains($0) }
    }

    /// How many wake-word tokens the transcript contains. A continuous recognizer
    /// keeps every past "Polly" in its running transcript, so the gate wakes on a
    /// *new* one by watching this count rise, not by "contains".
    static func wakeCount(_ transcript: String) -> Int {
        words(transcript).filter { variants.contains($0) }.count
    }

    /// The question the cook asked after the wake word, for the live caption.
    /// Everything up to and including the last wake token is dropped; if nothing
    /// follows yet, the whole transcript is shown (so "Polly…" reads live).
    static func strippedQuestion(_ transcript: String) -> String {
        let tokens = transcript.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let lastWakeIndex = tokens.lastIndex(where: {
            variants.contains($0.lowercased().filter(\.isLetter))
        }) else {
            return transcript.trimmingCharacters(in: .whitespaces)
        }
        let after = tokens[(lastWakeIndex + 1)...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return after.isEmpty ? transcript.trimmingCharacters(in: .whitespaces) : after
    }
}

// MARK: - Listening protocol (injected so the controller is testable)

@MainActor
protocol WakeWordListening: AnyObject {
    /// Fired when "Polly" is heard while dormant. Debounced by the listener.
    var onWake: (() -> Void)? { get set }
    /// Fired with the rolling live transcript (for the Listening caption).
    var onPartialTranscript: ((String) -> Void)? { get set }
    /// Whether on-device recognition is usable right now (authorized + supported).
    var isAvailable: Bool { get }
    /// Requests Speech authorization; returns whether on-device listening can run.
    func requestAuthorization() async -> Bool
    func start()
    func stop()
    /// Begins a fresh recognition segment (clears the running transcript so the
    /// next "Polly" wakes). Called each time the session returns to dormant.
    func restart()
    /// Feed a raw mic buffer. Safe to call from the audio render thread.
    nonisolated func append(_ buffer: AVAudioPCMBuffer)
}

// MARK: - On-device implementation

/// On-device "Polly" wake-word + live-transcription listener, backed by
/// `SFSpeechRecognizer` with `requiresOnDeviceRecognition`. Fed mic buffers from
/// `PollyAudioEngine`'s single tap (it hears even while the Realtime input is
/// muted). Each dormant→listen cycle runs on a fresh recognition segment via
/// `restart()`, so every "Polly" wakes — not just the first — and the running
/// transcript never grows unbounded. The Realtime session stays the source of
/// truth for the conversation; this only gates *when* Polly is allowed to hear.
@MainActor
@Observable
final class WakeWordListener: WakeWordListening {
    var onWake: (() -> Void)?
    var onPartialTranscript: ((String) -> Void)?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var isRunning = false
    /// Bumped on every (re)start; callbacks from a superseded task carry an old
    /// value and are ignored, so a `restart()` can't double-spawn tasks.
    @ObservationIgnored private var generation = 0
    /// Wake tokens seen so far in the CURRENT segment; a new "Polly" pushes this
    /// past the last-fired count and triggers a wake.
    @ObservationIgnored private var firedWakeCount = 0

    /// The active request, written on the main actor and read from the audio
    /// render thread in `append` — guarded by `requestLock`.
    @ObservationIgnored private let requestLock = NSLock()
    @ObservationIgnored nonisolated(unsafe) private var activeRequest: SFSpeechAudioBufferRecognitionRequest?

    var isAvailable: Bool {
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return false }
        return SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { _ in cont.resume() }
            }
        }
        return isAvailable
    }

    func start() {
        guard isAvailable, !isRunning else { return }
        isRunning = true
        beginTask()
    }

    func stop() {
        isRunning = false
        generation &+= 1   // ignore any in-flight callbacks
        task?.cancel()
        task = nil
        requestLock.lock()
        activeRequest?.endAudio()
        activeRequest = nil
        requestLock.unlock()
        PollyDebugLog.shared.log("wake: stopped")
    }

    /// Finalizes the current segment and starts a clean one, so the running
    /// transcript (which still holds the last "Polly") no longer blocks the next
    /// wake. The cancelled task's late callbacks are ignored via `generation`.
    func restart() {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        requestLock.lock()
        activeRequest?.endAudio()
        activeRequest = nil
        requestLock.unlock()
        beginTask()
        PollyDebugLog.shared.log("wake: segment restarted (rearmed)")
    }

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        requestLock.lock()
        let req = activeRequest
        requestLock.unlock()
        req?.append(buffer)
    }

    // MARK: - Recognizer lifecycle

    private func beginTask() {
        guard isRunning, let recognizer else { return }
        generation &+= 1
        let gen = generation
        firedWakeCount = 0

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.taskHint = .search
        requestLock.lock()
        activeRequest = req
        requestLock.unlock()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in self.handle(text, gen: gen) }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in self.restartIfCurrent(gen: gen) }
            }
        }
        PollyDebugLog.shared.log("wake: listening (on-device)")
    }

    private func handle(_ transcript: String, gen: Int) {
        guard gen == generation else { return }   // stale task
        onPartialTranscript?(transcript)
        let count = WakeWordMatcher.wakeCount(transcript)
        guard count > firedWakeCount else { return }
        firedWakeCount = count
        PollyDebugLog.shared.log("wake: heard \"Polly\" in \"\(transcript.suffix(40))\"")
        onWake?()
    }

    /// The on-device request caps out (~1 min) and finalizes; spin up a fresh one
    /// so listening is continuous for a whole cook. Ignores superseded tasks.
    private func restartIfCurrent(gen: Int) {
        guard gen == generation else { return }
        task = nil
        requestLock.lock()
        activeRequest = nil
        requestLock.unlock()
        guard isRunning else { return }
        beginTask()
    }
}
