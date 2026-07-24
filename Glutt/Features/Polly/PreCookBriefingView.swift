import SwiftData
import SwiftUI

/// Pre-cook rundown before Polly — same cream language as Recipe Detail, not a
/// dark cinematic overlay. One hero, clear dish gist, compact beat list, Polly
/// caption, one green CTA + skip.
struct PreCookBriefingView: View {
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe
    var scale: Double = 1
    /// `heardBriefing` — trailer was heard (or they tapped start).
    /// `awaitVerbalGo` — trailer finished naturally; Polly opens listening for
    /// a spoken "let's cook".
    let onContinue: (_ heardBriefing: Bool, _ awaitVerbalGo: Bool) -> Void

    @State private var briefing: CookBriefing?
    @State private var isLoading = true
    @State private var narrator = BriefingNarrator()
    @State private var didStartNarration = false
    @State private var didHandOff = false
    @State private var isHandingOff = false

    private let heroHeight: CGFloat = 300

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroHeader
                    creamSheet
                        .offset(y: -26)
                        .padding(.bottom, -26)
                }
            }
            .ignoresSafeArea(edges: .top)

            bottomBar
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .task { await loadBriefing() }
        .onChange(of: narrator.didFinishNaturally) { _, finished in
            guard finished, !didHandOff else { return }
            isHandingOff = true
            Haptics.impact(.soft)
            finish(heard: true, awaitVerbalGo: true)
        }
        .onDisappear { narrator.stop() }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .top) {
            RecipeImageView(recipe: recipe)
                .frame(height: heroHeight)
                .clipped()

            // Soft top chrome only — cream sheet owns the bottom of the photo.
            LinearGradient(
                colors: [Color.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: 120)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            HStack {
                circleButton(systemName: "xmark") {
                    Haptics.impact(.light)
                    finish(heard: false, awaitVerbalGo: false)
                }
                Spacer()
                Button("Skip") {
                    Haptics.impact(.light)
                    finish(heard: false, awaitVerbalGo: false)
                }
                .font(BrandFont.nunito(14.5, 750))
                .foregroundStyle(Theme.Colors.heading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(Theme.Colors.card.opacity(0.9)))
                .background(.ultraThinMaterial, in: Capsule())
                .disabled(didHandOff || isHandingOff)
                .accessibilityIdentifier("preCookBriefing.skip")
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
        .frame(height: heroHeight)
    }

    private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.Colors.heading)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Theme.Colors.card.opacity(0.85)))
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(didHandOff || isHandingOff)
    }

    // MARK: - Cream sheet

    private var creamSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Before you cook")
                .font(BrandFont.nunito(13, 750))
                .foregroundStyle(Theme.Colors.muted)
                .padding(.bottom, 8)

            Text(recipe.title)
                .font(BrandFont.bricolage(27, 700))
                .foregroundStyle(Theme.Colors.heading)
                .fixedSize(horizontal: false, vertical: true)

            if let briefing {
                HStack(spacing: 8) {
                    metaPill(briefing.timeLabel, systemImage: "clock")
                    metaPill("\(briefing.servings) servings", systemImage: "person.2")
                }
                .padding(.top, 14)

                beatList(briefing)
                    .padding(.top, 22)

                pollyCaptionBlock
                    .padding(.top, 20)
            } else if isLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.Colors.accent)
                    Text("Building your rundown…")
                        .font(BrandFont.nunito(14.5, 650))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.top, 28)
            }

            // Room for the pinned bottom bar.
            Color.clear.frame(height: 140)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.background)
        .clipShape(.rect(topLeadingRadius: 30, topTrailingRadius: 30))
    }

    private func metaPill(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(BrandFont.nunito(12.5, 750))
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.Colors.surface2))
    }

    // MARK: - Beats (compact vertical list)

    private func beatList(_ briefing: CookBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The cook, in brief")
                .font(BrandFont.nunito(13, 750))
                .foregroundStyle(Theme.Colors.muted)

            ScrollViewReader { proxy in
                VStack(spacing: 6) {
                    ForEach(Array(briefing.beats.enumerated()), id: \.element.id) { index, beat in
                        beatRow(beat, index: index, active: narrator.beatIndex == index)
                            .id(beat.id)
                    }
                }
                .onChange(of: narrator.beatIndex) { _, newValue in
                    guard let newValue, briefing.beats.indices.contains(newValue) else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(briefing.beats[newValue].id, anchor: .center)
                    }
                }
            }
        }
    }

    private func beatRow(_ beat: CookBriefing.Beat, index: Int, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(BrandFont.nunito(13, 800))
                .foregroundStyle(active ? Theme.Colors.creamText : Theme.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(active ? Theme.Colors.accent : Theme.Colors.surface2)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(beat.title)
                    .font(BrandFont.nunito(15.5, 800))
                    .foregroundStyle(Theme.Colors.heading)
                    .fixedSize(horizontal: false, vertical: true)
                if !beat.detail.isEmpty {
                    Text(beat.detail)
                        .font(BrandFont.nunito(13, 600))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(active ? Theme.Colors.greenTint : Theme.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    active ? Theme.Colors.accent.opacity(0.18) : Theme.Colors.border.opacity(0.55),
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.22), value: active)
    }

    // MARK: - Polly caption

    private var pollyCaptionBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: narrator.isSpeaking || isHandingOff ? "waveform" : "text.bubble.fill")
                    .symbolEffect(
                        .variableColor.iterative,
                        isActive: narrator.isSpeaking || isHandingOff
                    )
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)

                Text(statusLabel)
                    .font(BrandFont.nunito(13, 750))
                    .foregroundStyle(Theme.Colors.accent)

                Spacer(minLength: 0)

                if narrator.isSpeaking {
                    Button("Mute") {
                        Haptics.impact(.light)
                        narrator.stop()
                    }
                    .font(BrandFont.nunito(13, 750))
                    .foregroundStyle(Theme.Colors.muted)
                    .buttonStyle(.plain)
                }
            }

            Text(displayCaption)
                .font(BrandFont.nunito(16, 650))
                .foregroundStyle(Theme.Colors.heading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: displayCaption)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.Colors.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.Colors.border.opacity(0.55), lineWidth: 1)
        )
    }

    private var statusLabel: String {
        if isHandingOff { return "Polly’s listening" }
        if briefing == nil { return "Getting ready" }
        if narrator.isSpeaking {
            return narrator.isUsingPollyVoice ? "Polly’s rundown" : "Rundown"
        }
        return "Rundown ready"
    }

    private var displayCaption: String {
        if isHandingOff {
            return "Say “let’s cook” when you’re ready — or tap below."
        }
        if !narrator.caption.isEmpty { return narrator.caption }
        if isLoading { return "Putting together a quick look at this cook…" }
        return "A short look at what you’re about to make."
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.impact(.medium)
                finish(heard: true, awaitVerbalGo: false)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Colors.brightAccent)
                    Text(primaryCTATitle)
                        .font(BrandFont.nunito(16.5, 800))
                        .foregroundStyle(Theme.Colors.creamText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(Theme.Colors.accent))
                .shadow(color: Theme.Colors.textPrimary.opacity(0.14), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .disabled((isLoading && briefing == nil) || didHandOff || isHandingOff)
            .accessibilityIdentifier("preCookBriefing.start")

            Button("Skip summary") {
                Haptics.impact(.light)
                finish(heard: false, awaitVerbalGo: false)
            }
            .font(BrandFont.nunito(14.5, 700))
            .foregroundStyle(Theme.Colors.muted)
            .buttonStyle(.plain)
            .disabled(didHandOff || isHandingOff)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            Theme.Colors.background
                .shadow(color: Theme.Colors.textPrimary.opacity(0.06), radius: 16, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var primaryCTATitle: String {
        if isHandingOff { return "Connecting Polly…" }
        return recipe.isCookingBasic ? "Learn with Polly" : "Cook with Polly"
    }

    // MARK: - Logic

    private func loadBriefing() async {
        isLoading = true
        let plan = await CookPlanCompiler.compile(recipe: recipe, scale: scale)
        let built = CookBriefingBuilder.build(recipe: recipe, plan: plan)
        briefing = built
        isLoading = false
        guard !didStartNarration else { return }
        didStartNarration = true
        try? await Task.sleep(for: .milliseconds(220))
        narrator.narrate(built)
    }

    private func finish(heard: Bool, awaitVerbalGo: Bool) {
        guard !didHandOff else { return }
        didHandOff = true
        narrator.stop()
        dismiss()
        DispatchQueue.main.async {
            onContinue(heard, awaitVerbalGo)
        }
    }
}
