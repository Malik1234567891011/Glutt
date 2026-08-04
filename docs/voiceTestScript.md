# Chef voice — manual test script

For validating the six fixes from the Aug 1 voice audit. Most of these are timing
and audio bugs that no unit test can reach, so they need a real cook on a real
device with the speaker on.

## Before you start

Run the automated suite first — it's fast and catches the pure-logic regressions:

```bash
xcodebuild -project Glutt.xcodeproj -scheme Glutt \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath Build test -only-testing:GluttTests
```

Expect **317 tests, 0 failures**. The command still exits non-zero because of a
pre-existing SwiftData teardown crash — read the "Executed N tests" line, not the
exit code.

Then on device:

- Pick a **Gordon Ramsay** (ElevenLabs) cook for most of this. Half the fixes only
  exist on the cloned-voice path, and the default Chef voice won't exercise them.
- Pick a recipe with several unchecked checklist rows per step (Beef Wellington is
  ideal).
- Phone on the counter, speaker on, roughly arm's length — the same conditions
  that produced the bugs.

**Grabbing the log:** long-press the session timer for ~0.6s, or the "…" menu →
Copy debug log. Do it right after anything looks wrong, before the 800-line ring
buffer eats the evidence. Paste it somewhere before continuing.

---

## 1. She must not apologise after "okay"

The headline fix. This one fired constantly before.

1. Say "Chef", ask anything ("how long on this side?").
2. Let her answer fully.
3. Say **"okay"** and then stay completely silent for **15 seconds**. Don't touch
   the phone.

**Pass:** silence. She says nothing at all.
**Fail:** any variant of "sorry, I didn't catch that" / "could you say that again?"
about 4 seconds after your "okay".

Repeat with **"got it"**, **"thanks"**, **"yep"**, and **"perfect"**.

Then the escalation case, which was the worst version:

4. Say "okay", wait for silence, say "okay" again, wait 15s.

**Pass:** still silence.
**Fail:** an audible connection chime and a "getting Chef back" style recovery —
that's two watchdog strikes escalating into the reconnect ladder.

In the log, each of these should show a `gate: decision=acknowledgment` line with
**no** `watchdog: no reply` line after it. If you see
`watchdog: fired while dormant — ignored`, that's the new backstop doing its job —
harmless, but tell me, because it means a cancel got raced somewhere.

Also worth a pass: say **"that's all"** and wait 15s (should go quiet and dormant),
and say **"chef"** on its own while she's already listening, then wait 15s.

---

## 2. "What's next" must never get pushback

On a step with several **unchecked** checkboxes on screen — don't say anything
about the individual tasks, just do them silently or not at all.

1. Say "Chef, what's next?"

**Pass:** she marks the step done and gives you the next step.
**Fail:** anything that questions you — "you still need to…", re-reading the
current step back at you, listing unchecked items, or asking you to confirm you
finished.

Repeat with: **"let's move on"**, **"keep going"**, **"next step"**, and
**"alright, I got the colour on it, let's move on"** (that last one is a real
transcript that used to get classified as background chatter and dropped).

**The exception that should still work:** on a raw-chicken or raw-pork step, say
"what's next". She's allowed to flag the risk **once**, in one sentence, and must
still advance — something like "heads up, that chicken looked pink to me, your
call." If she refuses to advance, or repeats the warning, that's a fail.

---

## 3. "Done" must land

Mid-step, say just **"done"** and nothing else.

**Pass:** she responds — advances, or at minimum acknowledges out loud.
**Fail:** total silence, as if you hadn't spoken. In the log a fail looks like
`gate: decision=acknowledgment` on the word "done".

Also try **"okay done"**.

---

## 4. The wake word must survive an audio route change

This is the one that used to kill the session silently.

1. Start a cook, confirm "Chef" wakes her.
2. **Plug in wired headphones or connect AirPods mid-cook.**
3. Say "Chef" and ask something.
4. If she doesn't respond, wait **60 seconds** and try again.

**Pass:** she wakes — immediately, or at worst after one segment rotation (~60s).
**Fail:** she never wakes again for the rest of the cook while the screen still
says "Say Chef". That's the old bug.

Repeat pulling the headphones back out. In the log, `wake: heard "Chef" in …` is
the proof she heard you; `wake: segment restarted (rearmed)` marks each rotation.

While you're here, leave a cook running and **idle for 3–4 minutes**, then say
"Chef". Wake has to survive several segment rotations, not just one.

---

## 5. Interrupting a cloned voice must actually stop her

Ramsay voice specifically — this fix does nothing on the default voice.

1. Ask something that gets a long answer.
2. While she's mid-sentence, say **"Chef"**.

**Pass:** her audio stops within a beat and she starts listening.
**Fail:** she keeps talking to the end of the line while the UI flips to Listening.

Then the tuning question I still owe you: try interrupting at **normal speaking
volume** rather than raising your voice. If she doesn't yield, that's the
half-duplex threshold, not a bug — tell me and I'll drop it.

---

## 6. Opportunistic: the stranded-session fix

You can't trigger this on purpose — it needs a transcript to get lost in transit.
If it happens, the symptom is the UI stuck on "Listening" / "Still with you"
forever, never going dormant, after a clank or a cough. Grab the log immediately
if you see it.

---

## Regression checks on recent work

- **Demo cue:** say "okay, looks ready to serve". She should shout the DONUT line,
  the text should appear in the caption, and the model should **not** also answer
  the same sentence. Log shows `demo: scripted cue fired`.
- **Abbreviations:** get her to read a step with "2 tbsp" or "200g". She must say
  "tablespoons" and "grams", never "t-b-s-p".
- **She must never say "chef" herself** — it's the wake word, and hearing it
  through the speaker used to wake her on her own voice.

---

## Ship blocker

`DemoScript.isEnabled` is still `true`. Set it to `false` (or delete
`DemoScript.swift` and its two call sites in `PollySessionController`) before this
goes anywhere near a real user — right now the word "serve" makes Chef shout at
them.

---

## Known-open, don't file these as new

- Her caption appears a second or more before you hear anything on cloned voices —
  the whole reply is synthesised in one blocking request, with no streaming.
- Interrupting may need a raised voice (half-duplex RMS threshold).
- Unverified, from the audit: a network handoff may freeze the session with no
  recovery; the first few seconds after a cloned-voice greeting may be deaf;
  dismissing a phone call may leave the session looking live but dead; four
  rejected utterances in a row (TV, someone else in the room) force dormancy;
  unmuting a technique clip while engaged lets the clip talk to her.
