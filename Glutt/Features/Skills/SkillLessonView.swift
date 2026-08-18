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

    @State private var justLearned = false
    @State private var awarded = 0

    private var reader: SkillsProgressReader { SkillsProgressReader(progress: progressRows) }
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
                        // Reserved for the animated demonstration. Intentionally
                        // nothing today: `skill.animationAsset` is always nil,
                        // and the slot exists so adding one is content work.
                        if !unmet.isEmpty { recommendedFirst }
                        section("What you're learning", body: lesson.summary)
                        steps(lesson.steps)
                        watchFors(lesson.watchFors)
                        whyItMatters(lesson.whyItMatters)
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

    /// Tasteful, not an arcade. A line, the XP, and the obvious next thing.
    private var learnedBanner: some View {
        VStack(spacing: 10) {
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
}
