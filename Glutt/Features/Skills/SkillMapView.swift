import SwiftUI

/// The cooking world: one continuous scroll, not a stack of cards.
///
/// The first version drew every category as a big rounded rectangle, and by the
/// third region the whole feature read as a vertical pile of modules rather than
/// a place. So the containers are gone. The cream canvas runs the entire length
/// of the map and each region only tints the air around it, fading back to cream
/// before the next one begins.
///
/// Regions are rows of a `LazyVStack` in the parent scroll view, so sixty nodes
/// across eight regions are still only built as they scroll into view.
struct SkillMapView: View {
    let reader: SkillsProgressReader
    let onOpen: (Skill) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(SkillCatalog.categories.enumerated()), id: \.element.id) { index, category in
                SkillRegionView(
                    category: category,
                    regionIndex: index,
                    reader: reader,
                    onOpen: onOpen
                )
            }
        }
    }
}

/// One area of the world.
private struct SkillRegionView: View {
    let category: SkillCategory
    let regionIndex: Int
    let reader: SkillsProgressReader
    let onOpen: (Skill) -> Void

    /// Vertical space per node. Generous on purpose: the map is meant to be
    /// travelled through, not surveyed.
    private static let rowHeight: CGFloat = 112

    private var learned: Int {
        SkillProgression.learnedCount(in: category, learnedIDs: reader.learnedIDs)
    }

    /// Where Polly is standing, if the recommended skill lives in this region.
    private var bearIndex: Int? {
        guard let recommended = reader.recommended, recommended.categoryID == category.id else { return nil }
        return category.skills.firstIndex { $0.id == recommended.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SkillRegionHeader(
                category: category,
                learned: learned,
                total: category.learnableCount,
                rating: reader.rating(for: category),
                isRateable: RegionRating.isRateable(category))
                .padding(.horizontal, 24)

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    // Behind everything: the region's atmosphere. An irregular
                    // soft wash rather than a card, so the eye reads a place
                    // rather than a container.
                    RegionAtmosphere(theme: category.theme, seed: regionIndex)

                    trail(width: proxy.size.width, learnedIDs: reader.learnedIDs)

                    ForEach(Array(category.skills.enumerated()), id: \.element.id) { index, skill in
                        SkillNodeView(
                            skill: skill,
                            state: reader.state(for: skill),
                            tint: category.theme.tint,
                            personalBest: reader.personalBest(for: skill.id)
                        ) { onOpen(skill) }
                        .position(center(of: index, skill: skill, width: proxy.size.width))
                    }

                    // Polly stands next to the skill the cook is on, which is
                    // both the character moment and the answer to "where am I".
                    if let bearIndex {
                        let skill = category.skills[bearIndex]
                        let point = center(of: bearIndex, skill: skill, width: proxy.size.width)
                        Image("bearPointing")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 84)
                            .position(
                                x: bearX(for: skill.column, width: proxy.size.width),
                                y: point.y - 6
                            )
                            .allowsHitTesting(false)
                    }
                }
                // She walks to the next node rather than blinking out of one
                // and into the other. An opacity transition here used to drop
                // her entirely when the recommendation moved.
                .animation(.spring(response: 0.55, dampingFraction: 0.8), value: bearIndex)
            }
            .frame(height: CGFloat(category.skills.count) * Self.rowHeight + 24)
        }
        .padding(.bottom, 10)
    }

    private func center(of index: Int, skill: Skill, width: CGFloat) -> CGPoint {
        CGPoint(
            x: width * skill.column.unitX,
            y: CGFloat(index) * Self.rowHeight + Self.rowHeight / 2
        )
    }

    /// Polly stands on the opposite side of the node from the map's centre, so
    /// he never covers the path or the label.
    private func bearX(for column: SkillColumn, width: CGFloat) -> CGFloat {
        switch column {
        case .left: width * 0.62
        case .center: width * 0.80
        case .right: width * 0.20
        }
    }

    /// The route, drawn in two passes so the journey colours itself in behind
    /// the cook: solid in the region's own colour where they have been, faint
    /// and dashed where they have not.
    @ViewBuilder
    private func trail(width: CGFloat, learnedIDs: Set<String>) -> some View {
        ZStack {
            path(width: width, upTo: nil)
                .stroke(
                    Theme.Colors.border.opacity(0.9),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 12])
                )
            // Only where they have actually been. Passing nil here used to fall
            // through to "the whole path", which painted the route solid on a
            // map where nothing had been learned and read as finished.
            if let travelled = travelledIndex(learnedIDs) {
                path(width: width, upTo: travelled)
                    .stroke(category.theme.tint.opacity(0.6), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
    }

    /// How far the ink runs: to wherever the cook is standing.
    ///
    /// Not simply the last learned node. Finishing the first skill moves Polly
    /// onto the second, so the segment between them has been walked, and
    /// stopping the colour at the learned node left her standing on grey with
    /// the map reading as "nothing done yet". The ink follows her.
    private func travelledIndex(_ learnedIDs: Set<String>) -> Int? {
        let learned = lastLearnedIndex(learnedIDs)
        guard let bearIndex else { return learned }
        return max(learned ?? 0, bearIndex)
    }

    /// The last consecutive learned skill, which is as far as the cook has
    /// definitely finished.
    private func lastLearnedIndex(_ learnedIDs: Set<String>) -> Int? {
        var last: Int?
        for (index, skill) in category.skills.enumerated() {
            guard learnedIDs.contains(skill.id) else { break }
            last = index
        }
        return last
    }

    /// The route between nodes.
    ///
    /// Each segment stops at the node's edge rather than its centre. Drawn
    /// centre to centre, the solid travelled portion ran straight through the
    /// name printed under the node it was leaving, which was invisible while
    /// the whole path was a faint dotted line and obvious the moment any of it
    /// turned solid.
    private func path(width: CGFloat, upTo limit: Int?) -> Path {
        Path { path in
            let end = min(limit ?? (category.skills.count - 1), category.skills.count - 1)
            guard end > 0 else { return }
            for index in 0 ..< end {
                let fromSkill = category.skills[index]
                let toSkill = category.skills[index + 1]
                let from = center(of: index, skill: fromSkill, width: width)
                let to = center(of: index + 1, skill: toSkill, width: width)

                let dx = to.x - from.x
                let dy = to.y - from.y
                let length = max(sqrt(dx * dx + dy * dy), 1)
                let unit = CGPoint(x: dx / length, y: dy / length)

                // Leaving the node: clear the circle and the label under it.
                let start = inset(from, by: radius(of: fromSkill) + 22, along: unit)
                let finish = inset(to, by: -(radius(of: toSkill) + 8), along: unit)
                guard length > radius(of: fromSkill) + radius(of: toSkill) + 30 else { continue }

                path.move(to: start)
                path.addQuadCurve(
                    to: finish,
                    control: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                )
            }
        }
    }

    private func radius(of skill: Skill) -> CGFloat {
        SkillNodeView.diameter(for: skill, state: reader.state(for: skill)) / 2
    }

    private func inset(_ point: CGPoint, by distance: CGFloat, along unit: CGPoint) -> CGPoint {
        CGPoint(x: point.x + unit.x * distance, y: point.y + unit.y * distance)
    }
}

