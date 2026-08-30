import Foundation

/// The rubric for **Claw Grip**, which is the first thing Chef watches that can
/// actually hurt somebody.
///
/// Authored from the culinary instructor deliverable in
/// `docs/skills-instructor-deliverable.md`. Two of its judgements shaped this
/// file and are worth stating plainly, because both push *against* correcting
/// people:
///
/// 1. There is no such thing as a textbook claw. Hand size, arthritis, nail
///    length and the shape of what is being cut all change it, and the only
///    thing that actually matters is that no fingertip is forward of the
///    knuckles when the blade comes down. Everything else is style.
/// 2. A flat hand is not a mistake while the knife is nowhere near it. Cooks
///    steady a big cabbage with an open palm and then re-form as the blade
///    approaches, which is correct, and an app that calls it out has told a
///    competent person they are doing it wrong.
///
/// So the safety mistakes here carry a lower confidence floor than anything
/// else in the catalog, and every one of them requires having actually seen the
/// hand. Being wrong about a fingertip costs a moment of embarrassment; being
/// silent about one costs a finger. Neither of those is a reason to guess.
extension SkillVisualCheck {

    static let knifeClawGrip = SkillVisualCheck(
        id: "knife.claw.guard",
        // Process, not outcome. Unlike every cut that follows, the finished
        // board says nothing at all about whether the hand doing it was safe.
        assessmentMode: .process,
        framingInstruction:
            "Look down at the hand holding the food, and make three slow cuts. "
            + "Keep that whole hand and the edge of the knife in view as you go.",
        photoFraming:
            "Get someone to take a photo of your guiding hand mid cut, or prop your phone where it can see your hand and the blade together.",
        setupNeeds:
            ", and have your board and knife ready.",
        viewingNote: """
        # They are moments from three cuts, not three attempts
        The images come a second or two apart while the cook was actually
        cutting, so the guiding hand is in a different place in each one. That is
        normal and it is what you are here to read.

        COMBINE them. What matters is the relationship between the fingertips of
        the guiding hand and the edge of the blade AT THE MOMENT THE BLADE IS
        CLOSE. A hand that is flat and open while the knife is at the far end of
        the board is not in danger and is not a mistake. Judge the frames where
        the blade is near the hand, and say so in your evidence.

        If the guiding hand is out of frame in every view, that is
        `cannotAssess`. Do not infer where the fingers are from the shape of the
        food or the angle of the knife. This is the one skill where a confident
        guess is worse than no answer at all.
        """,
        // Both, and only both. The whole judgement is a relationship between
        // two things, so seeing one of them is seeing nothing.
        requiredVisibility: [.guidingHand, .tool],
        helpfulVisibility: [.thumb, .ingredient, .workSurface],
        parts: [
            SkillCheckPart(region: .guidingHand, label: "Fingertips curled back behind your knuckles"),
            SkillCheckPart(region: .thumb, label: "Thumb tucked in behind your fingers"),
            SkillCheckPart(region: .tool, label: "Blade riding against your knuckles"),
            SkillCheckPart(region: .ingredient, label: "Food sitting flat and steady"),
        ],
        rubric: SkillVisualRubric(
            subject:
                "the hand a cook is using to hold food steady while they cut, seen from their "
                + "own eyes",

            targetTechnique: [
                "The guiding hand rests on top of or beside the food, never in front of where "
                    + "the blade is travelling.",
                "The fingertips are curled or otherwise drawn back so the knuckles are the part "
                    + "closest to the knife.",
                "The thumb is behind the fingers, not reaching forward alongside the food.",
                "The flat of the blade can ride against the knuckles, which is what makes the "
                    + "hand a guide rather than just an obstacle.",
                "The food is stable enough that the hand is holding it rather than chasing it.",
            ],

            acceptableVariations: [
                "The shape of the claw itself. There is no correct one. Large hands, small hands, "
                    + "arthritic knuckles, long nails and the geometry of what is being cut all "
                    + "change it, and every version is fine if the fingertips are behind the "
                    + "knuckles.",
                "Which knuckle leads. Index, middle, or several together are all used by "
                    + "competent cooks.",
                "A flatter, more open hand on a large stable item, WHILE THE BLADE IS FAR AWAY. "
                    + "Cooks steady a cabbage or a big squash with an open palm and re-form as the "
                    + "knife comes back. Do not call this wrong unless the blade is near the hand.",
                "Exactly where the thumb sits, as long as it stays behind the line the blade is "
                    + "cutting on.",
                "A compact pinch rather than a claw on something very small, like a single clove "
                    + "or a chilli, where a full claw does not fit. The test is still whether the "
                    + "fingers are clear.",
                "Left handed cooks, where the whole thing is mirrored.",
                "Slow, deliberate, obviously careful cutting. Speed is not the skill and a "
                    + "beginner working slowly is doing the right thing.",
            ],

            rankedMistakes: [
                SkillCoachableMistake(
                    key: "fingertipsAhead",
                    observation:
                        "One or more fingertips of the guiding hand project past the knuckles, "
                        + "into the path the blade is travelling on.",
                    correction:
                        "Curl those fingertips back behind your knuckles before the next cut.",
                    rationale:
                        "This is the one that actually cuts people. With the knuckles forward, "
                        + "the flat of the blade has something to ride against and physically "
                        + "cannot reach your fingertips. With a fingertip out in front, nothing "
                        + "is stopping it.",
                    severity: .safety,
                    // Lower than anything else in the catalog. Withholding this
                    // because the evidence was merely good is the wrong bet.
                    confidenceFloor: 0.45,
                    requiresVisible: [.guidingHand, .tool]
                ),
                SkillCoachableMistake(
                    key: "thumbForward",
                    observation:
                        "The thumb of the guiding hand is extended forward alongside the food, "
                        + "level with or ahead of the fingers, near the cutting line.",
                    correction:
                        "Pull your thumb back behind your fingers. It is the one I do not want "
                        + "anywhere near the blade.",
                    rationale:
                        "Almost everybody protects their four fingers and forgets the thumb, "
                        + "because it is doing the holding and it feels like it is out of the "
                        + "way. It usually is not.",
                    severity: .safety,
                    confidenceFloor: 0.45,
                    requiresVisible: [.thumb, .tool]
                ),
                SkillCoachableMistake(
                    key: "handInFrontOfBlade",
                    observation:
                        "The guiding hand is holding the food on the side the knife is moving "
                        + "toward, so the blade is travelling at the hand rather than away "
                        + "from it.",
                    correction:
                        "Move your holding hand behind the knife, not in front of where it "
                        + "is travelling.",
                    rationale:
                        "No grip on the food is safe if the blade is pointed at the hand "
                        + "holding it. Get the direction right first and the finger position "
                        + "matters much less.",
                    severity: .safety,
                    confidenceFloor: 0.45,
                    requiresVisible: [.guidingHand, .tool]
                ),
                SkillCoachableMistake(
                    key: "rollingFood",
                    observation:
                        "A round or curved ingredient is rocking or rolling under the guiding "
                        + "hand while the knife is coming down.",
                    correction:
                        "Give that a flat side first so it cannot roll under the knife.",
                    rationale:
                        "A stable ingredient does more for your safety than any hand position. "
                        + "Cutting one flat face and turning it down means the food stops "
                        + "fighting you and your hand stops having to work for it.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],

            safetySignals: [
                "A fingertip or thumb visibly on, against, or underneath the cutting edge.",
                "Food visibly rolling while the blade is descending onto it.",
                "The cook reaching to catch a falling knife.",
                "Cutting toward the palm, holding food in the air, for something that could "
                    + "be cut on the board.",
            ],

            supportedEquipment: [
                "Western chef's knife",
                "Gyuto",
                "Santoku",
                "Utility knife",
            ],

            unsupportedEquipment: [
                "Serrated bread knife",
                "Meat cleaver",
                "Mandoline",
            ],

            notVisuallyAssessable: [
                "How hard the guiding hand is gripping. A relaxed hand and a tense one look "
                    + "the same.",
                "How sharp the knife is, which changes how much force is being used and "
                    + "therefore how much control there is.",
                "Whether the board is slipping on the counter, unless it visibly moves.",
                "Anything about a finger that is behind the food, the hand or the blade.",
            ],

            confidenceFloor: 0.55,
            passSummary: "Knuckles forward, fingertips clear of the blade.",
            variationSummary:
                "Their own version of the claw, and the fingers stayed behind the knuckles.",
            audioSignals: [
                "A knife meeting the board with a clean single knock per cut, rather than "
                    + "several forced knocks, suggests the cut is going through in one pass and "
                    + "the hand is not being asked to hold against a struggling blade. Supporting "
                    + "evidence only, and never a reason to fail anybody.",
            ]
        ),
        retryFraming:
            "Keep cutting and just angle your head down a little, so I can see your other hand "
            + "and the blade at the same time."
    )
}
