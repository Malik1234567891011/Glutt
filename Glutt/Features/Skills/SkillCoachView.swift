import SwiftData
import SwiftUI
import UIKit

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
    @State private var copiedLog = false

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.lg) {
                header
                Spacer(minLength: 0)
                centrepiece
                Spacer(minLength: 0)
                transcript
                listeningDock
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
        case .analysing:
            LookingAnimation()
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

    /// The same promise the cook screen makes: you can see when she is hearing
    /// you. Without it a cook talks into a phone that gives no sign it is on,
    /// which is the moment they go back to pressing buttons.
    private var listeningDock: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VoiceBars(state: barState)
            Text(dockCopy)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.card, in: Capsule())
    }

    private var barState: VoiceBars.State {
        guard let session else { return .idle }
        if session.isSpeaking { return .speaking }
        if case .analysing = session.stage { return .thinking }
        if session.isThinking { return .thinking }
        return session.isListening ? .listening : .idle
    }

    private var dockCopy: String {
        guard let session, session.phase == .live else { return "Connecting" }
        if session.isSpeaking { return "Chef is talking" }
        if case .analysing = session.stage { return "Looking at your hand" }
        if session.isThinking { return "Thinking" }
        if session.isListening { return "Listening" }
        return session.wakeWordAvailable ? "Say “Chef” to talk" : "Not listening"
    }

    /// No check button.
    ///
    /// There was one and it was the wrong shape: a cook with a knife in one hand
    /// and glasses on their face should not be hunting for a control, and having
    /// it there made asking out loud look optional. Say "Chef, does this look
    /// right" and she looks.
    @ViewBuilder private var footer: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(promptLine)
                .font(.footnote)
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.sm) {
                Button("Done") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    UIPasteboard.general.string = PollyDebugLog.shared.dump()
                    copiedLog = true
                } label: {
                    Image(systemName: copiedLog ? "checkmark" : "doc.on.clipboard")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityLabel("Copy debug log")
            }
        }
    }

    /// What to say, spelled out, because a screen that only listens has to tell
    /// you that it is listening AND what to say into it.
    private var promptLine: String {
        guard let session, session.phase == .live else { return "" }
        if !session.wakeWordAvailable {
            return "The wake word is not available on this device right now."
        }
        if session.isAwake { return "Go ahead, she is listening." }
        return "Say “Chef” to talk. Try “Chef, does this look right?”"
    }

    private var statusLine: String {
        switch session?.phase {
        case .idle, .connecting, .none: "Getting Chef ready"
        case .failed(let why): why
        case .ended: "Lesson finished"
        case .live:
            switch session?.stage {
            case .analysing: "Looking"
            case .safetyStop: "Put the knife down"
            default: (session?.isAwake ?? false)
                ? "Go ahead"
                : "Say “Chef” whenever you want her"
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

/// Five bars that say which way the conversation is flowing.
///
/// Lifted in spirit from the cook canvas dock, because a cook who has used the
/// app once already knows what these mean, and inventing a second visual
/// language for the same fact would be worse than copying.
struct VoiceBars: View {
    enum State { case idle, listening, speaking, thinking }

    let state: State

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: height(index: i, t: t))
                }
            }
            .frame(width: 28, height: 24)
        }
    }

    private var tint: Color {
        switch state {
        case .idle: Theme.Colors.mutedSoft
        case .listening, .speaking: Theme.Colors.accent
        case .thinking: Theme.Colors.amber
        }
    }

    private func height(index: Int, t: Double) -> CGFloat {
        let base: CGFloat
        switch state {
        case .listening: base = 8 + CGFloat((sin(t * 8 + Double(index)) + 1) * 7)
        case .speaking: base = 6 + CGFloat((sin(t * 6 + Double(index)) + 1) * 6)
        case .thinking: base = 5 + CGFloat((sin(t * 3 + Double(index)) + 1) * 3)
        case .idle: base = 4 + (index == 2 ? 3 : 0)
        }
        return max(4, min(22, base))
    }
}

/// What "Polly is looking at your hand" looks like.
///
/// A spinner says the app is busy. This is meant to say something different and
/// more specific: somebody is examining the thing you are holding. The ring
/// sweeps like a pass over the hand rather than spinning like a wait, and the
/// text names what is being looked at, because the five seconds of holding still
/// have to feel like part of the lesson rather than the price of it.
private struct LookingAnimation: View {
    @State private var sweep = false
    @State private var pulse = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.greenTint)
                    .frame(width: 156, height: 156)
                    .scaleEffect(pulse ? 1.04 : 0.96)

                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(
                        Theme.Colors.accent,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 156, height: 156)
                    .rotationEffect(.degrees(sweep ? 360 : 0))

                Image(systemName: "hand.raised.fingers.spread")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)
                    .opacity(pulse ? 1 : 0.65)
            }
            Text("Looking at your grip")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                sweep = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
