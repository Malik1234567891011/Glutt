import SwiftUI

/// "How do I get recipes in here?" — the answer, visually. The share-sheet
/// path is the best one (save straight from TikTok/IG/Safari) but the least
/// obvious, so it gets top billing and a step-by-step walkthrough.
struct ImportGuideView: View {
    @Environment(\.dismiss) private var dismiss

    /// Optional jump straight into the paste-a-link flow.
    var onPasteLink: (() -> Void)?

    @State private var isShowingShareSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    intro

                    methodCard(
                        number: 1,
                        icon: Ph.export.regular.resizable().scaledToFit().frame(width: 22, height: 22),
                        title: "Share from any app",
                        body: "Watching a recipe on TikTok, Instagram, YouTube, Pinterest, or Reddit? Tap the share button, pick Glutt, and it imports itself. The best way to save.",
                        actionLabel: "Show me how",
                        action: {
                            Haptics.impact(.medium)
                            isShowingShareSetup = true
                        }
                    )

                    methodCard(
                        number: 2,
                        icon: Ph.link.regular.resizable().scaledToFit().frame(width: 22, height: 22),
                        title: "Paste a link",
                        body: "Copy any recipe link — a website, a video, anything — and paste it in. Glutt reads the page and pulls out the recipe.",
                        actionLabel: onPasteLink == nil ? nil : "Paste a link now",
                        action: {
                            Haptics.impact(.medium)
                            if let onPasteLink {
                                dismiss()
                                onPasteLink()
                            }
                        }
                    )

                    methodCard(
                        number: 3,
                        icon: Ph.image.regular.resizable().scaledToFit().frame(width: 22, height: 22),
                        title: "Snap a screenshot",
                        body: "A cookbook page, a friend's text, a recipe with no link — screenshot it and Glutt reads the text right on your phone.",
                        actionLabel: nil,
                        action: {}
                    )
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Getting recipes in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingShareSetup) {
                ShareSheetSetupView()
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Three ways to save a recipe")
                .font(.gluttLargeTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Glutt is built around your recipes. However you find them, here's how to get them in.")
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func methodCard<Icon: View>(
        number: Int,
        icon: Icon,
        title: String,
        body: String,
        actionLabel: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    icon
                        .foregroundStyle(Theme.Colors.accent)
                }
                Text(title)
                    .font(.gluttHeadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            Text(body)
                .font(.gluttBody)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let actionLabel {
                Button(actionLabel, action: action)
                    .buttonStyle(.gluttPillFilled)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// ReciMe-style walkthrough for saving straight from the iOS share sheet,
/// including the optional "pin Glutt to Favorites" steps. Schematic, native
/// illustrations — no screenshots to go stale across iOS versions.
struct ShareSheetSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var step = 0

    private struct Step: Identifiable {
        let id = Int.random(in: 0...Int.max)
        let title: String
        let detail: String
        let illustration: Illustration
    }

    private enum Illustration {
        case shareButton
        case shareSheet(highlightMore: Bool)
        case favorites
        case openApp
    }

    private let steps: [Step] = [
        Step(
            title: "Tap Share on any recipe",
            detail: "In TikTok, Instagram, YouTube, Pinterest, Reddit, or Safari, hit the share button — the square with the arrow.",
            illustration: .shareButton
        ),
        Step(
            title: "Pick Glutt",
            detail: "Find Glutt in the row of apps and tap it. Don't see it? Tap “More” at the end of the row to reveal it.",
            illustration: .shareSheet(highlightMore: false)
        ),
        Step(
            title: "Pin it for one tap (optional)",
            detail: "In that app row, tap “More” → “Edit”, tap the ⊕ next to Glutt, drag it to the top, then tap Done. Now Glutt is always one tap away.",
            illustration: .favorites
        ),
        Step(
            title: "Open Glutt to finish",
            detail: "Glutt saves the link and pulls out the recipe. Open the app and it's waiting for you to review and save.",
            illustration: .openApp
        ),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $step) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        stepPage(index: index, step: step)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button(step < steps.count - 1 ? "Next" : "Got it") {
                    if step < steps.count - 1 {
                        Haptics.impact(.medium)
                        withAnimation { step += 1 }
                    } else {
                        Haptics.notify(.success)
                        dismiss()
                    }
                }
                .buttonStyle(.gluttPrimary)
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Save from the share sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                UserPrefs.current(in: context).hasSeenShareGuide = true
            }
        }
    }

    private func stepPage(index: Int, step: Step) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)

            illustration(step.illustration)
                .frame(height: 240)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Step \(index + 1)")
                    .font(.gluttCaption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(step.title)
                    .font(.gluttTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(step.detail)
                    .font(.gluttBody)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer(minLength: 0)
        }
        .padding(.bottom, Theme.Spacing.xl)
    }

    // MARK: - Schematic illustrations

    @ViewBuilder
    private func illustration(_ kind: Illustration) -> some View {
        switch kind {
        case .shareButton:
            ZStack {
                phoneFrame
                Ph.export.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Theme.Colors.accent)
            }
        case .shareSheet:
            ZStack {
                phoneFrame
                appRow(highlightGlutt: true)
            }
        case .favorites:
            ZStack {
                phoneFrame
                favoritesList
            }
        case .openApp:
            ZStack {
                phoneFrame
                VStack(spacing: Theme.Spacing.sm) {
                    gluttGlyph(size: 64)
                    Ph.checkCircle.fill
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
    }

    private var phoneFrame: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Theme.Colors.card)
            .frame(width: 150, height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
            )
            .shadow(color: Theme.Colors.textPrimary.opacity(0.08), radius: 8, y: 4)
    }

    private func appRow(highlightGlutt: Bool) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("Share")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 10) {
                appBlob(color: .gray.opacity(0.4), glyph: nil)
                gluttGlyph(size: 34, label: "Glutt")
                appBlob(color: .gray.opacity(0.4), glyph: nil)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var favoritesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Favorites")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 6) {
                gluttGlyph(size: 22)
                RoundedRectangle(cornerRadius: 3).fill(Theme.Colors.border).frame(width: 60, height: 8)
                Spacer()
                Ph.list.regular
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(6)
            .background(Theme.Colors.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 6) {
                    Circle().fill(Theme.Colors.border).frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 3).fill(Theme.Colors.border).frame(width: 50, height: 8)
                    Spacer()
                }
                .padding(6)
            }
        }
        .frame(width: 120)
    }

    private func appBlob(color: Color, glyph: String?) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color)
            .frame(width: 34, height: 34)
    }

    private func gluttGlyph(size: CGFloat, label: String? = nil) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.Colors.accent)
                .frame(width: size, height: size)
                .overlay(
                    Ph.forkKnife.bold
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.5, height: size * 0.5)
                        .foregroundStyle(.white)
                )
            if let label {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }
}
