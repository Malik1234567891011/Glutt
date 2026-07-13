import SwiftUI

/// Pulsing/rippling highlight + bobbing "Tap here 👇" bubble over a target.
/// Purely decorative — hit-testing passes through to the phase's tap handler.
struct CoachMark: View {
    var diameter: CGFloat = 48
    var ringRadius: CGFloat? = nil // nil → circle
    var label = "Tap here 👇"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private var radius: CGFloat { ringRadius ?? (diameter + 12) / 2 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous) // ripple
                .strokeBorder(OnboardingTheme.coralBright, lineWidth: 3)
                .frame(width: diameter + 12, height: diameter + 12)
                .scaleEffect(reduceMotion ? 1 : (animating ? 2.3 : 1))
                .opacity(reduceMotion ? 0.5 : (animating ? 0 : 0.8))
                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: animating)

            RoundedRectangle(cornerRadius: radius, style: .continuous) // pulse
                .fill(OnboardingTheme.coralBright.opacity(0.16))
                .strokeBorder(OnboardingTheme.coralBright, lineWidth: 3)
                .frame(width: diameter + 12, height: diameter + 12)
                .scaleEffect(reduceMotion ? 1 : (animating ? 1.09 : 0.95))
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animating)

            Text(label) // bobbing bubble above
                .font(OnboardingFonts.nunito(13, 800))
                .foregroundStyle(.white)
                .padding(.vertical, 7).padding(.horizontal, 14)
                .background(OnboardingTheme.coralBright, in: Capsule())
                .shadow(color: OnboardingTheme.coralBright.opacity(0.55), radius: 10, y: 8)
                .fixedSize()
                .offset(y: -(diameter / 2 + 34) + (reduceMotion ? 0 : (animating ? -5 : 0)))
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animating)
        }
        .onAppear { animating = true }
        .allowsHitTesting(false)
    }
}
