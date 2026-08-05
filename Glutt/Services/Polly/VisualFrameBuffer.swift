import Foundation
import UIKit

/// One measured frame, held long enough to be chosen over its neighbours.
struct BufferedVisualFrame {
    let id: String
    let image: UIImage
    let quality: VisualFrameQuality
    let capturedAt: Date
}

/// A short rolling window of recent frames, and the rule for picking one.
///
/// Keeping only the newest frame, which is what the phone camera does, is fine
/// when the camera sits still on a counter. It is wrong for a camera strapped to
/// someone's head: the newest frame is as likely as not to be the middle of a
/// glance at the recipe. Holding a couple of seconds and choosing the sharpest
/// is the difference between Polly seeing the pan and Polly seeing a smear.
struct VisualFrameBuffer {
    /// Just over a second at 7 fps. Kept deliberately small: a 504x896 frame is
    /// about 1.8 MB decoded, so this is already ~14 MB of held images, and
    /// hanging on to more risks starving the pool the toolkit recycles frames
    /// through. Enough to have a real choice, not enough to be a leak.
    var capacity: Int = 8
    /// Sharpness scores are four bytes each, so this remembers far longer than
    /// the images do. It exists to answer "how sharp does this scene normally
    /// get", which a one-second window cannot: at any instant the sharpest
    /// frame in the window is by definition the window's own peak.
    var historyCapacity: Int = 64

    private(set) var frames: [BufferedVisualFrame] = []
    private(set) var sharpnessHistory: [Double] = []

    init(capacity: Int = 8, historyCapacity: Int = 64) {
        self.capacity = capacity
        self.historyCapacity = historyCapacity
    }

    mutating func insert(_ frame: BufferedVisualFrame) {
        frames.append(frame)
        if frames.count > capacity {
            frames.removeFirst(frames.count - capacity)
        }
        sharpnessHistory.append(frame.quality.sharpness)
        if sharpnessHistory.count > historyCapacity {
            sharpnessHistory.removeFirst(sharpnessHistory.count - historyCapacity)
        }
    }

    mutating func removeAll() {
        frames.removeAll()
        sharpnessHistory.removeAll()
    }

    var newest: BufferedVisualFrame? { frames.last }

    /// The sharpest this scene has managed lately. The baseline blur is judged
    /// against.
    var recentPeakSharpness: Double { sharpnessHistory.max() ?? 0 }

    /// The best frame no older than `maxAge`, or why there isn't one.
    ///
    /// Sharpest wins rather than newest. Near-duplicates are not filtered here:
    /// among equally recent frames of the same scene we want the best one, and
    /// deduplication belongs at the point where we decide whether to send
    /// anything at all.
    func best(
        maxAge: TimeInterval,
        now: Date,
        gate: VisualFrameGate
    ) -> Result<BufferedVisualFrame, VisualFrameRejection> {
        guard !frames.isEmpty else { return .failure(.noFrames) }

        let cutoff = now.addingTimeInterval(-maxAge)
        let recent = frames.filter { $0.capturedAt >= cutoff }
        guard !recent.isEmpty else { return .failure(.tooOld) }

        let usable = recent.filter { gate.rejection(for: $0.quality) == nil }
        guard let best = usable.max(by: { $0.quality.sharpness < $1.quality.sharpness }) else {
            // Nothing passed. Report the newest frame's reason: it describes
            // what the cook is doing right now, which is what they can act on.
            let reason = recent.last.flatMap { gate.rejection(for: $0.quality) } ?? .blurred
            return .failure(reason)
        }

        // The best frame available is still not worth sending if the whole
        // window is softer than this scene manages when it is held still. That
        // is what a head turn looks like: not a dark frame, not a featureless
        // one, just a second of everything being worse than usual.
        let peak = recentPeakSharpness
        if peak > 0, best.quality.sharpness < peak * gate.relativeSharpnessFloor {
            return .failure(.blurred)
        }
        return .success(best)
    }
}
