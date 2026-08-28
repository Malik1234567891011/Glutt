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
        let usable = frames.compactMap { ImagePrep.prepareForVision($0) }
        guard !usable.isEmpty else { throw AssessorError.noUsableFrames }

        var messages: [LLMClient.Message] = [.system(systemPrompt(check: check))]
        for (index, jpeg) in usable.enumerated() {
            messages.append(.user(
                "View \(index + 1) of \(usable.count), taken during the same hold.",
                imageData: jpeg))
        }
        messages.append(.user(userPrompt(check: check)))

        return try await client.chatJSON(
            SkillVisualAssessment.self,
            messages: messages,
            temperature: 0.1,
            feature: usageFeature,
            timeout: 45
        )
    }

    // MARK: - Prompt

    /// Built from the rubric rather than written here, so authoring a new
    /// physical skill never means editing this file.
    static func systemPrompt(check: SkillVisualCheck) -> String {
        let r = check.rubric
        return """
        You are helping a cooking instructor evaluate \(r.subject). The images are
        first person, taken from the cook's own point of view during a single five
        second hold, so they are several views of one mostly static pose.

        # The technique being taught
        \(bullets(r.targetTechnique))

        # Differences that are NOT mistakes
        Do not report these as problems. A cook whose hand differs from the reference
        in one of these ways is holding the knife correctly.
        \(bullets(r.acceptableVariations))

        # Habits worth naming, if you can actually see them
        Report at most ONE of these, as `primaryIssueKey`, using the key exactly as
        written. Choose the one that costs the cook the most control. If none apply,
        return null.
        \(r.rankedMistakes.map { "- `\($0.key)`: \($0.observation)" }.joined(separator: "\n"))

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

        # How to answer
        1. FIRST decide whether you can see enough. Report visibility per region
           honestly. A region hidden behind the blade, the handle or another finger
           is `insufficient`, not `partial`.
           Hiding is NORMAL and is not a problem to report. These images are taken
           from the cook's own eyes, and in a correct pinch grip the thumb and the
           index finger are on opposite faces of the blade, so one of them is behind
           the steel by definition. Mark the hidden one `insufficient` and carry on
           assessing everything you CAN see. Only `tool` and `controlPoint`, which is
           where the hand meets the blade, have to be visible for the assessment to
           be worth anything.
        2. If the regions needed to judge the technique are not visible, set
           `overall` to `cannotAssess` and stop. Do not guess at a finger you cannot
           see, and do not soften a guess into a suggestion. Not seeing something is
           a different answer from it being wrong, and the app says different words
           for each.
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
        return """
        Assess the hold shown in the images above. Report visibility for: \(regions).
        Answer with the JSON object only.
        """
    }

    private static func bullets(_ lines: [String]) -> String {
        lines.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func schema(check: SkillVisualCheck) -> String {
        let regions = check.reportedVisibility
            .map { "\"\($0.rawValue)\": \"sufficient | partial | insufficient\"" }
            .joined(separator: ",\n            ")
        let criteria = check.rubric.rankedMistakes
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
          "techniqueFamily": "classicPinch | pinchVariation | bolsterGrip | handleGrip | pointerGrip | unknown",
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
