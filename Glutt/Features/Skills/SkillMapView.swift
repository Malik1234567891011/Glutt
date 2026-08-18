import SwiftUI

/// The cooking map: one long vertical scroll through every region.
///
/// Laid out rather than freeform. Each region computes node positions from a
/// column hint and a fixed row height, so the map looks handcrafted while
/// staying something a person can reason about. No physics, no 2D pan canvas,
/// and no dragging around a giant surface on a phone.
///
/// Regions are rows of a `LazyVStack` in the parent scroll view, so the eight
/// regions and their sixty nodes are only built as they come into view.
struct SkillMapView: View {
    let reader: SkillsProgressReader
    let onOpen: (Skill) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(SkillCatalog.categories.enumerated()), id: \.element.id) { index, category in
                SkillRegionView(
                    category: category,
                    reader: reader,
                    onOpen: onOpen
                )
                if index < SkillCatalog.categories.count - 1 {
                    regionJoin
                }
            }
        }
    }

    /// The dotted run between one region and the next, so the map reads as one
    /// world rather than a stack of separate cards.
    private var regionJoin: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 34))
        }
        .stroke(
            Theme.Colors.border,
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [2, 9])
        )
        .frame(width: 3, height: 34)
        .frame(maxWidth: .infinity)
    }
}

/// One coloured region of the map.
private struct SkillRegionView: View {
    let category: SkillCategory
    let reader: SkillsProgressReader
    let onOpen: (Skill) -> Void

    /// Vertical space per node. Enough that labels never collide with the row
    /// below, which is what makes a staggered layout read as a path.
    private static let rowHeight: CGFloat = 104

    private var learned: Int {
        SkillProgression.learnedCount(in: category, learnedIDs: reader.learnedIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            regionHeader
            GeometryReader { proxy in
                ZStack {
                    connectingPath(width: proxy.size.width)
                    ForEach(Array(category.skills.enumerated()), id: \.element.id) { index, skill in
                        SkillNodeView(
                            skill: skill,
                            state: reader.state(for: skill),
                            tint: category.theme.tint
                        ) { onOpen(skill) }
                        .position(center(of: index, skill: skill, width: proxy.size.width))
                    }
                }
            }
            .frame(height: CGFloat(category.skills.count) * Self.rowHeight)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .background(
            // A soft organic wash rather than a rectangular card, so regions
            // feel like areas of a map instead of a list of boxes.
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(category.theme.wash.opacity(0.55))
                .padding(.horizontal, 8)
        )
    }

    private var regionHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(category.name)
                    .font(BrandFont.bricolage(21, 700))
                    .foregroundStyle(Theme.Colors.heading)
                Spacer(minLength: 0)
                Text("\(learned) / \(category.learnableCount)")
                    .font(BrandFont.nunito(12.5, 800))
                    .foregroundStyle(category.theme.tint)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(category.blurb)
                .font(BrandFont.nunito(13, 600))
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func center(of index: Int, skill: Skill, width: CGFloat) -> CGPoint {
        CGPoint(
            x: width * skill.column.unitX,
            y: CGFloat(index) * Self.rowHeight + Self.rowHeight / 2
        )
    }

    /// Curved joins between consecutive nodes. Drawn once per region behind the
    /// nodes, so a region of twelve skills is one path rather than twelve views.
    private func connectingPath(width: CGFloat) -> some View {
        Path { path in
            for index in 0 ..< max(0, category.skills.count - 1) {
                let from = center(of: index, skill: category.skills[index], width: width)
                let to = center(of: index + 1, skill: category.skills[index + 1], width: width)
                path.move(to: from)
                // A single control point between the two rows gives the lane a
                // gentle S without needing per-node tuning.
                path.addQuadCurve(
                    to: to,
                    control: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                )
            }
        }
        .stroke(
            category.theme.tint.opacity(0.28),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 10])
        )
    }
}
