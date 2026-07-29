import Foundation

/// Tuning knobs for Polly live sessions. Change these constants, not call sites.
enum PollyConfig {
    static let realtimeModel = "gpt-realtime-2.1"
    static let voice = "marin"
    /// Mic capture is dropped for this long at the START of each Polly
    /// utterance: the echo canceller needs a beat to adapt to her voice, and
    /// her opening words leak through and trip server VAD (live logs: cuts at
    /// ~450-750ms with the "user" transcribed as her own first words).
    static let onsetCaptureGateSeconds: TimeInterval = 1.0
    /// While Polly is actively speaking, mic audio quieter than this RMS
    /// (voice tops out around ~0.25) is treated as echo of her own voice or
    /// room noise and NOT forwarded to the server, so it can't trip VAD and cut
    /// her off mid-sentence — the "it keeps interrupting itself on a slight
    /// noise" symptom. A clear, close voice sails past this floor, so
    /// intentional barge-in still works. Raise it if she still self-interrupts,
    /// lower it if real interruptions get swallowed. 0 disables the gate.
    static let bargeInRMSFloor: Float = 0.06
    /// Stricter floor while Polly is speaking (kitchen clanks sit under this;
    /// a close directed voice clears it). Used with `bargeInSustainedMs`.
    static let bargeInSpeakingRMSFloor: Float = 0.10
    /// Mic must stay above the speaking floor this long before chunks forward
    /// while Polly talks — rejects pan hits / short noise bursts.
    static let bargeInSustainedMs: Int = 280
    /// Beat to wait before requesting Polly's opening line, so the AEC-triggered
    /// AVAudioEngineConfigurationChange (which briefly stops the engine ~20ms
    /// after start) lands BEFORE her first audio is scheduled — otherwise the
    /// greeting buffers get flushed unheard and she's silent until the user
    /// speaks. Only applied when the mic pipeline is actually running.
    static let greetingWarmupSeconds: TimeInterval = 0.5
    /// Mic capture is held silent this long from the moment the greeting is
    /// requested. It bridges the startup window — the mic goes live ~1s before
    /// her first audio arrives, and that ambient/echo stream can trip server VAD
    /// and truncate her opening line at ~0ms (symptom: caption shows, no sound).
    /// Long enough to cover time-to-first-audio plus the onset adaptation window.
    static let greetingMicHoldSeconds: TimeInterval = 2.5
    /// Frames are downscaled so the longest side is at most this, then JPEG-compressed.
    static let frameMaxDimension: CGFloat = 1024
    static let frameJPEGQuality: CGFloat = 0.6
    /// OpenAI Realtime hard-caps sessions at 60 minutes; we end well before that.
    static let maxSessionMinutes = 52
    /// When Polly starts steering toward wrapping up.
    static let wrapUpWarningMinutes = 47
    /// v2 hybrid window: the conversation stays open until this much TRUE
    /// silence (no user speech, no Polly audio) passes — the v1 3s window was
    /// the #1 "she stopped listening" generator.
    static let hybridWindowSeconds: TimeInterval = 10
    /// Never-silent contract: if Polly's audio hasn't started this long after
    /// the cook stopped talking, force a spoken repair ("say that again?").
    static let responseWatchdogSeconds: TimeInterval = 4
    /// Never-silent contract: silent reconnect attempts before failing loud.
    /// (v1 allowed exactly one.)
    static let reconnectAttempts = 2
    /// Voice-reopen (barge-in through the half-duplex gate): instant reopen
    /// at this capture RMS…
    static let bargeReopenLoudRMS: Float = 0.12
    /// …or two ticks above this within 0.6s (syllable-gap tolerant).
    static let bargeReopenSoftRMS: Float = 0.055
    /// After Polly answers, keep listening this long for a natural follow-up
    /// without requiring "Polly" again. Activity-based: speech during the window
    /// extends the deadline until the turn completes.
    static let followUpWindowSeconds: TimeInterval = 7
    /// Right after wake ("Polly"), give the cook longer to form the first ask
    /// before re-gating — saying the name then thinking is normal at the stove.
    static let initialListenWindowSeconds: TimeInterval = 15
    /// When Polly's last line asked a question, keep the session open longer and
    /// treat short answers ("yeah", "no") as real turns.
    static let expectedAnswerWindowSeconds: TimeInterval = 14
    /// After a bare acknowledgment ("okay"), linger briefly then close if quiet.
    static let acknowledgmentGraceSeconds: TimeInterval = 2.5
    /// How often the follow-up watcher checks the deadline.
    static let followUpPollIntervalMs: UInt64 = 200
    /// Absolute idle while engaged (no valid interaction) before quietly closing.
    static let maxEngagedIdleSeconds: TimeInterval = 45
    /// When a transcript looks unfinished ("and", "uh", …), delay commitment
    /// this long so a continuation can arrive before we answer.
    static let unfinishedTurnHoldMs: UInt64 = 750
    /// How long a rejected-but-recoverable transcript chip stays tappable.
    static let recoverableTranscriptSeconds: TimeInterval = 8
    /// How many top PollyMemory facts get injected into the system prompt.
    static let memoryFactLimit = 12
    /// Ephemeral token lifetime requested from the proxy (OpenAI max is 600).
    static let tokenTTLSeconds = 600
}
