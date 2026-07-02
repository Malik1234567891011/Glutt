# Polly — Live AI Chef (v1 design)

**Date:** 2026-07-02 · **Status:** Approved by Omar · **Branch:** `feat/polly-live-chef` (stacked on `feat/plates-recipe-feed`, PR #3)

## What this is

Polly turns Glutt from a recipe app with a cook mode into a live AI chef. The user opens a saved
recipe, taps **Cook with Polly**, and gets a realtime voice + camera cooking session: Polly knows
the exact recipe, the pantry, diet rules, skill level, and past cooks; greets the user, confirms
the dish, checks missing ingredients, suggests substitutions, then runs the cook step by step —
tracking steps, timers, and substitutions, answering interruptions with dish-specific context, and
using camera frames to judge doneness, browning, cuts, and texture. Every cook teaches Polly the
user's kitchen (stove runs hot, owns cast iron, chops slowly) for the next one.

The wedge is not "talk to your recipe" — **Polly runs the cook with you.**

## v1 decisions (locked with Omar)

| Decision | Choice |
|---|---|
| Realtime provider | **OpenAI Realtime** (`gpt-realtime`, speech-to-speech) — whole existing stack is OpenAI |
| Transport | **Direct WebSocket** (`URLSessionWebSocketTask`) with ephemeral client secrets; isolated behind a protocol so WebRTC/LiveKit can replace it later |
| Camera | **Watch mode + on-demand**: frames on visual questions, "Show Polly" shutter, Polly-requested looks, and ~1 frame/10 s while the watch toggle is on |
| Long-term memory | **On-device SwiftData** (`PollyMemory`, `PollyCookLog`); schema shaped to sync to Postgres+pgvector later |
| Entry points | New **6th bottom tab "Polly"** + **Cook with Polly** button on recipe detail |
| Existing Cook Mode | Untouched; remains the no-AI fallback (restyle golden rule: never remove a feature) |

Known doc conflict, accepted by Omar: `product.md` caps the app at 5 intent-named tabs and bans
chef personas. Polly overrides both; `product.md` gets a short amendment noting the new contract.

## Architecture

```
┌─ Polly tab ──────────┐   ┌─ RecipeDetailView ─────────┐
│ memory card,         │   │ "Cook with Polly" button   │
│ recipe picker        │   └────────────┬───────────────┘
└──────────┬───────────┘                │
           └───────────┬────────────────┘
                       ▼
       PollySessionView (fullScreenCover)
                       │
        PollySessionController (@MainActor @Observable)
        state machine: idle → compiling → connecting →
        greeting → preflight → cooking(step) → finishing → ended
        │           │            │             │
        ▼           ▼            ▼             ▼
  CookPlan     Realtime      PollyAudio   PollyCamera
  Compiler     Transport     Engine       Controller
  (one-shot    (actor, WS    (AVAudio-    (AVCapture-
  gpt-4o via   to OpenAI     Engine,      Session,
  existing     Realtime,     voice-       preview +
  proxy;       ephemeral     processing   JPEG frames)
  cached)      token)        I/O, 24 kHz
                             PCM16)
        │
        ▼
  PollyToolRegistry ──► PantryMatcher / SubstitutionService /
                        DietGuard / NutritionEstimator /
                        TimerManager (session-owned) /
                        PollyMemory read+write / step tracking
```

### Components (all new unless noted)

**`Glutt/Services/Polly/`**
- `CookPlan.swift` — Codable recipe-execution graph: `mise: [MiseItem]`, `equipment: [String]`,
  `steps: [PlanStep]` where `PlanStep = {id, index, title, instruction, kind: prep|active|passive|checkpoint,
  estimatedSeconds?, timerSeconds?, dependsOn: [id], visualCheck?: String, recovery?: String,
  ingredientNames: [String]}`. Optional-tolerant custom `init(from:)` (Plates pattern).
- `CookPlanCompiler.swift` — `compile(recipe:scale:) async -> CookPlan`. One `LLMClient.chatJSON`
  call through the existing proxy (`gpt-4o`, json mode). Deterministic fallback `CookPlan.linear(from:)`
  derived from `RecipeStep`s when AI is unavailable/failed (session can still run; Polly narrates the
  raw steps). File-cached in Application Support keyed by recipe `persistentModelID` hash + scale +
  steps-content hash.
- `PollySessionToken.swift` + `PollyTokenService.swift` — `struct PollyTokenService` (Plates-style
  `Transport` closure DI) POSTs `{proxyBaseURL}/polly/session` with `x-glutt-proxy-key`, decodes
  `{clientSecret, expiresAt, model, voice}`.
- `RealtimeTransport.swift` — `protocol RealtimeTransporting` + `actor RealtimeWebSocketTransport`.
  Connects `wss://api.openai.com/v1/realtime?model=…` with `Authorization: Bearer <ephemeral>`.
  Encodes/decodes the Realtime event protocol (typed `RealtimeEvent` enums for the ~12 events we
  use: session.update, input_audio_buffer.append/speech_started, conversation.item.create,
  response.create/cancel, response.output_audio.delta, response.function_call_arguments.done,
  response.done, error, …). Reconnect-with-resume once on drop.
- `PollyAudioEngine.swift` — mic capture → 24 kHz mono PCM16 base64 chunks; playback via
  `AVAudioPlayerNode` buffer queue; `AVAudioSession` `.playAndRecord` + `.voiceChat` (hardware echo
  cancellation); barge-in = on `speech_started`, flush playback queue + send `response.cancel`.
- `PollyCameraController.swift` — `AVCaptureSession` (back camera default, flippable), preview
  layer, `captureFrame()` → downscaled JPEG (`ImagePrep` pattern, ≤1024 px, q0.6), watch-mode timer.
- `PollyToolRegistry.swift` — tool JSON schemas + async handlers. v1 tools:
  `get_current_step`, `mark_step_done`, `go_to_step`, `start_timer`, `check_timers`, `cancel_timer`,
  `check_pantry`, `find_substitutes` (SubstitutionService filtered by DietGuard), `get_nutrition`,
  `adjust_servings`, `remember_fact`, `request_camera_frame`, `end_session`.
  Handlers run on a session snapshot (pantry/prefs fetched once at start; memory writes go through
  the controller to the ModelContext).
- `PollyPromptBuilder.swift` — system instructions: Polly persona (calm, expert, concise, never
  condescending; house tone rules) + CookPlan JSON + pantry snapshot + diet rules/allergies/skill +
  top-N `PollyMemory` facts + past `CookSession`s of this recipe + camera/tool usage policy.
- `PollyMemoryExtractor.swift` — post-session one-shot `chatJSON` over the transcript → new/updated
  `PollyMemory` facts + a session summary for `PollyCookLog`.
- `PollyConfig.swift` — tuning constants: watch-mode frame interval, frame max dimension/quality,
  max session minutes, memory injection count, realtime model/voice names.

**`Glutt/Features/Polly/`**
- `PollyTabView.swift` — greeting header, "Polly knows your kitchen" memory card (top facts, count),
  saved-recipe picker (reuses `RecipeCard`, pantry-match badges), recent Polly cooks.
- `PollySessionView.swift` — full-bleed camera preview background; overlay: current-step card,
  active-timers bar (CookModeView pattern), status orb (listening/speaking/thinking), live caption
  line (last utterance), controls: mute, camera flip/off, watch-mode toggle (eye), "Show Polly"
  shutter, end. Preflight renders a missing-ingredients checklist card while Polly talks through it.
  Keeps `isIdleTimerDisabled = true`; bumps `floatingButtonSuppressors`; end → existing
  `CookFinishView(recipe:scale:onComplete:)`.
- `PollySessionController.swift` — the `@MainActor @Observable` brain described above; owns a
  session-scoped `TimerManager` (same class cook mode uses).
- `PollyPaywallHook.swift` — no-op seam (house pattern) for when payments return.

**Models — `Glutt/Models/Polly.swift`** (add to the explicit Schema in `GluttApp.swift` **and** to
every in-memory test container that needs them):
- `@Model PollyMemory` — `kind: MemoryKind (equipment|technique|pantryHabit|preference|outcome)`,
  `text: String`, `confidence: Double`, `timesReinforced: Int`, `createdAt`, `updatedAt`,
  `sourceRecipeTitle: String?`. De-dup on write by fuzzy text match within kind (reinforce instead
  of duplicate).
- `@Model PollyCookLog` — `startedAt`, `endedAt?`, `recipe: Recipe?`, `summary: String`,
  `stepsCompleted: Int`, `stepsTotal: Int`, `substitutions: [String]`, `endedEarly: Bool`.

**Proxy — `vercel-ai-proxy/api/polly/session.js`**
POST, gated by `x-glutt-proxy-key`. Calls OpenAI `POST /v1/realtime/client_secrets` with session
defaults (model `gpt-realtime`, voice `marin`, modalities audio+text, expiry ≤10 min) and returns
`{clientSecret, expiresAt, model, voice}`. The committed shared proxy key never touches the socket;
the long-lived `OPENAI_API_KEY` lives only in Vercel env. Version header
`x-glutt-proxy-version: polly-2026-07-02-1`; `has_*` flag added to `api/health.js`.

**App shell wiring** (exhaustive-switch tour): `AppTab.polly` case (label/icon) in `Router.swift`;
`case "polly"` deep link; `tabContent` case in `RootView.swift`; glyph case in `GluttTabBar.swift`;
session presented as `.fullScreenCover` from `RootView` via `router.pendingPollyRecipeID` (Plates
pattern). `NotificationRoutingDelegate` gains a `polly` destination; while a session is live, timer
banners are suppressed in `willPresent` (in-session timers render natively).

**Config (`project.yml` → `xcodegen generate`)**: add `NSMicrophoneUsageDescription`; reword
`NSCameraUsageDescription` to cover live sessions; add `UIBackgroundModes: [audio]` so Polly keeps
talking and timers keep ticking when the screen locks with wet hands.

**Icons**: vendor Phosphor `chef-hat` (tab), `microphone`, `microphone-slash`, `video-camera`,
`video-camera-slash`, `eye`, `eye-slash`, `camera-rotate`, `waveform` (fill+regular) per the
documented subset process; extend the `Ph` shim.

## Session lifecycle

1. **Compile** — CookPlan from cache or one proxy call (~2–4 s, spinner with copy).
2. **Mint + connect** — token from proxy; WS session.update with instructions, tools, server VAD,
   voice `marin`, audio in/out PCM16.
3. **Greeting + preflight** — Polly confirms the dish and servings; `check_pantry` result is already
   in context; missing items discussed, `find_substitutes` offered; user can start anyway.
4. **Cooking loop** — Polly drives via `get_current_step`/`mark_step_done`; passive steps get
   timers; interruptions are answered in-context; frames arrive per the camera policy and Polly
   comments on what she sees; substitutions and deviations are recorded in session state.
5. **Finish** — `end_session` tool or user tap → transcript summarized → `PollyMemory` facts +
   `PollyCookLog` written → `CookFinishView` for standard logging.

**Degradation ladder:** proxy unconfigured → tab shows setup card, detail button hidden (matches
`LLMClient.isConfigured` convention). Token mint fails → error card with "Cook without Polly" →
classic `CookModeView`. Mid-cook socket death → one silent reconnect, else banner with same
fallback, cook state preserved. Camera denied → voice-only session (mic denied → no session).
CookPlan compile fails → linear fallback plan.

## Costs

Rough v1 numbers at current gpt-realtime pricing: 30–40 min cook with intermittent conversation +
watch mode ≈ **$0.50–$2.00/session**. Knobs (constants in `PollyConfig`): watch-mode frame interval
(10 s), frame size (1024 px), idle-mic policy, max session length (90 min hard stop).

## Testing

Plates-style unit tests (closure DI, fakes; no live network/audio):
- `CookPlanDecodeTests` — contract decode incl. missing optionals; linear fallback from a Recipe.
- `PollyTokenServiceTests` — URL/headers/error mapping with fake transport.
- `RealtimeEventCodecTests` — encode/decode of the event subset, incl. function-call args assembly.
- `PollyToolRegistryTests` — each handler against in-memory SwiftData (pantry check, halal-filtered
  substitutes, timer start/check, step nav bounds, remember-fact dedup/reinforce).
- `PollySessionControllerTests` — state machine over a scripted fake transport (greet → preflight →
  step advance → tool round-trip → barge-in → end), no audio.
- `PollyMemoryExtractorTests` — decode + merge rules.
Live audio/camera/echo verified on device via TestFlight (simulator has no camera; realtime audio
misbehaves there).

## Explicitly out of scope for v1

Backend Postgres/pgvector memory sync; WebRTC/LiveKit transport; freeform "just talk" sessions not
anchored to a recipe; multi-recipe parallel cooks; Polly on the share extension; Live Activities;
paywall activation (seam only); Polly-initiated continuous vision beyond watch mode.

## What Omar must do (can't be done from this machine)

Final list delivered with the implementation, but known already:
1. **OpenAI**: ensure the API key on Vercel has Realtime API access + billing headroom.
2. **Vercel**: deploy `vercel-ai-proxy` (already pending for Plates/Spoonacular) — Polly adds
   `api/polly/session.js`; confirm `OPENAI_API_KEY` + `GLUTT_PROXY_CLIENT_KEY` env vars.
3. **Device testing**: run on a physical iPhone (camera + echo-cancelled audio don't exist on sim).
4. **App Store**: next submission includes mic permission string + background-audio justification.
