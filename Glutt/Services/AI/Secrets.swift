import Foundation

/// Beta-build secrets. For the TestFlight beta the AI key ships in the app —
/// acceptable for a small trusted group with a spend cap on the key.
/// TODO before public launch: move behind a proxy and rotate this key.
///
/// ⚠️ If you put a real key here, set a monthly spend limit on it at
/// platform.openai.com → Settings → Limits.
enum Secrets {
    /// OpenAI (or compatible) API key baked into beta builds.
    /// Empty string = AI features fall back to on-device heuristics.
    static let embeddedAIKey = ""
}
