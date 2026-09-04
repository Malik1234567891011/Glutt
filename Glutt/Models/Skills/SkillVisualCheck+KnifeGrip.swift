import Foundation

/// The rubric for **Hold a Chef's Knife**, which is the first thing Polly ever
/// watches somebody do.
///
/// Almost all of the intelligence in this feature is here rather than in code.
/// The vision model is capable of describing a hand on a knife; what it does not
/// know is which differences are mistakes, which are just hands, and which
/// belong to a lesson we are not teaching today. That judgement is culinary, it
/// is ours to make, and it is written down so it can be argued with.
///
/// The bar it is written against: a cook should be able to hold the knife the
/// way their grandmother taught them and be told it is fine, and be told the one
/// thing that is actually costing them control when it is not.
extension SkillVisualCheck {

    static let chefKnifeGrip = SkillVisualCheck(
        id: "knife.grip.pinch",
        assessmentMode: .process,
        // Rewritten after the archive showed the old one causing the failures it
        // was supposed to prevent.
        //
        // It used to say "rest the blade on your board, look down at your hand".
        // On a head mounted camera that is the worst thing a cook can do: the
        // knife ends up at counter level, at arm's length, low in the frame and
        // often behind whichever hand happens to be nearer. Measured across the
        // archive, the knife hand came out between 0.9 and 5.3 per cent of the
        // picture, and every look that passed had it held up and central.
        //
        // So the instruction now asks for the thing that works. This is not the
        // cook compensating for a weak system, it is the system stating a real
        // constraint plainly, the way every document scanner and barcode reader
        // does.
        framingInstruction:
            "Hold the knife up in front of you, about chest height, and look at YOUR HAND "
            + "rather than at the tip. Then turn your hand slowly, like you are showing me "
            + "both sides of the blade.",
        // The clearest case in the catalog for why photo mode is a different
        // lesson rather than a worse camera. Wearing glasses, a cook can never
        // see both faces of their own blade, so the live instruction is a plea
        // to keep turning and hope. Holding a phone they simply take one
        // picture of each side, which is the whole problem solved.
        photoFraming:
            "Hold the grip, and take one photo of the thumb side of the blade. Then, without "
            + "changing your hand at all, take one of the other side.",
        setupNeeds:
            " and pick up your knife.",
        viewingNote: """
        # They are angles, not attempts
        This is the most important thing about them. Nobody can see both faces of
        a knife at once: the thumb rests on one side of the blade and the curled
        index finger on the other, so any single instant hides one of them behind
        the steel. That is why you are given several.

        COMBINE them into one assessment of one grip. If a finger is clearly
        visible in ANY view, you have seen that finger, and its visibility is
        whatever the BEST view showed, not the worst. Judge the grip on
        everything the views show between them. Do not assess each image
        separately and do not report a region as hidden because it was hidden in
        the most recent one.

        The hand may be at a different angle in each view. That is the point, not
        an inconsistency to flag.

        A hidden finger here is a normal first person view of a CORRECT grip, not
        a failed photograph. Only the knife and where the hand meets it have to
        be visible for the assessment to be worth anything.

        One more thing about what these two grips look like. A correct pinch and
        a handle grip differ ONLY at the thumb and index finger: the other three
        fingers wrap the handle in both. So "the hand is at the bottom of the
        knife with fingers round the handle" describes both of them equally and
        is not evidence of anything. Find the thumb before you decide.
        """,
        // The knife, and where the hand sits on it. Enough to judge the thing that
        // matters most: whether they are steering the blade or the back of the
        // handle.
        requiredVisibility: [.tool, .controlPoint],
        // Welcome, never required. One of the thumb and the index finger is
        // behind the blade in any correct pinch grip, so demanding both is
        // demanding a view that does not exist.
        helpfulVisibility: [.thumb, .indexFinger, .remainingFingers, .wrist],
        // The whole lesson turns on one fact: where the thumb is.
        //
        // Everything else about a pinch grip and a handle grip is identical.
        // In both, the middle, ring and little fingers wrap the handle, so a
        // hand full of curled fingers is not evidence either way, and asking
        // "which grip is this" gets a familiar answer rather than a looked-at
        // one. Asked instead where the thumb is, with permission to say it
        // cannot tell, the question becomes one about pixels.
        observations: [
            SkillObservation(
                region: .thumb,
                question:
                    "Ring 1 is drawn on the thumb tip. Is the pixel under ring 1 on the "
                    + "flat METAL face of the blade, or on the HANDLE behind it? Answer for "
                    + "what the ring is sitting on, not for what the grip looks like overall. "
                    + "Say cannotTell if ring 1 is not drawn or the thumb is hidden.",
                answers: ["onBlade", "onHandle", "cannotTell"],
                correct: "onBlade"
            ),
            // The question nobody was asking, and the one that matters most.
            //
            // A cook held the knife with their whole hand wrapped round the
            // BLADE, every finger across the cutting edge, and was told "yep,
            // that's it, looks perfect". Her reading was not even wrong by her
            // own vocabulary: thumb on blade and index on blade is exactly what
            // a correct pinch grip looks like. Nothing in the schema could tell
            // a thumb and finger pinching the steel from a fist closed around
            // it, because nothing ever asked where the other three fingers
            // were.
            SkillObservation(
                region: .remainingFingers,
                question:
                    "On a chef's knife the blade is the wide flat steel and the handle is "
                    + "the narrower part beyond the collar. Are the middle, ring and little "
                    + "fingers wrapped around the wide STEEL BLADE, or around the narrower "
                    + "HANDLE? `onBlade` means the hand is closed around the steel, which is "
                    + "dangerous. `onHandle` is correct and normal. Say cannotTell if those "
                    + "fingers are hidden or out of frame.",
                answers: ["onHandle", "onBlade", "cannotTell"],
                correct: "onHandle"
            ),
            SkillObservation(
                region: .indexFinger,
                question:
                    "Ring 2 is drawn on the index fingertip. Is the pixel under ring 2 on "
                    + "the METAL blade or on the HANDLE? Say cannotTell if ring 2 is not "
                    + "drawn, or the finger is behind the blade where you cannot see it, "
                    + "which is common and perfectly normal.",
                answers: ["onBlade", "onHandle", "cannotTell"],
                correct: "onBlade"
            ),
        ],
        // Said while a look runs, in order, one per look.
        //
        // Every one of these answers "why is it shaped like that", which is the
        // half of a knife lesson that normally gets cut for time. None of them
        // restates the instruction, because a cook who has just been told where
        // to put their thumb does not need telling again while they wait.
        waitingFacts: [
            "While that comes through, here is why this grip and not the obvious one. "
            + "Pinching the blade puts your hand at the point the knife turns around. "
            + "Hold it at the back of the handle instead and your hand is a few inches "
            + "behind that point, so every small wobble at your wrist arrives at the tip "
            + "much bigger. Same hand, same knife, completely different accuracy.",

            "Something worth knowing while I look. Your bottom three fingers are not "
            + "aiming anything. They carry the weight, and that is all they do, which is "
            + "why they can stay loose. The aiming is entirely the thumb and index finger "
            + "on the steel. People who find chopping tiring are usually gripping with all "
            + "five as though the knife were trying to escape.",

            "One more thing while that lands. You can feel the angle of the blade through "
            + "the two fingers on the steel, which you cannot do through a handle. That is "
            + "the part that eventually lets you cut without watching the knife, because "
            + "your hand knows whether it is straight without you looking.",

            "A last one. That flat area where the blade meets the handle is not a "
            + "leftover. It is deliberately squared off on a chef's knife precisely so "
            + "there is somewhere to pinch, which is a reasonable clue that this grip was "
            + "not invented by whoever wrote the recipe you are following.",
        ],
        // Asked by itself. Inside the full prompt this same question came back
        // `onHandle` on a hand wrapped round the steel; on its own, `onBlade`.
        decisiveRegion: .remainingFingers,
        // Fingers curled around the blade is not a grip note, it is a stop.
        dangerousReadings: [.remainingFingers: ["onBlade"]],
        // And she may not say "that's it" without having seen the other three
        // fingers land somewhere safe. A pass she cannot support becomes "let
        // me see that again", which costs a moment; the alternative cost a cook
        // being congratulated with their hand around the edge.
        passRequires: [.remainingFingers: ["onHandle"]],
        // The whole grip, on one screen. Four parts of one shape rather than
        // four steps of a sequence, because that is what a hand does.
        parts: [
            SkillCheckPart(region: .controlPoint, label: "Hand forward, pinching the blade"),
            SkillCheckPart(region: .thumb, label: "Thumb on the flat, near the heel"),
            SkillCheckPart(region: .indexFinger, label: "Index finger curled on the far side"),
            SkillCheckPart(region: .remainingFingers, label: "Three fingers round the handle"),
        ],
        rubric: SkillVisualRubric(
            subject: "a cook's grip on a chef's knife, seen from their own eyes",

            targetTechnique: [
                "The classic pinch grip, which is the general purpose grip for chef's knife work.",
                "Thumb pad on one flat face of the blade, at or just forward of the heel, "
                    + "where the blade meets the handle.",
                "The side of the index finger on the opposite flat face, curled, opposing the thumb. "
                    + "Both fingers are on the flat of the blade and nowhere near the edge.",
                "Middle, ring and little fingers wrapped around the handle.",
                "The hand is far enough forward that it is steering the blade, "
                    + "rather than holding the back of the handle.",
            ],

            acceptableVariations: [
                "Exactly where along the blade the pinch sits. Some cooks pinch a little forward "
                    + "onto the blade, others sit right at the heel or against the bolster. "
                    + "All are fine if the hand is clearly controlling the blade.",
                "Knives with no bolster at all, which most Japanese knives lack. "
                    + "Judge the hand against the heel and the blade to handle junction, "
                    + "never against an expectation that a thick metal bolster is there.",
                "Small hands, large hands, and knives of very different sizes. "
                    + "Judge the RELATIONSHIP between hand, heel and handle, "
                    + "never absolute distances in the image.",
                "Left handed grips, which are the mirror image and equally correct.",
                "How far the three remaining fingers wrap, which handle shape largely decides.",
                "A thumb resting slightly onto the spine side of the blade face rather than "
                    + "square on the middle of it, if the pinch is clearly still opposing.",
            ],

            rankedMistakes: [
                SkillCoachableMistake(
                    key: "handleGrip",
                    observation:
                        "The whole hand is behind the blade on the handle, with nothing pinching "
                        + "the blade itself. Often called a handle grip or hammer grip.\n"
                        + "BE CAREFUL WITH THIS ONE. A correct pinch grip and a handle grip look "
                        + "almost identical, because in BOTH of them the middle, ring and little "
                        + "fingers are wrapped round the handle. The only difference is the thumb "
                        + "and the index finger, which in a pinch grip are up on the flat of the "
                        + "blade. So a hand low on the knife with fingers round the handle is NOT "
                        + "evidence of this mistake on its own. Report it only when you can "
                        + "positively see that the thumb is NOT on the blade. If the thumb is "
                        + "hidden, or you cannot tell where it is, this is not the answer.",
                    correction:
                        "You are holding it by the handle. Slide your hand forward until your "
                        + "thumb and index finger are pinching the flat of the blade, right where "
                        + "it meets the handle.",
                    rationale:
                        "Steering from the back of the handle means every small movement at your "
                        + "wrist becomes a big one at the tip. Pinching the blade puts your hand "
                        + "where the cutting happens, so the knife goes where you point it.",
                    isContextual: true,
                    severity: .outcomeCost,
                    // The thumb, not just the control point. The whole
                    // difference between this mistake and a correct pinch is
                    // where the thumb is, so concluding it without having seen
                    // the thumb is not a weak judgement, it is no judgement.
                    requiresVisible: [.controlPoint, .thumb],
                    // And the pictures have to agree that it is on the handle.
                    // On an archived look she called a textbook pinch grip
                    // `handleGrip` at 0.85 while the thumb sat plainly on the
                    // blade in a sharp, well framed close up. Under this rule
                    // that verdict cannot leave the building, because her own
                    // reading of the thumb would contradict it.
                    impliedBy: [.thumb: ["onHandle"]]
                ),
                SkillCoachableMistake(
                    key: "pointerGrip",
                    observation:
                        "The index finger is extended forward along the spine of the blade "
                        + "rather than curled into a pinch on the blade face.",
                    correction:
                        "Your index finger is running along the top of the blade. Curl it down "
                        + "onto the side of the blade instead, opposite your thumb.",
                    rationale:
                        "A finger on the spine is pushing the knife down rather than guiding it, "
                        + "so your hand works harder and you lose the fine control that comes from "
                        + "gripping the blade between two fingers. It is a real grip for delicate "
                        + "slicing, it is just not the one that makes everyday chopping easier.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.indexFinger]
                ),
                SkillCoachableMistake(
                    key: "thumbOnSpine",
                    observation:
                        "The thumb is on top of the spine rather than on the flat face of "
                        + "the blade.",
                    correction:
                        "Bring your thumb down onto the flat side of the blade so it presses "
                        + "against your index finger.",
                    rationale:
                        "The pinch only works when the thumb and finger oppose each other across "
                        + "the blade. A thumb on the spine has nothing to press against.",
                    isContextual: false,
                    severity: .outcomeCost,
                    requiresVisible: [.thumb]
                ),
                SkillCoachableMistake(
                    key: "fingersOffHandle",
                    observation:
                        "Two or more of the remaining fingers are floating clear of the handle "
                        + "rather than wrapped around it.",
                    correction:
                        "Wrap your bottom three fingers around the handle. They are doing the "
                        + "holding while the pinch does the steering.",
                    rationale:
                        "The pinch controls the angle, but the knife needs somewhere to sit. "
                        + "Fingers off the handle means the weight is hanging from two fingers.",
                    isContextual: false,
                    severity: .efficiency,
                    requiresVisible: [.remainingFingers]
                ),
                SkillCoachableMistake(
                    key: "wristBent",
                    observation:
                        "The wrist is bent hard sideways or upward rather than roughly in line "
                        + "with the forearm.",
                    correction:
                        "Relax your wrist and let the knife line up with your forearm.",
                    rationale:
                        "A bent wrist tires fast and takes the power out of the cut, because the "
                        + "arm can no longer drive the knife in a straight line.",
                    isContextual: false,
                    severity: .efficiency,
                    requiresVisible: [.wrist]
                ),
            ],

            safetySignals: [
                "Any finger visibly on, against, or below the cutting edge.",
                "The thumb wrapped over the spine and down the far side toward the edge.",
                "The knife being swung, waved or rotated in the air rather than held still.",
                "The blade pointed toward the cook's own body or face.",
            ],

            supportedEquipment: [
                "Western chef's knife",
                "Gyuto",
                "Santoku",
            ],

            unsupportedEquipment: [
                "Paring knife",
                "Serrated bread knife",
                "Boning or fillet knife",
                "Chinese cleaver or cai dao",
                "Meat cleaver",
                "Utility or steak knife",
                "Table knife",
            ],

            notVisuallyAssessable: [
                "How hard the cook is squeezing. A relaxed grip and a white knuckled one look "
                    + "the same in a photograph unless the knuckles are visibly blanched.",
                "Whether the grip is comfortable or painful.",
                "How sharp the knife is.",
                "Anything about a finger that is hidden behind the blade, the handle or "
                    + "another finger.",
            ],

            confidenceFloor: 0.55,
            passSummary: "Clean pinch grip.",
            variationSummary: "Own variation on the pinch grip, and in control of the knife."
        ),
        retryFraming:
            "Look at your hand rather than the point of the knife, and turn it slowly. Your "
            + "hand keeps dropping just below what I can see.",
    )
}
