import Foundation

/// Egg rubrics, authored from `docs/skills-instructor-deliverable.md`.
///
/// This is where `intentBranch` earns its place in the model. Four of these
/// skills have more than one correct answer and the rubrics genuinely invert
/// depending on which one the cook wants: browning is a fault in a French
/// omelette and the entire point of an American one, a crisp lacy edge is the
/// goal of one fried egg and a failure of another, and a jammy yolk is either
/// perfect or undercooked depending on a decision Chef cannot see.
///
/// So she asks first. Every time, before she looks. An app that picks a house
/// style and corrects everybody toward it is not teaching, it is imposing a
/// preference, and eggs are the category where that would happen most.
///
/// Two more instructor calls carried through here:
///
/// - **Salting eggs early is not a mistake.** The common warning that it makes
///   them tough is not supported by controlled testing, and it appears nowhere
///   in these rubrics as a fault.
/// - **A boiled egg cannot be judged through its shell.** Those two skills are
///   assessed on the cut egg and nothing else, and Chef says so rather than
///   pretending to read a pot.
extension SkillVisualCheck {

    // MARK: - Shared

    private static let eggsCannotBeSeen = [
        "How the egg tastes, or whether it is seasoned enough.",
        "The temperature of anything.",
        "How fresh the egg is, which decides more about a poached egg than technique does.",
        "Anything inside an intact shell.",
    ]

    private static let eggPans = [
        "Non-stick pan",
        "Carbon steel",
        "Well seasoned cast iron",
        "Stainless steel pan",
    ]

    // MARK: - Scrambled eggs

