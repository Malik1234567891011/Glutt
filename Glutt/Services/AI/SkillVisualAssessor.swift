import Foundation

/// Looking at what the cook is actually doing, and saying only what is
/// supported by the picture.
///
/// The division of labour here is the whole design. The model is asked to
/// **observe**: what tool is this, which fingers can I see, where are they, is
/// anything dangerous. The app decides what that **means** and what to say about
/// it, using the rubric the skill was authored with. So the model never invents
/// coaching, never ranks its own criticisms, and never gets to be confident on
/// our behalf.
///
/// That split is not fussiness. A model asked "is this grip correct?" will
/// answer the question every time, including when the thumb is behind the
/// handle and it cannot see it, and the resulting sentence is indistinguishable
/// from a real observation. One confidently wrong correction costs more trust
/// than ten missed ones.
enum SkillVisualAssessor {

    /// Tags the proxy's `ai_usage` row. Its own feature because this is the
    /// expensive surface: several images per attempt, and several attempts per
    /// lesson.
    static let usageFeature = "skill_visual_check"

    enum AssessorError: Error {
        case noUsableFrames
    }

    /// Assess a held pose from the frames captured during the hold.
    ///
    /// Frames are sent as separate user messages because `LLMClient.Message`
    /// carries one image each. Several views of a mostly static hand is the
    /// point: one blurred or occluded instant then costs a frame rather than
    /// the answer.
    static func assess(
        check: SkillVisualCheck,
        frames: [Data],
        client: LLMClient = .live
    ) async throws -> SkillVisualAssessment {
        // Crop to the hand FIRST, then downscale. The other order throws away
        // the pixels that decide the verdict and then enlarges what is left.
        //
        // This is here rather than in the frame ring because it is about what
        // the model needs, not about what the camera produced, and because a
        // frame kept for the archive should be the one that was actually sent.
        // One crop per hand, newest frame first, capped at the frame budget.
        // Two hands in the newest frame beats one hand in each of three, because
        // the question is which hand rather than which moment.
        let focused = Array(frames.flatMap(SkillFrameFocus.focusOnHands).prefix(check.framesPerLook))
        let usable = focused.compactMap { ImagePrep.prepareForVision($0.jpeg) }
        guard !usable.isEmpty else { throw AssessorError.noUsableFrames }

        // Refuse rather than answer badly.
        //
        // When a hand was found in every frame and was tiny in all of them, the
        // model will still return a verdict, and it will be a guess. On the run
        // that produced this check it guessed `handleGrip` on a grip whose thumb
        // was on the blade. Asking them to bring their hand up is both more
        // honest and more useful than a confident wrong correction.
        let seen = focused.compactMap(\.coverage)
        if !seen.isEmpty, seen.allSatisfy({ $0 < SkillFrameFocus.tooFarToJudge }) {
            let best = seen.max() ?? 0
            PollyDebugLog.shared.log(
                "skill: hand is only \(String(format: "%.1f", best * 100))% of the frame, too far to judge")
            throw VisualFrameRejection.subjectTooFar
        }

        var messages: [LLMClient.Message] = [.system(systemPrompt(check: check))]
        for (index, jpeg) in usable.enumerated() {
            messages.append(.user(
                "View \(index + 1) of \(usable.count) of the same grip, "
                    + (index == 0 ? "most recent." : "a moment earlier."),
                imageData: jpeg))
        }
        messages.append(.user(userPrompt(check: check)))

        do {
            let answer = try await client.chatJSON(
                SkillVisualAssessment.self,
                messages: messages,
                temperature: 0.1,
                feature: usageFeature,
                timeout: 45
            )
            // Archived AFTER the answer so the pictures and the verdict land in
            // one folder. `usable` rather than `frames`: these are the bytes the
            // model actually received, downscaled and recompressed, and judging
            // its eyesight against the originals would be judging the wrong
            // images.
#if DEBUG
            SkillLookArchive.save(
                frames: usable, check: check, assessment: answer,
                handCoverage: focused.compactMap(\.coverage).max(),
                originals: frames)
#endif
            return answer
        } catch {
#if DEBUG
            // A failed look is worth keeping too. Half the arguments about what
            // she can see turn out to be about a request that never landed.
            SkillLookArchive.save(
                frames: usable, check: check, assessment: nil,
                error: String(describing: error),
                handCoverage: focused.compactMap(\.coverage).max(),
                originals: frames)
#endif
            throw error
        }
    }

