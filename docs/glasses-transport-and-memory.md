# Glasses: transport, memory, and how we test from here

2026-08-06. Supersedes the conclusions in `glasses-memory-investigation.md`, which
is kept for its measurement history but whose headline finding is now retracted.

> **READ THIS FIRST, added 2026-08-20.** The transport question below was
> answered four times and three of those answers were wrong. The retractions
> cite each other and §1b and §2 can each be read as overturning the other, so it
> is genuinely possible to leave this document believing the opposite of what is
> true. The settled answer, in commit order:
>
> | When | Commit | Conclusion |
> | --- | --- | --- |
> | 2026-08-08 | `478ef3f` | "Bluetooth is not reachable." **Wrong.** The test blocked the Wi-Fi join while leaving the app configured for Wi-Fi, which is not the same as configuring for Bluetooth. |
> | 2026-08-09 | `aeadecb` | Bluetooth **is** reachable, via two Info.plist keys. First frame 1.8s against 15 to 20s. This part still stands. |
> | 2026-08-16 | `b41efdf` | Bluetooth is better and still cannot ship: `com.meta.ar.wearable` is an MFi protocol and Meta declined to authorise this bundle id on issue #266. Wi-Fi ships. |
>
> So: **§1b is retracted, and the retraction paragraphs at the top of §2 are
> correct.** Everything in §2 *below* those paragraphs is the old wrong text,
> kept for the record.
>
> Current state and the exact keys are in
> [glasses-bluetooth.md](glasses-bluetooth.md), which is shorter and is the one
> to read before changing anything.

---

## 0. THE ANSWER: it was our bug, and the camera is cheap

2026-08-07, 17:04. Identical run to the one in §0b, same glasses, same
`360x640 @ 2 fps for 60s`, same 111 frames, same ~19s to first frame:

```
LONG LOOK: ok · 111 frames · 19.7s to first frame · 75.0s total · +12 MB (link +6, frames +7)
```

**Twelve megabytes.** The run an hour earlier, with the same workload, cost
**896 MB**. Footprint sat between 65 and 77 MB for the entire seventy-five
seconds and never trended up. The post-teardown climb is gone too: flat at 68 to
71 MB across three minutes of sampling after the session stopped.

### What changed

One thing, and it was not in the camera path at all. `GlassesSpikeModel` did its
setup in `init`, and the view held it as:

```swift
@State private var model = GlassesSpikeModel()
```

SwiftUI re-evaluates that expression on **every** initialisation of the view
struct and keeps only the first. Every discarded instance had already run
`observeRegistration()`, `observeDevices()`, and built an `AutoDeviceSelector`
against `Wearables.shared`. Those observation Tasks were never cancelled, because
nothing knew the instance had been thrown away.

So the app accumulated live device selectors and toolkit observers for as long as
the screen was on. It was found while chasing something else entirely: the log
showed **eight run markers written in two seconds**, which was the same `init`
firing eight times.

This explains every symptom that made the memory behaviour so confusing:

| Symptom | Why |
|---|---|
| Cost tracked wall-clock, not frames | The view re-rendered at a steady rate driven by the memory label and log appends, not by frame delivery, so leaked instances accrued at a constant rate |
| Frame rate and resolution changed nothing | The leak was never in the frame path |
| The link phase cost the same rate with zero frames | Same reason |
| It kept climbing after `camera.stop()` and `session.stop()` | The leaked observers were not owned by either |
| It eventually came back | The abandoned instances were collected once the screen went away |

**The Device Access Toolkit's camera is cheap.** 111 frames over 55 seconds cost
7 MB. Establishing the Wi-Fi link cost 6 MB. Nothing here needs a bug report and
nothing here forces the on-demand look design.

### Confirmed on the old worst case

The same run at `med / 7 fps`, which previously cost 680 MB:

```
LONG LOOK: ok · 410 frames · 14.3s to first frame · 72.6s total · +26 MB (link +7, frames +19)
```

Both configurations, after the fix:

| Config | Frames | Link | Frames | Total | Was |
|---|---|---|---|---|---|
| low, 2 fps | 111 | +6 MB | +7 MB | **+12 MB** | 896 MB |
| med, 7 fps | 410 | +7 MB | +19 MB | **+26 MB** | 680 MB |

