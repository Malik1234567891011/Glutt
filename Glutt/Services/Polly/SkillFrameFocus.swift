import CoreGraphics
import UIKit
import Vision

/// Find the cook's hand in a first-person frame and spend the whole picture
/// on it.
///
/// Built after looking at what the assessor was actually being sent. A frame
/// arrives 504 by 896 and the hand holding the knife occupies something like
/// eight per cent of one corner, because the camera points where the head
/// points and a cook standing at a counter is looking at the counter. The rest
/// is fridge, sink, washing up and the phone.
///
/// At that scale the thumb is about fifteen pixels, which is not enough to tell
/// a thumb resting on the flat of a blade from a thumb wrapped round a handle.
/// The model duly guessed, and reported `handleGrip` on a grip whose thumb was
/// plainly on the blade once the corner was cropped out and enlarged. That is a
/// false correction, which is the one failure the whole rubric exists to
/// prevent, and no amount of prompt writing fixes it: the information was not
/// in the image.
///
/// So the crop happens before the prompt ever gets involved. Same pixel budget,
/// spent on the hand instead of on the kitchen.
///
/// **Never returns something worse than it was given.** No hand found, low
/// confidence, or a box that makes no sense, and the original frame goes
/// through untouched.
enum SkillFrameFocus {

    /// How much room to leave around the hand.
    ///
    /// Generous, and it has to be: the rubric requires `tool` and
    /// `controlPoint`, so a crop tight to the knuckles would cut off the blade,
    /// which turns a resolution problem into a visibility one. Vision returns
    /// landmarks for the hand only, and a chef's knife extends a long way
    /// past it.
    ///
    /// How much of the finished picture the hand should fill.
    ///
    /// A target, not a multiplier, and the third attempt at this. A fixed
    /// multiple of the hand cannot work across hand sizes: 2.5 cropped tight
    /// enough to cut the handle off below the knuckles, and 4.0 overshot the
    /// frame on a 5% hand and clamped straight back to the whole kitchen, which
    /// looked exactly like the union bug it replaced. Both were tuned on one
    /// example and broke on the next.
    ///
    /// Sizing the crop so the hand ends up at a fixed share of it is self
    /// correcting: a small hand gets a modest crop, a large one gets almost
    /// none.
    ///
    /// A quarter was still too tight. It framed the hand and lost the knife,
    /// and a hand with no visible tool is indistinguishable from a hand holding
    /// nothing. At 0.15 the archived originals all land with the blade above
    /// the hand and the handle below it, which is the only framing that can
    /// answer the question this rubric asks.
    static let handShareOfCrop: Double = 0.15

    /// Below this the detection is not worth acting on. A wrong crop is much
    /// worse than no crop: it would confidently send a picture of a countertop.
    private static let minimumConfidence: Float = 0.5

    /// How sure Vision must be about a single landmark before it counts toward
    /// the hand's box.
    ///
    /// Was 0.5, and that one number is why the cropper kept choosing an empty
    /// fist over the hand holding the knife. **A hand holding something has
    /// low confidence landmarks, because the thing it is holding is covering
    /// them.** An open empty hand shows Vision all twenty one points cleanly and
    /// scores high on every one. So the old threshold was, in effect, a filter
    /// that preferred hands with nothing in them, in a feature whose entire
    /// purpose is to look at what is in the cook's hand.
    ///
    /// Measured on the archived frames, knife hand box area:
    ///
    ///     frame        at 0.50            at 0.15
    ///     200723/1     0.0000 (dropped)   0.0060
    ///     200723/3     0.0121             0.0273
    ///     182732/1     0.0087             0.0249
    ///
    /// At 0.5 the knife hand was discarded in all three and the fist was
    /// cropped and sent. The model looked at it and correctly reported a hand
    /// holding no knife, which read as the model failing.
    private static let minimumLandmarkConfidence: Float = 0.15

    /// A hand already filling this much of the frame needs nothing done to it.
    private static let alreadyCloseEnough: CGFloat = 0.30

    /// Below this share of the frame, cropping cannot save it.
    ///
    /// Measured: a hand at 3.8% of a 504 by 896 frame is 93 pixels across, and
    /// the thumb inside it is about fifteen. Cropping buys roughly 1.6 times the
    /// effective resolution, which is worth having and is not enough to tell a
    /// thumb on a blade from a thumb on a handle. Under this, the honest answer
    /// is to ask them to bring their hand closer rather than to answer badly.
    static let tooFarToJudge: Double = 0.02

    /// One hand Vision found, and how curled it is.
    private struct Hand {
        let box: CGRect
        /// 0 splayed open, ~1 closed round something.
        let closedness: CGFloat
        let tips: [HandBoxes.Tip]
    }

