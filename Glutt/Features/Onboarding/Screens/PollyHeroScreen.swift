import SwiftUI

/// Screen 6 backdrop — the chef-cooking footage. Rendered as its own coordinator
/// layer so it can cross-fade in/out while the copy slides. Fades to cream at the
/// top (for the progress bar) and bottom (for the copy).
struct PollyBackdrop: View {
    var body: some View {
        LoopingVideoView(resource: "chef-cooking")
            .ignoresSafeArea()
            .overlay(scrim.ignoresSafeArea())
    }

    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: OnboardingTheme.cream, location: 0),
            .init(color: OnboardingTheme.cream.opacity(0), location: 0.16),
            .init(color: OnboardingTheme.cream.opacity(0), location: 0.44),
            .init(color: OnboardingTheme.cream.opacity(0.92), location: 0.60),
            .init(color: OnboardingTheme.cream, location: 0.70),
            .init(color: OnboardingTheme.cream, location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
    }
}

/// Screen 6 copy — credentials badge, headline, voice+camera pill, Continue.
/// Transparent, sitting over `PollyBackdrop`; the coordinator slides this in
/// while the backdrop fades.
struct PollyHeroScreen: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ratingBadge

            Text("Chef guides you through recipes, completely hands-free")
                .font(OnboardingFonts.bricolage(28, 700)).kerning(-0.6)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .foregroundStyle(OnboardingTheme.textHeading)
                .frame(maxWidth: 330)
                .padding(.top, 18)

            micPill.padding(.top, 15)

            Spacer().frame(height: 30)

            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    /// "4.9 ★ rated / Loved by 1M+ home cooks", laurel wreaths flanking.
    private var ratingBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 33, weight: .medium))
                .foregroundStyle(OnboardingTheme.greenDeep)
            VStack(spacing: 1) {
                Text("4.9 ★ rated")
                    .font(OnboardingFonts.bricolage(13.5, 700))
                    .foregroundStyle(OnboardingTheme.textHeading)
                Text("Loved by 1M+ home cooks")
                    .font(OnboardingFonts.nunito(10.5, 700))
                    .foregroundStyle(OnboardingTheme.mutedWarm)
            }
            Image(systemName: "laurel.trailing")
                .font(.system(size: 33, weight: .medium))
                .foregroundStyle(OnboardingTheme.greenDeep)
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
        .shadow(color: OnboardingTheme.warmBlack(0.14), radius: 12, y: 6)
    }

    /// Compact voice+camera label (no icon).
    private var micPill: some View {
        Text("Real-time voice + camera")
            .font(OnboardingFonts.nunito(12, 800)).kerning(0.2)
            .foregroundStyle(OnboardingTheme.greenTint)
            .padding(.vertical, 6.5).padding(.horizontal, 14)
            .background(OnboardingTheme.greenDeep, in: Capsule())
    }
}