/// The soft colour that says "you are somewhere new" without drawing a box.
///
/// Two offset blurred ellipses rather than a rounded rectangle. They bleed past
/// the edges and fade out top and bottom, so one region melts into the next and
/// the cream canvas is never actually interrupted.
private struct RegionAtmosphere: View {
    let theme: SkillTheme
    let seed: Int

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Ellipse()
                    .fill(theme.wash.opacity(0.95))
                    .frame(width: w * 1.5, height: h * 0.66)
                    .position(x: w * (seed.isMultiple(of: 2) ? 0.34 : 0.66), y: h * 0.3)
                Ellipse()
                    .fill(theme.wash.opacity(0.8))
                    .frame(width: w * 1.35, height: h * 0.6)
                    .position(x: w * (seed.isMultiple(of: 2) ? 0.72 : 0.28), y: h * 0.74)
            }
            .blur(radius: 46)
        }
        .allowsHitTesting(false)
    }
}

/// A region's title, set on the canvas rather than on a card.
private struct SkillRegionHeader: View {
    let category: SkillCategory
    let learned: Int
    let total: Int
    /// What this region has been shown to be worth, when there is anything to
    /// show. Nil covers two different situations and both are correct: not
    /// enough judged trials yet, and regions that cannot be judged at all.
    let rating: Int?
    /// True where a rating is possible in principle, so "Unranked" can be shown
    /// as a thing to earn rather than left blank forever on a region that will
    /// never have one.
    let isRateable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(category.name)
                    .font(BrandFont.bricolage(23, 700))
                    .foregroundStyle(Theme.Colors.heading)
                Spacer(minLength: 0)
                // A finished region says so, rather than making the cook read
                // "9 / 9" and work it out.
                if total > 0, learned == total {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Done")
                            .font(BrandFont.nunito(12.5, 800))
                    }
                    .foregroundStyle(Theme.Colors.accent)
                    .fixedSize()
                } else {
                    Text("\(learned) / \(total)")
                        .font(BrandFont.nunito(12.5, 800))
                        .foregroundStyle(category.theme.tint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(category.blurb)
                .font(BrandFont.nunito(13, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // The region's standard, under its own blurb rather than in a
            // strip of scores across the top of the tab. Scrolling the world
            // shows them one at a time, which is a dashboard nobody had to
            // build.
            //
            // Nothing at all on Flavour & Seasoning or Cooking Intuition. They
            // have no visual checks because you cannot photograph tasting as
            // you go, and giving them a number for the sake of symmetry would
            // be inventing a measurement. The asymmetry is the honest part.
            if isRateable {
                HStack(spacing: 6) {
                    if let rating {
                        Text("\(rating)")
                            .font(BrandFont.nunito(15, 800))
                            .foregroundStyle(category.theme.tint)
                            .monospacedDigit()
                        Text("skill rating")
                            .font(BrandFont.nunito(11.5, 700))
                            .foregroundStyle(Theme.Colors.muted)
                    } else {
                        Text("Unranked")
                            .font(BrandFont.nunito(12, 700))
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 26)
    }
}
