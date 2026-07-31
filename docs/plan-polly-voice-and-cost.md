# Plan: Polly custom voice, better hearing, and unit economics

Status: ready to execute. Written 2026-07-30.
Supersedes nothing. Complements `docs/plan-polly-v2-voice.md` (the WebRTC rebuild that shipped).

This document is a self-contained handoff. Every file:line reference below was verified against
the repo on 2026-07-30 unless explicitly marked otherwise.

---

## 0. What this is about

The starting question was "can Polly use a custom cloned voice." Investigating it turned up three
separate problems, in ascending order of value:

1. **Unit economics are broken.** A user who cooks with Polly weekly costs more than they pay.
   Fixable with one environment variable.
2. **Polly hears you worse than she needs to**, because of a config regression between the
   WebSocket and WebRTC transports, not because of the model.
3. **There are three different Polly voices** in the app, and the custom-voice work is really
   about collapsing them into one.

Do them in that order. Phase 0 is free and reversible. Phase 3 is the only one that needs a server.

---

## 1. Verified state of the system

### Voice

| Surface | Engine | Voice | Where |
|---|---|---|---|
| Live session | `gpt-realtime-2.1` speech-to-speech | `marin` | `Glutt/Services/Polly/PollyConfig.swift:5-6` |
| Pre-cook briefing | `gpt-4o-mini-tts` | `marin` | `vercel-ai-proxy/api/polly/speak.js:30-31` → `Glutt/Services/Polly/BriefingNarrator.swift:145` |
| Connection lost mid-cook | `AVSpeechSynthesizer` | generic `en-US` | `Glutt/Features/Polly/PollySessionController.swift:199,1177-1183` |

The third is unambiguously a different person and it speaks at the worst moment: called from
`PollySessionController.swift:1133` and `:1172` on connection loss. Its string at `:1180` also
violates the house no-dashes copy rule.

In speech-to-speech the voice is the model's audio decoder, not a parameter. Any owned voice
requires taking that decoder out of the loop (`output_modalities: ["text"]`).

### Transport and audio

- WebRTC via `LiveKitWebRTC` (`livekit/webrtc-xcframework`, pinned `144.7559.11` in `project.yml`),
  used **standalone** with no LiveKit SDK and no LiveKit Cloud.
- Adopted specifically so libWebRTC owns capture, playback, AEC and jitter, "replacing the
  AVAudioEngine graph and its echo-war band-aids" (`RealtimeWebRTCTransport.swift:22-26`).
- Audio session is `.playAndRecord` + `.videoChat` (`PollyAudioSession.swift:41`).
- Wake word survives via the audio device module: `adm.observer = engineTap`
  (`RealtimeWebRTCTransport.swift:187`), plus `setMuteMode(.inputMixer)` and
  `setRecordingAlwaysPreparedMode(true)`.
- Wake-feed paths #1 (APM capture-post delegate) and #2 (local track renderer) are device-proven
  dead: "init=0/frames=0" (`RealtimeWebRTCTransport.swift:183-185`). Only the engine tap is live.
- `captureRMS` is `max(hook.latestRMS, trackRenderer.latestRMS, engineTap.latestRMS)`
  (`RealtimeWebRTCTransport.swift:67-68`). Since the first two are dead, the engine tap is the
  only real source. Barge-in **is** alive, it just runs off a loudness threshold.

### Half-duplex

`RealtimeWebRTCTransport.swift:315`:

```swift
let enabled = micMode == .open && !greetingHold && (!assistantSpeaking || voiceReopened)
```

The mic track is disabled for Polly's whole utterance. To interrupt her you must clear an RMS gate
(`PollyConfig.swift:57-59`): `bargeReopenLoudRMS = 0.12` instantly, or `bargeReopenSoftRMS = 0.055`
twice within 600 ms, sampled on a 50 ms tick.

### The config regression (root cause candidate)

The WebSocket path sets these deliberately, with the reasoning written down
(`Glutt/Services/Polly/RealtimeEvent.swift:188-193`):

```swift
"turn_detection": [
    "type": "semantic_vad", "eagerness": "low",
    "create_response": false,      // client owns when Polly answers
    "interrupt_response": false,   // and when barge-in cancels her audio
]
```

The WebRTC path, which is what ships, omits both (`vercel-ai-proxy/api/polly/session.js:91`):

```js
turn_detection: { type: "semantic_vad", eagerness },
```

