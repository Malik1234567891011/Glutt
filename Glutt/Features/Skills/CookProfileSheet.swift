import SwiftUI

/// The cook's standing, behind a tap on the header line.
///
/// This is where the dashboard lives, and the point is that it lives HERE
/// rather than above the map. Rank, rating, every region's standard, strongest
/// and weakest, recent results: all of it useful, none of it worth pushing the
/// world below the fold for. The map answers "where am I and what next"; this
/// answers "how good am I", and only when somebody asks.
///
/// Deliberately not a grid of stat cards. Rows, hairlines and typography, in
/// the same cream the rest of the tab is built from.
///
/// # The rating is the hero, everything else explains it
///
/// The rank used to sit above the number in the largest type on the screen,
/// which read as a title with a caption under it. It is the other way round:
/// "Prep Cook I" is a label FOR 1,014, so the number leads and the rank sits
/// under it in the same breath. The two are one group, and the spacing says so.
struct CookProfileSheet: View {
    let reader: SkillsProgressReader
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingLadder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    standing

                    hairline
                        .padding(.top, Theme.Spacing.lg)

                    stats
                        .padding(.top, 18)

                    section("Region ratings", note: regionNote)
                        .padding(.top, 30)
                    regions
                        .padding(.top, 2)

                    if !recent.isEmpty {
                        section("Recently verified")
                            .padding(.top, 30)
                        recentResults
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Colors.background)
            .sheet(isPresented: $isShowingLadder) {
                CookRankLadderSheet(rating: reader.cookRating)
            }
            .navigationTitle("Cook Rating")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Native toolbar button rather than a drawn pill.
                //
                // This screen saves nothing, so "Done" was claiming an action
                // that does not exist. A close control also picks up whatever
                // the running iOS gives toolbar items, including the system
                // treatment on 26, which a hand drawn capsule never would.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: Standing

