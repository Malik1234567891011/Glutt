import Observation
import UIKit

/// A live window onto exactly what the reader is being shown.
///
/// Built because the argument could not be settled any other way. A cook held a
/// chef's knife with their whole hand wrapped around the blade and was told it
/// was perfect, repeatedly, through four different fixes. Every explanation on
/// offer, bad crop, bad selection, bad question, was a guess about pixels nobody
/// could see at the time. The archive answers it eventually, but only after the
/// lesson has ended and the moment has gone.
///
/// So this mirrors the frames as they are sent, with the marks drawn on and the
/// answers that came back, and the lesson puts them on screen next to the live
/// camera. When she says "perfect" and the cook's hand is on the steel, the
/// pictures she said it about are right there.
///
/// **Debug builds only.** Nothing here ships.
#if DEBUG
@MainActor
@Observable
final class SkillLookMirror {
    static let shared = SkillLookMirror()

    /// Exactly the images handed to the reader, newest look first.
    private(set) var sent: [UIImage] = []

    /// What came back about them, short enough to read at a glance on a phone.
    private(set) var verdict: String = ""

    /// Her per-picture readings, one line each.
    private(set) var readings: [String] = []

    /// When this look happened, so a stale panel is obvious.
    private(set) var at: Date?

    private init() {}

    func show(sent images: [Data]) {
        sent = images.compactMap(UIImage.init(data:))
        verdict = "looking…"
        readings = []
        at = Date()
    }

    func answered(_ verdict: String, readings: [String]) {
        self.verdict = verdict
        self.readings = readings
    }

    func failed(_ reason: String) {
        verdict = "no answer: \(reason)"
        readings = []
    }
}
#endif
