import AVFoundation
import UIKit

/// Whatever Polly is currently looking through.
///
/// Before a wearable camera there was one answer, the phone's back camera, and
/// `PollySessionController` talked to `PollyCameraController` directly in three
/// places. Two sources means neither the controller nor the canvas may know
/// which one is live: they ask for a frame, or for something to render, and get
/// it.
///
/// Main-actor because every caller is (the session controller and the canvas),
/// and because the phone implementation wraps an `@Observable` main-actor class.
@MainActor
protocol PollyVisualSource: AnyObject {
    var kind: PollyVisualSourceKind { get }
    var state: PollyVisualSourceState { get }
    /// What the canvas should draw. Sources differ here in a way that cannot be
    /// papered over: one owns a capture layer, the other only ever has frames.
    var preview: PollyVisualPreview { get }
    /// False for a wearable camera, which have exactly one camera pointed one way.
    var canFlip: Bool { get }

    func start() async
    func stop()
    func flip()

    /// The most recent usable frame, already downscaled and JPEG-encoded by
    /// `VisualFramePipeline`. Nil when nothing is streaming or no frame has
    /// arrived yet.
    func captureFrame() async -> Data?

    /// A deliberately better still, when Polly needs to read a thermometer or
    /// judge fine texture rather than answer "does this look about right". On
    /// the phone this is the same frame; a wearable camera have a real photo path.
    func captureHighDetailFrame() async -> Data?
}

extension PollyVisualSource {
    var isStreaming: Bool { state == .streaming }

    /// Whether Chef can get a picture if she asks for one. True while a look is
    /// in progress AND while merely connected, because to the cook those are the
    /// same thing: she can see. Only the plumbing knows the camera is off
    /// between looks.
    var canSee: Bool { state == .ready || state == .streaming }
}


/// One case on this branch. The enum survives the removal of the second because
/// the capture vocabulary is built around naming which source produced a frame,
/// and collapsing it would touch every rejection path to save one line.
enum PollyVisualSourceKind: String, Sendable {
    case phoneCamera

    /// What Polly is told the picture came from, so she can give the right
    /// instruction when a frame is unusable.
    var toolName: String {
        switch self {
        case .phoneCamera: return "phone_camera"
        }
    }
}

enum PollyVisualSourceState: Equatable, Sendable {
    case off
    case starting
    /// Connected, but not seeing: the session is up and the camera is not.
    ///
    /// No longer the resting state. The camera is opened with the session and
    /// held for the cook, because opening it costs 14 to 20 seconds of Wi-Fi
    /// association and the frames themselves are nearly free. This is what is
    /// left when the session came up and the camera did not, which is worth
    /// keeping rather than tearing down: the cook can be told, and a retry does
    /// not have to re-establish the connection.
    case ready
    case streaming
    /// The device is holding the connection but has stopped sending. Wait, do
    /// not restart: the toolkit resumes or stops on its own.
    case paused
    case unavailable(reason: String)
}

/// What Polly asked to see, and how badly she needs to see it.
struct PollyFrameRequest: Sendable {
    /// What she is trying to establish. Not used to choose a frame; it is here
    /// so the debug log says why a picture was taken.
    let reason: String
    /// True when she needs a real still rather than a stream frame.
    let highDetail: Bool
    /// What must be visible, in her words, echoed back in the result so the
    /// model can tell whether the picture answered its own question.
    let requiredView: String?
    let maxAge: TimeInterval

    init(reason: String, highDetail: Bool, requiredView: String?, maxAgeMillis: Int) {
        self.reason = reason
        self.highDetail = highDetail
        self.requiredView = requiredView
        // Clamped: a model asking for a frame no older than 10ms would reject
        // every real frame, and one asking for a minute would show her the past.
        self.maxAge = TimeInterval(min(max(maxAgeMillis, 200), 10_000)) / 1000
    }
}

/// What actually happened, in enough detail that a failure is actionable.
struct PollyFrameOutcome: Sendable {
    let captured: Bool
    let source: String?
    var frameID: String?
    var ageMillis: Int?
    var failureReason: String?
    var suggestion: String?

    static let unavailable = PollyFrameOutcome(
        captured: false,
        source: nil,
        failureReason: "camera_unavailable",
        suggestion: "Ask the cook to turn the camera on so you can see."
    )
}

/// Sources render themselves differently and there is no honest way to unify
/// them. `AVCaptureVideoPreviewLayer` is a live hardware layer the phone camera
/// owns; a wearable camera only ever hand over decoded frames.
enum PollyVisualPreview {
    case none
    case captureLayer(AVCaptureVideoPreviewLayer)
    case image(UIImage)
}