Roughly **50 KB per delivered frame**, which is about what a decoded frame we
briefly touch and release should cost, and it now scales with the frame count
the way a sane pipeline does. Establishing the link is 6 to 7 MB whatever the
configuration. Memory falls back afterwards rather than climbing: 92 → 86 MB
over thirty seconds, then 72 MB once the session stops.

Cost per second of streaming is now **0.16 MB/s at 2 fps** and **0.36 MB/s at
7 fps**. A 45-minute cook watching continuously at 2 fps would spend roughly
430 MB, which is affordable. Watch windows are essentially free.

### What is still true

The **19.7 seconds to first frame** is real and unchanged, and it is now the only
serious problem left. Meta's own figure for softAP setup is ~5s (§2). A cook
asking "does this look done" and waiting twenty seconds is the thing to fix next,
and it is a latency problem, not a memory one.

### Lesson

Four wrong models in two days, and the true cause was in our SwiftUI code the
whole time. The tell was there early: nobody else in 28 open issues had reported
a memory leak. That absence was evidence and it was noted and then ignored.

---

## 0b. Retracted: "it costs time, not frames"

2026-08-07. Three 60-second runs on real glasses, with the two supposed levers
moved hard:

| Config | Frames | Frames MB | **MB/frame** | **MB/second** |
|---|---|---|---|---|
| med, 7 fps (504x896) | 410 | 592 | 1.44 | 10.2 |
| med, 7 fps (504x896) | 408 | 680 | 1.67 | 11.7 |
| low, 2 fps (360x640) | 111 | 691 | **6.23** | **12.6** |

Frame rate down 3.5x, resolution down 2x, **the bill did not move.** Per frame the
number swings 4.3x and means nothing; per second it is flat at ~11 MB.

The clincher is the link phase, before any frame exists. Establishing the Wi-Fi
link takes 15 to 18 seconds, delivers **zero** frames, and costs 139, 219 and 205
MB across the three runs — 9.3, 11.8 and 12.3 MB per second. The same rate as
streaming, with nothing streaming.

**The camera costs roughly 11 MB for every second it is open, whatever is coming
through it.** Resolution, frame rate, codec and our frame gate are all irrelevant
to the memory question. The only lever is how many seconds the camera is open.

Worse, the clock does not stop when we do. Memory keeps climbing at ~8 MB/s after
`camera.stop()`, and keeps climbing after `session.stop()` too: 1354 MB at the
stop, 1599 MB thirty seconds later. It does come back — the same screen reads
69 MB a few minutes on — but nothing has yet caught when it turns around, which
is the open question in §5.

A 60-second look therefore costs about 900 MB and a phone has maybe 2.9 GB.

### Three wrong models, and why they were wrong

Worth recording, because each one survived a plausible-looking measurement:

1. **"The SDK leaks ~1.9 MB per delivered frame."** Measured with
   `MWDATMockDevice` linked into the app, which duplicates `MWDATCamera`'s ObjC
   classes. Retracted in §1.
2. **"The cost is all in the Wi-Fi association, frames are free."** Killed by the
   first long look: 592 MB of it landed after the first frame arrived.
3. **"Frames dominate, so drop the frame rate."** Killed by the run above. The
   per-frame figure was an artefact of holding the duration constant, which made
   frames and seconds move together.

The mistake common to all three: predicting from one run instead of holding a
variable still and moving another. The run that settled it moved frame rate and
resolution while pinning the clock, and all three totals landed on top of each
other.

---

## 1. The retracted per-frame leak

We spent two days designing around a claim that the toolkit retains ~1.9 MB per
delivered frame and ~42 MB per second of stream, never returns it, and cannot be
worked around. Every product decision since — on-demand looks instead of a live
stream, an eight-frame cap, the sharpness gate picking one frame out of a short
burst — was chosen to survive that.

Re-measured with `MWDATMockDevice` linked to the **test bundle only** instead of
into the app binary:

