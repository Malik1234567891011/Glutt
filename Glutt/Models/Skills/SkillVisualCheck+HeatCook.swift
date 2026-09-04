import Foundation

/// Rubrics for cooking in the pan once it is hot: sautéing, searing, deglazing,
/// reducing, and the pan sauce that combines all four.
/// Authored from `docs/skills-instructor-deliverable.md`.
///
/// Two instructor corrections run through this file and both are corrections to
/// things the app would otherwise have taught:
///
/// **Searing does not seal in juices.** It is a browning reaction and nothing
/// else. That myth is repeated everywhere, it is wrong, and Chef never says it.
/// Doneness is a separate question answered with a thermometer.
///
/// **There is no single correct searing method.** Hot start, frequent flipping,
/// reverse sear and cold start all produce excellent results, so "leave it alone
/// and do not touch it" is one school's advice presented as physics. Chef does
/// not enforce it.
extension SkillVisualCheck {

    // MARK: - Sauté

    static let heatSaute = SkillVisualCheck(
        id: "heat.saute.motion",
        assessmentMode: .process,
        framingInstruction:
            "Cook normally and keep the pan in view from above for about ten seconds.",
        setupNeeds:
            ", with your pan hot and the food ready to go in.",
        requiredVisibility: [.cookingSurface, .ingredient],
        helpfulVisibility: [.fat, .liquid],
        observations: [
            SkillObservation(
                region: .cookingSurface,
                id: "noPooling",
                question:
                    "Is there liquid pooling in the pan around the food, or is the base "
                        + "essentially dry and sizzling? `sizzling` or `pooling`. Say cannotTell if you "
                        + "cannot see the base of the pan.",
                answers: ["sizzling", "pooling", "cannotTell"],
                correct: "sizzling"
            ),
            SkillObservation(
                region: .fat,
                id: "fatFilm",
                question:
                    "Is there a visible film of fat under and around the food, or is the pan dry? "
                        + "`film` or `dry`. Say cannotTell if you cannot see the pan surface.",
                answers: ["film", "dry", "cannotTell"],
                correct: "film"
            ),
            SkillObservation(
                region: .ingredient,
                id: "colouring",
                question:
                    "Are the pieces taking on brown colour, or still pale and grey? `colouring` "
                        + "or `pale`. Say cannotTell if you cannot see the food clearly.",
                answers: ["colouring", "pale", "cannotTell"],
                correct: "colouring"
            ),
        ],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Colouring, not sitting in liquid"),
            SkillCheckPart(region: .cookingSurface, label: "Pan holding its heat"),
            SkillCheckPart(region: .fat, label: "Enough fat for contact"),
        ],
        rubric: SkillVisualRubric(
            subject: "food being sautéed in a pan, seen from above",
            targetTechnique: [
                "Small or medium pieces cooking relatively quickly in a modest film of fat.",
                "The pan is hot enough to cook and colour rather than sit in a wet simmer.",
                "Food is moved enough to cook evenly, but not so constantly that nothing ever "
                    + "stays in contact long enough to brown.",
                "Heat is adjusted as the load and the moisture in the pan change.",
            ],
            acceptableVariations: [
                "Stirring with a spoon or spatula instead of tossing. Tossing is a party trick "
                    + "as much as a technique and nobody needs it.",
                "A sauté that seeks no colour at all. Delicate aromatics are often cooked "
                    + "deliberately pale, and that is a choice rather than an undercook.",
                "Oil, whole butter, clarified butter, or a blend, depending on the heat and "
                    + "the flavour wanted.",
                "Leaving food undisturbed for stretches, which is correct when browning is "
                    + "the goal.",
                "Cooking in batches rather than all at once.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "heatMismatch",
                    observation:
                        "Either the food is colouring or scorching much faster than it can cook "
                        + "through, or it is sitting in its own released liquid without "
                        + "colouring at all.",
                    correction:
                        "Lower the heat, the outside is colouring before the inside can catch "
                        + "up. Or if it is sitting in liquid, raise it until that boils off.",
                    rationale:
                        "Almost every sauté problem is one of these two, and they look nothing "
                        + "alike in the pan even though both come down to the burner.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "crowding",
                    observation:
                        "The pan is loaded past the point where moisture can escape, so liquid "
                        + "is pooling and the food is pale.",
                    correction:
                        "Take some out and do it in two batches. There is more food here than "
                        + "the pan can dry out.",
                    rationale:
                        "A crowded pan cannot get above the boiling point of the water in it, "
                        + "so nothing browns no matter how high the burner goes.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "constantMovement",
                    observation:
                        "The food is being stirred or tossed continuously, so no piece stays "
                        + "against the pan long enough to take colour.",
                    correction:
                        "Leave it against the pan for a moment. You are moving it faster than "
                        + "it can brown.",
                    rationale:
                        "Browning needs contact time. Constant stirring feels attentive and is "
                        + "the main reason home sautés come out pale.",
                    isContextual: true,
                    severity: .efficiency,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "neglectedMovement",
                    observation:
                        "The food has been left long enough that one face is much darker than "
                        + "the rest and is heading past browned.",
                    correction:
                        "Turn the pieces now. One face is getting all the heat.",
                    rationale:
                        "The opposite failure to over-stirring, and just as common once "
                        + "somebody has been told to leave things alone.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: [
                "Fat smoking heavily or showing signs of igniting.",
                "A pan handle over the front edge of the hob.",
                "Food being added from a height into hot fat.",
            ],
            supportedEquipment: panEquipment,
            unsupportedEquipment: ["Deep fryer", "Oven roasting tray"],
            notVisuallyAssessable: panCannotBeSeen + [darkPanCaveat],
            confidenceFloor: 0.6,
            passSummary: "Good sauté, colouring rather than steaming.",
            variationSummary: "Their own pace with it, and the pan was doing the right thing.",
            audioSignals: [
                "A steady active sizzle throughout supports a sauté that is cooking rather "
                    + "than stewing. A sound that goes soft and wet and stays there suggests "
                    + "the pan has lost its heat or the load is too big.",
            ]
        ),
        retryFraming: "Hold the pan in view from above for a few seconds and carry on cooking."
    )

    // MARK: - Sear

    static let heatSear = SkillVisualCheck(
        id: "heat.sear.crust",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Look down into the pan while it sears, so I can see the surface of the food.",
        setupNeeds:
            ", with your pan hot and the food patted dry.",
        outcomeFraming:
            "Now lift or turn it so I can see the face that was against the pan.",
        requiredVisibility: [.ingredient],
        helpfulVisibility: [.cookingSurface, .fat, .liquid],
        observations: [
            SkillObservation(
                region: .ingredient,
                id: "surfaceDry",
                question:
                    "As the food goes into the pan, does its surface look dry and matte, or wet "
                        + "and glossy? `dry` or `wet`. Say cannotTell if no picture catches it going "
                        + "in.",
                answers: ["dry", "wet", "cannotTell"],
                correct: "dry"
            ),
            SkillObservation(
                region: .result,
                id: "crust",
                question:
                    "Look at the face that was against the pan. Is it `deepBrown` and evenly "
                        + "coloured, `blackened` in patches, or still `pale`? Say cannotTell if that "
                        + "face never comes into view.",
                answers: ["deepBrown", "blackened", "pale", "cannotTell"],
                correct: "deepBrown"
            ),
            SkillObservation(
                region: .cookingSurface,
                id: "crowding",
                question:
                    "Is there visible bare pan between the pieces, or are they packed edge to "
                        + "edge? `spaced` or `packed`. Say cannotTell if you cannot see the whole pan.",
                answers: ["spaced", "packed", "cannotTell"],
                correct: "spaced"
            ),
        ],
        parts: [
            SkillCheckPart(region: .ingredient, label: "Surface dry going in"),
            SkillCheckPart(region: .result, label: "Deep brown crust, not black", id: "crust"),
            SkillCheckPart(region: .cookingSurface, label: "Pan not crowded"),
        ],
        rubric: SkillVisualRubric(
            subject: "food being seared, and the crust it developed",
            targetTechnique: [
                "The surface going in is dry enough that the pan can brown it rather than "
                    + "first boiling water off it.",
                "The food develops a deep brown crust without bitter black patches.",
                "Searing is understood as flavour and colour development. It does NOT seal in "
                    + "juices and Chef never says that it does.",
                "Internal doneness is tracked separately, with a thermometer, and the crust is "
                    + "never treated as evidence of it.",
            ],
            acceptableVariations: [
                "Hot start, frequent flipping, reverse sear, and cold start. All of these are "
                    + "legitimate and produce excellent results. Never insist on one.",
                "Turning the food often. The rule about not moving it is one school's "
                    + "preference, not physics, and frequent flipping cooks very evenly.",
                "Butter added partway through for basting, with a higher smoke point fat used "
                    + "to start the sear.",
                "Deliberate char on some foods and in some cuisines, where the bitterness is "
                    + "wanted.",
                "A crust that is uneven because the food is not flat. Almost no real piece "
                    + "of meat is flat.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "burningBeforeBrowning",
                    observation:
                        "Black scorched patches and smoke are appearing while much of the "
                        + "surface is still pale.",
                    correction:
                        "Lower the heat. We want deep brown rather than black, and right now "
                        + "the outside will be burnt before the centre is anywhere near done.",
                    rationale:
                        "Black is not more browned, it is a different reaction and it tastes "
                        + "bitter. Uneven scorching usually means the pan is far hotter than "
                        + "the food can keep up with.",
                    severity: .irreversible,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "wetSurface",
                    observation:
                        "Visible water or steam is coming off the food and the surface is "
                        + "staying grey and pale rather than browning.",
                    correction:
                        "Pat the next surface dry before it hits the pan.",
                    rationale:
                        "While there is free water on the surface, the pan's energy is going "
                        + "into boiling it off and the food cannot get hot enough to brown.",
                    severity: .outcomeCost,
                    requiresVisible: [.ingredient]
                ),
                SkillCoachableMistake(
                    key: "crowding",
                    observation:
                        "The pan is loaded past the point where moisture can escape, so the "
                        + "food is greying rather than searing.",
                    correction:
                        "Take some out and sear it in two batches.",
                    rationale:
                        "A crowded pan traps steam, and steam is the opposite of a sear.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "donenessIgnored",
                    observation:
                        "The cook is judging whether the food is done from how the crust looks.",
                    correction:
                        "Check the centre temperature now. The crust is not a doneness test.",
                    rationale:
                        "Colour on the outside says nothing about the middle. This is the one "
                        + "place where guessing has a real safety cost rather than just a "
                        + "quality one.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.ingredient]
                ),
            ],
            safetySignals: [
                "Fat smoking heavily or igniting.",
                "A pan handle over the front edge of the hob.",
                "Raw meat juices visibly spreading onto ready to eat food or a clean surface.",
            ],
            supportedEquipment: [
                "Stainless steel pan",
                "Cast iron",
                "Carbon steel",
            ],
            unsupportedEquipment: [
                "Non-stick pan for a hard sear, which most manufacturers do not want heated "
                    + "that far. Say so warmly rather than refusing.",
            ],
            notVisuallyAssessable: panCannotBeSeen + [
                "Whether the food is cooked through. This is a thermometer question and Chef "
                    + "must never certify protein doneness or safety from colour.",
                darkPanCaveat,
            ],
            confidenceFloor: 0.6,
            passSummary: "Deep even crust, no bitter black patches.",
            variationSummary: "Their own searing method, and the crust came out well.",
            outcomeTolerance: [
                "Good: most of the contact surface a deep golden to brown, with limited black "
                    + "unless char was clearly wanted.",
                "Bad: a pale grey wet surface, or a bitter black crust with underdeveloped "
                    + "brown around it.",
                "Do not expect a uniform crust. Real food is not flat and it never sears "
                    + "perfectly evenly.",
            ],
            audioSignals: [
                "A loud sustained sizzle supports an active sear. A quiet pan that goes quieter "
                    + "after the food lands suggests the surface was wet or the pan too cool.",
            ]
        ),
        retryFraming: "Lift the food slightly or tip the pan so I can see the face that was down."
    )

    // MARK: - Deglaze

    static let heatDeglaze = SkillVisualCheck(
        id: "heat.deglaze.fond",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Before you add anything, look down into the pan so I can see what is stuck "
            + "to the bottom.",
        setupNeeds:
            ", once you have browned something and the pan has fond in it.",
        outcomeFraming: "Now show me the base of the pan after you have scraped it.",
        requiredVisibility: [.cookingSurface],
        helpfulVisibility: [.liquid, .tool, .fat],
        observations: [
            SkillObservation(
                region: .cookingSurface,
                id: "fondColour",
                question:
                    "What is stuck to the base of the pan before the liquid goes in? `brownFond` "
                        + "means golden to deep brown stuck-on residue. `blackBurnt` means black "
                        + "carbonised material. `noFond` means the base is essentially clean. Say "
                        + "cannotTell if you cannot see the base.",
                answers: ["brownFond", "blackBurnt", "noFond", "cannotTell"],
                correct: "brownFond"
            ),
            SkillObservation(
                region: .liquid,
                id: "bubbling",
                question:
                    "Once the liquid is in, is it actively bubbling, or sitting flat and still? "
                        + "`bubbling` or `flat`. Say cannotTell if no picture shows the liquid in the "
                        + "pan.",
                answers: ["bubbling", "flat", "cannotTell"],
                correct: "bubbling"
            ),
            SkillObservation(
                region: .tool,
                id: "baseCleared",
                question:
                    "After scraping, is the base of the pan largely clear of stuck-on residue? "
                        + "`cleared` or `stillStuck`. Say cannotTell if you cannot see the base "
                        + "afterwards.",
                answers: ["cleared", "stillStuck", "cannotTell"],
                correct: "cleared"
            ),
        ],
        parts: [
            SkillCheckPart(region: .cookingSurface, label: "Brown bits, not black"),
            SkillCheckPart(region: .liquid, label: "Liquid in and bubbling"),
            SkillCheckPart(region: .tool, label: "Base scraped clean"),
        ],
        rubric: SkillVisualRubric(
            subject: "the base of a pan before and after deglazing",
            targetTechnique: [
                "After browning, excess fat may be poured off while the brown stuck-on fond "
                    + "stays in the pan.",
                "Liquid is added carefully, away from the face, and the pan is not left "
                    + "unattended while it steams.",
                "The fond is scraped loose while the liquid bubbles, so it dissolves into it.",
                "Black burnt residue is not fond and is not worth lifting.",
            ],
            acceptableVariations: [
                "Any liquid. Water, stock, juice, vinegar, beer or wine all deglaze. Wine is "
                    + "not required and a cook using water is not cutting a corner.",
                "A wooden spoon, a silicone spatula or a whisk, depending on the pan.",
                "Non-stick producing very little fond. That is what the coating does and it is "
                    + "not a failure of the cook.",
                "Deglazing cast iron, which is fine for a short deglaze even though long "
                    + "acidic cooking is not ideal for the seasoning.",
                "Leaving some fat in deliberately, when the fat is part of the sauce.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "unsafeLiquidAddition",
                    observation:
                        "A large amount of cold liquid is being poured into a very hot fatty "
                        + "pan, or the cook's face and hands are directly over the pan as it "
                        + "goes in.",
                    correction:
                        "Pull the pan off the heat and add the liquid away from your face.",
                    rationale:
                        "That first moment throws a lot of very hot steam straight upward, and "
                        + "it comes up faster than you can move.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.cookingSurface, .liquid]
                ),
                SkillCoachableMistake(
                    key: "burntFondUsed",
                    observation:
                        "The residue in the pan is black and carbonised rather than golden "
                        + "to deep brown, and it is being deglazed anyway.",
                    correction:
                        "Those bits are black rather than brown. Do not build the sauce on "
                        + "them, they will make the whole thing bitter.",
                    rationale:
                        "Fond is concentrated browning and it is delicious. Carbon is bitter, "
                        + "and once it is in the sauce there is no taking it back out.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "fondLeftStuck",
                    observation:
                        "Brown fond is still visibly stuck to the base after the liquid has "
                        + "gone in and been simmering.",
                    correction:
                        "Scrape the brown layer up while the liquid is bubbling. That is the "
                        + "flavour you are trying to lift.",
                    rationale:
                        "The whole point of deglazing is moving that flavour off the pan and "
                        + "into the sauce. Left stuck, it goes in the washing up.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "tooMuchFat",
                    observation:
                        "A thick layer of fat is floating on the deglazing liquid.",
                    correction:
                        "Pour off the excess fat first and keep the browned bits.",
                    rationale:
                        "Fat and the finished sauce separate rather than combining, so too "
                        + "much of it leaves a greasy layer on top instead of body.",
                    severity: .efficiency,
                    requiresVisible: [.liquid, .fat]
                ),
            ],
            safetySignals: [
                "Alcohol being poured from the bottle directly over a flame or a very hot pan.",
                "A face directly over a pan as cold liquid hits hot fat.",
                "A pan handle over the front edge of the hob.",
            ],
            supportedEquipment: [
                "Stainless steel pan",
                "Cast iron",
                "Carbon steel",
                "Enamelled cast iron",
            ],
            unsupportedEquipment: [],
            notVisuallyAssessable: panCannotBeSeen + [
                "Whether the fond tastes bitter. Very dark brown and actually burnt can look "
                    + "alike, especially in a dark pan. When it is borderline, say so.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Good brown fond, lifted cleanly into the liquid.",
            variationSummary: "Their own liquid and their own method, and the fond came up.",
            outcomeTolerance: [
                "Good: a base that is essentially clean after scraping, with the colour now "
                    + "in the liquid.",
                "Some stubborn spots in the corners are normal and not worth mentioning.",
            ],
            audioSignals: [
                "A sharp hiss as the liquid lands confirms the pan was still hot enough for "
                    + "the fond to release.",
            ]
        ),
        retryFraming: "Tip the pan toward you a little so I can see the base of it."
    )

    // MARK: - Reduce

    static let heatReduce = SkillVisualCheck(
        id: "heat.reduce.body",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Look down into the pan so I can see how hard it is bubbling.",
        setupNeeds:
            ", with the liquid already in the pan.",
        outcomeFraming:
            "Now draw a spoon through it, or lift the spoon out, so I can see how it coats.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.cookingSurface, .tool],
        observations: [
            SkillObservation(
                region: .liquid,
                id: "bubbleRate",
                question:
                    "How hard is it bubbling? `controlled` means a steady simmer or gentle boil. "
                        + "`violent` means it is thrashing and spitting over the sides. `barelyMoving` "
                        + "means almost nothing is happening. Say cannotTell if you cannot see the "
                        + "surface.",
                answers: ["controlled", "violent", "barelyMoving", "cannotTell"],
                correct: "controlled"
            ),
            SkillObservation(
                region: .cookingSurface,
                id: "edgesClean",
                question:
                    "Is there darkened scorched material at the edges where the liquid line sits? "
                        + "`clean` or `scorched`. Say cannotTell if you cannot see the sides of the "
                        + "pan.",
                answers: ["clean", "scorched", "cannotTell"],
                correct: "clean"
            ),
            SkillObservation(
                region: .tool,
                id: "spoonCoat",
                question:
                    "When the spoon is lifted or drawn through, does the liquid coat the back of "
                        + "it, or run straight off like water? `coats` or `runsOff`. Say cannotTell if "
                        + "no picture shows the spoon out of the liquid.",
                answers: ["coats", "runsOff", "cannotTell"],
                correct: "coats"
            ),
        ],
        parts: [
            SkillCheckPart(region: .liquid, label: "Bubbling at a controlled rate"),
            SkillCheckPart(region: .cookingSurface, label: "Nothing catching at the edges"),
            SkillCheckPart(region: .tool, label: "Coats the back of a spoon"),
        ],
        rubric: SkillVisualRubric(
            subject: "a liquid reducing in a pan, and the body it has developed",
            targetTechnique: [
                "The liquid simmers or boils at a controlled rate so water evaporates and "
                    + "flavour concentrates.",
                "The cook watches both the volume and the consistency rather than the clock.",
                "It stops before it scorches, or before the salt and acid become overwhelming.",
                "For a pan sauce without starch, reduction alone can give it body.",
            ],
            acceptableVariations: [
                "A hard rolling boil for a robust stock or water reduction, and a bare simmer "
                    + "for cream or anything emulsified. Both are correct for their liquid.",
                "A wide pan reducing much faster than a narrow one. That is surface area "
                    + "rather than technique.",
                "Reduce by half being about volume, not about reaching a particular thickness.",
                "Stopping short of a classic coating consistency, because plenty of sauces are "
                    + "meant to stay loose.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "scorchingEdges",
                    observation:
                        "The reduction is catching and darkening around the edge of the pan or "
                        + "at the waterline.",
                    correction:
                        "Lower the heat and scrape the edge back into the middle.",
                    rationale:
                        "The edges are where a reduction always catches first, because that is "
                        + "the thinnest layer. Once it burns there it flavours everything.",
                    severity: .irreversible,
                    requiresVisible: [.liquid, .cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "overReduced",
                    observation:
                        "The liquid has gone sticky, syrupy or oily and is well past a "
                        + "sauce consistency.",
                    correction:
                        "Add a splash of water or stock and loosen it back to a "
                        + "sauce consistency.",
                    rationale:
                        "Over-reduction concentrates the salt as well as the flavour, so it "
                        + "goes from intense to inedible quite suddenly. Loosening it is "
                        + "usually a complete fix.",
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "underReduced",
                    observation:
                        "The liquid still runs like a broth and does not cling at all, where "
                        + "body was intended.",
                    correction:
                        "Keep it simmering. It should coat more than that before we stop.",
                    rationale:
                        "Body in a reduction comes from getting the water out. There is no "
                        + "shortcut and stopping early just makes a thin sauce.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "seasonedTooEarly",
                    observation:
                        "The cook has salted heavily before a substantial reduction.",
                    correction:
                        "Hold the rest of the salt until after this has reduced.",
                    rationale:
                        "Reducing removes water and not salt, so whatever you put in early "
                        + "gets stronger as the volume drops.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: [
                "A pan boiling over toward the burner.",
                "A pan handle over the front edge of the hob.",
                "A face directly over a hard boiling reduction.",
            ],
            supportedEquipment: panEquipment + ["Saucepan"],
            unsupportedEquipment: [],
            notVisuallyAssessable: panCannotBeSeen + [
                "How salty or how sharp it has become, which is the thing that actually "
                    + "decides when to stop. Ask the cook to taste a cooled drop.",
                "How much it has reduced, unless the starting level is known. Ask rather "
                    + "than estimate.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Reduced to a good consistency without catching.",
            variationSummary: "Their own consistency, and it suits what they are making.",
            outcomeTolerance: [
                "A useful home cue: it lightly coats the back of a spoon and a finger drawn "
                    + "through leaves a line that holds for a moment.",
                "Plenty of good sauces are looser than that on purpose. Do not treat the "
                    + "spoon-coating test as a universal target.",
            ],
            audioSignals: [
                "A dense continuous bubbling is a hard boil, a more intermittent sound is a "
                    + "simmer. Useful for confirming what you can already see.",
            ]
        ),
        retryFraming: "Lift the spoon out and hold it still for a second so I can see it coat."
    )

    // MARK: - Pan sauce challenge

    static let heatPanSauce = SkillVisualCheck(
        id: "heat.pan-sauce.result",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Work through it normally and keep the pan in view. I will pick up the stages "
            + "as they happen.",
        setupNeeds:
            ", once you have seared something and the pan has fond in it.",
        outcomeFraming:
            "Now lift a spoonful and let it run off, so I can see the body it has.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.cookingSurface, .tool, .fat],
        observations: [
            SkillObservation(
                region: .cookingSurface,
                id: "fondColour",
                question:
                    "What was in the pan at the start? `brownFond` means golden to deep brown "
                        + "stuck-on residue. `blackBurnt` means black carbonised material. `noFond` "
                        + "means the base was essentially clean. Say cannotTell if you cannot see the "
                        + "base before the liquid goes in.",
                answers: ["brownFond", "blackBurnt", "noFond", "cannotTell"],
                correct: "brownFond"
            ),
            SkillObservation(
                region: .liquid,
                id: "spoonCoat",
                question:
                    "When the spoon is lifted, does the sauce coat it, or run straight off like "
                        + "water? `coats` or `runsOff`. Say cannotTell if no picture shows the spoon "
                        + "out of the sauce.",
                answers: ["coats", "runsOff", "cannotTell"],
                correct: "coats"
            ),
            SkillObservation(
                region: .tool,
                id: "cohesive",
                question:
                    "Is there a separate layer of clear fat or oil sitting on or beside the "
                        + "sauce? `cohesive` means it is one uniform sauce. `split` means visible free "
                        + "fat. Say cannotTell if you cannot see the surface clearly.",
                answers: ["cohesive", "split", "cannotTell"],
                correct: "cohesive"
            ),
        ],
        parts: [
            SkillCheckPart(region: .cookingSurface, label: "Started from brown fond"),
            SkillCheckPart(region: .liquid, label: "Reduced to real body"),
            SkillCheckPart(region: .tool, label: "Cohesive, not split or greasy"),
        ],
        rubric: SkillVisualRubric(
            subject: "a pan sauce being built, and the finished sauce",
            targetTechnique: [
                "It starts from golden to brown fond rather than from burnt residue.",
                "Excess fat is managed, poured off or kept deliberately.",
                "The pan is deglazed and the fond scraped into the liquid.",
                "It is reduced until it has real flavour and body.",
                "It is finished off the heat or on low heat if butter or another emulsifier "
                    + "is going in.",
                "The finished sauce clings lightly to food or a spoon rather than leaving a "
                    + "separate greasy puddle.",
            ],
            acceptableVariations: [
                "Any flavour path. Wine is not required and neither are shallots, cream, "
                    + "mustard or herbs.",
                "Finishing with butter or not finishing with butter. Both make good sauces.",
                "Stock based, cream based or water based, all valid.",
                "A naturally thicker sauce from a gelatin rich stock, with no thickener at all.",
                "A deliberately thin pan juice, which is a real thing to want.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "burntFond",
                    observation:
                        "The sauce is being built on black carbonised residue rather than "
                        + "brown fond.",
                    correction:
                        "Do not build on those black bits, they are burnt rather than browned. "
                        + "Start the base again in a clean pan.",
                    rationale:
                        "Bitterness from burnt fond runs through the entire finished sauce and "
                        + "nothing you add later covers it.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "brokenGreasyFinish",
                    observation:
                        "The sauce has split, with visible fat separating out and pooling on "
                        + "the surface rather than staying combined.",
                    correction:
                        "Take it off the heat and whisk in a teaspoon of water. The fat is "
                        + "separating out.",
                    rationale:
                        "A butter finished sauce is an emulsion, and heat is what breaks it. "
                        + "Off the heat with a little water it usually comes straight back.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "waterySauce",
                    observation:
                        "The sauce runs off a spoon like broth with no body at all.",
                    correction:
                        "Keep reducing it. It should cling to the spoon before we stop.",
                    rationale:
                        "Body in a pan sauce comes from reduction. There is nothing else doing "
                        + "that job unless you have added a thickener.",
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "fondNotReleased",
                    observation:
                        "Brown fond is still stuck to the pan after deglazing and simmering.",
                    correction:
                        "Scrape the base while it bubbles. That colour belongs in the sauce.",
                    rationale:
                        "Everything that makes a pan sauce taste of what you cooked is in "
                        + "those stuck-on bits.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface]
                ),
            ],
            safetySignals: [
                "Alcohol poured from the bottle over a flame or very hot pan.",
                "A face directly over the pan as cold liquid meets hot fat.",
                "A pan handle over the front edge of the hob.",
            ],
            supportedEquipment: [
                "Stainless steel pan",
                "Cast iron",
                "Carbon steel",
            ],
            unsupportedEquipment: [
                "Non-stick, which develops very little fond. The lesson still works, there is "
                    + "just less to build on, and that is worth saying rather than marking down.",
            ],
            notVisuallyAssessable: panCannotBeSeen + [
                "Whether the sauce is balanced, which is the thing that actually decides "
                    + "whether it is good. Taste cannot be certified by camera and Chef should "
                    + "ask rather than claim.",
                "Whether it is too salty after reducing.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Cohesive sauce with real body, built on good fond.",
            variationSummary: "Their own sauce, and it came together properly.",
            outcomeTolerance: [
                "Good: cohesive enough to cling lightly to food or a spoon, with no separate "
                    + "greasy layer sitting on top.",
                "A thinner pan jus is a legitimate style. Judge against what the cook said "
                    + "they were making.",
            ],
            audioSignals: [
                "A hard boil after the butter goes in is the usual reason a finished sauce "
                    + "splits. If the cook mentions it was still boiling, that is the cause.",
            ]
        ),
        retryFraming: "Lift a spoonful and let it run back off so I can see the consistency."
    )
}
