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
enum SkillLearningMode: String, CaseIterable, Identifiable, Sendable {
    /// Glasses on, Chef watching live and correcting as you go.
    case watching
    /// No glasses. Chef teaches, you try it, you send her photos.
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

/// The one place that decides which mode a lesson runs in.
///
/// Detection picks the first answer and the cook can overrule it forever after.
/// That combination is deliberate: a pure toggle is a setting somebody flips
/// once and then forgets, leaving the app confidently wrong for them, and pure
/// detection takes away a choice that is genuinely theirs. Detecting once and
/// then obeying them is the version that is right on the first run without
/// anybody configuring anything.
@Observable
final class SkillLearningModeStore {
    private enum Keys {
        static let mode = "glutt.skills.learningMode"
        static let chosen = "glutt.skills.learningModeChosen"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasChosen = defaults.bool(forKey: Keys.chosen)
        self.mode = defaults.string(forKey: Keys.mode)
            .flatMap(SkillLearningMode.init(rawValue:)) ?? .showing
    }

    /// True once the cook has picked for themselves. Until then the stored
    /// value is only ever a guess and detection is allowed to move it.
    private(set) var hasChosen: Bool

    /// The mode to run in. Falls back to photos, which is the mode that works
    /// for everybody rather than the one that needs hardware.
    ///
    /// Stored rather than computed straight off `UserDefaults`, which is how it
    /// was written first and did not work: `@Observable` tracks stored property
    /// access, so a computed property reading defaults changes nothing it can
    /// see, and the switch inside a lesson wrote the new mode and left the
    /// screen sitting there showing the old one.
    var mode: SkillLearningMode {
        didSet { persist() }
    }

    /// The cook picking for themselves, which is different from the mode simply
    /// changing.
    ///
    /// Separate from the setter because picking the mode you are already in has
    /// to count. Somebody on the photos guess who deliberately taps Photos has
    /// chosen it, and if that does not register then the first time a pair of
    /// glasses connects they get silently moved off the thing they asked for.
    func choose(_ picked: SkillLearningMode) {
        hasChosen = true
        mode = picked
        persist()
    }

    private func persist() {
        defaults.set(mode.rawValue, forKey: Keys.mode)
        defaults.set(hasChosen, forKey: Keys.chosen)
    }

    /// Whether a pair of glasses has ever actually connected on this phone.
    ///
    /// The only honest signal available. `GlassesSupport.isAvailable` sounds
    /// like the right question and is not: it means the toolkit configured,
    /// which is true on every install whether or not the cook owns anything,
    /// and using it defaulted the entire world into a mode that needs hardware.
    /// Connection state is otherwise only knowable after starting a session,
    /// which is far too late to decide what a lesson screen should offer.
    ///
    /// So it is remembered instead. Nothing until the first successful connect
    /// anywhere in the app, and from then on Skills opens in watching mode.
    static var glassesHaveConnected: Bool {
        get { UserDefaults.standard.bool(forKey: "glutt.glasses.everConnected") }
        set { UserDefaults.standard.set(newValue, forKey: "glutt.glasses.everConnected") }
    }

    /// Set the opening guess from whether glasses are actually reachable.
    ///
    /// Silently ignored once the cook has chosen, so plugging a pair in does not
    /// quietly switch somebody who had already said they wanted photos.
    func suggest(glassesAvailable: Bool) {
        guard !hasChosen else { return }
        // Straight to `mode`, never through `choose`. A guess has to stay a
        // guess or the next one cannot correct it.
        mode = glassesAvailable ? .watching : .showing
    }

    /// For tests, and for a settings screen that wants to hand the decision back.
    func forget() {
        hasChosen = false
        mode = .showing
    }
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
