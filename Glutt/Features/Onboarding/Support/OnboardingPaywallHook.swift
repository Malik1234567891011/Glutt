import SuperwallKit

/// Single integration point for the post-onboarding paywall.
///
/// Registers the `onboarding_complete` placement. Superwall presents the paywall
/// configured for that placement in the dashboard; `completion` runs from the
/// feature block — after the user dismisses/skips the paywall, immediately if the
/// user is already subscribed, or immediately if no paywall can be shown
/// (no network / no matching campaign). That "fail-open" behavior guarantees
/// onboarding always finishes.
///
/// Keeping it isolated means onboarding code never changes when the paywall changes.
enum OnboardingPaywallHook {
    static func presentPostOnboarding(completion: @escaping () -> Void) {
        Superwall.shared.register(placement: "onboarding_complete") {
            completion()
        }
    }
}
