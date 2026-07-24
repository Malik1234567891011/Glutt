# Voice stack research for Polly rebuild — 2026-07-23

Primary-source research for rebuilding Polly (hands-free AI chef). Current stack: OpenAI Realtime,
model `gpt-realtime-2`, voice `marin`, raw WebSocket from Swift, ephemeral client secrets minted by
`vercel-ai-proxy/api/polly/session.js` via `POST /v1/realtime/client_secrets`, 13 client-side tools.
Environment: iPhone on counter, loudspeaker, barge-in required. All claims cite vendor docs/repos;
anything I could not confirm from a primary source is marked **[unconfirmed]**.

## Summary comparison

Scenario used everywhere below: **one 40-min cook, ~8 min active dialogue** (assume 4 min user
speech, 4 min Polly speech, ~24 exchanges, mic client-gated by the on-device "say Polly" gate during
the other 32 min, session/connection kept alive).

| Stack | Est. v2v latency | $/min active | 40-min cook est. | Session cap | iOS effort | Brain lives | Images mid-session | Lock-in |
|---|---|---|---|---|---|---|---|---|
| OpenAI Realtime 2.1, WebRTC direct | ~0.5–0.8 s (no official ms figure; 2.1 claims ≥25% p95 cut) | ~$0.05–0.08 | **~$0.50** (mini: ~$0.15) | 60 min hard | Medium (no official Swift SDK; community lib or hand-rolled WebRTC) | Our Vercel (pinned via client_secrets) | Yes ($5/1M img tok) | Low-med |
| OpenAI Realtime via LiveKit | ~0.6–0.9 s (extra hop) | ~$0.06–0.09 | **~$0.94** ($0.40 of it is idle agent minutes) | 60 min (model) | Med client (official Swift SDK) + high backend (agent svc) | Our agent code | Yes | Med (infra) |
| Gemini Live direct (Firebase AI Logic) | not published; community ~0.6–1 s | ~$0.012 | **~$0.12** | 15 min default → unlimited w/ compression; ~10-min conn segments + resumption | Low-med (official Swift path) | Our backend (ephemeral token `liveConnectConstraints`) | Yes (JPEG ≤1 FPS) | Low-med |
| Gemini Live via LiveKit | ~0.7–1 s | ~$0.023 | **~$0.54** | as above | Med + high backend | Our agent code | Yes | Med |
| Pipeline (Deepgram+LLM+Cartesia) via LiveKit Agents | ~0.7–1.2 s (STT ~0.3 s + LLM TTFT + TTS <0.09 s) | ~$0.033 | **~$0.61** | none doc'd | High (agent + 3 vendors + client-tool RPC plumbing) | Our agent code | Via LLM (extra work) | Med; components swappable |
| Vapi | not published | ~$0.10–0.13 | **~$2.15+** connected 40 min; ~$0.55 if reconnect per exchange | [unconfirmed] | Low (official iOS SDK, Daily-based) | Vapi dashboard/API | [unconfirmed] | High |
| Retell | not published | ~$0.08–0.12 | **~$3.00+** connected 40 min | [unconfirmed] | Very high — **no iOS SDK** | Retell dashboard | No | High |
| ElevenLabs Agents | not published (TTS component ~75 ms) | $0.08 + LLM pass-through | **~$3.30+** connected 40 min; ~$0.75 if only 8 min connected | [unconfirmed] | Low (official Swift SDK, client tools w/ results) | 11L dashboard (overridable) | [unconfirmed] | High |

### Cost arithmetic (assumptions shown once, reused everywhere)

- OpenAI's own audio token rates: input **1 tok/100 ms** (600 tok/min), output **1 tok/50 ms**
  (1,200 tok/min) → gpt-realtime-2.1 = $0.0192/min in, $0.0768/min out; 2.1-mini = $0.006/$0.024.
