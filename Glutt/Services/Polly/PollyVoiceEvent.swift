import Foundation

/// Privacy-safe structured voice-session events for debug dumps and metrics.
/// Never include raw audio. Transcripts are truncated.
enum PollyVoiceEvent: String {
    case wakeDetected = "wake.detected"
    case manualReopen = "wake.manual_reopen"
    case followUpArmed = "followup.armed"
    case followUpSpeech = "followup.speech"
    case followUpAccepted = "followup.accepted"
    case followUpRejected = "followup.rejected"
    case followUpTimeout = "followup.timeout"
    case acknowledgment = "followup.ack"
    case explicitEnd = "followup.explicit_end"
    case unfinishedHold = "turn.unfinished_hold"
    case turnCommitted = "turn.committed"
    case bargeInCandidate = "barge.candidate"
    case bargeInAccepted = "barge.accepted"
    case bargeInIgnored = "barge.ignored"
    case assistantSpeechStart = "assistant.speech_start"
    case assistantSpeechEnd = "assistant.speech_end"
    case sessionClosed = "session.closed"
    case audioInterrupted = "audio.interrupted"
    case micLost = "audio.mic_lost"
    case recoverableShown = "ui.recoverable_shown"
    case recoverableTapped = "ui.recoverable_tapped"
}

extension PollyDebugLog {
    /// Structured line: `evt=<code> key=value …` for easy grepping / metrics.
    func event(_ code: PollyVoiceEvent, _ fields: [String: String] = [:]) {
        var parts = ["evt=\(code.rawValue)"]
        for key in fields.keys.sorted() {
            let value = fields[key]?.replacingOccurrences(of: " ", with: "_") ?? ""
            parts.append("\(key)=\(value)")
        }
        log(parts.joined(separator: " "))
    }
}
