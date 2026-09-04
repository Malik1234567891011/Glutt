import Foundation

/// Rubrics for the cuts themselves, authored from the culinary instructor
/// deliverable in `docs/skills-instructor-deliverable.md`.
///
/// Almost all of these are judged on **what the cook produced**, not on the
/// motion that produced it, and that was the instructor's call rather than
/// ours. Nobody can read a dice at seven frames a second: the hand is a blur,
/// the food is under it, and the blade hides the last cut. A board of finished
/// cubes, spread into one layer, shows size spread and squareness instantly.
/// Pointing the camera at the outcome is not a compromise, it is the better
/// measurement.
///
/// The second theme running through all of them is tolerance. Every one of
/// these cuts has a professional standard, and every one of those standards is
/// the wrong bar for somebody dicing an onion in their own kitchen. Where the
/// deliverable gave a classical number it is kept as a reference, and the
/// number a cook is actually held to sits in `outcomeTolerance`, which is
/// looser on purpose.
extension SkillVisualCheck {

    // MARK: - Shared pieces

    /// The one mistake that outranks every cut in this file.
    ///
    /// The same sentence on every skill on purpose. A cook who hears a
    /// different phrasing of "mind your fingers" on each lesson learns a set of
    /// lesson-specific rules; one they hear every time is a habit.
    private static let unsafeGuidingHand = SkillCoachableMistake(
        key: "unsafeHand",
        observation:
            "The hand holding the food has fingertips or a thumb forward of the knuckles, in "
            + "the path of the blade, or is on the side the knife is travelling toward.",
        correction:
            "Curl your fingertips back behind your knuckles, and keep that hand behind the "
            + "blade rather than in front of it.",
        rationale:
            "Every cut in this lesson is a repeated motion, and a repeated motion with the "
            + "fingers exposed is the one that eventually finds them.",
        severity: .safety,
        confidenceFloor: 0.45,
        requiresVisible: [.guidingHand, .tool]
    )

    private static let chefKnives = [
        "Western chef's knife",
        "Gyuto",
        "Santoku",
    ]

    private static let notForChefKnifeWork = [
        "Serrated bread knife",
        "Paring knife for board work",
        "Meat cleaver",
        "Mandoline",
    ]

    /// True of every cut here, so written once.
    private static let cutsCannotBeSeen = [
        "How sharp the knife is, which is the single biggest thing affecting how the cut "
            + "looks. Ask rather than infer it.",
        "How hard the cook is gripping or pressing.",
        "Whether the board is moving on the counter, unless it visibly slides.",
        "Anything about the flavour, freshness or quality of the ingredient.",
    ]

    private static let boardParts = [
        SkillCheckPart(region: .result, label: "Pieces a similar size", id: "size"),
        SkillCheckPart(region: .result, label: "No stragglers much bigger than the rest", id: "outliers"),
        SkillCheckPart(region: .guidingHand, label: "Fingers stayed clear", id: "hand"),
    ]

    // MARK: - Slice

