import Foundation

/// What the camera is actually capable of judging about one skill.
///
/// Deliberately a separate thing from `SkillLesson`, which is what we *teach*.
/// The two answer different questions and change for different reasons: the
/// lesson changes when the technique is explained better, this changes when the
/// vision model gets better or worse at seeing a thumb. Folding them together
/// would mean a copy edit to a lesson could quietly alter what counts as a pass.
///
/// Static content like the rest of Skills, so authoring a check for a new skill
/// is a data edit with no migration. A skill with `visualCheck == nil` is simply
/// one Polly cannot watch yet, which is most of them.
struct SkillVisualCheck: Hashable, Sendable {
    /// Stable id, used on the attempt rows so history survives re-authoring.
    let id: String

    /// What Chef should be pointing the camera at for this one.
    let assessmentMode: SkillAssessmentMode

    /// What Polly says to set the shot up, immediately before the hold starts.
    ///
    /// Written to be spoken, not read. It has one job the rest of the lesson
    /// does not: getting the cook's own hand into frame without asking them to
    /// wave a knife around.
    let framingInstruction: String

    /// How far back into the live stream a look may reach, in seconds.
    ///
    /// There is no hold. There was one, of five seconds, and it existed because
    /// the design assumed a camera that has to be opened; the glasses stream
    /// continuously from the moment the lesson starts, so the frames were never
    /// what anyone was waiting for. This is now simply the window of recent
    /// history a look is allowed to draw from, wide enough to cover the sentence
    /// the cook was speaking while they asked.
    let lookbackSeconds: Double

    /// How many views to send.
    ///
    /// Three, because they are angles rather than retries. A grip has two faces
    /// and one instant only ever shows one of them, so the extra images are what
    /// makes a whole assessment possible rather than insurance against a blurred
    /// one. Above three the latency is felt and the angles stop being distinct.
    let framesPerLook: Int

    /// The minimum needed to say anything at all. Missing one of these produces
    /// "I cannot see" rather than a criticism.
    ///
    /// Deliberately small. It was originally every region the rubric mentions,
    /// which turned out to be a demand the world cannot meet: in a pinch grip
    /// the thumb and the index finger are on OPPOSITE faces of the blade, so
    /// from the cook's own eyes one of them is behind the steel by definition.
    /// Requiring both meant a correct grip, held perfectly still, in good light,
    /// was reported as unseeable about half the time. A cook looking straight at
    /// their hand being told "I cannot see your hand" is the single fastest way
    /// to lose them.
    let requiredVisibility: [SkillVisibilityRegion]

    /// Regions that sharpen the assessment when visible and block nothing when
    /// they are not. Reported by the assessor, and used to decide what she is
    /// allowed to comment on: a finger nobody saw cannot be corrected.
    let helpfulVisibility: [SkillVisibilityRegion]

    /// One purely perceptual question whose answer the CODE turns into a
    /// verdict, because the reader cannot be trusted to draw the conclusion.
    ///
    /// This exists because of nine experiments on one archived frame in which
    /// the cook's whole hand was closed around the steel. Every framing was
    /// tried and every one came back "on the handle": a minimal one line prompt,
    /// the full uncropped frame, a free description with no schema at all, a
    /// forced two way choice with both answers spelled out, gpt-4.1, gpt-5, and
    /// asking whether metal passed through the fist. It is not our prompt, not
    /// the crop, not the resolution and not the model tier. It is a language
    /// prior: hand plus knife means hand on handle, and it beats the pixels.
    ///
    /// One framing broke through. Asked to LOCATE the collar where steel meets
    /// handle, it answered correctly, "a white or pale collar just below the
    /// fist", and then concluded "fist on handle" in the same breath, which its
    /// own sentence contradicts. Perception was right; inference was not.
    ///
    /// So the reader is asked only where the collar is, forbidden from saying
    /// anything about grip, and the meaning is worked out here.
    let landmark: SkillLandmarkQuestion?

