import Foundation

/// Sauce rubrics, authored from `docs/skills-instructor-deliverable.md`.
///
/// Five of the six sauce skills are here. **Balance a Sauce is not**, and its
/// absence is the point: it is entirely a question of taste, and a visual
/// rubric for it would be Chef inventing opinions about flavour. She can watch
/// the discipline and she cannot judge the result, so she does not pretend to.
///
/// For the five that are here, the honest line runs through every one of them:
/// Chef can see structure and she cannot see seasoning. She knows a split
/// emulsion, a lumpy roux, a watery reduction and burnt fond on sight. Whether
/// the finished thing tastes good is a question she asks rather than answers.
extension SkillVisualCheck {

    private static let sauceCannotBeSeen = [
        "How it tastes. Salt, acid, sweetness, bitterness and balance are all invisible, and "
            + "they are what actually decide whether a sauce is good. Ask, never claim.",
        "Whether it is too salty, which reduction makes worse and which looks like nothing.",
        "Temperature.",
        "Whether raw flour has been cooked out, which is a taste rather than a colour.",
    ]

    private static let sauceSafety = [
        "A pan handle over the front edge of the hob.",
        "A face directly over a hard boiling reduction.",
        "Alcohol poured from the bottle over a flame or very hot pan.",
        "A pan boiling over toward the burner.",
    ]

    // MARK: - What is fond

