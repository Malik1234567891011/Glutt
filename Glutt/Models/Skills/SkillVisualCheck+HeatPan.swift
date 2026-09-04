import Foundation

/// Rubrics for reading a pan: preheating it, knowing when it is ready, and
/// reading the fat in it. Authored from `docs/skills-instructor-deliverable.md`.
///
/// This is the category the instructor expected to be our strongest, and the
/// reason is colour. A roux, a sear, browning butter and caramelising onions all
/// move along a continuous visible scale, which is exactly what a camera is good
/// at and exactly what a beginner cannot yet name. Where a knife rubric spends
/// its effort on what NOT to correct, these spend it on describing a colour
/// precisely enough that somebody can match what they are looking at.
///
/// Three limits shape every rubric here and are repeated because they are easy
/// to forget once a pan looks impressive:
///
/// - **Temperature is not visible.** Not the pan's, not the oil's, not the
///   food's. Everything here is inference from behaviour, and where the answer
///   actually matters it is a thermometer question.
/// - **A dark pan hides most of this.** Cast iron and dark non-stick destroy the
///   contrast the whole assessment rests on, so confidence drops and the rubric
///   says so rather than guessing harder.
/// - **Sound is real evidence and never sufficient.** Hood fans, music, pan
///   material and microphone gain all move it. It raises or lowers confidence in
///   something already seen. It never fails anybody on its own.
extension SkillVisualCheck {

    // MARK: - Shared pieces

    static let panCannotBeSeen = [
        "The actual temperature of the pan, the fat, or the food. Nothing in an image gives "
            + "you degrees, and guessing at them is the fastest way to be confidently wrong.",
        "How hot the burner is set. Even when the dial is in shot, the number on it means "
            + "different things on different stoves and says nothing about what the pan is doing.",
        "Taste, seasoning, or how salty anything is.",
        "Smell, including the nutty aroma that tells a cook their butter is ready.",
        "Anything under a lid, behind an oven door, or on the underside of the food.",
    ]

    static let panEquipment = [
        "Stainless steel pan",
        "Cast iron",
        "Carbon steel",
        "Non-stick pan",
        "Enamelled cast iron",
    ]

    /// Named as a limit rather than as unsupported equipment: a dark pan does
    /// not make the lesson wrong, it makes the camera worse at it, and the
    /// honest response is lower confidence rather than a refusal.
    static let darkPanCaveat =
        "A dark pan, especially cast iron or dark non-stick, hides most of the colour this "
        + "assessment depends on. When the pan is dark, lower your confidence and say what you "
        + "are unsure of rather than committing to a colour you cannot really see."

    // MARK: - Read oil in a pan

