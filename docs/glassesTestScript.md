# Meta glasses test script

First run of Polly against real Ray-Ban Meta Gen 2 glasses. Everything below has
already been proven against `MWDATMockDevice` on the simulator, so this is about
whether real hardware behaves like the mock, not whether the code works.

Ordered by **risk**. Sections 0 and 1 gate everything else: if the glasses never
reach `streaming`, nothing after it is worth trying.

Legend: **[BLOCKER]** = stop and report rather than pressing on.

---

## 0. Before you touch the app

- [ ] Glasses paired with the **Meta AI** app and charged above 50%.
- [ ] Meta AI → Settings → Your glasses → **Developer Mode** ON.
      This is not the same as a Wearables Developer Center account, and it is all
      we need. Firmware updates are known to switch it back off, so check it
      again if things stop working after an update.
- [ ] Glasses **not** connected to another experience (no "Hey Meta" session
      running).

**Signing note.** Meta's own sample carries two entitlements Glutt does not:
`com.apple.developer.networking.HotspotConfiguration` and
`com.apple.developer.networking.wifi-info`. They were deliberately left out,
because they generally need a paid Apple Developer team and Glutt currently signs
with the personal one. Try without them first. If the camera stream never starts
on device while it works on the simulator, that is the first thing to add, and it
will need a paid-team login.

---

## 1. The spike, before Polly — **[BLOCKER]**

Launch with the `-glassesSpike` argument. Do **not** tap Enable, Pair, On,
Unfold or Don: those drive the mock device, and you have a real one.

- [ ] **[BLOCKER]** `toolkit` reads `configured`.
- [ ] **[BLOCKER]** `registration` reads `registered`. If it reads `available`,
      the app has not been approved in Meta AI yet.
- [ ] Tap **Check** under permission. Expect `granted`, or a Meta AI prompt.
- [ ] **[BLOCKER]** Tap **Start session**. `session` must reach `started`.
- [ ] **[BLOCKER]** Tap **Add camera**. `stream` must go
      `waitingForDevice → starting → streaming`, and the preview must show what
      you are looking at.
- [ ] Note the **measured fps** against the configured rate. On the simulator,
      24 configured gave 22.2 measured. A real figure far below the configured
      rate is the single most important number in this whole script.
- [ ] Tap **Photo**. A still appears next to the preview within a second or two.

**What a failure looks like:** `noEligibleDevice` (glasses not connected or
Developer Mode off), `permissionDenied` (not approved in Meta AI), or a stream
that reaches `starting` and stops (most likely the Wi-Fi entitlements above).

---

## 2. The path Polly actually uses — **[BLOCKER]**

Same screen, POLLY row.

- [ ] **Tap Teardown first.** The coordinator opens its own `DeviceSession`, and
      the toolkit allows only one, so leaving section 1's session running gets you
      `sessionAlreadyExists`.
- [ ] **[BLOCKER]** Tap **Coordinator**. `polly source` must read `meta_glasses`.
      If it reads `phone_camera`, the glasses were refused and it fell back.
- [ ] **[BLOCKER]** Tap **Ask frame** while looking at something on the counter.
      Expect a line like `fast → captured from meta_glasses, ~40000 bytes, age
      <100ms`. Simulator took 4 to 39 ms.
- [ ] Tap **Ask detail**. Expect `high_detail → captured from meta_glasses`.
      Simulator took 557 ms; note the real figure.
- [ ] Now **turn your head quickly** and tap **Ask frame** during the turn.
      It should refuse with `frame_blurred`. This is the scene-relative gate
      doing its job, and it is the thing most likely to need retuning on real
      optics.
- [ ] Cover the lens and tap **Ask frame**. Expect `frame_too_dark`.

**What a failure looks like:** every request refused as `frame_blurred` means the
relative floor (0.6) is wrong for the glasses' optics. Every request succeeding
even mid-turn means it is too lax. Report the numbers either way, they are in the
log behind **Copy log**.

---

## 3. Losing the glasses must not lose the cook

- [ ] With the coordinator streaming, **fold the glasses shut**. On the mock this
      gave `Session ended by device` and a clean stop.
- [ ] Tap **Ask frame** afterwards. It must refuse with a reason, and the app must
      not crash or hang.
- [ ] Unfold, tap **Coordinator** again. It should recover.
- [ ] **Take the glasses off without folding them.** On the mock this produced no
      state change at all and frames kept flowing. Confirm that is also true on
      hardware, because it means the app cannot tell the difference between
      "worn" and "sitting on the counter filming your kitchen".

---

## 4. A real cook

Launch normally. If you want to compare against the mock first, or check
something without wearing the glasses, the `-mockGlasses` launch argument pairs a
fake pair already powered on and playing the wok fixture, so the whole cook
session behaves as though you were wearing them.

Start a normal Polly session and tap the camera button.

- [ ] The camera button shows the **glasses** icon, not the video icon.
- [ ] The canvas shows your point of view, not the phone's.
- [ ] Ask Polly "does this look right?" and confirm she describes what **you**
      are looking at rather than what the phone can see.
- [ ] Ask her something that needs detail, like reading a thermometer, and see
      whether she reaches for `high_detail` on her own.
- [ ] Say "Hey Chef" with the glasses on and confirm the wake word still fires.
      It taps the WebRTC capture path rather than the phone microphone, so it
      should follow the route automatically, but that has never been proven on
      hardware.
- [ ] Confirm Polly's voice comes out of the **glasses**, not the phone speaker.
- [ ] Talk over her mid-sentence. Barge-in should still work.

**What a failure looks like:** her voice on the phone speaker while she hears you
through the glasses, or the wake word never firing. Both point at
`PollyAudioSession.applyPreferredInput`, and the debug log lists every route it
saw under `audio: available inputs`.

---

## 5. The long one

Only once everything above passes. This is the test that decides whether this is
a product or a demo.

- [ ] A full 45 to 60 minute cook, app in the foreground throughout.
- [ ] Note glasses battery at start and end.
- [ ] Note whether the glasses got hot, and whether any
      `thermalCritical` / `batteryCritical` appeared in the log.
- [ ] Note how many of Polly's visual comments were **useful** rather than merely
      correct. That number matters more than the frame rate.

---

## Known limits, not bugs

- **Foreground only.** DAT 0.9 ends the camera session when the app backgrounds,
  and Polly already stands down on background by design. Do not test with the
  phone locked.
- **Roughly thirty dyld warnings at launch** about duplicate `SUPMediaStream`
  classes. That is Meta shipping the same symbols in `MWDATMockDevice` and
  `MWDATCamera`, and it goes away when the mock framework is dropped before
  distribution.
- **Nothing here can ship.** The toolkit is a developer preview distributed to
  named testers through release channels.
