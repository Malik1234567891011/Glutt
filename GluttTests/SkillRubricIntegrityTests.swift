import XCTest
@testable import Glutt

/// Rules every authored rubric has to obey, checked against the whole catalog.
///
/// These exist because the catalog is going from one visual check to sixty-odd,
/// and every one of them is prose written by hand. Prose does not fail to
/// compile. A mistake that requires seeing a region the check never asks about
/// is a correction that can never fire, and it looks completely fine in the
/// source: the only symptom is a cook who is never told the one thing they are
/// doing wrong.
///
/// Every assertion here started as a real bug in the knife grip rubric.
final class SkillRubricIntegrityTests: XCTestCase {

    private var checks: [(skill: Skill, check: SkillVisualCheck)] {
        SkillCatalog.allSkills
            .compactMap { skill in
                skill.visualCheck.map { (skill, $0) }
            }
    }

    func testTheCatalogActuallyHasWatchableSkills() {
        XCTAssertGreaterThanOrEqual(checks.count, 22, "knife and heat should both be watchable")
    }

    /// Ids end up on persisted attempt rows, so a duplicate silently merges two
    /// skills' histories.
    func testEveryCheckIdIsUnique() {
        let ids = checks.map(\.check.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate check ids: \(ids)")
    }

    /// The original bug this whole model exists because of. Requiring every
    /// region a rubric mentions meant demanding a view of both faces of a knife
    /// at once, which the world does not offer, and a correct grip came back
    /// unassessable about half the time.
    func testRequiredVisibilityStaysSmall() {
        for (skill, check) in checks {
            XCTAssertFalse(
                check.requiredVisibility.isEmpty,
                "\(skill.id) requires nothing, so it can never say it cannot see")
            XCTAssertLessThanOrEqual(
                check.requiredVisibility.count, 2,
                "\(skill.id) requires \(check.requiredVisibility.count) regions at once. "
                + "Every extra one is a view the cook has to produce before they get an answer.")
        }
    }

    /// A mistake gated on a region nobody is asked to report is a correction
    /// that can never be delivered.
    func testEveryMistakeCanActuallyFire() {
        for (skill, check) in checks {
            let reported = Set(check.reportedVisibility)
            for mistake in check.rubric.rankedMistakes {
                for region in mistake.requiresVisible {
                    XCTAssertTrue(
                        reported.contains(region),
                        "\(skill.id)/\(mistake.key) needs \(region.rawValue) visible, but the "
                        + "check never asks the model to report it, so it can never fire")
                }
            }
        }
    }

    /// Withholding a safety correction because the evidence was merely good is
    /// the wrong bet. Anything marked safety-critical has to be sayable at or
    /// below the floor everything else is held to.
    func testSafetyCorrectionsAreNotHarderToSayThanOrdinaryOnes() {
        for (skill, check) in checks {
            for mistake in check.rubric.rankedMistakes where mistake.severity == .safety {
                let floor = mistake.confidenceFloor ?? check.rubric.confidenceFloor
                XCTAssertLessThanOrEqual(
                    floor, check.rubric.confidenceFloor,
                    "\(skill.id)/\(mistake.key) is safety-critical but needs MORE confidence "
                    + "than an ordinary correction")
            }
        }
    }

    /// The sentence the whole feature is judged on. Empty or vague ones are how
    /// this turns back into advice from a webpage.
    func testEveryCorrectionIsARealSpokenInstruction() {
        for (skill, check) in checks {
            for mistake in check.rubric.rankedMistakes {
                XCTAssertGreaterThan(
                    mistake.correction.count, 25,
                    "\(skill.id)/\(mistake.key) correction is too short to be an instruction")
                XCTAssertFalse(
                    mistake.observation.isEmpty,
                    "\(skill.id)/\(mistake.key) has no observation, so the model cannot name it")
                XCTAssertFalse(
                    mistake.rationale.isEmpty,
                    "\(skill.id)/\(mistake.key) has no rationale to give if the cook asks why")
            }
        }
    }

    /// Repo rule, and it applies here more than anywhere: these strings are
    /// spoken out loud. See `.claude/rules/ui-copy.md`.
    func testNoDashesAsPunctuationInAnythingChefSays() {
        for (skill, check) in checks {
            var spoken = [check.framingInstruction, check.retryFraming]
            spoken.append(contentsOf: check.rubric.rankedMistakes.map(\.correction))
            spoken.append(contentsOf: check.rubric.rankedMistakes.map(\.rationale))
            spoken.append(contentsOf: check.parts.map(\.label))
            if let outcome = check.outcomeFraming { spoken.append(outcome) }
            if let branch = check.rubric.intentBranch { spoken.append(branch.question) }

            for line in spoken {
                XCTAssertFalse(line.contains("—"), "em dash in \(skill.id): \(line)")
                XCTAssertFalse(line.contains("–"), "en dash in \(skill.id): \(line)")
                XCTAssertFalse(line.contains(" - "), "spaced hyphen in \(skill.id): \(line)")
            }
        }
    }

    /// The list that stops this being a pose classifier. A rubric with no
    /// acceptable variations will fail somebody for having small hands.
    func testEveryRubricNamesThingsThatAreNotMistakes() {
        for (skill, check) in checks {
            XCTAssertGreaterThanOrEqual(
                check.rubric.acceptableVariations.count, 3,
                "\(skill.id) lists fewer than three acceptable variations, which means it is "
                + "about to correct people for cooking differently rather than wrongly")
        }
    }

    /// Parts drive a card the cook reads while holding a knife. Duplicate ids
    /// collapse rows in the UI.
    func testPartIdsAreUniqueWithinASkill() {
        for (skill, check) in checks {
            let ids = check.parts.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "duplicate part ids in \(skill.id): \(ids)")
        }
    }

