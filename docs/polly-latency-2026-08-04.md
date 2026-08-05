# Polly latency: where the time actually goes

**Measured 2026-08-04.** iPhone 17 Pro simulator (iOS 26.3), Debug build, recipe
"Creamy Lemon Chicken Rice Bowl" (7 plan steps), house voice `marin`, model
`gpt-realtime-2.1`, WebRTC transport, `semantic_vad` with `eagerness: low` and
`create_response: false`.

All numbers are read straight off `PollyDebugLog` timelines (More → Copy debug
log). Turns were driven by speaking into the simulator's microphone from the
Mac's speakers, so they are real end-to-end voice turns, not synthetic injections.

**Caveat, per CLAUDE.md:** the simulator borrows the Mac's network stack, TLS
fingerprint and egress IP, and its "microphone" is the room. Absolute network
legs (token mint, model round trips) will differ on a phone on cellular, and
platform AEC (VPIO) never activated here, which real hardware does. The
*shape* of the breakdown, and every ordering finding, holds regardless.

---

## 1. Session start (tap Cook → her first word)

### Before the change in this branch

| Leg | Cold (plan cache MISS) | Warm (cache HIT) |
|---|---|---|
| App start → plan compile begins | 0.68s | 0.56s |
| **Cook plan compile** | **7.96s** (LLM) | 0.21s |
| **Token mint** (Vercel proxy) | **1.11s** | 0.85s |
| Transport init + audio session | 0.19s | 0.11s |
| **Software AEC (AEC3) init** | **1.18s** | 1.00s |
| session.update → first audio | 1.36s | 1.37s |
| **Total to first spoken word** | **12.57s** | **4.21s** |

### After (token mint moved alongside the plan compile)

| Leg | Cold | Warm |
|---|---|---|
| Cook plan compile | 8.04s | 0.18s |
| Token mint | **0.00s on the critical path** | ~0.2s |
| Software AEC init | 0.93s | 0.86s |
| session.update → first audio | 1.38s | 1.19s |
| **Total to first spoken word** | **10.51s** | **4.05s** |

The cold-start log now reads:

```
+8.04s session: plan ready — 7 steps
+8.07s session: token minted — model=gpt-realtime-2.1 voice=marin
```

The mint used to start *after* plan-ready and finish 1.11s later. It is now
issued before the compile and has always finished by the time the plan lands.

### What still dominates a cold start

**The cook plan LLM compile is 8.0 seconds, 76% of the remaining 10.5s.** Nothing
else is close. It is cached per recipe+scale on disk, so it is a first-cook-only
cost, but the first cook of a dish is exactly the demo.

---

## 2. Voice turns (cook stops talking → her voice comes out)

| Turn | speech_stopped → transcript | transcript → response.create | → first audio | **voice-to-voice** |
|---|---|---|---|---|
| "How long should I bake the muffins for?" | 430ms | 10ms | 1276ms | **1716ms** |
| "The" (junk, single word) | 430ms | 0ms | 880ms | **1317ms** |
| "I know we are still on the first step, but tell me now, how do I finish the very last step of this recipe?" | 550ms | 0ms | 1600ms | **2149ms** |
| "What step am I on right now?" (**tool turn**) | 360ms | 0ms | 690ms → *preamble* | **1048ms** (misleading, see below) |
| Barge-in collision (see §4) | 480ms | 20ms | 4260ms | **5023ms** |

A plain question is answered in **1.3–2.1s**, which is fine. The client-side
conversational gate costs essentially nothing (0–20ms). Transcription
(`gpt-4o-transcribe`) is a consistent **360–550ms**, and it is fully serial:
because `create_response: false`, the model does not start generating until the
transcript is back and the gate has ruled.

### Tool turns are the slow ones

`"What step am I on right now?"`:

```
+117.37s speech stopped
+117.73s heard: "What step am I on right now?"          (360ms transcription)
+117.73s gate: committed user turn → response.create
+118.42s event: assistant audio START                   ⏱ voice-to-voice 1048 ms
+119.47s response DONE tools=[get_current_step]
             said="Let me check where you are in the plan so we keep things moving smoothly."
+122.30s response DONE  said="You're on the Tools step: pull out a skillet, saucepan, whisk…"
```

The real answer lands **4.93s** after the cook stopped speaking. Two serial
model passes: ~1.7s to decide on the tool, then ~2.8s to answer with its output.
Tool execution itself is a local dictionary lookup and is free.

