import SwiftUI

/// One skill on the map.
///
/// The states carry the whole meaning of the map, so they are drawn to be told
/// apart at a glance and without colour alone: learned has a tick, recommended
/// has a ring, coming soon is faded and dashed.
struct SkillNodeView: View {
    let skill: Skill
    let state: SkillState
    let tint: Color
    let onTap: () -> Void

    private var diameter: CGFloat { skill.isChallenge ? 76 : 60 }

    var body: some View {
        Button(action: {
            Haptics.impact(.light)
            onTap()
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(fill)
                        .frame(width: diameter, height: diameter)
                        .overlay(Circle().strokeBorder(stroke, style: strokeStyle))
                        .shadow(
                            color: Theme.Colors.textPrimary.opacity(state == .comingSoon ? 0 : 0.10),
                            radius: 8, y: 3
                        )
                    glyph
                }
                // The recommended node gets a soft halo so the eye lands on it
                // without anything flashing.
                .background(
                    Circle()
                        .fill(tint.opacity(state == .recommended ? 0.16 : 0))
                        .frame(width: diameter + 18, height: diameter + 18)
                )

                Text(skill.title)
                    .font(BrandFont.nunito(11.5, state == .learned ? 800 : 700))
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 104)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .learned:
            Image(systemName: "checkmark")
                .font(.system(size: skill.isChallenge ? 26 : 21, weight: .bold))
                .foregroundStyle(Theme.Colors.creamText)
        case .comingSoon:
            Image(systemName: "hourglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.muted)
        case .inProgress:
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tint)
        default:
            if skill.isChallenge {
                Image(systemName: "star.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(state == .recommended ? Theme.Colors.creamText : tint)
            } else {
                Circle()
                    .fill(state == .recommended ? Theme.Colors.creamText.opacity(0.9) : tint.opacity(0.45))
                    .frame(width: 13, height: 13)
            }
        }
    }

    private var fill: Color {
        switch state {
        case .learned: tint
        case .recommended: tint.opacity(0.85)
        case .inProgress: Theme.Colors.card
        case .comingSoon: Theme.Colors.surface2.opacity(0.6)
        case .notStarted: Theme.Colors.card
        }
    }

    private var stroke: Color {
        switch state {
        case .learned: .clear
        case .recommended: tint
        case .inProgress: tint.opacity(0.6)
        case .comingSoon: Theme.Colors.border
        case .notStarted: Theme.Colors.border
        }
    }

    private var strokeStyle: StrokeStyle {
        state == .comingSoon
            ? StrokeStyle(lineWidth: 1.5, dash: [3, 4])
            : StrokeStyle(lineWidth: state == .recommended ? 2.5 : 1.5)
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
