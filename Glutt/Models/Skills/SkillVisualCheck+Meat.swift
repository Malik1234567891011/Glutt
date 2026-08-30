import Foundation

/// Meat rubrics, authored from `docs/skills-instructor-deliverable.md`.
///
/// One rule outranks everything in this file and it is repeated in every
/// `notVisuallyAssessable` list below, because forgetting it once is the worst
/// thing this app could do: **Chef never certifies that meat is cooked from how
/// it looks.** Not the colour of the crust, not the colour of the juices, not
/// how pink the centre is. Colour is not a safety test. Where doneness matters
/// she asks for a thermometer, every time, and where she can see a cook judging
/// by eye she says so.
///
/// The consumer safety floors she works from: 145F with a three minute rest for
/// whole beef, pork, lamb and veal, 160F for anything minced, 165F for poultry.
/// A cook's own quality target may sit anywhere they like, and she does not
/// argue with it. She only refuses to confuse the two.
extension SkillVisualCheck {

    private static let meatCannotBeSeen = [
        "Whether the meat is cooked, or safe to eat. Colour is not a doneness test and never "
            + "becomes one. This needs a thermometer and Chef must ask for one rather than "
            + "offering an opinion.",
        "The internal temperature.",
        "How salty or well seasoned it is.",
        "How tender the cut inherently is, unless the cook says what it is.",
        "How fresh it is.",
    ]

    private static let meatSafety = [
        "Raw meat juices visibly running onto ready to eat food or a clean surface.",
        "A knife travelling toward the hand holding the meat.",
        "Fat smoking heavily or igniting.",
        "A pan handle over the front edge of the hob.",
    ]

    // MARK: - Season meat

