import SwiftData
import SwiftUI
import UIKit

/// The screen a cook looks at while Chef is teaching them to hold a knife.
///
/// Built around one question: **what am I supposed to be doing right now.** A
/// cook glancing down has a knife in one hand, glasses on their face and about a
/// second of attention to spare, so the current instruction is the whole screen
/// and everything else is a strip along the bottom.
///
/// It used to be the other way up. The middle was a large animation of her
/// state, her words sat under it in a card, and the step she was actually
/// teaching appeared nowhere at all: you could look at the phone and learn that
/// something was listening, which is not what anybody looks down for.
struct SkillCoachView: View {
    let skill: Skill
    let check: SkillVisualCheck

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Built here rather than taken from the environment, because nothing puts
    /// one there: `PollySessionController` owns its own and a lesson is not a
    /// cook. Its own coordinator also means a lesson can never inherit a phone
    /// camera someone turned on during a recipe.
    /// Cycles the suggestion under the buttons.
    ///
    /// One fixed line taught one thing. A cook who has read "Chef, does this
    /// look right?" fifty times has still never been told they can just ask for
    /// the video, because nothing on screen ever said so.
    @State private var hintIndex = 0
    private let hintTimer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()

    /// Only offers the video on skills that have one, because a suggestion that
    /// does not work is worse than no suggestion.
    private var hints: [String] {
        var lines = ["Try “Chef, does this look right?”"]
        if skill.animationAsset != nil {
            lines.append("Try “Chef, pull up the video”")
        }
        return lines
    }

    private var hint: String { hints[hintIndex % hints.count] }

