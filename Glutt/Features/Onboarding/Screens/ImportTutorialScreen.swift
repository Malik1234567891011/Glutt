import SwiftUI

/// Interactive, ReciMe-style walkthrough of "save from anywhere → it's in Glutt".
/// The user taps the highlighted spot on each real screenshot to advance:
/// Share icon → "Share to…" → Glutt. Performs NO real import; the end CTA hands
/// off to the real importer.
struct ImportTutorialScreen: View {
    let onImportNow: () -> Void
    let onFinish: () -> Void

    @State private var model = TutorialFlowModel()

    var body: some View {
        ZStack {
            GlowBackground()

            VStack(spacing: Theme.Spacing.lg) {
                header
                Spacer(minLength: 0)
                stage
                Spacer(minLength: 0)
                footer
            }
            .padding(.top, Theme.Spacing.md)

            if model.currentStep != nil { skipButton }
        }
        .animation(.spring(duration: 0.45), value: model.phase)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(model.headline)
                .font(.gluttLargeTitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textPrimary)
                .id(model.headline) // re-triggers the transition on change
                .transition(.opacity)
            if model.currentStep != nil {
                Text("Also works with TikTok, Pinterest, Safari & more.")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    // MARK: - Stage

    @ViewBuilder private var stage: some View {
        switch model.phase {
        case .walkthrough:
            if let step = model.currentStep {
                WalkthroughFrame(
                    step: step,
                    nudgeToken: model.nudgeToken,
                    onHotspotTap: { model.tapHotspot() },
                    onMiss: { model.tapMiss() }
                )
                .padding(.horizontal, Theme.Spacing.md)
                .transition(.opacity)
            }
        case .importing:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.large)
                Image(systemName: "fork.knife")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.Colors.accent)
            }
            .task {
                try? await Task.sleep(for: .seconds(1.1))
                model.tapHotspot() // importing -> success
            }
        case .success, .cta:
            savedCard
        }
    }

    // MARK: - Footer

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .success:
            // Brief beat on the saved card before the CTA slides in.
            Color.clear
                .frame(height: 1)
                .task {
                    try? await Task.sleep(for: .seconds(0.6))
                    model.tapHotspot() // success -> cta
                }
        case .cta:
            VStack(spacing: Theme.Spacing.sm) {
                Button("Import my first recipe", action: onImportNow)
                    .buttonStyle(.gluttPrimary)
                Button("I'll explore on my own", action: onFinish)
                    .buttonStyle(.gluttSecondary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        default:
            EmptyView()
        }
    }

    private var skipButton: some View {
        VStack {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.md)
            }
            Spacer()
        }
    }

    // MARK: - Saved result (presentational only — no Recipe model / network)

    /// A few real ingredients from the demoed reel, so the saved card reads like an
    /// actual recipe rather than a bare title. Presentational only.
    private let savedIngredients = [
        "3 packs Otoki Cheesy Ramen",
        "1 lb chicken breast",
        "1 cup buttermilk",
        "Mozzarella + heavy cream",
        "Hot honey glaze",
    ]

    private var savedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Colors.successTint)
                    .frame(width: 56, height: 56)
                    .overlay(Text("🍜").font(.title))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crispy hot honey chicken bites")
                        .font(.gluttHeadline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Saved to your recipes")
                        .font(.gluttCaption)
                        .foregroundStyle(Theme.Colors.accent)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
                    .font(.title2)
            }

            Divider().padding(.vertical, 2)

            Text("Ingredients")
                .font(.gluttCaption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(savedIngredients, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.accent.opacity(0.7))
                        Text(item)
                            .font(.gluttCaption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                Text("+ 4 more")
                    .font(.gluttCaption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.leading, 20)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: Theme.Colors.textPrimary.opacity(0.1), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

#Preview {
    ImportTutorialScreen(onImportNow: {}, onFinish: {})
}
