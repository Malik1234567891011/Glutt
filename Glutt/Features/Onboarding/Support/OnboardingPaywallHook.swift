import Foundation

/// Single integration point for the post-onboarding paywall.
///
/// Today there is no paywall — this completes immediately. When Superwall is
/// added (separate task), register the placement here and call `completion`
/// when the paywall is dismissed, e.g.:
///
///     Superwall.shared.register(placement: "onboarding_complete") { completion() }
///
/// Keeping it isolated means onboarding code never changes when the paywall lands.
enum OnboardingPaywallHook {
    static func presentPostOnboarding(completion: @escaping () -> Void) {
        completion()
    }
}