    static let meatSeason = SkillVisualCheck(
        id: "meat.season.coverage",
        assessmentMode: .outcome,
        framingInstruction: "Season it the way you normally would, looking down as you go.",
        setupNeeds:
            ", with the meat on a board and your salt to hand.",
        outcomeFraming: "Now turn it over so I can see both faces and the edges.",
        requiredVisibility: [.ingredient],
        helpfulVisibility: [.workSurface, .guidingHand],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Even coverage, no bare patches", id: "even"),
            SkillCheckPart(region: .ingredient, label: "Edges done too", id: "edges"),
        ],
        rubric: SkillVisualRubric(
            subject: "a piece of meat that has just been seasoned",
            targetTechnique: [
                "The salt is spread evenly across the whole surface rather than sitting in "
                    + "clumps.",
                "The sides and edges are seasoned as well as the two flat faces.",
                "The surface was dry before the salt went on.",
            ],
            acceptableVariations: [
                "Salting right before cooking, or salting hours ahead to dry brine. Both are "
                    + "correct and they do different things.",
                "Seasoning by eye and by pinch, or measuring it. Neither is better.",
                "Very different amounts, because thickness and cut change how much a piece "
                    + "of meat needs.",
                "Pepper and other spices added now or later, depending on how hard the sear "
                    + "is going to be.",
                "Salting from close up rather than from a height, if the coverage is even.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "patchySeasoning",
                    observation:
                        "There are visible clumps of salt in some places and bare unseasoned "
                        + "patches in others.",
                    correction:
                        "Season from a little higher up, and cover the whole surface including "
                        + "the edges.",
                    rationale:
                        "Salt does not move sideways through meat in the time you have. "
                        + "Wherever it lands is where it seasons, so a bare patch stays bland "
                        + "and a clump stays sharp.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "wetSaltWindow",
                    observation:
                        "The salt has drawn moisture to the surface, leaving it visibly wet, "
                        + "and the meat is about to go into a hot pan.",
                    correction:
                        "Either give it much longer, or pat it dry again before it goes in "
                        + "the pan.",
                    rationale:
                        "Salt pulls moisture out first and lets it back in later. The middle of "
                        + "that process is the wettest the surface ever gets, and it is the "
                        + "worst possible moment to try to brown it.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: meatSafety,
            supportedEquipment: ["Any cut of meat or poultry", "Fish fillets"],
            unsupportedEquipment: [],
            notVisuallyAssessable: meatCannotBeSeen + [
                "How much salt has actually gone on, which the camera cannot weigh. Judge "
                    + "evenness rather than quantity.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Seasoned evenly, edges included.",
            variationSummary: "Their own hand with the salt, and the coverage is even.",
            outcomeTolerance: [
                "Even is the standard, not heavy or light. How much salt to use is the cook's "
                    + "decision and cannot be judged from a picture anyway.",
            ]
        ),
        retryFraming: "Turn it over slowly so I can see the whole surface."
    )

    // MARK: - Dry before searing

    static let meatDry = SkillVisualCheck(
        id: "meat.dry.surface",
        assessmentMode: .outcome,
        framingInstruction: "Blot it the way you normally would.",
        setupNeeds:
            ", with the meat on a board and paper towel nearby.",
        outcomeFraming: "Hold it steady and turn it so I can see the light on the surface.",
        requiredVisibility: [.ingredient],
        helpfulVisibility: [.workSurface],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Surface matte, not shiny", id: "matte"),
            SkillCheckPart(region: .ingredient, label: "Folds and creases done too", id: "folds"),
        ],
        rubric: SkillVisualRubric(
            subject: "the surface of a piece of meat about to be seared",
            targetTechnique: [
                "The surface looks matte rather than wet and glossy.",
                "The folds, creases and skin side have been blotted as well as the flat faces.",
            ],
            acceptableVariations: [
                "Meat that has been dry brined and is already dry with no blotting needed.",
                "A marinade deliberately left on, which will change the sear and may be exactly "
                    + "what the cook wants.",
                "Paper towel, a clean cloth, or air drying in the fridge.",
                "Fish, where pressing hard would damage it, so a gentle blot is correct.",
                "A slightly tacky surface from dry brining, which is not the same as wet.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "visibleWetSurface",
                    observation:
                        "The surface is visibly glossy or beaded with moisture, or liquid is "
                        + "pooling on the board underneath.",
                    correction:
                        "Blot that surface until it looks matte before it goes in the pan.",
                    rationale:
                        "All that water has to boil off before anything can brown, and while it "
                        + "does the pan is losing the heat that was going to make the crust.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: meatSafety,
            supportedEquipment: ["Any cut of meat or poultry", "Fish fillets"],
            unsupportedEquipment: [],
            notVisuallyAssessable: meatCannotBeSeen + [
                "How wet the underside is, unless it is turned over.",
                "Whether a shine is moisture or fat, which look similar. When unsure, say so.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Surface matte and ready for the pan.",
            variationSummary: "Dry enough for the pan, however they got it there.",
            outcomeTolerance: [
                "Matte is the bar. Bone dry is not required and not achievable on most meat.",
            ]
        ),
        retryFraming: "Turn it toward the light a little so I can see whether it is still shiny."
    )

    // MARK: - Internal temperature

    static let meatTemperature = SkillVisualCheck(
        id: "meat.temperature.probe",
        assessmentMode: .process,
        framingInstruction:
            "Put the probe in the way you normally would, and look down at it as you do.",
        setupNeeds:
            ", with a thermometer and something cooking to check.",
        requiredVisibility: [.tool, .ingredient],
        helpfulVisibility: [.cookingSurface],
        parts: [
            SkillCheckPart(region: .tool, label: "Tip in the thickest part"),
            SkillCheckPart(region: .ingredient, label: "Clear of bone and pan"),
        ],
        rubric: SkillVisualRubric(
            subject: "a thermometer being used on meat",
            targetTechnique: [
                "The sensing tip reaches the thermal centre of the thickest part.",
                "It is clear of bone, of the pan, and of any large fat pocket.",
                "More than one spot is checked on an irregular piece.",
                "The cook knows both the safety floor and their own quality target, and knows "
                    + "which one they are aiming at.",
                "It is pulled below the target because carryover will take it further.",
            ],
            acceptableVariations: [
                "Any pull temperature the cook chooses for quality, as long as they are not "
                    + "confusing it with the safety floor. A steak at 130F is a choice, not "
                    + "an error.",
                "Instant read or leave-in probe.",
                "Entering from the side on something thin, which is the correct way to get the "
                    + "tip centred.",
                "Checking several times through the cook.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "colourAsSafety",
                    observation:
                        "The cook is judging whether the meat is done by looking at its colour, "
                        + "or at the colour of the juices, rather than measuring it.",
                    correction:
                        "Do not use the colour to call that done. Check the thickest part with "
                        + "the thermometer.",
                    rationale:
                        "Meat changes colour at temperatures that have nothing to do with "
                        + "whether it is safe. Poultry can look done and not be, and can look "
                        + "pink and be perfectly fine.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "touchingBoneOrPan",
                    observation:
                        "The probe is against a bone or has gone through into the pan.",
                    correction:
                        "Back the probe off and measure the meat itself.",
                    rationale:
                        "Bone and pan are both at temperatures that have nothing to do with the "
                        + "meat around them, so the number is meaningless.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.tool, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "probeTooShallow",
                    observation:
                        "Only the tip has entered, or it is in a thin part rather than the "
                        + "thickest.",
                    correction:
                        "Push the sensing tip into the centre of the thickest part.",
                    rationale:
                        "The thickest part is the coolest and the last to be done. Everywhere "
                        + "else reads finished before it is.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.tool, .ingredient]
                ),
            ],
            safetySignals: meatSafety,
            supportedEquipment: ["Instant read thermometer", "Leave-in probe thermometer"],
            unsupportedEquipment: [
                "An oven dial, which measures the air rather than the food.",
            ],
            notVisuallyAssessable: meatCannotBeSeen + [
                "The reading, unless the display is clearly legible in frame.",
                "Where the sensing element sits inside the probe, which varies by model.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Measured properly, in the right place.",
            variationSummary: "Their own target, measured the right way."
        ),
        retryFraming: "Look down at where the probe goes in and hold still for a second."
    )

    // MARK: - Sear meat

    static let meatSear = SkillVisualCheck(
        id: "meat.sear.crust",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Look down into the pan while it sears.",
        setupNeeds:
            ", with your pan hot and the meat patted dry.",
        outcomeFraming: "Lift or turn it so I can see the face that was against the pan.",
        requiredVisibility: [.ingredient],
        helpfulVisibility: [.cookingSurface, .fat, .tool],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Went in dry"),
            SkillCheckPart(region: .result, label: "Deep brown, not black", id: "crust"),
            SkillCheckPart(region: .tool, label: "Centre measured separately", id: "probe"),
        ],
        rubric: SkillVisualRubric(
            subject: "meat being seared, and the crust it developed",
            targetTechnique: [
                "The surface goes in dry enough to brown rather than steam.",
                "It develops a deep brown crust without bitter black patches.",
                "The pan is not crowded.",
                "Doneness is tracked separately with a thermometer. The crust is never treated "
                    + "as evidence of it.",
            ],
            acceptableVariations: [
                "Hot start, frequent flipping, reverse sear or cold start. All produce "
                    + "excellent results and none of them is the correct one.",
                "Turning it often. The rule about leaving it alone is one school's preference "
                    + "rather than physics.",
                "Butter added partway through, with a higher smoke point fat to start.",
                "An uneven crust on a piece of meat that is not flat, which is almost all "
                    + "of them.",
                "Deliberate char, where the cook wants it.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "donenessIgnored",
                    observation:
                        "The cook is deciding the meat is finished based on the crust, without "
                        + "measuring the centre.",
                    correction:
                        "Check the centre temperature now. The crust is not a doneness test.",
                    rationale:
                        "Colour on the outside is about the surface and the pan. It says nothing "
                        + "at all about the middle, and this is the one place where guessing "
                        + "has a real safety cost.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "burningBeforeBrowning",
                    observation:
                        "Black scorched patches and smoke while much of the surface is "
                        + "still pale.",
                    correction:
                        "Lower the heat. We want deep brown rather than black, and the centre "
                        + "cannot keep up with this.",
                    rationale:
                        "Black is not more browned, it is burnt, and it is bitter. Scorching "
                        + "while the rest is pale means the pan is hotter than the meat "
                        + "can use.",
                    severity: .irreversible,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "wetSurface",
                    observation:
                        "Steam is coming off and the surface stays grey and pale.",
                    correction:
                        "Pat the next surface dry before it goes in.",
                    rationale:
                        "The pan is spending its energy boiling water off instead of browning.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "crowding",
                    observation:
                        "The pan is loaded past the point where moisture can escape.",
                    correction:
                        "Take some out and sear it in two batches.",
                    rationale:
                        "A crowded pan traps steam, and steam is the opposite of a sear.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface, .ingredient]
                ),
            ],
            safetySignals: meatSafety,
            supportedEquipment: ["Stainless steel pan", "Cast iron", "Carbon steel"],
            unsupportedEquipment: [
                "Non-stick for a hard sear, which most manufacturers do not want heated "
                    + "that far.",
            ],
            notVisuallyAssessable: meatCannotBeSeen,
            confidenceFloor: 0.6,
            passSummary: "Deep even crust, and the centre measured separately.",
            variationSummary: "Their own searing method, and the crust came out well.",
            outcomeTolerance: [
                "Good: most of the contact face a deep golden to brown, with limited black "
                    + "unless char was wanted.",
                "Bad: pale grey and wet, or bitter black over underdeveloped brown.",
                "A uniform crust is not the standard. Real meat is not flat.",
            ],
            audioSignals: [
                "A loud sustained sizzle supports an active sear. A pan that goes quiet after "
                    + "the meat lands suggests a wet surface or a cool pan.",
            ]
        ),
        retryFraming: "Lift it slightly or tip the pan so I can see the face that was down."
    )