    static let knifeSlice = SkillVisualCheck(
        id: "knife.slice.motion",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Give me five normal slices at half speed, looking down at the board as you go.",
        setupNeeds:
            ", and have your board and knife ready.",
        outcomeFraming:
            "Now fan the slices out a little and look straight down at the cut faces.",
        requiredVisibility: [.tool, .ingredient],
        helpfulVisibility: [.guidingHand, .result, .workSurface],
        observations: [
            SkillObservation(
                region: .tool,
                id: "bladeTravel",
                question:
                    "Is the blade being drawn or pushed THROUGH the food, or pressed straight down into it? `travelling` means the cut used the length of the blade. `pressing` means it was pushed down like a guillotine. Say cannotTell if no picture catches the blade in the food.",
                answers: ["travelling", "pressing", "cannotTell"],
                correct: "travelling"
            ),
            SkillObservation(
                region: .guidingHand,
                id: "handBehind",
                question:
                    "Is the guiding hand behind the blade, out of its path? `behind` is correct. `inPath` means fingers are where the blade is travelling. Say cannotTell if that hand is out of frame.",
                answers: ["behind", "inPath", "cannotTell"],
                correct: "behind"
            ),
            SkillObservation(
                region: .result,
                id: "cleanFaces",
                question:
                    "Look at the cut faces of the slices. Are they clean and smooth, or torn and crushed where the blade dragged? `clean` or `torn`. Say cannotTell if you cannot see a cut face clearly.",
                answers: ["clean", "torn", "cannotTell"],
                correct: "clean"
            ),
        ],
        parts: [
            SkillCheckPart(region: .tool, label: "Blade travelling, not just pressing down"),
            SkillCheckPart(region: .guidingHand, label: "Guiding hand behind the blade"),
            SkillCheckPart(region: .result, label: "Clean faces, not torn or crushed"),
        ],
        rubric: SkillVisualRubric(
            subject: "a cook slicing on a board, seen from their own eyes",
            targetTechnique: [
                "The blade travels forward or backward as it goes down, so it slices through "
                    + "the food rather than crushing straight through it.",
                "The cutting path is deliberate and repeatable rather than landing in a "
                    + "different place each time.",
                "The guiding hand stays clear of the blade.",
                "The finished faces are relatively clean rather than torn or squashed.",
            ],
            acceptableVariations: [
                "Push cut, pull cut, a gentle rock, or the straight up-and-down push cut used "
                    + "with many Japanese knives. All of these are correct and which one a cook "
                    + "uses is a matter of knife and school, not of skill.",
                "Whether the tip stays on the board. A classic rock keeps it down, a flatter "
                    + "profile knife lifts clear, and both are right for their blade.",
                "Stroke length, which follows the knife and the ingredient.",
                "How much downward force. A ripe tomato needs almost none, a dense swede needs "
                    + "a lot, and neither says anything about technique.",
                "Slice thickness, unless the cook has named a target.",
            ],
            rankedMistakes: [
                unsafeGuidingHand,
                SkillCoachableMistake(
                    key: "crushNotSlice",
                    observation:
                        "The blade repeatedly stamps straight down and the food visibly "
                        + "compresses, tears or squashes at the cut rather than parting cleanly.",
                    correction:
                        "Let the blade travel forward or back as it goes down. Slice through it "
                        + "instead of pressing straight through.",
                    rationale:
                        "A knife cuts along its edge, not with it. Pressing straight down asks "
                        + "one point of the blade to do all the work, which crushes soft food "
                        + "and skids off dense food.",
                    severity: .outcomeCost,
                    requiresVisible: [.tool, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "wildLift",
                    observation:
                        "The blade lifts far higher than it needs to between cuts and lands in "
                        + "an inconsistent place each time.",
                    correction:
                        "Keep the knife closer to the board and shorten the stroke until it "
                        + "feels controlled.",
                    rationale:
                        "Height is where consistency goes. A blade that never leaves the "
                        + "neighbourhood of the board lands where you last left it.",
                    severity: .efficiency,
                    requiresVisible: [.tool]
                ),
                SkillCoachableMistake(
                    key: "sawingShort",
                    observation:
                        "Many small frantic back-and-forth strokes on ordinary produce that "
                        + "should part in one pass.",
                    correction:
                        "Use one longer, smoother stroke instead of sawing at it.",
                    rationale:
                        "Sawing is what you do when the knife is not doing the work. Usually "
                        + "that means the blade is dull rather than that the technique is wrong.",
                    severity: .efficiency,
                    requiresVisible: [.tool]
                ),
            ],
            safetySignals: [
                "A fingertip or thumb visibly on, against, or under the cutting edge.",
                "Food rolling while the blade descends.",
                "Cutting toward the palm in the air rather than on the board.",
            ],
            supportedEquipment: chefKnives,
            unsupportedEquipment: [
                "Serrated bread knife, which is the right tool for bread and tomatoes and uses "
                    + "a sawing action this lesson is not about.",
                "Meat cleaver",
                "Mandoline",
            ],
            notVisuallyAssessable: cutsCannotBeSeen,
            confidenceFloor: 0.55,
            passSummary: "Clean slicing stroke, faces cut rather than crushed.",
            variationSummary: "Their own stroke, and it was going through cleanly.",
            outcomeTolerance: [
                "Home standard: most slices within roughly a fifth of the intended thickness. "
                    + "One or two obvious outliers matter, a millimetre here and there does not.",
                "A professional would hold a consistent target thickness. Do not hold a home "
                    + "cook to that unless they asked for it.",
            ],
            audioSignals: [
                "Repeated hard knocks of the board on a single cut suggest stamping rather than "
                    + "slicing. A clean cut through firm produce is usually one crisp fracture. "
                    + "Supporting evidence only.",
            ]
        ),
        retryFraming:
            "Keep going and just look down a little more, so I can see the blade and the board "
            + "together."
    )

    // MARK: - Rough chop

    static let knifeRoughChop = SkillVisualCheck(
        id: "knife.rough-chop.result",
        assessmentMode: .outcome,
        framingInstruction:
            "Finish the chop, then spread it out once with the side of the knife.",
        photoFraming:
            "Spread it into one layer and take a photo looking straight down at the board.",
        setupNeeds:
            ", and have your board and knife ready.",
        outcomeFraming:
            "Look straight down at the board so I can see the whole pile in one layer.",
        requiredVisibility: [.result],
        helpfulVisibility: [.workSurface, .guidingHand, .tool],
        observations: [
            SkillObservation(
                region: .result,
                id: "sizeBand",
                question:
                    "Are the pieces broadly in one size band, the sort of rough chop that cooks evenly, or wildly mixed? `even` or `mixed`. A rough chop does not need to be neat, only consistent enough. Say cannotTell if you cannot see the pieces.",
                answers: ["even", "mixed", "cannotTell"],
                correct: "even"
            ),
            SkillObservation(
                region: .result,
                id: "noChunks",
                question:
                    "Is there a much larger chunk hiding among the rest, the kind that would still be raw when the others are done? `noChunks` means nothing stands out. `hasChunks` means at least one does. Say cannotTell if the pile is obscured.",
                answers: ["noChunks", "hasChunks", "cannotTell"],
                correct: "noChunks"
            ),
        ],
        parts: [
            SkillCheckPart(region: .result, label: "Pieces in a useful size band", id: "band"),
            SkillCheckPart(region: .result, label: "No giant chunks hiding in it", id: "outliers"),
        ],
        rubric: SkillVisualRubric(
            subject: "a board of roughly chopped vegetables",
            targetTechnique: [
                "The pieces are deliberately rustic but sit inside a useful size band for the "
                    + "dish they are going into.",
                "There are no large intact chunks hiding among much smaller fragments.",
            ],
            acceptableVariations: [
                "Shape. It is completely irrelevant here and there is no target geometry.",
                "Exact dimensions. There is no correct number for a rough chop.",
                "Different foods fracturing differently. An onion falls into layers, a carrot "
                    + "into wedges, and neither is a mistake.",
                "Rock chop, push cut or cross chop as the method.",
                "A few small flakes and crumbs at the edge of the pile, which every chop "
                    + "produces.",
            ],
            rankedMistakes: [
                unsafeGuidingHand,
                SkillCoachableMistake(
                    key: "sizeChaos",
                    observation:
                        "The pile contains pieces several times larger than the majority of "
                        + "the rest.",
                    correction:
                        "Find the biggest pieces and bring just those down to the size of "
                        + "the rest.",
                    rationale:
                        "Rough does not mean uneven. The only thing size consistency is really "
                        + "for is that everything finishes cooking at the same time, and one "
                        + "chunk twice the size of the rest is still raw when the rest is done.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "overChopped",
                    observation:
                        "What was meant to be a rough chop has been taken down to a fine mince "
                        + "or a paste.",
                    correction:
                        "Stop there. You already had it small enough for a rough chop.",
                    rationale:
                        "Past a certain point you are working against yourself: the pieces stop "
                        + "holding their texture in the pan and start releasing water instead.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A fingertip or thumb visibly against the cutting edge.",
                "Food rolling under a descending blade.",
            ],
            supportedEquipment: chefKnives,
            unsupportedEquipment: notForChefKnifeWork,
            notVisuallyAssessable: cutsCannotBeSeen,
            confidenceFloor: 0.55,
            passSummary: "Rustic, but everything in the same size band.",
            variationSummary: "Chopped their own way, and it will cook evenly.",
            outcomeTolerance: [
                "Home standard: the largest normal piece no more than about twice the width of "
                    + "the smallest normal piece. Ignore a few flakes and crumbs entirely.",
                "Do not apply a professional ruler standard to something called rough. That is "
                    + "the definition of a false correction here.",
            ]
        ),
        retryFraming:
            "Spread it out into one layer and hold still for a second so I can see the sizes."
    )

    // MARK: - Dice

    static let knifeDice = SkillVisualCheck(
        id: "knife.dice.result",
        assessmentMode: .outcome,
        framingInstruction:
            "When you have a handful done, spread them into a single layer on the board.",
        photoFraming:
            "Spread a handful into one layer and take a photo straight down at it.",
        setupNeeds:
            ", and have your board and knife ready.",
        outcomeFraming:
            "Look straight down at them. I am checking whether they will cook evenly, "
            + "not whether they are perfect.",
        requiredVisibility: [.result],
        helpfulVisibility: [.workSurface, .guidingHand, .tool],
        observations: [
            SkillObservation(
                region: .result,
                id: "evenSize",
                question:
                    "Are the dice a similar size to each other? `even` or `uneven`. Say cannotTell if you cannot see enough of them.",
                answers: ["even", "uneven", "cannotTell"],
                correct: "even"
            ),
            SkillObservation(
                region: .result,
                id: "squareFaces",
                question:
                    "Are the pieces roughly cube shaped with square faces, or wedged and triangular? `square` or `wedged`. Say cannotTell if the shapes are not clear.",
                answers: ["square", "wedged", "cannotTell"],
                correct: "square"
            ),
            SkillObservation(
                region: .result,
                id: "cleanCut",
                question:
                    "Do the pieces look cut, or crushed and squashed at the edges by a dull blade? `clean` or `crushed`. Say cannotTell if you cannot see the edges.",
                answers: ["clean", "crushed", "cannotTell"],
                correct: "clean"
            ),
        ],
        parts: [
            SkillCheckPart(region: .result, label: "Pieces a similar size", id: "size"),
            SkillCheckPart(region: .result, label: "Faces roughly square, not wedged", id: "square"),
            SkillCheckPart(region: .result, label: "Cut cleanly, not crushed", id: "clean"),
        ],
        rubric: SkillVisualRubric(
            subject: "a board of diced vegetables spread into one layer",
            targetTechnique: [
                "The pieces are cube-like, with faces that are roughly square rather than "
                    + "tapering to a wedge.",
                "The pieces are consistent enough with one another to cook at similar rates.",
                "Classical reference sizes, for context only: small dice about 6mm, medium "
                    + "about 12mm, large about 19mm.",
            ],
            acceptableVariations: [
                "Not matching a classical size at all. For an ordinary recipe that just says "
                    + "'diced', even pieces are the whole requirement and the specific number "
                    + "does not matter.",
                "Rounded and irregular pieces from the outside of curved produce. Squaring a "
                    + "carrot off completely wastes a third of it to win a geometry contest, and "
                    + "a cook who keeps that food is right.",
                "A recipe-specific dice at any stated size.",
                "Softer foods like tomato or avocado having much less defined edges.",
                "Pieces that are consistent in the dimension that matters for cooking, even "
                    + "when they are not perfect cubes. Thickness governs cooking time.",
            ],
            rankedMistakes: [
                unsafeGuidingHand,
                SkillCoachableMistake(
                    key: "unevenCookingSize",
                    observation:
                        "Clearly large and clearly small pieces are mixed through the batch, "
                        + "enough that they would not finish cooking together.",
                    correction:
                        "Use one finished piece as your size guide and match the next few "
                        + "cuts to it.",
                    rationale:
                        "This is the only thing dice size is actually for. Mixed sizes means "
                        + "some pieces are mush before the others are cooked.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "strongWedges",
                    observation:
                        "The pieces consistently taper to a wedge on the same side, which happens "
                        + "when the blade is leaning rather than upright.",
                    correction:
                        "Bring the blade upright. Your cuts are leaning, which is turning cubes "
                        + "into wedges.",
                    rationale:
                        "A leaning blade is usually the wrist rather than the hand, and it is "
                        + "easy to fix once you know it is happening. Wedges also stack badly, "
                        + "so the next cut leans further.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "crushing",
                    observation:
                        "The pieces are smeared, squashed or torn at the edges rather than "
                        + "cleanly cut.",
                    correction:
                        "Use a longer slicing stroke and less downward force.",
                    rationale:
                        "Crushed edges leak, which is why a crushed dice weeps on the board and "
                        + "browns badly in the pan.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A fingertip or thumb visibly against the cutting edge.",
                "Food rolling under a descending blade.",
            ],
            supportedEquipment: chefKnives,
            unsupportedEquipment: notForChefKnifeWork,
            notVisuallyAssessable: cutsCannotBeSeen,
            confidenceFloor: 0.55,
            passSummary: "Even dice, and it will cook at one rate.",
            variationSummary: "Not textbook cubes, but consistent enough to cook evenly.",
            outcomeTolerance: [
                "Home standard: the middle 80% of the pieces within about a quarter of the "
                    + "chosen size. Reject only inconsistency big enough to change how it cooks.",
                "A professional exercise would be within 10 to 15% and visibly square. That is "
                    + "not the bar here and should not be mentioned as though it were.",
                "For naturally curved vegetables, judge the cooking dimension, which is "
                    + "thickness, more than perfect cube geometry.",
            ]
        ),
        retryFraming:
            "Spread them a little thinner and look straight down, so they are not overlapping."
    )

    // MARK: - Mince

    static let knifeMince = SkillVisualCheck(
        id: "knife.mince.result",
        assessmentMode: .outcome,
        framingInstruction: "Spread a teaspoon of the finished mince thinly on the board.",
        photoFraming:
            "Spread a teaspoon of it thin and take a photo straight down at the board.",
        setupNeeds:
            ", and have your board and knife ready.",
        outcomeFraming: "Look straight down at it so I can see the individual pieces.",
        requiredVisibility: [.result],
        helpfulVisibility: [.workSurface, .guidingHand, .tool],
        observations: [
            SkillObservation(
                region: .result,
                id: "fineEnough",
                question:
                    "Is this mince fine enough that the pieces would disappear into a dish, "
                    + "or is it really a small dice with visible chunks? `fine` or `chunky`. "
                    + "Say cannotTell if you cannot see the individual pieces.",
                answers: ["fine", "chunky", "cannotTell"],
                correct: "fine"
            ),
            SkillObservation(
                region: .result,
                id: "evenMince",
                question:
                    "Are the pieces a similar size to each other, or a mix of dust and larger "
                    + "bits? `even` or `mixed`. Say cannotTell if you cannot see the pile "
                    + "clearly.",
                answers: ["even", "mixed", "cannotTell"],
                correct: "even"
            ),
            SkillObservation(
                region: .result,
                id: "notPaste",
                question:
                    "Has it been worked so far that it has gone wet and pasty, or are the "
                    + "pieces still separate? `separate` or `pasty`. Say cannotTell if you "
                    + "cannot judge the texture.",
                answers: ["separate", "pasty", "cannotTell"],
                correct: "separate"
            ),
        ],
        parts: boardParts,
        rubric: SkillVisualRubric(
            subject: "a spread of finely minced food on a board",
            targetTechnique: [
                "The food is cut into very small pieces suited to what it is for, without "
                    + "needless pounding.",
                "The pieces are fairly evenly distributed in size.",
                "For herbs, it stays leafy rather than becoming a bruised wet paste, unless a "
                    + "paste is the intention.",
                "For aromatics, fine enough to disperse through the dish matters more than any "
                    + "particular millimetre.",
            ],
            acceptableVariations: [
                "Rock chop, repeated slice-and-gather, or cross chop as the method.",
                "Deliberately taking something to a paste with salt and the flat of the knife. "
                    + "That is a real technique, not an overshoot.",
                "A wide range of fineness. 'Mince' covers a lot of ground and the recipe decides.",
                "Some sticking and smearing, which is normal with anything moist.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "unsafeGather",
                    observation:
                        "A hand is sweeping or gathering the pile while the knife is still in "
                        + "the other hand and close to it.",
                    correction:
                        "Set the knife down, or use the flat of the blade or a scraper to "
                        + "gather, before you carry on.",
                    rationale:
                        "Gathering with a bare hand next to a working blade is where a lot of "
                        + "kitchen cuts actually happen, because the hand is moving toward the "
                        + "knife rather than away from it.",
                    severity: .safety,
                    confidenceFloor: 0.45,
                    requiresVisible: [.guidingHand, .tool]
                ),
                SkillCoachableMistake(
                    key: "largeStragglers",
                    observation:
                        "A few pieces are noticeably larger than the bulk of the mince.",
                    correction:
                        "Pull the big pieces into the centre and give only those a few "
                        + "more passes.",
                    rationale:
                        "Working the whole pile again to fix four pieces overworks the rest. "
                        + "Gathering the stragglers is faster and keeps the texture.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "poundingHerbs",
                    observation:
                        "Leafy herbs have gone dark, wet and pasty from being pounded rather "
                        + "than sliced.",
                    correction:
                        "Switch from pounding straight down to clean slices. You are bruising "
                        + "them into the board.",
                    rationale:
                        "Bruised herbs leak their oils onto the board instead of into the dish, "
                        + "which is exactly the flavour you were chopping them for.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A hand gathering directly in front of a moving blade.",
                "A fingertip visibly against the edge.",
            ],
            supportedEquipment: chefKnives,
            unsupportedEquipment: notForChefKnifeWork,
            notVisuallyAssessable: cutsCannotBeSeen,
            confidenceFloor: 0.55,
            passSummary: "Fine, even mince.",
            variationSummary: "Their own fineness, and evenly done.",
            outcomeTolerance: [
                "Home standard for a fine mince: no repeated pieces much above 3 to 4mm. A "
                    + "formal brunoise is a different skill and a different bar.",
                "Judge how evenly it will disperse through a dish, not microscopic uniformity.",
            ]
        ),
        retryFraming: "Spread it a bit thinner so the pieces are not sitting on top of each other."
    )

    // MARK: - Julienne

    static let knifeJulienne = SkillVisualCheck(
        id: "knife.julienne.result",
        assessmentMode: .outcome,
        framingInstruction: "Line up six of the finished sticks side by side.",
        photoFraming:
            "Line six sticks up side by side and take a photo straight down at them.",
        setupNeeds:
            ", and have your board and knife ready.",
        outcomeFraming: "Look straight down at them so I can compare their thickness.",
        requiredVisibility: [.result],
        helpfulVisibility: [.workSurface, .guidingHand, .tool, .ingredient],
        observations: [
            SkillObservation(
                region: .result,
                id: "evenThickness",
                question:
                    "Are the sticks a similar thickness to each other? `even` or `uneven`. Say cannotTell if you cannot see enough of them.",
                answers: ["even", "uneven", "cannotTell"],
                correct: "even"
            ),
            SkillObservation(
                region: .result,
                id: "squareSection",
                question:
                    "Are the sticks square in cross section, or wedge shaped and tapering? `square` or `wedged`. Say cannotTell if the shapes are not clear.",
                answers: ["square", "wedged", "cannotTell"],
                correct: "square"
            ),
            SkillObservation(
                region: .guidingHand,
                id: "handClear",
                question:
                    "Did the guiding hand stay clear of the blade's path? `clear` or `inPath`. Say cannotTell if that hand is out of frame.",
                answers: ["clear", "inPath", "cannotTell"],
                correct: "clear"
            ),
        ],
        parts: [
            SkillCheckPart(region: .result, label: "Sticks a similar thickness", id: "thickness"),
            SkillCheckPart(region: .result, label: "Square-ish, not wedge shaped", id: "square"),
            SkillCheckPart(region: .guidingHand, label: "Fingers stayed clear", id: "hand"),
        ],
        rubric: SkillVisualRubric(
            subject: "a line of julienned vegetable sticks",
            targetTechnique: [
                "Thin, matchstick-like strips.",
                "Consistent enough with one another to cook at the same rate.",
                "The blade stays upright enough that the sticks do not come out triangular.",
                "Classical professional reference, for context only: about 3mm square and "
                    + "50 to 60mm long.",
            ],
            acceptableVariations: [
                "Length. Two inches versus two and a half is a difference between schools and "
                    + "is irrelevant to a home cook.",
                "Naturally tapered ends, unless this is a formal knife-cut drill.",
                "Ingredients like peppers, which are julienned from curved panels and cannot "
                    + "produce a perfect square cross-section without wasting most of them.",
                "A mandoline-produced julienne, which is a perfectly good way to prepare food. "
                    + "It just does not demonstrate this knife skill, so say that warmly rather "
                    + "than marking it wrong.",
            ],
            rankedMistakes: [
                unsafeGuidingHand,
                SkillCoachableMistake(
                    key: "unevenThickness",
                    observation:
                        "The sticks vary visibly in thickness across the batch.",
                    correction:
                        "Use the last strip as your visual spacer and match the next one to it.",
                    rationale:
                        "Matching to the piece you just cut keeps you honest. Matching to an "
                        + "idea in your head drifts.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "bladeLeaning",
                    observation:
                        "The sticks are consistently wedge shaped or triangular in section "
                        + "rather than square.",
                    correction:
                        "Bring the blade vertical. The sticks are coming out wedge shaped.",
                    rationale:
                        "A wedge-shaped stick has a thin edge that overcooks and a thick spine "
                        + "that does not, which is the whole thing julienne is trying to avoid.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "unstableStack",
                    observation:
                        "The stack of planks being cut is sliding apart before the cut lands.",
                    correction:
                        "Make a smaller stack. It is sliding before you cut it.",
                    rationale:
                        "Three planks that stay put beat six that move. The stack is only "
                        + "helping while it is stable.",
                    severity: .efficiency,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: [
                "A fingertip or thumb visibly against the cutting edge.",
                "A stack collapsing under a descending blade.",
            ],
            supportedEquipment: chefKnives,
            unsupportedEquipment: notForChefKnifeWork,
            notVisuallyAssessable: cutsCannotBeSeen,
            confidenceFloor: 0.55,
            passSummary: "Even matchsticks.",
            variationSummary: "Not competition julienne, but they will cook together.",
            outcomeTolerance: [
                "Home standard: most sticks around 2 to 4mm thick and similar enough to one "
                    + "another to cook together. Length can vary a lot and does not matter.",
                "A professional drill would be near 3mm square. Do not hold a home cook there.",
            ]
        ),
        retryFraming: "Line a few of them up next to each other and look straight down."
    )

    // MARK: - Dice an onion

    static let knifeDiceOnion = SkillVisualCheck(
        id: "knife.dice-onion.result",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Work through it normally, and angle your head so I can see the onion, the edge of "
            + "the knife and your holding hand together.",
        setupNeeds:
            ", and have an onion, a board and your knife ready.",
        outcomeFraming: "Now spread the dice out into one layer and look straight down.",
        requiredVisibility: [.ingredient, .tool],
        helpfulVisibility: [.guidingHand, .result, .workSurface],
        observations: [
            SkillObservation(
                region: .ingredient,
                id: "flatFace",
                question:
                    "Is the onion sitting on a flat cut face, or rolling on its curved side? `flat` or `rolling`. A flat face is what stops it moving. Say cannotTell if you cannot see how it sits.",
                answers: ["flat", "rolling", "cannotTell"],
                correct: "flat"
            ),
            SkillObservation(
                region: .guidingHand,
                id: "handBehind",
                question:
                    "Is the guiding hand behind the blade rather than in its path? `behind` or `inPath`. Say cannotTell if that hand is out of frame.",
                answers: ["behind", "inPath", "cannotTell"],
                correct: "behind"
            ),
            SkillObservation(
                region: .result,
                id: "evenDice",
                question:
                    "Are the dice a similar size to each other? `even` or `uneven`. Say cannotTell if you cannot see the pieces.",
                answers: ["even", "uneven", "cannotTell"],
                correct: "even"
            ),
        ],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Cut face flat on the board"),
            SkillCheckPart(region: .guidingHand, label: "Hand behind the blade"),
            SkillCheckPart(region: .result, label: "Dice a similar size", id: "even"),
        ],
        rubric: SkillVisualRubric(
            subject: "a cook dicing an onion, and the dice they produced",
            targetTechnique: [
                "The onion is halved and put cut-side down on the board before any fine work.",
                "The root may be left on as a handle.",
                "The final dice is reasonably even.",
                "Either school is correct: the traditional radial or vertical cuts with optional "
                    + "horizontal cuts and then cross cuts, OR the method that avoids horizontal "
                    + "cuts entirely by reorienting the onion.",
            ],
            acceptableVariations: [
                "Skipping the horizontal cuts completely. They are NOT required for mastery. "
                    + "There is a well documented method that avoids them specifically because "
                    + "they are the dangerous part, and a cook using it is doing something "
                    + "safer, not something lesser.",
                "Leaving the root fully intact, or trimming it, or having already removed it.",
                "Radial cuts that follow the curve of the onion rather than straight vertical "
                    + "ones. Both produce good dice.",
                "Peeling off the first flesh layer if it is tough or damaged, and leaving it on "
                    + "if it is sound.",
                "Uneven pieces at the very ends, which every onion produces.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "horizontalTowardPalm",
                    observation:
                        "The knife is travelling horizontally through the onion toward the palm "
                        + "or fingers of the hand bracing it.",
                    correction:
                        "Stop that cut. Move your hand out of the blade's path, or skip the "
                        + "horizontal cuts entirely.",
                    rationale:
                        "This is the single most dangerous thing in ordinary home knife work: "
                        + "a blade moving sideways at a flat hand with nothing to stop it. You "
                        + "do not need those cuts to dice an onion well.",
                    severity: .safety,
                    confidenceFloor: 0.45,
                    requiresVisible: [.tool, .guidingHand]
                ),
                SkillCoachableMistake(
                    key: "unstableOnion",
                    observation:
                        "The onion is sitting on its curved side and rocking while being cut, "
                        + "rather than resting on a flat cut face.",
                    correction:
                        "Put the cut face flat on the board before you keep going.",
                    rationale:
                        "A halved onion has a perfect flat face built into it. Cutting on the "
                        + "round side is doing it the hard and dangerous way for no reason.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "rootSeveredEarly",
                    observation:
                        "The root end has been cut away before the cross cuts, so the layers "
                        + "are separating and sliding.",
                    correction:
                        "Leave the root end attached until the cross cuts. It holds all the "
                        + "layers together for you.",
                    rationale:
                        "The root is the only thing holding an onion together. Once it is gone "
                        + "you are dicing a pile of loose curved layers instead of one object.",
                    isContextual: true,
                    severity: .efficiency,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "unevenFinalDice",
                    observation:
                        "The finished dice varies widely in size.",
                    correction:
                        "Tighten the spacing on the next cuts so the pieces match more closely.",
                    rationale:
                        "Onion is usually the thing that goes in first and cooks longest, so "
                        + "uneven pieces means some are sweet and soft while others are still raw.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "The knife point driven horizontally toward the supporting hand.",
                "The onion rolling on its curved side during a forceful cut.",
                "A fingertip visibly against the edge.",
            ],
            supportedEquipment: chefKnives,
            unsupportedEquipment: notForChefKnifeWork,
            notVisuallyAssessable: cutsCannotBeSeen,
            confidenceFloor: 0.55,
            passSummary: "Even dice, and the hand stayed out of the way.",
            variationSummary: "Their own method, safely done, and the dice is even.",
            outcomeTolerance: [
                "Home standard: the middle 80% of pieces within about a quarter of the chosen "
                    + "size. The end pieces of any onion will be odd and that is fine.",
            ]
        ),
        retryFraming:
            "Keep going and tip your head down a bit, so I can see the onion and the knife "
            + "at the same time."
    )

    // MARK: - Mince garlic

    static let knifeMinceGarlic = SkillVisualCheck(
        id: "knife.mince-garlic.result",
        assessmentMode: .outcome,
        framingInstruction: "Spread the garlic out thin on the board when you are done.",
        photoFraming:
            "Spread the garlic thin and take a photo straight down at it.",
        setupNeeds:
            ", and have a clove of garlic and your knife ready.",
        outcomeFraming: "Look straight down so I can see the individual pieces.",
        requiredVisibility: [.result],
        helpfulVisibility: [.workSurface, .guidingHand, .tool],
        observations: [
            SkillObservation(
                region: .result,
                id: "fineEnough",
                question:
                    "Is the garlic fine enough to melt into a dish, or still in visible "
                    + "chunks that would catch and burn? `fine` or `chunky`. Say cannotTell "
                    + "if you cannot see the individual pieces.",
                answers: ["fine", "chunky", "cannotTell"],
                correct: "fine"
            ),
            SkillObservation(
                region: .result,
                id: "evenMince",
                question:
                    "Are the pieces a similar size, or a mix of paste and larger bits? "
                    + "`even` or `mixed`. Uneven garlic burns in parts before the rest "
                    + "cooks. Say cannotTell if you cannot see the pile clearly.",
                answers: ["even", "mixed", "cannotTell"],
                correct: "even"
            ),
            SkillObservation(
                region: .result,
                id: "notPaste",
                question:
                    "Has it been worked into a wet paste, or are the pieces still separate? "
                    + "`separate` or `pasty`. Say cannotTell if you cannot judge the "
                    + "texture.",
                answers: ["separate", "pasty", "cannotTell"],
                correct: "separate"
            ),
        ],
        parts: boardParts,
        rubric: SkillVisualRubric(
            subject: "minced garlic spread on a board",
            targetTechnique: [
                "The clove is peeled, and the hard root end removed if it was still there.",
                "It is reduced to small, fairly even pieces.",
                "For an ordinary mince, it stops before it becomes a wet paste.",
            ],
            acceptableVariations: [
                "Slice then chop, smash then chop, or rock chop. All standard.",
                "A press, a grater or a knife-made paste. These are all legitimate preparations, "
                    + "but they are NOT interchangeable: more cell damage means more pungency, so "
                    + "they taste different in the finished dish. Ask what they are going for "
                    + "rather than ranking one above the others.",
                "Some sticky smearing on the board and the blade, which is what garlic does.",
                "Larger pieces when the recipe wants them, for example garlic that is going to "
                    + "be fished out later.",
            ],
            rankedMistakes: [
                unsafeGuidingHand,
                SkillCoachableMistake(
                    key: "largeChunks",
                    observation:
                        "A few pieces are much larger than the rest of the mince.",
                    correction:
                        "Pull those big pieces back into the pile and mince just until they "
                        + "match the rest.",
                    rationale:
                        "Garlic burns fast and small. A big piece among fine mince is either "
                        + "raw and harsh when the rest is done, or the rest is burnt by the "
                        + "time it softens.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "unintendedPaste",
                    observation:
                        "The garlic has been worked past a mince into a wet paste.",
                    correction:
                        "Stop chopping. You have crossed from mince into paste, which will hit "
                        + "a lot harder in the dish.",
                    rationale:
                        "Breaking more cells releases more of the compounds that make garlic "
                        + "sharp. A paste is not a finer mince, it is a stronger ingredient.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A hand gathering directly in front of a moving blade.",
                "A fingertip visibly against the edge.",
            ],
            supportedEquipment: chefKnives + ["Garlic press", "Microplane or fine grater"],
            unsupportedEquipment: notForChefKnifeWork,
            notVisuallyAssessable: cutsCannotBeSeen + [
                "How strong the garlic will taste, which depends on how much the cells were "
                    + "damaged and cannot be read from a photograph.",
            ],
            confidenceFloor: 0.55,
            passSummary: "Fine, even garlic.",
            variationSummary: "Their own way with it, and evenly done.",
            outcomeTolerance: [
                "Home standard: no repeated pieces much above 3 to 4mm for a fine mince.",
                "Judge whether it will disperse and cook evenly, not uniformity for its own sake.",
            ]
        ),
        retryFraming: "Spread it a little thinner so the pieces are not piled up."
    )

    // MARK: - Chop herbs

    static let knifeChopHerbs = SkillVisualCheck(
        id: "knife.chop-herbs.result",
        assessmentMode: .outcome,
        framingInstruction: "Spread the chopped herbs out once with the side of the knife.",
        photoFraming:
            "Spread the herbs out and take a photo straight down at the board.",
        setupNeeds:
            ", and have your herbs and your knife ready.",
        outcomeFraming:
            "Look straight down at them so I can see whether they are still dry and leafy.",
        requiredVisibility: [.result],
        helpfulVisibility: [.workSurface, .guidingHand, .tool],
        observations: [
            SkillObservation(
                region: .result,
                id: "stillGreen",
                question:
                    "Are the herbs still green and leafy, or dark and bruised? `green` or `bruised`. Say cannotTell if you cannot see them clearly.",
                answers: ["green", "bruised", "cannotTell"],
                correct: "green"
            ),
            SkillObservation(
                region: .result,
                id: "notWet",
                question:
                    "Is there a wet dark smear on the board where the herbs were worked over, or is the board clean around them? `dry` or `smeared`. Say cannotTell if you cannot see the board.",
                answers: ["dry", "smeared", "cannotTell"],
                correct: "dry"
            ),
            SkillObservation(
                region: .result,
                id: "evenCut",
                question:
                    "Are the pieces evenly cut, or a mix of dust and whole leaves? `even` or `mixed`. Say cannotTell if you cannot see the pile.",
                answers: ["even", "mixed", "cannotTell"],
                correct: "even"
            ),
        ],
        parts: [
            SkillCheckPart(region: .result, label: "Still green and leafy", id: "leafy"),
            SkillCheckPart(region: .result, label: "Not wet or bruised into the board", id: "dry"),
            SkillCheckPart(region: .result, label: "Evenly cut", id: "even"),
        ],
        rubric: SkillVisualRubric(
            subject: "chopped fresh herbs on a board",
            targetTechnique: [
                "The herbs are gathered and cut with a clean slicing motion.",
                "The result stays visibly leafy and green rather than wet, darkened or smashed.",
                "For parsley or coriander: gather, slice, gather again, repeat. Not pounding "
                    + "indefinitely in one place.",
                "For a basil or mint chiffonade: stacked, rolled, and sliced thinly, when "
                    + "ribbons are what is wanted.",
            ],
            acceptableVariations: [
                "An ordinary chop instead of a chiffonade. Ribbons are for when you want "
                    + "ribbons, and most dishes do not.",
                "Including tender stems. Coriander and parsley stems are full of flavour and "
                    + "many cooks deliberately keep them.",
                "A rustic, uneven chop when that is what the dish wants.",
                "Different knife motions, which vary with the blade.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "poundedWet",
                    observation:
                        "The herbs are dark, wet and flattened, with green staining on the board "
                        + "around them.",
                    correction:
                        "Use fewer, cleaner slices. You are crushing them into the board.",
                    rationale:
                        "That green on the board is the flavour. Once it is out of the leaf it "
                        + "is not going into the food.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "overworked",
                    observation:
                        "The herbs have been chopped well past the point of being usable, "
                        + "toward a paste.",
                    correction:
                        "Stop there. More chopping will bruise them without making the dish "
                        + "any better.",
                    rationale:
                        "Herbs are the one thing where doing less is doing it better. Every "
                        + "extra pass costs colour and aroma.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "largeStems",
                    observation:
                        "Thick woody stems are mixed through the chopped leaves.",
                    correction:
                        "Pull the thick woody stems out. The tender ones can stay.",
                    rationale:
                        "Woody stems stay woody however finely you chop them. Tender ones "
                        + "soften and taste of the herb.",
                    isContextual: true,
                    severity: .cosmetic,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A hand gathering directly in front of a moving blade.",
                "A fingertip visibly against the edge.",
            ],
            supportedEquipment: chefKnives,
            unsupportedEquipment: notForChefKnifeWork,
            notVisuallyAssessable: cutsCannotBeSeen,
            confidenceFloor: 0.55,
            passSummary: "Dry, leafy and evenly chopped.",
            variationSummary: "Chopped their own way, and still green and dry.",
            outcomeTolerance: [
                "Home standard: no wet green paste, and no repeated whole leaves or thick "
                    + "stems, unless a rustic chop was the intention.",
                "A professional garnish standard is a clean consistent cut. Do not apply it "
                    + "to herbs going into a stew.",
            ]
        ),
        retryFraming: "Spread them out once more and look straight down at the board."
    )

    // MARK: - Slice against the grain

    static let knifeAgainstGrain = SkillVisualCheck(
        id: "knife.against-grain.result",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Before you cut, hold the whole piece in view for a couple of seconds so I can "
            + "see which way the fibres run.",
        setupNeeds:
            ", and have the cooked meat on your board.",
        outcomeFraming: "Now make three slices and show me the face of one of them.",
        requiredVisibility: [.ingredient],
        helpfulVisibility: [.tool, .result, .guidingHand, .workSurface],
        observations: [
            SkillObservation(
                region: .tool,
                id: "crossingFibres",
                question:
                    "Is the knife crossing the muscle fibres at roughly a right angle, or running along them? `crossing` or `along`. The fibres are the fine parallel lines in the meat. Say cannotTell if you cannot make out the grain or the blade.",
                answers: ["crossing", "along", "cannotTell"],
                correct: "crossing"
            ),
            SkillObservation(
                region: .result,
                id: "shortFibres",
                question:
                    "On the cut face, are the fibres short, so the face looks like a bundle of short ends, or long and stringy running the length of the slice? `short` or `long`. Say cannotTell if you cannot see a cut face.",
                answers: ["short", "long", "cannotTell"],
                correct: "short"
            ),
        ],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Grain direction found"),
            SkillCheckPart(region: .tool, label: "Knife crossing the fibres"),
            SkillCheckPart(region: .result, label: "Short fibres on the cut face", id: "face"),
        ],
        rubric: SkillVisualRubric(
            subject: "a piece of cooked meat being sliced, and the cut faces produced",
            targetTechnique: [
                "The cook identifies which way the muscle fibres run before cutting.",
                "The knife cuts across those fibres, close to perpendicular for tougher cuts.",
                "The slices are an appropriate thickness for how tender the cut is.",
                "On the cut face, the fibres appear as short stubs rather than long strands "
                    + "running the length of the slice.",
            ],
            acceptableVariations: [
                "Not being exactly 90 degrees. A bias or angled slice both crosses the grain "
                    + "and gives broader slices, and is often the better choice.",
                "Tender cuts, where grain direction matters much less and a cook who does not "
                    + "fuss about it is not making a mistake.",
                "Reorienting the meat partway through. The grain changes direction within a "
                    + "large cut, and following it is correct rather than indecisive.",
                "Braised or shredded preparations, where this whole skill does not apply.",
            ],
            rankedMistakes: [
                unsafeGuidingHand,
                SkillCoachableMistake(
                    key: "withGrain",
                    observation:
                        "Long unbroken fibres run the full length of each slice, meaning the "
                        + "knife is travelling along the grain rather than across it.",
                    correction:
                        "Turn the meat about a quarter turn and cut across those long "
                        + "fibres instead.",
                    rationale:
                        "Cutting across the grain shortens every fibre to the thickness of the "
                        + "slice, so your teeth have almost no work to do. Cutting along it "
                        + "leaves them full length, and the same piece of meat eats tough.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "grainNotChecked",
                    observation:
                        "The cook begins slicing immediately without pausing to look at how "
                        + "the fibres run.",
                    correction:
                        "Before the next slice, pause and trace the muscle lines with your eyes.",
                    rationale:
                        "It takes two seconds and it is the entire skill. Everything else here "
                        + "is just cutting.",
                    severity: .efficiency,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "tooThickForToughCut",
                    observation:
                        "Thick slices from a cut that needs thin ones to eat tenderly.",
                    correction:
                        "Make the slices thinner. This cut will eat more tenderly that way.",
                    rationale:
                        "Slice thickness is fibre length once you are cutting across the grain. "
                        + "On a tough cut, thinner is the whole trick.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A fingertip or thumb visibly against the cutting edge.",
                "Meat sliding on the board under a descending blade.",
            ],
            supportedEquipment: chefKnives + ["Carving or slicing knife"],
            unsupportedEquipment: ["Meat cleaver", "Mandoline"],
            notVisuallyAssessable: cutsCannotBeSeen + [
                "How tender the cut inherently is. Ask what it is rather than guessing from "
                    + "appearance.",
                "Whether it has been cooked to the right doneness, which is a thermometer "
                    + "question and not this lesson.",
            ],
            confidenceFloor: 0.55,
            passSummary: "Cut across the grain, fibres short on the face.",
            variationSummary: "Sliced on a bias, and still crossing the grain.",
            outcomeTolerance: [
                "Home standard: the fibres on the cut face are visibly short stubs rather than "
                    + "long strands. Exact angle does not matter.",
            ]
        ),
        retryFraming:
            "Hold one slice up flat so I can see the cut face, and I will tell you which way "
            + "the fibres are running."
    )

    // MARK: - Mirepoix challenge

    static let knifeMirepoix = SkillVisualCheck(
        id: "knife.mirepoix.result",
        assessmentMode: .outcome,
        framingInstruction: "When it is all cut, put the three piles side by side on the board.",
        photoFraming:
            "Put the three piles side by side and take one photo straight down at them.",
        setupNeeds:
            ", and have onion, carrot and celery on your board.",
        outcomeFraming:
            "Look straight down so I can see all three together and compare them.",
        requiredVisibility: [.result],
        helpfulVisibility: [.workSurface, .ingredient],
        observations: [
            SkillObservation(
                region: .result,
                id: "threePiles",
                question:
                    "Are there three separate piles of vegetable, or has it been mixed together or left incomplete? `three` or `notThree`. Say cannotTell if you cannot see the board.",
                answers: ["three", "notThree", "cannotTell"],
                correct: "three"
            ),
            SkillObservation(
                region: .result,
                id: "onionDouble",
                question:
                    "Is the onion pile roughly twice the size of each of the other two? `double` or `notDouble`. Say cannotTell if you cannot compare the piles.",
                answers: ["double", "notDouble", "cannotTell"],
                correct: "double"
            ),
            SkillObservation(
                region: .result,
                id: "consistentWithin",
                question:
                    "Within each pile, are the pieces a similar size to each other? `consistent` or `mixed`. Say cannotTell if you cannot see the pieces.",
                answers: ["consistent", "mixed", "cannotTell"],
                correct: "consistent"
            ),
        ],
        parts: [
            SkillCheckPart(region: .result, label: "Three piles, sized for the cook", id: "size"),
            SkillCheckPart(region: .result, label: "Roughly twice as much onion", id: "ratio"),
            SkillCheckPart(region: .result, label: "Consistent within each vegetable", id: "even"),
        ],
        rubric: SkillVisualRubric(
            subject: "cut onion, carrot and celery for a mirepoix, in three piles",
            targetTechnique: [
                "Roughly two parts onion to one part carrot to one part celery, by volume.",
                "The pieces are sized for how long the dish will cook, and reasonably "
                    + "consistent within each vegetable.",
            ],
            acceptableVariations: [
                "A different ratio for a different cuisine or dish. Two to one to one is a "
                    + "useful French baseline, not a law, and plenty of good cooking ignores it.",
                "Large rustic pieces for a long stock, or small ones for a quick sauce. Both "
                    + "are right for their job, and the size is a decision rather than a skill "
                    + "level.",
                "Substituting or adding leek, fennel or celery leaf. That is a different "
                    + "aromatic base rather than a wrong mirepoix, and it may be exactly what "
                    + "the recipe wants.",
                "The three vegetables being cut to different sizes from one another, if the "
                    + "harder ones are smaller so everything softens together.",
            ],
            // No hand safety mistake here on purpose. This look is three
            // finished piles on a board, so there is no hand and no blade in
            // any of these frames: carrying the shared safety correction would
            // be a rule that could never fire. The knife safety coverage lives
            // in the cuts this challenge is built from.
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "sizeMismatchedToCook",
                    observation:
                        "Some pieces are much larger than the rest, enough that they would not "
                        + "soften in the same time.",
                    correction:
                        "Cut the largest pieces down. They will not soften in the same time "
                        + "as the rest.",
                    rationale:
                        "A mirepoix is there to dissolve into the background. Anything that is "
                        + "still recognisable at the end did not do its job.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "ratioWayOff",
                    observation:
                        "The proportions are far from two parts onion to one each of carrot "
                        + "and celery, for a dish that called for a classical mirepoix.",
                    correction:
                        "For a classical mirepoix, bring the onion up to about half of "
                        + "the total.",
                    rationale:
                        "Onion is the sweet, soft backbone. Carrot pushes it sweeter and celery "
                        + "pushes it greener, so too much of either takes over a base that is "
                        + "meant to disappear.",
                    isContextual: true,
                    severity: .efficiency,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A fingertip or thumb visibly against the cutting edge.",
                "A round vegetable rolling under a descending blade.",
            ],
            supportedEquipment: chefKnives,
            unsupportedEquipment: notForChefKnifeWork,
            notVisuallyAssessable: cutsCannotBeSeen + [
                "The actual ratio by weight, as opposed to how the piles look. Volume in three "
                    + "loose piles is a rough guide and should be treated as one.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Good mirepoix, sized to cook together.",
            variationSummary: "Their own proportions, and cut to soften evenly.",
            outcomeTolerance: [
                "Home standard: onion visibly the largest share, and each vegetable consistent "
                    + "within its own pile. Do not measure the ratio precisely from a photograph.",
            ]
        ),
        retryFraming: "Put the three piles next to each other and look straight down at them."
    )
}
