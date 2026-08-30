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

    // MARK: - Preheat a pan

    static let heatPreheat = SkillVisualCheck(
        id: "heat.preheat.state",
        assessmentMode: .process,
        framingInstruction:
            "Keep the pan in view for the last bit of heating, and show me the cue you use "
            + "before the food goes in.",
        setupNeeds:
            " and get your pan on the heat.",
        requiredVisibility: [.cookingSurface],
        helpfulVisibility: [.fat, .ingredient, .heatSource],
        parts: [
            SkillCheckPart(region: .cookingSurface, label: "Pan heating before the food goes in"),
            SkillCheckPart(region: .fat, label: "Fat moving freely, not smoking", id: "fat"),
            SkillCheckPart(region: .ingredient, label: "Food waiting, not already in", id: "food"),
        ],
        rubric: SkillVisualRubric(
            subject: "a pan being brought up to temperature before food goes in",
            targetTechnique: [
                "The pan is heated deliberately toward the state the next job needs, rather "
                    + "than heated as hot as it will go.",
                "Cast iron and other heavy pans get a longer, gentler preheat so the whole "
                    + "surface catches up rather than just the middle.",
                "The cook has a cue they are waiting for, rather than a length of time.",
            ],
            acceptableVariations: [
                "Cold starts. Skin-on chicken, duck, bacon, some fish and several good steak "
                    + "methods all start in a cold pan on purpose. If the cook says they are "
                    + "cold starting, that is the technique and not a missing preheat.",
                "Preheating dry, or preheating with the fat already in. Both are normal.",
                "Non-stick heated gently rather than hard. That is what the cookware wants and "
                    + "a cook doing it is following the manufacturer, not being timid.",
                "Very different preheat times. A thin aluminium pan is ready in a minute and "
                    + "cast iron takes five, and neither is a mistake.",
                "Not preheating at all for something that does not need it.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "overheatedEmpty",
                    observation:
                        "The empty pan is visibly smoking or scorching before any fat or food "
                        + "has gone into it.",
                    correction:
                        "Take the pan off the heat for a moment. It is hotter than this "
                        + "job needs.",
                    rationale:
                        "Past a certain point the pan stops helping. The fat will smoke the "
                        + "instant it lands, and anything you put in burns before it browns.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "foodTooEarly",
                    observation:
                        "Food has gone into the pan and there is little or no reaction from it, "
                        + "where a hot start was clearly intended.",
                    correction:
                        "Give the pan another minute before the rest of the food goes in.",
                    rationale:
                        "Food that lands in a cool pan sits there releasing water instead of "
                        + "browning, and once that water is out you are steaming rather than "
                        + "searing for the rest of the cook.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "castIronHotSpot",
                    observation:
                        "A heavy pan shows a strong reaction in the centre and almost none at "
                        + "the edges, so only the middle is up to temperature.",
                    correction:
                        "Give the cast iron more time at a lower setting so the whole surface "
                        + "catches up.",
                    rationale:
                        "Heavy pans hold heat brilliantly and spread it slowly. Rushing one on "
                        + "high gets you a scorching centre and cold edges at the same time.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface]
                ),
            ],
            safetySignals: [
                "A pan handle sticking out over the front edge of the hob where it can be "
                    + "caught.",
                "An empty pan smoking heavily and unattended.",
                "Fat at or past the point of igniting.",
            ],
            supportedEquipment: panEquipment,
            unsupportedEquipment: ["Oven roasting tray", "Wok on a domestic flat hob"],
            notVisuallyAssessable: panCannotBeSeen + [darkPanCaveat],
            confidenceFloor: 0.6,
            passSummary: "Pan brought up properly before the food went in.",
            variationSummary: "Their own approach to the heat, and the pan was ready for it.",
            audioSignals: [
                "A sharp immediate sizzle as the first food lands supports a pan that was "
                    + "ready. A muted response suggests it was not, or that the food was wet.",
            ]
        ),
        retryFraming: "Just look down into the pan for a couple of seconds and I will read it."
    )

    // MARK: - Know when the pan is ready

    static let heatPanReady = SkillVisualCheck(
        id: "heat.pan-ready.cue",
        assessmentMode: .process,
        framingInstruction:
            "Look down into the pan, and put one piece of food in while I am watching.",
        setupNeeds:
            ", get your pan on the heat, and have the food nearby.",
        requiredVisibility: [.cookingSurface],
        helpfulVisibility: [.fat, .ingredient],
        parts: [
            SkillCheckPart(region: .fat, label: "Oil moving freely across the pan"),
            SkillCheckPart(region: .cookingSurface, label: "Not smoking"),
            SkillCheckPart(region: .ingredient, label: "First piece reacts straight away"),
        ],
        rubric: SkillVisualRubric(
            subject: "a pan being tested for readiness, and the first food entering it",
            targetTechnique: [
                "Readiness is judged against the next job. A pan ready for a sear is not the "
                    + "same as a pan ready for eggs.",
                "The oil moves freely and coats the surface when the pan is tilted.",
                "The first piece of food gives a clear but controllable reaction for a hot "
                    + "sauté or sear.",
                "The pan does not need to be smoking. Smoking is past ready for almost "
                    + "everything.",
            ],
            acceptableVariations: [
                "A much quieter pan for delicate work. Eggs, fish and gentle aromatics want "
                    + "less heat and a softer response, and that is correct rather than timid.",
                "Skipping the water drop test entirely. It is optional, it behaves differently "
                    + "on different cookware, and it should never be required.",
                "Not seeing an oil shimmer. Shimmer is subtle and depends heavily on the light "
                    + "in the room, so it must never be the only thing a verdict rests on.",
                "Testing with a small piece of the actual food rather than any formal test.",
                "Judging by time and experience on a stove the cook knows well.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "testBecomesHazard",
                    observation:
                        "Water is being flicked or poured into a pan that already holds hot fat.",
                    correction:
                        "Do not put water into hot oil. Use how the oil moves, or a small piece "
                        + "of the food, to test it instead.",
                    rationale:
                        "Water hitting hot fat turns to steam instantly and throws the fat out "
                        + "of the pan. It is one of the few genuinely dangerous things in "
                        + "ordinary home cooking.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.cookingSurface, .fat]
                ),
                SkillCoachableMistake(
                    key: "smokingOil",
                    observation:
                        "The oil is actively smoking before any food has gone in.",
                    correction:
                        "Pull the pan off the heat. The oil is smoking before the food is "
                        + "even in.",
                    rationale:
                        "Oil past its smoke point is breaking down. It tastes acrid, and it is "
                        + "hotter than anything you are about to cook actually wants.",
                    severity: .irreversible,
                    requiresVisible: [.fat]
                ),
                SkillCoachableMistake(
                    key: "coldEntry",
                    observation:
                        "Food has gone in and is sitting nearly silent, or immediately weeping "
                        + "liquid, where a hot start was intended.",
                    correction:
                        "Take that back out if you can and let the pan recover. We want an "
                        + "immediate sizzle for this one.",
                    rationale:
                        "The first thirty seconds decide whether you get a crust or a grey "
                        + "surface. Once the food has released its water into a cool pan, you "
                        + "cannot get that back.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface, .ingredient]
                ),
            ],
            safetySignals: [
                "Water being introduced to a pan of hot fat.",
                "Fat smoking heavily or showing any sign of igniting.",
                "A pan handle over the front edge of the hob.",
            ],
            supportedEquipment: panEquipment,
            unsupportedEquipment: ["Deep fryer", "Oven roasting tray"],
            notVisuallyAssessable: panCannotBeSeen + [
                darkPanCaveat,
                "Whether the oil is at its smoke point, as opposed to visibly smoking. Only "
                    + "actual visible smoke counts.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Pan was ready, and the food reacted the moment it landed.",
            variationSummary: "Their own way of checking, and the pan was in the right state.",
            audioSignals: [
                "A sharp, immediate sizzle as the first piece lands is the strongest single "
                    + "cue that a pan is ready for searing.",
                "A muted or absent response suggests either a cool pan or wet food, and those "
                    + "two need different fixes, so ask rather than assume.",
            ]
        ),
        retryFraming: "Look down into the pan again and tilt it slightly so I can see the oil."
    )

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
