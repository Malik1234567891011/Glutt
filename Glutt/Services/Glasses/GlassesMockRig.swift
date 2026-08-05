import Foundation
import MWDATMockDevice

/// Arms a mock pair of Ray-Ban Meta glasses at launch, so a **real** Polly cook
/// session can be driven with glasses as the visual source without owning any.
///
/// The spike screen has its own manual controls for poking at the toolkit. This
/// exists for the other test: open a recipe, cook it, tap the camera button, and
/// confirm the canvas, the tool results and Polly herself all behave as though
/// the cook were wearing glasses.
///
/// Launch-argument gated and does nothing otherwise, so it cannot affect anyone
/// who is not deliberately testing. Goes when `MWDATMockDevice` goes.
enum GlassesMockRig {
    static let launchArgument = "-mockGlasses"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Retained for the process lifetime. A mock device that deallocates
    /// unpairs itself, and the failure looks exactly like glasses that will not
    /// connect, which is a miserable thing to debug.
    private nonisolated(unsafe) static var glasses: (any MockGlasses)?

    static func armIfRequested() {
        guard isRequested, glasses == nil else { return }

        MockDeviceKit.shared.enable(
            config: MockDeviceKitConfig(initiallyRegistered: true, initialPermissionsGranted: true)
        )
        guard let device = try? MockDeviceKit.shared.pairGlasses(model: .rayBanMeta) else {
            PollyDebugLog.shared.log("glasses: mock rig could not pair")
            return
        }
        device.powerOn()
        device.unfold()
        device.don()

        if let feed = Bundle.main.url(forResource: "glasses-mock-wok", withExtension: "mov") {
            device.services.camera.setCameraFeed(fileURL: feed)
        }
        if let still = Bundle.main.url(forResource: "glasses-mock-still", withExtension: "jpg") {
            device.services.camera.setCapturedImage(fileURL: still)
        }

        glasses = device
        PollyDebugLog.shared.log("glasses: mock rig armed (\(device.deviceIdentifier.prefix(8)))")
    }
}