    // MARK: - Baste a steak

    static let meatBaste = SkillVisualCheck(
        id: "meat.baste.butter",
        assessmentMode: .process,
        framingInstruction:
            "Tilt the pan and baste the way you normally would, looking down at it.",
        setupNeeds:
            ", with a steak searing and butter to hand.",
        requiredVisibility: [.cookingSurface, .fat],
        helpfulVisibility: [.ingredient, .tool],
        parts: [
            SkillCheckPart(region: .fat, label: "Butter foaming and golden, not black"),
            SkillCheckPart(region: .cookingSurface, label: "Handle tilted away from you"),
            SkillCheckPart(region: .ingredient, label: "Centre still being watched"),
        ],
        rubric: SkillVisualRubric(
            subject: "a steak being basted with foaming butter",
            targetTechnique: [
                "The butter is foaming and golden to lightly brown, not black.",
                "The pan is tilted with the handle away from the cook, so the fat pools on the "
                    + "far side.",
                "The spoon path is controlled and the fat is going onto the steak.",
                "The centre temperature is still being tracked while this happens.",
            ],
            acceptableVariations: [
                "Aromatics or none. Garlic, thyme and rosemary are traditional and entirely "
                    + "optional.",
                "Any number of bastes. There is no correct count.",
                "Not basting at all, which plenty of excellent steak methods skip.",
                "Butter that has browned deliberately, which is a flavour some cooks want.",
                "Basting with a spoon, or tipping the pan and using the fat that runs.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "unsafeTilt",
                    observation:
                        "The pan is tilted toward the cook's body, with hot fat pooling near "
                        + "the front edge and close to spilling.",
                    correction:
                        "Tilt the handle away from you, so the butter pools on the far side "
                        + "rather than toward your body.",
                    rationale:
                        "A pan of very hot fat tipped toward you has nowhere to go but onto "
                        + "you if your grip slips.",
                    severity: .safety,
                    confidenceFloor: 0.45,
                    requiresVisible: [.cookingSurface, .fat]
                ),
                SkillCoachableMistake(
                    key: "burntBastingButter",
                    observation:
                        "The butter solids in the pan have gone black and the fat is smoking.",
                    correction:
                        "Lower the heat and replace that butter. Burnt butter will not improve "
                        + "the steak, it will make it bitter.",
                    rationale:
                        "You are spooning that fat directly onto the meat, so whatever it "
                        + "tastes of goes straight onto the surface you are about to eat.",
                    severity: .irreversible,
                    requiresVisible: [.fat]
                ),
                SkillCoachableMistake(
                    key: "bastePastTarget",
                    observation:
                        "The basting is continuing well past the point where the steak's centre "
                        + "would have reached the stated target.",
                    correction:
                        "Stop basting and check the centre temperature now.",
                    rationale:
                        "Basting is adding heat as well as flavour. It is very easy to baste a "
                        + "medium rare steak all the way to medium while admiring the butter.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: meatSafety + [
                "Hot fat pooled at the near edge of a tilted pan.",
                "A cook's face directly over a pan of foaming butter.",
            ],
            supportedEquipment: ["Stainless steel pan", "Cast iron", "Carbon steel"],
            unsupportedEquipment: [],
            notVisuallyAssessable: meatCannotBeSeen + [
                "How hot the butter is.",
                "The nutty aroma that tells a cook the butter is where they want it.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Golden foaming butter, pan tilted safely.",
            variationSummary: "Their own basting rhythm, and it stayed under control.",
            audioSignals: [
                "Butter sizzles hard while its water cooks off and quietens as that goes. The "
                    + "quiet is the moment browning starts to run away.",
            ]
        ),
        retryFraming: "Tilt the pan again and hold it for a second so I can see the butter."
    )

    // MARK: - Rest meat

    static let meatRest = SkillVisualCheck(
        id: "meat.rest.handling",
        assessmentMode: .process,
        framingInstruction:
            "Show me where you put it to rest, and how you covered it if you did.",
        setupNeeds:
            ", with the meat just off the heat.",
        requiredVisibility: [.ingredient],
        // cookingSurface is here because `leftInHotPan` is a claim about where
        // the meat is sitting, and that is only sayable if the pan was seen.
        helpfulVisibility: [.workSurface, .tool, .cookingSurface],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Off the heat and left alone"),
            SkillCheckPart(region: .workSurface, label: "Loosely covered, or left open"),
        ],
        rubric: SkillVisualRubric(
            subject: "meat resting after cooking",
            targetTechnique: [
                "It is off the heat and out of the hot pan.",
                "A large roast is given real time before being cut.",
                "A crisp surface is left uncovered or tented loosely rather than wrapped "
                    + "tightly.",
            ],
            acceptableVariations: [
                "Very short rests for small cuts. The walk to the table is enough for a thin "
                    + "steak and a fixed rule like ten minutes for everything is wrong.",
                "No cover at all, which is right whenever crust matters more than heat.",
                "Reverse sear workflows that rest BEFORE the final sear.",
                "Serving something crisp immediately, prioritising the crust over the rest.",
                "Resting on a rack, a warm plate or a board.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "cutsLargeRoastImmediately",
                    observation:
                        "A large roast is being sliced within moments of coming off the heat.",
                    correction:
                        "Give the roast some time before you slice it. It is still carrying "
                        + "heat into the centre.",
                    rationale:
                        "A big piece of meat keeps cooking for a long time after it comes out, "
                        + "and cutting into it early means the middle never gets where you "
                        + "were aiming.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "steamsCrust",
                    observation:
                        "Something with a crisp crust or skin has been wrapped tightly in foil.",
                    correction:
                        "Leave the crisp surface uncovered, or tent it loosely. Tight foil will "
                        + "soften it.",
                    rationale:
                        "Steam has nowhere to go under tight foil, so it goes back into the "
                        + "crust you just spent twenty minutes building.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "leftInHotPan",
                    observation:
                        "The meat is resting in the pan it was cooked in, which is still hot.",
                    correction:
                        "Move it off the hot pan. It is still cooking where it is sitting.",
                    rationale:
                        "A hot pan is a heat source. Resting in one is not resting, it is "
                        + "cooking more slowly.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient, .cookingSurface]
                ),
            ],
            safetySignals: meatSafety,
            supportedEquipment: ["Board", "Rack", "Warm plate"],
            unsupportedEquipment: [],
            notVisuallyAssessable: meatCannotBeSeen + [
                "How long it has actually rested, unless Chef watched the whole time.",
                "What is happening to the temperature inside, which is a thermometer question "
                    + "rather than something a picture shows.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Rested properly, and the crust protected.",
            variationSummary: "Their own approach to resting it, and it suits the cut."
        ),
        retryFraming: "Look down at where it is resting so I can see how it is covered."
    )

