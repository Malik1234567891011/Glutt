import AVFoundation
import Foundation
import Observation
import Speech

// MARK: - Pure wake-word matching (unit-testable, no audio/Speech deps)

/// Detects the "Hey Chef" wake phrase in a transcript and strips it for display.
/// Pure string logic so the gate's core can be tested without Speech/audio.
enum WakeWordMatcher {
    /// The wake phrase is two words on purpose.
    ///
    /// "Chef" alone cannot be the trigger: it is a word cooks say constantly to
    /// each other, and it is what the chef voice calls the cook — Ramsay is told
    /// to address them as "chef", and the unclear-audio reply is literally "Say
    /// that again, chef?". The mic stays live while she talks so the cook can
    /// barge in, so a bare "chef" would wake her off her own speaker output, and
    /// worst of all in a loud kitchen where that reply fires most. Requiring a
    /// lead-in word closes that: she never opens a line with "hey chef".
    static let leadIns: Set<String> = ["hey", "hay", "hi", "yo"]

    /// "Chef" plus the mis-hears an on-device recognizer commonly returns for it.
    /// These can be loose because a lead-in has to precede them.
    static let names: Set<String> = ["chef", "chefs", "shef", "sheff", "chief"]

    private static func words(_ transcript: String) -> [String] {
        transcript.lowercased().split { !$0.isLetter }.map(String.init)
    }

    /// Positions of the name token in every "<lead-in> <name>" pair.
    private static func wakeEndIndices(_ tokens: [String]) -> [Int] {
        guard tokens.count >= 2 else { return [] }
        return (1..<tokens.count).filter { names.contains(tokens[$0]) && leadIns.contains(tokens[$0 - 1]) }
    }

    /// True if the transcript contains the wake phrase.
    static func containsWake(_ transcript: String) -> Bool {
        !wakeEndIndices(words(transcript)).isEmpty
    }

    /// How many times the wake phrase appears. A continuous recognizer keeps every
    /// past "Hey Chef" in its running transcript, so the gate wakes on a *new* one
    /// by watching this count rise, not by "contains".
    static func wakeCount(_ transcript: String) -> Int {
        wakeEndIndices(words(transcript)).count
    }

    /// The question the cook asked after the wake phrase, for the live caption.
    /// Everything up to and including the last wake phrase is dropped; if nothing
    /// follows yet, the whole transcript is shown (so "Hey Chef…" reads live).
    static func strippedQuestion(_ transcript: String) -> String {
        let raw = transcript.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let normalized = raw.map { $0.lowercased().filter(\.isLetter) }
        guard let lastWakeEnd = wakeEndIndices(normalized).last else {
            return transcript.trimmingCharacters(in: .whitespaces)
        }
        let after = raw[(lastWakeEnd + 1)...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return after.isEmpty ? transcript.trimmingCharacters(in: .whitespaces) : after
    }
}

// MARK: - Listening protocol (injected so the controller is testable)

@MainActor
protocol WakeWordListening: AnyObject {
    /// Fired when "Hey Chef" is heard while dormant. Debounced by the listener.
    var onWake: (() -> Void)? { get set }
    /// Fired with the rolling live transcript (for the Listening caption).
    var onPartialTranscript: ((String) -> Void)? { get set }
    /// Fired when on-device listening actually starts or stops. Recognizer
    /// availability is transient, so this — not a one-shot read of `isAvailable`
    /// at session start — is what the UI should believe.
    var onListeningChange: ((Bool) -> Void)? { get set }
    /// Whether on-device recognition is usable right now (authorized + supported).
    var isAvailable: Bool { get }
    /// Requests Speech authorization; returns whether on-device listening can run.
    func requestAuthorization() async -> Bool
    func start()
    func stop()
    /// Begins a fresh recognition segment (clears the running transcript so the
    /// next "Hey Chef" wakes). Called each time the session returns to dormant.
    func restart()
    /// Feed a raw mic buffer. Safe to call from the audio render thread.
    nonisolated func append(_ buffer: AVAudioPCMBuffer)
}

// MARK: - On-device implementation

/// On-device "Hey Chef" wake-word + live-transcription listener, backed by
/// `SFSpeechRecognizer` with `requiresOnDeviceRecognition`. Fed mic buffers from
/// `PollyAudioEngine`'s single tap (it hears even while the Realtime input is
/// muted). Each dormant→listen cycle runs on a fresh recognition segment via
/// `restart()`, so every "Hey Chef" wakes — not just the first — and the running
/// transcript never grows unbounded. The Realtime session stays the source of
/// truth for the conversation; this only gates *when* Polly is allowed to hear.
@MainActor
@Observable
final class WakeWordListener: WakeWordListening {
    var onWake: (() -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onListeningChange: ((Bool) -> Void)?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            onListeningChange?(isRunning)
        }
    }
    /// Bumped on every (re)start; callbacks from a superseded task carry an old
    /// value and are ignored, so a `restart()` can't double-spawn tasks.
    @ObservationIgnored private var generation = 0
    /// Wake tokens seen so far in the CURRENT segment; a new "Hey Chef" pushes this
    /// past the last-fired count and triggers a wake.
    @ObservationIgnored private var firedWakeCount = 0

