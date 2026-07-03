/// Gates live "Cook with Polly" sessions.
///
/// ⚠️ PAYWALL TEMPORARILY DISABLED FOR THE FREE LAUNCH.
/// While Glutt ships free (Paid Apps Agreement pending — DUNS in progress),
/// Polly sessions are unlocked for everyone. The completion block always runs.
///
/// Kept as a single no-op seam so the Premium gate can be switched back on with
/// a one-line change. To re-enable, see `docs/REENABLE-PAYMENTS.md`.
enum PollyPaywallHook {
    static func run(completion: @escaping () -> Void) {
        // Free launch: feature unlocked for everyone — always run.
        // Re-enable the gate per docs/REENABLE-PAYMENTS.md:
        //   Superwall.shared.register(placement: "polly_session") {
        //       guard Superwall.shared.subscriptionStatus.isActive else { return }
        //       completion()
        //   }
        completion()
    }
}
