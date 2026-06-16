import SwiftUI

/// Ambient, slowly drifting glow behind hero/celebration onboarding screens.
/// Built from Theme colors so it stays on-brand (cream base, warm green/tomato bloom).
struct GlowBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            Theme.Colors.background

            Circle()
                .fill(Theme.Colors.accent.opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: drift ? -90 : -60, y: drift ? -160 : -120)

            Circle()
                .fill(Theme.Colors.tomato.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: drift ? 110 : 80, y: drift ? 200 : 240)

            Circle()
                .fill(Theme.Colors.warning.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 90)
                .offset(x: drift ? 90 : 120, y: drift ? -180 : -140)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

#Preview {
    GlowBackground()
}