    /// What came back from looking for a hand.
    struct Focused {
        /// The cropped frame, or the original when there was nothing to crop to.
        let jpeg: Data
        /// The hand's share of the ORIGINAL frame, nil when no hand was found.
        /// Reported rather than acted on here: whether a look is worth taking is
        /// the session's decision, not the cropper's.
        let coverage: Double?
    }

    /// Crop to each hand found, or hand back exactly what arrived.
    ///
    /// One image per hand rather than one image of everything, because which
    /// hand matters and nothing here can tell which is which. A cook reading
    /// the lesson off their phone has a phone hand and a knife hand, and the
    /// phone hand is bigger, more central and better lit. Picking the largest
    /// would pick the wrong one every time.
    ///
    /// So both go, cropped and separated, and the model is told it may be shown
    /// a hand that is holding nothing relevant. That is a question it can
    /// actually answer from a clear picture, and could not from a wide shot of
    /// a kitchen with two hands in opposite corners.
    static func focusOnHands(in jpeg: Data) -> [Focused] {
        guard let image = UIImage(data: jpeg), let cgImage = image.cgImage else {
            return [Focused(jpeg: jpeg, coverage: nil)]
        }
        let boxes = handBoxes(in: cgImage)
        guard !boxes.isEmpty else { return [Focused(jpeg: jpeg, coverage: nil)] }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Ordered by how closed the hand is, not by how big it is.
        //
        // Being straight about what this is worth: on the thirteen archived
        // looks it never once changed which hand came first, because the hands
        // that differ most in grip also differ most in size and the ordering
        // agreed either way. The case it was built for, a 0.9% knife hand
        // beside a 4% empty one, it gets WRONG: at that size the landmarks are
        // too weak to measure and the empty hand scored higher.
        //
        // It stays because the criterion is right where size is merely
        // convenient, and because the thing that actually rescues that case is
        // the filter below rather than any ordering. If a future archive shows
        // grip and size disagreeing and grip losing, this should go.
        let ordered = boxes.sorted { $0.closedness > $1.closedness }
        let cropped = ordered.compactMap { hand -> Focused? in
            crop(cgImage, to: hand.box, tips: hand.tips, width: width, height: height,
                 orientation: image.imageOrientation)
        }

        // Drop the hands that are too far away to be worth looking at.
        //
        // This is the one that decided every wrong verdict. A cook holding the
        // knife out to one side and their free hand nearer the camera produces
        // a 4% empty hand and a 0.9% knife hand, and sending both meant the
        // clearest picture in the set was of a hand holding nothing. She judged
        // that one, found no thumb on any blade, and said so.
        //
        // Ordering by size does not fix it, it causes it: the nearer hand wins,
        // and which hand is nearer is a coin toss. Measured across the archive,
        // the knife hand was the larger one in every look that passed and the
        // smaller one in the look that failed. The order is now by grip.
        //
        // So an unjudgeable hand is not sent at all. If that leaves nothing,
        // the assessor refuses and asks them to bring their hand up, which is
        // both true and the only thing that would have helped.
        // Filter only. The order is already grip first and must not be resorted
        // by size, which is the preference that caused every wrong verdict.
        // Every hand goes. Nothing is dropped here for being small.
        //
        // This used to keep only hands above `tooFarToJudge` and it was throwing
        // away the answer: the knife hand is the small, half hidden one exactly
        // because it is holding a knife, and the confident, roomy, well lit hand
        // is the empty one. Filtering on size therefore selected against the
        // subject of the lesson, every time, and the model was left describing a
        // fist and correctly reporting no knife in it.
        //
        // Which hand matters is a question about what is IN them, and nothing
        // here can see that. So they all go, and the reader is asked to say
        // which picture the tool is in. `coverage` still rides along so the
        // assessor can refuse when every hand really is too far.
        return cropped.isEmpty ? [Focused(jpeg: jpeg, coverage: nil)] : cropped
    }

    /// How much this hand looks like it is holding a chef's knife.
    ///
    /// Deliberately unimplemented until the harness says what to look for.
    /// Guessing at a feature and tuning it on one frame is how the crop got
    /// three wrong answers in a row already.
    static func toolScore(
        _ image: CGImage,
        around box: CGRect,
        width: CGFloat,
        height: CGFloat
    ) -> Double {
        0
    }

