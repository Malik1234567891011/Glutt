import Foundation
import MWDATCore

/// Bring-up for Meta's Device Access Toolkit.
///
/// Almost nobody who opens Glutt owns Ray-Ban Meta glasses, so the toolkit is
/// treated as a capability the app might have rather than a dependency it needs.
/// `configure()` swallows every failure — a missing plist key, a breaking change
/// in what is still a developer preview, a companion app that isn't installed —
/// and everything downstream asks `isAvailable` and does without. Nothing here
/// may ever be on the path of a cook who has no glasses.
///
/// Lock-guarded rather than actor-isolated because `GluttApp.init` is the only
/// caller of `configure()` and it must not have to await anything.
final class GlassesSupport: @unchecked Sendable {
    static let shared = GlassesSupport()

    /// The scheme Meta AI calls back on once the user approves the integration.
    /// Must stay in step with `MWDAT.AppLinkURLScheme` in project.yml.
    static let callbackScheme = "glutt-wearables"

    private let lock = NSLock()
    private var configured = false
    private var failure: String?

    /// True once the toolkit configured cleanly. False is the ordinary case and
    /// means no glasses surfaces anywhere.
    var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        return configured
    }

    /// Why bring-up failed, for the debug screen. Nil when it succeeded or has
    /// not been attempted.
    var configurationFailure: String? {
        lock.lock(); defer { lock.unlock() }
        return failure
    }

    /// Call once, from `GluttApp.init`. Repeat calls are no-ops.
    func configure() {
        lock.lock()
        let alreadyAttempted = configured || failure != nil
        lock.unlock()
        guard !alreadyAttempted else { return }

        do {
            try Wearables.configure()
            lock.lock(); configured = true; lock.unlock()
            PollyDebugLog.shared.log("glasses: toolkit configured")
        } catch {
            let described = String(describing: error)
            lock.lock(); failure = described; lock.unlock()
            PollyDebugLog.shared.log("glasses: toolkit unavailable — \(described)")
        }
    }

    /// Which camera flow and which transport this build actually asked for.
    ///
    /// Both are decided entirely by Info.plist keys that nothing in the code
    /// mentions, which is how Glutt spent six weeks on a combination Meta had
    /// publicly named as broken without anyone noticing. Discussion #226:
    /// frames are dropped "when you are using bluetooth as the transport channel
    /// and have DAM enabled", and BTC plus DAM is exactly what an app inherits by
    /// moving from the 0.7 SDK to 0.8 and leaving its plist alone.
    ///
    /// Read from `Configuration`, which is the same parse the toolkit performs at
    /// launch, so this reports what the SDK concluded rather than what we meant.
    struct CameraFlow {
        /// True when the Device Access Toolkit App Model is in play. Defaults to
        /// true in 0.8 when the key is absent, and is forced true in 0.9, which
        /// is a reason to stay on 0.8 until Meta ship the decoder fix.
        let usesDAM: Bool
        /// True when the app is declared as an MFi accessory host, which is what
        /// holds the camera on Bluetooth Classic instead of the glasses' softAP.
        let declaresMFiAccessory: Bool

        var summary: String {
            "camera flow: DAM \(usesDAM ? "ON" : "off") · transport "
                + (declaresMFiAccessory ? "Bluetooth Classic (MFi accessory declared)" : "Wi-Fi softAP")
        }
    }

    /// Whether a pair of glasses is on the cook's face right now, rather than in
    /// a drawer.
    ///
    /// `isAvailable` only says the toolkit configured, which stays true forever
    /// once someone has registered a pair. The pre-cook screen needs the harder
    /// question: offering "Chef watches everything" to someone with no camera is
    /// a promise about a cook that cannot happen, and the setting would sit there
    /// silently doing nothing.
    ///
    /// Costs a moment because the selector resolves by observing rather than by
    /// asking, which is why `MetaGlassesVisualSource.start` waits on it too.
    func hasConnectedGlasses(timeout: TimeInterval = 2) async -> Bool {
        // `-fakeGlasses` / `GLUTT_FAKE_GLASSES=1`, Debug only. See `DevBuild`
        // for why this exists and what it does not do.
        if DevBuild.fakeGlasses { return true }
        guard isAvailable else { return false }
        let selector = AutoDeviceSelector(wearables: Wearables.shared)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if selector.activeDevice != nil { return true }
            try? await Task.sleep(for: .milliseconds(120))
        }
        return selector.activeDevice != nil
    }

    /// Parse an arbitrary info dictionary exactly as the toolkit parses ours.
    ///
    /// Exists for one reason: "our bundle resolves to DAM off" passes just as
    /// happily against a toolkit that ignores `DAMEnabled` and reports false to
    /// everyone. Without a case that must come back true, the assertion tests
    /// nothing, which is precisely the mistake this whole area is recovering
    /// from. Nil when the dictionary is too incomplete to parse at all.
    static func usesDAM(infoDictionary: [String: Any]) -> Bool? {
        (try? Configuration(infoDictionary: infoDictionary))?.usesDam
    }

    /// Nil only if the bundle is missing something `Configuration` insists on,
    /// which cannot happen in a built app.
    var cameraFlow: CameraFlow? {
        guard let configuration = try? Configuration(bundle: .main) else { return nil }
        let protocols = Bundle.main.object(forInfoDictionaryKey: "UISupportedExternalAccessoryProtocols") as? [String]
        return CameraFlow(
            usesDAM: configuration.usesDam,
            declaresMFiAccessory: protocols?.contains("com.meta.ar.wearable") ?? false)
    }

    /// Meta AI's post-approval callback. Returns true when the URL belonged to
    /// the toolkit so the caller knows not to also treat it as a Glutt deep link.
    @discardableResult
    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme == Self.callbackScheme else { return false }
        guard isAvailable else {
            PollyDebugLog.shared.log("glasses: callback dropped, toolkit not configured")
            return true
        }
        Task {
            do {
                _ = try await Wearables.shared.handleUrl(url)
                PollyDebugLog.shared.log("glasses: registration callback handled")
            } catch {
                PollyDebugLog.shared.log("glasses: registration callback failed — \(error)")
            }
        }
        return true
    }
}

