import Foundation

/// Mother sauce rubrics, authored from `docs/skills-instructor-deliverable.md`.
///
/// This is the category the instructor expected the camera to be best at, and
/// the reason is roux. Its colour runs along a continuous visible scale from
/// white through blond to brown to burnt, which is exactly the kind of judgement
/// a beginner cannot make and a camera can. The same is true of a split
/// hollandaise, a lumpy béchamel and a greasy espagnole: these sauces fail
/// visibly, and they fail in ways that have names.
///
/// What none of them can be judged on is taste, and every rubric here says so.
/// A perfectly smooth béchamel with no salt in it looks identical to a good one.
///
/// Two limits repeated throughout, both from the deliverable:
///
/// - **A dark pan makes most of this much harder.** Cast iron and dark
///   non-stick destroy the contrast these rubrics rest on, so Chef lowers her
///   confidence and asks for a spoonful in better light rather than guessing.
/// - **A visual rubric never declares an egg sauce microbiologically safe.**
///   Hollandaise and mayonnaise are warm and raw egg preparations respectively,
///   and where someone vulnerable is eating, that is a pasteurised egg question
///   rather than something a photograph settles.
extension SkillVisualCheck {

    private static let sauceTasteIsInvisible = [
        "How it tastes. Salt, acid and balance decide whether a sauce is good and none of them "
            + "can be seen. Ask, never claim.",
        "Whether raw flour has been cooked out, which is a flavour rather than a colour.",
        "Temperature.",
        "Whether an egg based sauce is safe for someone vulnerable to eat. That is a question "
            + "about pasteurised eggs and holding time, and a picture cannot answer it.",
    ]

    private static let darkPanLimit =
        "A dark pan makes the colour judgement much less reliable. When the pan is dark, ask "
        + "for a spoonful lifted into better light rather than committing to a stage."

    private static let sauceSafety = [
        "A pan handle over the front edge of the hob.",
        "A face directly over a hard boiling reduction.",
        "A pan boiling over toward the burner.",
        "Alcohol poured from the bottle over a flame or very hot pan.",
    ]

    // MARK: - Roux

