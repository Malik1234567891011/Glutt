import Observation
import UIKit

/// Owns both visual sources and decides which one Polly is looking through.
///
/// Conforms to `PollyVisualSource` itself and forwards to whichever is active,
/// so the session controller and the canvas hold one thing and never learn that
/// there are two.
///
/// The rule that matters most is what happens when the glasses drop mid-cook:
/// the cook session stays fully alive. Camera trouble has never been allowed to
/// fail a Polly session and it still isn't. What it must not do is quietly turn
/// the phone camera on instead: the phone may well be face down on the counter
/// or in a pocket, and a camera nobody asked for is worse than no camera. The
/// drop is recorded, the cook is told, and they choose.
@MainActor
@Observable
final class PollyVisualSourceCoordinator: PollyVisualSource {
    nonisolated let kind: PollyVisualSourceKind = .phoneCamera

    let phone: PhoneCameraVisualSource
    let glasses: MetaGlassesVisualSource

    /// Which source is currently in charge. Nil means nothing is looking.
    private(set) var activeKind: PollyVisualSourceKind?

    /// Set when the glasses go away on their own rather than being switched off.
    /// Cleared the moment anything starts again. The UI and Polly both read it.
    private(set) var lastGlassesDropReason: String?

    /// True when the toolkit is set up and glasses can plausibly be asked for.
    /// Cheap enough to read in a view body.
    var glassesPossible: Bool { GlassesSupport.shared.isAvailable }

    /// `glasses` defaults to nil and is built in the body rather than in the
    /// default argument: under Swift 5.10 a main-actor init cannot be evaluated
    /// in default-argument position (SE-0411 is not enabled). Same workaround
    /// `PollySessionController.init` documents.
    init(phone: PhoneCameraVisualSource, glasses: MetaGlassesVisualSource? = nil) {
        self.phone = phone
        self.glasses = glasses ?? MetaGlassesVisualSource()
    }

    private var active: (any PollyVisualSource)? {
        switch activeKind {
        case .metaGlasses: return glasses
        case .phoneCamera: return phone
        case nil: return nil
        }
    }

    // MARK: - PollyVisualSource

    var state: PollyVisualSourceState { active?.state ?? .off }
    var preview: PollyVisualPreview { active?.preview ?? .none }
    var canFlip: Bool { active?.canFlip ?? false }

    /// Prefer the glasses, fall back to the phone.
    ///
    /// Deliberately hung off the existing camera button rather than started with
    /// the session: Polly's camera has always been off until the cook asks for
    /// it, and wearing glasses is not a reason to start filming someone's
    /// kitchen the moment they open a recipe.
    func start() async {
        lastGlassesDropReason = nil

        if glassesPossible {
            await glasses.start()
            // `canSee`, not `isStreaming`: the glasses rest connected with the
            // camera off and only stream during a look, so demanding a live
            // stream here would read a healthy connection as a failure.
            if glasses.canSee {
                activeKind = .metaGlasses
                PollyDebugLog.shared.log("visual: glasses active")
                return
            }
            // Not connected, or refused. Nothing to report to the cook: they
            // asked for a camera and they are about to get one.
            glasses.stop()
        }

        await phone.start()
        activeKind = phone.isStreaming ? .phoneCamera : nil
        PollyDebugLog.shared.log("visual: phone camera \(phone.isStreaming ? "active" : "unavailable")")
    }

    /// Bring the glasses up at the start of a cook, and do nothing whatsoever
    /// if there are none.
    ///
    /// Deliberately not `start()`. That one falls back to the phone camera, and
    /// falling back here would point the phone at whatever it happens to be
    /// facing the moment a recipe opens, which is the thing the camera button
    /// exists to prevent. Glasses are different: they are on the cook's face,
    /// aimed where the cook is looking, and were put on for this.
    ///
    /// Started early because it is slow, not because it is urgent. Opening the
    /// camera stands up a Wi-Fi link to the glasses and that takes 14 to 20
    /// seconds; run alongside the plan compile and the token mint it finishes
    /// somewhere around Chef's first sentence, so by the time anyone is
    /// chopping she can already see. Left until the cook first asks "does this
    /// look right", it would be fifteen seconds of silence at the worst moment.
    func startGlassesIfAvailable() async {
        guard activeKind == nil, glassesPossible else { return }
        lastGlassesDropReason = nil
        await glasses.start()
        guard glasses.canSee else {
            // No glasses on, or they refused. Silent on purpose: nobody asked
            // for a camera, so nobody needs telling they did not get one.
            glasses.stop()
            return
        }
        activeKind = .metaGlasses
        PollyDebugLog.shared.log("visual: glasses active from the start of the cook")
    }