- Google's own per-minute figures (pricing page): audio in **$0.005/min** ($3/1M tok at 32 tok/s),
  audio out **$0.018/min** ($12/1M; implies 25 tok/s — derived, Google publishes only the $/min).
- OpenAI cook: in 2,400 tok×$32/1M=$0.077 + out 4,800×$64/1M=$0.307 + context re-reads (~4k-tok
  system+13 tools, ~24 responses, ~90% cache-hit at $0.40/1M cached text/audio) ≈ $0.09–0.13 →
  **≈$0.50**. Mini: $0.024+$0.096+~$0.02 → **≈$0.15**.
- Gemini cook (mic gated, ~8 min streamed): 8×$0.005=$0.04 in + 4×$0.018=$0.072 out + text ≈
  **$0.12**. If mic streams all 40 min: 40×$0.005+$0.072 ≈ **$0.27** — idle audio costs ~$0.15.
  **[unconfirmed]** whether silence sent to Gemini is tokenized/billed; assume yes, keep the gate.
- OpenAI idle: tokens bill per committed audio/response, not wall-clock, so an idle-but-open WebRTC
  session costs $0 — but server VAD can commit kitchen noise; tune `threshold`/gate the mic.
- LiveKit adder: agent session $0.01/min × 40 min = $0.40 (billed while connected, idle or not) +
  participant WebRTC ~$0.0005/min ≈ $0.02.
- Vapi: $0.05/min platform × 40 + provider costs at cost (≈$0.15–0.50 from above). Retell:
  ($0.055 infra + $0.015 TTS + $0.006–0.045 LLM)/min × 40. 11L: $0.08/min × 40 + LLM pass-through.
- Per-connected-minute platforms are priced for phone calls; a 40-min mostly-idle kitchen session is
  the worst case for them and the best case for token-billed APIs.

---

## 1. OpenAI Realtime API

- **Models (July 2026):** `gpt-realtime-2` shipped May 7, 2026 (announced as GPT-5-class reasoning
  for voice, 128k context — up from 32k, 5 reasoning-effort levels, parallel tool calls with spoken
  preambles). **Superseded July 6, 2026 by `gpt-realtime-2.1` and `gpt-realtime-2.1-mini`** (claimed
  ≥25% p95 latency reduction via caching; improved alphanumerics, noise handling, interruption
  behavior). Companions: `gpt-realtime-translate` ($0.034/min), `gpt-realtime-whisper` ($0.017/min).
  The pricing page now lists only the 2.1 family; `gpt-realtime-2` model page still live at the same
  price. Older `gpt-realtime`/`gpt-realtime-mini` no longer on the pricing page.
- **Pricing per 1M tokens — gpt-realtime-2 and 2.1 (identical):** text $4 in / $0.40 cached /
  $24 out; audio **$32 in / $0.40 cached / $64 out**; image $5 in / $0.50 cached.
  **2.1-mini:** text $0.60/$0.06/$2.40; audio **$10 in / $0.30 cached / $20 out**; image $0.80.
  Cached audio input is a 98.75% discount — long multi-turn convos are much cheaper than naive math.
