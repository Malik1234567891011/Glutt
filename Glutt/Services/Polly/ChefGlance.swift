import Foundation

/// The look the cook did not ask for: when Chef takes one, and what she is
/// looking for when she does.
///
/// `ChefWatchfulness` has carried a `glanceInterval` since the picker shipped
/// and nothing has ever read it. The prompt told her to speak up unasked, and
/// she cannot: a realtime model only acts when something hands it a turn, and
/// the only things that ever did were the cook talking and a tool result coming
/// back. So "Chef watches the whole cook" was a promise kept entirely by the
/// cook remembering to ask her to look, which is the one thing the glasses were
/// supposed to stop being necessary.
///
/// This is the missing half: a clock that hands her a turn, a brief naming what
/// this particular step can get wrong, and explicit permission to say nothing.
/// The timing rules live here rather than in the controller because they are the
/// interesting part and they are worth testing without a WebRTC session in the
/// room.
enum ChefGlance {

    /// Everything the decision depends on, gathered at the call site so this
    /// stays pure.
    struct Conditions: Equatable {
        /// Glasses are streaming. A phone propped on the counter pointing at the
        /// ceiling cannot support this and must never trigger it, which is the
        /// same reason the watchfulness picker is only drawn with glasses on.
        var canSee: Bool
        var watchfulness: ChefWatchfulness
        /// She is speaking, thinking, listening, or a clip is playing. Every one
        /// of those means the cook's attention is already spoken for.
        var isBusy: Bool
        var now: Date
        /// The later of: the last unprompted look, the end of the last turn, and
        /// the moment this step opened. Whichever happened last resets the clock,
        /// so a look never lands three seconds after she has just been talking.
        var quietSince: Date?
        /// Unprompted looks already spent on this step.
        var glancesThisStep: Int

        init(
            canSee: Bool,
            watchfulness: ChefWatchfulness,
            isBusy: Bool,
            now: Date,
            quietSince: Date?,
            glancesThisStep: Int
        ) {
            self.canSee = canSee
            self.watchfulness = watchfulness
            self.isBusy = isBusy
            self.now = now
            self.quietSince = quietSince
            self.glancesThisStep = glancesThisStep
        }
    }

    static func isDue(_ c: Conditions) -> Bool {
        guard c.canSee else { return false }
        guard let interval = c.watchfulness.glanceInterval else { return false }
        guard !c.isBusy else { return false }
        guard c.glancesThisStep < c.watchfulness.glanceBudgetPerStep else { return false }
        // Nil rather than distantPast: a step that has not opened yet has no
        // clock to be late against, and starting one from 1970 would fire a look
        // the instant the glasses connect.
        guard let quietSince = c.quietSince else { return false }
        return c.now.timeIntervalSince(quietSince) >= interval
    }

    /// True when this step is one an unprompted look can actually judge.
    ///
    /// Same rule the tool layer already uses to refuse an unseen `mark_step_done`:
    /// a step with a `visualCheck` is a step where something can go wrong on
    /// camera. It also keeps her off Tools, Prep and the steps that are only a
    /// pot going on, where a look has nothing to be right or wrong about and the
    /// only possible outcome is noise.
    static func canJudge(_ step: CookPlan.PlanStep) -> Bool {
        !(step.visualCheck?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    /// The note that arrives just before the turn. Short on purpose: the durable
    /// rules for what to do with a look live in the session prompt, and repeating
    /// them every twelve seconds would fill the context with instructions she
    /// already has.
    ///
    /// - Parameter number: which look this is on this step, counting from one.
    ///   She gets told, because "do not say the same thing twice" is impossible
    ///   to obey without knowing you have already been here.
    static func brief(for step: CookPlan.PlanStep, number: Int) -> String? {
        guard let look = step.visualCheck?.trimmingCharacters(in: .whitespacesAndNewlines),
              !look.isEmpty else { return nil }

        var lines = [
            "[system note] Unprompted look number \(number) at \"\(step.title)\". "
                + "The cook did not ask for this and does not know it is happening.",
            "Right looks like: \(look)",
        ]
        if let recovery = step.recovery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recovery.isEmpty {
            lines.append("Going wrong looks like: \(recovery)")
        }
        if number > 1 {
            lines.append(
                "You have already looked at this step \(number - 1) "
                + (number == 2 ? "time" : "times")
                + ". Do not repeat anything you have already said about it.")
        }
        lines.append("Follow the UNPROMPTED LOOK rules.")
        return lines.joined(separator: "\n")
    }
}
