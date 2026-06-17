/// Single integration point for the post-onboarding paywall.
///
/// ⚠️ PAYWALL TEMPORARILY DISABLED FOR THE FREE LAUNCH.
/// Glutt ships free while the Paid Apps Agreement is pending (DUNS in
/// progress), so onboarding finishes immediately with no paywall.
///
/// The integration is intentionally kept as a single no-op seam so payments can
/// be switched back on with a one-line change. To re-enable, see
/// `docs/REENABLE-PAYMENTS.md`.
enum OnboardingPaywallHook {
    static func presentPostOnboarding(completion: @escaping () -> Void) {
        // Free launch: no paywall — always continue.
        // Re-enable per docs/REENABLE-PAYMENTS.md:
        //   Superwall.shared.register(placement: "onboarding_complete") { completion() }
        completion()
    }
}
