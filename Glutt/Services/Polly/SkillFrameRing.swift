import Foundation

/// The last few seconds of what the cook was looking at, kept warm.
///
/// This replaces asking somebody to hold still for five seconds so we could take
/// a photograph we already had. The glasses stream continuously at seven frames
/// a second for the entire lesson, and `preparedFrame` reads the buffer that
/// stream is already filling, so the frames were never the thing we were waiting
/// for. A device log makes it plain: `glasses: frames +21 in 3.0s (7.0 fps)`
/// repeating from the first second of the session to the last, with a five
/// second countdown sitting in the middle of it.
///
/// So nothing is captured on demand. A shallow ring is kept topped up while the
/// camera is up, and a look is a read from memory: instant, and taken from the
/// moment the cook actually asked rather than five seconds after they stopped
/// caring.
@MainActor
final class SkillFrameRing {

    /// One frame and when it arrived.
    private struct Sample {
        let jpeg: Data
        let at: Date
    }

    /// How often to take one. Roughly every other frame the glasses send, which
    /// is plenty for a hand that is being held up deliberately, and cheap: the
    /// stream is running either way and this is a copy out of its buffer.
    static let sampleInterval: TimeInterval = 0.6

    /// About four seconds of history. Enough that a question asked mid sentence
    /// still has frames from before the cook started moving again.
    static let capacity = 7

    private var samples: [Sample] = []
    private var task: Task<Void, Never>?
    private let visuals: PollyVisualSourceCoordinator
    private let clock: () -> Date

    init(visuals: PollyVisualSourceCoordinator, clock: @escaping () -> Date = { .now }) {
        self.visuals = visuals
        self.clock = clock
    }

    var isEmpty: Bool { samples.isEmpty }

    /// Start topping the ring up. Safe to call more than once.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sampleOnce()
                try? await Task.sleep(for: .seconds(Self.sampleInterval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        samples.removeAll()
    }

    private func sampleOnce() async {
        guard visuals.activeKind != nil else { return }
        // Short max age: a frame the pipeline has been sitting on is not a
        // picture of now, and the whole point of the ring is that every entry in
        // it is a real moment.
        let capture = await visuals.preparedFrame(maxAge: 0.5, highDetail: false)
        guard let jpeg = capture.jpeg else { return }
        samples.append(Sample(jpeg: jpeg, at: clock()))
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    /// Frames spread across the window, newest first.
    ///
    /// Not the newest N, and this is the whole reason the ring exists rather
    /// than a single grab. **You cannot see both faces of a chef's knife at
    /// once.** The thumb is on one side of the blade and the curled index finger
    /// is on the other, so from the cook's own eyes one of them is behind the
    /// steel in any given instant. Two frames a fifth of a second apart are the
    /// same photograph twice and can never show a whole grip.
    ///
    /// Spread in time is spread in angle, because a hand is never perfectly
    /// still and a hand that has been asked to turn is deliberately not. So the
    /// views handed to the assessor are seconds apart, and between them they see
    /// round the blade in a way no single picture can. That is also the honest
    /// answer to "why not just photograph it": a photograph cannot do this.
    func spread(_ count: Int, within seconds: TimeInterval) -> [Data] {
        let cutoff = clock().addingTimeInterval(-seconds)
        let recent = samples.filter { $0.at >= cutoff }
        guard recent.count > count else { return recent.reversed().map(\.jpeg) }

        // Newest always included: it is the moment they meant. The rest are
        // evenly spaced back through the window.
        let step = Double(recent.count - 1) / Double(count - 1)
        let picked = (0..<count).map { i -> Sample in
            recent[recent.count - 1 - Int((Double(i) * step).rounded())]
        }
        return picked.map(\.jpeg)
    }

    /// Test seam: seed the ring so which frames a look picks can be asserted
    /// without a camera. That choice was wrong in shipped code and cost three
    /// assessments in one lesson, so it is worth being able to pin.
    func preload(_ entries: [(jpeg: Data, at: Date)]) {
        samples = entries.map { Sample(jpeg: $0.jpeg, at: $0.at) }
    }

    /// Fill the ring right now, for the case where a look is asked for before
    /// the sampler has had a chance to run. Bounded hard: this is a fallback,
    /// not a hold.
    func fillNow(upTo count: Int) async {
        for _ in 0..<count {
            await sampleOnce()
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
