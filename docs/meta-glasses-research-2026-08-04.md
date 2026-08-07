# Ray-Ban Meta + Polly: SDK research

Verified 2026-08-04 against `facebook/meta-wearables-dat-ios` at tag `0.9.0`. Everything
below is quoted from that repo, not recalled. Re-verify before acting on it: the toolkit
is a developer preview and its API has broken across minor versions twice already.

## Verified facts

**v0.9.0 shipped 2026-08-03.** Minimum deployment target moved iOS 15.2 → **17.2**.
`DeviceSession.addStream(config:)` was removed; `DeviceSession.addCamera(config:)` now
returns a `Camera` that owns the hardware and exposes `Camera.stream`. New errors:
`StreamError.thermalEmergency`, `.peakPowerShutdown`, `.batteryCritical`.
Camera Access "now ends the active preview session when the app backgrounds".
([CHANGELOG](https://github.com/facebook/meta-wearables-dat-ios/blob/main/CHANGELOG.md))

**Stream config.** Resolutions `.high` 720×1280, `.medium` 504×896, `.low` 360×640.
Frame rates 2, 7, 15, 24, 30. "Lower resolution and frame rate yield higher visual
quality due to less Bluetooth compression."

**Lifecycle.** Session: `idle → starting → started → paused → stopping → stopped`.
Stream: `stopped → waitingForDevice → starting → streaming → paused → stopped`.
Do not restart while `paused`; wait for `started` or `stopped`. Closing the hinges
forces `stopped`; opening them restores Bluetooth but does **not** restart the session.

**Frames and photos.** `stream.videoFramePublisher.listen { frame in frame.makeUIImage() }`.
Stills via `stream.capturePhoto(format: .jpeg)` delivered on `stream.photoDataPublisher`.

## The finding that matters most

`MWDATMockDevice` ships **inside the same SPM package** as the real SDK.

```swift
MockDeviceKit.shared.enable()
let mockDevice = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)
mockDevice.powerOn(); mockDevice.unfold(); mockDevice.don()
mockDevice.services.camera.setCameraFeed(fileURL: videoURL)
mockDevice.services.camera.setCapturedImage(fileURL: imageURL)
MockDeviceKit.shared.permissions.set(.camera, .denied)
```

This means we do **not** write our own fake glasses. We write one
`MetaGlassesVisualSource` against the real DAT types, and MockDeviceKit swaps the
*device* underneath it. Switching to hardware is then a config change, not a rewrite.
`doff()`, `fold()`, `powerOff()` give us real disconnect and pause paths to test
against, which a hand-rolled stub never would.

Mock media must be **h.265 (HEVC)** for video; JPEG or PNG for stills.

## Developer Mode is not the same as a developer account

| Mode | Requirement |
|------|-------------|
| Developer Mode | Toggle in Meta AI app: Settings → Your glasses → Developer Mode. Set `MetaAppID` to `0`. Registration always allowed. |
| Production | `APPLICATION_ID` + `ClientToken` from Wearables Developer Center, testers added to a release channel. |

So real hardware is reachable now, without a Wearables Developer Center account. The
account is only needed to distribute to other people. Mock-first is still the right
order because it makes the frame path deterministic and unit-testable, but the
hardware gate is lower than it looks.

## Info.plist and entitlements

The getting-started guide and the shipped CameraAccess sample disagree. The sample is
what actually runs, so prefer it, and treat the guide's `UISupportedExternalAccessoryProtocols`
= `com.meta.ar.wearable` and `fb-viewapp` query-scheme entry as things to try if
registration fails to find Meta AI.

Sample requires: `MWDAT` dict (`AppLinkURLScheme`, `MetaAppID`, `ClientToken`, `TeamID`),
a matching `CFBundleURLTypes` scheme, `UIBackgroundModes` = `processing`,
`bluetooth-central`, `audio`, `bluetooth-peripheral`, plus `NSBluetoothAlwaysUsageDescription`,
`NSBluetoothPeripheralUsageDescription`, `NSLocalNetworkUsageDescription` and
`NSBonjourServices` = `_bonjour._tcp`.

Entitlements: `com.apple.developer.networking.HotspotConfiguration` and
`com.apple.developer.networking.wifi-info`. The camera stream runs over Wi-Fi, which is
why local network and Wi-Fi info are needed at all.

**Risk:** those two entitlements generally need a paid Apple Developer Program team.
Glutt currently signs with the personal team `K8MRHHZ85N`. This may block *device*
builds once we go to real glasses. It should not affect mock builds.

## What this costs Glutt

- Deployment target 17.0 → 17.2 (`project.yml`).
- Three new SPM products: `MWDATCore`, `MWDATCamera`, `MWDATMockDevice`.
- `try Wearables.configure()` at launch, guarded so failure never breaks the app for
  the overwhelming majority of users who own no glasses.
- No backend work. Polly already sends images device → OpenAI over the WebRTC data
  channel; the proxy never sees them.

## Measured behaviour (spike, simulator, mock device, 2026-08-04)

Configured `.medium` at 24 fps and let it run: **965 frames, 22.2 fps measured,
504×896**, stable, no dropped-frame gaps. `capturePhoto(.jpeg)` returned
`accepted=true` while the stream was live and delivered a decodable 57 KB JPEG
about a second later. State order was exactly as documented:
`waitingForDevice → starting → streaming`.

Two findings that change design decisions:

**`doff()` does not stop the stream.** Taking the glasses off produced no session
or stream transition at all; frames kept arriving. So "the cook is no longer
wearing these" is not something the session tells us. If they set the glasses on
the counter mid-cook we keep streaming their countertop, which is both a privacy
question and a reason the frame gate cannot assume a frame shows the work surface.

**`fold()` is terminal and immediate.** Closing the hinges produced
`session error: Session ended by device`, then `stopping → stopped` on both
session and stream, and the state stream **finished**. Any `for await` over
`stateStream()` therefore ends, and a new `DeviceSession` is required. Matches the
docs; worth having seen.

Also: `AutoDeviceSelector` resolves its active device by observing, so one
constructed and passed to `createSession` in the same breath still has a nil
device and throws `noEligibleDevice`. Construct it early and wait for
`activeDevice`.

## Calibrating the frame gate against real footage

The first gate used an absolute sharpness threshold of 0.045 and refused every
single frame of real cooking footage. Measuring the whole wok fixture, 312
frames, showed why:

```
sharpness  min 0.0189  p05 0.0233  p25 0.0256  med 0.0281  p75 0.0314  max 0.0365
brightness min 0.2260  med 0.3497  max 0.4832
```

The entire clip spans 0.019 to 0.037. Shallow depth of field, a dark hob and
compression leave very little gradient even when the shot is perfectly still.

**An absolute sharpness threshold is the wrong idea.** The scale is a property of
the scene, not of the focus: a bright cutting board and a dark pan score nothing
alike whether or not either is blurred. Any fixed bar either refuses a dim
kitchen entirely or accepts everything in a bright one.

What replaced it:

- an absolute floor at **0.012**, low enough to only catch a frame with no detail
  at all;
- a **scene-relative** floor: the chosen frame must be at least **0.6** of the
  sharpest this scene has managed recently. That is what a head turn looks like,
  and it adapts to any kitchen.

The baseline has to outlive the images it is compared against, or it is just the
window's own maximum and can never fire. So the buffer keeps **8 images** (about
a second at 7 fps) and **64 sharpness scores** (about nine seconds).

Eight is also a memory ceiling, not just a design choice: a decoded 504×896 frame
is roughly 1.8 MB, so even eight is ~14 MB of held images, and retaining more
risks starving the pool the toolkit recycles frames through.

Simulated over the fixture at a 7 fps sampling, an 8-frame choice window always
contains a frame within 60% of the 9-second peak. The gate's job is to pick the
best available and refuse only when there is genuinely nothing, not to enforce a
quality bar.

## Measured through the production path

Driving `PollyVisualSourceCoordinator` rather than the toolkit directly, which is
what a cook session actually uses:

```
coordinator: active source is meta_glasses
fast        → 39879 bytes, frame age  36ms, took  39ms
fast        → 38191 bytes, frame age  39ms, took   4ms
high_detail → 35831 bytes,                  took 557ms
```

So a routine look costs single-digit milliseconds once the buffer is warm, and a
`capturePhoto` still is about half a second. That gap is the whole reason
`detail_level` is a parameter on the tool.

## The hardware bring-up, and the memory bug that dominated it (2026-08-05)

Five separate things stood between a paired pair of glasses and a live stream.
In order, because each only became visible once the previous one was fixed:

1. **`LSApplicationQueriesSchemes` was missing `fb-viewapp`.** The toolkit finds
   Meta AI with `canOpenURL`, which returns false for un-allowlisted schemes, so
   `startRegistration()` reports Meta AI as **not installed** while it sits on the
   home screen.
2. **Nothing ever called `startRegistration()`.** The mock had faked it with
   `MockDeviceKitConfig(initiallyRegistered: true)`. Developer Mode means
   registration is always *granted*, not that it can be skipped.
3. **The DAT app on the glasses was out of date**, reported as
   `datAppOnTheGlassesUpdateRequired`. `Wearables.shared.openDATGlassesAppUpdate()`
   deep links to the right page.
4. **The Wi-Fi entitlements were missing.** `HotspotConfiguration` and
   `wifi-info`. Without them the stream sits in `waitingForDevice` for ~30s and
   dies `deviceNotConnected`; with them it reaches `streaming`. **A personal Apple
   team cannot provision either** ("Personal development teams do not support the
   Hotspot and Access Wi-Fi Information capabilities"), so glasses work requires
   the paid team.
5. **Memory.** Below.

### `VideoFrame.makeUIImage()` leaks about 5.8 MB per call

Measured on device, 504×896 at 7 fps:

```
21.7  memory: 1178 MB used · 1.8 GB left (frame 1)
...
42.7  memory: 2031 MB used · 1.0 GB left (frame 149)
```

853 MB over 148 frames, a flat **5.76 MB per decoded frame**, killed inside a
minute. It scales with frames *decoded*, not frames delivered.

Three fixes that did **not** change the slope at all, and what each ruled out:

| Change | Slope after | Rules out |
|---|---|---|
| Admission control, one frame in flight | unchanged | queued `Task`s / backlog |
| Thumbnail the preview instead of retaining full frames | unchanged | our own retention |
| `autoreleasepool` around the frame handler | unchanged | autoreleased temporaries |

Everything we did with the *result* was irrelevant, which is what finally pointed
at the call itself. `VideoFrame` also exposes `sampleBuffer`, so the fix is to
decode it ourselves through one shared `CIContext`
(`VisualFramePipeline.image(from:)`) instead of calling `makeUIImage()`.

A `CIContext` owns Metal and GPU caches and is expensive to build.
`PollyCameraController` has carried the comment *"One shared context, allocating
a CIContext per frame is the expensive part of rendering"* since it was written.
The most likely explanation is that `makeUIImage()` builds one per call.

**Never call `VideoFrame.makeUIImage()` in a streaming path.** It is fine for a
one-off still.

### Diagnosing it was slow for an avoidable reason

The device had stopped writing crash reports (last one 2026-08-02) and jetsam
events (last one 2026-07-28) because its disk was full. "No crash report" was
read as evidence about the failure when it only meant the recorder was broken,
and that sent the investigation down two wrong paths (the mock framework, then
the entitlements — the latter was a real bug but not this one).

What actually settled it was `MemoryProbe`, which puts `phys_footprint` and
`os_proc_available_memory()` on screen and logs each 25 MB of decline. When a
device will not tell you why it killed something, make the app say so itself.

## Landmine: MWDATMockDevice and MWDATCamera collide

Linking both produces ~30 dyld warnings at launch, of the form:

```
objc[98379]: Class SUPMediaStreamVideoConfig is implemented in both
  MWDATMockDevice.framework/MWDATMockDevice and MWDATCamera.framework/MWDATCamera.
  This may cause spurious casting failures and mysterious crashes.
```

Meta statically links the same internal `SUPMediaStream*` and `FB*` Objective-C
classes into both xcframeworks. This is their packaging defect, not ours, and it
cannot be avoided while developing against the mock device because the mock flow
needs both frameworks.

Consequence: during the mock phase, treat unexplained casting failures or crashes
inside the toolkit as possibly this rather than our bug. And `MWDATMockDevice`
must come out of the target before anything is ever distributed.

## Distribution reality

The toolkit "is in developer preview" and distribution is through managed release
channels to named testers. This cannot ship to the App Store as a general feature
today. Treat it as a demo and a head start, not as 1.3.

## Sources

- https://github.com/facebook/meta-wearables-dat-ios (tag `0.9.0`)
- `CHANGELOG.md`, `AGENTS.md`
- `plugins/mwdat-ios/skills/{getting-started,camera-streaming,session-lifecycle,permissions-registration,mockdevice-testing}/SKILL.md`
- `samples/CameraAccess/CameraAccess/{Info.plist,CameraAccess.entitlements}`
- https://wearables.developer.meta.com/docs/mock-device-kit