    /// Things worth knowing, said while a look is running.
    ///
    /// A look is not instant. A device log timed one at forty six seconds
    /// between the cook asking and the answer arriving, and what filled it was
    /// "right, let me have a look" and then nothing. Silence that long reads as
    /// the app having died.
    ///
    /// So the wait carries the part of a lesson there is otherwise never room
    /// for: WHY the technique is shaped the way it is. Each one has to be worth
    /// a cook's attention on its own, which rules out restating the instruction
    /// they were just given. Used in order and not repeated within a lesson, so
    /// a cook who looks four times hears four different things.
    let waitingFacts: [String]

    /// The one observation asked on its own, in its own request, away from the
    /// rubric.
    ///
    /// Measured, on the same model and the same two pictures of a hand closed
    /// around a knife blade:
    ///
    ///     asked inside the full system prompt   onHandle   (wrong)
    ///     asked on its own                      onBlade    (right)
    ///
    /// And on a genuine pinch grip the small request answered `onHandle`, so it
    /// is discriminating rather than just alarmed. The full prompt is fourteen
    /// thousand characters of technique, mistakes, equipment and framing, and
    /// somewhere in all of that the deciding question stops being read. The
    /// answer is not to write it more loudly; it is to ask it by itself.
    let decisiveRegion: SkillVisibilityRegion?

    /// Readings that must hold before a cook can be told they got it right.
    ///
    /// Everything else in this file guards against a false correction, because
    /// a false correction is what makes a cook stop trusting the coach. That
    /// left the opposite direction completely unguarded, and the opposite
    /// direction is the dangerous one: a cook held a chef's knife with their
    /// whole hand wrapped around the BLADE, fingers across the cutting edge,
    /// and was told "yep, that's it, looks perfect" at 0.90 confidence.
    ///
    /// A pass is a claim too. If the pictures cannot confirm it, the honest
    /// answer is to ask for another look, not to congratulate somebody whose
    /// fingers are on the edge.
    let passRequires: [SkillVisibilityRegion: [String]]

    /// Readings that mean stop, whatever else the verdict said.
    ///
    /// Separate from `passRequires` because the words are different: one asks
    /// for another look, this one tells them to let go and re-grip. Kept out of
    /// the model's own `safety.immediateConcern`, which it did not raise on the
    /// hand closed around a blade, because a narrow perceptual question is
    /// answered far more reliably than "is this dangerous".
    let dangerousReadings: [SkillVisibilityRegion: [String]]

    /// The narrow, closed-answer questions asked about each picture, before any
    /// verdict is reached.
    ///
    /// The reason this exists, plainly: asked "which grip is this", the model
    /// picks a familiar answer and then writes evidence to match it. Across one
    /// archived session the `observedEvidence` strings repeated word for word
    /// between looks, two templates, and one of them was produced from an
    /// unreadable smear. Evidence written after the conclusion cannot check the
    /// conclusion.
    ///
    /// "Where is the thumb: on the blade, on the handle, or cannot tell" is a
    /// question about pixels. It is answered per picture, so three pictures give
    /// three answers that can disagree, and disagreement is a real result rather
    /// than noise hidden inside one confident verdict.
    let observations: [SkillObservation]

    /// Everything the assessor is asked to report on.
    var reportedVisibility: [SkillVisibilityRegion] { requiredVisibility + helpfulVisibility }

    /// The technique broken into the parts a cook can see on their own hand.
    ///
    /// Not steps. A grip is one gesture, not a sequence: nobody puts their thumb
    /// on, pauses, and then adds a finger. Numbering it into a wizard makes four
    /// screens out of one shape and asks somebody to hold a knife while
    /// following a slideshow. These are the parts of that shape, all visible at
    /// once, filling in as she confirms them.
    let parts: [SkillCheckPart]

    /// Everything the vision model needs to know about the technique itself.
    let rubric: SkillVisualRubric

    /// What Polly says when the view was not good enough. Not a failure message:
    /// the cook did nothing wrong, the camera did.
    let retryFraming: String