    private static func crop(
        _ cgImage: CGImage,
        to box: CGRect,
        tips: [HandBoxes.Tip] = [],
        width: CGFloat,
        height: CGFloat,
        orientation: UIImage.Orientation
    ) -> Focused? {
        // Vision works in a normalised, bottom-left origin space. Core Graphics
        // images are top-left. Getting this backwards crops the ceiling.
        let inPixels = CGRect(
            x: box.minX * width,
            y: (1 - box.maxY) * height,
            width: box.width * width,
            height: box.height * height)
        guard inPixels.width > 0, inPixels.height > 0 else { return nil }

        let coverage = Double((inPixels.width * inPixels.height) / (width * height))
        let padded = pad(inPixels, within: CGSize(width: width, height: height))
        guard let piece = cgImage.cropping(to: padded) else { return nil }

        // Sent at the size it was cut at. NOT enlarged back to the frame size,
        // which is what this did until the numbers came in.
        //
        // The old version drew the crop back up to the full frame so "the model
        // gets the resolution it is used to". Measured with `VisualFrameGate` on
        // an archive of real looks, that enlargement HALVED sharpness: the
        // originals score 0.028 to 0.033 and the enlarged crops cut from them
        // score 0.010 to 0.024. It was never adding detail, and it was visibly
        // destroying what was there, while disguising a two hundred pixel region
        // as a thousand pixel picture so that nothing downstream could tell.
        let cut = mark(
            UIImage(cgImage: piece, scale: 1, orientation: orientation),
            tips: tips, crop: padded, width: width, height: height)
        // 0.95, not 0.8, and this is not fussiness.
        //
        // The single fact that decides a knife grip is which side of the
        // BOLSTER the fingers are on, and the bolster is a thin bright band a
        // few pixels across. Thin high contrast edges are the first thing JPEG
        // ringing destroys, and this crop was being compressed three times over
        // on its way out: 0.6 leaving the camera, 0.8 here, 0.65 again in
        // `ImagePrep`. We were sanding off the one feature we were asking about.
        guard let jpeg = cut.jpegData(compressionQuality: 0.95) else { return nil }

        // Judge the crop we just made, not the frame it came from.
        //
        // This is the check that was missing when a look came back `handleGrip`
        // at 0.95 confidence on an unreadable brown smear. The frame was fine;
        // Vision had latched onto a half visible hand in a dark corner with no
        // knife near it, and the crop of that corner scored 0.0039 where every
        // other crop in the session scored between 0.0098 and 0.0243. The gate
        // that would have caught it already existed and was only ever run on
        // arriving frames, never on what we ourselves produced.
        let gate = VisualFrameGate()
        if let quality = gate.measure(cut), gate.rejection(for: quality) != nil {
            PollyDebugLog.shared.log(
                String(format: "skill: dropped a crop, sharpness %.4f brightness %.4f",
                       quality.sharpness, quality.brightness))
            return nil
        }
        return Focused(jpeg: jpeg, coverage: coverage)
    }