So both take the server default while `PollySessionController.swift:877` still sends
`.responseCreate` itself after `ConversationalGate` commits a turn. **Two masters.** A phantom
`speech_started` from her own echo can truncate her, which is the exact failure the half-duplex gate
was built to prevent. The reasoning survived the migration; the config did not.

### Echo canceller

`RealtimeWebRTCTransport.swift:98-106` sets `isEchoCancellationMobileMode = true`. That is AECM,
webrtc's legacy mobile canceller, not AEC3 (the log line at `PollyV2SpikeView.swift:229` calls it
"software AEC3 (mobile)", which is a misnomer). It is only invoked as a **fallback** when VPIO
refuses (`PollyV2SpikeView.swift:227`), never stacked with it. `apm.config` applies live
(comment at `:96`), so this is a runtime A/B on device.

### Proxy

- `vercel-ai-proxy/`, dependency-free Node on Vercel, live at `https://glutt-sable.vercel.app/api`.
  (`api.glutt.org` in `docs/AI-PROXY-SETUP.md` is NXDOMAIN.)
- Auth is a shared static `x-glutt-proxy-key`; no per-user auth. Device identified by
  `x-glutt-device-id`.
- `api/polly/session.js:68` reads `POLLY_REALTIME_MODEL`, defaulting to `gpt-realtime-2.1`.
- `api/polly/session.js:93` pins `transcription: { model: "gpt-4o-transcribe", language: "en" }`.
- `api/polly/session.js:27-45` `deviceCapExceeded()` defaults `POLLY_MONTHLY_SESSION_CAP` to **200**
  and returns `false` when the Upstash vars are missing. It fails open by design (`:24`, "a broken
  counter must never block a cook"). The Upstash vars are not currently set, so there is no cap.
- **ElevenLabs is already a keyed production vendor**: `ELEVENLABS_API_KEY` serves Scribe v2 at
  `api/import/transcribe.js:65`, with per-minute usage logging. A new voice vendor is not a new
  secret, a new billing hookup, or a new pattern.
- `api/polly/speak.js:107` sets `x-glutt-polly-voice` from `process.env.POLLY_VOICE` resolved at
  `:30`. It echoes the request, it does **not** report what OpenAI rendered. Do not use it as
  evidence of anything.

### Measured cost

`ai_usage` rows 51 and 57 (both `polly_realtime`, `gpt-realtime-2.1`) show `input_tokens: 4630` per
response. One active session logged 90,545 text input tokens in 3.10 minutes.

**The dominant cost is re-sending the ~4,630 token prompt on every response, not listening.**

`ai_usage` columns today: `id, user_id, install_id, feature, model, input_tokens, output_tokens,
audio_input_seconds, audio_output_seconds, duration_ms, ok, created_at, audio_input_tokens,
audio_output_tokens`. There is **no `cached_input_tokens` column**, so it is currently impossible to
tell whether prompt caching is hitting, and that is worth up to 10x on the prompt line.

`audio_input_seconds` and `audio_output_seconds` are NULL on every row.

### Confirmed pricing (per 1M tokens, OpenAI official pricing page)

| Model | Audio in | Audio cached | Audio out | Text in | Text cached | Text out |
|---|---|---|---|---|---|---|
| `gpt-realtime-2.1` | $32.00 | $0.40 | $64.00 | $4.00 | $0.40 | $24.00 |
| `gpt-realtime-2.1-mini` | $10.00 | $0.30 | $20.00 | $0.60 | $0.06 | $2.40 |

Note: text output on 2.1 is **$24**, not $16. The $16 figure belongs to the superseded
`gpt-realtime` / `gpt-realtime-1.5` snapshots.

### Cost model, 45-minute cook, Polly awake 20 min, ~50 responses

| Line | Tokens | Flagship | Mini |
|---|---|---|---|
| Text in (prompt × 50) | 231,500 | $0.93 | $0.14 |
| Audio in | 12,000 | $0.38 | $0.12 |
| Audio out | 10,000 | $0.64 | $0.20 |
| Text out | 5,500 | $0.13 | $0.01 |
| Transcription | 20 min | $0.12 | $0.12 |
| **Total** | | **$2.20** | **$0.59** |

Against ~$59.50 net revenue per year on a $70 subscription (after Apple's 15% Small Business rate):

| Usage | Flagship | Mini |
|---|---|---|
| 2 cooks/month | $53 ok | $14 ok |
| 1 cook/week | $114 **loss** | $31 ok |
| 2 cooks/week | $229 **loss** | $61 marginal |

---

## 2. Phase 0 — cost and safety. Free, reversible, do first.

No app build required for 0.1 and 0.2. Nothing here depends on any later decision.

### 0.1 Switch the brain to mini

Set the Vercel env var:

```
POLLY_REALTIME_MODEL=gpt-realtime-2.1-mini
```

`api/polly/session.js:68` already reads it. 3.7x cost reduction, instantly revertible, no App Store
review. Then **listen**: run one real cook and judge whether mini's audio comprehension holds up in
a noisy kitchen. If it degrades noticeably, revert and rely on 0.3 and 0.4 instead.

Also update `Glutt/Services/Polly/PollyConfig.swift:5` if the client-side constant is used anywhere
as more than a fallback label; the proxy is authoritative for what gets minted.

### 0.2 Turn the device cap on

Set `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` in Vercel, and set
`POLLY_MONTHLY_SESSION_CAP=25`. Without the Upstash vars, `deviceCapExceeded()` at
`api/polly/session.js:27-45` returns `false` unconditionally, so the documented 200-session default
is not actually enforced. At 52 minutes per session (`PollyConfig.swift:42`), an uncapped device is
worth roughly $430/month on the flagship.

Keep the fail-open behaviour. It is correct: a broken counter must never block a cook.

### 0.3 Make caching visible

```sql
-- supabase/migrations/0011_cached_tokens.sql
alter table ai_usage add column cached_input_tokens integer;
alter table ai_usage add column cached_audio_input_tokens integer;
```

Then populate them from the realtime `usage.input_token_details` object. The parser already exists at
`Glutt/Services/Polly/RealtimeEvent.swift:251-256` (`RealtimeUsage.init`) and needs the cached fields
added; the payload is assembled in `Glutt/Services/Polly/PollyTokenService.swift:101-107` and written
by `vercel-ai-proxy/api/polly/usage.js`.

Also add `chars` / `chars_per_1k` to `ai_rates` and `ai_usage` before the first ElevenLabs call in
Phase 2. An unrated model costs $0 by construction, and there are already two acknowledged
undercounts (`gpt-4o-transcribe` inside every session, and `polly_speak` audio tokens). Do not add a
third.

### 0.4 Fix the usage meter's fragility

`PollyTokenService.swift:110` is `_ = try? await transport(request)` — fire and forget, no retry. A
crash or force-quit loses the row. Persist the payload and drain on next launch. Also populate
`audio_input_seconds` / `audio_output_seconds` (currently NULL on every row, gap at
`PollyTokenService.swift:99-107`) so the migration `0006` per-minute rate columns work and so the
token-per-minute rates below can finally be measured rather than assumed.

### 0.5 Instrument latency

`Glutt/Features/Polly/PollyV2SpikeView.swift:309` already times speech-end to audio-start. Promote it
into production behind `PollyDebugLog` and collect a histogram. **Every latency number in this
document is a model, not a measurement.** Do this before any architecture decision.

---

## 3. Phase 1 — hearing. Four small edits, then one device test.

This is the experiment that decides whether Phase 3 is necessary. It may hand you full duplex on the
current stack for free.

### 1.1 Stop the server from truncating her

`vercel-ai-proxy/api/polly/session.js:91`:

```js
turn_detection: {
  type: "semantic_vad",
  eagerness,
  create_response: false,
  interrupt_response: false,
},
```

Matches what the WebSocket path already does (`RealtimeEvent.swift:188-193`) and what the client
already assumes (`PollySessionController.swift:877`). Proxy deploy, no app build.

**Check after deploying:** the greeting still fires. It is the one thing that might have relied on a
server-spawned response. If it goes silent, the greeting needs an explicit `response.create`.

### 1.2 Use the modern echo canceller

`Glutt/Services/Polly/RealtimeWebRTCTransport.swift:102`:

```swift
config.isEchoCancellationMobileMode = false   // AEC3, not legacy AECM
```

### 1.3 Stack AEC3 with VPIO instead of using it as a fallback

`Glutt/Features/Polly/PollyV2SpikeView.swift:227` — call `transport.enableSoftwareAEC()`
unconditionally after connect, not only when `!transport.isPlatformAECActive`. LiveKit's own SDK
models the target state as both cancellers active at once. Fix the misleading log string at `:229`
while you are there.

### 1.4 Full duplex, behind a debug toggle

`Glutt/Services/Polly/RealtimeWebRTCTransport.swift:315`:

```swift
let enabled = micMode == .open && !greetingHold
```

Put it behind a runtime toggle so you can A/B **inside a single session** rather than across two
builds.

### 1.5 The test

One device session. Real kitchen: loudspeaker, pan sizzling, tap running, extractor fan on. Not the
simulator, which cannot validate any of this.

Count, in both toggle states:
- phantom `input_audio_buffer.speech_started` events during Polly's utterances
- times she is cut off mid-sentence
- times a genuine interruption is missed

Test matrix that matters: iPhone 15-or-earlier **and** iPhone 16+ (`setPrefersEchoCancelledInput` is
iOS 18.2+ on certain 2024+ models and is invalid with `.videoChat`, which `PollyAudioSession.swift:41`
uses); built-in speaker, AirPods, and a Bluetooth kitchen speaker.

### How to read the result

- **Phantoms gone** → you have full duplex without migrating. LiveKit becomes a voice-and-reliability
  decision only, not a hearing one.
- **Phantoms persist** → you have measured, on your own hardware, the exact defect that LiveKit's
  `adaptive` interruption and `resume_false_interruption` exist to tolerate. That is the honest
  reason to move to Phase 3.

### 1.6 Better transcripts, which change behaviour here

`api/polly/session.js:93` pins `gpt-4o-transcribe`, which does not support keyword boosting. Models
that do (`gpt-live-transcribe`, `gpt-transcribe`) accept
`transcription: { model, prompt, keywords, languages, delay }`.

This is **not** cosmetic in this app. `PollySessionController.swift:993-999` feeds the input
transcript into `handleGatedTranscript`, and `ConversationalGate` decides on that text whether Polly
answers at all, including `looksUnfinished`, `isClearInterruption`, and
`consecutiveRejects >= 4 → dormant`. A mis-transcribed "deglaze the pan" becomes a rejected turn
becomes dormancy. Seed `keywords` with the current recipe's ingredients and techniques; it can be
re-sent mid-session via `session.update`.

*(The `:993-999` line reference came from an analysis agent and was not independently verified.
Confirm before relying on it.)*

---

## 4. Phase 2 — one Polly voice. No live-loop risk.

### 2.1 Bake-off first, and do it blind

A harness already exists at
`/private/tmp/claude-501/-Users-omarlahmimi-Documents-Glutt/e0b484f0-7e47-46e2-b0ea-4fdf5e125c23/scratchpad/voice-bakeoff/`
(`lines.json` + `bakeoff.mjs`). Move it into the repo if you want to keep it. It:

- pulls 10 real Polly registers from `PollyPromptBuilder.swift` (number callout, heat step, two
  rescue lines, teach voice, wait, small win, the real failure line)
- renders each on a **fast** tier and an **expressive** tier, discovered from `/v1/models` rather
  than hardcoded, because testing only the fast tier measures the wrong thing
- measures real time-to-first-byte from your network
- blinds the output with random tags and an answer key

```bash
export ELEVENLABS_API_KEY=...
node bakeoff.mjs list
node bakeoff.mjs render --voice <id>
```

Listen on a phone speaker at counter distance with the fan on, **before** opening `key.json`.
Judge the number callout and the two rescue lines hardest; prep and encouragement are easy for any
decent engine.

**Kill criterion: if nobody prefers the new voice, stop the whole voice project here.**

### 2.2 Design an original voice. Do not clone a human.

Use ElevenLabs Voice Design (`POST /v1/text-to-voice/design`), not cloning.

Reasons, in order:
- Their policy permits Professional Voice Cloning of **your own voice only**. Cloning someone else
  is not permitted even with consent. The documented workaround has the actor create the clone on
  *their* account and share it by revocable link, contingent on them keeping a paid plan. That is
  not an asset you own.
- Their ToS takes a perpetual, irrevocable, sublicensable licence over the voice and indicia of
  persona, which you would have to sub-grant onward from any actor.
- The cloned tier is documented as the slowest for latency, and the expressive conversational model
  explicitly does not preserve professional clone characteristics. Cloned-and-expressive is not a
  shippable combination.
- An unverified clone cannot be deleted once verification starts, and a failed captcha costs a
  24-hour lockout.

Never ship a premade library voice: they expire 31 December 2026.

**Portability:** even a designed voice is a slot on ElevenLabs' account. The only genuinely portable
asset is rendered audio committed to the repo. As soon as the voice is locked, render a few minutes
of clean reference lines and keep them. That is the rebuild kit.

**Disclosure:** ElevenLabs' Prohibited Use Policy requires clearly disclosing to users that they are
interacting with AI. OpenAI's TTS terms impose the same. You already carry this obligation via the
briefing. Add a line to the Polly onboarding copy regardless of vendor.

### 2.3 Repoint the briefing

`vercel-ai-proxy/api/polly/speak.js:30-31` resolves `POLLY_VOICE` and `gpt-4o-mini-tts` (now
deprecated by OpenAI). Add an ElevenLabs branch behind `POLLY_TTS_VENDOR`, keeping the
request/response contract byte-identical so `Glutt/Services/Polly/PollySpeechClient.swift` and
`BriefingNarrator.swift` need no changes.

### 2.4 Kill the robot failure voice

`PollySessionController.swift:1177-1183` uses `AVSpeechSynthesizer` with a generic `en-US` voice
(`offlineVoice` at `:199`), reached from `:1133` and `:1172`.

Render 8 to 12 failure lines plus 4 fillers **at build time** into `Glutt/Resources/PollyVoice/`,
and play them from a new `Glutt/Services/Polly/PollyVoiceFallback.swift`. It must configure its own
audio session, since it runs after WebRTC teardown. Build-time rather than runtime because the
failure case is frequently "no network," and because bundled audio is the only portable voice asset
you will own.

Declare the folder in `project.yml`, then `xcodegen generate`.

Also fix the copy at `:1180` — it contains an em dash, violating the house rule. Replace with:

```
"I have lost my connection, chef. Your steps stay right here on the screen."
```

### 2.5 Voice consistency is the whole point

Do **not** ship 2.3 alone. Right now all three surfaces at least intend to be `marin`
(`speak.js:2-4` says so explicitly). Giving only the briefing a new voice replaces one inconsistency
with a worse one. Ship 2.3 and 2.4 together, or neither.

---

## 5. Phase 2b — persona and delivery. Zero latency, zero infrastructure.

Run this in parallel with everything else. It is the highest value-per-risk work in the document and
it applies whether or not you ever migrate.

- **Rewrite `personaSection()`** (`Glutt/Services/Polly/PollyPromptBuilder.swift:39`, with
  `# Speaking style (strict)` at `:48`) into: a delivery spec (how to land quantities, "say one
  eighty, slow the number, leave a beat"), a register map keyed to plan phase (prep brisk, heat
  tighter and shorter, waits relaxed, rescue low and calm), a lexicon with per-session frequency
  budgets, and non-lexical delivery bound to triggers rather than turns.
- **Reconcile, do not append.** `runPolicySection()` at `:226` already says "Be directional, never
  chatty." Layering warmth on top without reconciling gives a model that picks a personality per
  turn.
- **New `Glutt/Services/Polly/PollyDelivery.swift`**: moment → per-response instruction fragment,
  wired into the existing `responseCreateWithInstructions` sites. Genuine prosody control at zero
  latency. Watch for her reading the stage direction aloud; the existing sites carry *semantic*
  instructions, so delivery-only ones are untested here.
- **Move the persona block into the mint response.** It is compiled into the binary today, so every
  listening-test iteration is an App Store review. Serve it from `session.js` and it iterates at
  env-flip speed. Do this first or this phase takes a quarter instead of a week.
- **Golden-string test** on the assembled instructions. The prompt-cache design depends on byte
  stability (`PollyPromptBuilder.swift:4-9`), and with the prompt at 4,630 tokens per response a
  variance bug is the difference between the $0.09 and $0.93 columns.

**Also: shrink the prompt.** At 4,630 tokens re-sent per response it is the single largest cost line
on the flagship. Audit `PollyPromptBuilder.swift` (387 lines) for content that could move into tool
results fetched on demand rather than living in every turn's prefix.

---

## 6. Phase 3 — LiveKit Agents. Only if Phase 1 fails.

### The one structural reason to do this

The agent's voice arrives as a WebRTC **remote audio track**, so playback, AEC and jitter stay inside
libWebRTC exactly as they do today. The app never owns playback.

This matters more than anything else. Today `renderPreProcessingDelegate: renderMonitor`
(`RealtimeWebRTCTransport.swift:157-161`) gives a sample-accurate "her audio is physically playing"
signal from inside libWebRTC, which is your AEC reference. A device-direct ElevenLabs voice played
through AVAudioEngine sits outside the render path: you lose the AEC reference, you lose NetEq jitter
buffering, and `PollyRenderMonitor` stops working. **A device-direct custom voice does not degrade
the echo defence, it dismantles it.** Server-side TTS re-encoded into the subscriber track is the
only architecture where an owned voice is free.

### Target configuration: half-cascade, not full cascade

```python
AgentSession(
    llm=openai.realtime.RealtimeModel(modalities=["text"]),
    tts=<your voice>,
)
```

`push_audio()` emits `input_audio_buffer.append` with no modality check, and the session update sends
the full audio input config (format, noise reduction, transcription, turn detection) unchanged. Only
`output_modalities` flips. So `far_field`, `gpt-4o-transcribe` (or the keyword-boosted replacement),
and camera frames via `push_video()` all survive. You keep audio-native comprehension **and** own the
voice.

Do not use a full STT → text LLM → TTS cascade. It throws away tone, urgency, and the ability to
recover from a mis-hearing, and it costs more than what you run today.

### What LiveKit genuinely gives you

| | Today | LiveKit Agents |
|---|---|---|
| Mic open while she speaks | no | yes |
| False-interrupt recovery | none | `resume_false_interruption` (2.0s default) |
| WiFi → cellular mid-cook | session dies | agent keeps `ChatContext` |
| Debugging a bad turn | clipboard log | downloadable both-sides audio, captured post-noise-cancellation |
| Turn detection | `semantic_vad` `eagerness: low` | Turn Detector v1 |
| Client-side noise filter | VPIO only | VPIO only (see below) |

### What is marketing, for your case specifically

- **Krisp BVC is not available to you.** Background voice cancellation ships on no native client
  SDK and is documented as for headsets, not speakerphone. The iOS Krisp filter is hard-gated on a
  LiveKit Cloud room token *and* attaches to `capturePostProcessingDelegate` — wake-feed path #1,
  which is already device-proven dead on your stack (`RealtimeWebRTCTransport.swift:183-185`).
  Agent-side BVC does exist and is metered as "voice isolation minutes."
- **The turn-detector benchmark is theirs.** 543 ms vs OpenAI's 1143 ms on eot-bench, but LiveKit
  wrote both the benchmark and the winner, and they tested OpenAI at `eagerness: auto`, **not your
  `low`**. No far-field breakdown exists.
- **Acoustic processing is identical.** Same libwebrtc APM, same Apple VPIO. LiveKit has no
  server-side AEC. What changes is policy, not signal processing.

### Pricing (confirmed from livekit.com/pricing and docs.livekit.io)

- Both the media server and the agents framework are **Apache 2.0**. Self-hosting both means you pay
  LiveKit $0.
- The "agent session minute" meter ($0.01/min after allowance) is defined as applying to *agents
  deployed to LiveKit Cloud*. Self-hosted agents do not hit it.
- Ship plan: $50/month, includes 5,000 agent session minutes and 150,000 WebRTC participant minutes.
  At ~100 session-hours/month you stay inside the allowance.
- Krisp NC (not BVC) is included with Cloud at no per-minute charge. Voice isolation / BVC is
  metered at $0.0012/min after allowance.
- **Observability requires Cloud.** It does not work with self-hosted media servers. Since
  observability is one of the two things actually worth having here, self-hosting is probably the
  wrong trade at your volume.
- The free Build plan hard-fails past its allowance rather than billing overage, capping you at
  ~16.7 session-hours. It cannot serve this workload.

**Recommendation: LiveKit Cloud, Ship plan, $50/month.** Do not self-host. The saving is $10 to $56
a month against a model bill several times larger, and self-hosting forfeits both Krisp and
observability.

### Cost impact

Roughly +$0.38/hr versus today with TTS free: +$0.70 transport rent, +$0.38 for full-duplex input
audio, offset by −$0.71 because text output replaces audio output. On mini the whole picture stays
well inside the subscription.

### Client work

- Add the LiveKit Swift SDK. It is built on the same webrtc-xcframework you already pin; check for
  conflict with the standalone dependency in `project.yml`.
- Wake word survives: `set(engineObservers:)` → `engineWillConnectInput` is the equivalent of
  `adm.observer`. Verify on device before committing.
- Camera: publish frames to the agent. The current on-demand JPEG tool call
  (`PollyCameraController.swift:66-91`) is decoupled from audio transport, so this is a data-path
  change, not an architecture change.
- On-device tools: the 15 tools in `PollyToolRegistry.swift` move from zero-hop local dispatch to an
  RPC round trip via the SFU (15 KiB cap, 7s ack). This is a regression; measure it.

### Gates that must clear before committing

1. **Which event carries text in text-out mode.** UNCONFIRMED: the API reference implies
   `response.output_text.delta`, the cookbook shows `response.text.delta`. Design for all three
   names including `response.output_audio_transcript.delta`, and log unhandled types loudly as
   `PollySessionController.swift:934-935` already does.
2. **Whether `output_modalities: ["text"]` is accepted at mint** (`POST /v1/realtime/client_secrets`)
   rather than only in `session.update`. A rejected session block rejects the **entire**
   `session.update`, and Polly silently runs as a generic assistant with no persona and no tools —
   the exact failure already documented at `RealtimeEvent.swift:197-200` for a missing `rate` field.
   One curl proves it.
3. **Whether audio input is still billed at the audio rate under text-only output.** Schema-supported
   but officially undocumented. Cheap to verify empirically once 0.3 lands.

---

## 7. Open questions and unverified claims

Marked so a future session does not treat them as settled.

- **UNCONFIRMED:** the ~600 tokens/min input and ~1200 tokens/min output audio rates used throughout
  this document. OpenAI does not publish them on any official page. Phase 0.4 (logging
  `audio_input_seconds` / `audio_output_seconds`) makes them measurable. All per-hour figures here
  depend on them.
- **UNCONFIRMED:** whether prompt caching is currently hitting. Worth up to 10x on the prompt line.
  Phase 0.3 makes it visible.
- **UNCONFIRMED:** whether an ephemeral `single_use_token` mint exists for raw ElevenLabs TTS. Only
  matters for a device-direct design; irrelevant if the TTS call happens on a LiveKit worker.
- **UNCONFIRMED:** ElevenLabs Flash's "~75 ms" figure — whether that is playable audio or a container
  header.
- **NOT VERIFIED FIRST-HAND:** `PollySessionController.swift:993-999` transcript → `ConversationalGate`
  wiring, and the claim that `PollyCaptureHook`'s gates (`:317`, `:645`, `:697`) are dead code.
  Both came from analysis agents. The dead-hook claim is supported by the file's own comment at
  `:184` but confirm before deleting anything.

### Dead code to remove (from the merge list in `docs/plan-polly-v2-voice.md`)

`Glutt/Services/Polly/PollyAudioEngine.swift` (558 lines, `start()` has zero app call sites),
`PollyCaptureHook`'s gates, `PollyRenderMonitor`, `PollyLocalTrackRenderer`, and
`PollyConfig.onsetCaptureGateSeconds` / `bargeInRMSFloor` / `hybridWindowSeconds` (zero references).

**Lift the `PCM` enum into a new `Glutt/Services/Polly/PCM.swift` first.** Its `resample` sets
`primeMethod = .none` and is exactly what any external audio player would need.

**Keep `PollyEngineTapObserver`. It is the wake feed.**

Reasoning about echo behaviour with five dead gates in the file is how the next 3am debugging round
loses three days.

---

## 8. Summary of the ordering

| Phase | What | Risk | Needs a build? |
|---|---|---|---|
| 0.1 | `POLLY_REALTIME_MODEL=gpt-realtime-2.1-mini` | none, revertible | no |
| 0.2 | Upstash vars + cap to 25 | none | no |
| 0.3 | `cached_input_tokens` column + rate rows | none | migration |
| 0.4 | Persist and retry the usage report | low | yes |
| 0.5 | Promote the latency timer | low | yes |
| 1.1 | `create_response`/`interrupt_response` false | low, check greeting | no |
| 1.2-1.4 | AEC3, stacked, full-duplex toggle | medium, device only | yes |
| 1.5 | The kitchen test | none | no |
| 1.6 | Keyword-boosted transcription | low | no |
| 2.1 | Blind bake-off | none | no |
| 2.2-2.5 | Designed voice, briefing, failure lines | low | yes |
| 2b | Persona and delivery | none | yes |
| 3 | LiveKit Agents half-cascade | high | yes, plus a worker |

Phase 0 pays for itself immediately. Phase 1 may make Phase 3 unnecessary. Phase 3 is a
voice-and-reliability decision, not a hearing one, unless Phase 1's kitchen test says otherwise.