    /// The active request, written on the main actor and read from the audio
    /// render thread in `append` — guarded by `requestLock`.
    @ObservationIgnored private let requestLock = NSLock()
    @ObservationIgnored nonisolated(unsafe) private var activeRequest: SFSpeechAudioBufferRecognitionRequest?
    /// The format of the first buffer this segment accepted. `append` is fanned
    /// out to three candidate mic feeds (APM capture-post, local track renderer,
    /// ADM engine tap) and nothing enforces that only one is live. They can carry
    /// different sample rates and commonFormats, and interleaving those into a
    /// single SFSpeechAudioBufferRecognitionRequest corrupts recognition rather
    /// than improving it. First format wins; the rest are dropped.
    @ObservationIgnored nonisolated(unsafe) private var acceptedFormat: AVAudioFormat?

    /// `start()` was asked for, regardless of whether the recognizer was ready.
    @ObservationIgnored private var wantsToRun = false
    @ObservationIgnored private var availabilityRetryTask: Task<Void, Never>?

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
        wantsToRun = true
        guard !isRunning else { return }
        guard isAvailable else {
            // Do NOT give up here. `SFSpeechRecognizer.isAvailable` is transient and
            // is routinely false for a moment right after init — and the caller reads
            // this exactly once at session start. One unlucky read used to leave the
            // wake word dead for the entire cook, which from the counter is
            // indistinguishable from "she never hears me".
            PollyDebugLog.shared.log("wake: recognizer not available yet — retrying")
            scheduleAvailabilityRetry()
            return
        }
        isRunning = true
        beginTask()
    }

    func stop() {
        wantsToRun = false
        availabilityRetryTask?.cancel()
        availabilityRetryTask = nil
        isRunning = false
        generation &+= 1   // ignore any in-flight callbacks
        task?.cancel()
        task = nil
        requestLock.lock()
        activeRequest?.endAudio()
        activeRequest = nil
        acceptedFormat = nil
        requestLock.unlock()
        PollyDebugLog.shared.log("wake: stopped")
    }

    /// Poll until the recognizer shows up, then start. Bounded so a genuinely
    /// unsupported device does not spin for the whole cook.
    private func scheduleAvailabilityRetry() {
        guard availabilityRetryTask == nil else { return }
        availabilityRetryTask = Task { [weak self] in
            for _ in 0..<20 {                       // ~10s at 500ms
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                guard self.wantsToRun, !self.isRunning else {
                    self.availabilityRetryTask = nil
                    return
                }
                if self.isAvailable {
                    self.isRunning = true
                    self.beginTask()
                    self.availabilityRetryTask = nil
                    PollyDebugLog.shared.log("wake: recognizer became available — listening")
                    return
                }
            }
            self?.availabilityRetryTask = nil
            PollyDebugLog.shared.log("wake: recognizer never became available this session")
        }
    }

    /// Finalizes the current segment and starts a clean one, so the running
    /// transcript (which still holds the last "Hey Chef") no longer blocks the next
    /// wake. The cancelled task's late callbacks are ignored via `generation`.
    func restart() {
        guard isRunning else { return }
        swapInFreshSegment()
        PollyDebugLog.shared.log("wake: segment restarted (rearmed)")
    }

    /// Install a new recognition segment BEFORE letting the old one go.
    ///
    /// The old order — nil out `activeRequest`, then `beginTask()` — opened a
    /// window in which every mic buffer was appended to nothing and silently
    /// discarded. It is reached from `restartIfCurrent` roughly once a minute for
    /// the whole cook, because the on-device request caps out around there, and
    /// the window spans a hop back to the main actor from the recognition
    /// callback, which is not short when the cook screen is rendering video. Say
    /// "Hey Chef" inside one and she simply does not hear you.
    private func swapInFreshSegment() {
        let previousTask = task
        requestLock.lock()
        let previousRequest = activeRequest
        requestLock.unlock()

        beginTask()   // overwrites activeRequest under the lock: no gap

        previousRequest?.endAudio()
        previousTask?.cancel()
    }

    nonisolated func append(_ buffer: AVAudioPCMBuffer) {
        requestLock.lock()
        let req = activeRequest
        // Lock the segment to the first format it sees. Three separate mic feeds
        // are wired to this method and nothing guarantees only one is live; mixing
        // sample rates into one request degrades recognition instead of enriching
        // it. Dropping the odd ones out is strictly better than interleaving.
        if let accepted = acceptedFormat {
            guard buffer.format.sampleRate == accepted.sampleRate,
                  buffer.format.channelCount == accepted.channelCount,
                  buffer.format.commonFormat == accepted.commonFormat else {
                requestLock.unlock()
                return
            }
        } else if req != nil {
            acceptedFormat = buffer.format
        }
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
        PollyDebugLog.shared.log("wake: heard \"Hey Chef\" in \"\(transcript.suffix(40))\"")
        onWake?()
    }

    /// The on-device request caps out (~1 min) and finalizes; spin up a fresh one
    /// so listening is continuous for a whole cook. Ignores superseded tasks.
    private func restartIfCurrent(gen: Int) {
        guard gen == generation else { return }
        guard isRunning else {
            task = nil
            requestLock.lock()
            activeRequest = nil
            acceptedFormat = nil
            requestLock.unlock()
            return
        }
        swapInFreshSegment()
    }
}