    /// How to photograph it, for a cook with no glasses on.
    ///
    /// A separate sentence from `framingInstruction` rather than a reworded one,
    /// because the two situations have nothing in common. Wearing glasses your
    /// hands are free and the camera is your face, so the instruction is about
    /// moving your hand. Holding a phone you have one hand left and the camera
    /// goes where you point it, so the instruction is about where to stand and
    /// what to point at. Trying to serve both from one string produced sentences
    /// that were wrong in both.
    ///
    /// Nil falls back to the live framing, which is fine for the skills where
    /// the two really do coincide, like looking down at a board.
    let photoFraming: String?

    /// How many photos to ask for.
    ///
    /// Fewer than `framesPerLook`. Three live frames are three angles snatched
    /// out of a movement that was happening anyway, and cost the cook nothing.
    /// Three photographs are three deliberate acts with a knife in one hand, so
    /// two well chosen ones are worth more than three grudging ones.
    let photosNeeded: Int

    /// The sentence for a cook holding a phone rather than wearing glasses.
    func framing(for mode: SkillLearningMode) -> String {
        switch mode {
        case .watching: framingInstruction
        case .showing: photoFraming ?? framingInstruction
        }
    }

    /// The tail of the sentence naming what to have to hand before starting,
    /// beginning with its own separator: ", with a pot of liquid on the heat."
    ///
    /// Stored as a tail rather than a whole sentence because the opener depends
    /// on the mode and the tail never does. A cook wearing glasses is told to
    /// put them on; a cook without is told to keep their phone to hand; both
    /// need the same pot of liquid. Writing 55 whole sentences twice to vary
    /// four words would be a lot of copy to keep in step.
    ///
    /// Written for the eye rather than the ear, unlike everything else here.
    let setupNeeds: String

    /// The whole sentence, for the mode this lesson is running in.
    func setupLine(for mode: SkillLearningMode) -> String {
        let opener = switch mode {
        case .watching: "Put your glasses on"
        case .showing: "Have your phone to hand"
        }
        return opener + setupNeeds
    }

    /// What the model needs to understand about seeing *this* thing, when the
    /// generic advice for the mode is not enough.
    ///
    /// The knife grip needs a paragraph nothing else needs: the thumb and the
    /// curled index finger are on opposite faces of the blade, so any single
    /// frame hides one of them and a model told to be thorough will report a
    /// correct grip as unassessable. That paragraph used to live in the prompt
    /// builder, where it was applied to every skill including the ones judged
    /// by looking down at a chopping board. It belongs to the skill.
    let viewingNote: String?

    /// What Polly says to get the *finished thing* into view, for the skills
    /// judged on what they produced rather than how they were done.
    ///
    /// Nil for pure-process skills. "Spread one handful into a single layer and
    /// look straight down" is a completely different request from "turn your
    /// hand slowly", and a skill assessed both ways needs both sentences.
    let outcomeFraming: String?

    /// After this many unusable views, stop asking and offer the way out.
    /// Two, because a third identical request is where a cook concludes the
    /// feature is broken and stops trusting the rest of it.
    let maxUnusableViews: Int

