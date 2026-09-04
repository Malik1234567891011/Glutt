/**
 * Pilot segments for Joshua Weissman's butter chicken, "The 2 Dollar Curry"
 * https://www.youtube.com/watch?v=hDjK5C2aoSs (396s).
 *
 * Every window below was read off frames extracted at 2fps from the normalized
 * master, not taken from a model. That matters more on this video than on the
 * others: it is cut fast, and there are five talking-head returns and a running
 * price-caption gag inside the cooking stretch, which runs 0:58 to 4:13. A
 * window picked off the narration alone lands on his face at least twice.
 *
 * The cuts that shaped these windows:
 *   93.5-97   he writes a joke on the plastic wrap. The marinade clip stops before it.
 *   160-160.5 talking head mid-spice, one second, left in rather than splitting the clip.
 *   169.5-171 talking head between the last spice and the tomatoes, so those are two clips.
 *   193.5-199 talking head + the optional hand blender, which the plan calls optional
 *             and no step claims, so no clip covers it.
 *   253.4+    the "$1.59 per serving" caption lands on the finished bowl. Serve ends first.
 *
 * `step_keywords` matter less here than on the older pilots, because the bundled
 * plan pins every clip by id, but they are still the fallback if that plan is
 * ever deleted. This recipe says "chicken", "sauce", "pan", "stir" and "simmer"
 * in most of its steps, so each set is chosen from the words only its own step
 * uses.
 */
