import SwiftUI

/// Shown while `Entitlements` is resolving the tier at cold launch.
/// A calm cream field matching the app identity — it flashes for well under a
/// second, so it stays deliberately minimal.
///
/// This is the only full-screen cover the paywall still owns. The hard-paywall
/// build also had a `PaywallGateOverlay`: an opaque blurred still of a recipe
/// library that sat over the whole app for anyone without a subscription. It
/// went with the hard paywall itself. Free users now get the real app, and the
/// wall is drawn on the individual Pro controls instead (see `PremiumFeature`).
/// Its `paywallLockedHome` asset is now unreferenced and can be dropped from the
/// catalog whenever the bundle size is worth a separate commit.
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