    init(
        id: String,
        assessmentMode: SkillAssessmentMode = .process,
        framingInstruction: String,
        photoFraming: String? = nil,
        photosNeeded: Int = 2,
        setupNeeds: String = " and get set up.",
        viewingNote: String? = nil,
        outcomeFraming: String? = nil,
        lookbackSeconds: Double = 5,
        framesPerLook: Int = 3,
        requiredVisibility: [SkillVisibilityRegion],
        helpfulVisibility: [SkillVisibilityRegion] = [],
        observations: [SkillObservation] = [],
        waitingFacts: [String] = [],
        decisiveRegion: SkillVisibilityRegion? = nil,
        landmark: SkillLandmarkQuestion? = nil,
        dangerousReadings: [SkillVisibilityRegion: [String]] = [:],
        passRequires: [SkillVisibilityRegion: [String]] = [:],
        parts: [SkillCheckPart] = [],
        rubric: SkillVisualRubric,
        retryFraming: String,
        maxUnusableViews: Int = 2
    ) {
        self.id = id
        self.assessmentMode = assessmentMode
        self.framingInstruction = framingInstruction
        self.photoFraming = photoFraming
        self.photosNeeded = photosNeeded
        self.setupNeeds = setupNeeds
        self.viewingNote = viewingNote
        self.outcomeFraming = outcomeFraming
        self.lookbackSeconds = lookbackSeconds
        self.framesPerLook = framesPerLook
        self.requiredVisibility = requiredVisibility
        self.helpfulVisibility = helpfulVisibility
        self.observations = observations
        self.waitingFacts = waitingFacts
        self.decisiveRegion = decisiveRegion
        self.landmark = landmark
        self.passRequires = passRequires
        self.dangerousReadings = dangerousReadings
        self.parts = parts
        self.rubric = rubric
        self.retryFraming = retryFraming
        self.maxUnusableViews = maxUnusableViews
    }

}

/// One part of a technique, as a cook would check it on their own hand.
///
/// Keyed to a visibility region so its state comes out of the assessment for
/// free: a region she could see, on a look that found no fault with it, is a
/// part that is right. Nothing extra is asked of the model for this.
struct SkillCheckPart: Hashable, Sendable, Identifiable {
    /// The region this part's state is read from.
    ///
    /// Several parts may share one. That is the normal case for a skill judged
    /// on what it produced: "pieces are a similar size" and "faces are square"
    /// are two things a cook checks separately and both are read off the same
    /// look at the same board.
    let region: SkillVisibilityRegion

    /// What it says on screen. Short enough to read at a glance with a knife in
    /// your hand, specific enough to act on.
    let label: String

    /// Distinct per part, because the region no longer is.
    let id: String

    init(region: SkillVisibilityRegion, label: String, id: String? = nil) {
        self.region = region
        self.label = label
        self.id = id ?? region.rawValue
    }
}

/// How far along one part is.
enum SkillPartState: Sendable {
    /// Not seen yet, or not judged yet.
    case unknown
    /// She has seen it and had nothing to say about it.
    case good
    /// This is the one thing she is correcting.
    case needsFixing
}

/// A part of the scene the assessor reports on separately.
///
/// Separate visibility per region, not one overall flag, because "I can see your
/// thumb but not your index finger" is a genuinely useful thing to say and a
/// single boolean cannot say it.
enum SkillVisibilityRegion: String, Hashable, Sendable, CaseIterable {
    // The tool and the hand on it. Written first for the knife grip, and still
    // the right vocabulary for anything held: a whisk, a spoon, a probe.
    case tool
    case controlPoint
    case thumb
    case indexFinger
    case remainingFingers
    case wrist

    /// The hand that is NOT holding the tool. The whole subject of the claw
    /// grip, and the thing every knife safety signal is actually about.
    case guidingHand

    // What is being worked on, and where.
    case ingredient
    case workSurface
    /// The finished thing, spread out to be looked at. This is the region for
    /// every outcome assessment: a board of dice, a line of julienne, a
    /// spoonful of mince. The instructor deliverable puts most knife cuts here
    /// rather than on the motion, because nobody can read a dice at 7fps but a
    /// board of finished cubes is trivially readable.
    case result

    // The pan and what is in it.
    case cookingSurface
    case fat
    case liquid
    /// The burner, dial or flame. Reported so Chef can say she cannot see it,
    /// never so she can grade it: the deliverable is emphatic that a dial
    /// number is not heat knowledge.
    case heatSource