    func stop() {
        glasses.stop()
        phone.stop()
        activeKind = nil
        lastGlassesDropReason = nil
    }

    func flip() { active?.flip() }

    func captureFrame() async -> Data? {
        await withGlassesDropCheck { await self.active?.captureFrame() }
    }

    func captureHighDetailFrame() async -> Data? {
        await withGlassesDropCheck { await self.active?.captureHighDetailFrame() }
    }

    /// Explicitly move to the phone, which is what the cook is choosing when
    /// they are told the glasses went and they want to carry on seeing.
    func switchToPhone() async {
        guard activeKind != .phoneCamera else { return }
        glasses.stop()
        await phone.start()
        activeKind = phone.isStreaming ? .phoneCamera : nil
        lastGlassesDropReason = nil
    }

    /// Notice a glasses session that ended under us, so the next thing that asks
    /// gets an honest answer rather than silence.
    @discardableResult
    private func withGlassesDropCheck(_ body: () async -> Data?) async -> Data? {
        let result = await body()
        if activeKind == .metaGlasses, case .unavailable(let reason) = glasses.state {
            lastGlassesDropReason = reason
            activeKind = nil
            PollyDebugLog.shared.log("visual: glasses dropped — \(reason)")
        }
        return result
    }

    /// The detail the tool layer needs to describe a failure properly, including
    /// which source was asked and why it could not deliver.
    func preparedFrame(
        maxAge: TimeInterval,
        highDetail: Bool
    ) async -> PollyVisualCapture {
        guard let activeKind else {
            return PollyVisualCapture(source: nil, jpeg: nil, rejection: .noFrames)
        }

        if activeKind == .metaGlasses {
            // Read the buffer the live stream is already filling.
            //
            // This used to call `captureLook`, which opened the camera, waited
            // for frames and closed it again, because the camera was held shut
            // between glances to save memory. The camera now stays open for the
            // cook, so a question can be answered from frames that already
            // exist instead of standing up a Wi-Fi link and making the cook wait
            // fifteen seconds for an answer to "does this look done".
            //
            // High detail still goes to `capturePhoto`, which is a real still
            // off the glasses rather than a stream frame, and falls back to the
            // buffer when it cannot deliver.
            let jpeg = highDetail
                ? await glasses.captureHighDetailFrame()
                : nil
            if let jpeg {
                await withGlassesDropCheck { nil }
                return PollyVisualCapture(source: .metaGlasses, jpeg: jpeg, rejection: nil)
            }
            let frame = await glasses.prepared(maxAge: maxAge)
            await withGlassesDropCheck { nil }
            return PollyVisualCapture(
                source: .metaGlasses,
                jpeg: frame.jpeg,
                frameID: frame.frameID,
                ageMillis: frame.ageMillis,
                rejection: frame.rejection
            )
        }

        let jpeg = highDetail
            ? await phone.captureHighDetailFrame()
            : await phone.captureFrame()
        return PollyVisualCapture(
            source: .phoneCamera,
            jpeg: jpeg,
            rejection: jpeg == nil ? .noFrames : nil
        )
    }
}

/// One capture attempt, successful or not, described well enough that Polly can
/// say something useful either way.
struct PollyVisualCapture {
    let source: PollyVisualSourceKind?
    let jpeg: Data?
    var frameID: String?
    var ageMillis: Int?
    let rejection: VisualFrameRejection?

    init(
        source: PollyVisualSourceKind?,
        jpeg: Data?,
        frameID: String? = nil,
        ageMillis: Int? = nil,
        rejection: VisualFrameRejection?
    ) {
        self.source = source
        self.jpeg = jpeg
        self.frameID = frameID
        self.ageMillis = ageMillis
        self.rejection = rejection
    }

    var succeeded: Bool { jpeg != nil }
}