    static let eggsScrambled = SkillVisualCheck(
        id: "eggs.scrambled.texture",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Keep the pan in view while you cook, and I will watch the curds forming.",
        setupNeeds:
            ", with your eggs beaten and a pan on the heat.",
        outcomeFraming: "Tip them onto a plate and look down so I can see the texture.",
        requiredVisibility: [.cookingSurface, .ingredient],
        helpfulVisibility: [.fat, .tool, .result],
        observations: [
            SkillObservation(
                region: .result,
                id: "stillGlossy",
                question:
                    "On the plate, do the eggs look soft and glossy, or dry and firm with a matte "
                        + "surface? `glossy` or `dry`. Say cannotTell if you cannot see them clearly.",
                answers: ["glossy", "dry", "cannotTell"],
                correct: "glossy"
            ),
            SkillObservation(
                region: .result,
                id: "evenCurds",
                question:
                    "Are the curds a fairly consistent size, or a mix of large clumps and fine "
                        + "grains? `consistent` or `mixed`. Say cannotTell if the texture is not "
                        + "visible.",
                answers: ["consistent", "mixed", "cannotTell"],
                correct: "consistent"
            ),
            SkillObservation(
                region: .result,
                id: "noWeeping",
                question:
                    "Is there watery liquid separating out around the eggs on the plate? `none` "
                        + "or `weeping`. Say cannotTell if you cannot see the plate around them.",
                answers: ["none", "weeping", "cannotTell"],
                correct: "none"
            ),
            SkillObservation(
                region: .cookingSurface,
                id: "browning",
                question:
                    "Are there brown or tan patches on the curds? `none` or `browned`. Say "
                        + "cannotTell if the colour is not clear.",
                answers: ["none", "browned", "cannotTell"]
            ),
        ],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Curds the size you wanted"),
            SkillCheckPart(region: .cookingSurface, label: "No browning unless you want it"),
            SkillCheckPart(region: .result, label: "Pulled before they looked done", id: "pull"),
        ],
        rubric: SkillVisualRubric(
            subject: "eggs being scrambled in a pan, and the finished texture",
            targetTechnique: [
                "The curd size and the final wetness match the style the cook named.",
                "The set egg is moved back into the liquid rather than left to sit.",
                "They come off the heat while still slightly softer than the target, because "
                    + "the pan finishes them.",
            ],
            acceptableVariations: [
                "Salting the eggs before cooking. The common warning that this makes them "
                    + "tough is not supported by controlled testing, and it must never be "
                    + "raised as a fault.",
                "Milk, cream, water or nothing added. All normal, all a matter of preference.",
                "Constant stirring for small curds, or slow folding for large ones. These are "
                    + "different styles rather than different skill levels.",
                "Butter or oil.",
                "A finished texture anywhere from barely set and custardy to firm and dry, "
                    + "because that is the cook's decision and not ours.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "heatTooHigh",
                    observation:
                        "The eggs are setting faster than the cook can move them, with the "
                        + "edges firming or browning before the middle has begun.",
                    correction:
                        "Lower the heat. They are setting faster than you can move them.",
                    rationale:
                        "Scrambled eggs go from perfect to overdone in about ten seconds on "
                        + "high heat, and there is no way to catch that window. Lower heat is "
                        + "what gives you one at all.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "overcooked",
                    observation:
                        "The eggs are already dry and firm in the pan, past the point the cook "
                        + "said they were going for.",
                    correction:
                        "Take them off now. The pan will finish the last bit for you.",
                    rationale:
                        "Eggs keep cooking in a hot pan after the heat is off. Waiting until "
                        + "they look right in the pan means they are overdone on the plate.",
                    severity: .irreversible,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "unevenRawWhite",
                    observation:
                        "Pockets of clear uncooked white are sitting between set curds, where a "
                        + "fully set style was intended.",
                    correction:
                        "Fold the liquid into the set curds so there are no raw pockets.",
                    rationale:
                        "Unmixed white sets separately and stays clear and slippery, which is "
                        + "the texture nobody is after.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: [
                "A pan handle over the front edge of the hob.",
                "Fat smoking heavily.",
            ],
            supportedEquipment: eggPans,
            unsupportedEquipment: [],
            notVisuallyAssessable: eggsCannotBeSeen,
            confidenceFloor: 0.6,
            passSummary: "Curds and wetness matched the style they asked for.",
            variationSummary: "Their own texture, and they hit it.",
            intentBranch: SkillIntentBranch(
                question: "Soft and creamy, or fluffy and firm?",
                options: [
                    SkillIntentOption(
                        key: "creamy",
                        spokenLabel: "soft, creamy, custardy, French",
                        judgeAgainst:
                            "Small fine curds, glossy, still slightly loose. NO browning at all, "
                            + "and pale colour is correct. Gentle heat and constant movement."),
                    SkillIntentOption(
                        key: "fluffy",
                        spokenLabel: "fluffy, big curds, American, diner style",
                        judgeAgainst:
                            "Large soft folds, fully set but not dry. A little colour is fine "
                            + "and is not a fault."),
                    SkillIntentOption(
                        key: "firm",
                        spokenLabel: "firm, well done, dry",
                        judgeAgainst:
                            "Fully set right through with no liquid egg anywhere. Do not call "
                            + "this overcooked. It is what they asked for, and it is also the "
                            + "conservative choice for anybody avoiding undercooked egg."),
                ],
                defaultKey: "fluffy"),
            outcomeTolerance: [
                "Judge against the style the cook named and nothing else.",
                "For a food safety standard, fully cooked means no visible liquid egg. Anyone "
                    + "cooking for someone vulnerable should be pointed at that, gently, once.",
            ],
            audioSignals: [
                "A quiet gentle sizzle suits the creamy styles. A loud frying sound means a "
                    + "hotter pan, which is evidence and not automatically a failure if a "
                    + "browned style was wanted.",
            ]
        ),
        retryFraming: "Look down into the pan again so I can see the curds."
    )

    // MARK: - Fried egg

    static let eggsFried = SkillVisualCheck(
        id: "eggs.fried.set",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Look down into the pan while it cooks.",
        setupNeeds:
            ", with an egg and a pan on the heat.",
        outcomeFraming: "Slide it onto a plate and look straight down at it.",
        requiredVisibility: [.ingredient],
        helpfulVisibility: [.cookingSurface, .fat, .result],
        observations: [
            SkillObservation(
                region: .ingredient,
                id: "whiteSet",
                question:
                    "Is the white fully set, including the thicker part immediately around the "
                        + "yolk? `set` means opaque throughout. `clearJelly` means there is still "
                        + "translucent uncooked white. Say cannotTell if you cannot see around the "
                        + "yolk.",
                answers: ["set", "clearJelly", "cannotTell"],
                correct: "set"
            ),
            SkillObservation(
                region: .cookingSurface,
                id: "undersideBurnt",
                question:
                    "Look at the underside and the edges. Are they burnt, blackened or blistered? "
                        + "`notBurnt` covers everything from pale through lacy golden brown. `burnt` "
                        + "means black. Say cannotTell if the underside never comes into view.",
                answers: ["notBurnt", "burnt", "cannotTell"],
                correct: "notBurnt"
            ),
            SkillObservation(
                region: .result,
                id: "yolkState",
                question:
                    "What state is the yolk in? `runny`, `jammy` or `hardSet`. Say cannotTell if "
                        + "the yolk is not visible or was broken.",
                answers: ["runny", "jammy", "hardSet", "cannotTell"]
            ),
        ],
        parts: [
            SkillCheckPart(region: .ingredient, label: "White set right up to the yolk"),
            SkillCheckPart(region: .result, label: "Yolk the way you wanted it", id: "yolk"),
            SkillCheckPart(region: .cookingSurface, label: "Underside not burnt"),
        ],
        rubric: SkillVisualRubric(
            subject: "an egg frying in a pan, and the finished egg",
            targetTechnique: [
                "The white is fully set, including the thicker part immediately around "
                    + "the yolk.",
                "The underside matches the style: lacy and browned, or pale and tender.",
                "The yolk is at the state the cook asked for and unbroken unless breaking it "
                    + "was intended.",
            ],
            acceptableVariations: [
                "Crisp brown lacy edges from a hot pan, or a completely pale tender white from "
                    + "a gentle one. Both are correct and they are different dishes.",
                "Sunny side up, over easy, over medium, over hard, basted, or covered "
                    + "and steamed.",
                "Butter, oil, bacon fat or a mixture.",
                "A little browning on the bottom of an egg the cook wanted tender. It is a "
                    + "matter of degree and only worth mentioning if it is scorched.",
                "A broken yolk that the cook broke on purpose.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "burntBottom",
                    observation:
                        "The underside is going dark brown or black while the top of the white "
                        + "is still liquid.",
                    correction:
                        "Lower the heat. The bottom is burning before the white is finished.",
                    rationale:
                        "The white nearest the yolk is the last thing to set, so a pan hot "
                        + "enough to rush it will always burn the bottom first.",
                    severity: .irreversible,
                    requiresVisible: [.ingredient, .cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "rawWhite",
                    observation:
                        "Clear, jelly-like uncooked white is still sitting around the yolk while "
                        + "the rest is set.",
                    correction:
                        "Give the top of that white some heat. Cover the pan for a moment, or "
                        + "spoon some hot fat over it.",
                    rationale:
                        "That thick white right by the yolk needs heat from above to set "
                        + "without overcooking everything underneath it.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "yolkBroken",
                    observation:
                        "The yolk has broken during turning, where it was meant to stay whole.",
                    correction:
                        "Slide the spatula further under before you turn it, so the yolk is "
                        + "not taking the bend.",
                    rationale:
                        "A yolk breaks when the egg folds underneath it. Getting the spatula "
                        + "all the way across means the whole egg moves as one piece.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: [
                "Fat smoking heavily.",
                "A pan handle over the front edge of the hob.",
            ],
            supportedEquipment: eggPans,
            unsupportedEquipment: [],
            notVisuallyAssessable: eggsCannotBeSeen + [
                "Whether the yolk is runny, jammy or set, unless it has been cut or broken. "
                    + "A whole yolk looks much the same from above at every stage.",
            ],
            confidenceFloor: 0.6,
            passSummary: "White set through, yolk as ordered.",
            variationSummary: "Their own style of fried egg, and it came out right.",
            intentBranch: SkillIntentBranch(
                question: "Crispy edges, or soft and tender?",
                options: [
                    SkillIntentOption(
                        key: "crispy",
                        spokenLabel: "crispy, lacy, brown edges",
                        judgeAgainst:
                            "Deep golden brown frilly edges and a browned underside are the "
                            + "GOAL here. Never call that overcooked."),
                    SkillIntentOption(
                        key: "tender",
                        spokenLabel: "soft, tender, no colour",
                        judgeAgainst:
                            "A pale white with no browning anywhere, set but soft. Any real "
                            + "browning means the pan was too hot for this style."),
                ],
                defaultKey: "tender"),
            outcomeTolerance: [
                "Judge against the style named. There is no universal perfect fried egg.",
                "A runny yolk is a legitimate choice, and also is not the fully cooked standard "
                    + "that anybody cooking for a vulnerable person should be following.",
            ]
        ),
        retryFraming: "Look down into the pan again so I can see the white around the yolk."
    )

    // MARK: - Soft-boiled egg

    static let eggsSoftBoiled = SkillVisualCheck(
        id: "eggs.soft-boiled.result",
        assessmentMode: .outcome,
        framingInstruction:
            "I cannot see through a shell, so cook it your way and then open it for me.",
        setupNeeds:
            ", with eggs, a pan of water and a timer.",
        outcomeFraming:
            "Cut it in half or take the top off, and hold it steady where I can see inside.",
        requiredVisibility: [.result],
        helpfulVisibility: [.ingredient, .workSurface],
        observations: [
            SkillObservation(
                region: .result,
                id: "whiteSet",
                question:
                    "Is the white fully set, or is there still clear jelly in it? `set` or "
                        + "`clearJelly`. Say cannotTell if you cannot see the white clearly.",
                answers: ["set", "clearJelly", "cannotTell"],
                correct: "set"
            ),
            SkillObservation(
                region: .result,
                id: "notBlownOut",
                question:
                    "Does the egg look intact, or is there a ragged blown-out tail of white where "
                        + "it escaped through a crack in the shell? `intact` or `blownOut`. Say "
                        + "cannotTell if you cannot see the outside of the egg.",
                answers: ["intact", "blownOut", "cannotTell"],
                correct: "intact"
            ),
            SkillObservation(
                region: .result,
                id: "yolkState",
                question:
                    "What state is the yolk in? `liquid`, `jammy` or `hardSet`. Say cannotTell if "
                        + "the yolk is not visible.",
                answers: ["liquid", "jammy", "hardSet", "cannotTell"]
            ),
        ],
        parts: [
            SkillCheckPart(region: .result, label: "White fully set", id: "white"),
            SkillCheckPart(region: .result, label: "Yolk as loose as you wanted", id: "yolk"),
        ],
        rubric: SkillVisualRubric(
            subject: "a soft-boiled egg that has been opened",
            targetTechnique: [
                "The white is fully set, with no clear jelly left.",
                "The yolk is at the state the cook was aiming for, from liquid through jammy.",
                "The shell is intact rather than cracked and leaking.",
            ],
            acceptableVariations: [
                "Starting in cold water, starting in boiling water, or steaming. All are "
                    + "legitimate methods with completely different timings, so never judge the "
                    + "time, only the result.",
                "Different times for egg size, starting temperature and altitude.",
                "A yolk anywhere from properly runny to fully jammy, depending on what "
                    + "they wanted.",
                "A slightly rough peel, which is about the age of the egg more than the method.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "overcookedYolk",
                    observation:
                        "The yolk is set well past the state the cook described, toward fully "
                        + "hard.",
                    correction:
                        "Cool the next one sooner. This one carried past the stage you "
                        + "were after.",
                    rationale:
                        "The centre keeps cooking in its own heat after it leaves the water, so "
                        + "the last thirty seconds happen on the counter rather than in the pan.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "unsetWhite",
                    observation:
                        "Clear, unset white is still visible, particularly close to the yolk.",
                    correction:
                        "Give the next one more time before you cool it.",
                    rationale:
                        "The white right against the yolk is the last part to set, so it is "
                        + "the honest test of whether the egg had long enough.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A pot boiling over.",
                "A pot handle over the front edge of the hob.",
            ],
            supportedEquipment: ["Saucepan", "Steamer basket"],
            unsupportedEquipment: [],
            notVisuallyAssessable: eggsCannotBeSeen + [
                "Anything at all about the egg while the shell is intact. This skill cannot be "
                    + "assessed until it is opened, and Chef must say that plainly rather than "
                    + "guessing from the pot.",
            ],
            confidenceFloor: 0.6,
            passSummary: "White set, yolk exactly where they wanted it.",
            variationSummary: "Their own yolk preference, and they hit it.",
            outcomeTolerance: [
                "Judge the yolk against what they said they wanted, not against a fixed idea "
                    + "of soft boiled.",
                "The white must be set. That part is not a preference.",
            ]
        ),
        retryFraming: "Hold the cut half a little steadier and closer so I can see the yolk."
    )

    // MARK: - Hard-boiled egg

    static let eggsHardBoiled = SkillVisualCheck(
        id: "eggs.hard-boiled.result",
        assessmentMode: .outcome,
        framingInstruction: "Cook it your way, then peel it and cut it in half for me.",
        setupNeeds:
            ", with eggs, a pan of water and a timer.",
        outcomeFraming: "Hold the cut half steady where I can see the yolk.",
        requiredVisibility: [.result],
        helpfulVisibility: [.ingredient, .workSurface],
        observations: [
            SkillObservation(
                region: .result,
                id: "yolkSet",
                question:
                    "Is the yolk set right through, pale to golden yellow? `set` means firm all "
                        + "the way in. `soft` means there is still a darker soft or liquid centre. Say "
                        + "cannotTell if you cannot see the middle of the yolk.",
                answers: ["set", "soft", "cannotTell"],
                correct: "set"
            ),
            SkillObservation(
                region: .result,
                id: "noGreyRing",
                question:
                    "Is there a grey-green layer where the yolk meets the white? `none` or "
                        + "`greyGreen`. Say cannotTell if the boundary is not visible.",
                answers: ["none", "greyGreen", "cannotTell"],
                correct: "none"
            ),
        ],
        parts: [
            SkillCheckPart(region: .result, label: "Yolk set right through", id: "set"),
            SkillCheckPart(region: .result, label: "No grey-green ring", id: "ring"),
        ],
        rubric: SkillVisualRubric(
            subject: "a hard-boiled egg cut in half",
            targetTechnique: [
                "The yolk is fully set right through, pale to golden yellow.",
                "The white is firm but still tender rather than bouncy.",
                "There is little or no grey-green layer around the yolk.",
            ],
            acceptableVariations: [
                "Boiling, steaming or pressure cooking.",
                "A faint grey line right at the yolk surface, which is very common and not "
                    + "worth mentioning unless it is a thick band.",
                "A yolk slightly off centre, which is about how the egg sat rather than "
                    + "about technique.",
                "A rough or torn peel, which is mostly the age of the egg.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "greenRing",
                    observation:
                        "A distinct grey-green band is visible around the outside of the yolk.",
                    correction:
                        "Shorten the cook a little next time, or cool them faster. That ring is "
                        + "an overcooking cue.",
                    rationale:
                        "It is a harmless reaction between iron in the yolk and sulfur in the "
                        + "white, and it only happens with prolonged heat. It is not a safety "
                        + "problem and it is a reliable sign the egg went too far.",
                    severity: .cosmetic,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "notFullySet",
                    observation:
                        "The centre of the yolk is still soft or wet, where fully hard "
                        + "was intended.",
                    correction:
                        "Give the next one a few more minutes before you cool it.",
                    rationale:
                        "The very centre is the last part to set. Everything else can look "
                        + "finished while it is still soft.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A pot boiling over.",
                "A pot handle over the front edge of the hob.",
            ],
            supportedEquipment: ["Saucepan", "Steamer basket", "Pressure cooker"],
            unsupportedEquipment: [],
            notVisuallyAssessable: eggsCannotBeSeen + [
                "Anything about the egg before it is opened.",
                "Whether the white is rubbery, which is texture rather than appearance.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Set through, tender white, no grey ring.",
            variationSummary: "Their own method, and it came out well.",
            outcomeTolerance: [
                "A faint line at the yolk surface is normal. Only a clear grey-green band is "
                    + "worth raising, and even then as a cue rather than a fault.",
                "Fully cooked is the conservative food safety standard for eggs, so a fully set "
                    + "yolk is never a criticism.",
            ]
        ),
        retryFraming: "Hold the cut half a little closer so I can see the edge of the yolk."
    )

    // MARK: - Poached egg

    static let eggsPoached = SkillVisualCheck(
        id: "eggs.poached.result",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Look down into the pan as the egg goes in and while it sets.",
        setupNeeds:
            ", with a pan of water, an egg and a small cup.",
        outcomeFraming: "Lift it out on a spoon and hold it still where I can see it.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.ingredient, .result, .tool],
        observations: [
            SkillObservation(
                region: .liquid,
                id: "waterState",
                question:
                    "What is the water doing? `gentleSimmer` means small bubbles rising, surface "
                        + "barely moving. `rollingBoil` means the surface is churning. `still` means no "
                        + "bubbles at all. Say cannotTell if you cannot see the water.",
                answers: ["gentleSimmer", "rollingBoil", "still", "cannotTell"],
                correct: "gentleSimmer"
            ),
            SkillObservation(
                region: .ingredient,
                id: "entryHeight",
                question:
                    "How does the egg go in? `close` means released from a cup or spoon held at "
                        + "or near the water surface. `dropped` means it falls from a height. Say "
                        + "cannotTell if no picture catches it going in.",
                answers: ["close", "dropped", "cannotTell"],
                correct: "close"
            ),
            SkillObservation(
                region: .result,
                id: "whiteGathered",
                question:
                    "Does the white stay gathered around the yolk, or stream away in wispy "
                        + "strands? `gathered` or `streaming`. Say cannotTell if you cannot see the egg "
                        + "in the water.",
                answers: ["gathered", "streaming", "cannotTell"],
                correct: "gathered"
            ),
        ],
        parts: [
            SkillCheckPart(region: .liquid, label: "Water gently simmering, not boiling"),
            SkillCheckPart(region: .ingredient, label: "Egg slid in from close to the water"),
            SkillCheckPart(region: .result, label: "White gathered around the yolk", id: "shape"),
        ],
        rubric: SkillVisualRubric(
            subject: "an egg being poached, and the finished egg on a spoon",
            targetTechnique: [
                "The water is at a gentle simmer, with small bubbles rather than a rolling boil.",
                "The egg goes in from a cup, held close to the surface, rather than dropped.",
                "Most of the white gathers around the yolk instead of streaming away.",
                "It comes out with the white set and is drained.",
            ],
            acceptableVariations: [
                "No vortex. Swirling the water helps with a single egg and is completely "
                    + "optional, and it does not work for several eggs at once.",
                "No vinegar. It firms the white slightly and plenty of good cooks never "
                    + "use it.",
                "Not straining the loose white off first. That is a refinement, not a "
                    + "requirement.",
                "A ragged, rustic shape. A perfect restaurant orb is not the standard and "
                    + "wispy edges are normal.",
                "A yolk anywhere from fully runny to jammy.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "boilingHard",
                    observation:
                        "The water is at a rolling boil and the white is being torn into "
                        + "streamers.",
                    correction:
                        "Lower the water to a gentle simmer. The boil is tearing the "
                        + "white apart.",
                    rationale:
                        "The white needs a few seconds of stillness to set around the yolk. "
                        + "Moving water takes it away before it can.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "dropHigh",
                    observation:
                        "The egg is being dropped into the water from well above the surface.",
                    correction:
                        "Bring the cup right down to the water before you let it go.",
                    rationale:
                        "Falling through air gives the egg speed, and it hits the bottom and "
                        + "spreads before it has begun to set.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient, .liquid]
                ),
                SkillCoachableMistake(
                    key: "underSet",
                    observation:
                        "Large patches of clear, translucent raw white are still visible on the "
                        + "lifted egg.",
                    correction:
                        "Give it another minute. There is still raw white on the outside.",
                    rationale:
                        "The outside of the white sets first, so clear patches on the surface "
                        + "mean it came out early.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: [
                "A pot boiling over.",
                "A pot handle over the front edge of the hob.",
                "A face directly over boiling water.",
            ],
            supportedEquipment: ["Saucepan", "Sauté pan", "Slotted spoon"],
            unsupportedEquipment: [],
            notVisuallyAssessable: eggsCannotBeSeen + [
                "The yolk, which is inside the set white. Whether it is runny cannot be seen "
                    + "until it is cut.",
                "How fresh the egg was, which decides how much the white spreads and is not "
                    + "a fault of the cook.",
            ],
            confidenceFloor: 0.6,
            passSummary: "White gathered and set, yolk still soft inside.",
            variationSummary: "A rustic one, and it held together fine.",
            outcomeTolerance: [
                "Home standard: most of the white is around the yolk, with no large clear raw "
                    + "patches. Wispy edges are normal and are never a fault.",
                "Do not judge against a restaurant-perfect oval. Almost nobody produces one at "
                    + "home and it says nothing about the skill.",
            ]
        ),
        retryFraming: "Lift it up on the spoon again and hold it steady for a second."
    )

    // MARK: - Omelette

    static let eggsOmelette = SkillVisualCheck(
        id: "eggs.omelette.result",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Keep the pan in view while the egg sets.",
        setupNeeds:
            ", with beaten eggs and a pan on the heat.",
        outcomeFraming: "Turn it onto a plate and look straight down at it.",
        requiredVisibility: [.cookingSurface, .ingredient],
        helpfulVisibility: [.result, .fat, .tool],
        observations: [
            SkillObservation(
                region: .cookingSurface,
                id: "stillGlossyWhenFolded",
                question:
                    "At the moment it is folded or rolled, is the surface still slightly glossy "
                        + "and moist, or already dry and fully set? `glossy` or `dry`. Say cannotTell "
                        + "if no picture catches the fold.",
                answers: ["glossy", "dry", "cannotTell"],
                correct: "glossy"
            ),
            SkillObservation(
                region: .result,
                id: "holdsTogether",
                question:
                    "On the plate, is it in one piece, or torn and split open? `onePiece` or "
                        + "`torn`. Say cannotTell if you cannot see it clearly.",
                answers: ["onePiece", "torn", "cannotTell"],
                correct: "onePiece"
            ),
            SkillObservation(
                region: .ingredient,
                id: "surfaceColour",
                question:
                    "What colour is the outside? `pale` for the French style with no colour "
                        + "taken, `golden` for a browned surface. Say cannotTell if the colour is not "
                        + "clear.",
                answers: ["pale", "golden", "cannotTell"]
            ),
        ],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Surface matching your style"),
            SkillCheckPart(region: .cookingSurface, label: "Folded before it dried out"),
            SkillCheckPart(region: .result, label: "Holding together on the plate", id: "intact"),
        ],
        rubric: SkillVisualRubric(
            subject: "an omelette being cooked and turned out",
            targetTechnique: [
                "The beaten egg is spread evenly and the setting edges are pushed in so raw "
                    + "egg runs underneath.",
                "Any filling is modest enough that the egg can close around it.",
                "It is folded or rolled while the surface still has some give.",
                "It holds together well enough to serve.",
            ],
            acceptableVariations: [
                "A completely pale, smooth, soft-centred French omelette, or a browned fluffy "
                    + "folded American one, or a flatter country style. All correct, and they "
                    + "are different dishes rather than different standards.",
                "Rolled, folded in half, or folded in thirds.",
                "Cosmetic seams, tears and patches, which almost every home omelette has.",
                "No filling at all.",
                "Cooking it well done, if that is what they want.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "styleHeatMismatch",
                    observation:
                        "The surface is browning where the cook asked for a pale French "
                        + "omelette, or it is pale and wet where they wanted a set folded one.",
                    correction:
                        "Lower the heat. For the omelette you described I do not want the "
                        + "outside taking colour.",
                    rationale:
                        "The two styles are separated almost entirely by pan temperature. Once "
                        + "an omelette has browned there is no getting back to the other one.",
                    isContextual: true,
                    severity: .irreversible,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "overSetBeforeFold",
                    observation:
                        "The surface has dried out and gone matte, and the edges are cracking "
                        + "rather than bending.",
                    correction:
                        "Fold it now, while the surface still has some flexibility.",
                    rationale:
                        "An omelette has one short window where it is set enough to move and "
                        + "still soft enough to bend. Past it, folding tears it.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "overfilled",
                    observation:
                        "There is far more filling than the sheet of egg can fold around.",
                    correction:
                        "Take some filling out. The egg cannot close around that much.",
                    rationale:
                        "The egg is the container. Once the filling is deeper than the egg is "
                        + "wide, it stops being an omelette and becomes scrambled eggs with "
                        + "extras, which is fine but is not this.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: [
                "A pan handle over the front edge of the hob.",
                "Fat smoking heavily.",
            ],
            supportedEquipment: ["Non-stick pan", "Carbon steel", "Well seasoned cast iron"],
            unsupportedEquipment: [
                "A large stainless pan with no fat, where any omelette will stick regardless "
                    + "of technique.",
            ],
            notVisuallyAssessable: eggsCannotBeSeen + [
                "The inside of a folded omelette, which is the part that decides whether a "
                    + "French one is right. Ask rather than claiming.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Set, folded in time, and matching the style asked for.",
            variationSummary: "Their own style of omelette, and it worked.",
            intentBranch: SkillIntentBranch(
                question: "French style, pale and soft in the middle, or American, "
                    + "folded and set?",
                options: [
                    SkillIntentOption(
                        key: "french",
                        spokenLabel: "French, pale, soft centre, rolled",
                        judgeAgainst:
                            "Smooth pale yellow surface with NO browning anywhere, rolled, soft "
                            + "and slightly loose in the middle. Any brown colour is a real "
                            + "fault here."),
                    SkillIntentOption(
                        key: "american",
                        spokenLabel: "American, folded, set through, filled",
                        judgeAgainst:
                            "Light golden colour is fine and expected, folded in half around a "
                            + "filling, fully set. Do not call the colour a mistake."),
                ],
                defaultKey: "american"),
            outcomeTolerance: [
                "Intact enough to serve. Cosmetic seams and small tears are minor and should "
                    + "not be raised unless the cook asks.",
                "Judge the colour ONLY against the style they named.",
            ]
        ),
        retryFraming: "Look down into the pan again so I can see the surface of the egg."
    )

    // MARK: - Egg mastery challenge

    static let eggsChallenge = SkillVisualCheck(
        id: "eggs.challenge.result",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Tell me what you are going for before each egg, then cook it with the pan in view.",
        setupNeeds:
            ", with several eggs, butter and a pan on the heat.",
        outcomeFraming: "Put it on a plate and look down at it before you start the next one.",
        requiredVisibility: [.ingredient],
        helpfulVisibility: [.cookingSurface, .result, .fat],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Target named before cooking"),
            SkillCheckPart(region: .result, label: "Result matched the target", id: "hit"),
            SkillCheckPart(region: .cookingSurface, label: "Heat adjusted between eggs"),
        ],
        rubric: SkillVisualRubric(
            subject: "a series of eggs cooked to stated targets",
            targetTechnique: [
                "The cook names the texture they are going for BEFORE each egg.",
                "Each egg lands close to the target they named.",
                "The heat is adjusted between eggs rather than left where the last one "
                    + "needed it.",
                "They can say what they changed and why.",
            ],
            acceptableVariations: [
                "Any three styles they like. The point is naming a target and hitting it, not "
                    + "which targets they choose.",
                "A poached egg instead of an omelette, or the other way round.",
                "Cooking them one at a time at their own pace.",
                "Missing one target and saying so. Recognising the miss is most of the skill.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "noTargetNamed",
                    observation:
                        "The cook starts an egg without saying what texture they are aiming for.",
                    correction:
                        "Tell me what you are going for before you start this one.",
                    rationale:
                        "Without a stated target there is nothing to hit, and no way for either "
                        + "of us to tell whether it worked.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "heatNeverAdjusted",
                    observation:
                        "The burner has been left at the same setting across eggs that need "
                        + "very different heat.",
                    correction:
                        "Change the heat before this one. It needs a different pan temperature "
                        + "from the last.",
                    rationale:
                        "This challenge is a heat control test. Cooking three different eggs on "
                        + "one setting means at most one of them can be right.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface]
                ),
            ],
            safetySignals: [
                "A pan handle over the front edge of the hob.",
                "Fat smoking heavily.",
            ],
            supportedEquipment: eggPans,
            unsupportedEquipment: [],
            notVisuallyAssessable: eggsCannotBeSeen + [
                "Whether the cook actually hit the texture they meant, in the cases where the "
                    + "difference is in the mouth. Ask them.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Named the target each time, and hit it.",
            variationSummary: "Their own three, and they landed where they said they would.",
            outcomeTolerance: [
                "Pass when each egg is recognisably the thing they said they were making.",
                "This is not a test of whether they can make a restaurant egg. It is a test of "
                    + "whether they can decide on one and then produce it.",
            ]
        ),
        retryFraming: "Hold the plate still for a second so I can see the texture."
    )
}