// MARK: - The one session

/// The single `DeviceSession` for the whole process.
///
/// The glasses allow exactly one session per device, and until this existed two
/// places created them independently: the cook session's
/// `MetaGlassesVisualSource`, and the Debug spike screen. Neither could see the
/// other's, so the second one to ask got `sessionAlreadyExists` and gave up,
/// falling back to the phone camera while a perfectly good stream was still
/// delivering frames at 7fps to nobody.
///
/// Waiting it out was already attempted and could not work. `MetaGlassesVisualSource`
/// kept a `retiringSession` and waited for it to reach `.stopped` before creating
/// the next one, which is right, but that property lives on an instance that is
/// rebuilt for every cook. A fresh instance has nothing to wait for and creates
/// straight into someone else's live session. The wait has to outlive the thing
/// doing the waiting, so it lives here.
///
/// Adopting rather than recreating is also the cheaper answer. Standing a session
/// and camera up costs 1.8s on Bluetooth and fifteen to twenty on the softAP, so
/// a second cook in the same launch now starts seeing immediately instead of
/// paying that again.
@MainActor
final class GlassesSessionBroker {
    static let shared = GlassesSessionBroker()

    private var live: DeviceSession?
    private var retiring: DeviceSession?

    private init() {}

    /// The session that is actually up, if there is one.
    var liveSession: DeviceSession? {
        guard let live, live.state == .started || live.state == .starting else { return nil }
        return live
    }

    /// The live session, or a new one. `adopted` is true when an existing
    /// session was handed back, in which case the caller must NOT call `start()`
    /// on it again.
    func acquire(selector: AutoDeviceSelector) async throws -> (session: DeviceSession, adopted: Bool) {
        if let existing = liveSession {
            PollyDebugLog.shared.log("glasses: adopted the live session (\(String(describing: existing.state)))")
            return (existing, true)
        }
        // Whatever was there is not usable. Let go of it before asking for more,
        // or the create lands inside its teardown.
        if let stale = live {
            live = nil
            retiring = stale
        }
        await waitForRelease()
        let created = try Wearables.shared.createSession(deviceSelector: selector)
        live = created
        return (created, false)
    }

    /// Give the session back. Only the holder can retire it, so a cook ending
    /// cannot pull the device out from under the spike screen or the reverse.
    func retire(_ session: DeviceSession) {
        guard live === session else {
            PollyDebugLog.shared.log("glasses: retire ignored, not the live session")
            return
        }
        live = nil
        retiring = session
        session.stop()
    }

    /// `stop()` is fire-and-forget in 0.8, so the next `createSession` races the
    /// teardown and throws. This is that race, waited out in the one place that
    /// survives the objects doing the racing.
    private func waitForRelease(timeout: TimeInterval = 6) async {
        guard let retiring else { return }
        self.retiring = nil
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(timeout)
        while Date() < deadline, retiring.state != .stopped, retiring.state != .idle {
            try? await Task.sleep(for: .milliseconds(150))
        }
        let waited = Date().timeIntervalSince(startedAt)
        guard waited > 0.15 else { return }
        PollyDebugLog.shared.log(String(
            format: "glasses: waited %.1fs for the old session to let go (now %@)",
            waited, String(describing: retiring.state)))
    }
}
