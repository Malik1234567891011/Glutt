# Glasses streaming memory: investigation, second opinion, and plan

> **RETRACTED 2026-08-06.** The headline conclusion below — that the toolkit
> retains ~1.9 MB per frame and ~42 MB/s and that the leak is "inside the
> toolkit" — does not reproduce. Every measurement in this document was taken
> with `MWDATMockDevice` linked into the app target alongside `MWDATCamera`,
> which statically duplicates the same internal ObjC classes. With the mock moved
> to the test bundle, a 120-second stream delivering 2872 frames costs 22 MB
> total. See `glasses-transport-and-memory.md`. The measurement history here is
> still worth keeping; the conclusions are not.

Working document. Started 2026-08-05 when the app began dying about a minute into
every glasses camera stream. Contains a second opinion Malik commissioned from
ChatGPT, my analysis of it, and the experiment plan that came out of both.

---

## 1. What we measured (all first-hand, on device unless stated)

Physical iPhone, real Ray-Ban Meta Gen 2, `.raw` at 504×896.

| Condition | Growth |
|---|---|
| Our frame handler doing nothing (`decode off`) | **2.07 MB/frame** |
| Our full decode path | 4.2 MB/frame |
| Simulator + MockDeviceKit, full path | 5.5–5.8 MB/frame |
| **Release build**, simulator + mock | **5.2 MB/frame** |
| Memory returned by `camera.stop()` + `session.stop()` | **none** |

Setup cost on device, before any frame arrives:
`271 MB → 303 MB (addCamera) → 436 MB (first frame)`.

Fixes attempted and what each ruled out:

| Change | Effect | Ruled out |
|---|---|---|
| Admission control, one frame in flight | none | queued Tasks / backlog |
| Thumbnail preview instead of full frame | none | our retention for preview |
| `autoreleasepool` around the handler | none | autoreleased temporaries |
| Own decode via shared `CIContext` instead of `makeUIImage()` | **5.8 → 4.2 MB/frame** | ~half the leak was ours |
| `CIContext(.cacheIntermediates: false)` | none | Core Image intermediate caching |
| Debug → Release | none | compiler/ARC debug artifacts |

Conclusion so far: roughly half the growth was ours and is fixed. The remaining
~2 MB/frame persists with our handler doing nothing, survives teardown, and
reproduces in Release.

---

## 2. Second opinion (ChatGPT), and what it got right

Malik asked ChatGPT to review. Its substantive corrections, in order of value:

**a. My isolation was incomplete.** In the "decode off" run our listener was still
subscribed and still hopped to the main actor per frame. The clean test is **no
subscriber at all**. Until that runs, attributing the residue to the SDK is not
proven. **This is correct and is the single best point it made.**

**b. My teardown test was the wrong test.** Footprint not dropping after `stop()`
does not distinguish a leak from an allocator holding freed pages. The
discriminating test is a **second stream**: if it climbs another full slope, the
memory is genuinely charged per frame. If it reuses the high-water mark, much of
it was cache. **Correct.**

**c. My arithmetic was sloppy.** "15 MB/s against a 2.7 GB budget gives 90
seconds" is wrong; that would be ~180s. The real budget is whatever
`os_proc_available_memory()` reports at that moment, it varies by device and
system pressure, and jetsam fires before it reaches zero. **Correct, and I
should not have quoted a headline number I had not reconciled.**

**d. Rate reduction cannot rescue a true per-frame leak.** At `.low` and 2 fps,
0.88 MiB/frame still accumulates ~1.76 MiB/s, or ~4.6 GiB over 45 minutes.
**Correct, and it kills option 4 from my earlier list outright.**

**e. Prior art exists for the sampling architecture.** RuthVision (Android,
shipping) runs "observation cycles" at a controlled interval rather than feeding
every frame to a model. "Where Was It?" captures around events. Both validate
periodic-observation as a product shape.

### What it got wrong or overstated

**"The simulator cannot answer this."** Partly wrong. The leak reproduces on the
simulator with MockDeviceKit, which already rules out the Wi-Fi transport, the
glasses firmware, and Malik's phone. The simulator is a legitimate first filter;
device runs are for confirmation, not for every iteration. Insisting on hardware
for each cycle is what burned an afternoon of Malik's time.

**"Don't let Claude redesign into user-requested capture."** Arguing against a
position I did not take: I proposed on-demand *and* predictive checkpoint warm-up.
But its framing is better than mine and worth adopting: the promise stays
"Polly catches mistakes you did not know you were making", and sampling delivers
that. My phrasing undersold it.

---

## 3. Verified from Meta directly (discussion #226, engineer `metadavithom`)

Checked first-hand rather than taken from the summary. On DAT 0.8:

> "if you use `.raw`, our SDK decoder has a bug where it freezes on the missed
> frame and doesn't recover."
>
> "1) Right now, switch to `.hvc1` and decode yourself."

