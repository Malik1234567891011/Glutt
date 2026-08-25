import Foundation

/// TEMPORARY — FOR THE DEMO VIDEO ONLY.
///
/// Hardcoded lines the chef says when he hears a keyword, so a take can be shot
/// without depending on the model choosing to say the right thing. The scripted
/// line is spoken directly and the model is never asked to respond, which is the
/// only way to make it word-for-word repeatable across takes.
///
/// To revert: delete this file along with its two call sites in
/// `PollySessionController` (`onPartialTranscript` and `handleGatedTranscript`).
enum DemoScript {

    /// The single switch — and Debug-only, so this cannot reach the App Store.
    ///
    /// It has to be build-gated rather than hand-flipped because of what it does
    /// in a real kitchen. The trigger is matched against the on-device
    /// recognizer's partial transcripts, which run even while dormant, so a step
    /// that reads "rest and serve" or a cook asking "when do I serve this?" gets
    /// shouted at. The Realtime path then deletes that turn without answering, so
    /// a genuine question about serving disappears instead of being handled.
    ///
    /// Consequence worth knowing: this is off in every Release build, and the
    /// `Glutt Beta` scheme is Release. Film the demo from the `Glutt` scheme.
    // Off, deliberately, including in Debug.
    //
    // It fires from the on-device recognizer's partial transcripts, which run
    // even while Chef is dormant, so no wake word is needed and the cook has no
    // way to see it coming. "Serve" is the trigger and "Serve" is the name of a
    // step in a recipe we demo, which meant a shouted line landing in the middle
    // of a cook nobody had asked for. The second cost is quieter and worse: the
    // Realtime branch deletes the matching turn, so a genuine "when do I serve
    // this?" disappeared instead of being answered.
    //
    // Flip to `true` only for a take you are directing, and narrow `triggers` to
    // a phrase nobody says by accident before you do.
    static let isEnabled = false

    struct Cue {
        /// Whole words, matched case-insensitively. Substrings never match, so
        /// "preserve" cannot fire the "serve" cue.
        let triggers: Set<String>
        let line: String
        let delivery: PollySpeechClient.Delivery?
    }

    /// Shouted. `eleven_multilingual_v2` has no audio tags, so anger comes from
    /// three places at once: the capitals and the short exclaimed clauses in the
    /// text, stability far below the session default (which is what lets the
    /// read swing), and style well above it (which exaggerates the swing).
    static let shouting = PollySpeechClient.Delivery(stability: 0.2, style: 0.75)

    static let cues: [Cue] = [
        Cue(
            triggers: ["serve", "serving", "served"],
            line: "YOU DONUT! That is NOT the perfect golden brown we are looking for! "
                + "Put it back. RIGHT NOW!",
            delivery: shouting
        ),
    ]

    /// Re-firing on every partial transcript would machine-gun the line, since
    /// the on-device recognizer reports a growing transcript many times a second.
    static let cooldown: TimeInterval = 20

    static func cue(for transcript: String) -> Cue? {
        guard isEnabled else { return nil }
        let words = Set(transcript.lowercased().split { !$0.isLetter }.map(String.init))
        return cues.first { !$0.triggers.isDisjoint(with: words) }
    }
}
