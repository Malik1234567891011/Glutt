import SwiftData
import SwiftUI

/// The Skills tab: one long scrolling cooking map.
///
/// Deliberately not a dashboard and not a grid of categories. Everything above
/// the map is kept to a single line of progress, because the map is the
/// feature and a header full of statistics would push it below the fold.
struct SkillsView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Query private var progressRows: [SkillProgress]
    @Query private var evidenceRows: [RatingEvidence]
    @State private var isShowingProfile = false

    private var reader: SkillsProgressReader {
        SkillsProgressReader(progress: progressRows, evidence: evidenceRows)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header
                    if !reader.hasStarted {
                        startHere
                    }
                    SkillMapView(reader: reader) { open($0) }
                        .padding(.top, 6)
                }
                .padding(.bottom, GluttTabBar.reservedHeight + 24)
            }
            .background(Theme.Colors.background)
            .navigationBarHidden(true)
            .sheet(isPresented: $isShowingProfile) {
                CookProfileSheet(reader: reader)
            }
        }
    }

    /// Opening a lesson goes through the router, so the SwiftData writes the
    /// lesson makes cannot dismiss it. See `Router.skillLesson`.
    private func open(_ skill: Skill) { router.skillLesson = skill }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Become a better cook")
                        .font(BrandFont.nunito(12, 800)).tracking(1.6).textCase(.uppercase)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Skills")
                        .font(BrandFont.bricolage(31, 700))
                        .foregroundStyle(Theme.Colors.heading)
                }
                Spacer()
                if reader.streak > 0 { streakChip }
            }
            progressLine
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var streakChip: some View {
        HStack(spacing: 6) {
            MS.fireFill.sized(16).foregroundStyle(Theme.Colors.coralBright)
            Text("^[\(reader.streak) day](inflect: true)")
                .font(BrandFont.nunito(13, 800)).foregroundStyle(Theme.Colors.amber)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(Capsule().fill(Theme.Colors.amberChip))
        .padding(.top, 6)
    }

    /// Level, skills learned and the bar toward the next level, as one quiet
    /// line rather than a card.
    ///
    /// This used to be a white rounded rectangle with the bear inside it, which
    /// pushed the map below the fold and turned the mascot into a profile
    /// photo. XP, level and skills learned are supporting information; the map
    /// is the product, so they get one line and the bear went to the path.
    private var progressLine: some View {
        let bar = reader.levelProgress
        return VStack(alignment: .leading, spacing: 10) {
            // Level and XP stay exactly as they were. This line is what a cook
            // has walked through; the row below is what they have been seen to
            // do, and keeping them visually separate is the whole point.
            HStack(spacing: 6) {
                Text("Level \(bar.level)")
                    .font(BrandFont.nunito(14.5, 800))
                    .foregroundStyle(Theme.Colors.heading)
                Text("·")
                    .foregroundStyle(Theme.Colors.muted)
                Text(reader.learnedCount == 1 ? "1 skill" : "\(reader.learnedCount) skills")
                    .font(BrandFont.nunito(14, 700))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: 0)
                Text("\(bar.needed - bar.into) XP to \(bar.level + 1)")
                    .font(BrandFont.nunito(11.5, 700))
                    .foregroundStyle(Theme.Colors.muted)
                    .lineLimit(1)
                    .fixedSize()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.surface2)
                    Capsule()
                        .fill(Theme.Colors.accent)
                        .frame(width: max(5, proxy.size.width * fraction(bar)))
                }
            }
            .frame(height: 7)

            cookRatingRow
        }
    }

    /// The way in to the rating, as an actual row rather than status text.
    ///
    /// This used to be the words "Unranked · pass a trial to start", which read
    /// as passive status and gave nobody a reason to touch it. A labelled row
    /// with a value and a chevron is the iOS grammar for "this opens
    /// something", and it is the difference between a feature being present and
    /// being findable.
    ///
    /// Deliberately no card, no background and no container: the map is the
    /// feature and this must not push it down the screen. It is one row of
    /// type, a divider above, and a 44pt tap target.
    @ViewBuilder private var cookRatingRow: some View {
        Divider().padding(.top, 2)

        Button {
            Haptics.selection()
            isShowingProfile = true
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cook Rating")
                        .font(BrandFont.nunito(14, 700))
                        .foregroundStyle(Theme.Colors.heading)
                    // Only while unranked, and it says what earns one rather
                    // than merely naming the state.
                    if reader.cookRank == nil {
                        Text(CookRating.placementLine(reader.evidence))
                            .font(BrandFont.nunito(11.5, 600))
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                Spacer(minLength: 8)
                Text(ratingValue)
                    .font(BrandFont.nunito(14, 800))
                    .foregroundStyle(reader.cookRank == nil
                                     ? Theme.Colors.muted : Theme.Colors.heading)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.muted)
            }
            // Comfortably past Apple's 44pt minimum, without a background that
            // would turn this into a card.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var ratingValue: String {
        guard let rating = reader.cookRating, let rank = reader.cookRank else { return "Unranked" }
        return "\(rating.formatted()) · \(rank.title)"
    }

    private func fraction(_ bar: (level: Int, into: Int, needed: Int)) -> CGFloat {
        guard bar.needed > 0 else { return 0 }
        return min(1, CGFloat(bar.into) / CGFloat(bar.needed))
    }

    /// First run. A map at 0% with nothing pointed at is a dead map, so a cook
    /// who has learned nothing gets one obvious place to begin.
    @ViewBuilder
    private var startHere: some View {
        if let first = reader.recommended {
            Button {
                Haptics.impact(.light)
                open(first)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                Image("bearSpoon")
                    .resizable().scaledToFit().frame(height: 78)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start your cooking journey")
                        .font(BrandFont.bricolage(19, 700))
                        .foregroundStyle(Theme.Colors.heading)
                    Text("Begin with a few fundamentals. You can explore anything you like along the way.")
                        .font(BrandFont.nunito(13.5, 600))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text(first.title)
                            .font(BrandFont.nunito(14.5, 800))
                            .foregroundStyle(Theme.Colors.creamText)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.Colors.creamText)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Theme.Colors.accent))
                    .padding(.top, 2)
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.Colors.greenTint)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }
}