    // MARK: - Butterfly a chicken breast

    static let meatButterfly = SkillVisualCheck(
        id: "meat.butterfly.cut",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Angle your head so I can see the blade, the breast and your top hand together "
            + "before you start cutting.",
        setupNeeds:
            ", with a chicken breast on a board and a sharp knife.",
        outcomeFraming: "Open it out like a book and look straight down at it.",
        requiredVisibility: [.tool, .guidingHand],
        helpfulVisibility: [.ingredient, .result, .workSurface],
        parts: [
            SkillCheckPart(region: .guidingHand, label: "Top hand flat and high, never in front"),
            SkillCheckPart(region: .tool, label: "Blade level, going in horizontally"),
            SkillCheckPart(region: .result, label: "Still hinged at the far edge", id: "hinge"),
        ],
        rubric: SkillVisualRubric(
            subject: "a chicken breast being butterflied, and the opened result",
            targetTechnique: [
                "The hand holding the breast is FLAT ON TOP of it and well above the blade, "
                    + "never in front of where the knife is travelling.",
                "The knife goes in horizontally at the thick side and stays level.",
                "It stops short of the far edge so the two halves stay hinged.",
                "The opened breast is a reasonably even thickness.",
            ],
            acceptableVariations: [
                "Cutting all the way through into two separate cutlets. That is a valid and "
                    + "different task, and it is not a failed butterfly if it was intended.",
                "Pounding it flat afterwards, or not.",
                "Trimming the tenderloin off first, or leaving it on.",
                "An uneven thickness at the very thin tail end, which is the shape of the "
                    + "breast rather than the cut.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "bladeTowardPalm",
                    observation:
                        "The knife is travelling horizontally toward the hand holding the "
                        + "breast, with the fingers or palm in the blade's path.",
                    correction:
                        "Stop. Move your top hand so the knife is never travelling toward your "
                        + "palm. Keep it flat on top and high.",
                    rationale:
                        "This is the one cut in ordinary home cooking where the blade moves "
                        + "sideways at your other hand with nothing between them. It is worth "
                        + "getting right before anything else about this cut.",
                    severity: .safety,
                    confidenceFloor: 0.4,
                    requiresVisible: [.tool, .guidingHand]
                ),
                SkillCoachableMistake(
                    key: "cutThroughHinge",
                    observation:
                        "The knife has gone all the way through and the breast is in two "
                        + "separate pieces, where a hinge was intended.",
                    correction:
                        "Stop about a centimetre before the far edge, so it opens like a book.",
                    rationale:
                        "The hinge is what lets you open it flat and keep it as one piece for "
                        + "stuffing or rolling.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
                SkillCoachableMistake(
                    key: "unevenThickness",
                    observation:
                        "The opened breast is still much thicker in one area than the rest.",
                    correction:
                        "Angle the knife toward the thickest area and level it out.",
                    rationale:
                        "Even thickness is the entire reason for doing this. An uneven "
                        + "butterfly cooks just as unevenly as the breast did.",
                    severity: .outcomeCost,
                    requiresVisible: [.result]
                ),
            ],
            safetySignals: meatSafety + [
                "A blade moving horizontally toward a bracing hand.",
                "A chicken breast sliding on the board under a moving knife.",
            ],
            supportedEquipment: ["Western chef's knife", "Gyuto", "Santoku", "Boning knife"],
            unsupportedEquipment: ["Serrated bread knife", "Meat cleaver"],
            notVisuallyAssessable: meatCannotBeSeen + [
                "How sharp the knife is, which matters more here than on most cuts because a "
                    + "dull blade needs force in a direction that is already dangerous.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Opened evenly, hinge intact, hand well clear.",
            variationSummary: "Their own way through it, and it opened evenly.",
            outcomeTolerance: [
                "Home standard: no part more than about half again the thickness of the rest. "
                    + "The thin tail end does not count.",
            ]
        ),
        retryFraming:
            "Hold it open flat and look straight down, and I will read the thickness."
    )

    // MARK: - Cook a great steak

    static let meatSteakChallenge = SkillVisualCheck(
        id: "meat.steak.challenge",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Tell me the centre temperature you are aiming for, then cook it with the pan "
            + "in view.",
        setupNeeds:
            ", with a steak, a hot pan and a thermometer.",
        outcomeFraming:
            "After it has rested, slice it and show me a cut face.",
        requiredVisibility: [.ingredient],
        helpfulVisibility: [.cookingSurface, .result, .tool, .fat],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Target named before starting"),
            SkillCheckPart(region: .result, label: "Deep crust, no bitter char", id: "crust"),
            SkillCheckPart(region: .tool, label: "Centre measured, not guessed", id: "probe"),
        ],
        rubric: SkillVisualRubric(
            subject: "a steak cooked from seasoning through to slicing",
            targetTechnique: [
                "The cook names a target centre temperature before starting.",
                "It goes in dry and seasoned, into a pan hot enough for the method they chose.",
                "It builds a deep brown crust without bitter black patches.",
                "The centre is measured rather than guessed, and it is pulled early enough for "
                    + "carryover to land it on the number.",
                "It rests, and is sliced across the grain if the cut calls for it.",
            ],
            acceptableVariations: [
                "Any searing strategy that suits the thickness: hot start, reverse sear, "
                    + "frequent flipping, cold start.",
                "Any target doneness the cook wants. That is their decision and Chef does not "
                    + "argue with it.",
                "Basting or not.",
                "Any pan that can take the heat.",
                "Serving it whole rather than sliced.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "donenessGuessed",
                    observation:
                        "The steak is being called done from its colour, its feel or the clock, "
                        + "with no measurement.",
                    correction:
                        "Measure the centre before you call it. Everything else is a forecast.",
                    rationale:
                        "This challenge is about landing on a number you named. Without "
                        + "measuring, neither of us can say whether you did.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "chasedCrust",
                    observation:
                        "The steak is still in the pan building colour after the centre has "
                        + "clearly passed the stated target.",
                    correction:
                        "Take it out now. The crust is not worth taking the centre past where "
                        + "you wanted it.",
                    rationale:
                        "Crust and centre are two clocks running at once. Once the middle has "
                        + "arrived, more time is only costing you.",
                    severity: .irreversible,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "noRest",
                    observation:
                        "The steak is being sliced immediately off the pan.",
                    correction:
                        "Give it a moment before you cut it.",
                    rationale:
                        "Even a steak carries a few degrees after it comes off, and the rest is "
                        + "when that finishes rather than when it runs onto the board.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: meatSafety,
            supportedEquipment: ["Stainless steel pan", "Cast iron", "Carbon steel"],
            unsupportedEquipment: ["Non-stick for a hard sear"],
            notVisuallyAssessable: meatCannotBeSeen + [
                "Whether the centre actually landed on the target. That is the thermometer's "
                    + "answer and Chef should ask for the number rather than reading the "
                    + "cut face.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Crust, centre and rest all landed.",
            variationSummary: "Their own method all the way through, and it worked.",
            outcomeTolerance: [
                "Pass on: no safety error, a crust that is mostly brown rather than pale or "
                    + "burnt, a centre the cook reports within a few degrees of the target they "
                    + "named, and one heat adjustment they can explain.",
                "Do not judge the doneness from the cut face. Ask for the number.",
            ],
            audioSignals: [
                "A loud sustained sizzle supports an active sear. A pan that quietens suggests "
                    + "a wet surface or a pan that has lost its heat.",
            ]
        ),
        retryFraming: "Hold a slice up flat so I can see the cut face."
    )
}