    /// How Polly refers to it out loud. Kept here rather than in the coach so
    /// the words match what the assessor was asked about.
    var spokenName: String {
        switch self {
        case .tool: "your knife"
        case .controlPoint: "where your hand meets the blade"
        case .thumb: "your thumb"
        case .indexFinger: "your index finger"
        case .remainingFingers: "your other fingers"
        case .wrist: "your wrist"
        case .guidingHand: "your other hand"
        case .ingredient: "what you are cutting"
        case .workSurface: "your board"
        case .result: "what you have cut so far"
        case .cookingSurface: "the pan"
        case .fat: "the oil in the pan"
        case .liquid: "what is in the pan"
        case .heatSource: "your burner"
        }
    }

    /// What the cook can physically do to bring this into view.
    ///
    /// Always a slow movement rather than a new pose to hold, because holding is
    /// what cannot work here: the thumb and the index finger are on opposite
    /// faces of the blade, so no single position shows both and asking somebody
    /// to freeze in the right one is asking for something that does not exist.
    /// Turning the hand is the only thing that puts every side in front of the
    /// camera, and the frames are read across the movement.
    ///
    /// The other reason this exists: "I cannot see" is a true sentence and a
    /// useless one. Naming what is missing AND the move that fixes it turns a
    /// dead end into an instruction, which is what an instructor would say.
    var howToBringIntoView: String {
        switch self {
        case .tool:
            "bring the knife up in front of you and turn it slowly so I can see it"
        case .controlPoint:
            "roll your hand slowly towards me so I can see where it meets the blade"
        case .thumb:
            "turn your hand slowly towards me and your thumb will come round"
        case .indexFinger:
            "roll your hand slowly the other way so the far side of the blade comes round"
        case .remainingFingers:
            "lower your hand and turn it a little so I can see your fingers on the handle"
        case .wrist:
            "pull back a touch and turn slowly so I get your wrist as well"
        case .guidingHand:
            "look down at the hand holding the food, so I can see your fingertips"
        case .ingredient:
            "look down at what you are cutting"
        case .workSurface:
            "pull your head back a little so I get the whole board"
        case .result:
            "spread it out into one layer and look straight down at it"
        case .cookingSurface:
            "look down into the pan"
        case .fat:
            "tilt the pan gently so the oil pools where I can see it"
        case .liquid:
            "look straight down into the pan so I can see the surface"
        case .heatSource:
            "glance down at the burner"
        }
    }
}

/// What Chef should be looking at for a given skill.
///
/// The instructor deliverable is blunt about this and it changed the shape of
/// the type: for most knife cuts the **outcome** is far more readable than the
/// motion. Nobody can judge a dice at seven frames a second, but a board of
/// finished cubes shows size spread and squareness at a glance. Authoring this
/// per skill is what stops us pointing the camera at the wrong thing and then
/// blaming the camera.
enum SkillAssessmentMode: String, Hashable, Sendable {
    /// Watch it being done. Grips, claw, thermometer placement, basting.
    case process
    /// Look at what it produced. Dice, julienne, mince, chopped herbs.
    case outcome
    /// Both matter and both are asked for, process first.
    case processThenOutcome
    /// Chef coaches and observes, but never certifies from sight.
    ///
    /// Roughly a fifth of the catalog lands here and the deliverable is
    /// emphatic that it should: "balance a sauce", "understand acid", "fix
    /// bland food" are real skills that a camera cannot grade. Forcing them
    /// into a visual rubric produces a pose classifier with a confident
    /// opinion about flavour, which is worse than admitting the limit.
    case dialogue

    /// How the lesson screen offers it. "Check your grip" is wrong on a board
    /// of diced onion and "look at what you made" is wrong on a knife hold.
    var calloutTitle: String {
        switch self {
        case .process: "Let Chef watch you do it"
        case .outcome: "Let Chef look at what you made"
        case .processThenOutcome: "Let Chef watch, then check your work"
        case .dialogue: "Talk it through with Chef"
        }
    }
}