| Run | Seconds | Frames | ΔMB | MB/s | MB/frame |
|---|---|---|---|---|---|
| Soak, raw/medium @ 7fps | 120.8 | 2872 | **22.1** | 0.2 | 0.01 |
| Duration 6s | 6.8 | 136 | 10.8 | 1.6 | 0.08 |
| Duration 12s | 12.8 | 288 | 2.7 | 0.2 | 0.01 |
| Duration 24s | 24.8 | 576 | 1.3 | 0.1 | 0.00 |
| Duration 48s | 48.8 | 1152 | 2.9 | 0.1 | 0.00 |
| No subscriber at all | 12.8 | 0 | 0.4 | 0.0 | — |
| With our full decode | 12.8 | 288 | 0.7 | 0.1 | 0.00 |
| Five 2s looks, one session | 2.8 each | 48 each | +0.1, −0.0, −1.4, +0.0, +1.5 | — | — |

2872 frames cost 22 MB. At the retracted figure they would have cost 5.6 GB. The
first run in any group carries ~10 MB of one-time setup and every run after it is
flat, which is a warm cache, not a leak. Repeated looks do not accumulate.

**The one variable that changed is the linkage.** Every measurement that produced
the old numbers — simulator and device alike — was taken with `MWDATMockDevice`
linked into the app target next to `MWDATCamera`. Those two products statically
duplicate the same internal `SUPMediaStream*` and `FB*` Objective-C classes, and
dyld says so out loud: *"may cause spurious casting failures and mysterious
crashes"*. We had already seen it crash real streams, which is why the product
was unlinked in the first place; it was re-linked to chase the memory question on
the simulator and never taken back out, including for the device builds.

So the leading explanation for the whole memory episode is that we were measuring
the duplicate-symbol hazard, not the toolkit. That was the first hypothesis, and
it was dropped too early.

### What this does not prove

The mock never touches the Wi-Fi transport, and the device numbers were
confounded too, so the growth seen on hardware still has two candidate causes:
the linkage (now gone) or softAP itself. Only hardware separates them, and it is
now **one** test rather than a series. See §5.

---

## 1b. The Bluetooth question, asked properly and answered no

2026-08-08. Meta's engineer closed issue #233, about the softAP displacing the
phone's internet, with this:

> "Live streaming applications will still have to use the BTC channel
> unfortunately. But softAP unblocks the high quality media requirement for the
> non streaming applications." — `sourabh-nanoti`

We are a live streaming application, so that reads like an instruction. And on
0.8, `metadavithom` said in discussion #226 that "BTC transport & DAM will be
the default behaviour if you update your app from the 0.7 sdk to 0.8 sdk". So
the SDK was pinned back to 0.8.0 and tested on real glasses. Three findings,
in order:

**`DAMEnabled` is not read by 0.8.0 at all.** The string appears nowhere in
either `MWDATCore` or `MWDATCamera`. The only Info.plist keys those binaries
look for are `appLinkURLScheme`, `clientToken` and `metaAppId`. Setting it
either way does nothing, on 0.8 or 0.9.

**0.8.0 with default configuration still uses the softAP.** Measured: the phone
moved to `Meta Glasses 01S9` twelve seconds after the camera was requested,
exactly as on 0.9.

**Blocking the Wi-Fi join does not fall back to Bluetooth.** Removing the
`HotspotConfiguration` entitlement stops the toolkit joining anything, which is
worth doing because the binary ships a `NoAccessoryWifiNetworkJoiner` beside the
two auto-join ones. Result: no join prompt, the phone kept its own network, the
`DeviceSession` reached `.started`, `addCamera` succeeded — and then the stream
sat in `waitingForDevice` and delivered zero frames, with `capturePhoto`
returning false. The Bluetooth control channel works. The media path needs the
softAP and has no fallback.

> **RETRACTED 2026-08-09 by `aeadecb`.** The conclusion below is wrong. This
> test blocked the Wi-Fi join while the app was still configured for Wi-Fi,
> which is not the same thing as configuring it for Bluetooth. Of course it
> produced a session that started and a stream that never delivered a frame.
> The selector is two Info.plist keys and is described in §2's retraction
> paragraphs and in glasses-bluetooth.md.

So: **there is no public way to select the BTC media transport in 0.8.0 or
0.9.0.** Meta says streaming apps must use it; the SDK offers no way to ask.
That contradiction is worth putting to them directly, and is the one open
question left on transport.

Everything above is reverted. The pin is back on 0.9.0, the entitlement is
back, and the spike lives on `spike/dat-0.8-bluetooth`.

