import Foundation

/// The five seconds where the cook holds still and Polly looks.
///
/// Not a burst. Three grabs spread across the hold, because the thing being
/// photographed is a hand that is *trying* to stay still and failing slightly:
/// it drifts, the knife occludes a finger for a moment, the head moves. One
/// frame decides the assessment on whichever instant it happened to land on.
/// Three costs almost nothing and turns a bad moment into a discarded frame.
///
/// Deliberately not motion analysis. We are not measuring how the hand moves,
/// we are getting several looks at one pose.
@MainActor
enum SkillHoldCapture {

    struct Result {
        /// Best frames first, ready for the assessor.
        let frames: [Data]
        /// How long the cook actually held, which becomes practice time.
        let duration: TimeInterval
        /// Why nothing came back, when nothing did. Distinguishes "no camera"
        /// from "camera is still waking up", which need different sentences.
        let rejection: VisualFrameRejection?

        var isEmpty: Bool { frames.isEmpty }
    }

    /// How many frames the assessor is sent. Above three the cost rises and the
    /// answer does not: they are views of the same still pose, not new
    /// information.
    static let framesToKeep = 3

    /// Run one hold.
    ///
    /// `onProgress` is called with 0...1 through the hold so the ring on screen
    /// is driven by the real capture rather than an animation that happens to
    /// last the same time. If they diverge, the cook is being lied to about when
    /// to stop holding still.
    static func run(
        check: SkillVisualCheck,
        visuals: PollyVisualSourceCoordinator,
        clock: () -> Date = { .now },
        onProgress: @MainActor (Double) -> Void = { _ in }
    ) async -> Result {
        let started = clock()
        var captured: [Data] = []
        var lastRejection: VisualFrameRejection?
        var elapsed: TimeInterval = 0

        for offset in check.captureOffsets {
            let wait = offset - elapsed
            if wait > 0 {
                // Progress is stepped between grabs rather than animated here.
                // The view smooths it; this stays honest about what it knows.
                onProgress(min(elapsed / check.holdSeconds, 1))
                try? await Task.sleep(for: .seconds(wait))
                elapsed = offset
            }
            guard !Task.isCancelled else { break }

            // `maxAge` is short: the whole point is a picture of right now, and
            // a cached frame from before the cook settled would be exactly the
            // blurred moment we are spreading these grabs to avoid.
            let capture = await visuals.preparedFrame(maxAge: 0.4, highDetail: false)
            if let jpeg = capture.jpeg {
                captured.append(jpeg)
            } else {
                lastRejection = capture.rejection
            }
        }

        // Hold out the rest of the five seconds even when the frames are already
        // in. The ritual is load bearing: a cook told to hold for five seconds
        // and released after two learns that the number was decoration.
        let remaining = check.holdSeconds - elapsed
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
        onProgress(1)

        let best = sharpest(captured, keeping: framesToKeep)
        PollyDebugLog.shared.log(
            "skill: hold captured \(captured.count) frame(s), kept \(best.count)"
                + (best.isEmpty ? " — \(lastRejection?.rawValue ?? "no frames")" : ""))

        return Result(
            frames: best,
            duration: clock().timeIntervalSince(started),
            rejection: best.isEmpty ? (lastRejection ?? .noFrames) : nil
        )
    }

    /// Rank by encoded size, largest first.
    ///
    /// A proxy, and an honest one: every frame here comes out of the same
    /// pipeline at the same JPEG quality and the same dimensions, so the one
    /// that needed the most bytes is the one with the most detail in it. Blur
    /// and motion smear both compress smaller. It is not a Laplacian and it does
    /// not need to be, because the job is only to drop the obviously worst of
    /// three near identical frames.
    static func sharpest(_ frames: [Data], keeping count: Int) -> [Data] {
        frames.sorted { $0.count > $1.count }.prefix(count).map { $0 }
    }
}
