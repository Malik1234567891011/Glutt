import SwiftUI

/// A region of the cooking map. Each has its own colour identity so a cook
/// learns to recognise "the green one is knives" without reading a label.
struct SkillCategory: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// One line under the region title. Says what the region is for, not what
    /// it contains.
    let blurb: String
    let theme: SkillTheme
    let skills: [Skill]

    var learnableCount: Int { skills.count }
    /// Regions we have written. An unauthored region still appears on the map,
    /// because seeing how far the world goes is the point.
    var isAuthored: Bool { skills.contains(where: \.isAuthored) }
}

/// A region's colour identity.
///
/// Three levels, deliberately. The canvas stays quiet cream everywhere. A
/// region only tints the air, enough to be recognised but never enough to
/// become a surface. The saturated end of the palette is reserved for
/// interaction: the node you have finished and the node you should tap next.
///
/// The first pass drew every wash from the existing warm palette, and Knife
/// Skills in `surface3` was indistinguishable from bare cream, which defeats
/// the point of having regions at all. So two soft tints outside the warm range
/// were added, used **only** as atmosphere behind nodes and never as a fill or
/// a text colour, which keeps Glutt's cream and herb identity intact while
/// letting one area feel different from the next.
struct SkillTheme: Hashable, Sendable {
    /// Node fill and region label colour. Always from the core palette.
    let tint: Color
    /// The soft shape of air behind a region's nodes.
    let wash: Color

    static let herb = SkillTheme(tint: Theme.Colors.accent, wash: Theme.Colors.greenTint)
    static let ember = SkillTheme(tint: Theme.Colors.coralBright, wash: Theme.Colors.tomatoTint)
    static let amber = SkillTheme(tint: Theme.Colors.amber, wash: Theme.Colors.amberChip)
    static let peach = SkillTheme(tint: Theme.Colors.tomato, wash: Theme.Colors.peachPanel)

    /// Atmosphere only. A cool, dusty blue that reads as a different part of the
    /// world without introducing a second brand colour.
    static let sky = SkillTheme(tint: Theme.Colors.accent, wash: Color(hex: 0xDCE6EC))
    /// Atmosphere only. A muted mauve for the flavour end of the map.
    static let plum = SkillTheme(tint: Theme.Colors.tomato, wash: Color(hex: 0xE7DEE8))
}
