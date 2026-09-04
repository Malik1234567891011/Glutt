import SwiftUI

/// The cook's standing, behind a tap on the header line.
///
/// This is where the dashboard lives, and the point is that it lives HERE
/// rather than above the map. Rank, rating, every region's standard, strongest
/// and weakest, recent results: all of it useful, none of it worth pushing the
/// world below the fold for. The map answers "where am I and what next"; this
/// answers "how good am I", and only when somebody asks.
///
/// Deliberately not a grid of stat cards. Rows, dividers and typography, in the
/// same cream the rest of the tab is built from.
struct CookProfileSheet: View {
    let reader: SkillsProgressReader
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    standing
                    regions
                    if !recent.isEmpty { recentResults }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Cook Rating")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Standing

    @ViewBuilder private var standing: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rank = reader.cookRank, let rating = reader.cookRating {
                Text(rank.title)
                    .font(BrandFont.bricolage(30, 700))
                    .foregroundStyle(Theme.Colors.heading)
                Text(rating.formatted())
                    .font(BrandFont.nunito(19, 800))
                    .foregroundStyle(Theme.Colors.accent)
                    .monospacedDigit()
                if let next = CookRank.toNext(from: rating) {
                    Text("\(next.points) to \(next.rank.title)")
                        .font(BrandFont.nunito(13, 700))
                        .foregroundStyle(Theme.Colors.muted)
                }
                // Said plainly while the rating rests on a handful of narrow
                // observations. Three checks is not a picture of somebody's
                // cooking, and presenting it as settled would be a claim the
                // evidence does not support.
                if reader.isRatingProvisional {
                    Text("Provisional · still learning what you can do")
                        .font(BrandFont.nunito(12.5, 600))
                        .foregroundStyle(Theme.Colors.muted)
                }
            } else {
                Text("Unranked")
                    .font(BrandFont.bricolage(30, 700))
                    .foregroundStyle(Theme.Colors.heading)
                // Names both halves. A cook who thinks reading earns this has
                // no reason to be watched, and a cook who thinks only trials
                // count has no reason to touch an ordinary node.
                Text("Your Cook Rating is based on cooking Glutt can actually "
                     + "verify. Lessons build your Level; skill checks and "
                     + "mastery trials show what you can do.")
                    .font(BrandFont.nunito(14, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Typographic, not a progress card. The count is the whole
                // message and a bar around it would add nothing but furniture.
                Text("\(progress.done) / \(progress.needed) verified checks")
                    .font(BrandFont.nunito(13, 800))
                    .foregroundStyle(Theme.Colors.accent)
                    .monospacedDigit()
                    .padding(.top, 2)
            }

            Divider().padding(.top, 10)

            HStack(spacing: 18) {
                stat("Level", "\(reader.levelProgress.level)")
                stat("Skills", "\(reader.learnedCount)")
                stat("Verified", "\(reader.evidence.count)")
            }
            .padding(.top, 4)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(BrandFont.nunito(19, 800))
                .foregroundStyle(Theme.Colors.heading)
                .monospacedDigit()
            Text(label)
                .font(BrandFont.nunito(11.5, 700))
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    // MARK: Regions

    @ViewBuilder private var regions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By region")
                .font(BrandFont.nunito(12, 800)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(Theme.Colors.muted)

            ForEach(SkillCatalog.categories, id: \.id) { category in
                HStack(spacing: 10) {
                    Circle()
                        .fill(category.theme.tint)
                        .frame(width: 8, height: 8)
                    Text(category.name)
                        .font(BrandFont.nunito(15, 700))
                        .foregroundStyle(Theme.Colors.heading)
                    Spacer(minLength: 8)
                    regionValue(category)
                }
            }
        }
    }

    /// A number, "Unranked", or the honest reason there will never be one.
    @ViewBuilder private func regionValue(_ category: SkillCategory) -> some View {
        if !RegionRating.isRateable(category) {
            // Not a gap to be filled later. You cannot photograph tasting as
            // you go, so saying so is more truthful than a dash that reads as
            // missing data.
            Text("Not scored")
                .font(BrandFont.nunito(12.5, 600))
                .foregroundStyle(Theme.Colors.muted)
        } else if let rating = reader.rating(for: category) {
            Text("\(rating)")
                .font(BrandFont.nunito(16, 800))
                .foregroundStyle(category.theme.tint)
                .monospacedDigit()
        } else {
            Text("Unranked")
                .font(BrandFont.nunito(12.5, 600))
                .foregroundStyle(Theme.Colors.muted)
        }
    }

    // MARK: Recent

    /// Split out because the type checker gave up on it inline.
    private func subtitle(for evidence: RatingEvidence) -> String {
        let kind = evidence.kind == .masteryTrial ? "Mastery trial" : "Skill check"
        // The count where there is one, the coarse outcome otherwise.
        return "\(kind) · \(evidence.spokenScore ?? evidence.spokenCredit)"
    }

    private var progress: (done: Int, needed: Int) {
        CookRating.placementProgress(reader.evidence)
    }

    private var recent: [RatingEvidence] {
        Array(reader.evidence.sorted { $0.occurredAt > $1.occurredAt }.prefix(6))
    }

    @ViewBuilder private var recentResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently verified")
                .font(BrandFont.nunito(12, 800)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(Theme.Colors.muted)

            ForEach(recent) { result in
                evidenceRow(result)
            }
        }
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

        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(BrandFont.nunito(14.5, 700))
                    .foregroundStyle(Theme.Colors.heading)
                Text(subtitle(for: result))
                    .font(BrandFont.nunito(11.5, 600))
                    .foregroundStyle(Theme.Colors.muted)
            }
            Spacer(minLength: 8)
            Text(result.occurredAt.formatted(.relative(presentation: .numeric)))
                .font(BrandFont.nunito(11.5, 600))
                .foregroundStyle(Theme.Colors.muted)
        }
    }
}