/// How much a mistake costs, which is what decides who gets corrected first.
///
/// Replaces relying on array order alone. Order still breaks ties, but a
/// cosmetic flaw authored above a safety issue can no longer outrank it, and
/// the ladder here is the one an instructor actually uses.
/// A question about where a landmark sits, and what each answer means.
///
/// Every case is a plain thing to look for. None of them is a judgement, and the
/// reader is told not to make one, because the moment it is allowed to conclude
/// it reaches for the familiar answer instead of the visible one.
struct SkillLandmarkQuestion: Sendable, Equatable, Hashable {
    /// Asked exactly as written.
    let question: String
    /// The only accepted answers, in the order they are offered.
    let answers: [String]
    /// The answer that means stop the lesson now.
    let dangerous: String
    /// The answer that means they have it right.
    let correct: String
    /// The answer that maps to a named mistake in the rubric.
    let mistake: (answer: String, key: String)?
    /// The answer meaning it could not be found.
    let cannotTell: String

    init(
        question: String,
        answers: [String],
        dangerous: String,
        correct: String,
        mistake: (answer: String, key: String)? = nil,
        cannotTell: String = "cannotTell"
    ) {
        self.question = question
        self.answers = answers
        self.dangerous = dangerous
        self.correct = correct
        self.mistake = mistake
        self.cannotTell = cannotTell
    }

    static func == (a: Self, b: Self) -> Bool {
        a.question == b.question && a.answers == b.answers
            && a.dangerous == b.dangerous && a.correct == b.correct
            && a.mistake?.answer == b.mistake?.answer && a.mistake?.key == b.mistake?.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(question)
        hasher.combine(answers)
    }
}

/// One narrow perceptual question about a picture, with a closed answer set.
///
/// Keyed by region so it refines what `visibility` already reports: instead of
/// "can you see the thumb", which the model answers `sufficient` to
/// unconditionally, this asks where the thumb actually is and offers
/// "cannotTell" as a first class answer rather than a failure.
struct SkillObservation: Sendable, Equatable, Hashable {
    /// The part of the technique this is about.
    let region: SkillVisibilityRegion
    /// Asked exactly as written, so the wording can be tuned per skill.
    let question: String
    /// The only answers accepted. Must include an honest "cannot tell" option,
    /// or the question becomes a forced choice and forced choices get guessed.
    let answers: [String]
    /// The answer that means "I could not place it", excluded from the majority.
    let cannotTell: String

    init(
        region: SkillVisibilityRegion,
        question: String,
        answers: [String],
        cannotTell: String = "cannotTell"
    ) {
        self.region = region
        self.question = question
        self.answers = answers
        self.cannotTell = cannotTell
    }
}

enum SkillMistakeSeverity: Int, Hashable, Sendable, Comparable {
    /// Cosmetic. Say it only when nothing else is wrong.
    case cosmetic = 0
    /// Works, but is harder than it needs to be.
    case efficiency = 1
    /// Will measurably hurt the finished dish.
    case outcomeCost = 2
    /// Will ruin it within seconds if nothing changes. Burning, splitting,
    /// scorching: the cases where explaining before acting is the wrong order.
    case irreversible = 3
    /// Somebody could get hurt. Outranks everything, including the
    /// one-correction rule.
    case safety = 4

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// A legitimate fork in the technique that Chef must resolve before judging.
///
/// The single most repeated instruction in the deliverable: *ask the intended
/// style before correcting a legitimate branch.* A French omelette and an
/// American one are both correct and have opposite rubrics, so browning is
/// either a fault or the point depending on an answer only the cook has. Same
/// for soft versus firm scrambled eggs, crisp versus tender fried eggs, and
/// the two schools of dicing an onion.
///
/// Without this the app picks a school and tells everybody else they are wrong,
/// which is exactly the pedantry the whole rubric system exists to avoid.
struct SkillIntentBranch: Hashable, Sendable {
    /// What Chef asks, out loud, before she looks.
    let question: String
    /// The branches, keyed so a rubric line can name one.
    let options: [SkillIntentOption]
    /// Used when the cook does not answer or says they do not mind. Never
    /// silently "the classical one": it is whichever is kindest to judge.
    let defaultKey: String
}

struct SkillIntentOption: Hashable, Sendable {
    let key: String
    /// How the cook might say it, for matching what they actually said.
    let spokenLabel: String
    /// What changes about the assessment when this branch is chosen.
    let judgeAgainst: String
}

/// The curriculum, translated into terms a vision model can be held to.
///
/// Prose rather than flags on purpose. The thing being described is "what good
/// looks like and how much variation is fine", and every attempt to reduce that
/// to booleans produces a pose classifier that fails people for having small
/// hands. The model gets the reasoning; the app keeps control of what is done
/// with the answer.
struct SkillVisualRubric: Hashable, Sendable {
    /// One line naming what is being assessed, for the top of the prompt.
    let subject: String

