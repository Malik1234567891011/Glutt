import AVFoundation
import Foundation
import Observation
import Speech

/// Short on-device dictation for pantry intake — not Polly. Start, speak a
/// casual list, stop, read the transcript. Recognition stays on-device when the
/// device supports it.
///
/// Two things here exist because of bugs a cook hit on device, and both are
/// about the gap between what `SFSpeechRecognizer` does and what someone
/// reciting the contents of their fridge expects.
///
/// **The list used to empty itself.** A recognition request covers about a
/// minute of audio and then ends. This class used to mirror that request's
/// hypothesis straight into `transcript`, so when the request ended and a new
/// one began, everything said so far vanished. Now segments are banked in
/// `DictationTranscript` and a finished request is quietly replaced with a
/// fresh one while the cook keeps talking, so the mic simply stays on.
///
/// **Stopping used to look like failure.** `stop()` called `endAudio()`, asking
/// for a final result, and then cancelled the task before it could arrive. The
/// cancellation came back as an error and painted "Couldn't catch that" over a
/// transcript that was perfectly correct, which is why tapping Find ingredients
/// afterwards worked fine. An intentional stop now drains rather than cancels.
@MainActor
@Observable
final class PantryDictationSession {
    private(set) var accumulated = DictationTranscript()
    var transcript: String { accumulated.text }
    var isListening = false
    var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var task: SFSpeechRecognitionTask?
    /// The request the audio tap is currently feeding.
    ///
    /// Boxed because the tap runs on an audio thread and this class is
    /// main-actor isolated. Swapping the box's contents is what lets a request
    /// be replaced mid-sentence without tearing down the engine and losing the
    /// fraction of a second it takes to restart it.
    private let requestBox = RecognitionRequestBox()
    /// The cook's intent, which outlives any single recognition request. True
    /// between tapping talk and tapping stop, whatever the recognizer does in
    /// between.
    private var wantsListening = false
    /// Set for the moment between asking a request to finish and it finishing,
    /// so the resulting callbacks are not read as failure.
    private var isDraining = false
    /// Guards against a restart storm if the recognizer refuses to start at all.
    private var consecutiveRestarts = 0

    var canDictate: Bool {
        recognizer?.isAvailable == true
    }

    func requestAccess() async -> Bool {
        let speechOk: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechOk = true
        case .notDetermined:
            speechOk = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        default:
            speechOk = false
        }
        guard speechOk else {
            errorMessage = "Speech recognition is turned off for Glutt. You can still type what you have."
            return false
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn't open the microphone."
            return false
        }

        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            errorMessage = "Microphone access is off. You can still type what you have."
            return false
        case .undetermined:
            let granted = await withCheckedContinuation { cont in
                session.requestRecordPermission { cont.resume(returning: $0) }
            }
            if !granted {
                errorMessage = "Microphone access is off. You can still type what you have."
            }
            return granted
        @unknown default:
            return false
        }
    }

    func start() {
        guard !isListening else { return }
        errorMessage = nil
        teardown()

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn’t available on this device. Type instead."
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        // Appends to whichever request is current, not to a captured one, so a
        // request can be swapped underneath without touching the engine.
        let box = requestBox
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            errorMessage = "Couldn't start listening."
            input.removeTap(onBus: 0)
            return
        }

        audioEngine = engine
        wantsListening = true
        isListening = true
        consecutiveRestarts = 0
        startRequest()
    }

    /// Begin a recognition request against the audio already flowing.
    ///
    /// Called on every start and again whenever a request ends by itself, which
    /// is the ~1 minute limit arriving mid-list. The cook is told nothing,
    /// because from their side nothing happened.
    private func startRequest() {
        guard let recognizer, wantsListening else { return }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        requestBox.replace(with: req)

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.accumulated.updateLive(result.bestTranscription.formattedString)
                    if result.isFinal { self.requestEnded(error: nil) }
                } else if error != nil {
                    self.requestEnded(error: error)
                }
            }
        }
    }

    /// One recognition request finished, for any reason.
    ///
    /// The distinction that matters is not what the error says, it is whether
    /// the cook still has the mic on. If they do, this is the limit being hit
    /// and the answer is another request. Reading error codes here is what the
    /// old version tried, and cancellation does not reliably report the code it
    /// is documented to report.
    private func requestEnded(error: (any Error)?) {
        let heardSomething = accumulated.bankLive()
        task = nil
        requestBox.finish()

        guard wantsListening, !isDraining else {
            finishListening()
            return
        }

        // A request that produced words did its job, however it ended. Only a
        // run of requests that produce nothing at all is a broken recognizer.
        // Counting every restart instead would strand a cook who simply pauses
        // to think: each pause ends a request, and the ninth pause in one list
        // would have turned the microphone off with no explanation.
        if heardSomething { consecutiveRestarts = 0 }
        consecutiveRestarts += 1
        // A recognizer failing instantly, over and over, is not the audio limit.
        // Give up rather than spin, and only then say something.
        guard consecutiveRestarts <= 8 else {
            if accumulated.isEmpty {
                errorMessage = "Couldn't catch that — try again, or type it."
            }
            finishListening()
            return
        }
        startRequest()
    }

    /// The cook tapped stop.
    ///
    /// `endAudio()` asks the recognizer for a final pass over what it has. The
    /// old code cancelled the task in the same breath, which killed that pass
    /// and reported it as an error. Now the engine stops feeding it, the request
    /// is closed, and the task is left alone to deliver; a timer tears it down
    /// if it never does, so a wedged recognizer cannot leave the button stuck
    /// on "Listening".
    func stop() {
        guard isListening || wantsListening else { return }
        wantsListening = false
        isDraining = true
        stopAudio()
        requestBox.endAudio()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, self.isDraining else { return }
            self.accumulated.bankLive()
            self.finishListening()
        }
    }

    func resetTranscript() {
        accumulated.reset()
        errorMessage = nil
    }

    private func finishListening() {
        isDraining = false
        isListening = false
        wantsListening = false
        teardown()
    }

    /// Stop the microphone without touching the recognition task, so a final
    /// result can still arrive.
    private func stopAudio() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
    }

    private func teardown() {
        task?.cancel()
        task = nil
        requestBox.finish()
        stopAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Holds the recognition request the audio tap feeds, so it can be swapped from
/// the main actor while the tap keeps running on the audio thread.
private final class RecognitionRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func replace(with request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); defer { lock.unlock() }
        self.request?.endAudio()
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }

    func endAudio() {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        request = nil
    }
}