**The instrumented `voiceToVoiceMs` metric under-reports this.** It stops at the
first audio, which on this turn was a spoken preamble. The p50/p95 shipped in
the end-of-session analytics event is therefore optimistic on exactly the turns
that feel slow.

**She emitted that preamble in direct violation of the prompt.** The persona
section already says, in capitals, to produce no audio in the same response as a
tool call. She said "Let me check where you are in the plan so we keep things
moving smoothly" anyway. Not changed here: the rule already exists, and shouting
it louder is a guess, not a fix.

---

## 3. Wake word and the half-duplex governor are not the problem

```
+112.55s wake: heard "Chef" in "Chef"
+112.56s governor: force open for wake
```

**~10ms** from on-device wake detection to the microphone opening. The governor,
the RMS floors, and the follow-up window never appeared on any critical path in
these logs.

---

## 4. The one genuinely pathological case

When the cook speaks while Polly is still talking, a barge-in cancel and a new
`response.create` race each other, and the new response took **4.26s** to start
emitting:

```
+7.65s  gate: wake during her turn — cancelling her response
+7.67s  gate: committed user turn → response.create
+7.73s  response DONE status=cancelled
+11.20s watchdog: no reply 4s after user turn (strike 1)
+12.19s ⏱ voice-to-voice 5023 ms
+12.76s response DONE  said="Sorry, I missed that—could you say it again, please?"
```

`PollyConfig.responseWatchdogSeconds` is 4s. The turn took 5.0s, so **the
watchdog fired and made her apologise for a turn she was already answering**.
This is the failure the code comment on `noteVoiceToVoiceLatency` predicted,
observed for the first time. It is not the common case, but it is the one that
sounds broken rather than merely slow.

---

## 5. Changed in this branch

**Token mint runs concurrently with the plan compile**
(`Glutt/Features/Polly/PollySessionController.swift:676`). No data dependency
existed; the mint only needs the chef, which is a synchronous read. Removes the
mint from the critical path entirely on a cold start (1.11s measured) and ~0.2s
on a warm one. Verified in the running app on both cache paths.

Nothing else was changed. Everything below is a recommendation, because each one
is a product or design call.

---

## 6. Recommendations (not implemented, need a decision)

Ordered by size of win.

### A. Prewarm the cook plan — worth ~8s off every first cook

The compile is a one-shot LLM call cached on disk by recipe+scale. It could run
when the recipe detail screen opens, or while the cook trailer plays, so the
plan is already cached by the time they tap Cook.

*The decision:* it costs one LLM call per recipe *viewed* rather than per recipe
*cooked*, so the bill goes up for browsing. Prewarming only on the trailer, or
only for bundled chef dishes, would cap that. Not mine to pick.

### B. Let the server create the response — worth ~400–550ms on every turn

`turn_detection.create_response` is `false` so the client owns when Polly
answers, which is the whole point of the ConversationalGate. The cost is that
generation cannot start until transcription completes.

*The decision:* flipping it to `true` would let generation overlap transcription,
but the gate is what stops her answering the extractor fan, and that gate was
built from real kitchen failures. A middle path exists (let the server start
generating, keep the client's `response.cancel` as the veto) but it changes how
eagerly she speaks, which is a product call.

### C. Keep the current step out of the tool path — worth ~3s on step questions

Every "what step am I on", "what's next", "read that again" costs a full extra
model round trip because `get_current_step` is a tool. If the current step index
and its text were pushed into the conversation as a system note on every step
change, most of those turns would collapse to one pass.

*The decision:* it adds a message per step change (tokens, and prompt-cache
churn on a prefix that is currently byte-stable). Worth measuring against the
3s, but it is a real architecture change.

### D. Fix the voice-to-voice metric to time the answer, not the preamble

`noteVoiceToVoiceLatency()` fires on the first `outputAudioStarted`. On tool
turns that is a preamble she should not be producing at all. Timing to the first
audio of a response that carried **no** tool calls would make the shipped p50/p95
honest.

### E. Raise `responseWatchdogSeconds` above the measured p95

At 4s it fires on real turns (§4). Measured turns ran 1.0–5.0s. The
never-silent contract is a deliberate product promise, so the number is Malik's
to set, but 4s is currently inside the normal distribution rather than outside it.

### F. Software AEC init costs ~0.9–1.2s of every session start

`audio: software AEC ON (AEC3)` is a full second between the transport
initialising and the connection being usable. Worth a look by whoever owns
`PollyAudioEngine` / `RealtimeWebRTCTransport`; deliberately not touched here.
