import SwiftUI

/// First onboarding screen: branded hero over the ambient glow + one CTA.
struct WelcomeScreen: View {
    let onStart: () -> Void

    @State private var float = false

    var body: some View {
        ZStack {
            GlowBackground()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.card)
                        .frame(width: 200, height: 260)
                        .shadow(color: Theme.Colors.textPrimary.opacity(0.12), radius: 18, y: 8)
                        .overlay(
                            VStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 56))
                                    .foregroundStyle(Theme.Colors.accent)
                                Text("Glutt")
                                    .font(.gluttLargeTitle)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                        )
                        .rotationEffect(.degrees(float ? -3 : 3))
                        .offset(y: float ? -8 : 8)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Your kitchen, sorted.")
                        .font(.gluttLargeTitle)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Save recipes from anywhere, cook what you already have, and waste less — all in one place.")
                        .font(.gluttBody)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.md)
                }

                Spacer()

                VStack(spacing: Theme.Spacing.sm) {
                    Button("Get started", action: onStart)
                        .buttonStyle(.gluttPrimary)

                    if let privacyURL = URL(string: "https://glutt.org/privacy") {
                        Link("Privacy Policy", destination: privacyURL)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                float = true
            }
        }
    }
}

#Preview {
    WelcomeScreen(onStart: {})
}
