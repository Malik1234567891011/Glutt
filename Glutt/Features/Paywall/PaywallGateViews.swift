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

/// The locked half of the hard paywall: an **opaque** cover over the whole app.
///
/// It used to be invisible, leaving the real tabs on show while swallowing
/// touches ("land-then-bounce"). That was dropped deliberately — an unpaid user
/// should never see the home feed, not even as scenery. Now they get this, and
/// `RootView` presents the paywall over it without waiting for a tap.
///
/// This still exists rather than the paywall simply being permanent, because
/// the paywall is dismissible (App Review expects a way out of a modal). Closing
/// it lands here, not in the app, and anything you tap opens it again.
struct PaywallGateOverlay: View {
    let onBounce: () -> Void

    var body: some View {
        ZStack {
            // A still of a full recipe library, blurred past reading. It shows
            // what is behind the wall without handing over any of it, and it
            // does not change with the viewer's own (empty) library — a real
            // blurred home screen would just be a blurred empty state.
            //
            // Blurred at runtime rather than baked in, so the radius stays
            // tunable. The asset is deliberately small and JPEG: at this radius
            // nobody can tell, and it saves ~2MB in the bundle.
            Image("paywallLockedHome")
                .resizable()
                .scaledToFill()
                // Heavy on purpose: the feed reads as colour and shape only,
                // nothing legible. Tunable in one place if it wants softening.
                .blur(radius: 22, opaque: true)
                // Blur samples past the edges, so overfill and clip rather than
                // letting soft borders show.
                .scaleEffect(1.12)
                .ignoresSafeArea()
                .clipped()

            // Lifts the copy off a busy photo and drops the contrast further,
            // so nothing underneath is readable.
            LinearGradient(
                colors: [
                    OnboardingTheme.cream.opacity(0.55),
                    OnboardingTheme.cream.opacity(0.9),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Text("Your recipes are waiting")
                    .font(OnboardingFonts.bricolage(28, 600)).kerning(-0.8)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingTheme.textHeading)
                    .padding(.bottom, 10)

                Text("Glutt Pro unlocks every recipe, your live AI chef, and the smart kitchen.")
                    .font(OnboardingFonts.nunito(15, 600))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(OnboardingTheme.mutedWarm)
                    .frame(maxWidth: 300)

                Spacer(minLength: 0)

                OnboardingPrimaryButton(title: "See plans", action: onBounce)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
        // The whole surface bounces, so a tap anywhere on the blurred feed opens
        // the paywall rather than doing nothing.
        .contentShape(Rectangle())
        .onTapGesture(perform: onBounce)
        .accessibilityLabel("Subscription required")
        .accessibilityHint("Subscribe to unlock Glutt")
    }
}
