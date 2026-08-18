import Observation
import UIKit

/// Owns Polly's visual source and forwards to it.
///
/// This used to own two sources, the phone camera and the Meta glasses, and
/// decide which one Chef was looking through. The glasses were removed (see
/// `docs/glasses-removal.md`), so there is one source left and this is a thin
/// forwarder over it.
///
/// It survives as a type rather than being collapsed into `PhoneCameraVisualSource`
/// for two reasons. The session controller and the canvas hold one thing and have
/// never needed to know how many sources exist, which is the property that made
/// adding glasses cheap and makes restoring them cheap. And `preparedFrame`
/// belongs here: it is the tool layer's contract, describing a capture attempt
/// well enough that Chef can say something useful when it fails.
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

    /// Deliberately hung off the camera button rather than started with the
    /// session: Polly's camera has always been off until the cook asks for it.
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

    func captureFrame() async -> Data? { await active?.captureFrame() }

    func captureHighDetailFrame() async -> Data? { await active?.captureHighDetailFrame() }

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