    static let motherRoux = SkillVisualCheck(
        id: "mother.roux.colour",
        assessmentMode: .process,
        framingInstruction:
            "Keep stirring and look down into the pan so I can see the colour.",
        setupNeeds:
            ", with butter, flour, a pan and a whisk or wooden spoon.",
        requiredVisibility: [.cookingSurface],
        helpfulVisibility: [.fat, .tool, .heatSource],
        observations: [
            SkillObservation(
                region: .fat,
                id: "flourCoated",
                question:
                    "Is all the flour coated in fat and smooth, or are there dry powdery pockets "
                        + "in it? `coated` or `powdery`. Say cannotTell if you cannot see into the pan.",
                answers: ["coated", "powdery", "cannotTell"],
                correct: "coated"
            ),
            SkillObservation(
                region: .tool,
                id: "evenColour",
                question:
                    "Is the roux one even colour across the pan, or are there darker scorched "
                        + "spots in it? `even` or `scorchedSpots`. Say cannotTell if you cannot see the "
                        + "whole surface.",
                answers: ["even", "scorchedSpots", "cannotTell"],
                correct: "even"
            ),
            SkillObservation(
                region: .cookingSurface,
                id: "noBlackFlecks",
                question:
                    "Are there black flecks in the roux? `none` or `blackFlecks`. Say cannotTell "
                        + "if the pan is too dark to judge.",
                answers: ["none", "blackFlecks", "cannotTell"],
                correct: "none"
            ),
        ],
        parts: [
            SkillCheckPart(region: .cookingSurface, label: "Colour matching the stage you want"),
            SkillCheckPart(region: .fat, label: "Every bit of flour coated in fat"),
            SkillCheckPart(region: .tool, label: "Moving constantly, no spot burning"),
        ],
        rubric: SkillVisualRubric(
            subject: "a roux cooking in a pan, and which stage it has reached",
            targetTechnique: [
                "The flour is fully coated in fat, with no dry powdery pockets.",
                "It is stirred continuously so it colours evenly rather than in spots.",
                "White stage: off-white to pale cream, no toasted colour, no raw floury look.",
                "Blond stage: light tan or golden, the colour of pale toasted cereal.",
                "Brown stage: from peanut butter through to a deeper brown, depending on "
                    + "the cuisine.",
                "Burnt: black flecks and acrid smoke. Not a stage, a restart.",
            ],
            acceptableVariations: [
                "Stopping anywhere along the scale. Which colour is right is decided by the "
                    + "sauce, not by how far you can take it.",
                "Butter, oil, or another fat.",
                "Equal parts by weight is the professional baseline, and recipes that give "
                    + "spoon measures are perfectly usable.",
                "A roux that looks looser or stiffer depending on the fat.",
                "Taking a long time over a dark roux. Slow is correct and rushing it is how "
                    + "it burns.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "scorchedRoux",
                    observation:
                        "Black flecks are visible in the roux, or it is smoking acridly.",
                    correction:
                        "Start that roux again. Those flecks are burnt, and they will flavour "
                        + "the whole sauce.",
                    rationale:
                        "Burnt flour is bitter and it does not dilute away. Everything built on "
                        + "it inherits the taste, which is why this is the one stage worth "
                        + "throwing away.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "heatTooHigh",
                    observation:
                        "The roux is colouring fast and unevenly, darker in some places than "
                        + "others.",
                    correction:
                        "Lower the heat. I want the colour to move evenly rather than "
                        + "spot burning.",
                    rationale:
                        "A roux on high heat browns wherever the pan is hottest, so you get "
                        + "burnt specks and pale flour at the same time and no usable stage "
                        + "in between.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "rawDryPockets",
                    observation:
                        "Dry, powdery flour is visible that has not been absorbed into the fat.",
                    correction:
                        "Keep stirring until every bit of flour is coated in fat.",
                    rationale:
                        "Uncoated flour never disperses. It goes into the sauce as a lump and "
                        + "stays there.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: [
                "Stainless steel pan",
                "Light coloured saucepan",
                "Carbon steel",
            ],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceTasteIsInvisible + [
                darkPanLimit,
                "The nutty aroma that most cooks actually use to judge a brown roux. Ask about "
                    + "it rather than working without it.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Even colour, caught at the stage they wanted.",
            variationSummary: "Their own colour, and it is even and unburnt.",
            audioSignals: [
                "A roux quietens as its water cooks off. Useful context, and far less "
                    + "informative here than colour.",
            ]
        ),
        retryFraming:
            "Lift a spoonful up toward the light, or tilt the pan, so I can see the colour."
    )

    // MARK: - Béchamel

    static let motherBechamel = SkillVisualCheck(
        id: "mother.bechamel.smooth",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Whisk the milk in with the pan in view.",
        setupNeeds:
            ", with butter, flour, milk, a pan and a whisk.",
        outcomeFraming: "Lift the spoon out and let it run off so I can see how it coats.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.cookingSurface, .tool],
        observations: [
            SkillObservation(
                region: .liquid,
                id: "smooth",
                question:
                    "Is the sauce smooth, or are there visible lumps in it? `smooth` or `lumpy`. "
                        + "Say cannotTell if you cannot see the surface clearly.",
                answers: ["smooth", "lumpy", "cannotTell"],
                correct: "smooth"
            ),
            SkillObservation(
                region: .liquid,
                id: "colour",
                question:
                    "What colour is it? `paleIvory` means white to pale cream. `browned` means it "
                        + "has taken tan or brown colour. Say cannotTell if the lighting does not let "
                        + "you judge.",
                answers: ["paleIvory", "browned", "cannotTell"],
                correct: "paleIvory"
            ),
            SkillObservation(
                region: .tool,
                id: "spoonCoat",
                question:
                    "When the spoon is lifted, does the sauce coat the back of it in an even "
                        + "layer, or run straight off like milk? `coats` or `runsOff`. Say cannotTell "
                        + "if no picture shows the spoon out of the sauce.",
                answers: ["coats", "runsOff", "cannotTell"],
                correct: "coats"
            ),
        ],
        parts: [
            SkillCheckPart(region: .liquid, label: "Smooth, no lumps"),
            SkillCheckPart(region: .liquid, label: "Pale ivory, not browned", id: "colour"),
            SkillCheckPart(region: .tool, label: "Coats the back of a spoon"),
        ],
        rubric: SkillVisualRubric(
            subject: "a béchamel being made, and its finished consistency",
            targetTechnique: [
                "The roux stays pale, with no colour taken.",
                "The milk goes in gradually and each addition is whisked smooth before "
                    + "the next.",
                "It comes to a gentle simmer so the starch fully thickens.",
                "The finished sauce is smooth, pale ivory, and pours in a continuous ribbon.",
            ],
            acceptableVariations: [
                "A wide range of thicknesses. A pouring béchamel and a stiff binder for "
                    + "croquettes are the same sauce at different ratios.",
                "Adding the milk cold or warm. Both work and cooks disagree about which "
                    + "is easier.",
                "Straining it, or not.",
                "A faint cream colour rather than pure white.",
                "Nutmeg, bay, onion or nothing.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "scorchedMilk",
                    observation:
                        "There is a browned or burnt layer on the base of the pan, and it is "
                        + "being scraped up into the sauce.",
                    correction:
                        "Do not scrape that burnt bottom into the sauce. Pour the clean sauce "
                        + "into another pan and lower the heat.",
                    rationale:
                        "Milk catches easily and once those solids are in, the whole sauce "
                        + "tastes scorched. Moving it is much easier than fixing it.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "lumpy",
                    observation:
                        "Visible lumps are suspended in the sauce.",
                    correction:
                        "Stop adding milk and whisk the base smooth before you add any more.",
                    rationale:
                        "Every lump is dry flour with a cooked skin around it. More liquid never "
                        + "reaches the inside, so they stay until you strain them out.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "tooThin",
                    observation:
                        "The sauce is still running like milk after simmering.",
                    correction:
                        "Give the starch time at a simmer before you decide it needs "
                        + "more thickener.",
                    rationale:
                        "Flour does not thicken until it is properly hot. Most thin béchamels "
                        + "are undercooked rather than under-floured.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "tooThick",
                    observation:
                        "The sauce has gone pasty and no longer pours.",
                    correction:
                        "Whisk in more hot milk, a little at a time.",
                    rationale:
                        "Easy to overshoot and completely reversible, so there is no reason to "
                        + "live with it.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Saucepan", "Stainless steel pan", "Whisk"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceTasteIsInvisible + [darkPanLimit],
            confidenceFloor: 0.6,
            passSummary: "Smooth, pale and the right consistency.",
            variationSummary: "Their own thickness, and it is smooth.",
            outcomeTolerance: [
                "For a medium sauce: pours in a continuous ribbon and lightly coats the back "
                    + "of a spoon.",
                "There is no single correct béchamel thickness. Judge against what they said "
                    + "they were making it for.",
            ]
        ),
        retryFraming: "Lift the spoon out again and hold it still for a second."
    )

    // MARK: - Velouté

    static let motherVeloute = SkillVisualCheck(
        id: "mother.veloute.body",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Whisk the stock in with the pan in view.",
        setupNeeds:
            ", with butter, flour, a light stock, a pan and a whisk.",
        outcomeFraming: "Lift the spoon and let it run off so I can see the body.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.cookingSurface, .tool],
        observations: [
            SkillObservation(
                region: .cookingSurface,
                id: "rouxColour",
                question:
                    "What colour was the roux taken to? `blond` means a light golden tan. `white` "
                        + "means no colour at all. `brown` means it went past blond into brown. Say "
                        + "cannotTell if no picture shows the roux.",
                answers: ["blond", "white", "brown", "cannotTell"],
                correct: "blond"
            ),
            SkillObservation(
                region: .liquid,
                id: "smooth",
                question:
                    "Is the sauce smooth, or are there visible lumps in it? `smooth` or `lumpy`. "
                        + "Say cannotTell if you cannot see the surface clearly.",
                answers: ["smooth", "lumpy", "cannotTell"],
                correct: "smooth"
            ),
            SkillObservation(
                region: .tool,
                id: "body",
                question:
                    "On the lifted spoon, does the sauce sit in a light even coat, or thick and "
                        + "pasty, or run straight off? `lightCoat`, `pasty` or `runsOff`. Say "
                        + "cannotTell if no picture shows the spoon out of the sauce.",
                answers: ["lightCoat", "pasty", "runsOff", "cannotTell"],
                correct: "lightCoat"
            ),
        ],
        parts: [
            SkillCheckPart(region: .cookingSurface, label: "Roux taken to blond, not brown"),
            SkillCheckPart(region: .liquid, label: "Velvety and smooth"),
            SkillCheckPart(region: .tool, label: "Coats lightly, not pasty"),
        ],
        rubric: SkillVisualRubric(
            subject: "a velouté being made, and its finished consistency",
            targetTechnique: [
                "The roux is taken to blond, a light golden tan, rather than kept white or "
                    + "pushed to brown.",
                "The stock goes in gradually and is whisked smooth.",
                "It simmers until velvety.",
                "The finished sauce is smooth, pale cream to golden depending on the stock, and "
                    + "coats lightly without being heavy.",
            ],
            acceptableVariations: [
                "Chicken, veal, fish or vegetable stock, all of which give different colours.",
                "A paler or deeper blond roux.",
                "Straining or not.",
                "A range of finished thicknesses, decided by what it is for.",
                "Cream added at the end, which makes it a derivative rather than a mistake.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "rouxTooDark",
                    observation:
                        "The roux has been taken well past blond into brown, for a sauce that "
                        + "was meant to stay pale.",
                    correction:
                        "That roux has gone past blond. For a pale velouté, start it again and "
                        + "stop at a light golden colour.",
                    rationale:
                        "A brown roux tastes toasted and thickens less, so a dark velouté is "
                        + "both the wrong colour and thinner than you expected.",
                    isContextual: true,
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "lumpy",
                    observation: "Visible lumps are suspended in the sauce.",
                    correction:
                        "Stop adding stock and whisk what is there smooth first.",
                    rationale:
                        "Lumps do not dissolve later. They come out on a sieve or not at all.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "watery",
                    observation:
                        "The sauce runs like stock with no clinging at all.",
                    correction:
                        "Keep it at a gentle simmer and judge it again once the starch has "
                        + "fully cooked.",
                    rationale:
                        "Starch thickens only once it is properly hot, so most thin veloutés "
                        + "just have not got there yet.",
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Saucepan", "Stainless steel pan", "Whisk"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceTasteIsInvisible + [
                darkPanLimit,
                "Whether the stock is any good, which is the thing that actually decides "
                    + "whether this sauce is worth eating. Ask.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Velvety, smooth and lightly coating.",
            variationSummary: "Their own stock and their own thickness, and it came out smooth.",
            outcomeTolerance: [
                "Coats lightly without being paste-like. Colour follows the stock and is not "
                    + "a judgement.",
            ]
        ),
        retryFraming: "Lift the spoon out again and hold it steady."
    )

    // MARK: - Espagnole and demi-glace

    static let motherEspagnole = SkillVisualCheck(
        id: "mother.espagnole.result",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Keep the pot in view as it reduces.",
        setupNeeds:
            ", with brown stock, aromatics and a heavy pot.",
        outcomeFraming:
            "Lift a spoonful and let it run off so I can see the colour and the body.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.cookingSurface, .tool, .fat],
        observations: [
            SkillObservation(
                region: .cookingSurface,
                id: "baseColour",
                question:
                    "How is the browned base? `browned` means deep golden to brown. `burnt` means "
                        + "black and carbonised. Say cannotTell if no picture shows it.",
                answers: ["browned", "burnt", "cannotTell"],
                correct: "browned"
            ),
            SkillObservation(
                region: .liquid,
                id: "gloss",
                question:
                    "What does the finished sauce look like? `deepBrownGlossy` means dark and "
                        + "shining. `dullOrPale` means thin, pale or matte. Say cannotTell if you "
                        + "cannot see it clearly.",
                answers: ["deepBrownGlossy", "dullOrPale", "cannotTell"],
                correct: "deepBrownGlossy"
            ),
            SkillObservation(
                region: .fat,
                id: "skimmed",
                question:
                    "Is there a separate layer of fat floating on the surface? `none` or "
                        + "`fatLayer`. Say cannotTell if you cannot see the surface.",
                answers: ["none", "fatLayer", "cannotTell"],
                correct: "none"
            ),
        ],
        parts: [
            SkillCheckPart(region: .cookingSurface, label: "Base browned, not burnt"),
            SkillCheckPart(region: .liquid, label: "Deep brown and glossy"),
            SkillCheckPart(region: .fat, label: "Skimmed, not greasy"),
        ],
        rubric: SkillVisualRubric(
            subject: "a brown sauce reducing, and the finished sauce on a spoon",
            targetTechnique: [
                "The aromatics and roux are properly browned without being burnt.",
                "It is skimmed as it simmers, so fat and scum do not stay in.",
                "It is strained.",
                "The finished sauce is deep brown, glossy and clean rather than greasy, and "
                    + "concentrated but still pourable.",
            ],
            acceptableVariations: [
                "Stopping at espagnole, or reducing on to demi-glace. Both are legitimate "
                    + "destinations.",
                "Working from a browned base without a separate roux, which many modern "
                    + "kitchens do.",
                "A range of concentrations. Demi-glace is much thicker than espagnole and "
                    + "neither is over-reduced.",
                "Tomato paste, fresh tomato or none.",
                "Taking hours. This is a long sauce and slowness is the method.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "burntBase",
                    observation:
                        "The browned base or roux has gone black rather than deep brown.",
                    correction:
                        "That base is burnt rather than browned. Start that stage again, or the "
                        + "bitterness will run through hours of work.",
                    rationale:
                        "This sauce concentrates everything in it. A slightly bitter base "
                        + "becomes a very bitter sauce after three hours of reduction.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "greasy",
                    observation:
                        "A distinct layer of fat is sitting on the surface of the sauce.",
                    correction:
                        "Skim that fat off the surface before you carry on reducing.",
                    rationale:
                        "Fat does not reduce, it concentrates alongside everything else. Skimmed "
                        + "early it is a small job, left in it is a greasy sauce.",
                    severity: .outcomeCost,
                    requiresVisible: [.liquid, .fat]
                ),
                SkillCoachableMistake(
                    key: "scorchingEdges",
                    observation:
                        "The sauce is catching and darkening around the edge of the pot.",
                    correction:
                        "Lower the heat and scrape the edges back in before they burn.",
                    rationale:
                        "The waterline is the thinnest layer and always burns first, and it "
                        + "flavours the whole pot when it does.",
                    severity: .irreversible,
                    requiresVisible: [.liquid, .cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "overReduced",
                    observation:
                        "The sauce has gone sticky and syrupy, well past a pourable "
                        + "consistency.",
                    correction:
                        "Loosen it with a little unsalted stock or water.",
                    rationale:
                        "Reduction concentrates salt as well as flavour, so it goes from intense "
                        + "to inedible fairly suddenly.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Heavy stockpot", "Saucepan", "Fine sieve"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceTasteIsInvisible + [
                darkPanLimit,
                "How good the stock underneath it is, which decides most of the result.",
                "How much it has reduced, unless the starting level was seen.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Deep brown, glossy and clean.",
            variationSummary: "Their own concentration, and it is clean and glossy.",
            outcomeTolerance: [
                "Deep brown, glossy rather than greasy, concentrated but still pourable.",
                "Demi-glace is legitimately much thicker. Judge against what they said they "
                    + "were making.",
            ]
        ),
        retryFraming: "Lift a spoonful again and let it run off slowly."
    )

    // MARK: - Sauce tomate

    static let motherTomate = SkillVisualCheck(
        id: "mother.tomate.result",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Keep the pan in view as it simmers.",
        setupNeeds:
            ", with tomatoes, aromatics and a pan on the heat.",
        outcomeFraming: "Draw a spoon through it so I can see the consistency.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.cookingSurface, .tool],
        observations: [
            SkillObservation(
                region: .cookingSurface,
                id: "nothingCatching",
                question:
                    "Is there darkened scorched material stuck to the bottom of the pan? `none` "
                        + "or `scorched`. Say cannotTell if you cannot see the base.",
                answers: ["none", "scorched", "cannotTell"],
                correct: "none"
            ),
            SkillObservation(
                region: .liquid,
                id: "reduced",
                question:
                    "Does the sauce look concentrated and thickened, or thin and watery with "
                        + "liquid separating out at the edges? `concentrated` or `watery`. Say "
                        + "cannotTell if you cannot see it clearly.",
                answers: ["concentrated", "watery", "cannotTell"],
                correct: "concentrated"
            ),
        ],
        parts: [
            SkillCheckPart(region: .cookingSurface, label: "Nothing catching on the bottom"),
            SkillCheckPart(region: .liquid, label: "Reduced and concentrated"),
            SkillCheckPart(region: .tool, label: "Consistency suits what it is for"),
        ],
        rubric: SkillVisualRubric(
            subject: "a tomato sauce simmering, and its finished consistency",
            targetTechnique: [
                "The aromatics are sweated or browned as the recipe intends.",
                "It simmers and concentrates rather than being served thin and raw.",
                "Nothing is catching or scorching on the bottom.",
                "The finished consistency suits what it is going on.",
            ],
            acceptableVariations: [
                "A classical French sauce tomate, built on aromatics and often stock and "
                    + "sometimes a roux, OR a clean Italian style with neither. These are "
                    + "different sauces rather than better and worse versions of one.",
                "Passed smooth or left rustic and chunky.",
                "Any level of reduction, decided by the dish.",
                "Fresh or tinned tomatoes.",
                "A deep red through to a brick colour depending on how long it cooked.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "scorching",
                    observation:
                        "A dark layer is catching on the base of the pan and being stirred in.",
                    correction:
                        "Lower the heat, and stop scraping that burnt layer back into the sauce.",
                    rationale:
                        "Tomato is thick and sugary and it catches easily. Once the burnt layer "
                        + "is stirred in, the whole pan tastes of it.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "overReducedPaste",
                    observation:
                        "The sauce has reduced to a thick paste that no longer moves.",
                    correction:
                        "Loosen it with a little water or stock.",
                    rationale:
                        "Past a point the tomato flavour stops concentrating and starts turning "
                        + "flat and slightly bitter.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "rawHarshTomato",
                    observation:
                        "The sauce is still thin and watery, with the tomato not yet broken "
                        + "down at all.",
                    correction:
                        "Give it more simmering before you do the final seasoning.",
                    rationale:
                        "Tomato needs time to lose its raw edge. Seasoning it before that "
                        + "means seasoning a different sauce from the one you will serve.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Saucepan", "Sauté pan", "Casserole"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceTasteIsInvisible + [
                "Acidity and sweetness, which are the two things a tomato sauce is usually "
                    + "adjusted for and neither of which is visible.",
                darkPanLimit,
            ],
            confidenceFloor: 0.6,
            passSummary: "Concentrated properly, nothing caught on the bottom.",
            variationSummary: "Their own style of tomato sauce, and it cooked down well.",
            outcomeTolerance: [
                "Judge against what it is going on. A sauce for pasta and a sauce for a base "
                    + "are different consistencies and both are right.",
            ]
        ),
        retryFraming: "Draw the spoon through it again so I can see how it moves."
    )

    // MARK: - Mayonnaise

    static let motherMayonnaise = SkillVisualCheck(
        id: "mother.mayonnaise.emulsion",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Add the oil the way you normally would, looking into the bowl.",
        setupNeeds:
            ", with an egg yolk, oil, an acid, a bowl and a whisk.",
        outcomeFraming: "Stop and let it sit for a moment so I can see whether it holds.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.tool],
        observations: [
            SkillObservation(
                region: .liquid,
                id: "evenGlossy",
                question:
                    "What does it look like in the bowl? `evenGlossy` means uniform, opaque and "
                        + "shining. `separated` means visible oil droplets or a broken curdled look. "
                        + "Say cannotTell if you cannot see into the bowl.",
                answers: ["evenGlossy", "separated", "cannotTell"],
                correct: "evenGlossy"
            ),
            SkillObservation(
                region: .liquid,
                id: "noFreeOil",
                question:
                    "Is there free oil sitting on the surface? `none` or `freeOil`. Say "
                        + "cannotTell if you cannot see the surface.",
                answers: ["none", "freeOil", "cannotTell"],
                correct: "none"
            ),
            SkillObservation(
                region: .tool,
                id: "holdsShape",
                question:
                    "On the lifted whisk, does it hold a shape, or run off? `holds` or `runsOff`. "
                        + "Say cannotTell if no picture shows the whisk lifted out.",
                answers: ["holds", "runsOff", "cannotTell"],
                correct: "holds"
            ),
        ],
        parts: [
            SkillCheckPart(region: .liquid, label: "Thick, glossy and even", id: "held"),
            SkillCheckPart(region: .liquid, label: "No free oil on top", id: "clean"),
            SkillCheckPart(region: .tool, label: "Holds its shape on the whisk"),
        ],
        rubric: SkillVisualRubric(
            subject: "mayonnaise being made, and whether the emulsion is holding",
            targetTechnique: [
                "The oil goes in very slowly at first, drop by drop, and can speed up once "
                    + "the emulsion has formed.",
                "The finished sauce is glossy, homogeneous and thick enough to hold a shape "
                    + "while still spreading.",
                "There is no free oil sitting on the surface.",
            ],
            acceptableVariations: [
                "Whisk, blender or immersion blender. The immersion blender method is much "
                    + "faster and is not cheating.",
                "Egg yolk, whole egg, or mustard as the emulsifier.",
                "Any oil, though a strong olive oil will taste much stronger.",
                "A softer, looser mayonnaise, which is a legitimate texture.",
                "Loosening it with water at the end, which is a normal finishing step.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "broken",
                    observation:
                        "The mixture has split, with visible oil separating out rather than "
                        + "staying combined.",
                    correction:
                        "Stop adding oil. Start again with a little water or a fresh yolk in a "
                        + "clean bowl, and whisk the broken mixture into that slowly.",
                    rationale:
                        "You cannot rescue a broken mayonnaise by whisking harder. You rebuild "
                        + "it around a new base, treating the broken one as if it were the oil.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "oilTooFast",
                    observation:
                        "Oil is pooling on the surface between whisks, arriving faster than "
                        + "the mixture is taking it.",
                    correction:
                        "Slow right down to a thin thread until it thickens and holds.",
                    rationale:
                        "At the start there is barely any emulsion to work with, so the first "
                        + "spoonful of oil matters more than all the rest.",
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "tooStiff",
                    observation:
                        "The mayonnaise has become so thick it barely moves and looks "
                        + "close to splitting.",
                    correction:
                        "Whisk in a teaspoon of water to loosen it before you add any more oil.",
                    rationale:
                        "There is a limit to how much oil a given amount of water can hold. Past "
                        + "it, the emulsion gets stiff and then it breaks.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: [],
            supportedEquipment: ["Bowl and whisk", "Immersion blender", "Food processor"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceTasteIsInvisible + [
                "Whether the eggs are pasteurised, which is what matters if anybody vulnerable "
                    + "is eating it. This is an uncooked egg preparation and Chef should raise "
                    + "that once, gently, rather than certifying anything.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Thick, glossy and holding.",
            variationSummary: "Their own texture, and the emulsion held.",
            outcomeTolerance: [
                "Glossy, homogeneous, holds a soft shape but still spreads. No oil puddle "
                    + "anywhere.",
                "Softer than shop mayonnaise is normal for a homemade one and is not a fault.",
            ]
        ),
        retryFraming: "Look straight down into the bowl and let it settle for a second."
    )

    // MARK: - Hollandaise

    static let motherHollandaise = SkillVisualCheck(
        id: "mother.hollandaise.emulsion",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Keep the bowl in view while you whisk, and I will watch how it moves.",
        setupNeeds:
            ", with egg yolks, warm butter, lemon, a bowl and a whisk.",
        outcomeFraming: "Lift the whisk out so I can see how it falls off.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.tool, .cookingSurface],
        observations: [
            SkillObservation(
                region: .liquid,
                id: "smooth",
                question:
                    "Is the sauce smooth, or grainy with visible particles of cooked egg in it? "
                        + "`smooth` or `grainy`. Say cannotTell if you cannot see the surface clearly.",
                answers: ["smooth", "grainy", "cannotTell"],
                correct: "smooth"
            ),
            SkillObservation(
                region: .liquid,
                id: "noSeparation",
                question:
                    "Is there an oily layer or pool of butter separating out? `none` or "
                        + "`oilySeparation`. Say cannotTell if you cannot see the surface.",
                answers: ["none", "oilySeparation", "cannotTell"],
                correct: "none"
            ),
            SkillObservation(
                region: .tool,
                id: "body",
                question:
                    "Falling off the whisk, does it fall in a thick ribbon that sits on the "
                        + "surface, or run off thin like liquid? `ribbon` or `thin`. Say cannotTell if "
                        + "no picture shows the whisk lifted out.",
                answers: ["ribbon", "thin", "cannotTell"],
                correct: "ribbon"
            ),
        ],
        parts: [
            SkillCheckPart(region: .liquid, label: "Smooth and glossy, no grain", id: "smooth"),
            SkillCheckPart(region: .liquid, label: "No oily separation", id: "held"),
            SkillCheckPart(region: .tool, label: "Thick enough to coat, still pours"),
        ],
        rubric: SkillVisualRubric(
            subject: "hollandaise being made, and whether it is holding",
            targetTechnique: [
                "The yolk base is whisked over gentle heat until it thickens and aerates, "
                    + "without ever scrambling.",
                "The warm butter goes in gradually while whisking.",
                "The finished sauce is smooth, glossy and lemon yellow.",
                "It is thick enough to coat but still pours.",
                "There are no oily pools and no grainy particles.",
            ],
            acceptableVariations: [
                "Clarified butter or whole melted butter.",
                "Over a bain-marie, directly on very low heat, or in a blender.",
                "A range of thicknesses.",
                "More or less lemon, which changes the colour slightly as well as the taste.",
                "A pale or a deeper yellow, depending on the eggs.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "curdledYolk",
                    observation:
                        "The sauce has visible grainy particles in it, like very fine "
                        + "scrambled egg.",
                    correction:
                        "That yolk has curdled. Start the egg base again rather than adding "
                        + "more butter to this.",
                    rationale:
                        "Once the yolk protein has set into grains it cannot be un-set. Adding "
                        + "butter to it just makes more of a grainy sauce.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "splitEmulsion",
                    observation:
                        "The sauce has gone thin and greasy, with butter fat separating out.",
                    correction:
                        "Stop the butter and whisk in a few drops of water. Rebuild it before "
                        + "you add any more.",
                    rationale:
                        "A split hollandaise is usually rescuable, and only if you stop "
                        + "immediately. Carrying on adding butter is what makes it permanent.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "tooHot",
                    observation:
                        "The sauce is steaming hard, or the bowl is sitting directly in "
                        + "boiling water and the mixture is tightening fast.",
                    correction:
                        "Get the bowl off the heat and keep whisking.",
                    rationale:
                        "Yolks begin setting around 65C and hollandaise gets more likely to "
                        + "curdle the closer it gets. Off the heat is almost always the "
                        + "right move.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "butterTooFast",
                    observation:
                        "Butter is going in faster than the sauce is taking it, with fat "
                        + "sitting on the surface between whisks.",
                    correction:
                        "Slow the butter to a thin stream until the sauce tightens again.",
                    rationale:
                        "The emulsion can only take fat as fast as the whisk can break it up. "
                        + "Anything faster is just waiting to split.",
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "tooThick",
                    observation:
                        "The sauce has become very stiff and barely moves.",
                    correction:
                        "Whisk in a little water or lemon until it flows again.",
                    rationale:
                        "A hollandaise that is too thick is close to breaking. Loosening it is "
                        + "both the fix and the prevention.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Bowl over a pan", "Saucepan on low heat", "Blender"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceTasteIsInvisible + [
                "The temperature of the sauce, which is the one thing that decides whether it "
                    + "survives. Ask rather than estimating.",
                "Whether it is safe to serve to someone vulnerable. This is a warm egg sauce, "
                    + "which means pasteurised eggs and short holding times, and no picture "
                    + "settles that.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Smooth, glossy and holding.",
            variationSummary: "Their own consistency, and the emulsion held.",
            outcomeTolerance: [
                "Smooth, glossy, lemon yellow. Thick enough to coat and still pourable.",
                "No oily pools and no grainy particles. Those two are the real tests.",
            ]
        ),
        retryFraming: "Lift the whisk out again and let it fall back so I can see it."
    )

    // MARK: - Beurre blanc

    static let motherBeurreBlanc = SkillVisualCheck(
        id: "mother.beurre-blanc.emulsion",
        assessmentMode: .processThenOutcome,
        framingInstruction:
            "Whisk the butter in with the pan in view, and I will watch it come together.",
        setupNeeds:
            ", with wine or vinegar, shallot, cold butter, a pan and a whisk.",
        outcomeFraming: "Lift the whisk out so I can see how it coats and falls.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.tool, .cookingSurface, .fat],
        observations: [
            SkillObservation(
                region: .liquid,
                id: "opaqueCreamy",
                question:
                    "What does the sauce look like? `opaqueCreamy` means pale, opaque and glossy. "
                        + "`oilySeparated` means clear butter fat has separated out of it. Say "
                        + "cannotTell if you cannot see it clearly.",
                answers: ["opaqueCreamy", "oilySeparated", "cannotTell"],
                correct: "opaqueCreamy"
            ),
            SkillObservation(
                region: .cookingSurface,
                id: "notBoiling",
                question:
                    "Once the butter is going in, is the sauce boiling, or is the surface still? "
                        + "`notBoiling` or `boiling`. Say cannotTell if you cannot see the surface.",
                answers: ["notBoiling", "boiling", "cannotTell"],
                correct: "notBoiling"
            ),
            SkillObservation(
                region: .tool,
                id: "coatsWhisk",
                question:
                    "Does the sauce coat the whisk, or run off it? `coats` or `runsOff`. Say "
                        + "cannotTell if no picture shows the whisk lifted out.",
                answers: ["coats", "runsOff", "cannotTell"],
                correct: "coats"
            ),
        ],
        parts: [
            SkillCheckPart(region: .liquid, label: "Opaque and creamy, not oily", id: "held"),
            SkillCheckPart(region: .cookingSurface, label: "Off the boil once butter goes in"),
            SkillCheckPart(region: .tool, label: "Coats the whisk"),
        ],
        rubric: SkillVisualRubric(
            subject: "a beurre blanc being built, and whether the emulsion is holding",
            targetTechnique: [
                "The acidic base is reduced well but not completely dry.",
                "The heat comes right down before any butter goes in.",
                "Cold butter is added a piece at a time, each one whisked in before the next.",
                "The finished sauce is opaque, creamy and glossy, with no floating butter oil.",
            ],
            acceptableVariations: [
                "Wine, vinegar, or a mixture as the base.",
                "Strained or left with the shallot in.",
                "A splash of cream in the base, which makes it much more stable and is a "
                    + "common professional shortcut rather than a compromise.",
                "Any finished thickness.",
                "Adding butter in larger pieces once it is established.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "split",
                    observation:
                        "Clear butter fat is sitting on the surface or pooling at the edges "
                        + "rather than staying combined.",
                    correction:
                        "Take it off the heat and whisk in a teaspoon of cool water, then add "
                        + "the butter more slowly.",
                    rationale:
                        "There is no egg holding this one together, so the emulsion lives or "
                        + "dies on temperature. Cool water and patience usually bring it back.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "tooHot",
                    observation:
                        "The sauce is bubbling or simmering while butter is being added.",
                    correction:
                        "Off the heat now. The butter is melting out instead of emulsifying.",
                    rationale:
                        "Above a fairly low temperature the butter simply melts into oil and "
                        + "water rather than dispersing. This is the single commonest way "
                        + "beurre blanc fails.",
                    severity: .irreversible,
                    requiresVisible: [.liquid, .cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "baseTooDry",
                    observation:
                        "The reduction has gone almost completely dry before the butter "
                        + "goes in.",
                    correction:
                        "Add a spoon of water before the next butter. The emulsion needs "
                        + "something watery to sit in.",
                    rationale:
                        "An emulsion needs both phases. Reduce the base to nothing and there is "
                        + "no water left for the butter to disperse into.",
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Saucepan", "Sauté pan", "Whisk"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceTasteIsInvisible + [
                "The temperature, which is the only thing keeping this sauce alive. Ask rather "
                    + "than estimating.",
                darkPanLimit,
            ],
            confidenceFloor: 0.6,
            passSummary: "Creamy, opaque and holding.",
            variationSummary: "Their own version, and the emulsion held.",
            outcomeTolerance: [
                "Opaque and creamy with no clear butter oil floating on it.",
                "Thickness varies a lot and is not the test. Whether it has split is the test.",
            ]
        ),
        retryFraming: "Lift the whisk out again and let it run off so I can see it."
    )
}