Context: glasses firmware occasionally drops I-frames when packets get large,
worse at `.high` and in noisy RF. Meta's stated options were `.hvc1` + your own
decoder now, an SDK decoder fix "in a few weeks", and a firmware fix in v128.

This is about a **freeze**, not memory. But it establishes two things that matter:

1. Meta's `.raw` decoder is known-defective and has been for at least a release.
2. **`.hvc1` + decode yourself is Meta's own recommendation**, not a workaround we
   invented. That is why their sample ships `Media/VideoFrameDecoder.swift`.

Also surfaced: a `DAMEnabled` Info.plist flag we have never set. Meta suggested
`false` to fix Bluetooth-transport frame drops. Untested here; a separate
variable, noted so it is not forgotten.

Caveat: that thread is 0.8. We are on 0.9.0 and its changelog does not mention a
decoder fix either way.

---

## 4. Open questions, in the order they should be answered

1. **Does memory grow with no `videoFramePublisher` subscriber at all?**
   Settles ours-vs-theirs. Cheap. Simulator first, device to confirm.
2. **Does a second stream add another full slope after teardown?**
   Settles leak-vs-cache, and therefore whether burst streaming is viable.
3. **How long does a second `addCamera` take with the session still alive?**
   12–17s on first connect. If a warm restart is 1–2s, on-demand and burst
   designs both open up. If not, only predictive warm-up works.
4. **Does `.hvc1` receive-only stay flat?** The biggest potential win.
5. **Does the leak scale with resolution?** Distinguishes "one image buffer per
   frame" from "fixed-size wrapper per frame", which points at different causes.

---

## 4b. RESULTS of the isolation ladder (2026-08-06, simulator + MockDeviceKit)

The ladder was driven by launch argument (`-probe none|count|decode|full`,
`-res`, `-hvc1`, `-autoStream`) so each run is one launch rather than a sequence
of taps on a segmented control that kept failing to register.

| Rung | Subscribers | Result |
|---|---|---|
| `full` (our whole pipeline) | 1 | 1690 frames, **1.96 MB/frame**, rock steady over 171s |
| **`none`** | **0** | **+2194 MB in 52s, ~42 MB/s** |
| `none` + `.hvc1` | 0 | ~52 MB/s |
| `none` + `.low` | 0 | ~47 MB/s |

**The `none` rung settles it.** With nothing subscribed to `videoFramePublisher`,
memory still grows at ~42 MB/s. Our code cannot be responsible for growth that
happens when we are not listening. The leak is inside the toolkit.

Two things worth noting:

- **Not consuming is worse than consuming** (42 MB/s with no listener vs 19 MB/s
  with our full pipeline). That suggests an internal queue that consumption
  partially drains but never fully.
- **Our pipeline now sits at the floor.** 1.96 MB/frame is almost exactly one
  504×896 BGRA buffer (1.81 MB), so after replacing `makeUIImage()` with our own
  shared-context decode, we add essentially nothing on top of what the SDK keeps.

### Two caveats on these numbers

- **`.hvc1` looking worse may be a mock artefact.** On real glasses `.raw` means
  the SDK decodes and `.hvc1` means it passes compressed samples through. The
  mock feeds a file, so the two paths may not differ the way they would on
  hardware. `.hvc1` is not disproven, only not-yet-supported.
- **The resolution test is invalid on the mock.** The fixture is a fixed 504×896
  file; requesting `.low` almost certainly does not re-encode it, which is why
  `.low` and `.medium` leak at the same rate. This one needs hardware.

## 5. Product architectures that survive a per-frame leak

Even in the worst case, the promise does not have to degrade to "ask Polly to
look". Ranked by how much of the promise they keep:

**A. Continuous compressed stream, selective inspection.** Requires `.hvc1` to be
memory-flat. Camera always live; a bounded VideoToolbox decoder holds one or two
buffers; the local gate picks what is worth sending. Polly receives an
observation every few seconds during risky work and every 30–60s while waiting.

**B. Predictive watch windows.** Polly owns the cook plan, so she knows a sear or
a reduction is coming. Open the camera shortly before, watch through the risky
minutes, close it after. A 45-minute recipe usually has only 5–10 minutes where
continuous vision earns its cost. Works even if every stream leaks, as long as
total frames stay inside budget.

**C. Predictive point checks.** Camera opens, takes a handful of frames at a
known checkpoint, closes. Cheapest, and still proactive: the cook never asks.

All three keep "Polly noticed before you ruined it". None require 45 minutes of
continuous video, which was my assumption and was never the product.

---

## 6. What this is not

Not a safety system. Periodic observation catches a dry pan, pooling liquid,
under-browning, wrong chop size, pastry colour, a splitting sauce. It will not
catch a one-second flare-up, a knife slip, or anything outside the current field
of view. The promise should stay "catches cooking mistakes", never "keeps you
safe".
