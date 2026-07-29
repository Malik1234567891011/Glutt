import AVFoundation
import Foundation
import Observation
import Speech

/// Short on-device dictation for pantry intake — not Polly. One-shot listen:
/// start → speak a casual list → stop → final transcript. Recognition stays
/// on-device when the device supports it.
@MainActor
@Observable
final class PantryDictationSession {
    var transcript = ""
    var isListening = false
    var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

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
        stopEngine()

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn’t available on this device. Type instead."
            return
        }

        let engine = AVAudioEngine()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            errorMessage = "Couldn't start listening."
            input.removeTap(onBus: 0)
            return
        }

        audioEngine = engine
        request = req
        isListening = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishListening()
                    }
                }
                if let error, (error as NSError).code != 216 /* cancelled */ {
                    self.errorMessage = "Couldn't catch that — try again, or type it."
                    self.finishListening()
                }
            }
        }
    }

    func stop() {
        request?.endAudio()
        finishListening()
    }

    func resetTranscript() {
        transcript = ""
        errorMessage = nil
    }

    private func finishListening() {
        isListening = false
        stopEngine()
    }

    private func stopEngine() {
        task?.cancel()
        task = nil
        request = nil
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
