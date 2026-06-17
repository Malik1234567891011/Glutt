import SwiftUI

/// A pulsing "tap here" coach mark drawn on top of a tutorial screenshot.
/// Fills the frame it is given (sized to the target button by `WalkthroughFrame`)
/// and never intercepts touches.
struct CoachMark: View {
    let pointer: TutorialStep.Pointer
    let showsLabel: Bool
    /// Increment to fire a one-shot, larger "you missed" nudge.
    let nudgeToken: Int

    @State private var ripple = false
    @State private var breathe = false
    @State private var nudge = false

    var body: some View {
        ZStack {
            // Expanding "radar" ripple — fades as it grows past the button.
            Circle()
                .stroke(Theme.Colors.accent.opacity(0.9), lineWidth: 3)
                .scaleEffect(ripple ? 2.2 : 1.0)
                .opacity(ripple ? 0 : 0.8)

            // Steady ring that gently breathes on the button itself.
            Circle()
                .fill(Theme.Colors.accent.opacity(0.12))
                .overlay(Circle().stroke(Theme.Colors.accent, lineWidth: 3))
                .scaleEffect(breathe ? 1.08 : 0.94)
        }
        .scaleEffect(nudge ? 1.28 : 1.0)
        .overlay(alignment: pointer == .down ? .top : .bottom) {
            if showsLabel {
                label.fixedSize().offset(y: pointer == .down ? -18 : 18)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                ripple = true
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .onChange(of: nudgeToken) { _, _ in
            withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) { nudge = true }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.16)) { nudge = false }
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if pointer == .up { Text("👆") }
            Text("Tap here").font(.caption2.weight(.bold)).foregroundStyle(.white)
            if pointer == .down { Text("👇") }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.Colors.accent, in: Capsule())
    }
}

#Preview {
    ZStack {
        Theme.Colors.background
        CoachMark(pointer: .up, showsLabel: true, nudgeToken: 0)
            .frame(width: 56, height: 56)
    }
}
