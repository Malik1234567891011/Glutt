import CoreGraphics
import Foundation
import UIKit

/// Why a frame is not worth showing Polly. Carried all the way out to the tool
/// result so she can say "hold still for a second" instead of guessing at a
/// smear, or asking about a pan she cannot actually see.
enum VisualFrameRejection: String, Sendable, Error {
    case noFrames = "no_frames"
    case tooOld = "frame_too_old"
    case blurred = "frame_blurred"
    case tooDark = "frame_too_dark"
    case tooBright = "frame_too_bright"
    /// The glasses camera is on its way up and has not delivered a frame yet.
    ///
    /// Its own case because it is the one failure that fixes itself. A cook who
    /// asks "does this look right" before the first frame arrives used to hear
    /// "no picture is coming through, check the camera" — advice for a problem
    /// they do not have, about a camera that is working. Chef needs to say she
    /// is nearly there and answer from what she already knows.
    ///
    /// The window is about two seconds over Bluetooth. It was 14 to 20 on the
    /// Wi-Fi transport, which is why this case exists at all.
    case warmingUp = "camera_warming_up"
    /// The feed was running and has stopped, rather than the picture being old
    /// because the cook moved.
    ///
    /// `tooOld` tells them to look at what they are working on, which is the
    /// right advice when a head turn left the buffer behind and useless advice
    /// when nothing has arrived over the radio for a minute. In a real cook Chef
    /// said "point it at the cutting board and hold still" three times at a cook
    /// who was already pointing at the cutting board and holding still.
    case feedStopped = "camera_feed_stopped"
    /// The hand is in shot and far too small to judge.
    ///
    /// The case that came out of actually looking at what the assessor was
    /// being sent. A cook standing at a counter is looking AT the counter, and
    /// a camera on their face frames the whole kitchen: fridge, sink, washing
    /// up. Their hand lands in a bottom corner at between one and four per cent
    /// of the picture, which puts the thumb at roughly fifteen pixels.
    ///
    /// The model does not refuse that. It answers, and it gets it wrong: on a
    /// measured example it reported `handleGrip` on a grip whose thumb was
    /// plainly on the blade once the corner was cropped out. That is a false
    /// correction, and the honest response is not a better prompt, it is asking
    /// them to bring their hand up.
    case subjectTooFar = "subject_too_far"
    /// The request to look never completed. Nothing to do with the camera.
    ///
    /// Every assessment failure used to be reported as `noFrames`, which Chef
    /// renders as a camera problem, so a dropped network request came out as
    /// "I cannot get a picture from your glasses". The cook then goes and
    /// fiddles with hardware that is working perfectly. Measured: an
    /// NSURLErrorDomain failure archived under exactly that wording.
    case lookRequestFailed = "look_request_failed"

    /// What Polly should ask the cook to do about it. Kept here so the wording
    /// lives next to the condition that produced it.
    var suggestion: String {
        switch self {
        case .lookRequestFailed:
            return "The pictures were taken fine and the request to read them failed, so this is "
                + "your problem and not theirs. Say something went wrong on your end and you did "
                + "not get a look that time, and offer to try again in a moment. Do NOT say you "
                + "cannot see, do not mention the camera or the glasses, and do not ask them to "
                + "move, turn, hold still or check anything, because everything at their end "
                + "worked."
        case .subjectTooFar:
            return "Their hand is in shot but far too small to read, because the camera is "
                + "framing the whole room. Ask them to bring their hand up in front of them, "
                + "closer to their face, and to look straight at it. Do not comment on their "
                + "grip until they have."
        case .noFrames:
            return "No picture is coming through. Ask the cook to check the camera."
        case .tooOld:
            return "The view has gone stale. Ask the cook to look at what they are working on."
        case .blurred:
            return "Everything is smeared with movement. Ask the cook to hold still for a second."
        case .tooDark:
            return "It is too dark to judge. Ask the cook to turn a light on or move closer."
        case .tooBright:
            return "The picture is blown out. Ask the cook to angle away from the light."
        case .feedStopped:
            return "The picture has stopped arriving from the glasses. This is not something "
                + "the cook can fix by moving or holding still, so do not ask them to. Say you "
                + "have lost the view, keep going on what they tell you, and mention it may "
                + "come back on its own."
        case .warmingUp:
            // Phrased as what to do rather than what to avoid. The first version
            // ended "do not ask them to check the camera", which is the exact
            // instruction a model is most likely to invert, and it put the
            // wrong phrase in front of it at the same time.
            return "Your eyes are still connecting, which takes a couple of seconds. Say so "
                + "in your own words, answer from the recipe and what they have told you, and "
                + "offer to look properly in a moment. Nothing is wrong on their end."
        }
    }
}

/// Cheap, local measurements of a single frame.
struct VisualFrameQuality: Sendable, Equatable {
    /// Mean gradient magnitude, roughly 0 to 1. Motion blur collapses it.
    let sharpness: Double
    /// Mean luminance, 0 to 1.
    let brightness: Double
    /// Difference hash. Near-identical frames land within a few bits.
    let hash: UInt64
}

