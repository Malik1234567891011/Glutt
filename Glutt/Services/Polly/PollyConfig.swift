import Foundation

/// Tuning knobs for Polly live sessions. Change these constants, not call sites.
enum PollyConfig {
    static let realtimeModel = "gpt-realtime-2"
    static let voice = "marin"
    /// Seconds between automatic camera frames while watch mode is on.
    static let watchFrameInterval: TimeInterval = 10
    /// Mic capture is dropped for this long at the START of each Polly
    /// utterance: the echo canceller needs a beat to adapt to her voice, and
    /// her opening words leak through and trip server VAD (live logs: cuts at
    /// ~450-750ms with the "user" transcribed as her own first words).
    static let onsetCaptureGateSeconds: TimeInterval = 1.0
    /// Frames are downscaled so the longest side is at most this, then JPEG-compressed.
    static let frameMaxDimension: CGFloat = 1024
    static let frameJPEGQuality: CGFloat = 0.6
    /// OpenAI Realtime hard-caps sessions at 60 minutes; we end well before that.
    static let maxSessionMinutes = 52
    /// When Polly starts steering toward wrapping up.
    static let wrapUpWarningMinutes = 47
    /// How many top PollyMemory facts get injected into the system prompt.
    static let memoryFactLimit = 12
    /// Ephemeral token lifetime requested from the proxy (OpenAI max is 600).
    static let tokenTTLSeconds = 600
}
