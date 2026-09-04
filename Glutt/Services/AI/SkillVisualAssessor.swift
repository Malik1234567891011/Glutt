import Foundation

/// Looking at what the cook is actually doing, and saying only what is
/// supported by the picture.
///
/// The division of labour here is the whole design. The model is asked to
/// **observe**: what tool is this, which fingers can I see, where are they, is
/// anything dangerous. The app decides what that **means** and what to say about
/// it, using the rubric the skill was authored with. So the model never invents
/// coaching, never ranks its own criticisms, and never gets to be confident on
/// our behalf.
///
/// That split is not fussiness. A model asked "is this grip correct?" will
/// answer the question every time, including when the thumb is behind the
/// handle and it cannot see it, and the resulting sentence is indistinguishable
/// from a real observation. One confidently wrong correction costs more trust
/// than ten missed ones.
enum SkillVisualAssessor {

    /// Tags the proxy's `ai_usage` row. Its own feature because this is the
    /// expensive surface: several images per attempt, and several attempts per
    /// lesson.
    static let usageFeature = "skill_visual_check"

    enum AssessorError: Error {
        case noUsableFrames
    }

    /// Assess a held pose from the frames captured during the hold.
    ///
    /// Frames are sent as separate user messages because `LLMClient.Message`
    /// carries one image each. Several views of a mostly static hand is the
    /// point: one blurred or occluded instant then costs a frame rather than
    /// the answer.
    /// Which model reads the pictures for a physical skill.
    ///
    /// Not the app default, and the reason is measured. On one archived frame
    /// with the cook's whole hand closed around a knife blade, GPT reported "on
    /// the handle" under nine different framings: a one line prompt, the full
    /// uncropped frame, a free description with no schema at all, a forced two
    /// way choice with both answers written out, gpt-4.1 and gpt-5. Hands are
    /// usually on handles, and that expectation beat the pixels every time.
    ///
    /// That is a property of a model family rather than of our prompt, so the
    /// cheapest way to find out whether it is shared is to ask a different
    /// family. Only the vision read moves; everything else in the app stays put.
    static let visionModel = "claude-sonnet-5"

    /// Answer from the single question when it is decisive, instead of waiting
    /// for the full rubric request.
    ///
    /// Set to `false` to restore the old behaviour completely. See the block in
    /// `assess` for what this trades away.
    static let answerFromTheSingleQuestionAlone = true

