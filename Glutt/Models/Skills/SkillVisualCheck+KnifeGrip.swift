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
        framingInstruction:
            "Rest the blade on your board, look down at your hand, and turn it slowly, like you "
            + "are showing me both sides of the knife. I will read it as you go.",
        // The knife, and where the hand sits on it. Enough to judge the thing that
        // matters most: whether they are steering the blade or the back of the
        // handle.
        requiredVisibility: [.tool, .controlPoint],
        // Welcome, never required. One of the thumb and the index finger is
        // behind the blade in any correct pinch grip, so demanding both is
        // demanding a view that does not exist.
        helpfulVisibility: [.thumb, .indexFinger, .remainingFingers, .wrist],
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
                        + "the blade itself. Often called a handle grip or hammer grip.",
                    correction:
                        "You are holding it by the handle. Slide your hand forward until your "
                        + "thumb and index finger are pinching the flat of the blade, right where "
                        + "it meets the handle.",
                    rationale:
                        "Steering from the back of the handle means every small movement at your "
                        + "wrist becomes a big one at the tip. Pinching the blade puts your hand "
                        + "where the cutting happens, so the knife goes where you point it.",
                    isContextual: true,
                    requiresVisible: [.controlPoint]
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

            confidenceFloor: 0.55
        ),
        retryFraming:
            "Keep hold of it and turn your hand slowly, and I will pick it up as it comes round.",
    )
}
