import AVFoundation
import Observation
import UIKit

/// The phone's own camera as a visual source. A thin wrapper: all the hardware
/// work still lives in `PollyCameraController`, which is unchanged and still the
/// thing tests inject.
///
/// Every property here derives from the wrapped controller rather than caching,
/// so SwiftUI observation flows through to the real state and there is no second
/// copy to fall out of step.
@MainActor
@Observable
final class PhoneCameraVisualSource: PollyVisualSource {
    nonisolated let kind: PollyVisualSourceKind = .phoneCamera

    let camera: PollyCameraController

    init(camera: PollyCameraController) {
        self.camera = camera
    }

    var state: PollyVisualSourceState {
        if camera.isRunning { return .streaming }
        // A denied camera is not a failure worth surfacing as an error: the cook
        // simply cooks by voice, which is how most sessions run anyway.
        return .off
    }

    var preview: PollyVisualPreview {
        camera.isRunning ? .captureLayer(camera.previewLayer) : .none
    }

    var canFlip: Bool { true }

    func start() async { await camera.start() }
    func stop() { camera.stop() }
    func flip() { camera.flip() }

    func captureFrame() async -> Data? { await camera.captureFrame() }

    /// The phone has no separate stills path in the Polly session, and inventing
    /// one would mean a second `AVCapturePhotoOutput` for no gain: the preview
    /// buffer is already 720p, well above what a 1024px frame needs.
    func captureHighDetailFrame() async -> Data? { await camera.captureFrame() }
}