export const butterChickenSegments = [
  {
    id: "seg-bc-marinade",
    // 84.5-86 is a wide of him at the counter; the close-up starts at 86.
    start_seconds: 86,
    end_seconds: 93,
    primary_action: "marinate",
    secondary_actions: ["coat", "toss"],
    ingredients: ["chicken thighs", "full fat yogurt", "garam masala", "kosher salt"],
    tools: ["mixing bowl"],
    starting_state: "cut chicken sitting on the spiced yogurt",
    ending_state: "every piece coated, bowl covered",
    technique: "yogurt marinade for curry",
    dish_stage: "prep",
    visual_questions: ["Is every piece coated?"],
    visual_cue:
      "Hands, not a spoon. Every piece wants to come out white, with no bare patch of chicken showing. Then cover it and it goes in the fridge.",
    watch_label: "Watch the chicken get coated",
    teaching_label: "See how to coat chicken in a yogurt marinade",
    notice:
      "Thirty minutes is the minimum and overnight is better. The yogurt is also what chars in the pan later, so do not rinse it off.",
    audio_useful: true,
    visual_quality: 0.9,
    boundary_confidence: 0.9,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["marinate", "marinade", "yogurt", "coat", "fridge"],
  },
  {
    id: "seg-bc-oil",
    // Oil goes in at 101 and the first chicken lands at 110.
    start_seconds: 100,
    end_seconds: 109,
    primary_action: "heat",
    secondary_actions: ["pour"],
    ingredients: ["vegetable oil"],
    tools: ["braiser", "deep pan"],
    starting_state: "dry pan on the heat",
    ending_state: "oil hot and rippling, nothing in it yet",
    technique: "bring a pan up to searing temperature",
    dish_stage: "sear",
    visual_questions: ["Is the oil moving on its own?"],
    visual_cue:
      "Two tablespoons in a wide deep pan on medium-high. It is ready when the oil thins out and ripples on its own, and the surface looks like it is moving.",
    watch_label: "Watch the oil come up to heat",
    teaching_label: "See what hot oil looks like",
    notice:
      "This is the step that decides the sear. Wet yogurt chicken into a lukewarm pan steams and goes grey, and it never comes back.",
    audio_useful: true,
    visual_quality: 0.85,
    boundary_confidence: 0.9,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["shimmering", "rippling", "oil", "preheat", "medium-high"],
  },
  {
    id: "seg-bc-sear",
    start_seconds: 110,
    end_seconds: 125,
    primary_action: "sear",
    secondary_actions: ["flip", "batch"],
    ingredients: ["marinated chicken"],
    tools: ["braiser", "tongs", "baking sheet"],
    starting_state: "marinated pieces laid into hot oil with gaps between them",
    ending_state: "browned and charred in spots, on a tray, still raw inside",
    technique: "sear marinated chicken in batches",
    dish_stage: "sear",
    visual_questions: ["Are there gaps between the pieces?", "Brown or charred, not grey?"],
    visual_cue:
      "Look at the gaps. Every piece is laid down with space around it, and none of them are moved for two minutes. Turned over, they are deep brown and black at the edges.",
    watch_label: "Watch the chicken sear",
    teaching_label: "See how far to take the sear",
    notice:
      "It comes out of the pan raw in the middle and that is correct. It finishes later in the sauce.",
    audio_useful: true,
    visual_quality: 0.95,
    boundary_confidence: 0.9,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["sear", "batches", "charred", "crowd", "tongs"],
  },
  {
    id: "seg-bc-aromatics",
    // 145.5-147 is the insert of the fond; the splash of water lands at 147.5.
    start_seconds: 136,
    end_seconds: 153,
    primary_action: "soften",
    secondary_actions: ["deglaze", "scrape", "season"],
    ingredients: ["yellow onion", "ginger", "garlic", "kosher salt", "black pepper"],
    tools: ["braiser", "wooden spoon"],
    starting_state: "onion, ginger and garlic into the pan the chicken left",
    ending_state: "softened and golden, nothing stuck to the base",
    technique: "sweat aromatics and lift the fond",
    dish_stage: "base",
    visual_questions: ["Is the brown coming off the base?", "Onion soft rather than raw?"],
    visual_cue:
      "Watch the base of the pan. That dark brown crust is the whole flavour of the sear, and a splash of water plus a scrape lifts it into the onions. Cook until it is dry again.",
    watch_label: "Watch the fond come up",
    teaching_label: "See how to scrape up the fond",
    notice:
      "The dark stuff on the bottom is not burnt, it is the best thing in the pan. Leaving it there is the mistake.",
    audio_useful: true,
    visual_quality: 0.9,
    boundary_confidence: 0.85,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["onion", "ginger", "fond", "scrape", "soften"],
  },
  {
    id: "seg-bc-spices",
    // 160-160.5 is a one second talking-head return, left inside the window.
    start_seconds: 155,
    end_seconds: 169,
    primary_action: "toast",
    secondary_actions: ["bloom", "stir"],
    ingredients: ["paprika", "ground cumin", "garam masala", "turmeric"],
    tools: ["braiser", "wooden spoon"],
    starting_state: "dry spices onto softened onions",
    ending_state: "spices dark and stuck to the vegetables, intensely fragrant",
    technique: "bloom ground spices in fat",
    dish_stage: "base",
    visual_questions: ["Have the spices gone from powder to paste?"],
    visual_cue:
      "They go in as loose powder and turn dark and glossy as they hit the fat. A minute is the whole window, and the smell tells you before the colour does.",
    watch_label: "Watch the spices toast",
    teaching_label: "See how long to toast spices",
    notice:
      "Ground spices in a hot dry pan go bitter in seconds. Keep them moving, and get the tomatoes ready before you start.",
    audio_useful: true,
    visual_quality: 0.9,
    boundary_confidence: 0.85,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["paprika", "cumin", "turmeric", "toast", "fragrant"],
  },
  {
    id: "seg-bc-tomatoes",
    start_seconds: 172,
    end_seconds: 192,
    primary_action: "reduce",
    secondary_actions: ["pour", "simmer", "stir"],
    ingredients: ["crushed tomatoes", "water"],
    tools: ["braiser", "wooden spoon"],
    starting_state: "crushed tomatoes onto the toasted spices",
    ending_state: "reduced by about a third, thick enough to hold a spoon track",
    technique: "build and reduce a curry base",
    dish_stage: "sauce",
    visual_questions: ["Does a spoon leave a track?"],
    visual_cue:
      "The can gets swirled out with water so nothing is left behind. Then watch the surface: loose and splashing at first, and by the end it plops rather than ripples.",
    watch_label: "Watch the sauce reduce",
    teaching_label: "See how far to reduce the sauce",
    notice: "Five to eight minutes, and it should end up about a third smaller than it started.",
    audio_useful: true,
    visual_quality: 0.9,
    boundary_confidence: 0.85,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["tomatoes", "reduce", "reduced", "thickened", "can"],
  },
  {
    id: "seg-bc-chicken-back",
    start_seconds: 201,
    end_seconds: 210,
    primary_action: "simmer",
    secondary_actions: ["return", "cover"],
    ingredients: ["seared chicken"],
    tools: ["braiser", "lid"],
    starting_state: "seared chicken tipped back into the reduced sauce",
    ending_state: "chicken submerged and cooked through under a lid",
    technique: "finish seared meat in its sauce",
    dish_stage: "sauce",
    visual_questions: ["Is every piece down in the sauce?"],
    visual_cue:
      "Everything on the tray goes in, resting juices included. Push the pieces down so the sauce covers them, then the lid goes on to speed it up.",
    watch_label: "Watch the chicken go back in",
    teaching_label: "See how the chicken finishes in the sauce",
    notice: "Three to five minutes is enough. It was already browned, this is only to cook it through.",
    audio_useful: true,
    visual_quality: 0.85,
    boundary_confidence: 0.9,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["back", "return", "lid", "through", "juices"],
  },
  {
    id: "seg-bc-cream",
    start_seconds: 211,
    end_seconds: 225,
    primary_action: "enrich",
    secondary_actions: ["pour", "stir"],
    ingredients: ["heavy cream"],
    tools: ["braiser", "wooden spoon"],
    starting_state: "cream poured into a dark red sauce",
    ending_state: "one even orange sauce, no white streaks",
    technique: "finish a curry with cream",
    dish_stage: "sauce",
    visual_questions: ["Any white streaks left?", "Is it barely bubbling?"],
    visual_cue:
      "Red to orange in about a minute of stirring. When the colour is even all the way through and no white is left, it is done.",
    watch_label: "Watch the cream go in",
    teaching_label: "See how cream changes the sauce",
    notice:
      "Keep it at a lazy bubble. Cream held at a hard boil splits, and a split sauce looks grainy and cannot be stirred back.",
    audio_useful: true,
    visual_quality: 0.95,
    boundary_confidence: 0.9,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["cream", "heavy", "orange", "streaks", "splits"],
  },
  {
    id: "seg-bc-butter",
    start_seconds: 226,
    end_seconds: 239,
    primary_action: "emulsify",
    secondary_actions: ["melt", "stir"],
    ingredients: ["unsalted butter"],
    tools: ["braiser", "wooden spoon"],
    starting_state: "cold butter onto the sauce with the heat off",
    ending_state: "glossy, with no fat sitting on top",
    technique: "mount a sauce with butter",
    dish_stage: "finish",
    visual_questions: ["Glossy, or is there a slick on top?"],
    visual_cue:
      "The butter sits on the surface and then disappears into it. Keep stirring the whole time it melts, and the finished sauce is glossy rather than greasy.",
    watch_label: "Watch the butter go in",
    teaching_label: "See how butter finishes the sauce",
    notice:
      "Heat off first. Butter dropped into a boiling sauce separates and leaves a yellow slick on top instead of shine.",
    audio_useful: true,
    visual_quality: 0.9,
    boundary_confidence: 0.9,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["butter", "emulsify", "emulsifies", "glossy", "melted"],
  },
  {
    id: "seg-bc-serve",
    // Ends before the "$1.59 per serving" caption lands at 253.4.
    start_seconds: 243,
    end_seconds: 253,
    primary_action: "serve",
    secondary_actions: ["ladle", "garnish"],
    ingredients: ["steamed rice", "cilantro"],
    tools: ["shallow bowl", "spoon"],
    starting_state: "rice pressed into one side of a shallow bowl",
    ending_state: "curry ladled alongside, cilantro over the top",
    technique: "plate a curry",
    dish_stage: "serve",
    visual_questions: ["Is the rice beside the curry rather than under it?"],
    visual_cue:
      "Rice packed into one side, curry ladled against it so the two stay separate, then whole cilantro leaves dropped on last.",
    watch_label: "Watch the plating",
    teaching_label: "See how it is served",
    notice: "Leaves, not chopped. They go on at the table, off the heat, so they stay green.",
    audio_useful: true,
    visual_quality: 0.9,
    boundary_confidence: 0.9,
    review_status: "approved",
    model_version: "manual-frame-read-v1",
    step_keywords: ["bowl", "rice", "cilantro", "ladle", "serve"],
  },
];
