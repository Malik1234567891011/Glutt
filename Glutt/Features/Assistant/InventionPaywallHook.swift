import SuperwallKit

/// Gates the AI "Invent a dish from what I have" feature behind Premium.
///
/// Registers the `invent_recipe` placement. The campaign for this placement is
/// configured as **gated** in the Superwall dashboard, so the `completion` block
/// runs only when the user has an active entitlement — immediately for current
/// subscribers, or right after they subscribe from the paywall. If a
/// non-subscriber closes the paywall, `completion` does NOT run: that is the gate.
///
/// Mirrors `OnboardingPaywallHook` so the paywall stays a single, isolated concern.
enum InventionPaywallHook {
    static func presentBeforeInventing(completion: @escaping () -> Void) {
        Superwall.shared.register(placement: "invent_recipe") {
            // Fail-closed gate: only run the paid feature when the user is
            // actually entitled. Superwall calls this block immediately for
            // active subscribers, and again right after a purchase completes
            // (status flips to active before the block fires). A non-subscriber
            // who merely dismisses the paywall stays inactive here, so the
            // feature never unlocks for free — independent of the campaign's
            // gating toggle.
            guard Superwall.shared.subscriptionStatus.isActive else { return }
            completion()
        }
    }
}
