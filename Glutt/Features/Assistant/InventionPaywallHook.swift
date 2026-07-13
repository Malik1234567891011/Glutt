import SuperwallKit

/// Gates the AI "Invent a dish from what I have" feature behind Glutt Premium.
///
/// Registers the `invent_recipe` placement. The gate is **fail-closed**: the
/// paid feature only runs when the user actually holds an active entitlement, so
/// a dismissed or skipped paywall never leaks the feature for free.
///
/// To temporarily disable payments again, see `docs/REENABLE-PAYMENTS.md`.
enum InventionPaywallHook {
    static func presentBeforeInventing(completion: @escaping () -> Void) {
        Superwall.shared.register(placement: "invent_recipe") {
            // Fail-closed: only run the paid feature when actually entitled.
            guard Superwall.shared.subscriptionStatus.isActive else { return }
            completion()
        }
    }
}