    // MARK: - Prompt

    /// Built from the rubric rather than written here, so authoring a new
    /// physical skill never means editing this file.
    static func systemPrompt(check: SkillVisualCheck) -> String {
        let r = check.rubric
        return """
        You are helping a cooking instructor evaluate \(r.subject). The images are
        first person, taken from the cook's own point of view a second or two
        apart.

        \(viewingGuidance(check))

        # The technique being taught
        \(bullets(r.targetTechnique))\(intentSection(r))\(toleranceSection(r))\(audioSection(r))

        # Differences that are NOT mistakes
        Do not report these as problems. A cook whose hand differs from the reference
        in one of these ways is holding the knife correctly.
        \(bullets(r.acceptableVariations))

        # Habits worth naming, if you can actually see them
        Report at most ONE of these, as `primaryIssueKey`, using the key exactly as
        written. They are listed **most costly first**: anything unsafe, then
        anything that will ruin the food in the next few seconds, then whatever
        most affects the result. When several are true, name the one highest in
        this list, not the one easiest to see. If none apply, return null.
        \(r.coachingOrder.map { "- `\($0.key)`: \($0.observation)" }.joined(separator: "\n"))

        # Stop the lesson for these
        \(bullets(r.safetySignals))
        Only report a safety concern you can see. A finger you cannot find is not a
        finger in a dangerous place.

        # Equipment this lesson is for
        \(bullets(r.supportedEquipment))
        If the tool is clearly one of these instead, set `overall` to
        `unsupportedEquipment` and name it. Do not coach a grip for a knife this
        lesson was not written for.
        \(bullets(r.unsupportedEquipment))

        # Things you cannot determine from an image
        Never claim any of these. If asked to judge one, say you cannot see it.
        \(bullets(r.notVisuallyAssessable))

        # You may be shown a hand that has nothing to do with this
        The pictures are cropped to each hand found in the shot, one hand per
        picture, and a cook often has two: one holding the thing you are here to
        judge and one holding their phone, a cloth, or nothing at all. So expect
        pictures that are not relevant, and judge the hand that is holding the
        tool.

        If NONE of the pictures contains the tool, say so. Set `tool` visibility
        to `insufficient`, set `overall` to `cannotAssess`, and put what you
        actually saw in `observedEvidence`, for example "a hand holding a phone".
        Do not describe a grip on a tool that is not in the picture.
        Never say the equipment is supported when you cannot see the equipment.

        That has happened. Three pictures of a hand holding a phone came back as
        "a chef's knife" with "the whole hand is behind the blade on the
        handle", which is an invented observation of an object that was not
        there, and it is worse than any wrong correction because nothing
        downstream can catch it.

        # How to answer
        1. FIRST decide whether you can see enough. Report visibility per region
           honestly. A region hidden behind something, or out of frame, is
           `insufficient`, not `partial`.
           Some hiding is NORMAL and is not a problem to report. These images come
           from the cook's own eyes while they work, so parts of the scene pass
           behind hands, tools and pans constantly. Mark what you cannot see
           `insufficient` and carry on assessing everything you CAN see.
        2. `cannotAssess` is ONLY for when \(requiredList(check)) is not visible.
           Nothing else earns it. If those are visible, assess, and keep assessing
           even when every other region is hidden. Answering `cannotAssess` because
           one optional region is obscured tells a cook who is looking straight at
           their own work that you cannot see it, which is the fastest way to lose
           them.
           What you must not do is guess. Do not report a habit about a region you
           marked `insufficient`: if you cannot see it, you cannot know what it is
           doing, so leave `primaryIssueKey` null and let the visibility field say
           why. Not seeing something and it being wrong are different answers and
           the app says different words for each.
        3. Separate what you SAW from what you CONCLUDE. `observedEvidence` is a
           short list of plain physical observations, each one something another
           person could verify from the same image. Your conclusions belong in the
           other fields.
        4. Be conservative. A false correction is worse than a missed one: it makes
           a cook distrust everything else you say. When two readings are possible,
           report the lower confidence.
        5. Confidence is your own, from 0 to 1, for the assessment as a whole.
           Below \(String(format: "%.2f", r.confidenceFloor)) the app will not repeat
           any criticism to the cook, so there is no cost to being honest.

        Reply with JSON only, no prose around it, in exactly this shape:
        \(schema(check: check))
        """
    }

