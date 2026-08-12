import Foundation

/// A dictation transcript that can only grow.
///
/// Pulled out of `PantryDictationSession` so the rule that matters is testable
/// without a microphone, because the rule is the whole bug: a cook listing
/// twenty things watched the box empty itself partway through and had to start
/// again.
///
/// `SFSpeechRecognizer` does not hand back one ever-growing string. A
/// recognition request covers roughly a minute of audio, and its
/// `bestTranscription.formattedString` is the hypothesis **for that request
/// only**. Mirror it straight into the UI and everything spoken before the
/// current request disappears the moment a new one starts. The recognizer is
/// also free to revise a hypothesis downward mid-request, which produces the
/// same symptom in miniature.
///
/// So the finished parts are banked and only the tail moves. Nothing that has
/// been banked can be taken away by a later result.
struct DictationTranscript: Equatable {
    /// Segments from recognition requests that have already finished.
    private(set) var banked: [String] = []
    /// The hypothesis for the request currently running.
    private(set) var live = ""

    var text: String {
        (banked + [live])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var isEmpty: Bool { text.isEmpty }

    /// A new hypothesis for the request in flight.
    ///
    /// Usually this just replaces the tail, because a hypothesis grows as
    /// someone keeps talking. The exception is the one a cook actually hit:
    /// pause for a couple of seconds mid-list, start talking again, and
    /// everything said before the pause disappears.
    ///
    /// What happens there is that the recognizer treats the silence as the end
    /// of an utterance and begins a **new hypothesis** for what follows, without
    /// ending the request and without reporting anything final. So the next
    /// callback carries "soy sauce" where the one before carried "eggs, milk,
    /// half an onion", and mirroring it drops the lot.
    ///
    /// A hypothesis that is shorter than the one before it and does not begin
    /// the same way is therefore not a revision, it is a fresh utterance. Bank
    /// the old one before taking the new.
    mutating func updateLive(_ hypothesis: String) {
        if startsAFreshUtterance(hypothesis) { bankLive() }
        live = hypothesis
    }

    /// A revision keeps the opening; a new utterance does not.
    ///
    /// Length is not the signal, which is the first thing tried and it was
    /// wrong: "rice" followed by a pause and "chicken thighs" is longer than
    /// what came before and is still a completely different thing, so treating
    /// growth as a revision dropped every short item in a list. What actually
    /// separates the two is whether the recognizer is still building on the same
    /// words. Refining runs "eggs" → "eggs, milk" and walking a guess back runs
    /// "half an onion" → "half an"; either way one is a prefix of the other.
    ///
    /// Where this is wrong it errs toward keeping too much. A recognizer that
    /// revises the *opening* of an utterance reads as new here and the cook sees
    /// a duplicate, which is visible and one edit away. The other mistake makes
    /// their list disappear, which is the bug this file exists for.
    private func startsAFreshUtterance(_ hypothesis: String) -> Bool {
        let new = Self.comparable(hypothesis)
        let old = Self.comparable(live)
        guard !old.isEmpty, !new.isEmpty else { return false }
        return !old.hasPrefix(new) && !new.hasPrefix(old)
    }

    /// Punctuation and case move around freely between hypotheses of the same
    /// words, so neither can be part of deciding whether one continues another.
    private static func comparable(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
    }

    /// The current request is over. Keep what it heard and clear the tail so the
    /// next request starts from nothing.
    ///
    /// Ignores an empty tail, which is what a request that ended before anyone
    /// spoke returns, so banking it would pad the text with blanks.
    /// Returns whether anything was actually banked, which is how the session
    /// tells a request that did real work from one that failed instantly.
    @discardableResult
    mutating func bankLive() -> Bool {
        let trimmed = live.trimmingCharacters(in: .whitespacesAndNewlines)
        live = ""
        guard !trimmed.isEmpty else { return false }
        // A restarted request sometimes re-reports the tail of the previous one.
        // Banking it again gives the cook "half an onion half an onion".
        guard banked.last != trimmed else { return false }
        banked.append(trimmed)
        return true
    }

    mutating func reset() {
        banked = []
        live = ""
    }
}