---

## 2. RETRACTED TWICE. Bluetooth transport works, and `DAMEnabled` is honoured

**Everything in this section below the retraction is wrong.** It is kept because
both errors were acted on and both cost weeks.

**Retraction 1, the transport.** Bluetooth Classic is selectable and Glutt now
runs on it. `UISupportedExternalAccessoryProtocols = com.meta.ar.wearable` plus
the `external-accessory` background mode holds the camera on BTC and keeps the
phone on its own Wi-Fi. This supersedes §1b, which reached the opposite conclusion from a test that was set up wrong. First frame in 1.8s rather
than fifteen.

**Retraction 2, `DAMEnabled`.** The key *is* read by 0.8.0, which is the version
we link. The quote below is from **0.9's** changelog, and "support for opting out
was removed" is a statement that it existed in 0.8. `project.yml` additionally
claimed the key was absent from the framework binary, on the strength of
`strings` output. `strings` does not enumerate Swift string literals, so that
observation could not distinguish "not read" from "not visible to grep".

Settled by test rather than argument. `GluttTests/Glasses/GlassesDAMConfigTests`
calls `MWDATCore.Configuration(infoDictionary:)`, the same parse the SDK performs
at launch, and gets: key absent → DAM **on**, `false` → **off**, `true` → **on**.
No glasses, no device, 2 milliseconds. It also asserts what the shipping bundle
resolves to, which is the assertion that would have caught the original mistake.

### Why this one mattered

`metadavithom` of Meta, discussion #226, a month before we hit it:

> I think there is an issue where we can drop frames when you are using bluetooth
> as the transport channel and have DAM enabled. **BTC transport & DAM will be the
> default behaviour if you update your app from the 0.7 sdk to 0.8 sdk**, but we
> have moved to Wifi in our sample app so perhaps didn't catch this.

That is Glutt exactly: BTC by the MFi keys, DAM by saying nothing. `jeffhoang`
measured both sides of it on issue #227 — with DAM on, frames stop dead 5 to 9
seconds in and never return with nothing on any error channel; with
`DAMEnabled=false`, a 30+ minute continuous run and only ordinary 1 to 2 second
stalls that heal by themselves. Our cooks froze at 12 to 19 seconds.

### The freeze itself, from Meta

`metadavithom`, #226, 2026-07-13:

> We've identified this as a glasses firmware bug — it is an issue where i-frames
> are dropped occasionally by the glasses and not sent, if the packet size gets
> too large. [...] On top of that **if you use `.raw`, our SDK decoder has a bug
> where it freezes on the missed frame and doesn't recover.**

So two defects stacked: firmware drops a keyframe, and the `.raw` decoder never
asks for another. `vinidlidoo` rebuilt a `VTDecompressionSession` every 0.5s
through a 72-second freeze and decoded nothing — the decoder is not wedged, it is
waiting for a reference that will never arrive. Only restarting the *stream*
brings it back, because that forces a keyframe.

Three fixes were promised. Ranked by what is actually available:

1. **`DAMEnabled=false`** — shipped. Removes the DAM half.
2. **`.hvc1` and decode ourselves** — Meta's standing recommendation. Recovers at
   the next keyframe with no restart. Not done.
3. **Meta's own `.raw` decoder fix** — promised 2026-07-13 "in a few weeks".
   **0.9.0 shipped 2026-08-03 with no mention of it**, and removed the DAM
   opt-out. That is the reason the SDK stays pinned to 0.8.0.
4. **Firmware v128** — "more than a month" from 2026-07-13.

### The restart that could never have worked

Our first mitigation tore the session down and rebuilt it. It failed on both
attempts in the cook of 2026-08-11 with `A session already exists for this
device`, and it was always going to. `jeffhoang`, #227, 2026-07-06:

> 0.8.0 made `Stream.stop()` / `DeviceSession.stop()` synchronous/fire-and-forget:
> re-adding a stream races the still-in-flight teardown and throws
> `DeviceSessionError.capabilityAlreadyActive` (code 5) or `sessionAlreadyExists`
> (code 3).

Now the camera is recycled on the session we already have, which forces the
keyframe without racing anything. A session rebuild is the fallback, and it waits
for the old session to actually reach `.stopped` first.

---

