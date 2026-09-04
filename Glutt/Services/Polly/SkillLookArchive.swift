import Foundation
import UIKit

/// Every frame a skill check actually looked at, written to disk with the
/// answer it produced.
///
/// Built for one specific argument that cannot otherwise be settled: Chef
/// reports that she cannot see a thumb while reporting that she CAN see the
/// fingers wrapped round the handle. From a cook's own eyes that is close to
/// impossible, because the thumb sits on the near face of the blade and the
/// wrapped fingers are further away and more occluded. Either the frames really
/// are that bad, or the model is over-reporting `insufficient` and we have been
/// blaming the camera for a prompt problem.
///
/// Nobody can settle that by reading a log line saying `thumb: insufficient`.
/// You have to look at the picture the model looked at. So this writes them out
/// next to the JSON it returned, and a whole session can be pulled off the
/// phone in one command:
///
///     xcrun devicectl device copy from --device <udid> \
///       --domain-type appDataContainer \
///       --domain-identifier com.omarlahmimi.glutt \
///       --source Documents/SkillLooks --destination ./looks
///
/// **Debug builds only.** Every call site is inside `#if DEBUG`, and writing a
/// cook's kitchen to disk in a shipping app would be indefensible.
#if DEBUG
/// Why this look happened, which decides whether a failed one is a bug.
///
/// A lesson starts looking the moment the cook says something that sounds like
/// "does this look right", without waiting for Chef to decide to call the tool.
/// When she then says something conversational instead, that speculative look is
/// thrown away and its request is cancelled. That cancellation is correct
/// behaviour and the cook never sees it, but in the archive it is
/// indistinguishable from a look the cook was actually waiting on: both land as
/// `NSURLErrorDomain Code=-999 "cancelled"`. Four of eight checks in one session
/// read as failures for this reason, which made the feature look far more broken
/// than it was.
enum SkillLookOrigin: String {
    case speculative = "started early, before she called for it"
    case requested = "she called for it"
}

enum SkillLookArchive {

    /// Task-local so nothing has to thread it through `deps.assess`, and so it
    /// follows the assessment into whatever child task does the request.
    @TaskLocal static var origin: SkillLookOrigin = .requested