    @ViewBuilder private var standing: some View {
        if let rank = reader.cookRank, let rating = reader.cookRating {
            VStack(alignment: .leading, spacing: 0) {
                // The number and its label, one group. Negative-ish leading
                // between them on purpose: a gap here would read as two facts
                // rather than one.
                Text(rating.formatted())
                    .font(BrandFont.bricolage(50, 700))
                    .foregroundStyle(Theme.Colors.accent)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                // The rank is the way into the ladder, because it is the
                // word somebody has just read and wants the rest of.
                Button {
                    Haptics.impact(.light)
                    isShowingLadder = true
                } label: {
                    HStack(spacing: 7) {
                        Text(rank.title)
                            .font(BrandFont.bricolage(26, 700))
                            .foregroundStyle(Theme.Colors.heading)
                        Image(systemName: "info.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
                .accessibilityLabel("\(rank.title). See all ranks")

                if let next = CookRank.toNext(from: rating) {
                    Text("\(next.points) to \(next.rank.title)")
                        .font(BrandFont.nunito(15, 600))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.top, 12)

                    if let progress = rankProgress {
                        rankLine(progress)
                            .padding(.top, 8)
                    }
                }

                Text(standingNote)
                    .font(BrandFont.nunito(14, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
        } else {
            unranked
        }
    }

    @ViewBuilder private var unranked: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Unranked")
                .font(BrandFont.bricolage(34, 700))
                .foregroundStyle(Theme.Colors.heading)

            // Names both halves. A cook who thinks reading earns this has no
            // reason to be watched, and a cook who thinks only trials count has
            // no reason to touch an ordinary node.
            Text("Your Cook Rating is based on cooking Glutt can actually "
                 + "verify. Lessons build your Level; skill checks and "
                 + "mastery trials show what you can do.")
                .font(BrandFont.nunito(14.5, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            // Typographic, not a progress card. The count is the whole message
            // and a bar around it would add nothing but furniture.
            Text("\(progress.done) / \(progress.needed) verified checks")
                .font(BrandFont.nunito(14, 800))
                .foregroundStyle(Theme.Colors.accent)
                .monospacedDigit()
                .padding(.top, 12)

            // Reachable while unranked too. "What am I working toward" is a
            // better question here than it is once you are on the ladder.
            Button {
                Haptics.impact(.light)
                isShowingLadder = true
            } label: {
                HStack(spacing: 5) {
                    Text("See the ranks")
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                }
                .font(BrandFont.nunito(14, 700))
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }

    /// How far into the current rank this cook is.
    ///
    /// Read straight off `CookRank`'s existing floor and ceiling, so the line
    /// is a view of the rating rather than a second opinion about it. Nil at
    /// Head Chef, which has no ceiling, and the "to next rank" line is absent
    /// there too, so the pair appear and disappear together.
    private var rankProgress: Double? {
        guard let rating = reader.cookRating else { return nil }
        let rank = CookRank.rank(for: rating)
        guard let ceiling = rank.ceiling, ceiling > rank.floor else { return nil }
        let travelled = Double(rating - rank.floor) / Double(ceiling - rank.floor)
        return min(1, max(0, travelled))
    }

    private func rankLine(_ progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.border)
                Capsule()
                    .fill(Theme.Colors.accent)
                    .frame(width: max(3, geometry.size.width * progress))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    /// What the rating rests on, said plainly.
    ///
    /// Provisional is called out while it rests on a handful of narrow
    /// observations. Three checks is not a picture of somebody's cooking, and
    /// presenting it as settled would be a claim the evidence does not support.
    private var standingNote: String {
        let count = reader.evidence.count
        let checks = "\(count) verified \(count == 1 ? "check" : "checks")"
        return reader.isRatingProvisional
            ? "Provisional rating · Based on \(checks)"
            : "Based on \(checks)"
    }

    // MARK: Stats

    private var hairline: some View {
        Rectangle()
            .fill(Theme.Colors.border)
            .frame(height: 1)
    }

    /// Three equal columns, so the numbers line up down the screen rather than
    /// bunching at the left in the order their labels happen to be long.
    private var stats: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            stat("Level", "\(reader.levelProgress.level)")
            stat("Skills", "\(reader.learnedCount)")
            stat("Verified", "\(reader.evidence.count)")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(BrandFont.bricolage(23, 700))
                .foregroundStyle(Theme.Colors.heading)
                .monospacedDigit()
            Text(label)
                .font(BrandFont.nunito(13, 700))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Sections

    /// The uppercase tracked label the rest of the Skills tab uses.
    @ViewBuilder private func section(_ title: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(BrandFont.nunito(12, 800)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let note {
                Text(note)
                    .font(BrandFont.nunito(13.5, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One quiet line doing the work seven repetitions of "Unranked" used to do
    /// badly: saying why most rows are empty.
    private var regionNote: String? {
        reader.evidence.isEmpty || SkillCatalog.categories.contains { reader.rating(for: $0) == nil }
            ? "Ratings appear as Glutt verifies your technique."
            : nil
    }

    // MARK: Regions

    private var regions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SkillCatalog.categories, id: \.id) { category in
                HStack(spacing: 11) {
                    Circle()
                        .fill(category.theme.tint)
                        .frame(width: 9, height: 9)
                    Text(category.name)
                        .font(BrandFont.nunito(17, 700))
                        .foregroundStyle(Theme.Colors.heading)
                    Spacer(minLength: Theme.Spacing.sm)
                    regionValue(category)
                }
                .frame(minHeight: 46)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(category.name), \(regionReading(category))")
            }
        }
    }

    /// A number, a dash, or the honest reason there will never be one.
    @ViewBuilder private func regionValue(_ category: SkillCategory) -> some View {
        if !RegionRating.isRateable(category) {
            // Not a gap to be filled later. You cannot photograph tasting as
            // you go, so saying so is more truthful than a dash, which here
            // means "not yet".
            Text("Not scored")
                .font(BrandFont.nunito(14.5, 600))
                .foregroundStyle(Theme.Colors.muted)
        } else if let rating = reader.rating(for: category) {
            Text("\(rating)")
                .font(BrandFont.nunito(17, 800))
                .foregroundStyle(category.theme.tint)
                .monospacedDigit()
        } else {
            // One glyph instead of the word, seven times.
            //
            // "Unranked" down every row was the loudest thing in the section
            // and it said nothing: it is the default state, and repeating a
            // default is how a list stops being scannable. The screen reader
            // still hears the word, through the row's accessibility label.
            Text("—")
                .font(BrandFont.nunito(17, 600))
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    /// What a screen reader hears in place of the dash.
    private func regionReading(_ category: SkillCategory) -> String {
        if !RegionRating.isRateable(category) { return "not scored" }
        if let rating = reader.rating(for: category) { return "\(rating)" }
        return "unranked"
    }

    // MARK: Recent

    private var progress: (done: Int, needed: Int) {
        CookRating.placementProgress(reader.evidence)
    }

    private var recent: [RatingEvidence] {
        Array(reader.evidence.sorted { $0.occurredAt > $1.occurredAt }.prefix(6))
    }

    private var recentResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(recent) { result in
                evidenceRow(result)
            }
        }
    }

    /// The line under a result: what kind of evidence it was, and the count.
    ///
    /// `2/2` rather than `2 of 2`, built here rather than by reformatting
    /// `RatingEvidence.spokenScore`. That property is named for what Chef says
    /// out loud, where "two of two" is the right reading and a slash is not.
    private func subtitle(for evidence: RatingEvidence) -> String {
        let kind = evidence.kind == .masteryTrial ? "Mastery trial" : "Skill check"
        guard evidence.criteriaObservable > 0 else {
            return "\(kind) · \(evidence.spokenCredit)"
        }
        return "\(kind) · \(evidence.criteriaMet)/\(evidence.criteriaObservable)"
    }

    /// One line of history. Its own function because the type checker gave up
    /// on it inline.
    private func evidenceRow(_ result: RatingEvidence) -> some View {
        // What kind of evidence, not a number. There is no score to print: the
        // pipeline answers narrow authored questions and the app decides what
        // they mean, so a mark out of a hundred here would invent precision
        // nobody measured.
        let isTrial = result.kind == .masteryTrial
        let symbol = isTrial ? "diamond.fill" : "checkmark.circle.fill"
        let tint: Color = result.credit == .clean ? Theme.Colors.accent : Theme.Colors.muted
        let title = SkillCatalog.skill(result.skillID)?.title ?? result.skillID

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, alignment: .leading)
                // Pulls the glyph onto the title's optical baseline, which a
                // top aligned symbol sits above.
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BrandFont.nunito(17, 700))
                    .foregroundStyle(Theme.Colors.heading)
                Text(subtitle(for: result))
                    .font(BrandFont.nunito(13.5, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(result.occurredAt.formatted(.relative(presentation: .numeric)))
                .font(BrandFont.nunito(13, 600))
                .foregroundStyle(Theme.Colors.muted)
                .padding(.top, 2)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}