    @State private var visuals = PollyVisualSourceCoordinator(
        phone: PhoneCameraVisualSource(camera: PollyCameraController()))
    @State private var session: SkillCoachSession?
    @State private var copiedLog = false

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.md) {
                header
                // Centred rather than pinned to the top: a glance goes to the
                // middle of the phone, and the instruction should be waiting
                // there rather than above where the thumb is.
                Spacer(minLength: 0)
                stepCard
                Spacer(minLength: 0)
                saidLine
                statusStrip
#if DEBUG
                // In the stack rather than floating over it. As an overlay this
                // sat on top of the footer and swallowed taps meant for the copy
                // log button, which is the one control a test session needs.
                SkillLookMirrorPanel()
#endif
                footer
            }
            .padding(Theme.Spacing.lg)

            if session?.showingDemonstration == true, let asset = skill.animationAsset {
                demonstration(asset)
            }
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

    // MARK: Where you are

    private var header: some View {
        HStack {
            Text(skill.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            if let session, !session.parts.isEmpty, !isFinished {
                let done = session.parts.filter { session.state(of: $0) == .good }.count
                Text("\(done) of \(session.parts.count)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.muted)
                    .monospacedDigit()
            }
        }
    }

    /// The instruction, at the size you can read at arm's length with your hands
    /// full. Everything else on this screen exists to not compete with it.
    @ViewBuilder private var stepCard: some View {
        if case .failed(let why) = session?.phase {
            // Was invisible: a dead session sat behind "Getting Chef ready"
            // forever, so the cook stood in their kitchen waiting for a lesson
            // that had already given up.
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.Colors.amber)
                Text("Chef could not connect")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.heading)
                Text(why)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await session?.retry(context: context) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.Colors.amberChip,
                in: RoundedRectangle(cornerRadius: Theme.Radius.cardLarge))
        } else {
            liveStepCard
        }
    }

    @ViewBuilder private var liveStepCard: some View {
        switch session?.stage {
        case .learned:
            outcomeCard(
                glyph: "checkmark.seal.fill",
                tint: Theme.Colors.accent,
                title: "That is your chef's knife grip",
                body: skill.lesson?.whyItMatters ?? "")
        case .safetyStop(let reason):
            outcomeCard(
                glyph: "hand.raised.fill",
                tint: Theme.Colors.tomato,
                title: "Put the knife down",
                body: reason)
        default:
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("The pinch grip")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.heading)
                ForEach(session?.parts ?? []) { part in
                    partRow(part)
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.Colors.card,
                in: RoundedRectangle(cornerRadius: Theme.Radius.cardLarge))
            // The border is the only thing that moves while she looks, so the
            // instruction stays readable through it.
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.cardLarge)
                    .strokeBorder(
                        isLooking ? Theme.Colors.accent : Theme.Colors.border,
                        lineWidth: isLooking ? 2 : 1)
                    .animation(.easeInOut(duration: 0.4), value: isLooking))
        }
    }

    /// One part of the grip, and how it is doing.
    ///
    /// Blank, green or amber. Never red: nothing here is a failure, it is a hand
    /// that has not been looked at yet or one thing to move.
    @ViewBuilder private func partRow(_ part: SkillCheckPart) -> some View {
        let state = session?.state(of: part) ?? .unknown
        let focused = session?.focusedPart == part.region
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: mark(for: state))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint(for: state))
                .frame(width: 22)
            Text(part.label)
                .font(.system(
                    size: 19,
                    weight: focused || state == .needsFixing ? .semibold : .regular,
                    design: .rounded))
                .foregroundStyle(
                    state == .unknown && !focused
                        ? Theme.Colors.textSecondary
                        : Theme.Colors.heading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .animation(.easeInOut(duration: 0.3), value: state)
    }

    private func mark(for state: SkillPartState) -> String {
        switch state {
        case .unknown: "circle"
        case .good: "checkmark.circle.fill"
        case .needsFixing: "arrow.turn.up.right"
        }
    }

    private func tint(for state: SkillPartState) -> Color {
        switch state {
        case .unknown: Theme.Colors.dotInactive
        case .good: Theme.Colors.accent
        case .needsFixing: Theme.Colors.amber
        }
    }

    private func outcomeCard(
        glyph: String, tint: Color, title: String, body: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: glyph)
                .font(.system(size: 34))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.heading)
                .fixedSize(horizontal: false, vertical: true)
            if !body.isEmpty {
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            tint.opacity(0.10),
            in: RoundedRectangle(cornerRadius: Theme.Radius.cardLarge))
    }

    // MARK: What she just said

    /// Secondary on purpose. Useful when you missed a sentence, never the reason
    /// to look down.
    @ViewBuilder private var saidLine: some View {
        if let caption = session?.caption, !caption.isEmpty, !isFinished {
            Text(caption)
                .font(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: What she is doing

    /// One row, always in the same place, so its meaning is learned once.
    private var statusStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isLooking {
                LookingMark()
            } else {
                VoiceBars(state: barState)
            }
            Text(statusCopy)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isLooking ? Theme.Colors.accent : Theme.Colors.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isLooking ? Theme.Colors.greenTint : Theme.Colors.card,
            in: Capsule())
        .animation(.easeInOut(duration: 0.25), value: isLooking)
    }

    private var isLooking: Bool {
        if case .analysing = session?.stage { return true }
        return false
    }

    private var isFinished: Bool {
        switch session?.stage {
        case .learned, .safetyStop: true
        default: false
        }
    }

    private var barState: VoiceBars.State {
        guard let session else { return .idle }
        if session.isSpeaking { return .speaking }
        if session.isThinking { return .thinking }
        return session.isListening ? .listening : .idle
    }

    private var statusCopy: String {
        guard let session else { return "Getting Chef ready" }
        if case .failed = session.phase { return "Not connected" }
        if case .ended = session.phase { return "Lesson finished" }
        guard session.phase == .live else { return "Getting Chef ready" }
        if isLooking { return "Looking at your grip" }
        if session.isSpeaking { return "Chef is talking" }
        if session.isThinking { return "Thinking" }
        if session.isListening { return "Listening" }
        if case .visionUnavailable = session.stage { return "I cannot see well enough" }
        return session.wakeWordAvailable ? "Say “Chef” to talk" : "Not listening"
    }

    // MARK: The demonstration

    /// The clip, over the lesson, without leaving it.
    ///
    /// She usually opens this herself through `show_the_video` when somebody
    /// asks to see it again, which is the point: a cook wearing glasses with a
    /// knife in one hand should not have to back out of a lesson and find the
    /// video. The button exists for the times she mishears.
    ///
    /// Dimmed rather than opaque so the parts list stays faintly visible behind
    /// it, and the clip is not the lesson, it is a reference inside it.
    @ViewBuilder private func demonstration(_ asset: String) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { session?.hideDemonstration() }

            VStack(spacing: Theme.Spacing.md) {
                LoopingVideoView(resource: asset, fills: false)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button("Close") { session?.hideDemonstration() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(Theme.Spacing.lg)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Out

    @ViewBuilder private var footer: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let session, session.phase == .live, !session.isAwake, session.wakeWordAvailable {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.muted)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: hint)
                    .onReceive(hintTimer) { _ in
                        withAnimation { hintIndex += 1 }
                    }
            }
            HStack(spacing: Theme.Spacing.sm) {
                Button(isFinished ? "Done" : "End lesson") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                if skill.animationAsset != nil, !isFinished {
                    Button {
                        session?.showDemonstration()
                    } label: {
                        Image(systemName: "play.rectangle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("Show the demonstration video")
                }
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
            .frame(width: 28, height: 22)
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
        case .listening: base = 8 + CGFloat((sin(t * 8 + Double(index)) + 1) * 6)
        case .speaking: base = 6 + CGFloat((sin(t * 6 + Double(index)) + 1) * 5)
        case .thinking: base = 5 + CGFloat((sin(t * 3 + Double(index)) + 1) * 3)
        case .idle: base = 4 + (index == 2 ? 3 : 0)
        }
        return max(4, min(20, base))
    }
}

/// A small sweep, for the seconds she is actually reading the frames.
///
/// Inline rather than the centrepiece it used to be. Looking is about four
/// seconds now and mostly happens underneath her own voice, so it does not
/// deserve to replace the instruction the cook is trying to follow.
private struct LookingMark: View {
    @State private var sweep = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.accent.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(Theme.Colors.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(sweep ? 360 : 0))
        }
        .frame(width: 20, height: 20)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }
}
