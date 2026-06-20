import SwiftUI
import PhosphorSwift

/// First onboarding screen: a food-photo hero on a sage panel + the highlighted
/// headline and a single "next" CTA.
struct WelcomeScreen: View {
    let onStart: () -> Void
    @State private var float = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            heroPanel
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HighlightHeadline(words: [
                    HeadlineWord(text: "Cook", style: .green),
                    HeadlineWord(text: "smarter", style: .amber),
                    HeadlineWord(text: "not", style: .plain),
                    HeadlineWord(text: "harder", style: .tomato),
                ])
                Text("Save recipes from anywhere, cook what you already have, and waste less — all in one place.")
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
            footer
        }
        .padding(.top, Theme.Spacing.lg)
        .background(Theme.Colors.background)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { float = true }
        }
    }

    private var heroPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Theme.Colors.sagePanel)
            // scattered decorative accents
            Ph.plus.bold.resizable().scaledToFit().frame(width: 22, height: 22)
                .foregroundColor(Theme.Colors.tomato).offset(x: -118, y: -118)
            Ph.sparkle.fill.resizable().scaledToFit().frame(width: 26, height: 26)
                .foregroundColor(Theme.Colors.warning).offset(x: 122, y: -92)
            Ph.plus.bold.resizable().scaledToFit().frame(width: 14, height: 14)
                .foregroundColor(Theme.Colors.accent).offset(x: 118, y: 120)
            Circle().fill(Theme.Colors.tomato).frame(width: 10, height: 10).offset(x: -120, y: 104)
            // the photo card
            Image("pestoGnocchiMealPrep")
                .resizable().scaledToFill()
                .frame(width: 200, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Theme.Colors.textPrimary.opacity(0.18), radius: 18, y: 10)
                .rotationEffect(.degrees(float ? -3 : -1))
            // floating "ready" pill
            HStack(spacing: 6) {
                Ph.clock.regular.resizable().scaledToFit().frame(width: 13, height: 13)
                Text("Ready in 25 min").font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.Colors.card, in: Capsule())
            .shadow(color: Theme.Colors.textPrimary.opacity(0.1), radius: 8, y: 3)
            .offset(y: 150)
        }
        .frame(height: 366)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var footer: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                PageDots(count: 6, index: 0)
                Spacer()
                Button(action: onStart) {
                    HStack(spacing: 8) {
                        Text("next").font(.system(size: 16, weight: .bold, design: .rounded))
                        Ph.arrowRight.bold.resizable().scaledToFit().frame(width: 16, height: 16)
                    }
                    .foregroundStyle(Theme.Colors.creamText)
                    .padding(.horizontal, 26).padding(.vertical, 15)
                    .background(Theme.Colors.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if let privacyURL = URL(string: "https://glutt.org/privacy") {
                Link("Privacy Policy", destination: privacyURL)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
    }
}

#Preview {
    WelcomeScreen(onStart: {})
}
