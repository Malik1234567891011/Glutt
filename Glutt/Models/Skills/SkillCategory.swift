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

/// A region's colour identity, drawn entirely from the existing palette.
///
/// Deliberately no new hexes. The brief suggests colours per region, but Glutt
/// already has a warm cream and herb green identity, and eight invented hues
/// would read as a different app bolted on. These are the palette's own accents
/// used at low opacity behind nodes, which keeps the map soft and unmistakably
/// Glutt.
struct SkillTheme: Hashable, Sendable {
    /// The node fill and region label colour.
    let tint: Color
    /// The soft organic shape behind a region's nodes.
    let wash: Color

    static let herb = SkillTheme(tint: Theme.Colors.accent, wash: Theme.Colors.greenTint)
    static let ember = SkillTheme(tint: Theme.Colors.coralBright, wash: Theme.Colors.tomatoTint)
    static let amber = SkillTheme(tint: Theme.Colors.amber, wash: Theme.Colors.amberChip)
    static let peach = SkillTheme(tint: Theme.Colors.tomato, wash: Theme.Colors.peachPanel)
    static let sand = SkillTheme(tint: Theme.Colors.textSecondary, wash: Theme.Colors.surface3)
}