    static func assess(
        check: SkillVisualCheck,
        frames: [Data],
        client: LLMClient = .live
    ) async throws -> SkillVisualAssessment {
        // Crop to the hand FIRST, then downscale. The other order throws away
        // the pixels that decide the verdict and then enlarges what is left.
        //
        // This is here rather than in the frame ring because it is about what
        // the model needs, not about what the camera produced, and because a
        // frame kept for the archive should be the one that was actually sent.
        // One crop per hand, newest frame first, capped at the frame budget.
        // Two hands in the newest frame beats one hand in each of three, because
        // the question is which hand rather than which moment.
        // The wide shot AND the close ups, not one or the other.
        //
        // Sending only crops is what let a look come back `handleGrip` at 0.95
        // on a picture with no knife in it. A crop with nothing around it cannot
        // be told apart from a patch of skin, so there was no way for her to
        // notice that the thing she was describing was not there. The wide frame
        // answers "is a knife in this scene at all, and which hand is holding
        // it"; the crops answer "where exactly is the thumb". Neither question
        // can be answered from the other's picture.
        let perFrame = frames.map(SkillFrameFocus.focusOnHands)
        // Every hand in the newest frame, because which hand is the question.
        //
        // When there is only one, spend the remaining budget on that same hand a
        // moment earlier instead, since a knife grip cannot be read from a
        // single angle: the thumb is on one face of the blade and the curled
        // index finger on the other.
        let newest = (perFrame.first ?? []).filter { $0.coverage != nil }
        var closeUps: [SkillFrameFocus.Focused]
        if newest.count > 1 {
            closeUps = Array(newest.prefix(3))
        } else {
            closeUps = perFrame.compactMap { $0.first { $0.coverage != nil } }
        }
        // Two close ups, not three. Each picture is real latency on the slow
        // request, and a look that times out at forty five seconds is worth
        // less than a slightly thinner one that arrives.
        closeUps = Array(closeUps.prefix(min(2, check.framesPerLook)))
        // 1600, not the 1280 default: the first frame is now a real photograph
        // rather than a video still, and the whole point of taking it is detail
        // that a smaller picture cannot carry.
        let wide = frames.first.flatMap { ImagePrep.prepareForVision($0, maxDimension: 1600) }

        var composed: [(jpeg: Data, isWide: Bool)] = []
        if let wide { composed.append((wide, true)) }
        for shot in closeUps {
            guard let prepared = ImagePrep.prepareForVision(shot.jpeg) else { continue }
            composed.append((prepared, false))
        }
        guard !composed.isEmpty else { throw AssessorError.noUsableFrames }
        let usable = composed.map(\.jpeg)
        let focused = perFrame.flatMap { $0 }

        // Refuse rather than answer badly.
        //
        // When a hand was found in every frame and was tiny in all of them, the
        // model will still return a verdict, and it will be a guess. On the run
        // that produced this check it guessed `handleGrip` on a grip whose thumb
        // was on the blade. Asking them to bring their hand up is both more
        // honest and more useful than a confident wrong correction.
        let seen = focused.compactMap(\.coverage)
        if !seen.isEmpty, seen.allSatisfy({ $0 < SkillFrameFocus.tooFarToJudge }) {
            let best = seen.max() ?? 0
            PollyDebugLog.shared.log(
                "skill: hand is only \(String(format: "%.1f", best * 100))% of the frame, too far to judge")
            throw VisualFrameRejection.subjectTooFar
        }

        var messages: [LLMClient.Message] = [
            .system(systemPrompt(check: check, pictures: composed.count))
        ]
        var closeUpNumber = 0
        for (index, shot) in composed.enumerated() {
            let caption: String
            if shot.isWide {
                caption = "Picture \(index + 1): the whole scene, as the cook sees it. "
                    + "Use this one to work out what is actually here and which hand is "
                    + "holding it. Do not read fine detail from it."
            } else {
                closeUpNumber += 1
                caption = "Picture \(index + 1): a close up of the hand, "
                    + (closeUpNumber == 1 ? "taken at the same moment." : "taken a moment earlier.")
                    + " Read the detail from this one."
            }
            messages.append(.user(caption, imageData: shot.jpeg))
        }
        messages.append(.user(userPrompt(check: check)))

#if DEBUG
        await MainActor.run { SkillLookMirror.shared.show(sent: usable) }
#endif

        // Asked alongside the rubric, not inside it.
        //
        // Started before the main request and awaited after, so the cook waits
        // for one round trip rather than two.
        async let decisive = decisiveReading(check: check, pictures: usable, client: client)
        // Awaited before the slow request is even attempted, so its answer is
        // in hand whether that one succeeds, fails or times out.
        let separate = await decisive

        // ONE SWITCH. Set to false and every look goes back to making the slow
        // rubric request first, exactly as it did before.
        //
        // Why this is worth having: a cook session answers "does this look
        // right" in about a second, because it drops the frame straight into
        // the Realtime session that is already open, already warm and already
        // holding the context. A skill check instead opens a fresh HTTP request
        // carrying fifteen thousand characters of rubric and three pictures,
        // and waits for the whole JSON before anybody hears a word. Measured on
        // device: twenty seven and thirty two seconds, and one timeout at
        // forty five.
        //
        // The single question is two pictures and one sentence, and it already
        // decides everything that gates the lesson: stop, pass, or ask. When it
        // gives a straight answer there is nothing the slow request adds that
        // the cook is waiting to hear.
        //
        // WHAT IS LOST while this is on: the specific named corrections. Nobody
        // hears "your index finger is along the spine" or "your wrist is bent",
        // and a wrong knife is not called out, because only the rubric request
        // knows about those. It is speed against detail, and it is here as a
        // switch rather than a rewrite precisely because that trade is worth
        // watching before it is settled.
        if answerFromTheSingleQuestionAlone,
           let quick = standaloneAnswer(check: check, reading: separate) {
            PollyDebugLog.shared.log(
                "skill: single question was decisive, skipping the slow rubric request")
#if DEBUG
            await MainActor.run {
                SkillLookMirror.shared.answered(
                    "\(quick.overall.rawValue) · from the single question alone",
                    readings: check.decisiveRegion.map {
                        ["\($0.rawValue)  \(separate ?? "-")"]
                    } ?? [])
            }
            SkillLookArchive.save(
                frames: usable, check: check, assessment: quick,
                handCoverage: focused.compactMap(\.coverage).max(),
                originals: frames)
#endif
            return quick
        }

        do {
            let decoded = try await client.chatJSON(
                SkillVisualAssessment.self,
                messages: messages,
                temperature: 0.1,
                feature: usageFeature,
                // 60, not 45. Measured: this request takes forty six seconds on
                // a good run, so the old limit was cutting off answers that were
                // about to arrive. It is a backstop rather than a budget, since
                // the single question already answers the cook in a few seconds
                // if this one never lands.
                timeout: 60,
                model: visionModel
            )
            // Archived AFTER the answer so the pictures and the verdict land in
            // one folder. `usable` rather than `frames`: these are the bytes the
            // model actually received, downscaled and recompressed, and judging
            // its eyesight against the originals would be judging the wrong
            // images.
            // Built once and left alone. A `var` here is captured by the debug
            // mirror's closure below, which Swift 6 makes an error and which is
            // a real hazard either way: that closure runs on another actor.
            let answer: SkillVisualAssessment = {
                var merged = decoded
                if let region = check.decisiveRegion, let reading = separate {
                    merged.decisive = SkillVisualAssessment.DecisiveReading(
                        region: region.rawValue, answer: reading)
                }
                return merged
            }()
            if let region = check.decisiveRegion, let reading = separate {
                PollyDebugLog.shared.log(
                    "skill: asked on its own, \(region.rawValue) is \(reading)")
            }

#if DEBUG
            await MainActor.run {
                SkillLookMirror.shared.answered(
                    "\(answer.overall.rawValue)"
                        + (answer.primaryIssueKey.map { " · \($0)" } ?? "")
                        + " · \(Int(answer.confidence * 100))%"
                        + " · tool in picture \(answer.toolPicture)",
                    readings: check.observations.map { observation in
                        let each = answer.observations.enumerated().map { index, reading in
                            "\(index + 1):\(reading[observation.id] ?? "-")"
                        }.joined(separator: "  ")
                        let agreed = answer.reading(for: observation) ?? "no majority"
                        return "\(observation.id)  \(each)  → \(agreed)"
                    })
            }
            SkillLookArchive.save(
                frames: usable, check: check, assessment: answer,
                handCoverage: focused.compactMap(\.coverage).max(),
                originals: frames)
#endif
            return answer
        } catch {
#if DEBUG
            await MainActor.run {
                SkillLookMirror.shared.failed(String(describing: error).prefix(120).description)
            }
            // A failed look is worth keeping too. Half the arguments about what
            // she can see turn out to be about a request that never landed.
            SkillLookArchive.save(
                frames: usable, check: check, assessment: nil,
                error: String(describing: error),
                handCoverage: focused.compactMap(\.coverage).max(),
                originals: frames)
#endif
            // The small question may well have landed even though the big one
            // did not, and it is the one that decides the outcome anyway.
            //
            // A cook asked, waited forty five seconds and got nothing, because
            // the rubric request timed out. That request carries four pictures
            // and fifteen thousand characters and is genuinely slow; the single
            // question carries two pictures and one sentence and comes back in
            // a few seconds. Losing the whole look because the slow half died,
            // while holding a perfectly good answer to the only question that
            // gates safety, is the worst possible trade.
            if let answer = standaloneAnswer(check: check, reading: separate) {
                PollyDebugLog.shared.log(
                    "skill: rubric request failed, answering from the single question instead")
                return answer
            }
            throw error
        }
    }