    static let heatOil = SkillVisualCheck(
        id: "heat.oil.film",
        assessmentMode: .process,
        framingInstruction:
            "Tilt the pan gently so the oil runs across it, and look down while it moves.",
        setupNeeds:
            " and get your pan on the heat.",
        requiredVisibility: [.cookingSurface, .fat],
        helpfulVisibility: [.ingredient],
        observations: [
            SkillObservation(
                region: .fat,
                id: "coverage",
                question:
                    "When the pan is tilted, does the oil run as a continuous film across the "
                        + "base, or are there dry bare patches it does not reach? `continuous` or "
                        + "`barePatches`. Say cannotTell if you cannot see the base.",
                answers: ["continuous", "barePatches", "cannotTell"],
                correct: "continuous"
            ),
            SkillObservation(
                region: .ingredient,
                id: "depth",
                question:
                    "How much oil is there? `thinFilm` means just enough to coat the base. "
                        + "`pooled` means deep enough that food would sit in a pool of it. Say "
                        + "cannotTell if you cannot judge the depth.",
                answers: ["thinFilm", "pooled", "cannotTell"],
                correct: "thinFilm"
            ),
            SkillObservation(
                region: .cookingSurface,
                id: "notSmoking",
                question:
                    "Is the oil actively giving off smoke? `notSmoking` or `smoking`. Say "
                        + "cannotTell if you cannot see above the pan.",
                answers: ["notSmoking", "smoking", "cannotTell"],
                correct: "notSmoking"
            ),
        ],
        parts: [
            SkillCheckPart(region: .fat, label: "A thin film, right across the base"),
            SkillCheckPart(region: .cookingSurface, label: "No dry bare patches"),
            SkillCheckPart(region: .ingredient, label: "Not sitting in a pool", id: "pool"),
        ],
        rubric: SkillVisualRubric(
            subject: "the oil in a pan, and how much of the base it is covering",
            targetTechnique: [
                "Enough oil to make a thin continuous film under the food, unless the food is "
                    + "supplying its own fat.",
                "The oil moves when the pan is tilted, and there are no dry bare patches where "
                    + "the food will stick.",
                "Hot enough for the job and below actively smoking.",
            ],
            acceptableVariations: [
                "Wildly different amounts of oil. Non-stick needs almost none, stainless needs "
                    + "a real film, and a fatty steak may need none added at all.",
                "Adding more oil partway through. Mushrooms and aubergine drink it and then "
                    + "give it back, and topping up mid-cook is correct rather than a mistake "
                    + "in the original measure.",
                "Deliberately shallow frying, where a pool of oil is the point.",
                "Butter, ghee, clarified butter, or any fat instead of oil.",
                "A cook who has measured rather than poured by eye.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "smokingOil",
                    observation: "The oil is actively smoking in the pan.",
                    correction:
                        "Lower the heat and let that oil come back below smoking before "
                        + "you cook.",
                    rationale:
                        "Smoking oil is breaking down. Everything cooked in it picks up that "
                        + "acrid taste, and it does not go away later.",
                    severity: .irreversible,
                    requiresVisible: [.fat]
                ),
                SkillCoachableMistake(
                    key: "dryPan",
                    observation:
                        "Bare dry patches of pan are visible under or between the food, with "
                        + "no film of fat on them.",
                    correction:
                        "Add just enough oil to restore a thin film under the food.",
                    rationale:
                        "The fat is what actually carries heat from the pan into the food. A "
                        + "dry patch is where things stick and tear rather than release.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface, .fat]
                ),
                SkillCoachableMistake(
                    key: "poolingOil",
                    observation:
                        "The food is sitting in a deep pool of oil rather than on a film of it, "
                        + "for what was meant to be a sauté.",
                    correction:
                        "You have more oil than this needs. Pour some off before it starts "
                        + "frying rather than sautéing.",
                    rationale:
                        "Past a film, the extra oil is not helping the cooking, it is just "
                        + "ending up in the food and on the plate.",
                    isContextual: true,
                    severity: .efficiency,
                    requiresVisible: [.fat]
                ),
            ],
            safetySignals: [
                "Water being added to a pan holding substantial hot oil.",
                "Oil igniting, or smoking heavily enough to suggest it is about to.",
                "A cook moving toward a pan fire with water. Stop immediately.",
            ],
            supportedEquipment: panEquipment,
            unsupportedEquipment: ["Deep fryer"],
            notVisuallyAssessable: panCannotBeSeen + [
                darkPanCaveat,
                "Which fat is in the pan, unless the cook says. Oils look much alike once hot.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Good thin film, right across the pan.",
            variationSummary: "Their own amount, and it covered what it needed to.",
            audioSignals: [
                "A steady even sizzle across the pan supports good coverage. Sizzle in one "
                    + "area only can mean the fat has pooled to one side of a pan that is not "
                    + "sitting flat.",
            ]
        ),
        retryFraming: "Tilt it once more, a bit slower, and keep looking down at the base."
    )

    // MARK: - Avoid crowding

