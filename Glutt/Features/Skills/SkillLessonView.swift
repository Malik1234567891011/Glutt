import SwiftData
import SwiftUI

/// One skill, taught.
///
/// Text first, and structured rather than a blob, so the sections read as a
/// chef talking you through it. The layout deliberately leaves the top slot
/// free: when animated demonstrations arrive they sit above `summary` and
/// nothing else has to move.
struct SkillLessonView: View {
    let skill: Skill

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var progressRows: [SkillProgress]
    @Query(sort: \SkillAttempt.startedAt, order: .reverse) private var allAttempts: [SkillAttempt]

    @State private var justLearned = false
    @State private var awarded = 0
    @State private var isPhotographing = false

    private var reader: SkillsProgressReader { SkillsProgressReader(progress: progressRows) }
    private var attempts: [SkillAttempt] { allAttempts.filter { $0.skillID == skill.id } }
    private var isMastered: Bool {
        progressRows.first { $0.skillID == skill.id }?.isMastered ?? false
    }
    private var isLearned: Bool { reader.learnedIDs.contains(skill.id) }
    private var category: SkillCategory? { SkillCatalog.category(of: skill) }
    private var unmet: [Skill] {
        SkillProgression.unmetPrerequisites(for: skill, learnedIDs: reader.learnedIDs)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heading
                    if let lesson = skill.lesson {
                        if let asset = skill.animationAsset { demonstration(asset) }
                        if !unmet.isEmpty { recommendedFirst }
                        section("What you're learning", body: lesson.summary)
                        steps(lesson.steps)
                        // The invitation sits directly under the steps, not at
                        // the bottom. Reading three steps and then being asked
                        // to try them is the whole shape of the lesson; putting
                        // it after "why this matters" turns it into a footnote.
                        if let check = skill.visualCheck {
                            checkCallout(check)
                        } else {
                            readingCallout
                        }
                        attemptHistory
                        watchFors(lesson.watchFors)
                        whyItMatters(lesson.whyItMatters)
                        // Polly sits after the teaching, not before it. The
                        // lesson answers the question they came with; she is
                        // for the one reading it gave them.
                        SkillAskPollyView(skill: skill)
                    } else {
                        comingSoon
                    }
                }
                .padding(20)
                .padding(.bottom, 96)
            }
            .background(Theme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
        }
        .onAppear {
            guard skill.isAuthored else { return }
            SkillProgressStore.markOpened(skill, in: context)
            Analytics.capture(.skillOpened, ["category": skill.categoryID])
        }
    }

    // MARK: Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(skill.title)
                .font(BrandFont.bricolage(27, 700))
                .foregroundStyle(Theme.Colors.heading)
            HStack(spacing: 8) {
                if let category {
                    pill(category.name, tint: category.theme.tint, background: category.theme.wash)
                }
                pill(skill.difficulty.label, tint: Theme.Colors.textSecondary, background: Theme.Colors.surface2)
                if skill.isAuthored {
                    pill("\(skill.estimatedMinutes) min", tint: Theme.Colors.textSecondary, background: Theme.Colors.surface2)
                }
                if skill.isChallenge {
                    pill("Mastery", tint: Theme.Colors.amber, background: Theme.Colors.amberChip)
                }
            }
            if !skill.shortDescription.isEmpty, skill.isAuthored {
                Text(skill.shortDescription)
                    .font(BrandFont.nunito(14.5, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pill(_ text: String, tint: Color, background: Color) -> some View {
        Text(text)
            .font(BrandFont.nunito(12, 800))
            .foregroundStyle(tint)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(background))
    }

    // MARK: The demonstration

    /// The clip that shows the thing being done, in the slot that was left for
    /// it when this screen was first built.
    ///
    /// Three decisions worth keeping:
    ///
    /// **It fits rather than fills.** The knife grip clip has its step numbers
    /// in the top corners and its labels along the bottom, so cropping to a
    /// tidy rectangle would remove the words. Letterboxing on a phone-width
    /// card costs a little height and keeps the lesson.
    ///
    /// **It loops, muted, with no controls.** A grip is something you glance
    /// back at repeatedly while your own hands are busy, so a replay button is
    /// a button you cannot press with a knife in your hand. The asset has no
    /// audio track at all, which also means it can never talk over Chef.
    ///
    /// **It stops while she is coaching.** `fullScreenCover` leaves this view
    /// in the window, so without the explicit pause a demonstration would keep
    /// looping underneath a live session that has the camera and microphone
    /// open.
    @ViewBuilder private func demonstration(_ asset: String) -> some View {
        LoopingVideoView(resource: asset, fills: false)
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.Colors.textPrimary.opacity(0.06), lineWidth: 1)
            )
            .accessibilityLabel("Demonstration of \(skill.title), playing on a loop")
    }

    // MARK: Nothing to show her

    /// What sits where the "show me" invitation goes, on the skills there is
    /// nothing to show.
    ///
    /// About a third of the map is like this and the honest thing is to say so.
    /// Tasting as you go is the clearest case: you could photograph somebody
    /// holding a spoon and it would prove nothing, because the skill is tasting
    /// BEFORE you reach for the salt, and the palate itself is invisible by
    /// definition. Resting meat is time. Preheating a pan is a temperature. A
    /// rubric over any of those would be Chef inventing an opinion and
    /// presenting it as an observation.
    ///
    /// Saying nothing here would be worse than saying this, because a cook who
    /// has done three lessons with a "try it and show her" button would read
    /// its absence as something missing rather than as a decision.
    private var readingCallout: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("This one is just to know", systemImage: "book.closed.fill")
                .font(.headline)
                .foregroundStyle(Theme.Colors.heading)

            Text("There is nothing to show Chef here. A photo of it would not tell her "
                 + "anything she could act on, so read it, use it next time you cook, and ask "
                 + "her anything below that did not land.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            Theme.Colors.surface2,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    // MARK: The check

    /// The thing that makes this a lesson rather than an article.
    ///
    /// Deliberately loud, and deliberately honest about what it needs. It reads
    /// as a different invitation in each mode because it IS a different lesson:
    /// with glasses on Chef watches your hands while you work, and without them
    /// she teaches, you check yourself, and you send her a couple of photos.
    ///
    /// The way to the other mode sits underneath rather than in a settings
    /// screen, because the moment somebody wants it is this one.
    @ViewBuilder private func checkCallout(_ check: SkillVisualCheck) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(
                isMastered ? "Chef has seen you do this" : calloutTitle(check),
                systemImage: isMastered ? "checkmark.seal.fill" : mode.glyph)
                .font(.headline)
                .foregroundStyle(isMastered ? Theme.Colors.accent : Theme.Colors.heading)

            Text(calloutBody(check))
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)

            Button(primaryActionTitle) { isPhotographing = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            Theme.Colors.greenTint,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .sheet(isPresented: $isPhotographing) {
            SkillPhotoCheckView(skill: skill, check: check)
        }
    }

    /// One mode on this branch. Live coaching was the other, and it existed to
    /// watch through a pair of Meta glasses, so it went out with them. Photos
    /// are not the consolation prize: for the knife grip they are better,
    /// because nobody can see both faces of a blade from their own eyes and a
    /// phone takes one picture of each side.
    private let mode: SkillLearningMode = .showing

    private var primaryActionTitle: String {
        isMastered ? "Show her again" : "Try it and show her"
    }

    private func calloutTitle(_ check: SkillVisualCheck) -> String {
        "Show Chef when you have it"
    }

    /// Both halves come from the check. This block used to name a knife and a
    /// grip in hardcoded copy, which was true of the one skill that existed
    /// when it was written and wrong for the seventy that followed it.
    private func calloutBody(_ check: SkillVisualCheck) -> String {
        check.setupLine(for: mode)
            + " Try it, then send her "
            + SkillCount.photos(check.photosNeeded)
            + " and she tells you the one thing worth changing."
    }

    /// What happened the last few times, in the cook's own history.
    ///
    /// Every attempt, not just the good ones. "Could not see your thumb" sitting
    /// in the list is the difference between a system that admits what it does
    /// not know and one that quietly drops the evidence.
    @ViewBuilder private var attemptHistory: some View {
        if !attempts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Your attempts")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.heading)
                ForEach(attempts.prefix(5)) { attempt in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Text(attempt.outcome.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint(for: attempt.outcome))
                            .frame(width: 92, alignment: .leading)
                        Text(attempt.note)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if practisedSeconds > 0 {
                    Text("\(attempts.count) attempts, about \(practisedMinutes) practising.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
    }

    private var practisedSeconds: Int { Int(attempts.reduce(0) { $0 + $1.seconds }) }

    private var practisedMinutes: String {
        practisedSeconds < 60 ? "\(practisedSeconds) seconds" : "\(practisedSeconds / 60) minutes"
    }

    private func tint(for outcome: SkillAttemptOutcome) -> Color {
        switch outcome {
        case .passed: Theme.Colors.accent
        case .corrected: Theme.Colors.amber
        case .inconclusive: Theme.Colors.muted
        case .wrongEquipment: Theme.Colors.muted
        case .stoppedForSafety: Theme.Colors.tomato
        }
    }

    // MARK: Sections

    private func section(_ title: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(title)
            Text(text)
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(BrandFont.nunito(12, 800)).tracking(1.4).textCase(.uppercase)
            .foregroundStyle(Theme.Colors.accent)
    }

    private func steps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("How to do it")
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(BrandFont.nunito(13, 800))
                        .foregroundStyle(Theme.Colors.creamText)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.Colors.accent))
                    Text(step)
                        .font(BrandFont.nunito(15, 600))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func watchFors(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Things to watch for")
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Theme.Colors.amber).frame(width: 6, height: 6).padding(.top, 7)
                    Text(item)
                        .font(BrandFont.nunito(14.5, 600))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func whyItMatters(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Why this matters")
            Text(text)
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.greenTint)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }

    /// Advice, never a gate. The cook can learn this right now regardless, which
    /// is the whole point of section 7 of the brief.
    private var recommendedFirst: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Recommended first")
            ForEach(unmet, id: \.id) { prerequisite in
                HStack(spacing: 9) {
                    Image(systemName: "circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Colors.muted)
                    Text(prerequisite.title)
                        .font(BrandFont.nunito(14, 700))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Text("You can learn this now either way.")
                .font(BrandFont.nunito(12.5, 600))
                .foregroundStyle(Theme.Colors.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }

    private var comingSoon: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Not written yet")
            Text("This one is on the map so you can see where Glutt is going. The lesson is coming.")
                .font(BrandFont.nunito(15, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if skill.isAuthored {
            VStack(spacing: 10) {
                if justLearned {
                    learnedBanner
                } else if isLearned {
                    Text("You've learned this one.")
                        .font(BrandFont.nunito(14, 700))
                        .foregroundStyle(Theme.Colors.accent)
                } else {
                    Button {
                        Haptics.notify(.success)
                        awarded = skill.xp
                        if SkillProgressStore.markLearned(skill, in: context) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                justLearned = true
                            }
                        }
                    } label: {
                        Text("I've got it")
                            .font(BrandFont.nunito(16.5, 800))
                            .foregroundStyle(Theme.Colors.creamText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Theme.Colors.accent))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Theme.Colors.background.opacity(0.98))
        }
    }

    /// True when this skill was the last unlearned one in its region.
    ///
    /// Finishing a region is the only moment on the map that is worth more than
    /// a line of text: it is the whole point of drawing regions instead of a
    /// list. Everything else stays deliberately quiet.
    private var justFinishedRegion: Bool {
        guard justLearned, let category else { return false }
        return SkillProgression.learnedCount(in: category, learnedIDs: reader.learnedIDs)
            == category.learnableCount
    }

    /// Tasteful, not an arcade. A line, the XP, and the obvious next thing.
    private var learnedBanner: some View {
        VStack(spacing: 10) {
            if justFinishedRegion, let category {
                regionComplete(category)
            }
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text("Nice, you learned \(skill.title).")
                    .font(BrandFont.nunito(14.5, 800))
                    .foregroundStyle(Theme.Colors.heading)
                Text("+\(awarded) XP")
                    .font(BrandFont.nunito(13, 800))
                    .foregroundStyle(Theme.Colors.amber)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let next = SkillProgression.next(after: skill, learnedIDs: reader.learnedIDs) {
                Button {
                    Haptics.impact(.light)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text("Next: \(next.title)")
                            .font(BrandFont.nunito(15.5, 800))
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Theme.Colors.creamText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().fill(Theme.Colors.accent))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The milestone. Polly celebrating, the region's name, and nothing else:
    /// no confetti, no modal, no badge shelf to go and look at later.
    private func regionComplete(_ category: SkillCategory) -> some View {
        HStack(spacing: 12) {
            Image("bearCelebrating")
                .resizable()
                .scaledToFit()
                .frame(height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(category.name) complete")
                    .font(BrandFont.nunito(15.5, 800))
                    .foregroundStyle(Theme.Colors.heading)
                Text("All \(category.learnableCount) of them. That is a whole area of cooking you have under you now.")
                    .font(BrandFont.nunito(12.5, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(category.theme.wash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}
