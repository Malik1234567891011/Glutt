import SwiftUI

/// Screen 6 — top-66% full-bleed looping video with scrim to cream, floating
/// voice-caption pill, rating badge, H1, mic pill, Continue.
struct PollyHeroScreen: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                OnboardingTheme.cream.ignoresSafeArea()

                ZStack {
                    Color(hex: 0x1A140F)
                    LoopingVideoView(resource: "glutt-intro", scale: 1, yOffsetFraction: -0.10)
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0x140F0A).opacity(0.30), location: 0),
                        .init(color: .clear, location: 0.24),
                        .init(color: .clear, location: 0.52),
                        .init(color: OnboardingTheme.cream.opacity(0.55), location: 0.82),
                        .init(color: OnboardingTheme.cream, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .frame(height: geo.size.height * 0.66)
                .ignoresSafeArea(edges: .top)

                captionPill
                    .offset(y: geo.size.height * 0.185 - geo.safeAreaInsets.top)

                VStack(spacing: 0) {
                    Spacer()
                    ratingBadge.padding(.bottom, 18)
                    Text("Polly guides you through recipes, completely hands-free")
                        .font(OnboardingFonts.bricolage(29, 600)).kerning(-0.6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(OnboardingTheme.textHeading)
                        .frame(maxWidth: 330)
                    HStack(spacing: 8) {
                        MS.micFill.sized(17).foregroundStyle(OnboardingTheme.mintBright)
                        Text("Real-time voice + camera")
                            .font(OnboardingFonts.nunito(13, 800)).kerning(0.2)
                            .foregroundStyle(OnboardingTheme.greenTint)
                    }
                    .padding(.vertical, 9).padding(.horizontal, 16)
                    .background(OnboardingTheme.greenDeep, in: Capsule())
                    .padding(.top, 15).padding(.bottom, 22)
                    OnboardingPrimaryButton(title: "Continue", action: onContinue)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)
            }
        }
    }

    private var captionPill: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(RadialGradient(colors: [OnboardingTheme.mintBright, OnboardingTheme.greenDeep],
                                             center: .init(x: 0.38, y: 0.30), startRadius: 0, endRadius: 22))
                MS.graphicEqFill.sized(18).foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            Text("\u{201C}Sear it 2 more minutes, I'll tell you when to flip.\u{201D}")
                .font(OnboardingFonts.nunito(13, 600))
                .foregroundStyle(.white)
                .lineSpacing(1.5)
        }
        .padding(.vertical, 11).padding(.leading, 13).padding(.trailing, 17)
        .frame(width: 286)
        .background(Color(hex: 0x140F0A).opacity(0.44), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.28), radius: 13, y: 10)
    }

    private var ratingBadge: some View {
        HStack(spacing: 10) {
            MS.ecoFill.sized(22).foregroundStyle(OnboardingTheme.greenDeep)
                .rotationEffect(.degrees(-18))
            VStack(spacing: 2) {
                Text("4.9 ★ rated")
                    .font(OnboardingFonts.bricolage(14, 700))
                    .foregroundStyle(OnboardingTheme.textHeading)
                Text("Loved by 1M+ home cooks")
                    .font(OnboardingFonts.nunito(11, 700))
                    .foregroundStyle(OnboardingTheme.mutedWarm)
            }
            MS.ecoFill.sized(22).foregroundStyle(OnboardingTheme.greenDeep)
                .rotationEffect(.degrees(18))
                .scaleEffect(x: -1)
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
        .background(OnboardingTheme.greenDeep.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
    }
}