    /// A verdict built from the single question alone.
    ///
    /// Deliberately thin. It knows where the deciding part of the hand is and
    /// nothing else, so it never names a specific mistake: it can stop a cook
    /// whose hand is on the steel, and it can confirm one whose hand is not.
    /// Anything subtler waits for a request that actually completes.
    ///
    /// Nil when the single question could not place it either, because then
    /// there is genuinely nothing to say and the caller should report the
    /// failure honestly.
    private static func standaloneAnswer(
        check: SkillVisualCheck,
        reading: String?
    ) -> SkillVisualAssessment? {
        guard let region = check.decisiveRegion,
              let observation = check.decisiveObservation,
              let reading, reading != observation.cannotTell,
              observation.answers.contains(reading)
        else { return nil }

        // Enough visibility for the decision layer to get as far as the gates,
        // which is honest: to place these fingers on the blade or the handle it
        // had to see both the hand and the tool.
        let visibility = Dictionary(
            uniqueKeysWithValues: check.requiredVisibility.map { ($0.rawValue, SkillVisualAssessment.Visibility.sufficient) })

        let dangerous = check.dangerousReadings[region]?.contains(reading) ?? false
        var assessment = SkillVisualAssessment(
            equipment: SkillVisualAssessment.Equipment(
                reading: "the tool for this lesson", supported: true, confidence: 0.7),
            visibility: visibility,
            overall: dangerous ? .needsAdjustment : .ready,
            confidence: 0.7,
            // Says where the verdict came from, so the archive does not go
            // blank on this path.
            //
            // It did: every fast look wrote an empty "what she claims she
            // actually saw", which is the one section built to settle arguments
            // about her eyesight. A faster answer that cannot be checked
            // afterwards is a bad trade.
            observedEvidence: [
                "answered from the single question alone, without the rubric request",
                "\(region.rawValue) read as \(reading)",
            ],
            toolPicture: 1)
        assessment.decisive = SkillVisualAssessment.DecisiveReading(
            region: region.rawValue, answer: reading)
        return assessment
    }

