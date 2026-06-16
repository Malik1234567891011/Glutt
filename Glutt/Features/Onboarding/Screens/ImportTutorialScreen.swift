import SwiftUI

enum TutorialPhase: Int, CaseIterable {
    case intro, showPost, coachTapShare, shareSheet, importing, success, cta

    var next: TutorialPhase? { TutorialPhase(rawValue: rawValue + 1) }
    var isTerminal: Bool { self == .cta }
}

/// Scripted, deterministic walkthrough of "save from anywhere → it's in Glutt".
/// Performs NO real import; the optional end CTA hands off to the real importer.
struct ImportTutorialScreen: View {
    let onImportNow: () -> Void
    let onFinish: () -> Void

    @State private var phase: TutorialPhase = .intro

    var body: some View {
        ZStack {
            GlowBackground()

            VStack(spacing: Theme.Spacing.lg) {
                Text(headline)
                    .font(.gluttLargeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xl)
                    .id(headline) // re-triggers transition on change
                    .transition(.opacity)

                Spacer()
                stage
                Spacer()

                if phase == .cta {
                    VStack(spacing: Theme.Spacing.sm) {
                        Button("Import my first recipe", action: onImportNow)
                            .buttonStyle(.gluttPrimary)
                        Button("I'll explore on my own", action: onFinish)
                            .buttonStyle(.gluttSecondary)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task { await runScript() }
    }

    private var headline: String {
        switch phase {
        case .intro, .showPost: "Found a recipe you love?"
        case .coachTapShare, .shareSheet: "Just tap Share → Glutt"
        case .importing: "Pulling out the recipe…"
        case .success, .cta: "That's it — it's saved. ✨"
        }
    }

    @ViewBuilder private var stage: some View {
        switch phase {
        case .intro, .showPost, .coachTapShare:
            postCard
        case .shareSheet:
            ShareSheetMock(highlightGlutt: true)
                .padding(.horizontal, Theme.Spacing.md)
        case .importing:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.large)
                Image(systemName: "fork.knife")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.accent)
            }
        case .success, .cta:
            savedCard
        }
    }

    /// Generic social-post stand-in (original art, not a real platform's chrome).
    private var postCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.accent.opacity(0.15))
                .frame(height: 180)
                .overlay(Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Colors.accent))
            HStack {
                Text("15-min garlic butter noodles")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                ZStack {
                    Circle().fill(Theme.Colors.accent.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .scaleEffect(phase == .coachTapShare ? 1.18 : 1)
                .overlay(alignment: .bottom) {
                    if phase == .coachTapShare {
                        Text("Tap here")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.Colors.accent, in: Capsule())
                            .offset(y: 26)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.1), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.md)
    }

    /// Pre-baked "imported" result — presentational only, no Recipe model / network.
    private var savedCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Theme.Colors.successTint)
                .frame(width: 64, height: 64)
                .overlay(Text("🍝").font(.title))
            VStack(alignment: .leading, spacing: 4) {
                Text("Garlic butter noodles")
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Saved to your recipes")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.accent)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.accent)
                .font(.title2)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.1), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func runScript() async {
        let timings: [(TutorialPhase, Double)] = [
            (.showPost, 1.4), (.coachTapShare, 1.6), (.shareSheet, 1.8),
            (.importing, 1.4), (.success, 1.4), (.cta, 0.6),
        ]
        for (next, delay) in timings {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }
            withAnimation(.spring(duration: 0.5)) { phase = next }
        }
    }
}

#Preview {
    ImportTutorialScreen(onImportNow: {}, onFinish: {})
}
