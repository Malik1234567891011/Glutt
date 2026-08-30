import Observation
import UIKit

/// Owns Polly's visual source and forwards to it.
///
/// Conforms to `PollyVisualSource` itself, so the session controller and the
/// canvas hold one thing and never learn how many there might be.
///
/// **This branch has one source: the phone camera.** It had two, and the second
/// was a pair of Ray-Ban Meta glasses. Everything to do with them, from the
/// toolkit down to the MFi accessory declaration in the Info.plist, is removed
/// on `apple-ready` and lives in full on `skills-knife-coaching`. See
/// `docs/apple-ready-branch.md` before adding any of it back.
///
/// The shape is kept rather than flattened. `activeKind`, `preparedFrame` and
/// the capture rejection vocabulary all still exist and still behave, because
/// the whole point of this branch is that it is the same app with one input
/// removed, not a fork that has to be reconciled later.
@MainActor
@Observable
final class PollyVisualSourceCoordinator: PollyVisualSource {
    nonisolated let kind: PollyVisualSourceKind = .phoneCamera

    let phone: PhoneCameraVisualSource

    /// Which source is currently in charge. Nil means nothing is looking.
    private(set) var activeKind: PollyVisualSourceKind?

    init(phone: PhoneCameraVisualSource) {
        self.phone = phone
    }

    private var active: (any PollyVisualSource)? {
        activeKind == .phoneCamera ? phone : nil
    }

    // MARK: - PollyVisualSource

    var state: PollyVisualSourceState { active?.state ?? .off }
    var preview: PollyVisualPreview { active?.preview ?? .none }
    var canFlip: Bool { active?.canFlip ?? false }

    /// Start the camera, which happens when the cook taps the camera button and
    /// at no other time.
    ///
    /// Polly's camera has always been off until it is asked for, and that has
    /// not changed. A camera nobody asked for is worse than no camera, given
    /// the phone may be face down on the counter or in a pocket.
    func start() async {
        await phone.start()
        activeKind = phone.isStreaming ? .phoneCamera : nil
        PollyDebugLog.shared.log("visual: phone camera \(phone.isStreaming ? "active" : "unavailable")")
    }

    func stop() {
        phone.stop()
        activeKind = nil
    }

    func flip() { active?.flip() }

    func captureFrame() async -> Data? {
        await active?.captureFrame()
    }

    func captureHighDetailFrame() async -> Data? {
        await active?.captureHighDetailFrame()
    }

    /// Kept so callers that offer "carry on with the phone" still compile and
    /// still do the right thing. With one source it is `start()` by another
    /// name, and it stays because the alternative is editing every call site to
    /// say the same thing.
    func switchToPhone() async {
        guard activeKind != .phoneCamera else { return }
        await start()
    }

    /// The detail the tool layer needs to describe a failure properly.
    func preparedFrame(
        maxAge: TimeInterval,
        highDetail: Bool
    ) async -> PollyVisualCapture {
        guard activeKind != nil else {
            return PollyVisualCapture(source: nil, jpeg: nil, rejection: .noFrames)
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