    /// `Documents/SkillLooks`, which is what `appDataContainer` exposes.
    private static var root: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SkillLooks", isDirectory: true)
    }

    /// Sortable, and legible enough to match against a debug log line.
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.timeZone = .current
        return f
    }()

    /// Write one look: the frames as sent, and the assessment as returned.
    ///
    /// Frames are written in the order the assessor received them, and the
    /// filenames say so, because "view 1 of 3, most recent" is the sentence in
    /// the prompt and the whole point is to check it against the pixels.
    static func save(
        frames: [Data],
        check: SkillVisualCheck,
        assessment: SkillVisualAssessment?,
        error: String? = nil,
        handCoverage: Double? = nil,
        originals: [Data] = [],
        at date: Date = .now
    ) {
        guard let root else { return }
        let folder = root.appendingPathComponent(
            "\(stamp.string(from: date))-\(check.id)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true)

            for (index, jpeg) in frames.enumerated() {
                let label = index == 0 ? "most-recent" : "earlier-\(index)"
                try jpeg.write(to: folder.appendingPathComponent(
                    "view-\(index + 1)-\(label).jpg"))
            }

            // The uncropped frames too. Saving only what was sent meant the
            // crop could not be retuned without asking for another test round,
            // and the crop turned out to be the thing that needed retuning.
            for (index, jpeg) in originals.enumerated() {
                try jpeg.write(to: folder.appendingPathComponent(
                    "original-\(index + 1).jpg"))
            }

            let summary = report(
                frames: frames, check: check, assessment: assessment,
                error: error, handCoverage: handCoverage)
            try Data(summary.utf8).write(
                to: folder.appendingPathComponent("verdict.txt"))

            PollyDebugLog.shared.log("skill: archived this look to \(folder.lastPathComponent)")
        } catch {
            PollyDebugLog.shared.log("skill: could not archive the look — \(error)")
        }
    }

    /// Written for a person reading it beside the images, not for a parser.
    ///
    /// It leads with the visibility table because that is the disputed part.
    /// Anybody checking this opens the jpgs, looks at the hand, then reads down
    /// this list asking "is that true?", and the answer should be obvious
    /// within a couple of seconds either way.
    private static func report(
        frames: [Data],
        check: SkillVisualCheck,
        assessment: SkillVisualAssessment?,
        error: String?,
        handCoverage: Double?
    ) -> String {
        var out = ["\(check.id)", ""]

        out.append("origin: \(origin.rawValue)")
        out.append("frames sent: \(frames.count)")
        for (index, jpeg) in frames.enumerated() {
            let size = UIImage(data: jpeg).map { "\(Int($0.size.width))x\(Int($0.size.height))" }
                ?? "undecodable"
            out.append("  view \(index + 1): \(size), \(jpeg.count / 1024)KB")
        }
        if let handCoverage {
            out.append(String(format: "hand found, %.1f%% of the frame", handCoverage * 100))
            out.append(handCoverage < SkillFrameFocus.tooFarToJudge
                ? "  TOO FAR to judge. Cropping cannot recover this."
                : "  cropped to the hand before sending")
        } else {
            out.append("no hand detected, whole frame sent")
        }
        out.append("")

        guard let assessment else {
            out.append("NO ASSESSMENT: \(error ?? "unknown failure")")
            if origin == .speculative, error?.contains("-999") == true {
                out.append("")
                out.append("NOT A BUG. This look was started early on the chance the cook")
                out.append("wanted one, she went on talking instead, and it was thrown away.")
                out.append("The cook saw nothing and waited for nothing.")
            }
            return out.joined(separator: "\n")
        }

        out.append("what she said she could see")
        out.append("  (open the jpgs and check each of these yourself)")
        for region in check.reportedVisibility {
            let seen = assessment.visibility[region.rawValue]
            let required = check.requiredVisibility.contains(region) ? "  [required]" : ""
            out.append("  \(region.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0))"
                + "\(seen?.rawValue ?? "not reported")\(required)")
        }
        out.append("")

        out.append("verdict")
        out.append("  overall      \(assessment.overall.rawValue)")
        out.append("  confidence   \(String(format: "%.2f", assessment.confidence))")
        out.append("  issue        \(assessment.primaryIssueKey ?? "none")")
        out.append("  equipment    \(assessment.equipment.reading)"
            + " (supported: \(assessment.equipment.supported))")
        if assessment.safety.immediateConcern {
            out.append("  SAFETY       \(assessment.safety.description ?? "unspecified")")
        }
        out.append("")

        if !check.observations.isEmpty {
            out.append("where she placed each part, picture by picture")
            out.append("  (this is the reading the correction is now gated on)")
            for observation in check.observations {
                let perPicture = assessment.observations.enumerated().map { index, reading in
                    "\(index + 1):\(reading[observation.id] ?? "-")"
                }.joined(separator: "  ")
                let agreed = assessment.reading(for: observation) ?? "NO MAJORITY"
                out.append("  \(observation.id.padding(toLength: 14, withPad: " ", startingAt: 0))"
                    + "\(perPicture.isEmpty ? "nothing reported" : perPicture)  ->  \(agreed)")
            }
            out.append("")
        }

        out.append("what she claims she actually saw")
        for line in assessment.observedEvidence {
            out.append("  - \(line)")
        }
        out.append("")

        out.append("decision layer said")
        out.append("  \(String(describing: SkillCoachDecision.decide(assessment, check: check)))")

        return out.joined(separator: "\n")
    }

    /// Wipe the archive, so a test session is not read against yesterday's.
    static func clear() {
        guard let root else { return }
        try? FileManager.default.removeItem(at: root)
    }
}
#endif