    static let saucesFond = SkillVisualCheck(
        id: "sauces.fond.reading",
        assessmentMode: .outcome,
        framingInstruction: "Take the food out and look straight down at the empty pan.",
        setupNeeds:
            ", once you have browned something in a pan.",
        outcomeFraming: "Tip the pan toward the light a little so I can see the colour.",
        requiredVisibility: [.cookingSurface],
        helpfulVisibility: [.fat],
        parts: [
            SkillCheckPart(region: .cookingSurface, label: "Golden to deep brown, not black"),
            SkillCheckPart(region: .fat, label: "Excess fat dealt with"),
        ],
        rubric: SkillVisualRubric(
            subject: "the base of a pan after something has been browned in it",
            targetTechnique: [
                "The residue stuck to the base is golden through to deep brown.",
                "The cook can tell that apart from black carbonised material, which is burnt "
                    + "and not worth building on.",
            ],
            acceptableVariations: [
                "A very dark brown fond, which is fine and is not the same as black.",
                "Almost no fond at all in a non-stick pan. That is the coating doing its job "
                    + "rather than the cook doing something wrong.",
                "Patchy fond, heavier where the food sat.",
                "Fond under a layer of fat, which just needs pouring off first.",
                "Fond from vegetables, which is paler than fond from meat.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "burntAsFond",
                    observation:
                        "The residue is black and carbonised rather than brown, and the cook is "
                        + "treating it as usable.",
                    correction:
                        "That part is black rather than brown. Do not build the sauce on it, it "
                        + "will be bitter.",
                    rationale:
                        "Browned material is sweet and savoury. Carbon is just bitter, and once "
                        + "it is dissolved into a sauce there is no way to take it back out.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "tooMuchFat",
                    observation:
                        "A deep layer of fat is covering the base, so the fond is swimming "
                        + "rather than stuck.",
                    correction:
                        "Pour off the excess fat and keep the browned bits underneath.",
                    rationale:
                        "The fat will not join a sauce, it will float on top of it. The flavour "
                        + "you want is the brown layer under it.",
                    severity: .efficiency,
                    requiresVisible: [.cookingSurface, .fat]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Stainless steel pan", "Cast iron", "Carbon steel"],
            unsupportedEquipment: [
                "Non-stick, which develops very little fond. The lesson still works and there "
                    + "is simply less to look at.",
            ],
            notVisuallyAssessable: sauceCannotBeSeen + [
                "Whether very dark fond has actually crossed into bitter. A dark pan makes this "
                    + "much harder, and when it is borderline Chef should say so.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Read the pan right, brown rather than black.",
            variationSummary: "Their own read on it, and it is usable fond.",
            outcomeTolerance: [
                "Golden through deep brown is good. Only clearly black, carbonised material is "
                    + "a problem, and a few dark specks at the edge are normal.",
            ]
        ),
        retryFraming: "Tilt the pan toward the light again so I can see the base."
    )

    // MARK: - Pan sauce

    static let saucesPanSauce = SkillVisualCheck(
        id: "sauces.pan-sauce.body",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Build it as you normally would, with the pan in view.",
        setupNeeds:
            ", once you have browned something and the pan has fond in it.",
        outcomeFraming: "Lift a spoonful and let it run back off so I can see the body.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.cookingSurface, .tool, .fat],
        parts: [
            SkillCheckPart(region: .cookingSurface, label: "Fond lifted into the liquid"),
            SkillCheckPart(region: .liquid, label: "Reduced to real body"),
            SkillCheckPart(region: .tool, label: "Cohesive, not split or greasy"),
        ],
        rubric: SkillVisualRubric(
            subject: "a pan sauce being built, and the finished sauce on a spoon",
            targetTechnique: [
                "It starts from brown fond rather than burnt residue.",
                "The fond is scraped loose into the bubbling liquid.",
                "It is reduced until it has body rather than stopped while watery.",
                "Any butter finish happens off the heat or on very low heat.",
                "The finished sauce clings lightly to a spoon without a separate greasy layer.",
            ],
            acceptableVariations: [
                "Any liquid. Wine is not required and water works.",
                "Finishing with butter, cream, or nothing.",
                "A deliberately thin pan jus, which is a real thing to want.",
                "Aromatics or none.",
                "A naturally thick sauce from a gelatinous stock with no other thickener.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "burntFond",
                    observation: "The sauce is being built on black carbonised residue.",
                    correction:
                        "Do not build on those black bits. Start the base again in a clean pan.",
                    rationale:
                        "Bitterness from burnt fond runs through the whole sauce and nothing "
                        + "added later covers it.",
                    severity: .irreversible,
                    requiresVisible: [.cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "brokenGreasy",
                    observation:
                        "Fat has separated out and is sitting as a distinct layer or as pools "
                        + "on the surface.",
                    correction:
                        "Take it off the heat and whisk in a teaspoon of water. The fat is "
                        + "separating out.",
                    rationale:
                        "A butter finished sauce is an emulsion and heat breaks it. Off the "
                        + "heat with a splash of water it usually comes straight back.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "watery",
                    observation:
                        "The sauce runs off the spoon like broth, with no clinging at all.",
                    correction:
                        "Keep reducing it. It should cling to the spoon before you stop.",
                    rationale:
                        "Body comes from getting the water out. There is no shortcut unless you "
                        + "are adding a thickener.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "fondNotReleased",
                    observation:
                        "Brown fond is still stuck to the base after the liquid has been "
                        + "simmering.",
                    correction:
                        "Scrape the base while it bubbles. That colour belongs in the sauce.",
                    rationale:
                        "Everything that makes the sauce taste of what you cooked is in those "
                        + "stuck-on bits.",
                    severity: .outcomeCost,
                    requiresVisible: [.cookingSurface]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Stainless steel pan", "Cast iron", "Carbon steel"],
            unsupportedEquipment: ["Non-stick, which develops very little fond to build on."],
            notVisuallyAssessable: sauceCannotBeSeen,
            confidenceFloor: 0.6,
            passSummary: "Cohesive sauce with real body, built on good fond.",
            variationSummary: "Their own sauce, and it came together.",
            outcomeTolerance: [
                "Good: clings lightly to the back of a spoon, with no separate greasy layer.",
                "A thinner jus is a legitimate style. Judge against what they said they "
                    + "were making.",
            ]
        ),
        retryFraming: "Lift the spoon out again and hold it still for a second."
    )

    // MARK: - Vinaigrette

    static let saucesVinaigrette = SkillVisualCheck(
        id: "sauces.vinaigrette.emulsion",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Whisk it the way you normally would, looking down into the bowl.",
        setupNeeds:
            ", with oil, vinegar, a bowl and a whisk.",
        outcomeFraming: "Stop whisking and look down at it so I can see whether it holds.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.tool, .workSurface],
        parts: [
            SkillCheckPart(region: .liquid, label: "Oil going in slowly", id: "stream"),
            SkillCheckPart(region: .liquid, label: "Cloudy and even, not separated", id: "held"),
        ],
        rubric: SkillVisualRubric(
            subject: "a vinaigrette being whisked, and how it looks once it settles",
            targetTechnique: [
                "The acid, salt and any emulsifier go in first.",
                "The oil goes in gradually while whisking, rather than all at once, when a "
                    + "stable dressing is wanted.",
                "Immediately after whisking it looks homogeneous and slightly cloudy rather "
                    + "than two visible layers.",
            ],
            acceptableVariations: [
                "Ratios other than three parts oil to one part acid. That is a useful starting "
                    + "point rather than a rule, and sharper dressings at two to one are common "
                    + "and correct.",
                "Shaking it in a jar instead of whisking. Completely valid.",
                "A deliberately broken vinaigrette, where the oil and acid are meant to stay "
                    + "separate and get spooned over separately.",
                "No mustard, which means it will separate sooner and that is expected rather "
                    + "than a fault.",
                "Separating again after a few minutes, which every unstabilised vinaigrette does.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "oilDumped",
                    observation:
                        "All the oil has gone in at once and the mixture is sitting in two "
                        + "distinct layers despite whisking.",
                    correction:
                        "Add the oil in a thinner stream while you whisk, so the droplets stay "
                        + "broken up.",
                    rationale:
                        "An emulsion is made by breaking fat into tiny droplets. A whole pour "
                        + "arrives faster than the whisk can break it, so most of it never "
                        + "gets divided.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                // No "over dressed the salad" mistake here on purpose. This
                // check looks into a mixing bowl while a dressing is being
                // made, so there are no leaves in any of these frames and a
                // rule about them could never fire. Dressing a salad is a
                // different moment and would need its own look.
                SkillCoachableMistake(
                    key: "splitAfterWhisking",
                    observation:
                        "Moments after whisking stops, the mixture has already separated back "
                        + "into distinct oil and acid layers.",
                    correction:
                        "Whisk in a small spoon of mustard, and it will hold together for "
                        + "much longer.",
                    rationale:
                        "Oil and vinegar have no reason to stay mixed on their own. An "
                        + "emulsifier like mustard sits between the two and stops the droplets "
                        + "finding each other again.",
                    isContextual: true,
                    severity: .efficiency,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: [],
            supportedEquipment: ["Bowl and whisk", "Jar", "Blender", "Immersion blender"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceCannotBeSeen + [
                "Whether the balance is right, which is the entire point of a vinaigrette and "
                    + "cannot be seen. Ask them to taste it on a leaf rather than off a spoon.",
                "How strong the vinegar is, which changes the right ratio completely.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Came together evenly and held.",
            variationSummary: "Their own dressing, and it did what they wanted.",
            outcomeTolerance: [
                "Homogeneous and slightly cloudy immediately after whisking is the bar.",
                "Separating again later is normal for anything without an emulsifier, and is "
                    + "never a fault.",
            ]
        ),
        retryFraming: "Look down into the bowl again and hold still for a second."
    )

    // MARK: - Understand an emulsion

    static let saucesEmulsion = SkillVisualCheck(
        id: "sauces.emulsion.state",
        assessmentMode: .outcome,
        framingInstruction: "Make one, then let it sit still for a moment.",
        setupNeeds:
            ", with oil, an acid, an egg yolk or mustard, a bowl and a whisk.",
        outcomeFraming: "Look straight down into the bowl so I can see whether it is holding.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.tool],
        parts: [
            SkillCheckPart(region: .liquid, label: "Even and opaque, not separated", id: "held"),
            SkillCheckPart(region: .tool, label: "Coats the whisk", id: "coat"),
        ],
        rubric: SkillVisualRubric(
            subject: "an emulsion in a bowl, held or broken",
            targetTechnique: [
                "A held emulsion looks even, opaque and slightly thickened, with no free oil "
                    + "on the surface.",
                "A broken one shows visible separation: a greasy layer, or oil droplets "
                    + "gathering and joining up.",
                "The cook can tell those apart and knows that adding fat too fast is what "
                    + "usually causes the second.",
            ],
            acceptableVariations: [
                "A temporary emulsion that separates after a while, which is what a vinaigrette "
                    + "without mustard does and is entirely normal.",
                "Any emulsifier: mustard, egg yolk, honey, or none at all.",
                "Different thicknesses. Thick is not the same as stable and thin is not "
                    + "the same as broken.",
                "Whisk, blender, jar or immersion blender.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "broken",
                    observation:
                        "The mixture has separated, with a greasy layer or visible oil droplets "
                        + "joining back together.",
                    correction:
                        "Stop adding fat. Start again with a little water or acid in a clean "
                        + "bowl, and whisk the broken mixture back into it slowly.",
                    rationale:
                        "You cannot fix a broken emulsion by whisking harder. You rebuild it "
                        + "around a fresh base, adding the broken one as if it were the oil.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "fatTooFast",
                    observation:
                        "Fat is going in faster than the mixture is taking it, with oil pooling "
                        + "on the surface between whisks.",
                    correction:
                        "Slow the oil down to a thin stream until it tightens up again.",
                    rationale:
                        "The whisk can only break up so much fat at a time. Anything arriving "
                        + "faster than that just sits there waiting to join back together.",
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Bowl and whisk", "Blender", "Immersion blender", "Jar"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceCannotBeSeen + [
                "Whether it will STAY held. Stability over time cannot be judged from one look, "
                    + "and a temporary emulsion looks identical to a permanent one at the moment "
                    + "it is made.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Held together, even and opaque.",
            variationSummary: "Their own emulsion, and it is holding.",
            outcomeTolerance: [
                "Held means even and opaque with no free oil on top, right now.",
                "Separating later is normal without an emulsifier and is not a failure.",
            ]
        ),
        retryFraming: "Look straight down into the bowl and let it settle for a second."
    )

    // MARK: - Thicken a sauce

    static let saucesThicken = SkillVisualCheck(
        id: "sauces.thicken.body",
        assessmentMode: .processThenOutcome,
        framingInstruction: "Thicken it your way, with the pan in view.",
        setupNeeds:
            ", with the sauce in a pan and whatever you are thickening "
            + "it with.",
        outcomeFraming:
            "Draw a spoon through it, or lift the spoon out, so I can see how it coats.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.tool, .cookingSurface],
        parts: [
            SkillCheckPart(region: .liquid, label: "Smooth, no lumps"),
            SkillCheckPart(region: .tool, label: "Coats the back of a spoon"),
            SkillCheckPart(region: .cookingSurface, label: "Brought back to a simmer"),
        ],
        rubric: SkillVisualRubric(
            subject: "a sauce being thickened, and its finished consistency",
            targetTechnique: [
                "The mechanism suits the sauce: reduction, roux, a starch slurry, a puree, "
                    + "or an emulsion.",
                "The result is smooth rather than lumpy.",
                "A starch is brought back to a simmer so it can actually thicken.",
                "The finished body is judged on how it coats, not on how it looks in the pan.",
            ],
            acceptableVariations: [
                "Any thickening mechanism, chosen for the sauce.",
                "A wide range of finished thicknesses. There is no universal correct viscosity "
                    + "and the dish decides.",
                "A sauce left deliberately thin.",
                "Cloudiness from starch, which is normal and not a fault.",
                "Cream or dairy behaving differently from a stock based sauce.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "lumpy",
                    observation:
                        "Visible lumps of flour or starch are suspended in the sauce.",
                    correction:
                        "Stop adding liquid and whisk what is there smooth before you "
                        + "add more.",
                    rationale:
                        "A lump is dry flour with a cooked skin around it. More liquid does not "
                        + "reach the inside, so it never dissolves and you end up straining it.",
                    severity: .irreversible,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "rawSlurry",
                    observation:
                        "A starch slurry has gone in but the sauce is not being brought back to "
                        + "a simmer, and it is staying thin.",
                    correction:
                        "Bring it back to a simmer so the starch can actually thicken.",
                    rationale:
                        "Starch only does its job once it gets hot enough to swell. Below that "
                        + "it just sits there making the sauce cloudy.",
                    severity: .outcomeCost,
                    requiresVisible: [.liquid, .cookingSurface]
                ),
                SkillCoachableMistake(
                    key: "tooThick",
                    observation:
                        "The sauce has gone pasty and no longer flows.",
                    correction:
                        "Whisk in a little more of a compatible liquid until it flows again.",
                    rationale:
                        "Thickening is easy to overshoot and very easy to reverse. Loosening it "
                        + "costs you nothing.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: sauceSafety,
            supportedEquipment: ["Saucepan", "Sauté pan", "Whisk"],
            unsupportedEquipment: [],
            notVisuallyAssessable: sauceCannotBeSeen + [
                "Whether raw flour has been cooked out, which is a taste rather than a "
                    + "appearance.",
                "How much thicker it will get as it cools, which is often a lot.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Smooth, and the body they were after.",
            variationSummary: "Their own thickness, and it suits the dish.",
            outcomeTolerance: [
                "A useful home cue: it coats the back of a spoon and a finger drawn through "
                    + "leaves a line that holds for a moment.",
                "Plenty of good sauces are looser than that on purpose. This is a cue rather "
                    + "than a universal target.",
            ]
        ),
        retryFraming: "Lift the spoon out again and hold it steady so I can see it coat."
    )
}
