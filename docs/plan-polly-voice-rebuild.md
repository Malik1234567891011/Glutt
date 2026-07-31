# Plan: Polly voice layer rebuild

Status: in progress. Started 2026-07-30. Branch `polly-voice-rebuild`.
Supersedes the execution order in `docs/plan-polly-voice-and-cost.md`, which stays valid as
research but whose phase ordering was written before the client was diagnosed.

---

## Context

The starting goal was to give Polly a custom ElevenLabs voice. Investigating it turned up
something bigger: **the model is not the problem, the 4,000 lines wrapped around it are.**

The user reports all four of: she does not react when first spoken to; she stops listening
partway through a cook; she cuts herself off and cannot be interrupted; the audio itself breaks.
A code-traced diagnosis found eleven distinct defects, most of them proven rather than inferred,
which together produce exactly those four symptoms without needing a common cause.

Meanwhile the benchmark data says `gpt-realtime-2.1` scores **95.7% on Full Duplex Bench** —
near the top of the industry for turn-taking. Swapping vendor (Qwen 84.1%, Grok 82.9%) would
inherit every one of the eleven defects. So: rebuild the client, keep the model.

### Decisions taken

| Question | Decision |
|---|---|
| Model | Stay on `gpt-realtime-2.1`. Cost is explicitly **not** a priority; quality is. |
| `reasoning.effort` | Pin to `high`. It was unset, so we were running an undocumented default. |
| Architecture | Rewrite the client voice layer. **Not** LiveKit. |
| Custom voice | Decided by a spike (step 9), not up front. |
| Deploy | Branch plus Vercel preview. User merges to main, which is what deploys. |
| Migrations | Applied directly (additive only), and always **before** any client change. |
| Persona rewrite | Dropped. User: "she sounds fine." Only rule deduplication survives. |
| Mini model, device cap | Dropped. Both were cost plays. |

### Why not LiveKit

Its only unique advantage is that server-rendered TTS is guaranteed echo-cancelled. Against
that: the acoustic chain is identical (same libwebrtc APM, same Apple VPIO, no server-side AEC),
the 15 on-device tools become RPC round trips through the SFU with a 15KiB cap and 7s ack, it
costs ~$50/month, and it adds a Python service to operate. Step 9 tests the one thing LiveKit
would buy us, for one day of work.

---

## The eleven defects

Each is traced to code. `file:line` refs were verified 2026-07-30.

| # | Defect | Symptom |
|---|---|---|
| 1 | `handleTransportError` (`PollySessionController.swift:1440-1486`) never closes the old transport. Leaks a peer connection, an ADM, **a second VPIO claim on the mic**, a meter task and a permanent route observer. | audio breaks |
| 2 | `PollySessionView.swift:621-625` "Try again" nils the controller without calling `end()`, leaking the whole stack again. | audio breaks |
| 3 | `WakeWordListener.swift:193-201` drops every buffer between recognition requests, ~once a minute. | no reaction |
| 4 | `PollySessionController.swift:674` reads `wakeWord.isAvailable` once; `SFSpeechRecognizer` is transiently false after init, and nothing observes `availabilityDidChange`. | no reaction |
| 5 | Clip unmute hard-mutes the mic (`:299-301`); only `.finished`/`.paused` restore it (`:303-316`), but teardown emits `.idle`, an explicit no-op (`:317-319`). Advance a step mid-clip and the mic is stranded. | stops listening |
| 6 | `PollyAudioEngine.stop():373` calls `AVAudioSession.setActive(false)` three lines before `transport.close()` (`:728` vs `:731`), while WebRTC is live. Reachable mid-cook via Polly's own `end_session` tool. | audio breaks |
| 7 | Three components mutate `AVAudioSession` directly, which `RTCAudioSession.h:141-144` explicitly forbids. `BriefingNarrator.stop()` never deactivates `.playback` before WebRTC installs `.playAndRecord`. | audio breaks |
| 8 | `ConversationalGate` returns `.uncertain` as its catch-all and four consecutive rejects end the session (`:1124`, `:1135`). "Is that enough?" contains no cook word. | stops listening |
| 9 | `PollySessionController.swift:1386` routes **any** error while `phase != .live` into `handleTransportError`, including the benign `item_not_found` the gate provokes itself on every reject (`:1108`, `:1116`, `:1125`). | "I've lost my connection" |
| 10 | No `interruptionNotification` observer anywhere in production. `DormantReason.audioInterrupted` (`:799`) is declared and never emitted. A phone call kills the cook. | stops listening |
| 11 | `enableSoftwareAEC()`, `isPlatformAECActive` and `audioDiagnostics()` are reachable only from `PollyV2SpikeView`, gated on `-pollyV2Spike` (`RootView.swift:22`). Production cannot observe whether AEC runs and has no fallback. | everything |