    /// Ask the one deciding question on its own, with nothing else in scope.
    ///
    /// Never throws. This runs beside the real assessment and a failure here
    /// must leave that assessment exactly as it was rather than taking the whole
    /// look down with it.
    private static func decisiveReading(
        check: SkillVisualCheck,
        pictures: [Data],
        client: LLMClient
    ) async -> String? {
        guard let observation = check.decisiveObservation,
              !pictures.isEmpty
        else { return nil }

        struct OneAnswer: Decodable { let answer: String }

        // The close ups only. The wide shot is context for the rubric and here
        // it is just another thing to be distracted by.
        var content: [LLMClient.Message] = [.system(
            "You look at photographs of a cook's hand and answer ONE question about what is "
            + "in them. Answer only from what is visible. Reply with JSON and nothing else.")]
        for (index, jpeg) in pictures.suffix(2).enumerated() {
            content.append(.user("Picture \(index + 1).", imageData: jpeg))
        }
        content.append(.user(
            observation.question
            + "\n\nReply exactly as {\"answer\": \"\(observation.answers.joined(separator: " | "))\"}"))

        do {
            let reply = try await client.chatJSON(
                OneAnswer.self,
                messages: content,
                temperature: 0,
                feature: "\(usageFeature)_decisive",
                timeout: 30,
                model: visionModel)
            return observation.answers.contains(reply.answer) ? reply.answer : nil
        } catch {
            PollyDebugLog.shared.log("skill: the single question failed — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Prompt

    /// Built from the rubric rather than written here, so authoring a new
    /// physical skill never means editing this file.
    static func systemPrompt(check: SkillVisualCheck, pictures: Int = 3) -> String {
        let r = check.rubric
        return """
        You are helping a cooking instructor evaluate \(r.subject). The images are
        first person, taken from the cook's own point of view a second or two
        apart.

        \(viewingGuidance(check))

        # The technique being taught
        \(bullets(r.targetTechnique))\(intentSection(r))\(toleranceSection(r))\(audioSection(r))

        # Differences that are NOT mistakes
        Do not report these as problems. A cook whose hand differs from the reference
        in one of these ways is holding the knife correctly.
        \(bullets(r.acceptableVariations))

        # Habits worth naming, if you can actually see them
        Report at most ONE of these, as `primaryIssueKey`, using the key exactly as
        written. They are listed **most costly first**: anything unsafe, then
        anything that will ruin the food in the next few seconds, then whatever
        most affects the result. When several are true, name the one highest in
        this list, not the one easiest to see. If none apply, return null.
        \(r.coachingOrder.map { "- `\($0.key)`: \($0.observation)" }.joined(separator: "\n"))

        # Stop the lesson for these
        \(bullets(r.safetySignals))
        Only report a safety concern you can see. A finger you cannot find is not a
        finger in a dangerous place.

        # Equipment this lesson is for
        \(bullets(r.supportedEquipment))
        If the tool is clearly one of these instead, set `overall` to
        `unsupportedEquipment` and name it. Do not coach a grip for a knife this
        lesson was not written for.
        \(bullets(r.unsupportedEquipment))

        # Things you cannot determine from an image
        Never claim any of these. If asked to judge one, say you cannot see it.
        \(bullets(r.notVisuallyAssessable))

        # You may be shown a hand that has nothing to do with this
        The pictures are cropped to each hand found in the shot, one hand per
        picture, and a cook often has two: one holding the thing you are here to
        judge and one holding their phone, a cloth, or nothing at all. So expect
        pictures that are not relevant, and judge the hand that is holding the
        tool.

        If NONE of the pictures contains the tool, say so. Set `tool` visibility
        to `insufficient`, set `overall` to `cannotAssess`, and put what you
        actually saw in `observedEvidence`, for example "a hand holding a phone".
        Do not describe a grip on a tool that is not in the picture.
        Never say the equipment is supported when you cannot see the equipment.

        That has happened. Three pictures of a hand holding a phone came back as
        "a chef's knife" with "the whole hand is behind the blade on the
        handle", which is an invented observation of an object that was not
        there, and it is worse than any wrong correction because nothing
        downstream can catch it.

        # First, find the tool. `toolPicture` before anything else.
        You are given a wide shot and then one close up per hand. The cook has
        two hands and usually only one of them is holding anything, so at least
        one close up is of a hand holding nothing, or holding a phone, or resting
        on the counter. That is expected and it is not a mistake by anyone.
        Your first job is to say which picture actually shows the tool this
        lesson is about, by its number. Use the wide shot to work out what is in
        the scene and where, then name the close up that shows it.
        If NO picture shows the tool, answer 0, set `overall` to `cannotAssess`,
        and stop there. Do not judge a hand that is not holding the tool, and
        never describe a tool you cannot see. Saying "the whole hand is behind
        the blade on the handle" about a picture with no blade in it has
        happened, and it is worse than any wrong correction, because nothing
        downstream can catch it.
        Everything after this point is about the picture you just named. Ignore
        the others except as context.

        # The one question that decides this lesson
        \(check.landmark?.question ?? "")
        Answer it in the `landmark` field. Answer it from what you can find in
        the picture, not from what a hand holding a knife usually looks like.
        Hands are usually on handles, and that expectation has been measured
        overriding the pixels on this exact question, so treat a familiar-looking
        answer as a warning rather than a confirmation.

        # The magenta rings are there to help you, use them
        The close up pictures have small magenta rings drawn on the cook's
        fingertips, numbered 1 to 5: 1 thumb, 2 index, 3 middle, 4 ring,
        5 little. We put them there, they are not in the kitchen, and they are
        placed by a hand tracker rather than by you.
        Use them as anchors. When a question asks about a finger, find its ring
        and answer for what is directly under and just inside that ring, rather
        than judging the pose as a whole. A grip that "looks like" a familiar one
        is exactly how a hand closed around a blade gets read as a correct pinch,
        because both of them put the thumb and index finger on the steel. The
        rings on fingers 3, 4 and 5 are what separate the two, and they are worth
        more than any impression of the shape.
        If a ring is missing, that finger was not located. Say cannotTell rather
        than guessing where it went.

        # Answer the picture questions first, and answer them per picture
        `observations` comes first in the JSON for a reason: it is what you can
        SEE, and it has to be settled before you decide what it MEANS.
        You have been given \(pictures) pictures, so `observations` must contain
        exactly \(pictures) entries, in the same order, one per picture, using
        only the answers offered. Not fewer. A picture you skip is a picture
        nobody asked about, and the one you are most tempted to skip is the one
        that is hardest to read, which is exactly the one carrying the answer.
        Answer each picture on its own. Do not copy your answer for picture one
        into picture two because they are the same hand. They were taken at
        different moments from different angles and they genuinely differ, and
        two pictures disagreeing is useful information that the app knows what
        to do with.
        `cannotTell` is a real answer and a good one. Use it whenever the part
        is hidden, out of frame, facing away, or too small or too blurred to
        place. It is not a failure and it costs nothing: the app simply asks the
        cook to turn their hand. Guessing costs a great deal, because a wrong
        correction is the one thing that makes a cook stop believing you.
        The wide picture will often be `cannotTell` for everything. That is
        correct and expected. Read the scene from it, not the detail.

        # How to answer
        1. FIRST decide whether you can see enough. Report visibility per region
           honestly. A region hidden behind something, or out of frame, is
           `insufficient`, not `partial`.
           Some hiding is NORMAL and is not a problem to report. These images come
           from the cook's own eyes while they work, so parts of the scene pass
           behind hands, tools and pans constantly. Mark what you cannot see
           `insufficient` and carry on assessing everything you CAN see.
        2. `cannotAssess` is ONLY for when \(requiredList(check)) is not visible.
           Nothing else earns it. If those are visible, assess, and keep assessing
           even when every other region is hidden. Answering `cannotAssess` because
           one optional region is obscured tells a cook who is looking straight at
           their own work that you cannot see it, which is the fastest way to lose
           them.
           What you must not do is guess. Do not report a habit about a region you
           marked `insufficient`: if you cannot see it, you cannot know what it is
           doing, so leave `primaryIssueKey` null and let the visibility field say
           why. Not seeing something and it being wrong are different answers and
           the app says different words for each.
        3. Separate what you SAW from what you CONCLUDE. `observedEvidence` is a
           short list of plain physical observations, each one something another
           person could verify from the same image. Your conclusions belong in the
           other fields.
           Keep them SHORT. Two or three, a dozen words each at most. A cook is
           standing there holding a knife while you write them, and one archived
           look spent its time on five sentences of hedging about which picture
           showed what. None of that reaches them; it only makes them wait.
           An observation about something that is not in the picture is not an
           observation. These images are cropped tight around a hand, so fingers
           run off the edge constantly. If a finger leaves the frame you cannot
           see where it ends, and that region is `insufficient`. Marking it
           `sufficient` and then writing "the remaining fingers are wrapped round
           the handle" is a guess with an observation's wording, and it has
           already been caught doing exactly that on a picture where those
           fingers were outside the image entirely.
           Before you mark a region `sufficient`, check that you could point at
           it in the picture. If you could not, it is `insufficient`, and that is
           a perfectly good answer.
        4. Be conservative. A false correction is worse than a missed one: it makes
           a cook distrust everything else you say. When two readings are possible,
           report the lower confidence.
        5. Confidence is your own, from 0 to 1, for the assessment as a whole.
           Below \(String(format: "%.2f", r.confidenceFloor)) the app will not repeat
           any criticism to the cook, so there is no cost to being honest.

        Reply with JSON only, no prose around it, in exactly this shape:
        \(schema(check: check, pictures: pictures))
        """
    }

    static func userPrompt(check: SkillVisualCheck) -> String {
        let regions = check.reportedVisibility.map(\.rawValue).joined(separator: ", ")
        let subject = switch check.assessmentMode {
        case .outcome: "the finished result shown"
        default: "the single attempt shown"
        }
        return """
        Assess \(subject) across the images above, using all of them together.
        Report visibility for: \(regions), taking the best view of each.
        Answer with the JSON object only.
        """
    }

    /// How to read this particular set of images, which depends entirely on
    /// whether they are angles on one moving thing or looks at a finished one.
    private static func viewingGuidance(_ check: SkillVisualCheck) -> String {
        if let note = check.viewingNote { return note }
        switch check.assessmentMode {
        case .outcome:
            return """
            # Views of a finished result
            These show something the cook has already produced, spread out to be
            looked at. Judge it as a whole: the spread of sizes across the batch,
            not the single best or single worst piece. A few outliers in an
            otherwise even batch are normal food, not a failure.
            """
        case .process, .processThenOutcome, .dialogue:
            return """
            # They are angles, not attempts
            The images are moments from one continuous attempt, taken while the
            cook's hands were moving. COMBINE them into a single assessment. If
            something is clearly visible in ANY view, you have seen it, and its
            visibility is whatever the BEST view showed, not the worst. Do not
            assess each image separately, and do not report a region as hidden
            because it happened to be hidden in the most recent one.

            Things will be at different angles in each view. That is the point,
            not an inconsistency to flag.
            """
        }
    }

    /// The fork the cook has already resolved out loud, so the model judges the
    /// style they are actually cooking rather than the one the book prefers.
    private static func intentSection(_ r: SkillVisualRubric) -> String {
        guard let branch = r.intentBranch else { return "" }
        let options = branch.options
            .map { "- `\($0.key)` (\($0.spokenLabel)): \($0.judgeAgainst)" }
            .joined(separator: "\n")
        return """


        # This technique has more than one correct version
        The cook has been asked: "\(branch.question)". Judge against the branch
        they chose, and against `\(branch.defaultKey)` if they did not choose.
        Never mark one branch wrong for not being another.
        \(options)
        """
    }

    private static func toleranceSection(_ r: SkillVisualRubric) -> String {
        guard !r.outcomeTolerance.isEmpty else { return "" }
        return """


        # How close is close enough
        These are the tolerances a home cook is held to, which are looser than a
        professional exercise on purpose. Judge against these, not against a
        culinary school standard.
        \(bullets(r.outcomeTolerance))
        """
    }

    private static func audioSection(_ r: SkillVisualRubric) -> String {
        guard !r.audioSignals.isEmpty else { return "" }
        return """


        # Sound, if it is mentioned to you
        You are given images, not audio. These are listed only so you know what
        the cook may describe. Never infer them from a picture.
        \(bullets(r.audioSignals))
        """
    }

    /// The regions that actually gate an assessment, named in the prompt so the
    /// model is not left inferring which ones matter.
    /// The closed answer sets, spelled out so the model has no room to invent
    /// a fourth answer.
    private static func observationFields(_ check: SkillVisualCheck) -> String {
        check.observations
            .map { "\"\($0.id)\": \"\($0.answers.joined(separator: " | "))\"" }
            .joined(separator: ", ")
    }

    private static func requiredList(_ check: SkillVisualCheck) -> String {
        let names = check.requiredVisibility.map { "`\($0.rawValue)`" }
        guard let last = names.last else { return "nothing" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " or " + last
    }

    private static func bullets(_ lines: [String]) -> String {
        lines.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func schema(check: SkillVisualCheck, pictures: Int) -> String {
        let regions = check.reportedVisibility
            .map { "\"\($0.rawValue)\": \"sufficient | partial | insufficient\"" }
            .joined(separator: ",\n            ")
        let criteria = check.rubric.coachingOrder
            .map { "\"\($0.key)\"" }
            .joined(separator: " | ")
        // ONE ENTRY PER PICTURE, generated from the real count.
        //
        // This used to print exactly two entries whatever it had been given, and
        // the model copied the shape it was shown: a look with three pictures
        // came back with two readings, a look with four came back with three.
        // The picture it dropped was picture three, the only one in which the
        // cook's thumb was visible, so the majority came out `NO MAJORITY` and
        // the grip could not be judged. The answer was in the frame, in the
        // request, and never asked about.
        let entries = (1...max(1, pictures))
            .map { "            { \"picture\": \($0), \(observationFields(check)) }" }
            .joined(separator: ",\n")
        let observations = check.observations.isEmpty ? "" : """
          "observations": [
        \(entries)
          ],

        """
        let landmark = check.landmark.map {
            "  \"landmark\": \"\($0.answers.joined(separator: " | "))\",\n"
        } ?? ""
        return """
        {
          "toolPicture": 0,
        \(landmark)
        \(observations)  "equipment": {
            "reading": "what tool you believe this is, in plain words",
            "supported": true,
            "confidence": 0.0
          },
          "handedness": "left | right | unknown",
          "visibility": {
            \(regions)
          },
          "safety": {
            "immediateConcern": false,
            "description": "null, or what you can see that is dangerous",
            "confidence": 0.0
          },
          "techniqueFamily": "a short plain label for the style you saw, or unknown",
          "overall": "ready | acceptableVariation | needsAdjustment | cannotAssess | unsupportedEquipment",
          "confidence": 0.0,
          "primaryIssueKey": "null, or one of: \(criteria)",
          "observedEvidence": ["two or three observations, each under twelve words"]
        }
        """
    }
}

// MARK: - The answer

/// What the model saw. Deliberately close to the wire: interpretation happens
/// in `SkillCoachDecision`, not here.
struct SkillVisualAssessment: Decodable, Sendable, Equatable {

    struct Equipment: Decodable, Sendable, Equatable {
        let reading: String
        let supported: Bool
        let confidence: Double
    }

    struct Safety: Decodable, Sendable, Equatable {
        let immediateConcern: Bool
        let description: String?
        let confidence: Double
    }

    enum Visibility: String, Decodable, Sendable {
        case sufficient
        case partial
        case insufficient

        /// Enough to judge on. `partial` counts: a thumb seen at an angle is
        /// still a thumb we can place, and demanding perfect views would send
        /// every real cook round the retry loop forever.
        var isUsable: Bool { self != .insufficient }
    }

    enum Overall: String, Decodable, Sendable {
        case ready
        case acceptableVariation
        case needsAdjustment
        case cannotAssess
        case unsupportedEquipment
    }

    let equipment: Equipment
    let handedness: String?
    let visibility: [String: Visibility]
    let safety: Safety
    let techniqueFamily: String?
    let overall: Overall
    let confidence: Double
    let primaryIssueKey: String?
    let observedEvidence: [String]

    /// One entry per picture: region name to the answer given for it.
    ///
    /// Kept as raw strings because the answer sets are authored per skill and
    /// this type must not need editing to add one.
    let observations: [[String: String]]

    /// Which picture the tool was actually in, 1 based. Zero means none of them.
    ///
    /// The cropper sends one close up per hand and cannot tell which hand holds
    /// what, because the hand holding a knife is the one whose landmarks the
    /// knife is covering. So the reader picks, and this is the answer.
    let toolPicture: Int

    /// Where the deciding landmark sits, when the check asks for one. Raw
    /// because the answers are authored per skill.
    let landmark: String?

    /// A reading taken in its own request, which outranks anything this
    /// assessment says about the same region. See `decisiveRegion`.
    var decisive: DecisiveReading?

    /// A reading taken in its own request.
    struct DecisiveReading: Sendable, Equatable {
        let region: String
        let answer: String
    }

    /// A value from the model that we want as a string and will accept in any
    /// scalar shape it arrives in.
    ///
    /// Written after a schema that listed `"picture": 1` alongside the answers
    /// threw `typeMismatch: expected String, found number` on every single look
    /// in a session. The lesson went completely silent, because a look that
    /// cannot be decoded is a look with no answer to say. Nothing about one
    /// stray integer should be able to do that, so this decodes whatever turns
    /// up and lets the unknown keys sit there harmlessly.
    private struct LooseScalar: Decodable {
        let text: String
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let string = try? value.decode(String.self) { text = string }
            else if let int = try? value.decode(Int.self) { text = String(int) }
            else if let double = try? value.decode(Double.self) { text = String(double) }
            else if let bool = try? value.decode(Bool.self) { text = String(bool) }
            else { text = "" }
        }
    }

    // Tolerant decoding: a model that omits an optional field should not fail
    // the whole assessment, because the app can say "I could not see" perfectly
    // well from a partial answer and cannot say anything at all from a throw.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        equipment = try c.decodeIfPresent(Equipment.self, forKey: .equipment)
            ?? Equipment(reading: "unknown", supported: true, confidence: 0)
        handedness = try c.decodeIfPresent(String.self, forKey: .handedness)
        visibility = try c.decodeIfPresent([String: Visibility].self, forKey: .visibility) ?? [:]
        safety = try c.decodeIfPresent(Safety.self, forKey: .safety)
            ?? Safety(immediateConcern: false, description: nil, confidence: 0)
        techniqueFamily = try c.decodeIfPresent(String.self, forKey: .techniqueFamily)
        overall = try c.decodeIfPresent(Overall.self, forKey: .overall) ?? .cannotAssess
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        // "null" arrives as a real string often enough to be worth handling.
        let key = try c.decodeIfPresent(String.self, forKey: .primaryIssueKey)
        primaryIssueKey = (key == "null" || key?.isEmpty == true) ? nil : key
        let loose = try c.decodeIfPresent([[String: LooseScalar]].self, forKey: .observations) ?? []
        observations = loose.map { $0.mapValues(\.text) }
        toolPicture = try c.decodeIfPresent(Int.self, forKey: .toolPicture) ?? 0
        landmark = try c.decodeIfPresent(String.self, forKey: .landmark)
        observedEvidence = try c.decodeIfPresent([String].self, forKey: .observedEvidence) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case equipment, handedness, visibility, safety, techniqueFamily
        case overall, confidence, primaryIssueKey, observedEvidence
        case observations, toolPicture, landmark
    }

    /// Test seam.
    init(
        equipment: Equipment,
        handedness: String? = nil,
        visibility: [String: Visibility] = [:],
        safety: Safety = Safety(immediateConcern: false, description: nil, confidence: 0),
        techniqueFamily: String? = nil,
        overall: Overall,
        confidence: Double,
        primaryIssueKey: String? = nil,
        observedEvidence: [String] = [],
        observations: [[String: String]] = [],
        toolPicture: Int = 0,
        landmark: String? = nil
    ) {
        self.equipment = equipment
        self.handedness = handedness
        self.visibility = visibility
        self.safety = safety
        self.techniqueFamily = techniqueFamily
        self.overall = overall
        self.confidence = confidence
        self.primaryIssueKey = primaryIssueKey
        self.observedEvidence = observedEvidence
        self.observations = observations
        self.toolPicture = toolPicture
        self.landmark = landmark
    }

    /// What the pictures agreed on for one region, or nil when they did not.
    ///
    /// A majority of the pictures that could place it, and "could not place it"
    /// does not vote. Three pictures reading onBlade, onBlade, cannotTell is a
    /// clear answer; onBlade, onHandle, cannotTell is not, and returning nil
    /// there is the honest outcome rather than picking the first.
    ///
    /// Ties return nil on purpose. A tie is the model telling us it changed its
    /// mind between two pictures of the same hand, which is exactly the noise
    /// that produced opposite verdicts on near identical grips.
    func reading(for observation: SkillObservation) -> String? {
        // A reading taken on its own wins. It was measured right where the one
        // buried in the full prompt was measured wrong, on the same pictures.
        if let decisive, decisive.region == observation.id {
            return decisive.answer == observation.cannotTell ? nil : decisive.answer
        }
        let answers = observations
            .compactMap { $0[observation.id] }
            .filter { $0 != observation.cannotTell }
        guard !answers.isEmpty else { return nil }

        var tally: [String: Int] = [:]
        for answer in answers { tally[answer, default: 0] += 1 }
        let ranked = tally.sorted { $0.value > $1.value }
        guard let top = ranked.first else { return nil }
        if ranked.count > 1, ranked[1].value == top.value { return nil }
        return top.key
    }

    /// Whether every region the check needs came back usable.
    func sawEnough(for check: SkillVisualCheck) -> Bool {
        check.requiredVisibility.allSatisfy { visibility[$0.rawValue]?.isUsable ?? false }
    }

    /// The regions we could not see, in the order the check lists them, so the
    /// cook is asked about the most important one first.
    func unseenRegions(for check: SkillVisualCheck) -> [SkillVisibilityRegion] {
        check.reportedVisibility.filter { visibility[$0.rawValue]?.isUsable != true }
    }
}