    /// Skills judged on what they produced need the sentence that gets the
    /// finished thing into shot. "Turn your hand slowly" is the wrong request
    /// for a board of diced onion.
    func testOutcomeSkillsSayHowToShowTheResult() {
        for (skill, check) in checks
        where check.assessmentMode == .outcome || check.assessmentMode == .processThenOutcome {
            XCTAssertNotNil(
                check.outcomeFraming,
                "\(skill.id) is judged on its outcome but never says how to show it")
            XCTAssertFalse(
                check.rubric.outcomeTolerance.isEmpty,
                "\(skill.id) is judged on its outcome with no stated tolerance, so it will be "
                + "held to whatever the model imagines a professional standard is")
        }
    }

    /// Every skill that can be watched must also say what it cannot see. This is
    /// the field that keeps Chef honest about grip pressure, sharpness and taste.
    func testEveryRubricAdmitsWhatItCannotSee() {
        for (skill, check) in checks {
            XCTAssertFalse(
                check.rubric.notVisuallyAssessable.isEmpty,
                "\(skill.id) claims it can see everything about the technique")
        }
    }

    /// The lesson screen tells a cook what to pick up before they start. It used
    /// to say "pick up your knife" to everybody, including on the searing
    /// lesson, because it was written when one skill existed.
    func testEverySkillSaysWhatToHaveReady() {
        let placeholder = " and get set up."
        for (skill, check) in checks {
            XCTAssertNotEqual(
                check.setupNeeds, placeholder,
                "\(skill.id) never says what to have ready, so the lesson screen falls back "
                + "to generic copy")
            XCTAssertTrue(
                check.setupNeeds.hasSuffix("."),
                "\(skill.id) prep line is not a sentence: \(check.setupNeeds)")
            XCTAssertFalse(check.setupNeeds.contains("—"), "em dash in \(skill.id)")
            XCTAssertFalse(check.setupNeeds.contains(" - "), "spaced hyphen in \(skill.id)")

            // Stored as a tail so the opener can vary by mode. A tail that does
            // not start with its own separator composes into a run on sentence.
            XCTAssertTrue(
                check.setupNeeds.hasPrefix(" ") || check.setupNeeds.hasPrefix(","),
                "\(skill.id) setupNeeds must begin with its separator: \(check.setupNeeds)")

            for mode in SkillLearningMode.allCases {
                let line = check.setupLine(for: mode)
                XCTAssertFalse(
                    line.contains("  "), "\(skill.id) composes a double space in \(mode)")
                XCTAssertTrue(line.hasSuffix("."), "\(skill.id) composes badly in \(mode)")
            }
        }
    }

    /// A cook holding the phone cannot be told to look down at their own hand.
    /// Where the two modes genuinely differ, the rubric has to say both.
    func testProcessSkillsThatNeedADifferentPhotoFramingHaveOne() {
        for (skill, check) in checks where check.photoFraming != nil {
            let photo = check.photoFraming!
            XCTAssertNotEqual(
                photo, check.framingInstruction,
                "\(skill.id) authors a photo framing identical to the live one")
            XCTAssertFalse(photo.contains("—"), "em dash in \(skill.id)")
            XCTAssertFalse(photo.contains(" - "), "spaced hyphen in \(skill.id)")
            XCTAssertGreaterThan(photo.count, 25, "\(skill.id) photo framing is too terse")
        }
    }

    /// Two deliberate photographs, not three grudging ones. Asking for more
    /// than a cook can take with a knife in one hand is how this mode gets
    /// abandoned halfway through.
    func testNobodyIsAskedForTooManyPhotos() {
        for (skill, check) in checks {
            XCTAssertGreaterThanOrEqual(check.photosNeeded, 1, "\(skill.id) asks for none")
            XCTAssertLessThanOrEqual(
                check.photosNeeded, 3,
                "\(skill.id) asks for \(check.photosNeeded) photos, which is a chore")
        }
    }

    /// A demonstration clip that is not in the bundle fails silently: the player
    /// asserts in debug and renders an empty frame in release, so a typo in the
    /// asset name would ship as a blank card above the lesson.
    func testEveryDemonstrationClipIsActuallyBundled() {
        let named = SkillCatalog.allSkills.compactMap { skill -> (String, String)? in
            skill.animationAsset.map { (skill.id, $0) }
        }
        XCTAssertFalse(named.isEmpty, "no skill has a demonstration clip any more")

        for (skillID, asset) in named {
            let url = Bundle(for: Self.self).url(forResource: asset, withExtension: "mp4")
                ?? Bundle.main.url(forResource: asset, withExtension: "mp4")
            XCTAssertNotNil(url, "\(skillID) names \(asset).mp4, which is not in the bundle")
        }
    }

    /// The clips are shipped inside the app, so every one of them is paid for
    /// by every download whether it is watched or not.
    func testDemonstrationClipsStayASensibleSize() throws {
        for skill in SkillCatalog.allSkills {
            guard let asset = skill.animationAsset else { continue }
            let url = Bundle(for: Self.self).url(forResource: asset, withExtension: "mp4")
                ?? Bundle.main.url(forResource: asset, withExtension: "mp4")
            guard let url else { continue }
            let bytes = try Data(contentsOf: url).count
            XCTAssertLessThan(
                bytes, 2_000_000,
                "\(asset).mp4 is \(bytes / 1024)KB. Re-encode it before shipping it.")
        }
    }

    /// A watchable skill with no lesson is a check with nothing to teach before
    /// it runs.
    func testEveryWatchableSkillHasBeenWritten() {
        for (skill, _) in checks {
            XCTAssertNotNil(skill.lesson, "\(skill.id) can be watched but has no lesson")
        }
    }
}