Plus the server-side one: `vercel-ai-proxy/api/polly/session.js` omits `create_response` and
`interrupt_response`, so both default to `true` and the server answers and truncates on its own
while the client also drives `response.create` at `:1189`. Two masters.

---

## Steps

### 1. `reasoning.effort` — DONE

`vercel-ai-proxy/api/polly/session.js`. `POLLY_REASONING_EFFORT`, default `high`, validated
against the allowed set, with a 400-fallback that re-mints without the field rather than failing
the session. Applied value surfaces as `x-glutt-polly-reasoning` and in the JSON body.

The only change that makes Polly smarter and better at tools: agentic (τ-Voice, which *is* tool
calling) goes 38.0% → 45.7%, overall 72.5% → 79.1%. Costs ~+240ms TTFA — watch it against
`PollyConfig.responseWatchdogSeconds` (4s).

### 2. One owner of `AVAudioSession`

Route every category/active change through `LKRTCAudioSession.lockForConfiguration`. Delete the
`setActive(false)` in `PollyAudioEngine.stop()`. Make `BriefingNarrator` hand the session over
cleanly instead of leaving `.playback` active.

### 3. Transport lifecycle

Close the old transport before assigning a new one in `handleTransportError`. Call `end()` on
retry. Remove the route observer in `close()`. Add an instance counter so a leak shows up in the
debug log instead of as mystery crackle.

### 4. Wake word

Overlap recognition requests so no audio is dropped at the seam. Observe
`availabilityDidChange` and retry instead of a one-shot read. Feed one consistent format.

### 5. Clip/mic state machine and error routing

Restore `micMode` on `.idle` too, and on player teardown. Narrow `:1386` so only genuine
transport errors reach `handleTransportError`.

### 6. Interruptions

Observe `interruptionNotification`. Emit the `audioInterrupted` events that already exist as
dead enum cases. Pause and resume rather than dying.

### 7. AEC into production, plus the A/B toggles

Log `audioDiagnostics()` 1.5s after connect so AEC state is finally observable. Switch to AEC3
(`isEchoCancellationMobileMode = false`). Two `@AppStorage` toggles in the `PollySessionView`
overflow menu — stacked AEC, and full duplex — shipping in Release so both can be A/B'd inside
one session on a real device.

### 8. Gate replacement

Adopt OpenAI's published pattern: a `wait_for_user` no-op tool plus their "Unclear Audio" prompt
block, written for exactly this problem — kitchen noise, side conversation, TV. Replaces brittle
string heuristics with a model decision. Set `create_response: false` and
`interrupt_response: false` at mint so the client is the sole owner of when Polly speaks.

### 9. The voice spike — decides the architecture

Set `output_modalities: ["text"]`, stream text to ElevenLabs, play through the **same
voice-processing unit** rather than a separate `AVAudioPlayer`. Measure whether VPIO cancels it.

- **Pass** → cloned voice ships, tools stay local, nothing monthly.
- **Fail** → adopt LiveKit Agents for server-rendered TTS, knowing exactly why.

### 10. Instrumentation

Voice-to-voice timer promoted from the spike view into `PollySessionController` (`.speechStopped`
`:1296` → `.outputAudioStarted` `:1256`), percentiles to PostHog via the existing
`Analytics.capture` façade at the `.cookFinished` site. Durable usage queue modelled on
`ImportInbox.swift:6-38` — 27 session mints produced 10 usage rows, so 63% of sessions currently
report nothing. `cached_input_tokens` columns via migration **first**, because
`_lib/usage.js:72` spreads fields verbatim into PostgREST and never checks the status, so an
unknown column silently loses the entire row.

---

## Status as of 2026-07-30

Branch `polly-voice-rebuild`, 7 commits, 380 tests green, nothing merged.

