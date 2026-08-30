import Foundation
import SwiftUI

/// How a cook is going to prove they can do something.
///
/// Not a capture setting. The two modes are genuinely different lessons, which
/// is the thing that took a while to see: without glasses Chef cannot narrate
/// over somebody's hands while they work, so she teaches, they check themselves,
/// and then they show her. Every instruction changes with it. "Look down at your
/// hand and turn it slowly" is a sentence that only makes sense when the camera
/// is on your face, and it is nonsense when the camera is the thing you are
/// holding.
///
/// `.showing` is deliberately not a fallback. For half the catalog it is the
/// better path: nobody can see both faces of a knife from their own eyes, and a
/// phone takes one photo of each. A board of finished dice photographs better
/// standing over it than it ever looks through glasses.
/// **Only `.showing` is reachable on this branch.** `.watching` meant glasses
/// on, Chef correcting live, and it went out with the hardware. The case itself
/// stays because `SkillAttempt` persists this and the SwiftData schema has to
/// stay identical to `skills-knife-coaching`, or moving between builds becomes
/// a migration.
enum SkillLearningMode: String, CaseIterable, Identifiable, Sendable {
    /// Glasses on, Chef watching live. Not reachable here.
    case watching
    /// Chef teaches, you try it, you send her photos.
    case showing

    var id: String { rawValue }

    /// What the toggle says.
    var label: String {
        switch self {
        case .watching: "Meta glasses"
        case .showing: "Photos"
        }
    }

    var glyph: String {
        switch self {
        case .watching: "eyeglasses"
        case .showing: "camera.fill"
        }
    }

    /// One line under the toggle, so the choice is legible rather than jargon.
    var explanation: String {
        switch self {
        case .watching:
            "Chef watches through your glasses and corrects you while you work."
        case .showing:
            "Chef talks you through it, then you send her photos and she checks them."
        }
    }

    var other: SkillLearningMode { self == .watching ? .showing : .watching }
}

/// Counts written out, for the places a runtime built string cannot use
/// inflection markup.
///
/// `^[\(n) photo](inflect: true)` only resolves when the string is a
/// `LocalizedStringKey` literal. Interpolated into a `String` and handed to
/// `Text`, it renders as the raw markup, which is exactly what shipped on the
/// lesson screen for a moment.
enum SkillCount {
    static func photos(_ n: Int) -> String {
        switch n {
        case 1: "one photo"
        case 2: "two photos"
        case 3: "three photos"
        default: "\(n) photos"
        }
    }

    /// Sentence case, not `.capitalized`, which title-cases every word and
    /// turns "two photos" into "Two Photos".
    static func photosSentence(_ n: Int) -> String {
        let text = photos(n)
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
