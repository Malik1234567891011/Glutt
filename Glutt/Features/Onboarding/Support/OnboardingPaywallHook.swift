import SuperwallKit

/// Single integration point for the post-onboarding paywall.
///
/// Registers the `onboarding_complete` placement so Superwall can present the
/// paywall (campaign "Glutt" → paywall 234287) when onboarding finishes. In
/// automatic mode the `completion` block runs once the paywall is dismissed
/// (whether the user purchased or the audience filter skipped the paywall).
///
/// To temporarily disable payments again, see `docs/REENABLE-PAYMENTS.md`.
enum OnboardingPaywallHook {
    static func presentPostOnboarding(completion: @escaping () -> Void) {
        Superwall.shared.register(placement: "onboarding_complete") {
            completion()
        }
    }
}
