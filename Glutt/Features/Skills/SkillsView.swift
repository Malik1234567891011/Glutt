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

    private var reader: SkillsProgressReader { SkillsProgressReader(progress: progressRows) }

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
            progressCard
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

    /// Level, the bar toward the next one, and the bear. One card rather than
    /// four separate stats, so progression reads at a glance.
    private var progressCard: some View {
        let bar = reader.levelProgress
        return HStack(spacing: 14) {
            Image("gluttBear")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.Colors.surface2))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Level \(bar.level)")
                        .font(BrandFont.nunito(15, 800))
                        .foregroundStyle(Theme.Colors.heading)
                    Text(reader.learnedCount == 1 ? "1 skill learned" : "\(reader.learnedCount) skills learned")
                        .font(BrandFont.nunito(12.5, 700))
                        .foregroundStyle(Theme.Colors.muted)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Colors.surface2)
                        Capsule()
                            .fill(Theme.Colors.accent)
                            .frame(width: max(6, proxy.size.width * fraction(bar)))
                    }
                }
                .frame(height: 8)
                Text("\(bar.needed - bar.into) XP to level \(bar.level + 1)")
                    .font(BrandFont.nunito(11.5, 700))
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.group, style: .continuous)
                .strokeBorder(Theme.Colors.textPrimary.opacity(0.06), lineWidth: 1)
        )
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
