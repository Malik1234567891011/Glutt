import SwiftData
import SwiftUI

/// The screen a cook looks at while Polly is teaching them to hold a knife.
///
/// Almost nothing on it, on purpose. Their eyes are supposed to be on their own
/// hand, not on a phone, so this exists to answer two questions at a glance: is
/// she listening, and how long do I have to keep holding this. Everything else
/// is her voice.
struct SkillCoachView: View {
    let skill: Skill
    let check: SkillVisualCheck

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Built here rather than taken from the environment, because nothing puts
    /// one there: `PollySessionController` owns its own and a lesson is not a
    /// cook. Its own coordinator also means a lesson can never inherit a phone
    /// camera someone turned on during a recipe.
    @State private var visuals = PollyVisualSourceCoordinator(
        phone: PhoneCameraVisualSource(camera: PollyCameraController()))
    @State private var session: SkillCoachSession?

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.lg) {
                header
                Spacer(minLength: 0)
                centrepiece
                Spacer(minLength: 0)
                transcript
                footer
            }
            .padding(Theme.Spacing.lg)
        }
        .task {
            guard session == nil else { return }
            let new = SkillCoachSession(skill: skill, check: check, visuals: visuals)
            session = new
            await new.start(context: context)
        }
        .onDisappear {
            let closing = session
            Task { await closing?.end() }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 4) {
            Text(skill.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Colors.heading)
            Text(statusLine)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// The ring, or whatever has replaced it.
    @ViewBuilder private var centrepiece: some View {
        switch session?.stage ?? .teaching {
        case .holding(let progress):
            HoldRing(progress: progress, seconds: check.holdSeconds)
        case .analysing:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView().controlSize(.large).tint(Theme.Colors.accent)
                Text("Polly is checking your grip")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        case .learned:
            resultBadge(
                glyph: "checkmark.seal.fill",
                tint: Theme.Colors.accent,
                title: "That is your chef's knife grip")
        case .safetyStop(let reason):
            resultBadge(glyph: "hand.raised.fill", tint: Theme.Colors.tomato, title: reason)
        case .visionUnavailable:
            resultBadge(
                glyph: "eye.slash",
                tint: Theme.Colors.amber,
                title: "I cannot get a clear enough view")
        case .teaching, .coaching:
            listeningMark
        }
    }

    private var listeningMark: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.greenTint)
                .frame(width: 132, height: 132)
            Image(systemName: (session?.isSpeaking ?? false) ? "waveform" : "ear")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Theme.Colors.accent)
                .symbolEffect(.variableColor.iterative, isActive: session?.isSpeaking ?? false)
        }
    }

    private func resultBadge(glyph: String, tint: Color, title: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: glyph)
                .font(.system(size: 52))
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    /// Her last line, for the cook who was looking at their hand and missed it.
    @ViewBuilder private var transcript: some View {
        if let caption = session?.caption, !caption.isEmpty {
            Text(caption)
                .font(.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if session?.stage == .visionUnavailable {
                Button("Try the check again") { session?.checkNow() }
                    .buttonStyle(SecondaryButtonStyle())
            } else if session?.canCheck == true {
                Button("Check my grip") { session?.checkNow() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button("Done") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var statusLine: String {
        switch session?.phase {
        case .idle, .connecting, .none: "Getting Polly ready"
        case .failed(let why): why
        case .ended: "Lesson finished"
        case .live:
            switch session?.stage {
            case .holding: "Hold still"
            case .analysing: "Looking"
            case .safetyStop: "Put the knife down"
            default: "Talk to her whenever you like"
            }
        }
    }
}

/// The five second ring.
///
/// Counts down rather than up, and is driven by the real capture rather than
/// its own animation, so it can never finish while frames are still coming in.
private struct HoldRing: View {
    let progress: Double
    let seconds: Double

    private var remaining: Int { max(0, Int((seconds * (1 - progress)).rounded(.up))) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surface3, lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.3), value: progress)
            VStack(spacing: 2) {
                Text("\(remaining)")
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.heading)
                Text("hold still")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(width: 156, height: 156)
    }
}
