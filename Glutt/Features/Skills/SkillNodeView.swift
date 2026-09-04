import SwiftUI

/// One skill on the map.
///
/// Nodes were identical white circles with a tiny dot, which is a wireframe
/// state: nothing to recognise, nothing to remember, and no way to tell at a
/// glance which one to touch. Now every skill carries its own glyph, and the
/// states differ in size, fill, ring and weight rather than only in colour.
///
/// The recommended node is deliberately the loudest object on the screen. It is
/// larger, saturated, ringed and haloed, because the single most useful thing
/// the map can say is "tap this one".
struct SkillNodeView: View {
    let skill: Skill
    let state: SkillState
    let tint: Color
    /// How many times this skill has been verified. Zero on anything never
    /// shown to her.
    var verifiedCount: Int = 0
    let onTap: () -> Void

    /// Shared with the map, which has to know where a node ends so the trail
    /// can stop at its edge rather than run through the label underneath it.
    static func diameter(for skill: Skill, state: SkillState) -> CGFloat {
        if skill.isChallenge { return state == .recommended ? 92 : 84 }
        return state == .recommended ? 78 : 62
    }

    private var diameter: CGFloat { Self.diameter(for: skill, state: state) }

    private var glyphSize: CGFloat { diameter * (skill.isChallenge ? 0.4 : 0.36) }

    var body: some View {
        Button(action: {
            Haptics.impact(state == .recommended ? .medium : .light)
            onTap()
        }) {
            VStack(spacing: 7) {
                shape
                label
            }
            // Comfortably past Apple's 44pt minimum even for the smallest node.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var shape: some View {
        ZStack {
            // Halo, recommended only. Soft enough that it reads as attention
            // rather than an alert.
            if state == .recommended {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: diameter + 26, height: diameter + 26)
            }

            container
                .frame(width: diameter, height: diameter)
                .shadow(
                    color: Theme.Colors.textPrimary.opacity(shadowOpacity),
                    radius: state == .recommended ? 14 : 8,
                    y: state == .recommended ? 6 : 3
                )

            glyph
        }
    }

    /// Mastery nodes get a different silhouette, not just a bigger circle, so a
    /// milestone is recognisable while scrolling past at speed.
    @ViewBuilder
    private var container: some View {
        if skill.isChallenge {
            RoundedRectangle(cornerRadius: diameter * 0.31, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: diameter * 0.31, style: .continuous)
                        .strokeBorder(stroke, style: strokeStyle)
                )
                .rotationEffect(.degrees(45))
                .scaleEffect(0.82)
        } else {
            Circle()
                .fill(fill)
                .overlay(Circle().strokeBorder(stroke, style: strokeStyle))
        }
    }

    /// The skill's own glyph, with a plain dot as the fallback so an SF Symbol
    /// that does not exist on this OS degrades instead of vanishing.
    @ViewBuilder
    private var glyph: some View {
        if state == .learned {
            Image(systemName: "checkmark")
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(Theme.Colors.creamText)
        } else if UIImage(systemName: skill.glyph) != nil {
            Image(systemName: skill.glyph)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(glyphColor)
        } else {
            Circle()
                .fill(glyphColor)
                .frame(width: glyphSize * 0.5, height: glyphSize * 0.5)
        }
    }

    private var label: some View {
        VStack(spacing: 1) {
            Text(skill.shortName)
                .font(BrandFont.nunito(state == .recommended ? 13 : 12, state == .learned || state == .recommended ? 800 : 700))
                .foregroundStyle(labelColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            if state == .recommended {
                Text("NEXT")
                    .font(BrandFont.nunito(9.5, 800)).tracking(1.1)
                    .foregroundStyle(tint)
            }
            // A node that has actually been shown to her wears a small mark,
            // and only mastery trials carry a count.
            //
            // No score, because evidence is not a score. No personal-best
            // module and no trophy card either: the map itself is the cabinet,
            // and a seal on a diamond you passed is the record, in the place
            // where you set it.
            if verifiedCount > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold))
                    if skill.isChallenge, verifiedCount > 1 {
                        Text("\(verifiedCount)")
                            .font(BrandFont.nunito(11, 800))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(tint)
            }
        }
        .frame(width: 112)
    }

    private var fill: Color {
        switch state {
        case .learned: tint
        case .recommended: tint
        case .inProgress: Theme.Colors.card
        case .comingSoon: Theme.Colors.surface2.opacity(0.55)
        case .notStarted: Theme.Colors.card
        }
    }

    private var glyphColor: Color {
        switch state {
        case .recommended: Theme.Colors.creamText
        case .comingSoon: Theme.Colors.muted.opacity(0.55)
        case .inProgress: tint
        default: tint.opacity(0.55)
        }
    }

    private var stroke: Color {
        switch state {
        case .learned: .clear
        case .recommended: Theme.Colors.creamText.opacity(0.85)
        case .inProgress: tint.opacity(0.75)
        case .comingSoon: Theme.Colors.border.opacity(0.8)
        case .notStarted: Theme.Colors.border
        }
    }

    private var strokeStyle: StrokeStyle {
        switch state {
        case .comingSoon: StrokeStyle(lineWidth: 1.5, dash: [3, 4])
        case .recommended: StrokeStyle(lineWidth: 3)
        case .inProgress: StrokeStyle(lineWidth: 2.5)
        default: StrokeStyle(lineWidth: 1.5)
        }
    }

    private var shadowOpacity: Double {
        switch state {
        case .comingSoon: 0
        case .recommended: 0.20
        default: 0.09
        }
    }

    private var labelColor: Color {
        switch state {
        case .comingSoon: Theme.Colors.muted
        case .learned, .recommended: Theme.Colors.heading
        default: Theme.Colors.textSecondary
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .learned: "\(skill.title), learned"
        case .recommended: "\(skill.title), recommended next"
        case .inProgress: "\(skill.title), in progress"
        case .comingSoon: "\(skill.title), coming soon"
        case .notStarted: skill.title
        }
    }
}