    static let heatCrowding = SkillVisualCheck(
        id: "heat.crowding.layout",
        assessmentMode: .process,
        framingInstruction: "Look straight down into the pan so I can see how it is loaded.",
        setupNeeds:
            ", with your pan hot and the food ready to go in.",
        requiredVisibility: [.cookingSurface, .ingredient],
        helpfulVisibility: [.liquid, .fat],
        observations: [
            SkillObservation(
                region: .ingredient,
                id: "notStacked",
                question:
                    "Is every piece lying flat on the pan, or are some sitting on top of others? "
                        + "`flat` or `stacked`. Say cannotTell if you cannot see the whole pan.",
                answers: ["flat", "stacked", "cannotTell"],
                correct: "flat"
            ),
            SkillObservation(
                region: .cookingSurface,
                id: "gapsVisible",
                question:
                    "Is there visible bare pan between the pieces? `visible` or `packed`. Say "
                        + "cannotTell if you cannot see the pan surface.",
                answers: ["visible", "packed", "cannotTell"],
                correct: "visible"
            ),
            SkillObservation(
                region: .liquid,
                id: "noPooling",
                question:
                    "Is liquid collecting in the pan around the food? `dry` means the base is "
                        + "essentially dry and sizzling. `pooling` means visible liquid. Say cannotTell "
                        + "if you cannot see the base.",
                answers: ["dry", "pooling", "cannotTell"],
                correct: "dry"
            ),
        ],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Nothing stacked on top of anything else"),
            SkillCheckPart(region: .cookingSurface, label: "Pan surface visible between pieces"),
            SkillCheckPart(region: .liquid, label: "No pooling liquid", id: "dry"),
        ],
        rubric: SkillVisualRubric(
            subject: "how much food is in a pan, and whether it is browning or steaming",
            targetTechnique: [
                "Each piece has real contact with the hot pan.",
                "There is enough exposed pan that the moisture coming out of the food can "
                    + "evaporate rather than collecting.",
                "Nothing is stacked on top of anything else where browning is the point.",
                "The pan keeps an active sizzle instead of filling with liquid and steam.",
            ],
            acceptableVariations: [
                "Pieces touching or briefly overlapping. Space between every single piece is "
                    + "not the rule, and thin vegetables that get tossed regularly are fine "
                    + "packed fairly close.",
                "A genuinely full pan for braising, wilting greens, sweating onions or "
                    + "steaming. None of those follow searing rules and a full pan is correct.",
                "A powerful burner and a wide heavy pan carrying more food than a small "
                    + "domestic hob could.",
                "A sparsely loaded pan. That is never a mistake in itself, so do not correct "
                    + "somebody for cooking two things in a big pan.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "steamingInsteadOfBrowning",
                    observation:
                        "Liquid has pooled in the pan, the food is pale, and there is visible "
                        + "steam rather than active frying.",
                    correction:
                        "Take some of the food out and cook it in two batches, so this moisture "
                        + "can boil off.",
                    rationale:
                        "Food cannot brown above the boiling point of the water sitting around "
                        + "it. While that liquid is in the pan you are boiling, whatever the "
                        + "burner says.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "stackedSear",
                    observation:
                        "Pieces are resting on top of one another rather than each touching "
                        + "the pan.",
                    correction:
                        "Give every piece its own contact with the pan. The ones on top "
                        + "cannot brown.",
                    rationale:
                        "Browning happens where food touches hot metal. A piece sitting on "
                        + "another piece is being steamed by it.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: [
                "A pan so overloaded that food is falling onto the burner.",
                "A pan handle over the front edge of the hob.",
            ],
            supportedEquipment: panEquipment,
            unsupportedEquipment: ["Deep fryer", "Oven roasting tray"],
            notVisuallyAssessable: panCannotBeSeen + [
                "Whether the food was wet when it went in, which causes the same pooling as "
                    + "crowding and needs a different fix. Ask.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Well loaded pan, everything touching the base.",
            variationSummary: "Packed their own way, and still browning rather than steaming.",
            audioSignals: [
                "A strong sizzle collapsing into a soft wet simmer after loading is the "
                    + "clearest sign a pan has been overloaded.",
                "Distinguish a brief dip, which is just the pan giving up heat to cold food "
                    + "and recovering, from a sustained wet sound that never comes back.",
            ]
        ),
        retryFraming: "Look straight down into the pan again so I can see the whole base."
    )

    // MARK: - Read butter in a pan

