# Polly v2 — voice system rebuild (2026-07-23)

Rebuild of the Polly live-call voice stack. Decisions below were locked in a grilling session
with Omar on 2026-07-23; supporting research (all primary-source, arithmetic shown):
`docs/voice-stack-research-2026-07-23.md` and `docs/webrtc-transport-vetting-2026-07-23.md`.

## Why (diagnosis)

Every documented v1 failure was client-side or config, not the model:

- Speakerphone echo → false barge-ins → a stack of band-aids that *created* the UX bugs:
  `bargeInRMSFloor 0.06` drops quiet real speech ("doesn't listen"), `semantic_vad` at
  `eagerness: low` adds seconds before replies ("takes forever"), 2.5s greeting mic-hold +
  1.0s onset gate, 3s follow-up window ("stopped listening"), one silent reconnect then dead
  ("doesn't answer").
- Raw WebSocket transport means we own AEC/jitter/engine-restart resilience in a custom
  `AVAudioEngine` graph that iOS silently stops on route changes.
- The 3-day-old wake gate misses words (SFSpeech hack) — a missed wake reads as deafness.
- Model string was two releases stale (`gpt-realtime-2`; 2.1 shipped 2026-07-06 with ≥25% p95
  latency cut. Bumped server-side in Phase 0 — reaches shipped clients via `token.model`).

## Locked decisions

1. **North star: reliability.** Silence is the unforgivable failure. Speed second,
   naturalness third, cost a ceiling not a goal (quality-first at current scale).
2. **Target environment:** iPhone on counter + loudspeaker, hands messy. AirPods/locked-screen
   are not requirements. **Camera (REVISED 2026-07-24):** the "Show Polly" shutter and the
   `request_camera_frame` tool STAY (they work over the data channel on v2 and cost nothing to
   keep — Omar re-decided when the deletion consequence was spelled out); only **watch mode**
   (10s auto-frames + eye button + WatchModeScheduler) is deleted.
3. **Interaction: hybrid window.** Wake word ("Polly" *or* "Hey Polly") opens a conversation
   that stays open through the exchange; closes after ~10s of true silence or dismissal;
   fully open while Polly is guiding a step. The 3s follow-up window is gone.
