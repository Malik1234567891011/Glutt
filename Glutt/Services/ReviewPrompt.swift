import Foundation

/// The once-per-install latch in front of the native App Store rating card.
///
/// The card itself is asked for with SwiftUI's `requestReview` action at the
/// call site — this type only decides *whether* to spend the ask, because the
/// decision is the part worth keeping in one place.
///
/// Two things about the system card shape everything here:
///
/// 1. **It is fire-and-forget.** No callback, no return value, no way to know
///    whether the card appeared or what was tapped. So nothing may ever wait on
///    it, and the screen underneath has to stand on its own.
/// 2. **The impressions are scarce.** iOS throttles the card to three per user
///    per 365 days across the whole app, and people can switch it off entirely
///    in Settings → App Store. Asking twice for the same reason wastes one of
///    three chances, which is what the latch protects.
///
/// The latch lives in `UserDefaults` rather than `UserPrefs`: it is install-local
/// bookkeeping about a system quota, not something the user chose, and it must
/// survive a forced re-run of onboarding (`Router.forceOnboarding`) that leaves
/// the SwiftData record untouched.
enum ReviewPrompt {

    /// Where in the app an ask came from. Recorded on the analytics event so a
    /// second moment added later stays separable from onboarding's.
    enum Moment: String {
        /// Onboarding screen 6 — the Polly hero, a beat after it settles. Peak
        /// enthusiasm, and the screen already shows the "4.9 ★ rated" laurel,
        /// so the card reads as *add yours* rather than a cold ask.
        case onboardingPolly = "onboarding_polly"
    }

    private static let askedKey = "reviewPromptAsked"

    /// True once any moment has spent the ask.
    static var hasAsked: Bool { UserDefaults.standard.bool(forKey: askedKey) }

    /// Whether to ask now. Call immediately before `requestReview()`, then
    /// `markAsked(_:)` — the two are split so the caller can bail out during a
    /// pre-ask delay without burning the latch.
    static func shouldAsk() -> Bool {
        // Automated UI runs: the simulator shows this card on *every* launch,
        // where it would sit on top of the screen being captured and swallow
        // taps. Same reasoning as the Superwall and analytics opt-outs.
        guard !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return false }
        return !hasAsked
    }

    /// Burns the latch and records the ask. Call right before `requestReview()`,
    /// never after — if the process dies mid-card the ask still happened.
    static func markAsked(_ moment: Moment) {
        UserDefaults.standard.set(true, forKey: askedKey)
        Analytics.capture(.reviewPrompted, ["moment": moment.rawValue])
    }

    #if DEBUG
    /// Re-arms the latch so the card can be reached again on the next run.
    /// Note this only clears *our* gate — iOS keeps its own 3-per-year throttle,
    /// so on a real device the card may still decline to appear.
    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: askedKey)
    }
    #endif
}
