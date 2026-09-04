import CoreGraphics
import Foundation
import Vision

/// Finding the cook's hands, and nothing else.
///
/// Split out of `SkillFrameFocus` so it can be compiled and run **off the
/// phone**. Two things forced that:
///
/// 1. `VNDetectHumanHandPoseRequest` returns nothing whatsoever in the iOS
///    Simulator. A test of hand selection that runs there is green because it
///    found no hands, which is worse than no test at all.
/// 2. Running the test on the device crashes before it can connect, so the
///    normal answer to (1) is not available either.
///
/// This file imports no UIKit, so `scripts/verify-knife-selection` compiles it
/// straight into a small macOS tool and checks the real selection against real
/// frames. Same source, same constants, same answer. If this ever needs UIKit,
/// the verification loop dies with it.
enum HandBoxes {

    /// One hand, in Vision's normalised bottom-left space.
    struct Found {
        let box: CGRect
        /// 0 splayed open, roughly 1 curled around something.
        let closedness: CGFloat
        /// Fingertips we located, in the order the marks are numbered.
        /// Empty when Vision could not place them confidently enough to draw.
        let tips: [Tip]
    }

    /// One fingertip we are confident enough about to draw a mark on.
    struct Tip {
        let finger: Finger
        /// Normalised, bottom-left origin, same space as `box`.
        let point: CGPoint
    }

    enum Finger: Int, CaseIterable {
        case thumb = 1, index, middle, ring, little

        var joint: VNHumanHandPoseObservation.JointName {
            switch self {
            case .thumb: .thumbTip
            case .index: .indexTip
            case .middle: .middleTip
            case .ring: .ringTip
            case .little: .littleTip
            }
        }

        var spoken: String {
            switch self {
            case .thumb: "thumb"
            case .index: "index finger"
            case .middle: "middle finger"
            case .ring: "ring finger"
            case .little: "little finger"
            }
        }
    }

    /// How sure Vision must be that this is a hand at all.
    static let minimumObservationConfidence: Float = 0.5

    /// How sure Vision must be about a single landmark before it counts toward
    /// the hand's box.
    ///
    /// Was 0.5, and that one number is why the cropper kept choosing an empty
    /// fist over the hand holding the knife. **A hand holding something has low
    /// confidence landmarks, because the thing it is holding is covering
    /// them.** An open empty hand shows Vision all twenty one points cleanly and
    /// scores high on every one, so the old threshold was in effect a filter
    /// that preferred hands with nothing in them, inside a feature whose whole
    /// purpose is to look at what is in the cook's hand.
    ///
    /// Measured on archived frames, knife hand box area:
    ///
    ///     frame        at 0.50            at 0.15
    ///     200723/1     0.0000 (dropped)   0.0060
    ///     200723/3     0.0121             0.0273
    ///     182732/1     0.0087             0.0249
    ///
    /// At 0.5 the knife hand was discarded in all three, the fist was cropped
    /// and sent, and the model correctly reported a hand holding no knife.
    static let minimumLandmarkConfidence: Float = 0.15

    /// A box narrower than this is one landmark and a rounding error.
    static let minimumBoxSide: CGFloat = 0.004

    static func detect(in image: CGImage) -> [Found] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else { return [] }

        var found: [Found] = []
        for observation in observations
        where observation.confidence >= minimumObservationConfidence {
            guard let points = try? observation.recognizedPoints(.all) else { continue }
            var box: CGRect?
            for (_, point) in points where point.confidence >= minimumLandmarkConfidence {
                let dot = CGRect(x: point.location.x, y: point.location.y, width: 0, height: 0)
                box = box.map { $0.union(dot) } ?? dot
            }
            // A very low bar. The hand we most want is the one most occluded,
            // so anything with two landmarks that are not the same point is
            // worth keeping and letting the reader decide.
            guard let box, box.width > minimumBoxSide, box.height > minimumBoxSide
            else { continue }
            let tips = Finger.allCases.compactMap { finger -> Tip? in
                guard let point = points[finger.joint],
                      point.confidence >= minimumLandmarkConfidence
                else { return nil }
                return Tip(finger: finger, point: point.location)
            }
            found.append(Found(box: box, closedness: closedness(of: points), tips: tips))
        }
        return found
    }

    static func closedness(
        of points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint]
    ) -> CGFloat {
        // The wrist's own confidence is deliberately not checked.
        //
        // It is usually the least confident joint on the hand, because in a
        // first person view it sits at the very bottom of the frame or just
        // outside it. Measured on the failing frames: 0.49 and 0.20, both under
        // the threshold used everywhere else, so gating on it returned zero for
        // every hand and this whole signal was dead on arrival. Its POSITION is
        // still reported and is still a fine origin to measure from.
        guard let wrist = points[.wrist] else { return 0 }

        let tips: [VNHumanHandPoseObservation.JointName] =
            [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
        let knuckles: [VNHumanHandPoseObservation.JointName] =
            [.thumbMP, .indexMCP, .middleMCP, .ringMCP, .littleMCP]

        func meanDistance(_ joints: [VNHumanHandPoseObservation.JointName]) -> CGFloat? {
            // A lower bar than elsewhere: this is a shape comparison across
            // five fingers, so one soft landmark moves the mean a little rather
            // than producing a wrong claim about a specific finger.
            let usable = joints.compactMap { points[$0] }.filter { $0.confidence >= 0.25 }
            guard !usable.isEmpty else { return nil }
            let total = usable.reduce(CGFloat(0)) { sum, point in
                let dx = point.location.x - wrist.location.x
                let dy = point.location.y - wrist.location.y
                return sum + sqrt(dx * dx + dy * dy)
            }
            return total / CGFloat(usable.count)
        }

        guard let tipSpan = meanDistance(tips),
              let knuckleSpan = meanDistance(knuckles),
              knuckleSpan > 0
        else { return 0 }

        // Open hand: tips sit well beyond the knuckles, so the ratio is high.
        // Curled hand: tips come back toward the wrist and it falls under one.
        return max(0, min(1, 2 - (tipSpan / knuckleSpan)))
    }
}