    /// The technique we are teaching, as the assessor should understand it.
    let targetTechnique: [String]

    /// Differences that are NOT mistakes. This list is the difference between an
    /// instructor and a pedant, and it is the reason false criticism is rarer
    /// than it would otherwise be.
    let acceptableVariations: [String]

    /// Known wrong-for-this-lesson habits, most important first. The order is
    /// the coaching priority: when several are true, the cook hears about the
    /// first one and nothing else.
    let rankedMistakes: [SkillCoachableMistake]

    /// Configurations that stop the lesson immediately. Only things we would be
    /// confident about from a photograph.
    let safetySignals: [String]

    /// Equipment this lesson is written for.
    let supportedEquipment: [String]

    /// Equipment that needs a different lesson, and should be said so rather
    /// than coached badly.
    let unsupportedEquipment: [String]

    /// Things a photograph genuinely cannot establish, listed so the model is
    /// told not to try. Grip pressure is the canonical one: it looks identical
    /// at every force.
    let notVisuallyAssessable: [String]

    /// Below this, Polly does not critique. She says she cannot see well enough,
    /// which is a different sentence and a much better one.
    let confidenceFloor: Double

    /// The fork to resolve out loud before judging anything, when there is one.
    let intentBranch: SkillIntentBranch?

    /// What good and bad look like in the finished thing, in the tolerances a
    /// home cook should actually be held to.
    ///
    /// Separate from `targetTechnique` because they are different standards and
    /// conflating them is the documented failure mode: professional julienne is
    /// 3mm square, a home cook needs sticks that cook at the same rate, and
    /// holding the second person to the first number is how an instructor loses
    /// somebody who was doing fine.
    let outcomeTolerance: [String]

    /// How the attempt reads back in the cook's own history when it passed.
    ///
    /// Authored per skill because the history screen is read weeks later by the
    /// person who did it. "Clean pinch grip" beats "passed", and neither can be
    /// written generically once the catalog covers pans and sauces as well as
    /// knives.
    let passSummary: String

    /// The same, for a pass on a cook's own legitimate variation.
    let variationSummary: String

    /// Sounds that support a reading. **Never sufficient on their own.**
    ///
    /// The deliverable is careful here and the caution is kept: hood fans,
    /// music, pan material, microphone gain and distance all move the signal,
    /// so audio raises or lowers confidence in something already seen, or
    /// prompts a question. It never fails a cook by itself, and there is no
    /// path in the decision layer by which it can.
    let audioSignals: [String]

    init(
        subject: String,
        targetTechnique: [String],
        acceptableVariations: [String],
        rankedMistakes: [SkillCoachableMistake],
        safetySignals: [String] = [],
        supportedEquipment: [String] = [],
        unsupportedEquipment: [String] = [],
        notVisuallyAssessable: [String] = [],
        confidenceFloor: Double = 0.55,
        passSummary: String = "Done well.",
        variationSummary: String = "Their own way of doing it, and in control of it.",
        intentBranch: SkillIntentBranch? = nil,
        outcomeTolerance: [String] = [],
        audioSignals: [String] = []
    ) {
        self.subject = subject
        self.targetTechnique = targetTechnique
        self.acceptableVariations = acceptableVariations
        self.rankedMistakes = rankedMistakes
        self.safetySignals = safetySignals
        self.supportedEquipment = supportedEquipment
        self.unsupportedEquipment = unsupportedEquipment
        self.notVisuallyAssessable = notVisuallyAssessable
        self.confidenceFloor = confidenceFloor
        self.passSummary = passSummary
        self.variationSummary = variationSummary
        self.intentBranch = intentBranch
        self.outcomeTolerance = outcomeTolerance
        self.audioSignals = audioSignals
    }

