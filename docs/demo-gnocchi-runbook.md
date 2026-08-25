# Live demo runbook: Gnocchi with Brown Butter and Sage

The dish is Nicky's, from Kitchen Sanctuary:
[recipe](https://www.kitchensanctuary.com/gnocchi-brown-butter-sage/) ·
[video](https://www.youtube.com/watch?v=3sUJwjvmzk8). It ships as bundled chef
content, its cook plan is hand-written and checked in, and its clips are
materialized MP4s served from Supabase.

Fifteen minutes, four servings, one pan of water and one frying pan. It was
chosen well: every risky moment is a *look* rather than a time, which is exactly
what the app is for.

Last verified 2026-08-24 against `bring-meta-glasses-back`.

---

## Before you go live

1. **Install the build with no dev flags.** In particular **not**
   `GLUTT_FAKE_GLASSES=1`: that makes `hasConnectedGlasses()` answer yes with
   nothing paired, so you get the seeing-mode picker and then a camera that
   never delivers a frame.
2. **Open the app and confirm you land on Recipes.** The sign-in wall in
   `RootView` is full screen and has **no dismiss** unless a sign-in error
   happens to surface the "Continue without an account" link. Signed out at
   demo time means stuck.
3. **Grant mic and speech** on a throwaway cook, not during the demo.
4. **Network.** Clips are signed URLs that expire, and a stale cache is dropped
   and re-signed, so **clips need internet at demo time** however well you warm
   them. Polly's realtime session needs it too. The cook plan does not: it is
   bundled, so every step and cue below works with no connection at all.
5. **Check the log took.** One cook, then look for
   `clips: native 3sUJwjvmzk8 assigned 9/10 steps, 9 unique segments (pilot=9)`.
   Nine of ten is correct, see below.

You do **not** need the Mac, the media-worker, or `npm run serve-local`. Clips
come from Supabase. If `Secrets.local.plist` has a `mediaPlaybackBaseURL`, the
app prefers that and falls back to the proxy when it is unreachable, but for a
demo it is cleaner to have no override so rehearsal uses the same path as the
demo.

---

## What to say, and what it demonstrates

The plan is **12 steps**: Tools, Prep, then ten cook steps. Two numbers are on
screen and they differ on purpose: the header counts all twelve
("Step 3 of 12"), the card badge counts only cook steps ("STEP 1"). Below is by
card badge.

| Beat | What you do | What it shows |
| --- | --- | --- |
| Open the dish | Recipes → Nicky's Kitchen Sanctuary → the gnocchi | Bundled chef content, pantry match reads "4 of 9" |
| Cook with Chef | Tap it | Pre-cook briefing, missing ingredients, chef picker |
| **Seeing mode** | Perfectionist / Watchful / Hands off | Only drawn with glasses connected |
| Tools | "All set" | Setup before heat, which most recipes skip. Nine tools: pot for boiling and pan for frying, sieve to drain, bowl, spatula, knife and board for the lemon, teaspoon, zester |
| Prep | Board work | Sage picked, lemon zested and halved, before any heat. Two items, not three: the garlic is pre-minced |
| **Water first** | Step 1 | The scheduler: the slowest thing goes on first. No clip here, deliberately |
| **Gnocchi float** | Step 2 | The best moment in the demo. Float, then drain in the sieve. See below |
| **Water test** | Step 3 | The save. See below |
| Fry | Step 4 | Clip: gnocchi into the pan |
| **Brown butter** | Step 5 | The centrepiece, and the recovery |
| Sage | Step 6 | Crackle, then quiet |
| Garlic | Step 7 | Thirty seconds, and why. Chef says out loud that the clip shows slices and yours is minced |
| Lemon | Step 9 | Off the heat, and why |

### Step 1 has no clip, on purpose

Nine of the ten cook steps get a clip. "Water on" gets none, because the video
has no honest shot of it. `assignClips` used to force leftovers onto unmatched
steps in list order, which put the **garlic** clip on "Water on" along with its
cue. The positional fallback is gone. An empty first step is the correct
behaviour, not a missing clip.

### The three set pieces

**The gnocchi float** (step 2). Say: *"Chef, how do I know when the gnocchi are
done?"* It is a `checkpoint`, not a timer: they sink, then rise all at once,
floating is the signal, and leaving them in after that makes them gluey.

**The water test** (step 3). Say: *"Is the pan ready?"* Not in Nicky's video:
flick in a few drops, they should skitter and bead. Vanishing instantly with a
crack is too hot, and the recovery names the stakes out loud, that too hot here
is what burns the butter two steps later.

**The brown butter** (step 5). The dish turns on about fifteen seconds. Ask
*"how do I know when it's done?"* then *"what if I burn it?"* Recovery: black
flecks and a sharp smell mean burnt, burnt butter cannot be brought back, tip it
and start again.

### Worth doing if the moment is there

- **Interrupt her.** Say "Chef" over the middle of a long answer. She stops
  mid-sentence and listens. **Only "Chef" does this** — talking over her with
  anything else deliberately does not interrupt.
- **She stops listening when she stops talking.** There is no open mic after an
  answer any more. Every turn starts with "Chef". Steps 1 and 2 teach this in
  their copy and the later steps do not repeat it.
- **Stop listening.** A small grey control appears in the dock while she is
  listening. It closes the turn without taking the wake word with it.
- **Change the amounts.** "I've only got half a pack of gnocchi." She rescales
  and says one line back rather than reading the whole list.
- **Ask for a timer.** She offers rather than starting one uninvited.
- **Step by step.** Back out and tap "Or cook step by step" for the same plan
  without the voice.

---

## The seeing modes

Perfectionist / Watchful / Hands off are drawn in the pre-cook briefing **only
when glasses are connected**, because offering "Chef watches everything" to
someone with no camera is a promise about a cook that cannot happen.

`GLUTT_FAKE_GLASSES=1` (device) or `-fakeGlasses` (simulator) fakes the
**answer, not a camera**, so the picker appears but nothing delivers a frame.
Use it to see and choose a mode, never to demo vision, and never on the build
you demo with.

---

## If something goes wrong

| Symptom | Cause | What to do live |
| --- | --- | --- |
| No clips at any step | No network, or signed URLs lapsed and could not re-sign | Carry on. Every cue is in the plan and is spoken regardless. Do not stop to debug |
| Clips on some steps only | Fell through to the YouTube path | Same. It matches fewer steps but still plays |
| She says she cannot see | Glasses session not adopted | Say it is looking through the phone instead and tap the camera button |
| Long pause before she talks | Realtime session connecting | 6 to 10 seconds cold. Fill it, it will not fail |
| She recommends the wrong step | Steps out of order | "Chef, go to step 7" |
| She listens forever | Should not happen now, 25s ceiling | Tap "Stop listening" in the dock |

---

## Why this dish is safe

- **The plan is bundled.** `Glutt/Resources/CookPlan-gnocchi-brown-butter-sage.json`,
  loaded by `CookPlanCompiler.bundledPlan(for:)` before the cache and before the
  network, so it is identical every run.
- **The cues are authored**, not hoped for. `GnocchiDemoPlanTests` asserts the
  float cue, the water test wording, the brown butter target and failure, the
  garlic warning, the lemon off the heat, the water going on first, and that the
  plan has no scheduling problems.
- **The clip mapping is pinned.** `GnocchiClipMappingTests` fetches the real
  pilot and asserts every step lands on its own segment, that nothing is reused,
  and that "Water on" stays empty.
- **The quantities are Nicky's**, with one deliberate exception: 500g gnocchi,
  75g butter, 20 sage leaves, and 2 tsp of minced garlic from a tube where she
  slices 2 cloves. Pre-minced is already cut, so it takes half the time and
  burns sooner, and it is wet, so it spits going into hot butter.

## Two things that were armed and are not any more

**The scripted "YOU DONUT" cue.** `DemoScript` was enabled in every Debug build,
matched against the on-device recognizer's partial transcripts (which run even
while Chef is dormant, so no wake word needed), and triggered on "serve" —
the name of the last step in this recipe. It also deleted the matching turn, so
a genuine "when do I serve this?" disappeared instead of being answered. Now
`isEnabled = false`. Turn it on only for a take you are directing, and narrow
`triggers` to a phrase nobody says by accident first.

**The local-only clip path.** `NativeClipService` used to throw straight past the
proxy when the local media-worker was unreachable, so a laptop that changed
Wi-Fi silently downgraded the demo to YouTube. It now tries local, then the
proxy, then lets the caller fall back.