### Superseded text, kept for the record

From the 0.9.0 changelog, under *Removed*:

> Support for opting out of the Device Access Toolkit App Model (DAM). DAM is now
> always enabled, so the `MWDAT.DAMEnabled` Info.plist key is ignored.

The build put on the phone on 2026-08-05 to force Bluetooth therefore tested
nothing. The key has been removed from `project.yml`.

Camera frames come over Wi-Fi and only Wi-Fi. Meta's `alexsinkmeta` on issue #240:

> In SDK 0.8.0, camera streaming no longer runs over the baseline BLE connection.
> Instead, a higher-bandwidth link must be established first, and the CameraAccess
> sample relies on joining the glasses' own local Wi-Fi network (SoftAP).

### The costs are documented, and one of them is better news than we thought

`sourabh-nanoti` on issue #227 lists the softAP caveats:

> 1. The phone goes to mobile data as the wifi channel is used by the SDK to
>    deliver video frames to the phone.
> 2. The startup of the video session takes ~5 sec to start as setting up softAP
>    takes this time.
> 3. An additional prompt is shown which the user has to click before the SDK
>    initializes softAP.

The phone falls back to **cellular**, it does not lose the internet. That matters
more than anything else here: Polly's OpenAI Realtime session survives a look, on
any phone with a data connection. The architectural conflict we thought we had —
a camera that takes the network away from a voice assistant that needs it — is
not one, except on Wi-Fi-only iPads or a phone with no signal.

The ~19s we measured to first frame is well outside Meta's stated ~5s. That is a
real gap and worth reporting once it is re-measured without the mock linked.

Two prompts are involved and both must be answered:
- **"Join Wi-Fi network Meta Glasses"** — needs the `HotspotConfiguration` and
  `wifi-info` entitlements, which we have via Omar's team.