    /// Mistakes in the order they should be raised: severity first, then the
    /// author's ranking. Nothing reads `rankedMistakes` directly for coaching.
    var coachingOrder: [SkillCoachableMistake] {
        rankedMistakes.enumerated()
            .sorted { a, b in
                a.element.severity == b.element.severity
                    ? a.offset < b.offset
                    : a.element.severity > b.element.severity
            }
            .map(\.element)
    }
}

/// One habit worth correcting, with the words to correct it in.
///
/// The fix is authored rather than generated because this is the sentence the
/// whole feature is judged on. A model asked to invent it produces "remember to
/// use a pinch grip for better control", which is advice from a webpage. The
/// specific, physical instruction is the thing that makes a cook believe they
/// were actually seen.
struct SkillCoachableMistake: Hashable, Sendable {
    /// Matches `SkillGripFamily` or a criterion name the assessor returns.
    let key: String
    /// What the cook is doing, in the assessor's terms.
    let observation: String
    /// What Polly says. One instruction, physical, no preamble.
    let correction: String
    /// Why it matters, offered only if the cook asks.
    let rationale: String
    /// True when this is wrong for this lesson rather than wrong in general.
    /// Changes the language from "fix that" to "not for this one".
    let isContextual: Bool

    /// How much this one costs, which decides whether it jumps the queue.
    let severity: SkillMistakeSeverity

    /// The confidence needed to say this specific thing, when it differs from
    /// the rubric's floor.
    ///
    /// The deliverable rejects one global threshold, and it is right to. A
    /// fingertip in the blade path is worth mentioning on thinner evidence than
    /// a slightly bent wrist, because being wrong costs a moment of
    /// embarrassment in one direction and a cut finger in the other. Nil means
    /// use the rubric's floor.
    let confidenceFloor: Double?

    /// What must have been visible for this to be sayable.
    ///
    /// "Your index finger is along the spine" is only a thing we get to say if
    /// somebody saw the index finger. Without this the model can infer a finger
    /// position from the shape of the hand and be confidently wrong about the
    /// one thing the cook can check for themselves.
    let requiresVisible: [SkillVisibilityRegion]

    /// The plain observations that have to hold before this correction is
    /// allowed out, keyed by region.
    ///
    /// This exists because `requiresVisible` turned out to be unenforceable.
    /// Across a whole archived session the model marked every region
    /// `sufficient` every single time, including on a frame that was an
    /// unreadable smear, so a gate built on its own visibility report can never
    /// fire. Asking "where is the thumb" with three possible answers is a
    /// different kind of question: narrow, checkable, and answered from the
    /// picture rather than from the verdict it is about to give.
    ///
    /// The rule is positive evidence, not absence of contradiction. Handle grip
    /// requires the thumb to READ as on the handle. A thumb it cannot place is
    /// not permission to correct, which is exactly what the rubric text has
    /// always said and the code was not enforcing.
    let impliedBy: [SkillVisibilityRegion: [String]]

    init(
        key: String,
        observation: String,
        correction: String,
        rationale: String,
        isContextual: Bool = false,
        severity: SkillMistakeSeverity = .outcomeCost,
        confidenceFloor: Double? = nil,
        requiresVisible: [SkillVisibilityRegion] = [],
        impliedBy: [SkillVisibilityRegion: [String]] = [:]
    ) {
        self.key = key
        self.observation = observation
        self.correction = correction
        self.rationale = rationale
        self.isContextual = isContextual
        self.severity = severity
        self.confidenceFloor = confidenceFloor
        self.requiresVisible = requiresVisible
        self.impliedBy = impliedBy
    }
}
