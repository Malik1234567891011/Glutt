import SwiftUI

/// Shown while `SubscriptionGate` is resolving entitlement at cold launch.
/// A calm cream field matching the app identity — it flashes for well under a
/// second, so it stays deliberately minimal.
struct GateSplashView: View {
    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()
            ProgressView()
                .tint(Theme.Colors.accent)
        }
    }
}

/// The "bounce" half of the hard paywall. When the gate is `.locked` this sits
/// invisibly over the whole app: the tabs stay visible underneath (the app
/// looks real), but it swallows every touch and re-presents the paywall instead
/// of letting it through. No X, no free actions — any tap bounces.
struct PaywallGateOverlay: View {
    let onBounce: () -> Void

    var body: some View {
        // A full-screen plain button is the most reliable "swallow everything"
        // layer: sitting on top and hit-testable, it intercepts every touch
        // before the content beneath can receive it — so taps bounce and
        // scrolls/drags simply do nothing. `.plain` + a clear label means no
        // visible press highlight, so the tabs underneath still look live.
        Button(action: onBounce) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .ignoresSafeArea()
        .accessibilityLabel("Subscription required")
        .accessibilityHint("Subscribe to unlock Glutt")
    }
}