- **Local Network permission** — separate, gates the socket layer *after* the
  join succeeds. If the join works and frames never arrive, this is the suspect
  (issue #240). Settings → Privacy & Security → Local Network → Glutt.

---

## 3. A product risk we had not logged: audio and camera fight

Polly currently routes voice through the glasses (task #12) and wants to look
through the same glasses. Two open issues say those two things interfere.

**#260 — HFP kills photo capture.** With `AVAudioSession` in HFP mode on the
glasses, `capturePhoto()` returns `issued: true` and `photoDataPublisher` never
fires, while video frames keep flowing on the same stream. Reverting the audio
category restores it immediately. The reporter tried four category variants;
Meta's own documented recipe performed *worst*. The variant that works uses
`.allowBluetoothA2DP` with `preferredInput` pinned to the **built-in mic**.

Consequence for us: `captureHighDetailFrame()` is the path that calls
`capturePhoto`, so on glasses audio it degrades to a stream frame every time. It
already falls back correctly, so this is a quality ceiling rather than a break —
but the "read the thermometer" use case does not work while Chef is speaking
through the glasses.

**#256 — the camera permanently stops A2DP playback.** Starting a stream pauses
whatever is playing and never resumes it, for the rest of the app session, with
no route change and no `.ended` interruption notification. Native capture on the
same hardware resumes correctly, so only the streaming path is affected.

Neither is fixed in 0.9.0. Both need to be verified against our own audio setup
before we promise "Chef talks and watches through the glasses".

---

## 4. How we test from here

The old loop was: put the glasses on, tap through the spike screen, copy a log
out of a dying app, paste it, change one variable, repeat. One data point per
interruption, and a real risk of poisoning the results — an OS memory-kill leaves
the glasses in the stuck-broadcast state of issue #231, recoverable only by
putting them in the case with the lid shut for 30–60s, and every measurement
taken before noticing is suspect.

`GluttTests/Glasses/GlassesMemoryMatrixTests.swift` replaces it. It drives the
real toolkit with a mock device and reports seconds, frames, ΔMB, MB/s and
MB/frame per configuration. Twenty configurations run unattended in a few
minutes.

```bash
xcodebuild test -scheme "Glutt Glasses Matrix" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:GluttTests/GlassesMemoryMatrixTests/testA3_soak \
  CODE_SIGN_IDENTITY="-"
```

Four things had to be true to make this work, none of them obvious:

1. **The mock belongs on the test target, not the app.** Same duplicate-symbol
   reason as §1, and it is also what stops the mock ever reaching a shipped
   build, which closes task #14.
2. **The fixture must be H.265.** `setCameraFeed(fileURL:)` accepts nothing else
   and fails *silently* on H.264 — the stream still reaches `.streaming` because
   the control handshake completes before frame extraction is attempted, so the
   symptom is a publisher that simply never fires (issue #197). Ours is HEVC.
3. **Sign ad-hoc, with `CODE_SIGN_IDENTITY="-"`.** Under
   `CODE_SIGNING_ALLOWED=NO` the SDK's keychain lookup fails, `configure()`
   throws, and the host app fatals on first touch of `Wearables.shared` with an
   error that blames the caller (issue #197 again).
4. **A dedicated scheme carries the gate.** The matrix is skipped unless
   `GLUTT_GLASSES_MATRIX=1`, and there is no way to get an environment variable
   into a unit-test host from the xcodebuild command line: `FOO=1 xcodebuild`
   stops at the build system and the `TEST_RUNNER_` prefix only reaches a
   XCUITest runner. A scheme test action is the one place it survives.

### What the harness cannot tell us

It has no radio. Anything downstream of softAP — association time, the Wi-Fi and
Local Network prompts, cellular fallback, RF-dependent frame stalls, thermal
limits, real firmware — is invisible to it. It also pins its own frame rate: the
counts came back identical (288 in 12s, ~22fps) whether we asked for 2fps or
30fps, so the mock plays the file at the file's cadence and no mock experiment
can vary frame rate. Use duration instead.

Its job is to kill wrong hypotheses cheaply so hardware time is spent on the ones
that survive.

---

## 5. The one question left: how fast does it come back

Everything above says a look costs seconds, and that the meter keeps running for
at least thirty seconds after a full teardown. It also says the memory is
eventually returned, because the screen reads 69 MB minutes later.

Nobody has measured the turnaround, and it decides the product outright:

| If memory returns in | Then |
|---|---|
| A minute or two | Chef can look as often as she likes, just not back to back. Cover the gap out loud and this ships. |
| Never, until relaunch | A hard budget of two or three looks per app launch. Vision becomes something the cook spends, and the UI has to say so. |

The spike now samples every 15 seconds for three minutes after the session stops
and reports the peak and how much has come back, so one run answers it.

---

## 6. The old hardware test, kept for the record

Everything above narrows two days of guessing to a single question: **with the
mock no longer linked into the app, does a look on real glasses still cost
hundreds of megabytes?**

Build is already correct (device build verified clean, no `MWDATMockDevice`).
Reset the glasses first — case, lid shut, a full minute — because the earlier
runs almost certainly left them in the #231 state, and the cost per look climbing
419 → 603 → 839 MB across runs is exactly what that looks like.

Then five looks, and read three numbers:

| Number | If it says | Then |
|---|---|---|
| ΔMB per look | single/low-double-digit | the linkage was the whole thing; a live stream is back on the table and the on-demand design becomes a choice, not a cage |
| ΔMB per look | still hundreds | softAP is genuinely expensive; on-demand looks stay, and this is a real bug report to Meta with a clean repro |
| Time to first frame | ~5s | matches Meta's stated softAP cost, Chef just needs a line to cover it |
| Time to first frame | ~19s | four times Meta's figure, worth raising on #227 |
| Wi-Fi prompt | appears once, phone drops to cellular | expected and documented; Polly's voice session survives |

---

## 6. Reading list, ranked

| Issue | Why it matters to us |
|---|---|
| #227 | softAP caveats stated by Meta; the throughput knee (504×896 @ ≤24fps is stable, 720p stalls at any rate) |
| #240 | Wi-Fi entitlements and Local Network permission are both required and undocumented |
| #260 | HFP audio breaks `capturePhoto` — hits our high-detail path |
| #256 | camera stream permanently stops A2DP playback |
| #197 | the two prerequisites that make mock-based automated testing work |
| #231 | stuck-broadcast state after an OS kill; poisons later measurements |
| #254, #214 | `.raw` frame stalls; Meta recommends `.hvc1` + decode yourself |

Notably absent from all 28 open issues: **anyone reporting a memory leak.** That
absence should have been a much louder signal than it was.
