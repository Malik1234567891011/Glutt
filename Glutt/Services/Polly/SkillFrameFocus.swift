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
    /// Tuned against real captured frames, twice, and the second time was the
    /// one that mattered.
    ///
    /// The first pass settled on 2.5 while the box was still the union of every
    /// hand, so it was padding something the size of a kitchen and 2.5 looked
    /// reasonable. With per-hand boxes the same number crops tight to the
    /// knuckles and cuts the handle off below them, which quietly destroys the
    /// judgement: the whole question is whether the hand is FORWARD on the
    /// blade or BACK on the handle, and you cannot answer that without both
    /// ends of the knife in shot. A measured crop showed blade and hand and no
    /// handle at all, and came back `handleGrip` on a textbook pinch.
    ///
    /// So: generous. A hand is a small object attached to a long one, and the
    /// long one is what the hand is being judged against.
    private static let padding: CGFloat = 4.0

    /// Below this the detection is not worth acting on. A wrong crop is much
    /// worse than no crop: it would confidently send a picture of a countertop.
    private static let minimumConfidence: Float = 0.5

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

        // Biggest first: when the budget forces a choice, a hand that fills more
        // of the picture is the one worth spending an image on.
        let cropped = boxes.compactMap { box -> Focused? in
            crop(cgImage, to: box, width: width, height: height, orientation: image.imageOrientation)
        }.sorted { ($0.coverage ?? 0) > ($1.coverage ?? 0) }

        return cropped.isEmpty ? [Focused(jpeg: jpeg, coverage: nil)] : cropped
    }

    private static func crop(
        _ cgImage: CGImage,
        to box: CGRect,
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

        // Back up to roughly the size the frame arrived at, so the model gets
        // the resolution it is used to rather than a small sharp square. The
        // upscale adds no information; it just stops the image being downsampled
        // again on the way out.
        let target = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let enlarged = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIImage(cgImage: piece, scale: 1, orientation: orientation)
                .draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = enlarged.jpegData(compressionQuality: 0.8) else { return nil }
        return Focused(jpeg: jpeg, coverage: coverage)
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
    private static func handBoxes(in image: CGImage) -> [CGRect] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else { return [] }

        var boxes: [CGRect] = []
        for observation in observations where observation.confidence >= minimumConfidence {
            guard let points = try? observation.recognizedPoints(.all) else { continue }
            var box: CGRect?
            for (_, point) in points where point.confidence >= minimumConfidence {
                let dot = CGRect(x: point.location.x, y: point.location.y, width: 0, height: 0)
                box = box.map { $0.union(dot) } ?? dot
            }
            // A box with no area is one landmark, which says where a fingertip
            // is and nothing about where to crop.
            if let box, box.width > 0.01, box.height > 0.01 { boxes.append(box) }
        }
        return boxes
    }

    /// Grow the box around its own centre and keep it inside the frame.
    private static func pad(_ rect: CGRect, within size: CGSize) -> CGRect {
        let grownWidth = rect.width * (1 + padding)
        let grownHeight = rect.height * (1 + padding)
        let grown = CGRect(
            x: rect.midX - grownWidth / 2,
            y: rect.midY - grownHeight / 2,
            width: grownWidth,
            height: grownHeight)

        // Slide back inside rather than clamping the edges, so a hand near a
        // corner keeps the full crop instead of a sliver of one.
        var x = grown.minX
        var y = grown.minY
        let w = min(grown.width, size.width)
        let h = min(grown.height, size.height)
        x = min(max(0, x), size.width - w)
        y = min(max(0, y), size.height - h)
        return CGRect(x: x, y: y, width: w, height: h).integral
    }
}
