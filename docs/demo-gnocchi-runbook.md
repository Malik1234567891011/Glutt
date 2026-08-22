# Live demo runbook: Gnocchi with Brown Butter and Sage

The dish is Nicky's, from Kitchen Sanctuary:
[recipe](https://www.kitchensanctuary.com/gnocchi-brown-butter-sage/) ·
[video](https://www.youtube.com/watch?v=3sUJwjvmzk8). It ships as bundled chef
content, its cook plan is hand-written and checked in, and its clips come from
the real grounding pipeline.

Fifteen minutes, four servings, one pan of water and one frying pan. It was
chosen well: every risky moment is a *look* rather than a time, which is exactly
what the app is for.

---

## Before you go live

Do these in order. The last two are the ones that actually matter.

1. **Install the build.** `bring-meta-glasses-back`, or whichever branch this
   merges into.
2. **Sign in, or dismiss the sign-in sheet.** On a fresh install it covers the
   bottom third of the Recipes tab, and it will cover the demo too.
3. **Grant mic and speech** on the first cook, not during the demo.
4. **Warm the clips. This is the important one.** Clip windows are cached in
   `UserDefaults` keyed `glutt.stepClips.v5.<videoId>.<hash>`, which means a
   **reinstall wipes them**. So warm AFTER the final install: open the dish,
   start Cook with Chef, and leave it for **90 seconds**. Two Gemini calls run
   back to back, ground then refine, about 50 to 70 seconds total. Once cached
   it is instant forever.
5. **Check it took.** In the debug log you want
   `clips: indexed 10 step clips`. If you instead see `clips: index failed`,
   the warm did not work and clips will not appear.
6. **Network.** Clips play from YouTube live; there is no offline copy. Polly
   also needs the network for the realtime session. Nothing else does: the cook
   plan is bundled, so the steps and every cue below work with no connection at
   all.

---

## What to say, and what it demonstrates

The plan is 14 steps: Tools, Prep, then twelve cook steps. Numbering in the app
excludes Tools and Prep, so "Step 1" is Water on.

| Beat | What you do | What it shows |
| --- | --- | --- |
| Open the dish | Recipes → Nicky's Kitchen Sanctuary → the gnocchi | Bundled chef content, pantry match reads "4 of 9" |
| Cook with Chef | Tap it | Pre-cook briefing, missing ingredients, chef picker |
| **Seeing mode** | Pick Perfectionist / Watchful / Hands off | Only appears with glasses connected. See the note below |
| Tools | "All set" | Setup before heat, which most recipes skip |
| Prep | Board work | Garlic sliced, sage picked, lemon zested, all before the heat |
| **Water first** | Step 1 | The scheduler: the slowest thing goes on first |
| **Gnocchi float** | Step 2 | The best moment in the demo. See below |
| **Water test** | Step 4 | The save. See below |
| Fry | Step 5 | Clip: gnocchi going into the pan, 1:56 to 2:17 |
| **Brown butter** | Step 7 | The centrepiece. Clip 2:31 to 3:26, and the recovery |
| Sage | Step 8 | Clip 3:26 to 3:35, crackle then crisp |
| Garlic | Step 9 | One minute, and why |
| Lemon | Step 11 | Off the heat, and why |

### The three set pieces

**The gnocchi float** (step 2). Say: *"Chef, how do I know when the gnocchi are
done?"* She has this as a `checkpoint`, not a timer, and the cue is written as
"they sink at first, then rise and bob on the surface. Floating is the signal,
and it happens all at once. Leave them in after that and they go gluey." If you
have the glasses on, this is the moment to ask her to look.

**The water test** (step 4). Say: *"Is the pan ready?"* This step exists because
you asked for it, and it is not in Nicky's video: flick in a few drops, they
should skitter and bead and take a second or two to go. Vanishing instantly with
a crack means too hot. The recovery line names the stakes out loud, that too hot
here is what burns the butter two steps later. Good place to say the app is
teaching, not reading.

**The brown butter** (step 7). The whole dish turns on about fifteen seconds.
Say: *"How do I know when it's done?"* Cue: it melts, foams, the foam subsides,
and the milk solids on the bottom go hazelnut and smell nutty. Then ask
*"what if I burn it?"* Recovery: black flecks and a sharp smell mean burnt,
burnt butter cannot be brought back, tip it and start again, losing 75g of
butter beats serving it. A 55 second clip runs alongside.

### Things worth doing if the moment is there

- **Interrupt her.** Say "Chef" over the middle of a long answer. She stops
  mid-sentence and listens. This only started working this week.
- **Change the amounts.** "I've only got half a pack of gnocchi." She rescales
  and says one line back rather than reading the whole list.
- **Ask for a timer.** She will not start one uninvited any more, she offers.
- **Step by step.** Back out and tap "Or cook step by step" to show the same
  plan, same Tools and Prep, without the voice.

---

## The seeing modes

Perfectionist / Watchful / Hands off are drawn in the pre-cook briefing **only
when glasses are connected**. With the glasses on, they appear on their own.
Without them, launch with `GLUTT_FAKE_GLASSES=1` on device, or `-fakeGlasses` on
the simulator, and the picker appears. That fakes the answer, not a camera, so do
not then ask her to look through the glasses.

---

## If something goes wrong

| Symptom | Cause | What to do live |
| --- | --- | --- |
| No clips at any step | The warm did not take, or no network | Carry on. Every cue is in the plan and is spoken regardless. Do not stop to debug |
| She says she cannot see | Glasses session not adopted | Say it is looking through the phone instead and tap the camera button |
| Long pause before she talks | Realtime session connecting | It is 6 to 10 seconds on a cold start. Fill it, it will not fail |
| She recommends the wrong step | Steps got out of order | "Chef, go to step 7" |
| She talks too long | Fell back to old prompt behaviour | Say "Chef" over her, which now cuts her off |

---

## Why this dish is safe

Everything the demo depends on is checked in rather than generated at runtime:

- **The plan is bundled.** `Glutt/Resources/CookPlan-gnocchi-brown-butter-sage.json`,
  loaded by `CookPlanCompiler.bundledPlan(for:)` before the cache and before the
  network. The compiler is an LLM call and would otherwise produce a slightly
  different plan every run, which is fine for the library and not fine for a
  dish being cooked in front of an audience.
- **The cues are authored**, not hoped for. `GnocchiDemoPlanTests` asserts the
  float cue, the water test with its "skitter" and "too hot" wording, the brown
  butter target and failure, the garlic warning, the lemon going in off the heat,
  the water going on first, and that the plan has no scheduling problems.
- **The quantities are Nicky's**, asserted against the source: 500g gnocchi, 75g
  butter, 20 sage leaves, 2 cloves.
- **The clips are real**, from the grounding pipeline rather than hand-typed
  timestamps, because `StepClipFallbacks` is deliberately empty on the principle
  that windows come from the grounded AV pipeline.

## One bug this uncovered

Clips were broken for every uncached recipe in the app, not just this one. The
proxy's two phases return different shapes: `ground` includes
`youtube_video_id`, `primary_action` and `visual_cue`, and `refine` omits all
three. `StepClip` required them, so refine threw `keyNotFound`, the whole fetch
threw with it, and the cook silently got no clips after paying for two Gemini
calls. The only trace was one line in the debug log.

Decoding is now tolerant of the fields the two phases disagree about, with the
video id backfilled from the response root, and `StepClipDecodingTests` pins both
real payloads. Timings stay required, so a genuinely broken clip is still dropped
rather than played from zero.

Worth knowing because it means clips have probably been silently missing on any
recipe whose cache was cold, for as long as the proxy has returned that shape.