4. **Brain: OpenAI `gpt-realtime-2.1`, client-direct over OpenAI's first-party WebRTC**
   (`POST /v1/realtime/calls` SDP exchange; events on the data channel; audio I/O owned by
   WebRTC's stack — its AEC replaces the RMS-floor/mic-hold band-aids). Gemini Live rejected
   for now: preview-only models, ~10-min reconnect segments, WebSocket-only (keeps our audio
   scar tissue), Live tools docs unpublished — all clash with reliability-first.
   `gpt-realtime-2.1-mini` stays one server-side string away as a cost lever.
5. **Control plane server-side:** persona/voice/model/turn_detection pinned at token mint via
   `client_secrets` so VAD + persona tuning never needs an App Store release.
6. **Never-silent contract (all four):**
   - Response watchdog: if her audio hasn't started ~4s after end-of-turn → forced spoken
     repair ("sorry, say that again?").
   - Verbal ack before slow tool work ("one sec…").
   - Reconnect ×2 with transcript replay + audible chime (v1 did one silent attempt).
   - Canned offline audio in Polly's real voice, bundled as assets, for zero-network states
     (token mint failed / reconnects exhausted / airplane mode). No dead-air paths.
   - Per-device monthly minute cap in the proxy as an abuse guard.
7. **Wake word: Apple on-device, rebuilt.** Picovoice is B2B-only (~$6k/yr), openWakeWord has
   no iOS runtime + NC-licensed models. On-device SFSpeech has NO 1-minute task limit → kill
   restart churn; `SpeechAnalyzer` availability-gated upgrade on iOS 26+; matcher accepts both
   wake phrases.
8. **Voice: bake-off** — same 4 lines (greeting / step / repair / wrap-up) in `marin`, `cedar`,
   + candidates, played on the actual kitchen speaker; pick by ear. Canned failure lines are
   regenerated in the winning voice.
9. **Turn detection:** re-tuned once real AEC exists — start `semantic_vad` eagerness `auto`,
   evaluate `high` during soak; consider `server_vad` + `idle_timeout_ms` for "next step?"
   nudges (mutually exclusive with semantic_vad — decide on device, it's a server-side knob).
10. **Cut-over:** v2 built behind the existing seams (`RealtimeTransporting`,
    controller closures) on branch `polly-v2-voice` → Omar's real-kitchen device soak +
    short TestFlight → merge deletes the WS engine + camera stack. Git history is the archive.
11. **Scope:** in-cook calls only. Engine stays reusable for a future quick-ask Polly.
    Survivors: all 13 tools (incl. `request_camera_frame`), the "Show Polly" shutter,
    `PollyPromptBuilder`, `CookPlanCompiler` (moved to background precompile → instant
    greeting), memory store, redesigned call UI, `PollyDebugLog` loop.

## Cost basis (research doc has the arithmetic)

40-min cook, ~8 min dialogue: **~$0.50** on 2.1 (mini ~$0.15; Gemini would be ~$0.12).
Token-billed + wake-gated idle ≈ $0 while quiet; per-minute platforms (Vapi/Retell/11L,
LiveKit agent minutes) bill the whole cook — that's why they lost. Cached audio input is
98.75% off with a stable prefix: instructions + tools must never mutate mid-session, and
`retention_ratio` truncation (v1 used 0.8) busts the cache — revisit before enabling.

## Phases

- **Phase 0 — instant relief (shipped with this doc):** proxy default model →
  `gpt-realtime-2.1` (+ version header bump `polly-2026-07-23-1`), `PollyConfig` fallback
  aligned. Verify: `x-glutt-proxy-version` + `model` in mint response. If Vercel env
  `POLLY_REALTIME_MODEL` overrides, flip it in the dashboard.
- **Phase 1 — WebRTC transport spike:** `RealtimeWebRTCTransport: RealtimeTransporting`
  (SDP offer/answer, data-channel events through the existing `RealtimeEvent` codec, audio
  by WebRTC). Binary + wake-word buffer strategy per the vetting doc. Exit criteria: greeting
  audible on device, speakerphone echo test clean, wake listener receives PCM while dormant.
- **Phase 2 — v2 engine core:** hybrid-window state machine; never-silent contract
  (watchdog, acks, reconnect ×2 + replay + chime, canned audio); delete obsolete band-aids.
- **Phase 3 — wake listener rebuild:** SpeechAnalyzer (iOS 26+) / SFSpeech floor, no restart
  churn, both phrases, unit-tested matcher.
- **Phase 4 — server hardening:** pin turn_detection/voice at mint; per-device monthly cap
  (`x-device-id`); rotate the committed `GLUTT_PROXY_CLIENT_KEY` out of `Secrets.swift`.
- **Phase 5 — final integration:** delete watch mode only (shutter + camera tool stay),
  background cook-plan precompile, dead-code sweep, tests green.
- **Phase 6 — bake-off + soak:** voice pick, VAD eagerness tuning via server config, ≥5 real
  cooks across ≥2 recipes (quiet + noisy), TestFlight, merge.

## Status 2026-07-24 (~6am) + Phase 6 runbook

Phases 0–5 SHIPPED. Engine device-validated across two in-app cooks ("pretty impressed");
server hardening live on prod (dual-key, mint-pinned audio plane, dormant device cap).
Pending outside the repo: friend adds `GLUTT_PROXY_CLIENT_KEY_NEXT` (value is in the local
`Secrets.local.plist` comment) to the glutt-sable Vercel project + redeploys → then swap the
local plist to the NEXT key.

**Phase 6 runbook (mechanical):**
1. **Voice bake-off:** run the spike (`-pollyV2Spike`), tap voice chips (marin/cedar/coral/…)
   — each reads the same 4 lines in a fresh session. Winner → `POLLY_VOICE` env on the
   sable project (friend/dashboard) or keep marin (code default).
2. **Eagerness walk-up:** during real cooks, step `POLLY_VAD_EAGERNESS` low → auto → high
   (env flip + redeploy; no app builds). Stop at the last value with zero false cut-ins.
3. **Canned offline audio:** generate the failure lines in the WINNING voice (TTS), bundle as
   assets, play on token-mint failure / reconnects-exhausted (the last never-silent gap).
4. **Soak:** ≥5 real cooks across ≥2 recipes, quiet + noisy (fan/tap/music). Watch
   PollyDebugLog for: phantom interruptions (expect zero), watchdog strikes, reconnects.
5. **Merge-time deletions (single commit):** `PollyAudioEngine.swift` (+PCM helpers if
   unreferenced), `RealtimeWebSocketTransport`/`URLSessionWebSocket` + WS-only codec paths
   (appendAudio/outputAudioDelta/truncateItem cases + their tests), `PollyV2SpikeView` +
   `-pollyV2Spike` scheme arg + RootView hook, dead transport probes (PollyCaptureHook gates,
   PollyRenderMonitor, PollyLocalTrackRenderer — KEEP PollyEngineTapObserver, it IS the wake
   feed), PollyConfig leftovers (`onsetCaptureGateSeconds`, `bargeInRMSFloor`), controller's
   legacy `audio.isMuted` shadow writes + tests that pin them. Re-run one device cook after.
6. **TestFlight** → merge to main → App Store build carries the NEXT proxy key; after
   adoption, promote NEXT → primary on Vercel and retire the old (git-leaked) key.

**Post-soak follow-up (deliberately deferred):** SpeechAnalyzer wake path (iOS 26+) —
availability-gated inside `WakeWordListener.beginTask()`, feed `AnalyzerInput(buffer:)` from
the same tap, volatile results → `WakeWordMatcher`, HARD fallback to SFSpeech on any setup
failure. Deferred because it can't be validated on the sim and would replace the working wake
path on the primary test device untested.

## Risks / open spike questions

- **No official OpenAI iOS WebRTC SDK** — community lib vs hand-rolled thin SDP layer;
  vetting doc decides. Isolated behind `RealtimeTransporting` either way.
- **Wake-word mic access under WebRTC capture:** VPIO exclusivity may block a parallel
  `AVAudioEngine` tap; fallback is capture-side processing hooks in the WebRTC stack.
  Phase 1 exit criterion; worst case the wake listener runs only while the WebRTC track is
  muted-but-capturing (track-level gate, same UX).
- **60-min session wall (no resumption):** keep v1's 47-min wrap-up / 52-min stop; the
  reconnect-with-replay path doubles as the >60-min escape hatch if ever needed.
- **`marin` may lose the bake-off** → regenerate canned lines, update `POLLY_VOICE`.
- **App Store:** next submission carries the same mic strings; no new entitlements needed
  (background audio already declared; camera strings can be REMOVED with the camera stack).
