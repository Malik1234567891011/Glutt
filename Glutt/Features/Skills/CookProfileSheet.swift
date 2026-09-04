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
            .navigationTitle("Your cooking")
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
            } else {
                Text("Unranked")
                    .font(BrandFont.bricolage(30, 700))
                    .foregroundStyle(Theme.Colors.heading)
                // Says what the rating is FOR, which nothing else on the screen
                // does. A cook who does not know reading will not earn it has
                // no reason to attempt a trial.
                Text("A rating comes from mastery trials, the diamonds on the "
                     + "map. Lessons build your level; trials show what you can "
                     + "actually do.")
                    .font(BrandFont.nunito(14, 600))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CookRating.placementLine(reader.trials))
                    .font(BrandFont.nunito(13, 800))
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.top, 2)
            }

            Divider().padding(.top, 10)

            HStack(spacing: 18) {
                stat("Level", "\(reader.levelProgress.level)")
                stat("Skills", "\(reader.learnedCount)")
                stat("Trials", "\(reader.trials.count)")
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

    private var recent: [TrialResult] {
        Array(reader.trials.sorted { $0.finishedAt > $1.finishedAt }.prefix(6))
    }

    @ViewBuilder private var recentResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent trials")
                .font(BrandFont.nunito(12, 800)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(Theme.Colors.muted)

            ForEach(recent) { result in
                HStack(spacing: 10) {
                    Text("\(result.score)")
                        .font(BrandFont.nunito(16, 800))
                        .foregroundStyle(Theme.Colors.heading)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(SkillCatalog.skill(result.skillID)?.title ?? result.skillID)
                            .font(BrandFont.nunito(14.5, 700))
                            .foregroundStyle(Theme.Colors.heading)
                        // Stated rather than deducted. A result that says
                        // "independent" only means something because the
                        // alternative is written down instead of silently
                        // costing points.
                        Text(result.wasIndependent
                             ? "Independent"
                             : "^[\(result.coachCalls) coach call](inflect: true)")
                            .font(BrandFont.nunito(11.5, 600))
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    Spacer(minLength: 8)
                    Text(result.ratingDelta >= 0 ? "+\(result.ratingDelta)" : "\(result.ratingDelta)")
                        .font(BrandFont.nunito(13, 800))
                        .foregroundStyle(result.ratingDelta >= 0
                                         ? Theme.Colors.accent : Theme.Colors.muted)
                        .monospacedDigit()
                }
            }
        }
    }
}
