import Foundation

/// Rubrics for the four Cooking Basics skills a camera can honestly judge.
/// Authored from `docs/skills-instructor-deliverable.md`.
///
/// Four of nine, and the gap is the point. The instructor was blunt that most
/// of this category is judgement rather than technique: reading a recipe,
/// seasoning as you go, knowing when food is done and resting meat are all real
/// skills that a photograph cannot certify. Writing visual rubrics for them
/// would produce an app with confident opinions about flavour, which is worse
/// than admitting the limit. They stay unwatchable until Chef can coach through
/// conversation instead.
///
/// What is left is genuinely strong. Simmer versus boil is close to ideal:
/// continuous, visible, and something beginners get wrong constantly. Putting a
/// thermometer in the right part of a chicken is pure geometry. And the one
/// rule that outranks everything in this file, from the deliverable: **colour is
/// not a safety test.** Chef never certifies that meat is cooked from how it
/// looks, on any skill, ever.
extension SkillVisualCheck {

    // MARK: - Simmer and boil

    static let basicsSimmerVsBoil = SkillVisualCheck(
        id: "basics.simmer-boil.surface",
        assessmentMode: .process,
        framingInstruction: "Look straight down into the pot so I can see the surface.",
        setupNeeds:
            ", with a pot of liquid on the heat.",
        requiredVisibility: [.liquid],
        helpfulVisibility: [.cookingSurface, .heatSource],
        parts: [
            SkillCheckPart(region: .liquid, label: "Bubble size and rate match the job"),
            SkillCheckPart(region: .cookingSurface, label: "Not climbing toward the rim"),
        ],
        rubric: SkillVisualRubric(
            subject: "the surface of a liquid in a pot, and how hard it is bubbling",
            targetTechnique: [
                "A simmer is gentle: small bubbles, breaking intermittently to steadily, with "
                    + "the surface moving but not churning.",
                "A boil is vigorous: continuous bubbling across most of the surface, visibly "
                    + "rolling.",
                "The cook picks one deliberately for the job and adjusts the heat to hold it "
                    + "there, rather than setting the dial once and leaving it.",
            ],
            acceptableVariations: [
                "The whole range from a bare simmer, with barely a bubble, to an active simmer "
                    + "that is nearly a boil. Simmer covers a lot of ground and the recipe "
                    + "decides where in it to sit.",
                "Starchy liquids that foam, and thick sauces that make large slow bubbles. "
                    + "Bubble size changes with what is in the pot, not only with the heat.",
                "A pot that looks more active for a moment after a lid comes off.",
                "A hard boil for pasta or for reducing a stock, which is correct.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "foamOverRisk",
                    observation:
                        "Foam or liquid is climbing toward the rim of the pot and about to "
                        + "go over.",
                    correction:
                        "Lower the heat now, and lift the pot off if you need to. It is about "
                        + "to come over the top.",
                    rationale:
                        "Boiling starchy water goes over the edge much faster than it looks "
                        + "like it will, and it takes the burner and your floor with it.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "boilingWhenSimmerNeeded",
                    observation:
                        "The liquid is at a full rolling boil where a simmer was intended.",
                    correction:
                        "Lower the heat until the surface is gently bubbling rather "
                        + "than rolling.",
                    rationale:
                        "A hard boil tears delicate things apart and drives liquid off faster "
                        + "than the flavour has time to develop. It also will not make anything "
                        + "cook meaningfully quicker.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
                SkillCoachableMistake(
                    key: "notActuallySimmering",
                    observation:
                        "The liquid is hot and still, with almost no bubbles breaking, where a "
                        + "simmer was intended.",
                    correction:
                        "Raise it slightly. I want regular small bubbles, not just hot "
                        + "still liquid.",
                    rationale:
                        "Below a simmer things stop cooking and start sitting. It is the "
                        + "commonest reason a braise takes twice as long as the recipe said.",
                    isContextual: true,
                    severity: .outcomeCost,
                    requiresVisible: [.liquid]
                ),
            ],
            safetySignals: [
                "A pot boiling over toward the burner.",
                "A pot handle over the front edge of the hob.",
                "A face directly over a hard boiling pot.",
            ],
            supportedEquipment: ["Saucepan", "Stockpot", "Sauté pan", "Casserole"],
            unsupportedEquipment: [],
            notVisuallyAssessable: [
                "The temperature of the liquid. A simmer is not one number and it changes with "
                    + "what is dissolved in the pot and with altitude.",
                "Which state the recipe actually wanted, unless the cook says.",
                "What is under the surface.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Held at the right state for the job.",
            variationSummary: "Their own level, and it suits what is in the pot.",
            audioSignals: [
                "A boil is a dense continuous sound. A simmer is more intermittent, with "
                    + "individual bubbles audible. This is one of the clearest audio "
                    + "distinctions in cooking, and still only ever confirms what is seen.",
            ]
        ),
        retryFraming: "Look straight down into the pot again, and hold it for a second."
    )

    // MARK: - Use a thermometer

    static let basicsThermometer = SkillVisualCheck(
        id: "basics.thermometer.placement",
        assessmentMode: .process,
        framingInstruction:
            "Put the probe in the way you normally would, and look down at it as you do.",
        setupNeeds:
            ", with your thermometer and something cooking to check.",
        requiredVisibility: [.tool, .ingredient],
        helpfulVisibility: [.cookingSurface],
        parts: [
            SkillCheckPart(region: .tool, label: "Tip in the thickest part"),
            SkillCheckPart(region: .ingredient, label: "Clear of bone and of the pan"),
        ],
        rubric: SkillVisualRubric(
            subject: "a thermometer probe being placed into food",
            targetTechnique: [
                "The sensing tip goes into the thickest part, the bit that will be coolest.",
                "It avoids bone, the pan itself, and any large pocket of fat.",
                "For thin food, it goes in from the side so the tip sits in the centre rather "
                    + "than straight through.",
                "More than one spot is checked when the shape is irregular.",
                "The lowest relevant reading is the one that counts, and the probe is cleaned "
                    + "before it touches cooked food again.",
            ],
            acceptableVariations: [
                "Instant read or a leave-in probe. Both are correct tools.",
                "Any entry angle that gets the tip where it needs to be.",
                "Different pull temperatures for different recipes and styles, because a cook "
                    + "may be allowing for carryover. Safety minimums are a separate matter and "
                    + "are not negotiable, but a quality target is the cook's to choose.",
                "Checking earlier than strictly necessary. There is no cost to an extra look.",
            ],
            rankedMistakes: [
                SkillCoachableMistake(
                    key: "touchingBoneOrPan",
                    observation:
                        "The probe is resting against a bone, or has gone through the food and "
                        + "is touching the pan.",
                    correction:
                        "Back the probe off the bone and measure the meat itself.",
                    rationale:
                        "Bone conducts heat differently and the pan is far hotter than anything "
                        + "in it, so either one gives you a number that has nothing to do with "
                        + "whether the food is cooked.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.tool, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "probeTooShallow",
                    observation:
                        "Only the very end of the probe has entered the food, or it is in a "
                        + "thin edge rather than the thickest part.",
                    correction:
                        "Push the tip into the centre of the thickest part.",
                    rationale:
                        "The thickest part is the last to come up to temperature. Everywhere "
                        + "else will read done before it is.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.tool, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "oneRandomSpot",
                    observation:
                        "A single reading is being taken from an irregularly shaped piece, and "
                        + "treated as the answer.",
                    correction:
                        "Check one more spot nearby. I want the coolest part, not the "
                        + "first number.",
                    rationale:
                        "A chicken is not one thickness. The first number you get is just one "
                        + "of several, and the lowest is the one that matters.",
                    severity: .outcomeCost,
                    requiresVisible: [.tool, .ingredient]
                ),
                SkillCoachableMistake(
                    key: "dirtyProbeReuse",
                    observation:
                        "A probe that has been in raw or undercooked food goes back into food "
                        + "that is finished, without being cleaned.",
                    correction:
                        "Clean the probe before it touches cooked food again.",
                    rationale:
                        "The probe goes to the coolest part of raw meat and then straight into "
                        + "something you are about to eat. It is the one utensil that travels "
                        + "between those two worlds.",
                    severity: .safety,
                    confidenceFloor: 0.5,
                    requiresVisible: [.tool]
                ),
            ],
            safetySignals: [
                "Raw meat juices visibly contacting ready to eat food.",
                "A hand deep inside a hot oven with no protection.",
            ],
            supportedEquipment: ["Instant read thermometer", "Leave-in probe thermometer"],
            unsupportedEquipment: [
                "An oven dial or built-in oven thermometer, which measures the air and not "
                    + "the food.",
            ],
            notVisuallyAssessable: [
                "The reading itself, unless the display is clearly legible in frame.",
                "Whether the food is safe. That is what the number is for, and Chef must never "
                    + "substitute an opinion about colour for it.",
                "Whether the thermometer is accurate or needs calibrating.",
                "How far the sensing tip is from the physical end of the probe, which varies "
                    + "by model. Where it matters, ask.",
            ],
            confidenceFloor: 0.6,
            passSummary: "Probe in the right place, clear of bone and pan.",
            variationSummary: "Their own placement, and the tip is where it needs to be."
        ),
        retryFraming: "Look down at where the probe goes in, and hold still for a second."
    )
}