/// Decides which of the recent frames, if any, is worth sending.
///
/// At 24 frames a second almost everything the glasses produce is worthless to
/// send: duplicates of the last one, smears from a head turn, a counter nobody
/// is working at. This is what keeps us from paying to show a model seven
/// blurry pictures of the same pan every second.
///
/// Heuristics only, no model. Core Graphics on a small grayscale buffer is
/// enough to tell a smear from a still, and cheap enough to run on every frame.
/// Pure and synchronous so it can be tested against real footage; callers run it
/// off the main actor.
struct VisualFrameGate: Sendable {
    /// An absolute floor, and deliberately a very low one. Measured across the
    /// wok fixture, real cooking footage spans only 0.019 to 0.037: shallow
    /// depth of field, a dark hob, and compression leave little gradient even
    /// when the shot is perfectly steady. An absolute quality bar set anywhere
    /// near "sharp" rejects an entire dim kitchen, so this only catches a frame
    /// with essentially no detail in it at all.
    ///
    /// Judging blur is `relativeSharpnessFloor`'s job.
    var minSharpness: Double = 0.012
    /// How sharp the chosen frame must be relative to the sharpest this scene
    /// has recently managed. This is the real blur test, because it adapts:
    /// a bright cutting board and a dark pan score nothing alike, but in both
    /// cases a frame taken mid head-turn scores well below that scene's own
    /// recent best.
    var relativeSharpnessFloor: Double = 0.6
    var minBrightness: Double = 0.06
    var maxBrightness: Double = 0.97
    /// Hamming distance under which two frames are "the same picture".
    var duplicateDistance: Int = 6

    init() {}

    /// Side length of the grayscale buffer everything is measured on. Small
    /// enough to be nearly free, large enough that blur still shows.
    private static let workingSide = 96

    // MARK: - Measuring

    func measure(_ image: UIImage) -> VisualFrameQuality? {
        guard let gray = Self.grayscale(image, side: Self.workingSide) else { return nil }
        return VisualFrameQuality(
            sharpness: Self.sharpness(gray, side: Self.workingSide),
            brightness: Self.brightness(gray),
            hash: Self.differenceHash(gray, side: Self.workingSide)
        )
    }

    /// The reason this frame is unusable, or nil when it is fine.
    func rejection(for quality: VisualFrameQuality) -> VisualFrameRejection? {
        if quality.brightness < minBrightness { return .tooDark }
        if quality.brightness > maxBrightness { return .tooBright }
        if quality.sharpness < minSharpness { return .blurred }
        return nil
    }

    func isDuplicate(_ a: VisualFrameQuality, _ b: VisualFrameQuality) -> Bool {
        Self.hammingDistance(a.hash, b.hash) <= duplicateDistance
    }

    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - Measurements

    /// Mean absolute gradient, normalised. A held shot has real edges; a frame
    /// captured mid head-turn has had them averaged away by the exposure.
    static func sharpness(_ gray: [UInt8], side: Int) -> Double {
        guard side > 1, gray.count >= side * side else { return 0 }
        var total = 0.0
        var samples = 0
        for y in 0..<(side - 1) {
            let row = y * side
            let next = row + side
            for x in 0..<(side - 1) {
                let here = Double(gray[row + x])
                let dx = abs(Double(gray[row + x + 1]) - here)
                let dy = abs(Double(gray[next + x]) - here)
                total += dx + dy
                samples += 1
            }
        }
        guard samples > 0 else { return 0 }
        // Two differences per sample, each at most 255.
        return total / (Double(samples) * 510)
    }

    static func brightness(_ gray: [UInt8]) -> Double {
        guard !gray.isEmpty else { return 0 }
        let total = gray.reduce(0.0) { $0 + Double($1) }
        return total / (Double(gray.count) * 255)
    }

    /// 64-bit difference hash: compare each pixel with its right-hand neighbour
    /// on an 8-row by 9-column grid sampled out of the working buffer. Robust to
    /// brightness drift, which a plain average hash is not, and that matters
    /// under a flickering gas flame.
    static func differenceHash(_ gray: [UInt8], side: Int) -> UInt64 {
        guard side >= 9, gray.count >= side * side else { return 0 }
        var hash: UInt64 = 0
        var bit = 0
        for row in 0..<8 {
            let y = row * side / 8
            for column in 0..<8 {
                let xLeft = column * side / 9
                let xRight = (column + 1) * side / 9
                if gray[y * side + xLeft] < gray[y * side + xRight] {
                    hash |= (1 << UInt64(bit))
                }
                bit += 1
            }
        }
        return hash
    }

    /// Square grayscale buffer. Core Graphics rather than Core Image on purpose:
    /// no CIContext to allocate and no GPU round trip, on a path that may run
    /// tens of times a second.
    static func grayscale(_ image: UIImage, side: Int) -> [UInt8]? {
        guard side > 0, let cgImage = image.cgImage else { return nil }
        var buffer = [UInt8](repeating: 0, count: side * side)
        let space = CGColorSpaceCreateDeviceGray()
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let context = CGContext(
                      data: base,
                      width: side,
                      height: side,
                      bitsPerComponent: 8,
                      bytesPerRow: side,
                      space: space,
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else { return false }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? buffer : nil
    }
}