    static func userPrompt(check: SkillVisualCheck) -> String {
        let regions = check.reportedVisibility.map(\.rawValue).joined(separator: ", ")
        let subject = switch check.assessmentMode {
        case .outcome: "the finished result shown"
        default: "the single attempt shown"
        }
        return """
        Assess \(subject) across the images above, using all of them together.
        Report visibility for: \(regions), taking the best view of each.
        Answer with the JSON object only.
        """
    }

    /// How to read this particular set of images, which depends entirely on
    /// whether they are angles on one moving thing or looks at a finished one.
    private static func viewingGuidance(_ check: SkillVisualCheck) -> String {
        if let note = check.viewingNote { return note }
        switch check.assessmentMode {
        case .outcome:
            return """
            # Views of a finished result
            These show something the cook has already produced, spread out to be
            looked at. Judge it as a whole: the spread of sizes across the batch,
            not the single best or single worst piece. A few outliers in an
            otherwise even batch are normal food, not a failure.
            """
        case .process, .processThenOutcome, .dialogue:
            return """
            # They are angles, not attempts
            The images are moments from one continuous attempt, taken while the
            cook's hands were moving. COMBINE them into a single assessment. If
            something is clearly visible in ANY view, you have seen it, and its
            visibility is whatever the BEST view showed, not the worst. Do not
            assess each image separately, and do not report a region as hidden
            because it happened to be hidden in the most recent one.

            Things will be at different angles in each view. That is the point,
            not an inconsistency to flag.
            """
        }
    }

    /// The fork the cook has already resolved out loud, so the model judges the
    /// style they are actually cooking rather than the one the book prefers.
    private static func intentSection(_ r: SkillVisualRubric) -> String {
        guard let branch = r.intentBranch else { return "" }
        let options = branch.options
            .map { "- `\($0.key)` (\($0.spokenLabel)): \($0.judgeAgainst)" }
            .joined(separator: "\n")
        return """


        # This technique has more than one correct version
        The cook has been asked: "\(branch.question)". Judge against the branch
        they chose, and against `\(branch.defaultKey)` if they did not choose.
        Never mark one branch wrong for not being another.
        \(options)
        """
    }

    private static func toleranceSection(_ r: SkillVisualRubric) -> String {
        guard !r.outcomeTolerance.isEmpty else { return "" }
        return """


        # How close is close enough
        These are the tolerances a home cook is held to, which are looser than a
        professional exercise on purpose. Judge against these, not against a
        culinary school standard.
        \(bullets(r.outcomeTolerance))
        """
    }

    private static func audioSection(_ r: SkillVisualRubric) -> String {
        guard !r.audioSignals.isEmpty else { return "" }
        return """


        # Sound, if it is mentioned to you
        You are given images, not audio. These are listed only so you know what
        the cook may describe. Never infer them from a picture.
        \(bullets(r.audioSignals))
        """
    }