| Step | State |
|---|---|
| 1 `reasoning.effort` | **done** — `POLLY_REASONING_EFFORT`, default `high`, 400-fallback, reported via `x-glutt-polly-reasoning` |
| 2 audio session ownership | **partly done** — the `setActive(false)`-under-live-WebRTC landmine is gone, `BriefingNarrator` releases its session, incoming category logged. The `LKRTCAudioSession.lockForConfiguration` migration is NOT done: it is the riskiest change here and cannot be validated anywhere but a device |
| 3 transport lifecycle | **done** — old transport closed before the new one connects, `abandon()` for retry, live instance counter in the log |
| 4 wake word | **done** — no deaf window at the segment seam, availability retried instead of read once, one audio format per session |
| 5 clip/mic and error routing | **done** — `.idle` releases the hold, 120s failsafe, only `code == "transport"` reaches the reconnect ladder |
| 6 interruptions | **done** — observed, resumed on `shouldResume`, dormant with an explanation |
| 7 AEC into production | **done** — applied and verified in `connect()`, AEC3 not AECM, two toggles in the overflow menu |
| 8 gate | **done** — `create_response`/`interrupt_response` false, `wait_for_user` tool, Unclear Audio and Silence prompt blocks |
| 9 latency | **done** — voice-to-voice timer in production, p50/p95 on the `cookFinished` PostHog event |
| 9b usage durability | **not done** — 27 mints produced 10 usage rows. Cost-visibility work, deprioritised |
| 10 voice spike | **PASSED** — cloned voice ships on device, LiveKit not needed. See below |

### Step 10 result: device-side ElevenLabs playback stays echo-cancelled

Settled 2026-07-31 from three device cooks (45, 293 and 429 line logs), not from
reasoning.

The question was whether audio the app plays itself — outside libWebRTC, through
`AVAudioPlayer` on the shared session — is still cancelled by Apple's
voice-processing unit. `docs/plan-polly-voice-and-cost.md` assumed it would not,
and used that to argue for LiveKit and server-rendered TTS: "a device-direct
custom voice does not degrade the echo defence, it dismantles it."

**The decisive test is whether Polly's own words ever come back as a USER
transcript.** Across every turn of all three cooks, they never do — each `heard:`
line is the cook, none contains a phrase she spoke. `AEC[avail=1 req=1 ACTIVE=1]`
throughout. VPIO cancels her even though libWebRTC no longer owns playback.

So: **the cloned voice runs on device. No LiveKit, no Python worker, no
$50/month, and the 15 tools stay local and zero-hop.** That closes the largest
open architectural question in both plan documents.

One caveat from the same data. The residue is inaudible to the transcriber but
not to the RMS meter: the mic reopened mid-utterance at `rms 0.069` and `0.088`
with the cook silent. `bargeReopenSoftRMS` raised 0.055 → 0.09; real speech
measured 0.162–0.233 in the same logs.

### What needs a device, not a simulator

Everything acoustic. The simulator validates none of it. On the first real cook,
copy the debug log (`…` menu, or long-press the session timer) and check:

- `AEC[avail= req= ACTIVE=]` — if `ACTIVE=0`, VPIO is not engaging and the
  software canceller is all you have. That single line has never been available
  before.
- `transport: init/deinit (live=N)` — must settle back to 1 after any reconnect.
- `⏱ voice-to-voice p50/p95` — if p95 approaches 4000ms, drop
  `POLLY_REASONING_EFFORT` to `medium`.
- `wake: listening (on-device)` — should reappear roughly once a minute with no
  missed wakes around it.
- `media: mic released after clip` — should follow every unmuted clip.

## Verification

- **Proxy**: `curl -i` the preview URL and check `x-glutt-polly-reasoning`. If it reads
  `default`, the reasoning fallback fired and the field was rejected.
- **Client**: build and test via XcodeBuildMCP (`build_run_sim`, `test_sim`). The simulator
  cannot validate any of the acoustic work — that needs a device.
- **Device**: one real cook per toggle state. Count phantom `speech_started` during her
  utterances, mid-sentence cut-offs, and missed interruptions. `…` menu → Copy debug log.
- **Leak check**: the transport instance counter must return to zero after a reconnect.

## Notes for whoever picks this up

- `PollyV2SpikeView` is launch-arg gated and never runs in a shipping cook. Anything "fixed"
  there is not fixed.
- The proxy stamps `x-glutt-proxy-version`; check it before assuming the repo matches what is
  live on Vercel.
- `gpt-live-transcribe` in a `type: "realtime"` session is UNCONFIRMED — the schema accepts it,
  the model page lists only `transcription_sessions`. Test before shipping.
- Transcription is a **sidecar**. OpenAI: it "should be treated as guidance of input audio
  content rather than precisely what the model heard." Tuning keywords improves the gate's input,
  not Polly's hearing.
- GPT-Live-1 (natively full duplex) is ChatGPT-only as of 2026-07-30, with no API model ID and no
  date. Do not plan around it, but the rewrite deliberately leaves room to adopt it.