    static let heatButter = SkillVisualCheck(
        id: "heat.butter.stage",
        assessmentMode: .process,
        framingInstruction:
            "Tilt the pan so the butter pools where I can see its colour, or lift a spoonful "
            + "if the pan is dark.",
        setupNeeds:
            ", get your pan on the heat, and have your butter ready.",
        requiredVisibility: [.fat],
        helpfulVisibility: [.cookingSurface, .ingredient],
        observations: [
            SkillObservation(
                region: .cookingSurface,
                id: "noBlackSpecks",
                question:
                    "Are there black specks in the butter or on the pan base? `none` or "
                        + "`blackSpecks`. Say cannotTell if the pan is too dark to judge.",
                answers: ["none", "blackSpecks", "cannotTell"],
                correct: "none"
            ),
            SkillObservation(
                region: .cookingSurface,
                id: "notSmoking",
                question:
                    "Is the pan giving off visible smoke? `notSmoking` or `smoking`. Say "
                        + "cannotTell if you cannot see above the pan.",
                answers: ["notSmoking", "smoking", "cannotTell"],
                correct: "notSmoking"
            ),
            SkillObservation(
                region: .fat,
                id: "stage",
                question:
                    "Which stage is the butter at? `melting`, `foaming` for pale yellow and "
                        + "bubbling, `goldenSolids` for browning milk solids, `brown` for full brown "
                        + "butter, or `burnt` for black and acrid. Say cannotTell if you cannot see the "
                        + "colour.",
                answers: ["melting", "foaming", "goldenSolids", "brown", "burnt", "cannotTell"]
            ),
        ],
        parts: [
            SkillCheckPart(region: .fat, label: "Colour matches what you are going for"),
            SkillCheckPart(region: .cookingSurface, label: "No black specks in the pan"),
        ],
        rubric: SkillVisualRubric(
            subject: "butter cooking in a pan, and which stage it has reached",
            targetTechnique: [
                "The stages run in order: melting, then foaming and sizzling as the water "
                    + "cooks off, then the milk solids beginning to colour, then a nutty brown, "
                    + "then burnt black solids.",
                "Pale yellow and quietly foaming is the stage for eggs and gentle cooking.",
                "Golden brown solids with a nutty smell is brown butter, and it is a deliberate "
                    + "destination rather than a stage on the way somewhere.",
                "Black specks and acrid smoke is burnt, and it is not recoverable.",
                "The heat comes down or the pan comes off before the target stage arrives, "
                    + "because butter moves faster than a cook can react at the end.",
            ],
            acceptableVariations: [
                "Butter deliberately kept pale. For scrambled eggs or a delicate fish, pale "
                    + "foaming butter is exactly right and is not undercooked.",
                "Clarified butter and ghee, which have had the milk solids removed and so "
                    + "barely brown at all. A pale clarified butter is not a cook being timid.",
                "Cultured and higher-water butters, which foam more and for longer.",
                "Butter blended with oil to raise the temperature it tolerates.",
                "Stopping anywhere along the colour scale, because where to stop is decided by "
                    + "the dish and not by the butter.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "burntButter",
                    observation:
                        "The milk solids have gone black rather than brown, with dark specks "
                        + "in the pan and acrid smoke coming off it.",
                    correction:
                        "Start that butter again. Those milk solids are burnt rather than "
                        + "browned, and they will make the whole dish bitter.",
                    rationale:
                        "Brown butter and burnt butter are the same process a few seconds "
                        + "apart. Brown is nutty and sweet, burnt is acrid, and nothing you "
                        + "add afterwards covers it.",
                    severity: .irreversible,
                    requiresVisible: [.fat]
                ),
                SkillCoachableMistake(
                    key: "heatTooHigh",
                    observation:
                        "The butter is foaming violently and the solids are colouring fast and "
                        + "unevenly, racing toward brown.",
                    correction:
                        "Lower the heat now. Butter goes from brown to burnt in seconds.",
                    rationale:
                        "There is no way to catch it at the right moment if it is moving that "
                        + "quickly. Slowing it down is what gives you a window at all.",
                    severity: .irreversible,
                    requiresVisible: [.fat]
                ),
                SkillCoachableMistake(
                    key: "wrongStageForTask",
                    observation:
                        "The butter has been taken well past the pale foaming stage for a job "
                        + "that wanted it pale, such as scrambled eggs.",
                    correction:
                        "Get the eggs in now. You do not want to wait for brown butter unless "
                        + "that flavour is what you are after.",
                    rationale:
                        "Brown butter is a strong, specific flavour. It is wonderful where it "
                        + "belongs and it takes over a dish where it does not.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.fat]
                ),
            ],
            safetySignals: [
                "Butter smoking heavily.",
                "A pan handle over the front edge of the hob.",
            ],
            supportedEquipment: [
                "Stainless steel pan",
                "Light coloured non-stick",
                "Carbon steel",
            ],
            unsupportedEquipment: [],
            notVisuallyAssessable: panCannotBeSeen + [
                "The nutty aroma, which is the cue most cooks actually use for brown butter. "
                    + "Ask about it rather than trying to judge without it.",
                "A dark pan makes butter colour very hard to read. Ask the cook to lift a "
                    + "spoonful into the light rather than committing to a stage you cannot see.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Butter caught at the right stage.",
            variationSummary: "Their own stage, and it suits what they are cooking.",
            audioSignals: [
                "Butter sizzles loudly while its water is cooking off and quietens noticeably "
                    + "as that water goes. The quiet is a useful signal that browning is about "
                    + "to start, but never a doneness cue on its own.",
            ]
        ),
        retryFraming:
            "Tilt the pan again so the butter gathers on one side, or lift a spoonful up "
            + "toward the light."
    )
}