    /// The regions that actually gate an assessment, named in the prompt so the
    /// model is not left inferring which ones matter.
    private static func requiredList(_ check: SkillVisualCheck) -> String {
        let names = check.requiredVisibility.map { "`\($0.rawValue)`" }
        guard let last = names.last else { return "nothing" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " or " + last
    }

    private static func bullets(_ lines: [String]) -> String {
        lines.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func schema(check: SkillVisualCheck) -> String {
        let regions = check.reportedVisibility
            .map { "\"\($0.rawValue)\": \"sufficient | partial | insufficient\"" }
            .joined(separator: ",\n            ")
        let criteria = check.rubric.coachingOrder
            .map { "\"\($0.key)\"" }
            .joined(separator: " | ")
        return """
        {
          "equipment": {
            "reading": "what tool you believe this is, in plain words",
            "supported": true,
            "confidence": 0.0
          },
          "handedness": "left | right | unknown",
          "visibility": {
            \(regions)
          },
          "safety": {
            "immediateConcern": false,
            "description": "null, or what you can see that is dangerous",
            "confidence": 0.0
          },
          "techniqueFamily": "a short plain label for the style you saw, or unknown",
          "overall": "ready | acceptableVariation | needsAdjustment | cannotAssess | unsupportedEquipment",
          "confidence": 0.0,
          "primaryIssueKey": "null, or one of: \(criteria)",
          "observedEvidence": ["short plain observations, two to five of them"]
        }
        """
    }
}

// MARK: - The answer

/// What the model saw. Deliberately close to the wire: interpretation happens
/// in `SkillCoachDecision`, not here.
struct SkillVisualAssessment: Decodable, Sendable, Equatable {

    struct Equipment: Decodable, Sendable, Equatable {
        let reading: String
        let supported: Bool
        let confidence: Double
    }

    struct Safety: Decodable, Sendable, Equatable {
        let immediateConcern: Bool
        let description: String?
        let confidence: Double
    }

    enum Visibility: String, Decodable, Sendable {
        case sufficient
        case partial
        case insufficient

        /// Enough to judge on. `partial` counts: a thumb seen at an angle is
        /// still a thumb we can place, and demanding perfect views would send
        /// every real cook round the retry loop forever.
        var isUsable: Bool { self != .insufficient }
    }

    enum Overall: String, Decodable, Sendable {
        case ready
        case acceptableVariation
        case needsAdjustment
        case cannotAssess
        case unsupportedEquipment
    }

    let equipment: Equipment
    let handedness: String?
    let visibility: [String: Visibility]
    let safety: Safety
    let techniqueFamily: String?
    let overall: Overall
    let confidence: Double
    let primaryIssueKey: String?
    let observedEvidence: [String]

    // Tolerant decoding: a model that omits an optional field should not fail
    // the whole assessment, because the app can say "I could not see" perfectly
    // well from a partial answer and cannot say anything at all from a throw.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        equipment = try c.decodeIfPresent(Equipment.self, forKey: .equipment)
            ?? Equipment(reading: "unknown", supported: true, confidence: 0)
        handedness = try c.decodeIfPresent(String.self, forKey: .handedness)
        visibility = try c.decodeIfPresent([String: Visibility].self, forKey: .visibility) ?? [:]
        safety = try c.decodeIfPresent(Safety.self, forKey: .safety)
            ?? Safety(immediateConcern: false, description: nil, confidence: 0)
        techniqueFamily = try c.decodeIfPresent(String.self, forKey: .techniqueFamily)
        overall = try c.decodeIfPresent(Overall.self, forKey: .overall) ?? .cannotAssess
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        // "null" arrives as a real string often enough to be worth handling.
        let key = try c.decodeIfPresent(String.self, forKey: .primaryIssueKey)
        primaryIssueKey = (key == "null" || key?.isEmpty == true) ? nil : key
        observedEvidence = try c.decodeIfPresent([String].self, forKey: .observedEvidence) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case equipment, handedness, visibility, safety, techniqueFamily
        case overall, confidence, primaryIssueKey, observedEvidence
    }

    /// Test seam.
    init(
        equipment: Equipment,
        handedness: String? = nil,
        visibility: [String: Visibility] = [:],
        safety: Safety = Safety(immediateConcern: false, description: nil, confidence: 0),
        techniqueFamily: String? = nil,
        overall: Overall,
        confidence: Double,
        primaryIssueKey: String? = nil,
        observedEvidence: [String] = []
    ) {
        self.equipment = equipment
        self.handedness = handedness
        self.visibility = visibility
        self.safety = safety
        self.techniqueFamily = techniqueFamily
        self.overall = overall
        self.confidence = confidence
        self.primaryIssueKey = primaryIssueKey
        self.observedEvidence = observedEvidence
    }

    /// Whether every region the check needs came back usable.
    func sawEnough(for check: SkillVisualCheck) -> Bool {
        check.requiredVisibility.allSatisfy { visibility[$0.rawValue]?.isUsable ?? false }
    }

    /// The regions we could not see, in the order the check lists them, so the
    /// cook is asked about the most important one first.
    func unseenRegions(for check: SkillVisualCheck) -> [SkillVisibilityRegion] {
        check.reportedVisibility.filter { visibility[$0.rawValue]?.isUsable != true }
    }
}