- **Tokens per minute (OpenAI's own figures):** input audio 1 tok/100 ms; output audio 1 tok/50 ms
  → $0.0192/min in, $0.0768/min out (2.1). Full conversation is re-sent per Response; cost levers:
  `token_limits.post_instructions`, `retention_ratio` (<1.0 busts cache — trade-off), item deletion.
- **Session cap:** "The maximum duration of a Realtime session is 60 minutes" (realtime-conversations
  guide; dev-blog notes it was raised from 30). No native resumption — a >60-min cook needs a
  client-side new-session-with-context-replay dance.
- **WebRTC on iOS:** SDP exchange via `POST https://api.openai.com/v1/realtime/calls` with
  `Authorization: Bearer <ephemeral key>`; events over the data channel. Docs say WebRTC is for
  "browser and **mobile** clients" but ship **no official iOS/Swift SDK or sample** — community
  options: `m1guelpf/swift-realtime-openai` (434★, WebRTC+WebSocket transports),
  `PallavAg/VoiceModeWebRTCSwift` demo, plus unofficial `stasel/WebRTC` framework binaries.
- **turn_detection:** `server_vad` (default; `threshold` 0–1, `prefix_padding_ms`,
  `silence_duration_ms`, `create_response`, `interrupt_response`) and `semantic_vad` (`eagerness`:
  `auto`=`medium`, `low`, `high`). **`idle_timeout_ms` is server_vad-only**: fires after response
  audio finishes + timeout, emits `input_audio_buffer.timeout_triggered`, commits empty audio and
  prompts the model — useful for "are you still there / next step?" nudges mid-cook.
- **Server-side pinning:** yes — `POST /v1/realtime/client_secrets` accepts the full session object
  (`instructions`, `model`, `tools`, `audio.output.voice` incl. `marin`/`cedar`,
  `audio.input.turn_detection`, `max_output_tokens`), which is exactly our current Vercel setup.
  TTL field `expires_at` exists; min/max TTL **[unconfirmed]** from the docs I could fetch.

Sources: https://developers.openai.com/api/docs/models/gpt-realtime-2 ·
https://developers.openai.com/api/docs/models/gpt-realtime-2.1 ·
https://developers.openai.com/api/docs/pricing ·
https://developers.openai.com/api/docs/guides/realtime ·
https://developers.openai.com/api/docs/guides/realtime-webrtc ·
https://developers.openai.com/api/docs/guides/realtime-vad ·
https://developers.openai.com/api/docs/guides/realtime-costs ·
https://developers.openai.com/api/docs/guides/realtime-conversations ·
https://developers.openai.com/blog/realtime-api ·
https://community.openai.com/t/new-realtime-models-on-the-api-gpt-realtime-2-1-and-gpt-realtime-2-1-mini/1385896 ·
https://x.com/OpenAI/status/2052438194625593804 ·
https://github.com/m1guelpf/swift-realtime-openai

## 2. Google Gemini Live API

- **Models:** `gemini-2.5-flash-native-audio-preview-12-2025` (native audio, "higher quality audio
  outputs with better pacing, voice naturalness") and `gemini-3.1-flash-live-preview` ("audio-to-audio
  model optimized for real-time dialogue"). Both **preview**, both with a free tier. Vertex twins:
  `gemini-live-2.5-flash-native-audio`.
- **Pricing (3.1-flash-live-preview, per 1M tok):** text $0.75 in / $4.50 out; audio **$3.00 in
  ("or $0.005/minute") / $12.00 out ("or $0.018/minute")**; image/video in $1.00 ($0.002/min).
  2.5-native-audio: text $0.50/$2.00, audio $3.00/$12.00. Google's token rates: audio input
  **32 tok/s**; output $/min implies 25 tok/s (Google publishes the $/min directly).
  → **~4–13x cheaper than OpenAI 2.1 on audio** ($0.005 vs $0.019 in; $0.018 vs $0.077 out).
- **Session limits:** audio-only **15 min**, audio+video **2 min** — but `contextWindowCompression`
  "extend[s] sessions to an unlimited amount of time". The underlying **connection lasts ~10 min**;
  server sends `GoAway` (with `timeLeft`) then you reconnect with a session-resumption handle
  (`SessionResumptionUpdate` tokens, valid **2 h** after last termination). More moving parts than
  OpenAI, but no hard 60-min wall.
- **Ephemeral tokens:** Live-API-only; `newSessionExpireTime` default **1 min**, `expireTime` default
  **30 min**, `uses` default 1; **`liveConnectConstraints` locks model/config/system instructions
  server-side** — direct equivalent of our client_secrets pinning.
- **VAD/barge-in:** `automaticActivityDetection` (`disabled`, `startOfSpeechSensitivity`,
  `endOfSpeechSensitivity`, `prefixPaddingMs`, `silenceDurationMs`); interruption cancels/discards
  generation (`interrupted` signal); manual `activityStart`/`activityEnd` mode available. 2.5-only
  extras: `proactive_audio` (model may decline to answer irrelevant audio — interesting for a noisy
  kitchen) and `enable_affective_dialog`. No semantic-eagerness knob like OpenAI's.
- **Function calling:** supported in Live (plus Google Search grounding).
- **iOS/Swift story:** **Firebase AI Logic officially supports the Live API from Swift** (bidirectional
  streaming; quickstart app). Caveat: Firebase's page says tools docs for Live are "coming soon" —
  our 13 tools may hit rough SDK edges; raw WebSocket from Swift (like today's OpenAI WS stack) is
  the fallback. Audio: 16-bit PCM 16 kHz in / 24 kHz out.

Sources: https://ai.google.dev/gemini-api/docs/pricing · https://ai.google.dev/gemini-api/docs/live ·
https://ai.google.dev/gemini-api/docs/live-session · https://ai.google.dev/gemini-api/docs/live-guide ·
https://ai.google.dev/gemini-api/docs/ephemeral-tokens · https://ai.google.dev/gemini-api/docs/tokens ·
https://firebase.google.com/docs/ai-logic/live-api

## 3. Pipeline components (STT → LLM → TTS)

- **Deepgram:** streaming Nova-3 **$0.0048/min** (multilingual $0.0058); newer **Flux**
  ("conversational speech recognition" with built-in end-of-turn detection, `EagerEndOfTurn`,
  `eager_eot_threshold` 0.3–0.9) **$0.0065/min** English. Latency: Nova-3/Flux "sub-300 ms" typical;
  Flux end-of-turn **~260 ms p50**, claims 200–600 ms agent-latency reduction vs STT+VAD. Bills on
  audio streamed. TTS Aura-2 $0.030/1k chars. Deepgram Voice Agent API (their own bundle):
  $0.075/min standard. $200 free credit.
- **AssemblyAI:** Universal-Streaming **$0.15/hr = $0.0025/min**, but bills **WebSocket-open time,
  idle included** — a trap for a 40-min mostly-idle session; close the socket when gated. Claims
  immutable transcripts in ~300 ms (their comparison: 307 ms vs Deepgram 516 ms median word emission
  — vendor benchmark). `u3-rt-pro` tier $0.45/hr. $50 free credit.
- **Cartesia:** current model **Sonic-3.5** (stable May 4, 2026, "sub-90ms latency", 42 languages);
  older sonic-turbo claimed 40 ms TTFA. Credit-priced: Pro $5/mo ≈ 133 TTS min (≈$0.038/min);
  Startup $49 = 1.25M credits (≈$0.029/min effective at the same credits/min rate — derived from
  their own calculator, not a posted per-minute price).
- **ElevenLabs TTS:** Flash/Turbo **$0.05/1k chars, "~75ms" model latency**; Multilingual v2/v3
  $0.10/1k chars, ~250–300 ms. At a spoken ~900 chars/min that's ≈$0.045/min (Flash).
- **Realistic end-to-end:** no pipeline vendor publishes a guaranteed v2v number. Component sums
  (vendor-claimed): ~300 ms STT/EOT + LLM TTFT (~200–400 ms for flash-class models) + ~90 ms TTS
  first-audio + network/playout → **~0.7–1.2 s** well-tuned. S2S models (OpenAI/Gemini) remove two
  hops and are the latency floor.

Sources: https://deepgram.com/pricing · https://developers.deepgram.com/docs/flux/flux-nova-3-comparison ·
https://deepgram.com/learn/introducing-flux-conversational-speech-recognition ·
https://www.assemblyai.com/pricing · https://www.assemblyai.com/blog/introducing-universal-streaming ·
https://docs.cartesia.ai/build-with-cartesia/tts-models · https://cartesia.ai/pricing ·
https://elevenlabs.io/pricing/api

## 4. LiveKit

- **Swift SDK:** `livekit/client-sdk-swift`, 432★, latest **v2.15.2 (mid-July 2026)**, roughly
  monthly releases (2.14.0 → 2.15.2 May–July 2026; a 2.15.x release fixes Xcode 27 beta builds),
  6 open issues. Mature, SPM-installable.
- **Cloud pricing:** Build free (1,000 agent min, 5,000 participant min, $2.50 inference credits);
  Ship $50/mo (5,000 agent min, 150k participant min); Scale $500/mo (50k agent min, 1.5M
  participant min). Overages: **agent sessions $0.01/min**, participant minutes $0.0005 (Ship) /
  $0.0004 (Scale)/min. Optional LiveKit Inference: e.g. "GPT Realtime" $0.0676/min, STT
  $0.0025–0.0117/min, TTS up to $0.18/min.
- **Agent hosting:** deploying agents on LiveKit Cloud is live and self-serve ("available today";
  launch blog): **$0.01/min while the agent is actively serving a user**, includes global hosting,
  unlimited data transfer, observability; warm instances on paid plans; one-command rollback. The
  blog doesn't label it "GA" explicitly — treat as production-marketed. Framework: Agents for
  **Python and Node.js** (no Swift agents).
- **S2S plugins:** OpenAI Realtime (Py+Node, `voice="marin"` example in their docs), Gemini Live
  (Py+Node), Azure OpenAI, Amazon Nova Sonic, xAI Grok Voice, Ultravox, Phonic, NVIDIA PersonaPlex.
  Architecture: your agent process holds the model connection; phone ↔ LiveKit room (WebRTC) ↔ agent
  ↔ model — i.e., **the S2S model is proxied through your agent**, adding a hop but centralizing the
  brain server-side.
- **Turn detector:** neural audio-native EOT model (semantic + intonation/pitch/rhythm), 14
  languages; **v1** served on LiveKit Inference (free for Cloud agents), **v1-mini** runs locally on
  CPU, free everywhere; requires VAD `min_silence_duration ≥ 0.25 s`. (Deprecated text version:
  Qwen2.5-0.5B, ~50–160 ms, 396 MB.)
- **Noise cancellation:** Krisp (NC + BVC) and ai-coustics via Cloud. **Swift gets standard Krisp NC
  (`LiveKitKrispNoiseFilter`) but BVC — background-voice cancellation — is Web-only.** Inbound-side
  filtering on the agent works regardless of client platform.

Sources: https://github.com/livekit/client-sdk-swift ·
https://github.com/livekit/client-sdk-swift/releases · https://livekit.com/pricing ·
https://livekit.com/blog/deploy-and-scale-agents-on-livekit-cloud/ ·
https://docs.livekit.io/agents/models/realtime/ · https://docs.livekit.io/agents/models/realtime/openai/ ·
https://docs.livekit.io/agents/build/turns/turn-detector/ ·
https://docs.livekit.io/home/cloud/noise-cancellation/

## 5. Managed voice-agent platforms

- **Vapi:** platform fee **$0.05/min** + provider costs passed through at cost ("$0 if you bring
  your own API key"); Build plan usage-based, 10 concurrency lines included ($10/line beyond);
  HIPAA +$2k/mo. Official iOS SDK `VapiAI/client-sdk-ios` (33★, iOS 13+, **Daily.co WebRTC** under
  the hood). Client tools exist (`clientMessages: ['tool-calls']`) **but per their docs client-only
  tools "do not send results back to the model"** — for tools whose output the model must consume
  (most of Polly's 13), Vapi wants a server URL. Custom persona/prompt: dashboard/API-defined;
  BYO-model supported (incl. your own LLM endpoint). Pros: cheap client integration, at-cost models.
  Cons: per-connected-minute fee brutal for idle-heavy sessions; client-tool round-trip limitation;
  prompt lives in Vapi.
- **Retell:** component pricing — voice engine **$0.055/min** + TTS ($0.015/min platform voices,
  $0.04 ElevenLabs) + LLM ($0.003/min GPT-5-nano → $0.16/min GPT-5.5; Claude 4.6 Sonnet $0.08/min);
  US telephony $0.015/min; $10 free credit; no platform subscription. SDKs: **server SDKs (Node,
  Python) + web JS client SDK only — no official iOS/Swift SDK** (org repos confirm). Effectively
  telephony/web-first; disqualifying for a native kitchen app without building our own client.
- **ElevenLabs Agents:** plan-bundled minutes (Free 15, Starter 75, Creator 275, Pro 1,238, Scale
  3,738, Business 12,375/mo) then **$0.08/min** (burst-over-concurrency $0.16/min); **LLM cost is
  billed separately/passed through**; STT+TTS+orchestration are what the per-minute buys. Swift SDK
  `elevenlabs/elevenlabs-swift-sdk`: 115★, v3.2.x (releases through June 2026), iOS 13+, **built on
  LiveKit WebRTC**, supports **Client Tools with `sendToolResult()`** (results DO return to the
  model) + MCP. Persona/prompt configured in their dashboard (per-session overrides exist);
  BYO-LLM supported (their model list + custom LLM endpoint). Pros: best-in-class voices, real
  client tools, easy Swift. Cons: $0.08/min meter runs while connected, LLM extra, vendor lock.

Sources: https://vapi.ai/pricing · https://docs.vapi.ai/tools/client-side-websdk ·
https://github.com/VapiAI/client-sdk-ios · https://www.retellai.com/pricing ·
https://docs.retellai.com/get-started/sdk · https://github.com/RetellAI ·
https://elevenlabs.io/pricing/agents · https://elevenlabs.io/docs/agents-platform/customization/llm ·
https://github.com/elevenlabs/elevenlabs-swift-sdk

## 6. Wake word ("Hey Polly")

- **Picovoice Porcupine:** 4.9k★; iOS SDK via CocoaPods `Porcupine-iOS` (+ Swift APIs
  `PorcupineManager`/`Porcupine`); custom keywords trained in Picovoice Console → `.ppn` file;
  AccessKey required at init. Accuracy claim (their public benchmark repo, miss-rate at 1 false
  alarm/10 h, noisy 10 dB SNR): "11.0x more accurate and 6.5x faster" than PocketSphinx/Snowboy.
  **Licensing changed:** FAQ now says Picovoice is B2B with "no dedicated free or paid plans for
  personal or non-commercial use"; the old 2021 3-user free tier is gone. Current: **Free Trial**
  (evaluation, no card) → **Foundation plan** (self-serve; metered in monthly active users —
  "a unique device, app, or browser instance that initializes the engine within a 30-day period").
  Pricing page/checkout are JS-rendered and unfetchable; third-party captures of the checkout list
  **$6,000/yr incl. 100 Porcupine MAU/mo, Enterprise from $30k/yr [unconfirmed — verify in Console
  before deciding]**. At Glutt's scale that's likely a non-starter vs. free options.
- **openWakeWord:** 2.6k★, Apache-2.0 code but **bundled pre-trained models are CC BY-NC-SA
  (non-commercial)**; custom models trainable in a Colab in <1 h on synthetic data; runtimes
  ONNX/tflite — **no official iOS support**; you'd port inference yourself.
- **Apple on-device (current approach):** SFSpeechRecognizer stops **server-based** tasks at one
  minute ("the framework stops speech recognition tasks that last longer than one minute"); Apple
  forum guidance: **no duration limit for on-device recognition** (since WWDC19), so the restart
  loop is only mandatory when the server path is used — keep `requiresOnDeviceRecognition = true`.
  iOS 26 adds **SpeechAnalyzer/SpeechTranscriber + SpeechDetector**: on-device, long-form,
  AsyncSequence-based, reported (WWDC25 coverage) ~2x faster than Whisper Large v3 Turbo. Since
  Glutt targets iOS 17+, SFSpeech stays the floor, SpeechAnalyzer the upgrade path. Cost: $0.

Sources: https://github.com/Picovoice/porcupine · https://github.com/Picovoice/wake-word-benchmark ·
https://picovoice.ai/docs/faq/general/ · https://picovoice.ai/blog/introducing-picovoices-free-tier/ ·
https://github.com/dscripka/openWakeWord ·
https://developer.apple.com/documentation/speech/sfspeechrecognizer ·
https://developer.apple.com/forums/thread/131940 · https://developer.apple.com/documentation/speech/

## Facts that surprised me / contradict our assumptions

1. **`gpt-realtime-2` is two releases behind.** 2.1/2.1-mini shipped July 6, 2026 (same price,
   ≥25% p95 latency cut claimed). One-line change in `PollyConfig.swift` + `session.js` — do it
   regardless of the rebuild decision. Also **2.1-mini at $10/$20 per 1M audio** makes an
   OpenAI-cheap tier (~$0.15/cook) we haven't evaluated.
2. **Gemini Live is ~4x cheaper on audio-in and ~4x on audio-out than gpt-realtime-2.1** ($0.005 vs
   $0.019, $0.018 vs $0.077/min), has an official Swift path (Firebase AI Logic), ephemeral tokens
   with server-side-pinned instructions, session resumption — but both Live models are still
   **preview**, and Firebase's Live tools docs are "coming soon" (risk for our 13 tools).
3. **OpenAI's 60-min hard session cap** is real and resumption-free; a long cook + chat could hit
   it. Gemini's default is 15 min but extends to **unlimited** with context compression (with
   ~10-min reconnect ceremonies).
4. **Idle time, not talk time, dominates cost on per-minute platforms.** The same 40-min cook is
   ~$0.12–0.50 on token-billed direct APIs vs $2–3.30+ on Vapi/Retell/ElevenLabs and +$0.40 on any
   LiveKit-agent topology (agent minutes accrue while idle). Our on-device wake-word gate is worth
   real money; it also matters that AssemblyAI bills WebSocket-open time (idle included) while
   Deepgram bills audio streamed.
5. **Vapi's client-side tools don't return results to the model** per their own docs — Polly's
   13 tools are mostly read-modify-respond, so Vapi would force a server round-trip per tool.
   ElevenLabs' Swift SDK does support result-returning client tools; Retell has **no iOS SDK at all**.
6. **Picovoice killed the hobby tier.** Their FAQ says B2B-only, no personal plans; captured
   checkout pricing suggests ~$6k/yr. openWakeWord's pre-trained models are non-commercial-licensed
   and iOS-unsupported. Our free Apple-based "say Polly" gate (no 1-min limit on-device, and
   SpeechAnalyzer coming for iOS 26) remains the right call.
7. **Cached audio input is $0.40/1M (98.75% off)** on OpenAI — with a stable prefix (instructions +
   13 tools never mutating mid-session), long conversations are far cheaper than the sticker math;
   avoid `retention_ratio` truncation that busts the cache.
8. **ElevenLabs' Swift SDK is LiveKit WebRTC underneath**, and LiveKit's Krisp **BVC** (background
   voice removal — TV, family chatter in a kitchen) is **web-only**; Swift gets standard NC only.
9. **OpenAI still has no official iOS/WebRTC SDK** — moving off our raw WebSocket to WebRTC means a
   community lib (m1guelpf, 434★) or hand-rolled SDP against `/v1/realtime/calls` with unofficial
   WebRTC builds. Meanwhile `idle_timeout_ms` (server_vad-only) could power "next step?" nudges —
   but it's incompatible with semantic_vad if we adopt that for barge-in feel.