    /// Draw a numbered ring on each fingertip.
    ///
    /// This is set-of-mark prompting, and it is here because of a specific,
    /// documented weakness rather than a hunch. Asked "are the middle, ring and
    /// little fingers on the blade or the handle", the reader looked straight at
    /// a hand closed around a blade and answered "on the handle". That is not
    /// general stupidity: the same reader reliably calls boiling water, steam
    /// and pan colour, because those are gross texture judgements. This one is a
    /// fine occlusion boundary across a thin landmark between two low texture,
    /// similarly lit objects, which is the exact case the spatial reasoning
    /// literature reports these models collapsing on. Aggregation layers blur
    /// boundaries and downweight thin structures, so the bolster, which is the
    /// whole answer, is the first thing to go.
    ///
    /// Marking converts it from a spatial judgement into a lookup: not "where
    /// are the fingers" but "is the pixel under ring 3 grey steel or handle".
    /// Rings are drawn hollow and small on purpose, so the mark sits around the
    /// fingertip rather than covering the thing being asked about.
    private static func mark(
        _ image: UIImage,
        tips: [HandBoxes.Tip],
        crop: CGRect,
        width: CGFloat,
        height: CGFloat
    ) -> UIImage {
        guard !tips.isEmpty else { return image }
        let size = image.size
        let radius = max(7, min(size.width, size.height) * 0.045)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
            for tip in tips {
                // Vision is bottom-left, Core Graphics is top-left, and the
                // point has to land inside the crop we actually cut.
                let inFrame = CGPoint(x: tip.point.x * width, y: (1 - tip.point.y) * height)
                let local = CGPoint(
                    x: (inFrame.x - crop.minX) / crop.width * size.width,
                    y: (inFrame.y - crop.minY) / crop.height * size.height)
                guard local.x.isFinite, local.y.isFinite,
                      local.x > -radius, local.y > -radius,
                      local.x < size.width + radius, local.y < size.height + radius
                else { continue }

                let ring = CGRect(
                    x: local.x - radius, y: local.y - radius,
                    width: radius * 2, height: radius * 2)
                // Magenta: nothing in a kitchen is this colour, so a mark can
                // never be mistaken for part of the knife or the hand.
                context.cgContext.setStrokeColor(
                    UIColor(red: 1, green: 0, blue: 0.85, alpha: 1).cgColor)
                context.cgContext.setLineWidth(max(2, radius * 0.28))
                context.cgContext.strokeEllipse(in: ring)

                let label = "\(tip.finger.rawValue)" as NSString
                let font = UIFont.boldSystemFont(ofSize: radius * 1.5)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor(red: 1, green: 0, blue: 0.85, alpha: 1),
                    .strokeColor: UIColor.black,
                    .strokeWidth: -3,
                ]
                let measured = label.size(withAttributes: attributes)
                label.draw(
                    at: CGPoint(x: local.x + radius * 1.1, y: local.y - measured.height / 2),
                    withAttributes: attributes)
            }
        }
    }

    /// One box per hand, and emphatically NOT one box around all of them.
    ///
    /// The first version unioned every landmark from every hand, which is a
    /// bug with a very convincing disguise: with a phone in one hand and a
    /// knife in the other it reported a confident 27% "hand" that was actually
    /// the gap between them, padded out to the whole kitchen. The crop did
    /// nothing and the number in the log said it had worked.
    ///
    /// Pose rather than plain object detection because a hand holding a knife is
    /// a hand at an unusual angle, half occluded by its own fingers and by the
    /// blade, and the pose model handles that far better than a rectangle
    /// detector. It also degrades usefully: four confident landmarks still give
    /// a box worth cropping to.
    /// Everything the selector knows about one frame, for the offline harness.
    ///
    /// Exists because "it cropped the wrong hand" cannot be argued about from a
    /// log line. `SkillFrameFocusTests` runs this over the archived frames and
    /// checks the chosen crop actually contains the knife, which is the only way
    /// to know a change here helped rather than moved the failure.
    struct Candidate {
        /// Normalised, Vision's bottom-left origin space.
        let box: CGRect
        let closedness: CGFloat
        let coverage: Double
        let holdsTool: Double
    }

    /// Which crop index each hand became, so a harness can name them.
    static func candidates(in jpeg: Data) -> [Candidate] {
        guard let image = UIImage(data: jpeg), let cgImage = image.cgImage else { return [] }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        return handBoxes(in: cgImage).map { hand in
            Candidate(
                box: hand.box,
                closedness: hand.closedness,
                coverage: Double(hand.box.width * hand.box.height),
                holdsTool: toolScore(cgImage, around: hand.box, width: width, height: height))
        }
    }

    private static func handBoxes(in image: CGImage) -> [Hand] {
        HandBoxes.detect(in: image)
            .map { Hand(box: $0.box, closedness: $0.closedness, tips: $0.tips) }
    }

    /// How closed the fingers are, from 0 (splayed open) to about 1 (a fist).
    ///
    /// The signal that replaces "pick the biggest hand". A hand holding a knife
    /// is curled around it; a hand resting on the counter is not. Size cannot
    /// tell them apart, and worse, size actively prefers whichever hand is
    /// nearer the camera, which is a coin toss and was deciding every verdict.
    ///
    /// Measured as fingertip distance from the wrist against knuckle distance
    /// from the wrist, so it is scale free and works the same on a hand across
    /// the room as on one held up close.
    ///
    /// It does not separate a knife from a phone, and is not asked to. It
    /// separates holding something from holding nothing, which is the case that
    /// was failing. The prompt handles the rest by telling her she may be shown
    /// a hand holding something irrelevant.

    /// Size the crop so the hand fills `handShareOfCrop` of it, centred on the
    /// hand and kept inside the frame.
    private static func pad(_ rect: CGRect, within size: CGSize) -> CGRect {
        let handArea = rect.width * rect.height
        let frameArea = size.width * size.height
        guard handArea > 0, frameArea > 0 else { return rect }

        // Same aspect as the frame, scaled so the hand lands on the target.
        let scale = ((handArea / CGFloat(handShareOfCrop)) / frameArea).squareRoot()
        let width = min(size.width * scale, size.width)
        let height = min(size.height * scale, size.height)

        // Slide back inside rather than clamping the edges, so a hand near a
        // corner keeps the full crop instead of a sliver of one. What is beyond
        // the frame edge was never captured and no crop recovers it.
        var x = rect.midX - width / 2
        var y = rect.midY - height / 2
        x = min(max(0, x), size.width - width)
        y = min(max(0, y), size.height - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}
