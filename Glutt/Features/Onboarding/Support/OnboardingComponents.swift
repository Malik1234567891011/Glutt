import SwiftUI

/// Primary CTA: 60pt capsule, Bricolage 600/19, pressed = translateY(1).
struct OnboardingPrimaryButton: View {
    let title: String
    var height: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.impact(.medium)
            action()
        } label: {
            Text(title)
                .font(OnboardingFonts.bricolage(height == 60 ? 19 : 18, 600))
                .kerning(0.2)
                .foregroundStyle(OnboardingTheme.creamText)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(OnboardingTheme.greenDeep, in: Capsule())
                .shadow(color: OnboardingTheme.warmBlack(0.14), radius: 12, y: 10)
        }
        .buttonStyle(PressOffsetStyle())
    }
}

struct PressOffsetStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.offset(y: configuration.isPressed ? 1 : 0)
    }
}

/// Goals-gate disabled state: non-interactive gray pill.
struct OnboardingDisabledPill: View {
    let title: String
    var body: some View {
        Text(title)
            .font(OnboardingFonts.bricolage(19, 600))
            .kerning(0.2)
            .foregroundStyle(OnboardingTheme.disabledText)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(OnboardingTheme.disabledBg, in: Capsule())
    }
}

/// "Maybe later" / "Not now" / "Skip tutorial" links (Nunito 700/15, muted).
struct OnboardingTextLink: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Text(title)
                .font(OnboardingFonts.nunito(15, 700))
                .foregroundStyle(OnboardingTheme.muted)
        }
        .buttonStyle(.plain)
    }
}

/// Top chrome: 40pt back circle + 8pt progress track. `overVideo` is the
/// Polly-screen glass variant. Sits at (design 60 − 54) = 6pt below safe top.
struct OnboardingChrome: View {
    enum Style { case cream, overVideo }
    let progress: Double
    var style: Style = .cream
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.impact(.light)
                onBack()
            } label: {
                MS.chevronLeft.sized(24)
                    .foregroundStyle(style == .cream ? Color(hex: 0x4A4238) : .white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(style == .cream ? AnyShapeStyle(Color.white)
                                                      : AnyShapeStyle(.white.opacity(0.24)))
                    )
                    .background(style == .overVideo ? AnyView(Circle().fill(.ultraThinMaterial)) : AnyView(EmptyView()))
                    .shadow(color: style == .cream ? OnboardingTheme.warmBlack(0.12) : .clear, radius: 3.5, y: 2)
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(style == .cream ? OnboardingTheme.warmBlack(0.09) : .white.opacity(0.32))
                    Capsule()
                        .fill(style == .cream ? OnboardingTheme.progressFill : OnboardingTheme.progressFillDark)
                        .frame(width: geo.size.width * progress)
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45), value: progress)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }
}

/// Screen H1 — Bricolage 600, tight tracking, centered, balanced wrap.
struct OnboardingHeadline: View {
    let text: String
    var size: CGFloat = 27
    var maxWidth: CGFloat = 300
    init(_ text: String, size: CGFloat = 27, maxWidth: CGFloat = 300) {
        self.text = text; self.size = size; self.maxWidth = maxWidth
    }
    var body: some View {
        Text(text)
            .font(OnboardingFonts.bricolage(size, 600))
            .kerning(-0.5)
            .lineSpacing(size * 0.18 / 2)
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.textHeading)
            .frame(maxWidth: maxWidth)
    }
}

/// Subhead — Nunito 600 14.5, muted, centered.
struct OnboardingSubhead: View {
    let text: String
    var maxWidth: CGFloat = 280
    init(_ text: String, maxWidth: CGFloat = 280) { self.text = text; self.maxWidth = maxWidth }
    var body: some View {
        Text(text)
            .font(OnboardingFonts.nunito(14.5, 600))
            .multilineTextAlignment(.center)
            .foregroundStyle(OnboardingTheme.muted)
            .frame(maxWidth: maxWidth)
    }
}

#Preview("Components") {
    VStack(spacing: 20) {
        OnboardingChrome(progress: 0.3) {}
        OnboardingHeadline("Any food rules?")
        OnboardingSubhead("Tap all that apply")
        OnboardingPrimaryButton(title: "Continue") {}
        OnboardingDisabledPill(title: "Continue")
        OnboardingTextLink(title: "Maybe later") {}
    }
    .padding(24)
    .background(OnboardingTheme.cream)
}
