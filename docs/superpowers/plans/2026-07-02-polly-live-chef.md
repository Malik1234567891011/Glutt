# Polly — Live AI Chef Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Realtime voice+camera cooking sessions ("Cook with Polly") launched from any saved recipe, plus a new Polly bottom tab, with on-device kitchen memory that improves every cook.

**Architecture:** A `@MainActor @Observable` session controller orchestrates four isolated units — a WebSocket transport speaking the OpenAI Realtime GA protocol (ephemeral tokens minted by the existing Vercel proxy), an AVAudioEngine voice pipeline (PCM16 24 kHz, echo-cancelled), an AVCaptureSession camera with watch-mode frame policy, and a tool registry that maps Realtime function calls onto Glutt's existing pure services (PantryMatcher, SubstitutionService, DietGuard, NutritionEstimator, TimerManager). A one-shot `LLMClient` call compiles each Recipe into a cached `CookPlan` execution graph. Two new SwiftData models persist durable memory.

**Tech Stack:** Swift 5.10 / SwiftUI / SwiftData, iOS 17.0, XcodeGen, XCTest, OpenAI Realtime API (`gpt-realtime-2`) over `URLSessionWebSocketTask`, Vercel serverless (plain fetch, no npm deps). **No new SPM dependencies.**

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-02-polly-live-chef-design.md`. Branch: `feat/polly-live-chef`.
- `project.yml` is the source of truth; after editing it or ADDING ANY new file, run `xcodegen generate` (expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`). `Glutt.xcodeproj` IS git-tracked: every commit that follows a regeneration stages `Glutt.xcodeproj` too, so no task leaves a dirty tree.
- Build/test/run through XcodeBuildMCP tools (`build_sim`, `test_sim`, scheme `Glutt`), NOT raw `xcodebuild`. Call `session_show_defaults` before the first build call in your session.
- Icons: Phosphor only via the vendored `Ph` shim (`Glutt/DesignSystem/Phosphor.swift`) — never `Image(systemName:)` in Polly UI (the floating + button's `plus` is pre-existing; leave it).
- Design tokens only: `Theme.Colors.*`, `Theme.Spacing.*`, `Theme.Radius.*`, `Font.glutt*` (`Glutt/DesignSystem/Theme.swift`, `Typography.swift`). Light mode only, portrait iPhone only. Haptics via `Haptics.*` on every new interactive control.
- Tone of voice: warm, calm, practical. No guilt language, no fake precision, no "beta" wording in user-facing copy.
- Never remove or reroute an existing feature (restyle golden rule). `CookModeView` stays untouched.
- All AI features must degrade: `LLMClient.isConfigured == false` → Polly surfaces are hidden or show a setup card; session failures offer "Cook without Polly" → classic `CookModeView`.
- Tests: XCTest with `@testable import Glutt`, closure-based dependency injection (Plates pattern), in-memory `ModelContainer` with an explicit `Schema([...])` list. No network, no live audio/camera in tests.
- Commits: `feat(polly): <imperative summary>` (or `docs(polly):`), one commit per task step block, ending with the Claude co-author trailer used in this repo.
- The committed shared proxy key (`Secrets.aiProxyClientKey`) authenticates calls to OUR proxy only; the OpenAI key lives exclusively in Vercel env vars. Ephemeral tokens (`ek_…`) are the only credential the socket ever sees.
- OpenAI Realtime sessions hard-cap at **60 minutes** — the controller must warn and rotate/end before that (see `PollyConfig.maxSessionMinutes = 52`).

---

## Shared Contracts (read this before implementing ANY task)

Every task references these exact names and signatures. If your task consumes a type from another task, the signature below is authoritative — do not improvise.

### New file map

```
Glutt/Services/Polly/
  PollyConfig.swift            — tuning constants (Task 2)
  CookPlan.swift               — execution graph model + linear fallback (Task 2)
  CookPlanCompiler.swift       — LLM compile + file cache (Task 12)
  PollyTokenService.swift      — ephemeral token mint via proxy (Task 4)
  RealtimeEvent.swift          — client/server event codec (Task 6)
  RealtimeTransport.swift      — protocol + WebSocket actor (Task 7)
  PollyAudioEngine.swift       — mic capture + playback + PCM helpers (Task 8)
  PollyCameraController.swift  — capture session + watch scheduler (Task 9)
  PollyToolRegistry.swift      — tool schemas + handlers + CookState (Task 10)
  PollyPromptBuilder.swift     — system instructions assembly (Task 11)
  PollyMemoryStore.swift       — upsert/dedup/top-facts over PollyMemory (Task 3)
  PollyMemoryExtractor.swift   — post-cook fact extraction (Task 14)
Glutt/Models/Polly.swift       — @Model PollyMemory + PollyCookLog (Task 3)
Glutt/Features/Polly/
  PollySessionController.swift — session brain / state machine (Task 13)
  PollySessionView.swift       — live session UI (Task 15)
  PollySessionSubviews.swift   — orb, step card, controls, preflight card (Task 15)
  PollyTabView.swift           — tab home: memory card + recipe picker (Task 16)
  PollyPaywallHook.swift       — no-op premium seam (Task 15)
vercel-ai-proxy/api/polly/session.js — token mint endpoint (Task 5)
GluttTests/
  PollyIconAssetTests.swift (Task 1), CookPlanTests.swift, PollyMemoryStoreTests.swift,
  PollyTokenServiceTests.swift, RealtimeEventCodecTests.swift, RealtimeTransportTests.swift,
  PCMTests.swift, WatchModeSchedulerTests.swift, PollyToolRegistryTests.swift,
  PollyPromptBuilderTests.swift, CookPlanCompilerTests.swift,
  PollySessionControllerTests.swift, PollyMemoryExtractorTests.swift,
  PollyRouterTests.swift          — 14 suites total
```

### Interface contracts

```swift
// PollyConfig.swift (Task 2)
enum PollyConfig {
    static let realtimeModel = "gpt-realtime-2"
    static let voice = "marin"
    static let watchFrameInterval: TimeInterval = 10
    static let frameMaxDimension: CGFloat = 1024
    static let frameJPEGQuality: CGFloat = 0.6
    static let maxSessionMinutes = 52          // OpenAI hard cap is 60
    static let wrapUpWarningMinutes = 47
    static let memoryFactLimit = 12
    static let tokenTTLSeconds = 600
}

// CookPlan.swift (Task 2)
struct CookPlan: Codable, Equatable {
    enum StepKind: String, Codable { case prep, active, passive, checkpoint }
    struct MiseItem: Codable, Equatable { let name: String; let prep: String }
    struct PlanStep: Codable, Equatable, Identifiable {
        let id: String; let index: Int; let title: String; let instruction: String
        let kind: StepKind; let estimatedSeconds: Int?; let timerSeconds: Int?
        let dependsOn: [String]; let visualCheck: String?; let recovery: String?
        let ingredientNames: [String]
    }
    let title: String; let servings: Int
    let mise: [MiseItem]; let equipment: [String]; let steps: [PlanStep]
    var isFallback: Bool                    // true when built by linear(from:)
    static func linear(from recipe: Recipe, scale: Double) -> CookPlan
}
// Decoding is optional-tolerant (custom init(from:) like PlateCard): missing
// arrays -> [], missing scalars -> nil/0, unknown kind string -> .active.

// Glutt/Models/Polly.swift (Task 3) — BOTH must be added to the Schema list in
// GluttApp.swift and to every test container that touches them.
enum MemoryKind: String, Codable, CaseIterable {
    case equipment, technique, pantryHabit, preference, outcome
}
@Model final class PollyMemory {
    var kindRaw: String            // MemoryKind.rawValue
    var text: String
    var confidence: Double         // 0...1
    var timesReinforced: Int
    var createdAt: Date
    var updatedAt: Date
    var sourceRecipeTitle: String?
    var kind: MemoryKind { get }   // computed from kindRaw, default .outcome
    init(kind: MemoryKind, text: String, confidence: Double, sourceRecipeTitle: String?)
}
@Model final class PollyCookLog {
    var startedAt: Date
    var endedAt: Date?
    var recipe: Recipe?
    var summary: String
    var stepsCompleted: Int
    var stepsTotal: Int
    var substitutions: [String]
    var endedEarly: Bool
    init(startedAt: Date, recipe: Recipe?)
}

// PollyMemoryStore.swift (Task 3)
enum PollyMemoryStore {
    @discardableResult
    static func upsert(kind: MemoryKind, text: String, confidence: Double,
                       sourceRecipeTitle: String?, in context: ModelContext) -> PollyMemory
    static func topFacts(limit: Int, in context: ModelContext) -> [PollyMemory]
}
// upsert dedup rule: same kind + Jaccard word-overlap of lowercased texts >= 0.6
// -> reinforce existing (timesReinforced += 1, confidence = max, updatedAt = now,
// keep the LONGER text); else insert new.

// PollyTokenService.swift (Task 4)
struct PollySessionToken: Decodable, Equatable {
    let value: String              // "ek_..."
    let expiresAt: Int?            // unix seconds, wire key "expiresAt"
    let model: String
    let voice: String
}
enum PollyTokenError: LocalizedError, Equatable { case notConfigured, badResponse(String) }
struct PollyTokenService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    init(transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
         baseURL: String = Secrets.aiProxyBaseURL,
         clientKey: String = Secrets.aiProxyClientKey)
    func mint() async throws -> PollySessionToken   // POST {baseURL}/polly/session
    static let live: PollyTokenService
}

// RealtimeEvent.swift (Task 6)
struct RealtimeToolDefinition: Encodable, Equatable {
    let type = "function"; let name: String; let description: String
    let parameters: JSONValue      // JSON Schema as a JSONValue tree
}
enum JSONValue: Codable, Equatable {   // minimal JSON tree used for schemas/args
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])
}
struct RealtimeSessionConfig {
    var instructions: String
    var tools: [RealtimeToolDefinition]
    var voice: String              // PollyConfig.voice
    var model: String              // PollyConfig.realtimeModel
    var transcribeInput: Bool      // true -> audio.input.transcription = {model: "gpt-4o-transcribe"}
}
struct RealtimeFunctionCall: Equatable { let name: String; let callId: String; let argumentsJSON: String }
enum RealtimeClientEvent: Equatable {
    case sessionUpdate(RealtimeSessionConfig)
    case appendAudio(base64: String)
    case createUserText(String)
    case createUserImage(dataURI: String, itemId: String?)  // itemId lets us delete stale watch frames
    case createFunctionOutput(callId: String, output: String)
    case deleteItem(itemId: String)
    case responseCreate
    case responseCancel
    case truncateItem(itemId: String, audioEndMs: Int)
    func encoded() throws -> Data     // exact GA JSON, see protocol reference below
}
enum RealtimeServerEvent: Equatable {
    case sessionCreated
    case sessionUpdated
    case speechStarted                       // input_audio_buffer.speech_started
    case speechStopped
    case inputTranscript(String)             // conversation.item.input_audio_transcription.completed
    case outputAudioDelta(itemId: String, base64: String)
    case outputTranscriptDelta(itemId: String, delta: String)
    case responseDone(status: String, calls: [RealtimeFunctionCall])
    case responseCancelled
    case error(code: String?, message: String)
    case unhandled(type: String)
    static func decode(_ data: Data) -> RealtimeServerEvent
}

// RealtimeTransport.swift (Task 7)
protocol RealtimeSocket: Sendable {          // seam over URLSessionWebSocketTask
    func send(text: String) async throws
    func receiveText() async throws -> String
    func close()
}
protocol RealtimeTransporting: AnyObject, Sendable {
    func connect(token: String, model: String) async throws
    func send(_ event: RealtimeClientEvent) async throws
    var events: AsyncStream<RealtimeServerEvent> { get }
    func close() async
}
actor RealtimeWebSocketTransport: RealtimeTransporting {
    init(socketFactory: @escaping @Sendable (URLRequest) -> RealtimeSocket = ...)
}

// PollyAudioEngine.swift (Task 8)
enum PCM {
    static func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data          // native float -> 16-bit LE mono
    static func buffer(fromPCM16 data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer?
    static func resample(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer?
}
@MainActor @Observable final class PollyAudioEngine {
    private(set) var isRunning: Bool
    var isMuted: Bool
    private(set) var isPlaying: Bool         // assistant audio currently audible
    private(set) var inputLevel: Float       // 0...1 for the orb
    func start(onChunk: @escaping @Sendable (String) -> Void) throws  // base64 PCM16 24k mono ~100ms chunks
    func stop()
    func enqueue(base64: String)             // assistant audio playback
    @discardableResult func interruptPlayback() -> Int  // stops + returns played ms of current item
}

// PollyCameraController.swift (Task 9)
struct WatchModeScheduler: Equatable {       // pure, testable
    var isEnabled: Bool
    var interval: TimeInterval               // PollyConfig.watchFrameInterval
    private(set) var lastSent: Date?
    mutating func shouldSendFrame(now: Date) -> Bool
}
@MainActor @Observable final class PollyCameraController: NSObject {
    private(set) var isRunning: Bool
    private(set) var isAuthorized: Bool
    let previewLayer: AVCaptureVideoPreviewLayer
    func start() async                       // requests permission if needed
    func stop()
    func flip()
    func captureFrame() async -> Data?       // JPEG, downscaled to PollyConfig.frameMaxDimension
}

// PollyToolRegistry.swift (Task 10)
struct CookState: Equatable {
    var stepIndex: Int = 0
    var completedStepIDs: Set<String> = []
    var substitutions: [String] = []
    var servings: Int
}
@MainActor final class PollyToolRegistry {
    static let toolDefinitions: [RealtimeToolDefinition]   // all 13 tools below
    private(set) var state: CookState
    var onRequestFrame: (() async -> Bool)?    // controller captures+sends; true on success
    var onEndSession: (() -> Void)?
    init(plan: CookPlan, recipe: Recipe, pantry: [PantryItem], prefs: UserPrefs,
         timers: TimerManager, context: ModelContext)
    func handle(name: String, argumentsJSON: String) async -> String  // JSON string result
}
// Tool names (locked): get_current_step, mark_step_done, go_to_step, start_timer,
// check_timers, cancel_timer, check_pantry, find_substitutes, get_nutrition,
// adjust_servings, remember_fact, request_camera_frame, end_session

// PollyPromptBuilder.swift (Task 11)
enum PollyPromptBuilder {
    static func instructions(recipe: Recipe, plan: CookPlan,
                             pantryMatch: PantryMatcher.MatchResult,
                             prefs: UserPrefs, memories: [PollyMemory],
                             pastSessions: [CookSession]) -> String
}

// CookPlanCompiler.swift (Task 12)
enum CookPlanCompiler {
    static func cacheKey(recipe: Recipe, scale: Double) -> String
    static func cachedPlan(forKey key: String) -> CookPlan?
    static func store(_ plan: CookPlan, forKey key: String)
    static func compile(recipe: Recipe, scale: Double) async -> CookPlan
    // compile: cache hit -> cached; else LLMClient.chatJSON -> store; any error ->
    // CookPlan.linear(from:scale:) (isFallback = true, NOT cached).
}

// PollySessionController.swift (Task 13)
@MainActor @Observable final class PollySessionController {
    enum Phase: Equatable { case idle, compiling, connecting, live, reconnecting, ended, failed(String) }
    struct Dependencies {                      // closure DI, Plates pattern
        var mintToken: () async throws -> PollySessionToken
        var makeTransport: () -> RealtimeTransporting
        var compilePlan: (Recipe, Double) async -> CookPlan
        var extractMemories: (String, String) async throws -> PollyMemoryExtractor.Extraction
        var now: () -> Date
        static let live: Dependencies
    }
    private(set) var phase: Phase
    private(set) var plan: CookPlan?
    private(set) var captionText: String       // rolling last utterance line
    private(set) var isPollySpeaking: Bool
    private(set) var isListening: Bool
    private(set) var isThinking: Bool          // responseCreate sent, no audio back yet
    private(set) var wantsEnd: Bool            // set by the end_session tool; the VIEW observes it and calls end()
    private(set) var missingIngredients: [String]  // pantry-match misses captured at start
    var isWatching: Bool                       // watch-mode toggle
    let audio: PollyAudioEngine
    let camera: PollyCameraController
    let timers: TimerManager
    var registry: PollyToolRegistry?           // set during start()
    var stepIndex: Int { registry?.state.stepIndex ?? 0 }
    init(recipe: Recipe, scale: Double, deps: Dependencies = .live,
         audio: PollyAudioEngine = PollyAudioEngine(),
         camera: PollyCameraController = PollyCameraController())
    // start() runs ONCE per controller instance (guard phase == .idle); retrying
    // after .failed means creating a NEW controller. Mic permission is requested
    // by PollySessionView BEFORE start(); pass requireMic: false in unit tests.
    func start(context: ModelContext, requireMic: Bool = true) async
    func end(context: ModelContext, endedEarly: Bool) async  // extract memories, write PollyCookLog
    func sendShowPolly() async                 // manual shutter frame + response.create
    func toggleMute(); func flipCamera()
}

// PollyMemoryExtractor.swift (Task 14)
enum PollyMemoryExtractor {
    struct Fact: Decodable, Equatable { let kind: String; let text: String; let confidence: Double }
    struct Extraction: Decodable, Equatable { let facts: [Fact]; let summary: String }
    static func extract(transcript: String, recipeTitle: String) async throws -> Extraction
    static func apply(_ extraction: Extraction, recipeTitle: String, in context: ModelContext)
}

// Router additions (Task 15/16)
// AppTab gains `case polly` THIRD in the case order (today, recipes, polly, plan,
// kitchen, progress) with label "Polly"; Router gains:
struct PollyLaunch: Identifiable, Equatable {          // defined beside Router (Task 15)
    let id = UUID(); let recipe: Recipe; let scale: Double
    init(recipe: Recipe, scale: Double)
}
//   var pollyLaunch: PollyLaunch?      // RootView presents the session cover via .fullScreenCover(item:)
//   var isPollySessionActive = false   // NotificationRoutingDelegate.willPresent returns [] while true
// Deep link: case "polly": selectedTab = .polly
// PollyPaywallHook.run(completion:) — no-op seam, calls completion() immediately.
```

### OpenAI Realtime GA protocol reference (verified 2026-07-02 from developers.openai.com)

**Token mint (proxy-side):** `POST https://api.openai.com/v1/realtime/client_secrets`, header `Authorization: Bearer <OPENAI_API_KEY>`, body:
```json
{"expires_after": {"anchor": "created_at", "seconds": 600},
 "session": {"type": "realtime", "model": "gpt-realtime-2",
             "audio": {"output": {"voice": "marin"}}}}
```
Response contains `{"value": "ek_...", "expires_at": 1234567890, ...}`. Voice cannot change after the model first speaks.

**WS connect (client):** `wss://api.openai.com/v1/realtime?model=gpt-realtime-2` with header `Authorization: Bearer ek_...` (ephemeral). Messages are JSON text frames.

**session.update (client → server, GA shape — note `"type": "realtime"` and nested audio):**
```json
{"type": "session.update", "session": {
  "type": "realtime",
  "output_modalities": ["audio"],
  "instructions": "<PollyPromptBuilder output>",
  "tools": [{"type": "function", "name": "start_timer",
             "description": "...", "parameters": {"type": "object", "properties": {...}, "required": [...]}}],
  "tool_choice": "auto",
  "audio": {
    "input": {"format": {"type": "audio/pcm", "rate": 24000},
               "turn_detection": {"type": "semantic_vad"},
               "transcription": {"model": "gpt-4o-transcribe"}},
    "output": {"format": {"type": "audio/pcm"}, "voice": "marin"}},
  "truncation": {"type": "retention_ratio", "retention_ratio": 0.8,
                  "token_limits": {"post_instructions": 16000}}}}
```

**Other client events:**
- `{"type": "input_audio_buffer.append", "audio": "<base64 pcm16 mono 24k>"}` (≤15 MB/chunk; send ~100 ms chunks)
- Text: `{"type": "conversation.item.create", "item": {"type": "message", "role": "user", "content": [{"type": "input_text", "text": "..."}]}}`
- Image: same but content `[{"type": "input_image", "image_url": "data:image/jpeg;base64,..."}]`; optional client-chosen `"id"` on the item (e.g. `"wf_3"`) enables later `conversation.item.delete`.
- Tool result: `{"type": "conversation.item.create", "item": {"type": "function_call_output", "call_id": "<call_id>", "output": "<json string>"}}` then `{"type": "response.create"}`
- `{"type": "conversation.item.delete", "item_id": "wf_2"}` — used to drop stale watch frames (cost control)
- `{"type": "response.create"}`, `{"type": "response.cancel"}`
- `{"type": "conversation.item.truncate", "item_id": "<assistant item>", "content_index": 0, "audio_end_ms": 1500}` — after barge-in, tell the server how much audio the user actually heard

**Server events we handle (GA names):** `session.created`, `session.updated`, `input_audio_buffer.speech_started` (server auto-cancels the in-flight response; client must stop playback + send truncate), `input_audio_buffer.speech_stopped`, `conversation.item.input_audio_transcription.completed` (`.transcript`), `response.output_audio.delta` (`.delta` base64, `.item_id`), `response.output_audio_transcript.delta`, `response.done` (function calls appear as `response.output[]` items with `"type": "function_call"`, fields `name`, `call_id`, `arguments` (JSON string); usage under `response.usage`), `response.cancelled`, `error` (`.code`, `.message`). Everything else → `.unhandled(type:)`.

**Audio:** PCM16 little-endian mono 24 kHz both directions. User audio ≈ 1 token/100 ms, assistant ≈ 1 token/50 ms. Session max 60 min. Prompt caching applies when the conversation prefix is static — instructions/tools are set once at session start and never mutated mid-cook.

### House patterns cheat-sheet

- Proxy handler shape: copy `vercel-ai-proxy/api/plates/deck.js` — shared-secret gate on `x-glutt-proxy-key` vs `GLUTT_PROXY_CLIENT_KEY` env (gate disabled if env unset), `x-glutt-proxy-version` response header, JSON errors `{error: "..."}` with proper status.
- Client service shape: copy `Glutt/Services/Plates/PlatesService.swift` — `Transport` closure DI, trimmed `Secrets` defaults, 20 s timeout, typed `LocalizedError`.
- ViewModel/tests shape: copy `Glutt/Features/Plates/PlatesFeedViewModel.swift` + `GluttTests/PlatesFeedViewModelTests.swift` — `Dependencies` struct of closures with `static let live`.
- In-memory test container: `ModelContainer(for: Schema([...needed models...]), configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])` inside `@MainActor` test class `setUpWithError`.
- `CookFinishView(recipe:scale:onComplete:)` is the session end screen (writes CookSession/FoodLog/Leftover); `TimerManager` API: `start(label:seconds:)`, `cancel(_:)`, `cancelAll()`, `timers`, `now`, `CookTimer.remainingSeconds(at:)`, `TimerManager.format(seconds:)`.

---
### Task 1: Permissions, background audio, and vendored Phosphor icons

**Files:**
- Modify: `/Users/omarlahmimi/Documents/Glutt/project.yml` (targets.Glutt.info.properties block, lines 28–44 — camera string is line 39)
- Modify: `/Users/omarlahmimi/Documents/Glutt/Glutt/DesignSystem/Phosphor.swift` (insert 8 enum cases at 5 alphabetical positions: after lines 22 `camera`, 34 `checkSquare`, 43 `export`, 60 `magnifyingGlass`, 84 `trash`)
- Create: 12 imagesets under `/Users/omarlahmimi/Documents/Glutt/Glutt/Resources/Assets.xcassets/Phosphor/` — `chef-hat.imageset`, `chef-hat-fill.imageset`, `microphone.imageset`, `microphone-fill.imageset`, `microphone-slash.imageset`, `video-camera.imageset`, `video-camera-fill.imageset`, `video-camera-slash.imageset`, `eye.imageset`, `eye-fill.imageset`, `eye-slash.imageset`, `camera-rotate.imageset`
- Test: Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyIconAssetTests.swift`
- Regenerated as side effects (both git-tracked, commit them): `/Users/omarlahmimi/Documents/Glutt/Glutt/Info.plist`, `/Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`

**Interfaces:**
- Consumes: existing `Ph` shim API in `Glutt/DesignSystem/Phosphor.swift` — `enum Ph: String` with `var regular: Image`, `var bold: Image`, `var fill: Image`; existing imageset `Contents.json` shape (see `camera.imageset`).
- Produces (Tasks 15/16 rely on these exact case names):
  ```swift
  // New Ph cases — .regular is vendored for all eight; .fill is vendored ONLY for
  // chefHat, microphone, videoCamera, eye. Later tasks must use .regular for
  // microphoneSlash / videoCameraSlash / eyeSlash / cameraRotate.
  case cameraRotate = "camera-rotate"
  case chefHat = "chef-hat"
  case eye = "eye"
  case eyeSlash = "eye-slash"
  case microphone = "microphone"
  case microphoneSlash = "microphone-slash"
  case videoCamera = "video-camera"
  case videoCameraSlash = "video-camera-slash"
  ```
  Plus Info.plist capabilities the session stack requires at runtime: `NSMicrophoneUsageDescription` (AVAudioEngine mic tap, Task 8), reworded `NSCameraUsageDescription` (AVCaptureSession, Task 9), `UIBackgroundModes: [audio]` (playback continues when the screen locks, Task 13).

- [ ] **Step 1: Write the failing icon-asset test.** Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyIconAssetTests.swift` with exactly:

  ```swift
  import UIKit
  import XCTest
  @testable import Glutt

  /// Guards the vendored Polly icon subset: every imageset the Polly UI references
  /// must exist in the app's asset catalog. Catches a forgotten copy step or a
  /// renamed imageset before it becomes an invisible button on device.
  final class PollyIconAssetTests: XCTestCase {

      /// Tests run hosted inside the Glutt app, so the app's compiled asset
      /// catalog lives in the app bundle — not in the test bundle.
      private let appBundle = Bundle(identifier: "com.omarlahmimi.glutt") ?? .main

      private let expectedImagesets = [
          "chef-hat", "chef-hat-fill",
          "microphone", "microphone-fill",
          "microphone-slash",
          "video-camera", "video-camera-fill",
          "video-camera-slash",
          "eye", "eye-fill",
          "eye-slash",
          "camera-rotate",
      ]

      func testAllPollyIconAssetsExist() {
          for name in expectedImagesets {
              XCTAssertNotNil(
                  UIImage(named: name, in: appBundle, compatibleWith: nil),
                  "Missing Phosphor imageset '\(name)' in Assets.xcassets/Phosphor"
              )
          }
      }
  }
  ```

- [ ] **Step 2: Regenerate the project so the new test file is compiled.** XcodeGen enumerates source files at generation time, so a brand-new `.swift` file needs a regenerate:

  ```bash
  cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate
  ```

  Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 3: Run the test suite and confirm the new test fails (RED).** If this is the session's first XcodeBuildMCP call, call `session_show_defaults` first (project `Glutt.xcodeproj`, scheme `Glutt`, an iOS 17+ iPhone simulator). Run tests: `test_sim` (scheme `Glutt`) — expected: FAIL. `PollyIconAssetTests.testAllPollyIconAssetsExist` fails with 12 "Missing Phosphor imageset" assertions; every pre-existing suite still passes. Do NOT proceed if the failure is a compile error instead of the assertion.

- [ ] **Step 4: Add mic permission, reword camera permission, add background audio in `project.yml`.** In `/Users/omarlahmimi/Documents/Glutt/project.yml`, inside `targets.Glutt.info.properties`, replace exactly this block (line 39–40):

  Before:
  ```yaml
        NSCameraUsageDescription: Glutt uses the camera to scan your fridge or pantry and to estimate meals you log from photos.
        ITSAppUsesNonExemptEncryption: false
  ```

  After:
  ```yaml
        NSCameraUsageDescription: Glutt uses the camera to scan your fridge or pantry, to estimate meals you log from photos, and to let Polly watch the pan during live cooking sessions.
        NSMicrophoneUsageDescription: Polly, your live cooking chef, listens so you can ask questions and get guidance hands-free while you cook.
        # Polly keeps guiding you (voice + timers) when the screen locks mid-cook.
        UIBackgroundModes:
          - audio
        ITSAppUsesNonExemptEncryption: false
  ```

  (Unquoted plain scalars match the surrounding style; neither new string contains a `: ` sequence, so no quoting is needed.)

- [ ] **Step 5: Vendor the 12 Phosphor SVG imagesets.** Run this exact script via Bash (network is fine here — it's a one-time vendoring step, not a test):

  ```bash
  set -e
  ASSETS="/Users/omarlahmimi/Documents/Glutt/Glutt/Resources/Assets.xcassets/Phosphor"
  BASE="https://raw.githubusercontent.com/phosphor-icons/core/main/assets"

  # Regular weight — 8 icons
  for name in chef-hat microphone microphone-slash video-camera video-camera-slash eye eye-slash camera-rotate; do
    dir="$ASSETS/$name.imageset"
    mkdir -p "$dir"
    curl -fsSL "$BASE/regular/$name.svg" -o "$dir/$name.svg"
    cat > "$dir/Contents.json" <<EOF
  {"properties":{"template-rendering-intent":"template"},"images":[{"idiom":"universal","filename":"$name.svg"}],"info":{"version":1,"author":"xcode"}}
  EOF
  done

  # Fill weight — 4 icons
  for name in chef-hat microphone video-camera eye; do
    dir="$ASSETS/$name-fill.imageset"
    mkdir -p "$dir"
    curl -fsSL "$BASE/fill/$name-fill.svg" -o "$dir/$name-fill.svg"
    cat > "$dir/Contents.json" <<EOF
  {"properties":{"template-rendering-intent":"template"},"images":[{"idiom":"universal","filename":"$name-fill.svg"}],"info":{"version":1,"author":"xcode"}}
  EOF
  done

  # Verify every download is a real SVG, not an HTML error page
  count=0
  for f in "$ASSETS"/{chef-hat,microphone,microphone-slash,video-camera,video-camera-slash,eye,eye-slash,camera-rotate}.imageset/*.svg \
           "$ASSETS"/{chef-hat,microphone,video-camera,eye}-fill.imageset/*.svg; do
    head -c 300 "$f" | grep -q "<svg" || { echo "BAD SVG: $f"; exit 1; }
    count=$((count + 1))
  done
  echo "$count SVGs OK (expected 12)"
  ```

  Expected output ends with `12 SVGs OK (expected 12)`. If any curl fails (icon renamed upstream), stop and check the icon name at https://phosphoricons.com — do not invent a substitute glyph. Note the heredoc bodies above are shown indented for plan readability; when running, the `EOF` delimiter must be at column 0 (or use `<<-EOF` with tab indentation). Simplest: paste the script into a file in the scratchpad and `bash` it.

- [ ] **Step 6: Add the 8 new `Ph` cases.** In `/Users/omarlahmimi/Documents/Glutt/Glutt/DesignSystem/Phosphor.swift`, make these five edits (each keeps the enum's existing alphabetical-ish ordering; every case gets an explicit raw value per house style):

  Edit 1 — before:
  ```swift
      case camera = "camera"
      case carrot = "carrot"
  ```
  after:
  ```swift
      case camera = "camera"
      case cameraRotate = "camera-rotate"
      case carrot = "carrot"
  ```

  Edit 2 — before:
  ```swift
      case checkSquare = "check-square"
      case circle = "circle"
  ```
  after:
  ```swift
      case checkSquare = "check-square"
      case chefHat = "chef-hat"
      case circle = "circle"
  ```

  Edit 3 — before:
  ```swift
      case export = "export"
      case flame = "flame"
  ```
  after:
  ```swift
      case export = "export"
      case eye = "eye"
      case eyeSlash = "eye-slash"
      case flame = "flame"
  ```

  Edit 4 — before:
  ```swift
      case magnifyingGlass = "magnifying-glass"
      case minus = "minus"
  ```
  after:
  ```swift
      case magnifyingGlass = "magnifying-glass"
      case microphone = "microphone"
      case microphoneSlash = "microphone-slash"
      case minus = "minus"
  ```

  Edit 5 — before:
  ```swift
      case trash = "trash"
      case warning = "warning"
  ```
  after:
  ```swift
      case trash = "trash"
      case videoCamera = "video-camera"
      case videoCameraSlash = "video-camera-slash"
      case warning = "warning"
  ```

- [ ] **Step 7: Regenerate the project for the `project.yml` change.**

  ```bash
  cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate
  ```

  Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

  Then verify XcodeGen wrote the new keys into the generated plist:

  ```bash
  /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" -c "Print :UIBackgroundModes" -c "Print :NSCameraUsageDescription" /Users/omarlahmimi/Documents/Glutt/Glutt/Info.plist
  ```

  Expected: the mic string, an array containing `audio`, and the reworded camera string. (New imagesets inside `Assets.xcassets` need no regeneration — the catalog is a single build input — but the `project.yml` edit does.)

- [ ] **Step 8: Build.** Build: `build_sim` (scheme `Glutt`) — expected: succeeds (asset catalog compiles the 12 new SVG imagesets; `Phosphor.swift` compiles with 8 new cases).

- [ ] **Step 9: Run tests and confirm GREEN.** Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, includes `PollyIconAssetTests/testAllPollyIconAssetsExist`, and all pre-existing suites still pass.

- [ ] **Step 10: Commit.** On branch `feat/polly-live-chef`:

  ```bash
  cd /Users/omarlahmimi/Documents/Glutt
  git add project.yml Glutt/Info.plist Glutt.xcodeproj \
    Glutt/DesignSystem/Phosphor.swift \
    Glutt/Resources/Assets.xcassets/Phosphor/chef-hat.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/chef-hat-fill.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/microphone.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/microphone-fill.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/microphone-slash.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/video-camera.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/video-camera-fill.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/video-camera-slash.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/eye.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/eye-fill.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/eye-slash.imageset \
    Glutt/Resources/Assets.xcassets/Phosphor/camera-rotate.imageset \
    GluttTests/PollyIconAssetTests.swift
  git commit -m "$(cat <<'MSG'
  feat(polly): add mic/background-audio permissions and vendored Polly icons

  - NSMicrophoneUsageDescription + UIBackgroundModes [audio] in project.yml;
    camera usage string reworded to cover live cooking sessions
  - Vendor 12 Phosphor imagesets (chef-hat, microphone, video-camera, eye
    regular+fill; slash/camera-rotate regular) into the asset catalog
  - Extend the Ph shim with 8 cases; PollyIconAssetTests guards the imagesets

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
  MSG
  )"
  ```

---

### Task 2: PollyConfig + CookPlan model + linear fallback

**Files:**
- Create: `Glutt/Services/Polly/PollyConfig.swift` (new folder — first Polly file; picked up by the `Glutt/` glob on `xcodegen generate`)
- Create: `Glutt/Services/Polly/CookPlan.swift`
- Test: `GluttTests/CookPlanTests.swift`
- Read-only dependency (do NOT modify): `Glutt/Features/Cook/CookModeView.swift:328-340` — the file-scope `extension RecipeStep { func ingredientsUsed(from:) -> [RecipeIngredient] }` is internal (no access modifier), so `CookPlan.linear(from:scale:)` reuses it directly from the same target.

**Interfaces:**
- Consumes (existing, `Glutt/Models/Recipe.swift`): `Recipe.title: String`, `Recipe.servings: Int`, `Recipe.sortedSteps: [RecipeStep]`, `Recipe.ingredients: [RecipeIngredient]`; `RecipeStep.text: String`, `RecipeStep.durationSeconds: Int?`; `RecipeIngredient.name: String`; and (from `CookModeView.swift:331`) `func ingredientsUsed(from ingredients: [RecipeIngredient]) -> [RecipeIngredient]`.
- Produces (contract — consumed by Tasks 10, 11, 12, 13, 15):

```swift
enum PollyConfig {
    static let realtimeModel = "gpt-realtime-2"
    static let voice = "marin"
    static let watchFrameInterval: TimeInterval = 10
    static let frameMaxDimension: CGFloat = 1024
    static let frameJPEGQuality: CGFloat = 0.6
    static let maxSessionMinutes = 52
    static let wrapUpWarningMinutes = 47
    static let memoryFactLimit = 12
    static let tokenTTLSeconds = 600
}

struct CookPlan: Codable, Equatable {
    enum StepKind: String, Codable { case prep, active, passive, checkpoint }
    struct MiseItem: Codable, Equatable { let name: String; let prep: String }
    struct PlanStep: Codable, Equatable, Identifiable {
        let id: String; let index: Int; let title: String; let instruction: String
        let kind: StepKind; let estimatedSeconds: Int?; let timerSeconds: Int?
        let dependsOn: [String]; let visualCheck: String?; let recovery: String?
        let ingredientNames: [String]
    }
    let title: String; let servings: Int
    let mise: [MiseItem]; let equipment: [String]; let steps: [PlanStep]
    var isFallback: Bool
    static func linear(from recipe: Recipe, scale: Double) -> CookPlan
}
```

Decoding is optional-tolerant (PlateCard pattern): missing arrays → `[]`, missing `servings` → `0`, missing optional scalars → `nil`, unknown/missing `kind` string → `.active`, missing `isFallback` → `false`. `encode(to:)` stays compiler-synthesized (Task 12's file cache round-trips CookPlan as JSON). Both structs keep explicit memberwise inits because a custom `init(from:)` suppresses the synthesized one.

- [ ] **Step 1: Write the failing test file**

Create `GluttTests/CookPlanTests.swift` with exactly this content:

```swift
import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class CookPlanTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }
    override func tearDownWithError() throws { container = nil; try super.tearDownWithError() }

    // MARK: - Decoding: full compiler contract

    private let fullJSON = """
    {
      "title": "Creamy Lemon Chicken",
      "servings": 4,
      "mise": [
        { "name": "chicken thighs", "prep": "pat dry, season both sides" },
        { "name": "garlic", "prep": "mince" }
      ],
      "equipment": ["large skillet", "tongs"],
      "steps": [
        {
          "id": "s1",
          "index": 0,
          "title": "Sear the chicken",
          "instruction": "Sear the chicken thighs 4 minutes per side until golden.",
          "kind": "active",
          "estimatedSeconds": 480,
          "timerSeconds": 240,
          "dependsOn": [],
          "visualCheck": null,
          "recovery": null,
          "ingredientNames": ["chicken thighs"]
        },
        {
          "id": "s2",
          "index": 1,
          "title": "Check the browning",
          "instruction": "Flip and confirm a deep golden crust before adding the garlic.",
          "kind": "checkpoint",
          "estimatedSeconds": 60,
          "timerSeconds": null,
          "dependsOn": ["s1"],
          "visualCheck": "Crust should be deep golden, not pale or burnt.",
          "recovery": "If pale, sear 2 more minutes; if burnt, lower the heat and scrape the pan.",
          "ingredientNames": ["chicken thighs", "garlic"]
        }
      ],
      "isFallback": false
    }
    """

    func testDecodesFullCompilerContract() throws {
        let plan = try JSONDecoder().decode(CookPlan.self, from: Data(fullJSON.utf8))

        XCTAssertEqual(plan.title, "Creamy Lemon Chicken")
        XCTAssertEqual(plan.servings, 4)
        XCTAssertFalse(plan.isFallback)

        XCTAssertEqual(plan.mise.count, 2)
        XCTAssertEqual(plan.mise[0].name, "chicken thighs")
        XCTAssertEqual(plan.mise[0].prep, "pat dry, season both sides")
        XCTAssertEqual(plan.mise[1].name, "garlic")
        XCTAssertEqual(plan.mise[1].prep, "mince")

        XCTAssertEqual(plan.equipment, ["large skillet", "tongs"])
        XCTAssertEqual(plan.steps.count, 2)

        let s1 = plan.steps[0]
        XCTAssertEqual(s1.id, "s1")
        XCTAssertEqual(s1.index, 0)
        XCTAssertEqual(s1.title, "Sear the chicken")
        XCTAssertEqual(s1.instruction, "Sear the chicken thighs 4 minutes per side until golden.")
        XCTAssertEqual(s1.kind, .active)
        XCTAssertEqual(s1.estimatedSeconds, 480)
        XCTAssertEqual(s1.timerSeconds, 240)
        XCTAssertEqual(s1.dependsOn, [])
        XCTAssertNil(s1.visualCheck)
        XCTAssertNil(s1.recovery)
        XCTAssertEqual(s1.ingredientNames, ["chicken thighs"])

        let s2 = plan.steps[1]
        XCTAssertEqual(s2.id, "s2")
        XCTAssertEqual(s2.index, 1)
        XCTAssertEqual(s2.title, "Check the browning")
        XCTAssertEqual(s2.instruction, "Flip and confirm a deep golden crust before adding the garlic.")
        XCTAssertEqual(s2.kind, .checkpoint)
        XCTAssertEqual(s2.estimatedSeconds, 60)
        XCTAssertNil(s2.timerSeconds)
        XCTAssertEqual(s2.dependsOn, ["s1"])
        XCTAssertEqual(s2.visualCheck, "Crust should be deep golden, not pale or burnt.")
        XCTAssertEqual(s2.recovery, "If pale, sear 2 more minutes; if burnt, lower the heat and scrape the pan.")
        XCTAssertEqual(s2.ingredientNames, ["chicken thighs", "garlic"])
    }

    // MARK: - Decoding: optional tolerance

    func testToleratesMinimalPayloadWithUnknownKind() throws {
        let json = """
        {"title":"x","steps":[{"id":"s1","index":0,"title":"t","instruction":"i","kind":"weird"}]}
        """
        let plan = try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8))

        XCTAssertEqual(plan.title, "x")
        XCTAssertEqual(plan.servings, 0, "missing servings defaults to 0")
        XCTAssertTrue(plan.mise.isEmpty, "missing mise defaults to []")
        XCTAssertTrue(plan.equipment.isEmpty, "missing equipment defaults to []")
        XCTAssertFalse(plan.isFallback, "missing isFallback defaults to false")

        let step = try XCTUnwrap(plan.steps.first)
        XCTAssertEqual(step.id, "s1")
        XCTAssertEqual(step.index, 0)
        XCTAssertEqual(step.title, "t")
        XCTAssertEqual(step.instruction, "i")
        XCTAssertEqual(step.kind, .active, "unknown kind string falls back to .active")
        XCTAssertNil(step.estimatedSeconds)
        XCTAssertNil(step.timerSeconds)
        XCTAssertTrue(step.dependsOn.isEmpty)
        XCTAssertNil(step.visualCheck)
        XCTAssertNil(step.recovery)
        XCTAssertTrue(step.ingredientNames.isEmpty)
    }

    // MARK: - Linear fallback

    func testLinearFallbackFromRecipeSteps() throws {
        let context = container.mainContext
        let recipe = Recipe(title: "Weeknight Ragu", servings: 2)
        recipe.ingredients = [
            RecipeIngredient(name: "ground beef", sortIndex: 0),
            RecipeIngredient(name: "onion", sortIndex: 1),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Brown the ground beef with the onion until no pink remains."),
            RecipeStep(index: 1, text: "Simmer the sauce gently, stirring occasionally.", durationSeconds: 300),
        ]
        context.insert(recipe)
        try context.save()

        let plan = CookPlan.linear(from: recipe, scale: 1.5)

        XCTAssertEqual(plan.title, "Weeknight Ragu")
        XCTAssertEqual(plan.servings, 3, "2 servings x 1.5 scale, rounded")
        XCTAssertTrue(plan.isFallback)
        XCTAssertTrue(plan.mise.isEmpty)
        XCTAssertTrue(plan.equipment.isEmpty)
        XCTAssertEqual(plan.steps.count, 2)

        let first = plan.steps[0]
        XCTAssertEqual(first.id, "s1")
        XCTAssertEqual(first.index, 0)
        XCTAssertEqual(first.title, "Brown the ground beef with the…", "first 6 words + ellipsis")
        XCTAssertEqual(first.instruction, "Brown the ground beef with the onion until no pink remains.")
        XCTAssertEqual(first.kind, .active, "no durationSeconds -> active")
        XCTAssertNil(first.estimatedSeconds)
        XCTAssertNil(first.timerSeconds)
        XCTAssertEqual(first.dependsOn, [])
        XCTAssertNil(first.visualCheck)
        XCTAssertNil(first.recovery)
        XCTAssertEqual(first.ingredientNames, ["ground beef", "onion"])

        let second = plan.steps[1]
        XCTAssertEqual(second.id, "s2")
        XCTAssertEqual(second.index, 1)
        XCTAssertEqual(second.title, "Simmer the sauce gently, stirring occasionally.", "6 words or fewer -> untruncated")
        XCTAssertEqual(second.kind, .passive, "durationSeconds -> passive")
        XCTAssertEqual(second.estimatedSeconds, 300)
        XCTAssertEqual(second.timerSeconds, 300)
        XCTAssertEqual(second.dependsOn, ["s1"])
        XCTAssertTrue(second.ingredientNames.isEmpty, "step text mentions no ingredient")
    }

    func testLinearFallbackClampsServingsToAtLeastOne() throws {
        let recipe = Recipe(title: "Tiny Batch", servings: 1)
        container.mainContext.insert(recipe)
        let plan = CookPlan.linear(from: recipe, scale: 0.25)
        XCTAssertEqual(plan.servings, 1, "max(1, rounded scaled servings)")
        XCTAssertTrue(plan.steps.isEmpty)
        XCTAssertTrue(plan.isFallback)
    }
}
```

Fixture rationale (deterministic on purpose): `ingredientsUsed(from:)` matches on `canonicalName` words longer than 2 chars appearing in the lowered step text. `IngredientCanonicalizer.canonicalize("ground beef")` strips the noise word "ground" → `"beef"`, which appears in step 1's text; `"onion"` canonicalizes to itself and also appears. Step 2's text contains neither, so its `ingredientNames` is empty. No network, no SwiftData models beyond the four listed in the Schema.

- [ ] **Step 2: Run the tests — expect compile failure**

Run `xcodegen generate` (Bash, from the repo root) so the new test file joins the `GluttTests` target. Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`. If this is the session's first XcodeBuildMCP call, call `session_show_defaults` first (project `Glutt.xcodeproj`, scheme `Glutt`, an iOS 17+ iPhone simulator).

Run tests: `test_sim` (scheme `Glutt`) — expected: FAIL — the test target does not compile: `cannot find 'CookPlan' in scope` in `CookPlanTests.swift`. This is the red step; do not proceed until you have seen this exact failure.

- [ ] **Step 3: Create PollyConfig.swift**

Create `Glutt/Services/Polly/PollyConfig.swift` with exactly this content:

```swift
import Foundation

/// Tuning knobs for Polly live sessions. Change these constants, not call sites.
enum PollyConfig {
    static let realtimeModel = "gpt-realtime-2"
    static let voice = "marin"
    /// Seconds between automatic camera frames while watch mode is on.
    static let watchFrameInterval: TimeInterval = 10
    /// Frames are downscaled so the longest side is at most this, then JPEG-compressed.
    static let frameMaxDimension: CGFloat = 1024
    static let frameJPEGQuality: CGFloat = 0.6
    /// OpenAI Realtime hard-caps sessions at 60 minutes; we end well before that.
    static let maxSessionMinutes = 52
    /// When Polly starts steering toward wrapping up.
    static let wrapUpWarningMinutes = 47
    /// How many top PollyMemory facts get injected into the system prompt.
    static let memoryFactLimit = 12
    /// Ephemeral token lifetime requested from the proxy (OpenAI max is 600).
    static let tokenTTLSeconds = 600
}
```

- [ ] **Step 4: Create CookPlan.swift**

Create `Glutt/Services/Polly/CookPlan.swift` with exactly this content. Note: it reuses `RecipeStep.ingredientsUsed(from:)`, the internal file-scope extension declared in `Glutt/Features/Cook/CookModeView.swift:328-340` — same target, no import or change needed there.

```swift
import Foundation

/// Compiled execution graph for one cook session. Produced by CookPlanCompiler
/// (one-shot LLM call, cached) or by the deterministic `linear(from:scale:)`
/// fallback when AI is unavailable — the session runs either way.
struct CookPlan: Codable, Equatable {
    enum StepKind: String, Codable {
        case prep, active, passive, checkpoint
    }

    struct MiseItem: Codable, Equatable {
        let name: String
        let prep: String
    }

    struct PlanStep: Codable, Equatable, Identifiable {
        let id: String
        let index: Int
        let title: String
        let instruction: String
        let kind: StepKind
        let estimatedSeconds: Int?
        let timerSeconds: Int?
        let dependsOn: [String]
        let visualCheck: String?
        let recovery: String?
        let ingredientNames: [String]

        init(
            id: String,
            index: Int,
            title: String,
            instruction: String,
            kind: StepKind,
            estimatedSeconds: Int? = nil,
            timerSeconds: Int? = nil,
            dependsOn: [String] = [],
            visualCheck: String? = nil,
            recovery: String? = nil,
            ingredientNames: [String] = []
        ) {
            self.id = id
            self.index = index
            self.title = title
            self.instruction = instruction
            self.kind = kind
            self.estimatedSeconds = estimatedSeconds
            self.timerSeconds = timerSeconds
            self.dependsOn = dependsOn
            self.visualCheck = visualCheck
            self.recovery = recovery
            self.ingredientNames = ingredientNames
        }

        // Optional-tolerant decoding (PlateCard pattern): the LLM may omit any
        // non-essential field. Arrays default to empty, scalars to nil, and an
        // unknown kind string degrades to .active instead of failing the plan.
        enum CodingKeys: String, CodingKey {
            case id, index, title, instruction, kind, estimatedSeconds
            case timerSeconds, dependsOn, visualCheck, recovery, ingredientNames
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            instruction = try c.decodeIfPresent(String.self, forKey: .instruction) ?? ""
            let kindRaw = try c.decodeIfPresent(String.self, forKey: .kind)
            kind = kindRaw.flatMap(StepKind.init(rawValue:)) ?? .active
            estimatedSeconds = try c.decodeIfPresent(Int.self, forKey: .estimatedSeconds)
            timerSeconds = try c.decodeIfPresent(Int.self, forKey: .timerSeconds)
            dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
            visualCheck = try c.decodeIfPresent(String.self, forKey: .visualCheck)
            recovery = try c.decodeIfPresent(String.self, forKey: .recovery)
            ingredientNames = try c.decodeIfPresent([String].self, forKey: .ingredientNames) ?? []
        }
    }

    let title: String
    let servings: Int
    let mise: [MiseItem]
    let equipment: [String]
    let steps: [PlanStep]
    /// True when this plan was built by `linear(from:scale:)` rather than the compiler.
    var isFallback: Bool

    init(
        title: String,
        servings: Int,
        mise: [MiseItem] = [],
        equipment: [String] = [],
        steps: [PlanStep] = [],
        isFallback: Bool = false
    ) {
        self.title = title
        self.servings = servings
        self.mise = mise
        self.equipment = equipment
        self.steps = steps
        self.isFallback = isFallback
    }

    enum CodingKeys: String, CodingKey {
        case title, servings, mise, equipment, steps, isFallback
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        servings = try c.decodeIfPresent(Int.self, forKey: .servings) ?? 0
        mise = try c.decodeIfPresent([MiseItem].self, forKey: .mise) ?? []
        equipment = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        steps = try c.decodeIfPresent([PlanStep].self, forKey: .steps) ?? []
        isFallback = try c.decodeIfPresent(Bool.self, forKey: .isFallback) ?? false
    }

    /// Deterministic no-AI fallback: one plan step per recipe step, in order,
    /// each depending on the previous. Steps with a detected timer become
    /// passive (Polly starts the timer); everything else is active.
    static func linear(from recipe: Recipe, scale: Double) -> CookPlan {
        let steps = recipe.sortedSteps.enumerated().map { offset, step in
            PlanStep(
                id: "s\(offset + 1)",
                index: offset,
                title: shortTitle(for: step.text),
                instruction: step.text,
                kind: step.durationSeconds != nil ? .passive : .active,
                estimatedSeconds: step.durationSeconds,
                timerSeconds: step.durationSeconds,
                dependsOn: offset == 0 ? [] : ["s\(offset)"],
                ingredientNames: step.ingredientsUsed(from: recipe.ingredients).map(\.name)
            )
        }
        return CookPlan(
            title: recipe.title,
            servings: max(1, Int((Double(recipe.servings) * scale).rounded())),
            steps: steps,
            isFallback: true
        )
    }

    /// First six words of the step text, with an ellipsis when truncated.
    private static func shortTitle(for text: String) -> String {
        let words = text.split(separator: " ")
        guard words.count > 6 else { return text }
        return words.prefix(6).joined(separator: " ") + "…"
    }
}
```

- [ ] **Step 5: Run the tests — expect green**

Run `xcodegen generate` (Bash, from the repo root) so the two new source files join the `Glutt` target. Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, includes `CookPlanTests/testDecodesFullCompilerContract`, `CookPlanTests/testToleratesMinimalPayloadWithUnknownKind`, `CookPlanTests/testLinearFallbackFromRecipeSteps`, `CookPlanTests/testLinearFallbackClampsServingsToAtLeastOne`, and all pre-existing suites still green.

- [ ] **Step 6: Commit**

```bash
git add Glutt.xcodeproj Glutt/Services/Polly/PollyConfig.swift Glutt/Services/Polly/CookPlan.swift GluttTests/CookPlanTests.swift
git commit -m "feat(polly): add CookPlan execution-graph model with linear fallback

PollyConfig centralizes the realtime tuning constants. CookPlan is the
Codable+Equatable cook execution graph with optional-tolerant decoding
(missing arrays -> [], unknown step kind -> .active, missing isFallback
-> false) and a deterministic linear(from:scale:) fallback built from
RecipeStep order, detected timers, and the existing ingredientsUsed
heuristic, so sessions run even when the compiler is unavailable.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9"
```

`Glutt.xcodeproj` is git-tracked and regenerated by `xcodegen generate`, so it is staged alongside the new files. Do not commit `project.yml` (untouched by this task).

---

### Task 3: PollyMemory + PollyCookLog models, schema registration, PollyMemoryStore

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Models/Polly.swift`
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyMemoryStore.swift`
- Modify: `/Users/omarlahmimi/Documents/Glutt/Glutt/App/GluttApp.swift` (the `Schema([...])` array, lines 48–60 — append `PollyMemory.self, PollyCookLog.self`)
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyMemoryStoreTests.swift`

**Interfaces:**
- Consumes: `Recipe` (existing `@Model`, `Glutt/Models/Recipe.swift` — `PollyCookLog.recipe` relationship target; `init(title:)` with defaults suffices in tests).
- Produces (later tasks depend on these exact signatures — Task 10 `remember_fact`, Task 11 prompt builder, Task 13 controller `end(...)`, Task 14 extractor `apply`, Task 16 tab memory card):

```swift
enum MemoryKind: String, Codable, CaseIterable {
    case equipment, technique, pantryHabit, preference, outcome
}
@Model final class PollyMemory {
    var kindRaw: String
    var text: String
    var confidence: Double
    var timesReinforced: Int
    var createdAt: Date
    var updatedAt: Date
    var sourceRecipeTitle: String?
    var kind: MemoryKind { get }   // MemoryKind(rawValue: kindRaw) ?? .outcome
    init(kind: MemoryKind, text: String, confidence: Double, sourceRecipeTitle: String?)
}
@Model final class PollyCookLog {
    var startedAt: Date
    var endedAt: Date?
    var recipe: Recipe?
    var summary: String
    var stepsCompleted: Int
    var stepsTotal: Int
    var substitutions: [String]
    var endedEarly: Bool
    init(startedAt: Date, recipe: Recipe?)
}
enum PollyMemoryStore {
    @discardableResult
    static func upsert(kind: MemoryKind, text: String, confidence: Double,
                       sourceRecipeTitle: String?, in context: ModelContext) -> PollyMemory
    static func topFacts(limit: Int, in context: ModelContext) -> [PollyMemory]
}
```

Both models MUST be added to the `Schema` in `GluttApp.swift` and to every in-memory test container that touches them (`PollyCookLog` pulls in the `Recipe` graph: `Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self`).

- [ ] **Step 1: Write the failing test file**

Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyMemoryStoreTests.swift` with exactly:

```swift
import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PollyMemoryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // PollyCookLog references Recipe, so the whole Recipe graph rides along.
        let schema = Schema([
            PollyMemory.self, PollyCookLog.self,
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    override func tearDownWithError() throws { container = nil; try super.tearDownWithError() }

    // MARK: - upsert

    func testUpsertInsertsNewFact() throws {
        let memory = PollyMemoryStore.upsert(
            kind: .equipment, text: "Owns a cast iron skillet", confidence: 0.8,
            sourceRecipeTitle: "Smash Burgers", in: context
        )
        XCTAssertEqual(memory.kind, .equipment)
        XCTAssertEqual(memory.kindRaw, "equipment")
        XCTAssertEqual(memory.timesReinforced, 1)
        XCTAssertEqual(memory.confidence, 0.8)
        XCTAssertEqual(memory.sourceRecipeTitle, "Smash Burgers")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PollyMemory>()).count, 1)
    }

    func testNearDuplicateSameKindReinforcesInsteadOfDuplicating() throws {
        // Word sets: {chops, onions, slowly} vs {chops, onions, slowly, and, carefully}
        // -> Jaccard 3/5 = 0.6, at the threshold, so it must reinforce.
        let original = PollyMemoryStore.upsert(
            kind: .technique, text: "chops onions slowly", confidence: 0.5,
            sourceRecipeTitle: nil, in: context
        )
        let updatedAtBefore = original.updatedAt

        let result = PollyMemoryStore.upsert(
            kind: .technique, text: "Chops onions slowly and carefully", confidence: 0.9,
            sourceRecipeTitle: "French Onion Soup", in: context
        )

        XCTAssertEqual(result.persistentModelID, original.persistentModelID, "should reinforce, not insert")
        XCTAssertEqual(result.timesReinforced, 2)
        XCTAssertEqual(result.confidence, 0.9, "confidence takes the max of old and new")
        XCTAssertEqual(result.text, "Chops onions slowly and carefully", "keeps the longer text")
        XCTAssertGreaterThanOrEqual(result.updatedAt, updatedAtBefore)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PollyMemory>()).count, 1)
    }

    func testDistinctTextSameKindInsertsSecondRow() throws {
        // Word sets share nothing -> Jaccard 0 -> new row.
        PollyMemoryStore.upsert(kind: .equipment, text: "Owns a cast iron skillet",
                                confidence: 0.8, sourceRecipeTitle: nil, in: context)
        PollyMemoryStore.upsert(kind: .equipment, text: "Stove runs hot on medium",
                                confidence: 0.7, sourceRecipeTitle: nil, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PollyMemory>()).count, 2)
    }

    func testSameTextDifferentKindInsertsTwoRows() throws {
        PollyMemoryStore.upsert(kind: .equipment, text: "Owns a rice cooker",
                                confidence: 0.8, sourceRecipeTitle: nil, in: context)
        PollyMemoryStore.upsert(kind: .preference, text: "Owns a rice cooker",
                                confidence: 0.8, sourceRecipeTitle: nil, in: context)
        let all = try context.fetch(FetchDescriptor<PollyMemory>())
        XCTAssertEqual(all.count, 2, "dedup only applies within the same kind")
        XCTAssertEqual(all.allSatisfy { $0.timesReinforced == 1 }, true)
    }

    // MARK: - topFacts

    func testTopFactsOrdersByReinforcementThenRecencyAndAppliesLimit() throws {
        let wok = PollyMemory(kind: .equipment, text: "Owns a wok", confidence: 0.7, sourceRecipeTitle: nil)
        wok.timesReinforced = 3
        wok.updatedAt = Date(timeIntervalSince1970: 1_000)
        let heat = PollyMemory(kind: .technique, text: "Prefers medium heat", confidence: 0.6, sourceRecipeTitle: nil)
        heat.timesReinforced = 1
        heat.updatedAt = Date(timeIntervalSince1970: 3_000)
        let rice = PollyMemory(kind: .outcome, text: "Rice came out sticky last time", confidence: 0.5, sourceRecipeTitle: nil)
        rice.timesReinforced = 1
        rice.updatedAt = Date(timeIntervalSince1970: 2_000)
        context.insert(wok)
        context.insert(heat)
        context.insert(rice)

        let top2 = PollyMemoryStore.topFacts(limit: 2, in: context)
        XCTAssertEqual(top2.map(\.text), ["Owns a wok", "Prefers medium heat"],
                       "timesReinforced desc, then updatedAt desc")

        let all = PollyMemoryStore.topFacts(limit: 10, in: context)
        XCTAssertEqual(all.count, 3, "limit beyond the row count returns everything")
    }

    // MARK: - Model behavior

    func testGarbageKindRawFallsBackToOutcome() {
        let memory = PollyMemory(kind: .equipment, text: "Owns a blender", confidence: 0.5, sourceRecipeTitle: nil)
        memory.kindRaw = "vibes"
        XCTAssertEqual(memory.kind, .outcome)
    }

    func testCookLogInitDefaultsAndRecipeRelationship() throws {
        let recipe = Recipe(title: "Shakshuka")
        context.insert(recipe)
        let log = PollyCookLog(startedAt: Date(timeIntervalSince1970: 500), recipe: recipe)
        context.insert(log)

        XCTAssertEqual(log.startedAt, Date(timeIntervalSince1970: 500))
        XCTAssertNil(log.endedAt)
        XCTAssertEqual(log.summary, "")
        XCTAssertEqual(log.stepsCompleted, 0)
        XCTAssertEqual(log.stepsTotal, 0)
        XCTAssertEqual(log.substitutions, [])
        XCTAssertFalse(log.endedEarly)
        XCTAssertEqual(log.recipe?.title, "Shakshuka")
    }
}
```

- [ ] **Step 2: Regenerate the project so the new test file is compiled**

Run `xcodegen generate` via Bash in `/Users/omarlahmimi/Documents/Glutt` — XcodeGen bakes file lists into `Glutt.xcodeproj`, so every new `.swift` file needs a regeneration even under globbed folders. Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 3: Run tests — confirm the failure**

Run tests: `test_sim` (scheme `Glutt`) — expected: FAIL. The `GluttTests` target does not compile: `cannot find 'PollyMemory' in scope` / `cannot find 'PollyMemoryStore' in scope` in `PollyMemoryStoreTests.swift`.

- [ ] **Step 4: Create the models file**

Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Models/Polly.swift` with exactly:

```swift
import Foundation
import SwiftData

/// What kind of kitchen fact Polly learned about the user.
enum MemoryKind: String, Codable, CaseIterable {
    case equipment, technique, pantryHabit, preference, outcome
}

/// A durable fact Polly learned during a cook ("stove runs hot", "owns cast
/// iron"). Facts are reinforced across cooks instead of duplicated — see
/// `PollyMemoryStore.upsert`. Schema is shaped to sync to Postgres later.
@Model
final class PollyMemory {
    /// `MemoryKind.rawValue`, stored raw so an unknown value written by a
    /// future app version still loads (the computed `kind` falls back).
    var kindRaw: String
    var text: String
    /// 0.0–1.0 confidence in the fact.
    var confidence: Double
    /// How many times separate cooks confirmed this fact.
    var timesReinforced: Int
    var createdAt: Date
    var updatedAt: Date
    /// Title of the recipe being cooked when the fact was first learned.
    var sourceRecipeTitle: String?

    var kind: MemoryKind { MemoryKind(rawValue: kindRaw) ?? .outcome }

    init(kind: MemoryKind, text: String, confidence: Double, sourceRecipeTitle: String?) {
        self.kindRaw = kind.rawValue
        self.text = text
        self.confidence = confidence
        self.timesReinforced = 1
        self.createdAt = .now
        self.updatedAt = .now
        self.sourceRecipeTitle = sourceRecipeTitle
    }
}

/// One Polly session's outcome record, written when the session ends.
/// Distinct from `CookSession` (the user's own rating/leftovers log):
/// this captures what Polly saw — progress, substitutions, and a summary.
@Model
final class PollyCookLog {
    var startedAt: Date
    var endedAt: Date?
    var recipe: Recipe?
    var summary: String
    var stepsCompleted: Int
    var stepsTotal: Int
    var substitutions: [String]
    var endedEarly: Bool

    init(startedAt: Date, recipe: Recipe?) {
        self.startedAt = startedAt
        self.recipe = recipe
        self.summary = ""
        self.stepsCompleted = 0
        self.stepsTotal = 0
        self.substitutions = []
        self.endedEarly = false
    }
}
```

- [ ] **Step 5: Create the memory store**

Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyMemoryStore.swift` with exactly:

```swift
import Foundation
import SwiftData

/// Write/read chokepoint over `PollyMemory`. All writes go through `upsert`,
/// which reinforces an existing near-duplicate fact (same kind, fuzzy text
/// match) instead of inserting a new row — memories get stronger, not noisier.
/// Callers own saving the context.
enum PollyMemoryStore {
    /// Two texts describe "the same fact" when the Jaccard index of their
    /// lowercased word sets is at least this.
    private static let duplicateThreshold = 0.6

    @discardableResult
    static func upsert(
        kind: MemoryKind,
        text: String,
        confidence: Double,
        sourceRecipeTitle: String?,
        in context: ModelContext
    ) -> PollyMemory {
        let raw = kind.rawValue
        let descriptor = FetchDescriptor<PollyMemory>(
            predicate: #Predicate { $0.kindRaw == raw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let sameKind = (try? context.fetch(descriptor)) ?? []
        let newWords = words(in: text)

        if let existing = sameKind.first(where: { jaccard(words(in: $0.text), newWords) >= duplicateThreshold }) {
            existing.timesReinforced += 1
            existing.confidence = max(existing.confidence, confidence)
            existing.updatedAt = .now
            if text.count > existing.text.count {
                existing.text = text
            }
            return existing
        }

        let memory = PollyMemory(kind: kind, text: text, confidence: confidence, sourceRecipeTitle: sourceRecipeTitle)
        context.insert(memory)
        return memory
    }

    /// Strongest facts first: most-reinforced, then most recently updated.
    static func topFacts(limit: Int, in context: ModelContext) -> [PollyMemory] {
        let descriptor = FetchDescriptor<PollyMemory>(sortBy: [
            SortDescriptor(\.timesReinforced, order: .reverse),
            SortDescriptor(\.updatedAt, order: .reverse),
        ])
        let all = (try? context.fetch(descriptor)) ?? []
        return Array(all.prefix(limit))
    }

    // MARK: - Fuzzy match

    /// Lowercased alphanumeric word set: "My stove runs HOT!" ->
    /// {"my", "stove", "runs", "hot"}.
    private static func words(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b)
        guard !union.isEmpty else { return 1 } // two empty texts are the same fact
        return Double(a.intersection(b).count) / Double(union.count)
    }
}
```

- [ ] **Step 6: Register both models in the app schema**

Modify `/Users/omarlahmimi/Documents/Glutt/Glutt/App/GluttApp.swift` (lines 48–60). Before:

```swift
    let container: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            RecipeCollection.self,
            PantryItem.self,
            GroceryItem.self,
            Leftover.self,
            PlannedMeal.self,
            FoodLog.self,
            CookSession.self,
            UserPrefs.self,
        ])
```

After:

```swift
    let container: ModelContainer = {
        let schema = Schema([
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            RecipeCollection.self,
            PantryItem.self,
            GroceryItem.self,
            Leftover.self,
            PlannedMeal.self,
            FoodLog.self,
            CookSession.self,
            UserPrefs.self,
            PollyMemory.self,
            PollyCookLog.self,
        ])
```

- [ ] **Step 7: Regenerate the project so the two new source files are compiled**

Run `xcodegen generate` via Bash in `/Users/omarlahmimi/Documents/Glutt` (picks up `Glutt/Models/Polly.swift` and `Glutt/Services/Polly/PollyMemoryStore.swift`; if Task 2 has not run yet, this is also the first file in the new `Glutt/Services/Polly/` folder). Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 8: Run tests — confirm green**

Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, includes `testUpsertInsertsNewFact`, `testNearDuplicateSameKindReinforcesInsteadOfDuplicating`, `testDistinctTextSameKindInsertsSecondRow`, `testSameTextDifferentKindInsertsTwoRows`, `testTopFactsOrdersByReinforcementThenRecencyAndAppliesLimit`, `testGarbageKindRawFallsBackToOutcome`, `testCookLogInitDefaultsAndRecipeRelationship`, plus the pre-existing suite (no regressions — the schema change is additive, so the on-disk store migrates in place).

- [ ] **Step 9: Commit**

```bash
git add Glutt/Models/Polly.swift Glutt/Services/Polly/PollyMemoryStore.swift Glutt/App/GluttApp.swift GluttTests/PollyMemoryStoreTests.swift Glutt.xcodeproj
git commit -m "$(cat <<'EOF'
feat(polly): add on-device kitchen memory models and dedup store

PollyMemory (kind stored raw with .outcome fallback) and PollyCookLog
join the app schema; PollyMemoryStore reinforces near-duplicate facts
(same kind, Jaccard word overlap >= 0.6 -> bump timesReinforced, take
max confidence and the longer text) instead of inserting noise, and
serves topFacts ordered by reinforcement then recency.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
EOF
)"
```

---

### Task 4: PollyTokenService (ephemeral realtime token mint)

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyTokenService.swift` (contains both `PollySessionToken` and `PollyTokenService` — the file map in Shared Contracts lists a single file for this task)
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyTokenServiceTests.swift` (new file)

**Interfaces:**

Consumes (existing, `Glutt/Services/AI/Secrets.swift` lines 9 & 13):
```swift
Secrets.aiProxyBaseURL: String    // "https://glutt-sable.vercel.app/api"
Secrets.aiProxyClientKey: String  // shared proxy key, proxy auth only
```

Produces (exact Shared Contracts signatures; Task 5 serves the wire shape, Task 13's `PollySessionController.Dependencies.mintToken: () async throws -> PollySessionToken` consumes `mint()`):
```swift
struct PollySessionToken: Decodable, Equatable {
    let value: String              // "ek_..."
    let expiresAt: Int?            // unix seconds, wire key "expiresAt"
    let model: String
    let voice: String
}
enum PollyTokenError: LocalizedError, Equatable { case notConfigured, badResponse(String) }
struct PollyTokenService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    // memberwise init(transport:baseURL:clientKey:) with live defaults (Plates pattern)
    func mint() async throws -> PollySessionToken   // POST {baseURL}/polly/session
    static let live: PollyTokenService
}
```

This is a pure networking unit in the `PlatesService` house style (`Transport` closure DI, trimmed `Secrets` defaults, 20 s timeout, typed `LocalizedError`). No SwiftData, no `PollyConfig` dependency — the proxy (Task 5) decides model/voice/TTL; the client just decodes what it is given. Tests use a fake transport: no network.

- [ ] **Step 1: Write the failing test file**

  Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyTokenServiceTests.swift` with exactly this content (style copied from `GluttTests/PlatesServiceTests.swift`):

  ```swift
  import XCTest
  @testable import Glutt

  final class PollyTokenServiceTests: XCTestCase {
      private func ok(_ json: String, url: URL) -> (Data, URLResponse) {
          (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
      }

      private let tokenJSON = #"{"value":"ek_abc","expiresAt":1751500000,"model":"gpt-realtime-2","voice":"marin"}"#

      func testMintBuildsRequestAndDecodes() async throws {
          var captured: URLRequest?
          let service = PollyTokenService(
              transport: { req in
                  captured = req
                  return self.ok(self.tokenJSON, url: req.url!)
              },
              baseURL: "https://example.test/api",
              clientKey: "secret-key"
          )
          let token = try await service.mint()
          XCTAssertEqual(
              token,
              PollySessionToken(value: "ek_abc", expiresAt: 1_751_500_000, model: "gpt-realtime-2", voice: "marin")
          )
          let request = try XCTUnwrap(captured)
          XCTAssertTrue(try XCTUnwrap(request.url).absoluteString.hasSuffix("/polly/session"))
          XCTAssertEqual(request.httpMethod, "POST")
          XCTAssertEqual(request.value(forHTTPHeaderField: "x-glutt-proxy-key"), "secret-key")
          XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
          XCTAssertEqual(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8), "{}")
      }

      func testNon2xxThrowsBadResponse() async {
          let service = PollyTokenService(
              transport: { req in
                  (Data("boom".utf8), HTTPURLResponse(url: req.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!)
              },
              baseURL: "https://example.test/api",
              clientKey: "k"
          )
          do { _ = try await service.mint(); XCTFail("expected throw") }
          catch let PollyTokenError.badResponse(detail) { XCTAssertTrue(detail.contains("502")) }
          catch { XCTFail("wrong error: \(error)") }
      }

      func testMissingValueKeyThrowsBadResponse() async {
          let service = PollyTokenService(
              transport: { req in
                  self.ok(#"{"expiresAt":1751500000,"model":"gpt-realtime-2","voice":"marin"}"#, url: req.url!)
              },
              baseURL: "https://example.test/api",
              clientKey: "k"
          )
          do { _ = try await service.mint(); XCTFail("expected throw") }
          catch let PollyTokenError.badResponse(detail) { XCTAssertEqual(detail, "Unexpected response shape") }
          catch { XCTFail("wrong error: \(error)") }
      }

      func testEmptyBaseURLThrowsNotConfigured() async {
          let service = PollyTokenService(transport: { _ in (Data(), URLResponse()) }, baseURL: "", clientKey: "")
          do { _ = try await service.mint(); XCTFail("expected throw") }
          catch PollyTokenError.notConfigured {} catch { XCTFail("wrong error: \(error)") }
      }
  }
  ```

- [ ] **Step 2: Regenerate the Xcode project**

  New files only enter targets via XcodeGen. Run:
  ```bash
  cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate
  ```
  Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 3: Run tests — confirm they fail for the right reason**

  If this is the session's first build/test call, call `session_show_defaults` first (confirm project `Glutt.xcodeproj`, scheme `Glutt`, an iOS 17+ simulator; set with `session_set_defaults` if missing).

  Run tests: `test_sim` (scheme Glutt) — expected: FAIL — the `GluttTests` target does not compile, with errors on `PollyTokenServiceTests.swift` such as `cannot find 'PollyTokenService' in scope` and `cannot find 'PollySessionToken' in scope`. Any other kind of failure means Step 1 was mistyped; fix before proceeding.

- [ ] **Step 4: Minimal implementation**

  Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyTokenService.swift` with exactly this content (the `Glutt/Services/Polly/` folder already exists from Task 2; creating the file first is fine either way — XcodeGen picks it up in Step 5):

  ```swift
  import Foundation

  /// The short-lived OpenAI Realtime credential minted by the Glutt proxy.
  /// Wire shape from `POST {proxy}/polly/session`:
  /// `{"value": "ek_...", "expiresAt": 1751500000, "model": "...", "voice": "..."}`.
  struct PollySessionToken: Decodable, Equatable {
      let value: String              // "ek_..."
      let expiresAt: Int?            // unix seconds
      let model: String
      let voice: String
  }

  enum PollyTokenError: LocalizedError, Equatable {
      case notConfigured
      case badResponse(String)

      var errorDescription: String? {
          switch self {
          case .notConfigured: "Polly isn't available in this build."
          case .badResponse(let detail): "Couldn't start a Polly session: \(detail)"
          }
      }
  }

  /// Mints ephemeral Realtime tokens from the Glutt proxy's `/polly/session`
  /// endpoint. Mirrors `PlatesService`'s transport + auth, with an injectable
  /// `transport` so it is testable. The committed proxy key authenticates this
  /// call only; the token it returns is the sole credential the socket sees.
  struct PollyTokenService {
      typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

      var transport: Transport = { try await URLSession.shared.data(for: $0) }
      var baseURL: String = Secrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
      var clientKey: String = Secrets.aiProxyClientKey.trimmingCharacters(in: .whitespacesAndNewlines)

      static let live = PollyTokenService()

      func mint() async throws -> PollySessionToken {
          guard !baseURL.isEmpty else { throw PollyTokenError.notConfigured }
          guard let url = URL(string: "\(baseURL)/polly/session") else {
              throw PollyTokenError.badResponse("Bad URL")
          }

          var request = URLRequest(url: url, timeoutInterval: 20)
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          request.httpBody = Data("{}".utf8)
          if !clientKey.isEmpty {
              request.setValue(clientKey, forHTTPHeaderField: "x-glutt-proxy-key")
          }

          let (data, response) = try await transport(request)
          guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
              let code = (response as? HTTPURLResponse)?.statusCode ?? -1
              throw PollyTokenError.badResponse("HTTP \(code)")
          }
          do {
              return try JSONDecoder().decode(PollySessionToken.self, from: data)
          } catch {
              throw PollyTokenError.badResponse("Unexpected response shape")
          }
      }
  }
  ```

  Notes on why this satisfies the contract exactly:
  - The `var` properties with default values give the struct the memberwise `init(transport:baseURL:clientKey:)` with live defaults — the exact init the contract specifies and the tests call.
  - Plain `JSONDecoder()` with no key strategy: the wire key `expiresAt` maps 1:1 onto the property, and `expiresAt: Int?` tolerates its absence while a missing `value`/`model`/`voice` throws, which `mint()` maps to `.badResponse("Unexpected response shape")`.
  - No query items are needed, so a plain `URL(string:)` replaces Plates' `URLComponents` dance; guard failure maps to `.badResponse("Bad URL")` like `PlatesService.get`.

- [ ] **Step 5: Regenerate the Xcode project again**

  ```bash
  cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate
  ```
  Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 6: Run tests — confirm green**

  Run tests: `test_sim` (scheme Glutt) — expected: PASS, includes `PollyTokenServiceTests/testMintBuildsRequestAndDecodes`, `PollyTokenServiceTests/testNon2xxThrowsBadResponse`, `PollyTokenServiceTests/testMissingValueKeyThrowsBadResponse`, `PollyTokenServiceTests/testEmptyBaseURLThrowsNotConfigured`, with all pre-existing suites still passing.

- [ ] **Step 7: Commit**

  ```bash
  git -C /Users/omarlahmimi/Documents/Glutt add Glutt.xcodeproj Glutt/Services/Polly/PollyTokenService.swift GluttTests/PollyTokenServiceTests.swift
  git -C /Users/omarlahmimi/Documents/Glutt commit -m "$(cat <<'EOF'
  feat(polly): add ephemeral realtime token service

  PollyTokenService POSTs {} to {proxy}/polly/session with the shared proxy
  key and 20s timeout, decoding {value, expiresAt, model, voice} into
  PollySessionToken. Plates-style Transport closure DI; notConfigured when
  the proxy base URL is empty, badResponse for non-2xx and decode failures.
  Covered by four fake-transport tests (request shape, happy path, 502,
  malformed body, unconfigured build).

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
  EOF
  )"
  ```

---

### Task 5: Vercel proxy endpoint `api/polly/session.js`

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/vercel-ai-proxy/api/polly/session.js`
- Modify: `/Users/omarlahmimi/Documents/Glutt/vercel-ai-proxy/api/health.js` (insert two `has_*` flags inside the `env` object, after line 12 `has_SPOONACULAR_API_KEY`, before line 13 `node_env`)
- Test: none in JS — `vercel-ai-proxy/` has no test runner (no `package.json`, no npm deps by design). The Swift decode tests in Task 4 (`GluttTests/PollyTokenServiceTests.swift`) are the contract test for this endpoint's response shape; this task re-runs them as a cross-check.

**Interfaces:**
- Consumes:
  - Env vars: `OPENAI_API_KEY` with fallbacks `glutt_proxy_prod`, `GLUTT_PROXY_PROD` (identical resolution to `api/chat/completions.js` lines 1–8); `GLUTT_PROXY_CLIENT_KEY` (gate — unset means gate disabled, same semantics as `api/plates/deck.js` lines 87–97); optional `POLLY_REALTIME_MODEL` (default `"gpt-realtime-2"`), optional `POLLY_VOICE` (default `"marin"`).
  - Upstream: `POST https://api.openai.com/v1/realtime/client_secrets` with `Authorization: Bearer <OPENAI_API_KEY>` (protocol reference in the plan preamble).
- Produces (the HTTP contract Task 4's `PollyTokenService.mint() async throws -> PollySessionToken` decodes):
  - `POST {Secrets.aiProxyBaseURL}/polly/session` → `200 {"value": "ek_...", "expiresAt": <unix seconds or null>, "model": "<model used>", "voice": "<voice used>"}` — exactly the wire keys of `PollySessionToken` (`value`, `expiresAt`, `model`, `voice`).
  - Response headers on every response: `x-glutt-proxy-version: polly-2026-07-02-1`; on 200 additionally `Cache-Control: no-store`.
  - Errors: `405 {"error": "Method not allowed"}` + `Allow: POST` header; `401 {"error": "Unauthorized"}`; `500 {"error": "not configured"}` (missing OpenAI key); `502 {"error": "upstream <status>"}` (upstream non-2xx, body never forwarded); `502 {"error": "upstream unreachable"}` (fetch threw).

- [ ] **Step 1: Create the endpoint file**

  No failing-test-first here — there is deliberately no JS runner in `vercel-ai-proxy/` (plain fetch, no npm deps, per the plan's tech stack). The contract test lives in Swift (Task 4) and is run in Step 4. Create `/Users/omarlahmimi/Documents/Glutt/vercel-ai-proxy/api/polly/session.js` with exactly this content:

  ```js
  // Polly: mints short-lived OpenAI Realtime client secrets ("ek_...") so the
  // app can open a Realtime WebSocket without ever seeing the long-lived
  // OPENAI_API_KEY. Secrets expire after 10 minutes (PollyConfig.tokenTTLSeconds);
  // the socket itself may live up to 60.

  function resolveOpenAIKey() {
    return (
      process.env.OPENAI_API_KEY ||
      process.env.glutt_proxy_prod ||
      process.env.GLUTT_PROXY_PROD ||
      ""
    ).trim();
  }

  export default async function handler(req, res) {
    res.setHeader("x-glutt-proxy-version", "polly-2026-07-02-1");

    if (req.method !== "POST") {
      res.setHeader("Allow", "POST");
      return res.status(405).json({ error: "Method not allowed" });
    }

    const openAIKey = resolveOpenAIKey();
    const expectedProxyKey = process.env.GLUTT_PROXY_CLIENT_KEY || "";

    if (!openAIKey) {
      return res.status(500).json({ error: "not configured" });
    }

    if (expectedProxyKey) {
      const incomingKey = req.headers["x-glutt-proxy-key"] || "";
      if (incomingKey !== expectedProxyKey) {
        return res.status(401).json({ error: "Unauthorized" });
      }
    }

    const model = (process.env.POLLY_REALTIME_MODEL || "").trim() || "gpt-realtime-2";
    const voice = (process.env.POLLY_VOICE || "").trim() || "marin";

    try {
      const upstream = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${openAIKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          expires_after: { anchor: "created_at", seconds: 600 },
          session: {
            type: "realtime",
            model,
            audio: { output: { voice } },
          },
        }),
      });

      if (!upstream.ok) {
        // Never forward the upstream body: it can echo key/request details.
        return res.status(502).json({ error: `upstream ${upstream.status}` });
      }

      const data = await upstream.json();
      res.setHeader("Cache-Control", "no-store");
      return res.status(200).json({
        value: data.value,
        expiresAt: data.expires_at ?? null,
        model,
        voice,
      });
    } catch {
      return res.status(502).json({ error: "upstream unreachable" });
    }
  }
  ```

  Notes locking this to the shared contracts: the request body is byte-for-byte the "Token mint (proxy-side)" shape from the plan's protocol reference (`expires_after.anchor = "created_at"`, `seconds = 600`, `session.type = "realtime"`, nested `audio.output.voice`). The 200 body keys `value` / `expiresAt` / `model` / `voice` are exactly `PollySessionToken`'s decoding keys from Task 4. No new file needs `xcodegen generate` — this folder is not part of the Xcode project.

- [ ] **Step 2: Syntax-check the new handler locally (deterministic, no network)**

  Run with Bash:
  ```bash
  node --check /Users/omarlahmimi/Documents/Glutt/vercel-ai-proxy/api/polly/session.js
  ```
  Expected: exit 0, no output. (`node --check` parses ESM `.js` fine here because it only validates syntax; if your local Node rejects `export default` in a bare `.js` check, run `node --input-type=module --check < /Users/omarlahmimi/Documents/Glutt/vercel-ai-proxy/api/polly/session.js` instead — same expected result: exit 0.)

- [ ] **Step 3: Add the Polly env flags to `api/health.js`**

  `health.js` exposes one `has_*` boolean per env key, so add the two Polly-tunable keys in the same style. In `/Users/omarlahmimi/Documents/Glutt/vercel-ai-proxy/api/health.js`, change:

  Before (lines 12–13):
  ```js
        has_SPOONACULAR_API_KEY: Boolean((process.env.SPOONACULAR_API_KEY || "").trim()),
        node_env: process.env.NODE_ENV || "unknown",
  ```

  After:
  ```js
        has_SPOONACULAR_API_KEY: Boolean((process.env.SPOONACULAR_API_KEY || "").trim()),
        has_POLLY_REALTIME_MODEL: Boolean((process.env.POLLY_REALTIME_MODEL || "").trim()),
        has_POLLY_VOICE: Boolean((process.env.POLLY_VOICE || "").trim()),
        node_env: process.env.NODE_ENV || "unknown",
  ```

  (No `has_` flag for the OpenAI key is needed — `has_OPENAI_API_KEY` already exists on line 6. `POLLY_REALTIME_MODEL` and `POLLY_VOICE` are optional overrides, so `false` here is a healthy state, not an error.)

  Then syntax-check it the same way:
  ```bash
  node --check /Users/omarlahmimi/Documents/Glutt/vercel-ai-proxy/api/health.js
  ```
  Expected: exit 0, no output.

- [ ] **Step 4: Cross-check the response contract against the Swift decode tests**

  Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, includes all `PollyTokenServiceTests` tests from Task 4 (they decode the exact `{"value", "expiresAt", "model", "voice"}` body this endpoint emits, plus the 401/500 error paths via the stubbed `Transport`). No Swift source changed in this task, so this run is a regression gate only.

- [ ] **Step 5: Commit**

  ```bash
  git add vercel-ai-proxy/api/polly/session.js vercel-ai-proxy/api/health.js
  git commit -m "$(cat <<'EOF'
  feat(polly): add realtime client-secret mint endpoint to the proxy

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
  EOF
  )"
  ```

- [ ] **Step 6: Verify the deployed endpoint (requires deployment — skip locally)**

  This step can only run after `vercel-ai-proxy/` is deployed (the same pending founder-side deploy as Plates; see the launch checklist in the spec). Do NOT block the plan on it — mark it skipped if the deploy has not happened, and record it as follow-up. Once deployed to the base URL the app uses (`Secrets.aiProxyBaseURL` = `https://glutt-sable.vercel.app/api`):

  1. Wrong method →
     ```bash
     curl -si https://glutt-sable.vercel.app/api/polly/session
     ```
     Expected: `HTTP/2 405`, headers include `allow: POST` and `x-glutt-proxy-version: polly-2026-07-02-1`, body `{"error":"Method not allowed"}`.

  2. Gate rejects a missing/wrong key (only when `GLUTT_PROXY_CLIENT_KEY` is set in Vercel) →
     ```bash
     curl -si -X POST https://glutt-sable.vercel.app/api/polly/session
     ```
     Expected: `HTTP/2 401`, body `{"error":"Unauthorized"}`.

  3. Happy path (replace `<key>` with the value of `Secrets.aiProxyClientKey` from `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/AI/Secrets.swift`) →
     ```bash
     curl -si -X POST -H "x-glutt-proxy-key: <key>" https://glutt-sable.vercel.app/api/polly/session
     ```
     Expected: `HTTP/2 200`, headers include `cache-control: no-store` and `x-glutt-proxy-version: polly-2026-07-02-1`, body shaped like
     ```json
     {"value":"ek_abc123...","expiresAt":1751444400,"model":"gpt-realtime-2","voice":"marin"}
     ```
     (`value` starts with `ek_`; `expiresAt` is a unix-seconds integer ~600 s in the future, or `null` if upstream omits it. If Vercel is missing `OPENAI_API_KEY`, this returns `500 {"error":"not configured"}` instead — that is an env-var problem, not a code problem.)

  4. Health flags →
     ```bash
     curl -s https://glutt-sable.vercel.app/api/health
     ```
     Expected: the `env` object now contains `"has_POLLY_REALTIME_MODEL"` and `"has_POLLY_VOICE"` keys (both `false` is fine — the code defaults to `gpt-realtime-2` / `marin`).

---

### Task 6: Realtime event codec (RealtimeEvent.swift)

The pure JSON codec between Swift and the OpenAI Realtime GA wire protocol. No networking, no audio — just `RealtimeClientEvent.encoded()` producing the exact GA JSON shapes from the protocol reference in the plan preamble, and `RealtimeServerEvent.decode(_:)` mapping server frames onto the contract enum (never throwing; anything unparseable becomes `.unhandled`). Task 7 (transport), Task 10 (tool registry) and Task 13 (session controller) all build on these types.

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/RealtimeEvent.swift` (folder already exists from Task 2's `PollyConfig.swift`)
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/RealtimeEventCodecTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks. The GA constants (`rate: 24000`, `semantic_vad`, `gpt-4o-transcribe`, `retention_ratio 0.8`, `post_instructions 16000`) are inlined per the protocol reference; `PollyConfig.voice` / `PollyConfig.realtimeModel` flow in through `RealtimeSessionConfig` fields set by callers, not referenced here.
- Produces (exact shared-contract signatures; Task 7/10/13 depend on all of them):
  ```swift
  enum JSONValue: Codable, Equatable {
      case string(String), number(Double), bool(Bool), null
      case array([JSONValue]), object([String: JSONValue])
      var jsonObject: Any { get }   // JSONSerialization bridge (helper, used internally + by tests)
  }
  struct RealtimeToolDefinition: Encodable, Equatable {
      let type = "function"; let name: String; let description: String
      let parameters: JSONValue
  }
  struct RealtimeSessionConfig: Equatable {   // Equatable required so RealtimeClientEvent can synthesize ==
      var instructions: String; var tools: [RealtimeToolDefinition]
      var voice: String; var model: String; var transcribeInput: Bool
  }
  struct RealtimeFunctionCall: Equatable { let name: String; let callId: String; let argumentsJSON: String }
  enum RealtimeClientEvent: Equatable {
      case sessionUpdate(RealtimeSessionConfig)
      case appendAudio(base64: String)
      case createUserText(String)
      case createUserImage(dataURI: String, itemId: String?)
      case createFunctionOutput(callId: String, output: String)
      case deleteItem(itemId: String)
      case responseCreate
      case responseCancel
      case truncateItem(itemId: String, audioEndMs: Int)
      func encoded() throws -> Data
  }
  enum RealtimeServerEvent: Equatable {
      case sessionCreated, sessionUpdated, speechStarted, speechStopped
      case inputTranscript(String)
      case outputAudioDelta(itemId: String, base64: String)
      case outputTranscriptDelta(itemId: String, delta: String)
      case responseDone(status: String, calls: [RealtimeFunctionCall])
      case responseCancelled
      case error(code: String?, message: String)
      case unhandled(type: String)
      static func decode(_ data: Data) -> RealtimeServerEvent
  }
  ```

- [ ] **Step 1: Write the failing codec tests**

  Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/RealtimeEventCodecTests.swift` with exactly this content. Every client-event test decodes `encoded()` output back through `JSONSerialization` and asserts the nested fields as dictionaries (never string comparison, so key order is irrelevant). Server-event fixtures are copied from the GA protocol reference in the plan preamble.

  ```swift
  import XCTest
  @testable import Glutt

  final class RealtimeEventCodecTests: XCTestCase {

      // MARK: - Helpers

      /// Encodes the event and parses it back so assertions compare
      /// dictionaries, not JSON strings (key order must not matter).
      private func encodedDictionary(_ event: RealtimeClientEvent) throws -> [String: Any] {
          let data = try event.encoded()
          let object = try JSONSerialization.jsonObject(with: data)
          return try XCTUnwrap(object as? [String: Any], "top-level JSON must be an object")
      }

      private func decode(_ fixture: String) -> RealtimeServerEvent {
          RealtimeServerEvent.decode(Data(fixture.utf8))
      }

      private var startTimerTool: RealtimeToolDefinition {
          RealtimeToolDefinition(
              name: "start_timer",
              description: "Start a countdown timer for a cooking step.",
              parameters: .object([
                  "type": .string("object"),
                  "properties": .object([
                      "label": .object(["type": .string("string")]),
                      "seconds": .object(["type": .string("number")])
                  ]),
                  "required": .array([.string("label"), .string("seconds")])
              ]))
      }

      private var config: RealtimeSessionConfig {
          RealtimeSessionConfig(
              instructions: "You are Polly, a warm live cooking coach.",
              tools: [startTimerTool],
              voice: "marin",
              model: "gpt-realtime-2",
              transcribeInput: true)
      }

      // MARK: - JSONValue

      func testJSONValueRoundTripsThroughCodable() throws {
          let original = JSONValue.object([
              "name": .string("polly"),
              "count": .number(3),
              "enabled": .bool(true),
              "note": .null,
              "steps": .array([.string("prep"), .number(2.5), .bool(false)])
          ])
          let data = try JSONEncoder().encode(original)
          let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
          XCTAssertEqual(decoded, original)
      }

      func testJSONValueDecodesRawJSON() throws {
          let raw = #"{"type":"object","properties":{"seconds":{"type":"number"}},"required":["seconds"],"default":null,"max":15,"strict":true}"#
          let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
          XCTAssertEqual(decoded, .object([
              "type": .string("object"),
              "properties": .object(["seconds": .object(["type": .string("number")])]),
              "required": .array([.string("seconds")]),
              "default": .null,
              "max": .number(15),
              "strict": .bool(true)
          ]))
      }

      // MARK: - Client events: session.update

      func testSessionUpdateEncodesGAShape() throws {
          let payload = try encodedDictionary(.sessionUpdate(config))
          XCTAssertEqual(payload["type"] as? String, "session.update")

          let session = try XCTUnwrap(payload["session"] as? [String: Any])
          XCTAssertEqual(session["type"] as? String, "realtime")
          XCTAssertEqual(session["output_modalities"] as? [String], ["audio"])
          XCTAssertEqual(session["instructions"] as? String, "You are Polly, a warm live cooking coach.")
          XCTAssertEqual(session["tool_choice"] as? String, "auto")

          let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
          XCTAssertEqual(tools.count, 1)
          XCTAssertEqual(tools[0]["type"] as? String, "function")
          XCTAssertEqual(tools[0]["name"] as? String, "start_timer")
          XCTAssertEqual(tools[0]["description"] as? String, "Start a countdown timer for a cooking step.")
          let parameters = try XCTUnwrap(tools[0]["parameters"] as? [String: Any])
          XCTAssertEqual(parameters["type"] as? String, "object")
          XCTAssertEqual(parameters["required"] as? [String], ["label", "seconds"])
          let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
          let seconds = try XCTUnwrap(properties["seconds"] as? [String: Any])
          XCTAssertEqual(seconds["type"] as? String, "number")

          let audio = try XCTUnwrap(session["audio"] as? [String: Any])
          let input = try XCTUnwrap(audio["input"] as? [String: Any])
          let inputFormat = try XCTUnwrap(input["format"] as? [String: Any])
          XCTAssertEqual(inputFormat["type"] as? String, "audio/pcm")
          XCTAssertEqual(inputFormat["rate"] as? Int, 24000)
          let turnDetection = try XCTUnwrap(input["turn_detection"] as? [String: Any])
          XCTAssertEqual(turnDetection["type"] as? String, "semantic_vad")
          let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
          XCTAssertEqual(transcription["model"] as? String, "gpt-4o-transcribe")
          let output = try XCTUnwrap(audio["output"] as? [String: Any])
          let outputFormat = try XCTUnwrap(output["format"] as? [String: Any])
          XCTAssertEqual(outputFormat["type"] as? String, "audio/pcm")
          XCTAssertEqual(output["voice"] as? String, "marin")

          let truncation = try XCTUnwrap(session["truncation"] as? [String: Any])
          XCTAssertEqual(truncation["type"] as? String, "retention_ratio")
          let ratio = try XCTUnwrap(truncation["retention_ratio"] as? Double)
          XCTAssertEqual(ratio, 0.8, accuracy: 0.0001)
          let tokenLimits = try XCTUnwrap(truncation["token_limits"] as? [String: Any])
          XCTAssertEqual(tokenLimits["post_instructions"] as? Int, 16000)
      }

      func testSessionUpdateOmitsTranscriptionWhenDisabled() throws {
          var silent = config
          silent.transcribeInput = false
          let payload = try encodedDictionary(.sessionUpdate(silent))
          let session = try XCTUnwrap(payload["session"] as? [String: Any])
          let audio = try XCTUnwrap(session["audio"] as? [String: Any])
          let input = try XCTUnwrap(audio["input"] as? [String: Any])
          XCTAssertNil(input["transcription"])
          XCTAssertNotNil(input["turn_detection"])
          XCTAssertNotNil(input["format"])
      }

      // MARK: - Client events: everything else

      func testAppendAudioEncodes() throws {
          let payload = try encodedDictionary(.appendAudio(base64: "UENNMTZBVURJTw=="))
          XCTAssertEqual(payload["type"] as? String, "input_audio_buffer.append")
          XCTAssertEqual(payload["audio"] as? String, "UENNMTZBVURJTw==")
          XCTAssertEqual(payload.count, 2)
      }

      func testCreateUserTextEncodes() throws {
          let payload = try encodedDictionary(.createUserText("How hot should the pan be?"))
          XCTAssertEqual(payload["type"] as? String, "conversation.item.create")
          let item = try XCTUnwrap(payload["item"] as? [String: Any])
          XCTAssertEqual(item["type"] as? String, "message")
          XCTAssertEqual(item["role"] as? String, "user")
          let content = try XCTUnwrap(item["content"] as? [[String: Any]])
          XCTAssertEqual(content.count, 1)
          XCTAssertEqual(content[0]["type"] as? String, "input_text")
          XCTAssertEqual(content[0]["text"] as? String, "How hot should the pan be?")
      }

      func testCreateUserImageEncodesWithItemId() throws {
          let payload = try encodedDictionary(
              .createUserImage(dataURI: "data:image/jpeg;base64,AAAA", itemId: "wf_3"))
          XCTAssertEqual(payload["type"] as? String, "conversation.item.create")
          let item = try XCTUnwrap(payload["item"] as? [String: Any])
          XCTAssertEqual(item["id"] as? String, "wf_3")
          XCTAssertEqual(item["type"] as? String, "message")
          XCTAssertEqual(item["role"] as? String, "user")
          let content = try XCTUnwrap(item["content"] as? [[String: Any]])
          XCTAssertEqual(content.count, 1)
          XCTAssertEqual(content[0]["type"] as? String, "input_image")
          XCTAssertEqual(content[0]["image_url"] as? String, "data:image/jpeg;base64,AAAA")
      }

      func testCreateUserImageOmitsIdWhenNil() throws {
          let payload = try encodedDictionary(
              .createUserImage(dataURI: "data:image/jpeg;base64,BBBB", itemId: nil))
          let item = try XCTUnwrap(payload["item"] as? [String: Any])
          XCTAssertNil(item["id"])
          let content = try XCTUnwrap(item["content"] as? [[String: Any]])
          XCTAssertEqual(content[0]["type"] as? String, "input_image")
      }

      func testCreateFunctionOutputEncodes() throws {
          let payload = try encodedDictionary(
              .createFunctionOutput(callId: "call_1", output: #"{"ok":true}"#))
          XCTAssertEqual(payload["type"] as? String, "conversation.item.create")
          let item = try XCTUnwrap(payload["item"] as? [String: Any])
          XCTAssertEqual(item["type"] as? String, "function_call_output")
          XCTAssertEqual(item["call_id"] as? String, "call_1")
          XCTAssertEqual(item["output"] as? String, #"{"ok":true}"#)
      }

      func testDeleteItemEncodes() throws {
          let payload = try encodedDictionary(.deleteItem(itemId: "wf_2"))
          XCTAssertEqual(payload["type"] as? String, "conversation.item.delete")
          XCTAssertEqual(payload["item_id"] as? String, "wf_2")
          XCTAssertEqual(payload.count, 2)
      }

      func testResponseCreateEncodes() throws {
          let payload = try encodedDictionary(.responseCreate)
          XCTAssertEqual(payload["type"] as? String, "response.create")
          XCTAssertEqual(payload.count, 1)
      }

      func testResponseCancelEncodes() throws {
          let payload = try encodedDictionary(.responseCancel)
          XCTAssertEqual(payload["type"] as? String, "response.cancel")
          XCTAssertEqual(payload.count, 1)
      }

      func testTruncateItemEncodes() throws {
          let payload = try encodedDictionary(.truncateItem(itemId: "item_9", audioEndMs: 1500))
          XCTAssertEqual(payload["type"] as? String, "conversation.item.truncate")
          XCTAssertEqual(payload["item_id"] as? String, "item_9")
          XCTAssertEqual(payload["content_index"] as? Int, 0)
          XCTAssertEqual(payload["audio_end_ms"] as? Int, 1500)
      }

      // MARK: - Server events

      func testDecodesSessionCreated() {
          let fixture = #"{"type": "session.created", "event_id": "event_1", "session": {"id": "sess_1"}}"#
          XCTAssertEqual(decode(fixture), .sessionCreated)
      }

      func testDecodesSpeechStarted() {
          let fixture = #"{"type": "input_audio_buffer.speech_started", "event_id": "event_2", "audio_start_ms": 120, "item_id": "item_2"}"#
          XCTAssertEqual(decode(fixture), .speechStarted)
      }

      func testDecodesRemainingSimpleEvents() {
          XCTAssertEqual(decode(#"{"type": "session.updated", "session": {}}"#), .sessionUpdated)
          XCTAssertEqual(
              decode(#"{"type": "input_audio_buffer.speech_stopped", "audio_end_ms": 900, "item_id": "item_2"}"#),
              .speechStopped)
          XCTAssertEqual(decode(#"{"type": "response.cancelled", "response_id": "resp_7"}"#), .responseCancelled)
      }

      func testDecodesInputTranscriptionCompleted() {
          let fixture = #"""
          {"type": "conversation.item.input_audio_transcription.completed",
           "event_id": "event_3", "item_id": "item_2", "content_index": 0,
           "transcript": "Should I flip the salmon now?"}
          """#
          XCTAssertEqual(decode(fixture), .inputTranscript("Should I flip the salmon now?"))
      }

      func testDecodesOutputAudioDelta() {
          let fixture = #"""
          {"type": "response.output_audio.delta", "event_id": "event_5",
           "response_id": "resp_1", "item_id": "item_3",
           "output_index": 0, "content_index": 0, "delta": "UENNQVVESU8="}
          """#
          XCTAssertEqual(decode(fixture), .outputAudioDelta(itemId: "item_3", base64: "UENNQVVESU8="))
      }

      func testDecodesOutputTranscriptDelta() {
          let fixture = #"""
          {"type": "response.output_audio_transcript.delta", "event_id": "event_6",
           "response_id": "resp_1", "item_id": "item_3",
           "output_index": 0, "content_index": 0, "delta": "Nice sear"}
          """#
          XCTAssertEqual(decode(fixture), .outputTranscriptDelta(itemId: "item_3", delta: "Nice sear"))
      }

      func testDecodesResponseDoneExtractsFunctionCalls() throws {
          let fixture = #"""
          {"type": "response.done", "event_id": "event_7",
           "response": {
             "id": "resp_2",
             "status": "completed",
             "output": [
               {"type": "message", "id": "item_4", "role": "assistant",
                "content": [{"type": "output_audio", "transcript": "On it."}]},
               {"type": "function_call", "id": "item_5", "name": "start_timer",
                "call_id": "call_1", "arguments": "{\"label\":\"pasta\",\"seconds\":480}"},
               {"type": "function_call", "id": "item_6", "name": "check_pantry",
                "call_id": "call_2", "arguments": "{\"names\":[\"butter\"]}"}
             ],
             "usage": {"total_tokens": 900}}}
          """#
          guard case .responseDone(let status, let calls) = decode(fixture) else {
              return XCTFail("expected .responseDone")
          }
          XCTAssertEqual(status, "completed")
          XCTAssertEqual(calls.count, 2)
          XCTAssertEqual(calls, [
              RealtimeFunctionCall(name: "start_timer", callId: "call_1",
                                   argumentsJSON: #"{"label":"pasta","seconds":480}"#),
              RealtimeFunctionCall(name: "check_pantry", callId: "call_2",
                                   argumentsJSON: #"{"names":["butter"]}"#)
          ])
      }

      func testDecodesError() {
          let fixture = #"""
          {"type": "error", "event_id": "event_9",
           "error": {"type": "invalid_request_error", "code": "invalid_value",
                     "message": "Audio format not supported.", "param": null}}
          """#
          XCTAssertEqual(decode(fixture), .error(code: "invalid_value", message: "Audio format not supported."))
      }

      func testUnknownTypeIsUnhandled() {
          let fixture = #"{"type": "rate_limits.updated", "rate_limits": []}"#
          XCTAssertEqual(decode(fixture), .unhandled(type: "rate_limits.updated"))
      }

      func testMalformedPayloadsAreUnhandled() {
          XCTAssertEqual(RealtimeServerEvent.decode(Data([0xFF, 0x00, 0x13, 0x37])),
                         .unhandled(type: "malformed"))
          XCTAssertEqual(decode(#"{"no_type": true}"#), .unhandled(type: "malformed"))
          XCTAssertEqual(decode(#"[1, 2, 3]"#), .unhandled(type: "malformed"))
      }
  }
  ```

- [ ] **Step 2: Regenerate the project and confirm the tests fail**

  - Run `xcodegen generate` (Bash, from `/Users/omarlahmimi/Documents/Glutt`) so the new test file joins the `GluttTests` target. Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.
  - Run tests: `test_sim` (scheme `Glutt`) — expected: **FAIL** — the `GluttTests` target does not compile (`cannot find 'RealtimeClientEvent' in scope`, `cannot find 'RealtimeServerEvent' in scope`, `cannot find type 'JSONValue' in scope`, `cannot find type 'RealtimeToolDefinition' in scope`). This is the red state; do not proceed until you have seen it.

- [ ] **Step 3: Implement the codec**

  Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/RealtimeEvent.swift` with exactly this content:

  ```swift
  import Foundation

  // MARK: - JSONValue

  /// Minimal JSON tree used for Realtime tool schemas and function-call
  /// arguments. Fully `Codable` in both directions so schemas can be declared
  /// in Swift and payloads decoded straight off the wire.
  enum JSONValue: Codable, Equatable {
      case string(String)
      case number(Double)
      case bool(Bool)
      case null
      case array([JSONValue])
      case object([String: JSONValue])

      init(from decoder: Decoder) throws {
          let container = try decoder.singleValueContainer()
          if container.decodeNil() {
              self = .null
          } else if let bool = try? container.decode(Bool.self) {
              self = .bool(bool)
          } else if let number = try? container.decode(Double.self) {
              self = .number(number)
          } else if let string = try? container.decode(String.self) {
              self = .string(string)
          } else if let array = try? container.decode([JSONValue].self) {
              self = .array(array)
          } else if let object = try? container.decode([String: JSONValue].self) {
              self = .object(object)
          } else {
              throw DecodingError.dataCorruptedError(
                  in: container, debugDescription: "Unsupported JSON value")
          }
      }

      func encode(to encoder: Encoder) throws {
          var container = encoder.singleValueContainer()
          switch self {
          case .string(let value): try container.encode(value)
          case .number(let value): try container.encode(value)
          case .bool(let value): try container.encode(value)
          case .null: try container.encodeNil()
          case .array(let value): try container.encode(value)
          case .object(let value): try container.encode(value)
          }
      }

      /// Bridge to a `JSONSerialization`-compatible object tree.
      var jsonObject: Any {
          switch self {
          case .string(let value): return value
          case .number(let value): return value
          case .bool(let value): return value
          case .null: return NSNull()
          case .array(let values): return values.map(\.jsonObject)
          case .object(let values): return values.mapValues(\.jsonObject)
          }
      }
  }

  // MARK: - Session configuration

  /// A Realtime function tool advertised via `session.update`.
  struct RealtimeToolDefinition: Encodable, Equatable {
      let type = "function"
      let name: String
      let description: String
      let parameters: JSONValue      // JSON Schema as a JSONValue tree
  }

  /// Everything the initial `session.update` needs. Built once per session.
  /// `model` rides along for the WS connect URL — the GA protocol does not
  /// put it inside the `session.update` payload.
  struct RealtimeSessionConfig: Equatable {
      var instructions: String
      var tools: [RealtimeToolDefinition]
      var voice: String              // PollyConfig.voice
      var model: String              // PollyConfig.realtimeModel
      var transcribeInput: Bool      // true -> audio.input.transcription = {model: "gpt-4o-transcribe"}
  }

  /// A function call the model asked us to run, lifted out of `response.done`.
  struct RealtimeFunctionCall: Equatable {
      let name: String
      let callId: String
      let argumentsJSON: String
  }

  // MARK: - Client -> server events

  /// The subset of OpenAI Realtime GA client events Polly sends.
  /// `encoded()` emits the exact wire JSON documented in the plan's
  /// protocol reference.
  enum RealtimeClientEvent: Equatable {
      case sessionUpdate(RealtimeSessionConfig)
      case appendAudio(base64: String)
      case createUserText(String)
      case createUserImage(dataURI: String, itemId: String?)  // itemId lets us delete stale watch frames
      case createFunctionOutput(callId: String, output: String)
      case deleteItem(itemId: String)
      case responseCreate
      case responseCancel
      case truncateItem(itemId: String, audioEndMs: Int)

      func encoded() throws -> Data {
          try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
      }

      private var payload: [String: Any] {
          switch self {
          case .sessionUpdate(let config):
              return ["type": "session.update", "session": Self.sessionPayload(config)]
          case .appendAudio(let base64):
              return ["type": "input_audio_buffer.append", "audio": base64]
          case .createUserText(let text):
              return ["type": "conversation.item.create",
                      "item": ["type": "message", "role": "user",
                               "content": [["type": "input_text", "text": text]]]]
          case .createUserImage(let dataURI, let itemId):
              var item: [String: Any] = ["type": "message", "role": "user",
                                         "content": [["type": "input_image", "image_url": dataURI]]]
              if let itemId { item["id"] = itemId }
              return ["type": "conversation.item.create", "item": item]
          case .createFunctionOutput(let callId, let output):
              return ["type": "conversation.item.create",
                      "item": ["type": "function_call_output", "call_id": callId, "output": output]]
          case .deleteItem(let itemId):
              return ["type": "conversation.item.delete", "item_id": itemId]
          case .responseCreate:
              return ["type": "response.create"]
          case .responseCancel:
              return ["type": "response.cancel"]
          case .truncateItem(let itemId, let audioEndMs):
              return ["type": "conversation.item.truncate", "item_id": itemId,
                      "content_index": 0, "audio_end_ms": audioEndMs]
          }
      }

      private static func sessionPayload(_ config: RealtimeSessionConfig) -> [String: Any] {
          var input: [String: Any] = [
              "format": ["type": "audio/pcm", "rate": 24000],
              "turn_detection": ["type": "semantic_vad"]
          ]
          if config.transcribeInput {
              input["transcription"] = ["model": "gpt-4o-transcribe"]
          }
          let tools: [[String: Any]] = config.tools.map {
              ["type": $0.type, "name": $0.name, "description": $0.description,
               "parameters": $0.parameters.jsonObject]
          }
          return [
              "type": "realtime",
              "output_modalities": ["audio"],
              "instructions": config.instructions,
              "tools": tools,
              "tool_choice": "auto",
              "audio": [
                  "input": input,
                  "output": ["format": ["type": "audio/pcm"], "voice": config.voice]
              ],
              "truncation": ["type": "retention_ratio", "retention_ratio": 0.8,
                             "token_limits": ["post_instructions": 16000]]
          ]
      }
  }

  // MARK: - Server -> client events

  /// The subset of OpenAI Realtime GA server events Polly reacts to.
  enum RealtimeServerEvent: Equatable {
      case sessionCreated
      case sessionUpdated
      case speechStarted                       // input_audio_buffer.speech_started
      case speechStopped
      case inputTranscript(String)             // conversation.item.input_audio_transcription.completed
      case outputAudioDelta(itemId: String, base64: String)
      case outputTranscriptDelta(itemId: String, delta: String)
      case responseDone(status: String, calls: [RealtimeFunctionCall])
      case responseCancelled
      case error(code: String?, message: String)
      case unhandled(type: String)

      /// Never throws: anything unparseable becomes `.unhandled` so a weird
      /// frame can never take the session down.
      static func decode(_ data: Data) -> RealtimeServerEvent {
          guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let type = object["type"] as? String else {
              return .unhandled(type: "malformed")
          }
          switch type {
          case "session.created":
              return .sessionCreated
          case "session.updated":
              return .sessionUpdated
          case "input_audio_buffer.speech_started":
              return .speechStarted
          case "input_audio_buffer.speech_stopped":
              return .speechStopped
          case "conversation.item.input_audio_transcription.completed":
              return .inputTranscript(object["transcript"] as? String ?? "")
          case "response.output_audio.delta":
              guard let itemId = object["item_id"] as? String,
                    let delta = object["delta"] as? String else { return .unhandled(type: type) }
              return .outputAudioDelta(itemId: itemId, base64: delta)
          case "response.output_audio_transcript.delta":
              guard let itemId = object["item_id"] as? String,
                    let delta = object["delta"] as? String else { return .unhandled(type: type) }
              return .outputTranscriptDelta(itemId: itemId, delta: delta)
          case "response.done":
              let response = object["response"] as? [String: Any] ?? [:]
              let output = response["output"] as? [[String: Any]] ?? []
              let calls: [RealtimeFunctionCall] = output.compactMap { item in
                  guard item["type"] as? String == "function_call",
                        let name = item["name"] as? String,
                        let callId = item["call_id"] as? String else { return nil }
                  return RealtimeFunctionCall(name: name, callId: callId,
                                              argumentsJSON: item["arguments"] as? String ?? "{}")
              }
              return .responseDone(status: response["status"] as? String ?? "unknown", calls: calls)
          case "response.cancelled":
              return .responseCancelled
          case "error":
              let error = object["error"] as? [String: Any] ?? [:]
              return .error(code: error["code"] as? String,
                            message: error["message"] as? String ?? "Unknown realtime error")
          default:
              return .unhandled(type: type)
          }
      }
  }
  ```

  Then run `xcodegen generate` (Bash, from `/Users/omarlahmimi/Documents/Glutt`) so the new source file joins the `Glutt` target. Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 4: Run the tests green**

  Run tests: `test_sim` (scheme `Glutt`) — expected: **PASS**, includes `RealtimeEventCodecTests.testJSONValueRoundTripsThroughCodable`, `testJSONValueDecodesRawJSON`, `testSessionUpdateEncodesGAShape`, `testSessionUpdateOmitsTranscriptionWhenDisabled`, `testAppendAudioEncodes`, `testCreateUserTextEncodes`, `testCreateUserImageEncodesWithItemId`, `testCreateUserImageOmitsIdWhenNil`, `testCreateFunctionOutputEncodes`, `testDeleteItemEncodes`, `testResponseCreateEncodes`, `testResponseCancelEncodes`, `testTruncateItemEncodes`, `testDecodesSessionCreated`, `testDecodesSpeechStarted`, `testDecodesRemainingSimpleEvents`, `testDecodesInputTranscriptionCompleted`, `testDecodesOutputAudioDelta`, `testDecodesOutputTranscriptDelta`, `testDecodesResponseDoneExtractsFunctionCalls`, `testDecodesError`, `testUnknownTypeIsUnhandled`, `testMalformedPayloadsAreUnhandled` — and all pre-existing suites still pass.

- [ ] **Step 5: Commit**

  ```bash
  git -C /Users/omarlahmimi/Documents/Glutt add Glutt.xcodeproj Glutt/Services/Polly/RealtimeEvent.swift GluttTests/RealtimeEventCodecTests.swift
  git -C /Users/omarlahmimi/Documents/Glutt commit -m "$(cat <<'EOF'
  feat(polly): add realtime GA event codec

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
  EOF
  )"
  ```

---

### Task 7: RealtimeTransport (WebSocket actor + socket seam)

**Files:**
- Create: `Glutt/Services/Polly/RealtimeTransport.swift`
- Test: `GluttTests/RealtimeTransportTests.swift`

**Interfaces:**

Consumes (Task 6, `Glutt/Services/Polly/RealtimeEvent.swift`):
```swift
enum RealtimeClientEvent: Equatable {
    case sessionUpdate(RealtimeSessionConfig)
    case appendAudio(base64: String)
    case createUserText(String)
    case createUserImage(dataURI: String, itemId: String?)
    case createFunctionOutput(callId: String, output: String)
    case deleteItem(itemId: String)
    case responseCreate
    case responseCancel
    case truncateItem(itemId: String, audioEndMs: Int)
    func encoded() throws -> Data
}
enum RealtimeServerEvent: Equatable {
    case sessionCreated
    case sessionUpdated
    case speechStarted
    case speechStopped
    case inputTranscript(String)
    case outputAudioDelta(itemId: String, base64: String)
    case outputTranscriptDelta(itemId: String, delta: String)
    case responseDone(status: String, calls: [RealtimeFunctionCall])
    case responseCancelled
    case error(code: String?, message: String)
    case unhandled(type: String)
    static func decode(_ data: Data) -> RealtimeServerEvent
}
```

Produces (consumed by Task 13 `PollySessionController` via `Dependencies.makeTransport: () -> RealtimeTransporting`):
```swift
protocol RealtimeSocket: Sendable {          // seam over URLSessionWebSocketTask
    func send(text: String) async throws
    func receiveText() async throws -> String
    func close()
}
protocol RealtimeTransporting: AnyObject, Sendable {
    func connect(token: String, model: String) async throws
    func send(_ event: RealtimeClientEvent) async throws
    var events: AsyncStream<RealtimeServerEvent> { get }
    func close() async
}
actor RealtimeWebSocketTransport: RealtimeTransporting {
    init(socketFactory: @escaping @Sendable (URLRequest) -> RealtimeSocket = { URLSessionWebSocket(request: $0) })
}
enum RealtimeTransportError: LocalizedError, Equatable { case notConnected, badURL, nonTextFrame }
final class URLSessionWebSocket: RealtimeSocket, @unchecked Sendable { init(request: URLRequest) }
```

Behavior contract (from the plan header + spec):
- `connect(token:model:)` builds a `URLRequest` for `wss://api.openai.com/v1/realtime?model=<model>` with header `Authorization: Bearer <token>`, creates the socket through the factory, and starts a receive loop `Task`: every received text frame goes through `RealtimeServerEvent.decode` and is yielded into the `events` stream. On any receive error the loop yields `.error(code: "transport", message:)` and finishes the stream.
- `send(_:)` encodes via `event.encoded()` and sends as a text frame; before `connect` it throws `.notConnected`.
- `close()` cancels the receive loop, closes the socket, and finishes the stream (a cancellation-driven receive error must NOT yield a spurious `.error`).
- `events` is single-consumer and created once in `init` (the controller in Task 13 iterates it exactly once).
- No reconnect logic lives here — the single silent reconnect from the spec's degradation ladder is Task 13's job (it creates a fresh transport via `makeTransport`).
- Tests never touch the network: the production `URLSessionWebSocket` is exercised only for type conformance at compile time; all behavior tests use a scripted `FakeSocket`.

**Steps:**

- [ ] **Step 1: Write the failing test file.** Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/RealtimeTransportTests.swift` with exactly this content:

```swift
import XCTest
@testable import Glutt

/// Scripted stand-in for the production socket. Serves a queue of incoming
/// frames, records outgoing sends, and — once the script is exhausted —
/// either throws (`throwsWhenExhausted: true`) or suspends until `close()`.
final class FakeSocket: RealtimeSocket, @unchecked Sendable {
    struct ScriptExhausted: Error {}

    private let lock = NSLock()
    private let throwsWhenExhausted: Bool
    private var script: [String]
    private var sentLines: [String] = []
    private var closeCount = 0
    private var waiter: CheckedContinuation<String, Error>?

    init(script: [String], throwsWhenExhausted: Bool) {
        self.script = script
        self.throwsWhenExhausted = throwsWhenExhausted
    }

    var sent: [String] { lock.withLock { sentLines } }
    var isClosed: Bool { lock.withLock { closeCount > 0 } }

    func send(text: String) async throws {
        lock.withLock { sentLines.append(text) }
    }

    func receiveText() async throws -> String {
        let next: String? = lock.withLock { script.isEmpty ? nil : script.removeFirst() }
        if let next { return next }
        if throwsWhenExhausted { throw ScriptExhausted() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiter = continuation }
        }
    }

    func close() {
        let pending: CheckedContinuation<String, Error>? = lock.withLock {
            closeCount += 1
            let current = waiter
            waiter = nil
            return current
        }
        pending?.resume(throwing: CancellationError())
    }
}

/// Thread-safe capture box for the URLRequest handed to the socket factory.
private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?
    var request: URLRequest? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class RealtimeTransportTests: XCTestCase {
    func testConnectPassesModelQueryAndBearerTokenToSocketFactory() async throws {
        let capture = RequestCapture()
        let socket = FakeSocket(script: [], throwsWhenExhausted: false)
        let transport = RealtimeWebSocketTransport(socketFactory: { request in
            capture.request = request
            return socket
        })

        try await transport.connect(token: "ek_test_123", model: "gpt-realtime-2")

        let request = try XCTUnwrap(capture.request)
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.host, "api.openai.com")
        XCTAssertEqual(url.path, "/v1/realtime")
        XCTAssertEqual(url.query, "model=gpt-realtime-2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ek_test_123")
        await transport.close()
        XCTAssertTrue(socket.isClosed)
    }

    func testScriptedServerFramesArriveDecodedInOrder() async throws {
        let socket = FakeSocket(
            script: [
                #"{"type": "session.created"}"#,
                #"{"type": "input_audio_buffer.speech_started"}"#,
            ],
            throwsWhenExhausted: false
        )
        let transport = RealtimeWebSocketTransport(socketFactory: { _ in socket })
        try await transport.connect(token: "ek_test", model: "gpt-realtime-2")

        var iterator = transport.events.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        XCTAssertEqual(first, .sessionCreated)
        XCTAssertEqual(second, .speechStarted)
        await transport.close()
    }

    func testSendResponseCreateEncodesResponseCreateJSON() async throws {
        let socket = FakeSocket(script: [], throwsWhenExhausted: false)
        let transport = RealtimeWebSocketTransport(socketFactory: { _ in socket })
        try await transport.connect(token: "ek_test", model: "gpt-realtime-2")

        try await transport.send(.responseCreate)

        let sent = socket.sent
        XCTAssertEqual(sent.count, 1)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(sent[0].utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["type"] as? String, "response.create")
        await transport.close()
    }

    func testExhaustedScriptYieldsTransportErrorThenFinishesStream() async throws {
        let socket = FakeSocket(
            script: [#"{"type": "session.created"}"#],
            throwsWhenExhausted: true
        )
        let transport = RealtimeWebSocketTransport(socketFactory: { _ in socket })
        try await transport.connect(token: "ek_test", model: "gpt-realtime-2")

        var received: [RealtimeServerEvent] = []
        for await event in transport.events {   // exits only when the stream finishes
            received.append(event)
        }

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.first, .sessionCreated)
        let last = try XCTUnwrap(received.last)
        guard case .error(let code, let message) = last else {
            return XCTFail("Expected .error as the final event, got \(last)")
        }
        XCTAssertEqual(code, "transport")
        XCTAssertFalse(message.isEmpty)
        await transport.close()
    }

    func testSendBeforeConnectThrowsNotConnected() async {
        let transport = RealtimeWebSocketTransport(socketFactory: { _ in
            FakeSocket(script: [], throwsWhenExhausted: false)
        })
        do {
            try await transport.send(.responseCreate)
            XCTFail("expected throw")
        } catch let error as RealtimeTransportError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
```

Why the fake is shaped this way: the receive loop inside the transport is the stream's single consumer, so one pending `waiter` continuation is enough; `throwsWhenExhausted: false` keeps the session "open" (the loop suspends) so send/connect assertions run against a live transport, while `true` simulates a dropped socket deterministically without any network.

- [ ] **Step 2: Regenerate the project so the new test file joins the target.**
  Run in Bash: `cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate`
  Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 3: Run tests — confirm the expected failure.**
  Run tests: `test_sim` (scheme `Glutt`) — expected: **FAIL** — the `GluttTests` target does not compile: `cannot find type 'RealtimeSocket' in scope`, `cannot find 'RealtimeWebSocketTransport' in scope`, `cannot find type 'RealtimeTransportError' in scope`. (The app target still builds; only the test target breaks. This is the failing-test state for a compiled language.)

- [ ] **Step 4: Implement the transport.** Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/RealtimeTransport.swift` with exactly this content:

```swift
import Foundation

enum RealtimeTransportError: LocalizedError, Equatable {
    case notConnected
    case badURL
    case nonTextFrame

    var errorDescription: String? {
        switch self {
        case .notConnected: "Polly isn't connected yet."
        case .badURL: "Couldn't build the realtime session URL."
        case .nonTextFrame: "Received an unreadable frame from the realtime session."
        }
    }
}

/// Seam over `URLSessionWebSocketTask` so the transport is testable
/// with a scripted fake (no network in tests).
protocol RealtimeSocket: Sendable {
    func send(text: String) async throws
    func receiveText() async throws -> String
    func close()
}

/// Production socket: a thin wrapper over `URLSessionWebSocketTask`.
/// `URLSessionTask` is documented thread-safe, hence `@unchecked Sendable`.
final class URLSessionWebSocket: RealtimeSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(request: URLRequest) {
        task = URLSession.shared.webSocketTask(with: request)
        task.resume()
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func receiveText() async throws -> String {
        while true {
            switch try await task.receive() {
            case .string(let text):
                return text
            case .data(let data):
                guard let text = String(data: data, encoding: .utf8) else {
                    throw RealtimeTransportError.nonTextFrame
                }
                return text
            @unknown default:
                continue
            }
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

/// Abstraction the session controller (Task 13) talks to; lets tests and the
/// reconnect path swap the whole transport, and a future WebRTC/LiveKit
/// transport slot in behind the same face.
protocol RealtimeTransporting: AnyObject, Sendable {
    func connect(token: String, model: String) async throws
    func send(_ event: RealtimeClientEvent) async throws
    var events: AsyncStream<RealtimeServerEvent> { get }
    func close() async
}

/// WebSocket transport for the OpenAI Realtime GA protocol.
/// `events` is single-consumer and created once in `init`; the receive loop
/// decodes every text frame via `RealtimeServerEvent.decode` and yields it.
/// On a receive failure it yields `.error(code: "transport", ...)` and
/// finishes the stream — reconnecting is the controller's decision.
actor RealtimeWebSocketTransport: RealtimeTransporting {
    nonisolated let events: AsyncStream<RealtimeServerEvent>

    private let continuation: AsyncStream<RealtimeServerEvent>.Continuation
    private let socketFactory: @Sendable (URLRequest) -> RealtimeSocket
    private var socket: RealtimeSocket?
    private var receiveTask: Task<Void, Never>?

    init(
        socketFactory: @escaping @Sendable (URLRequest) -> RealtimeSocket = { URLSessionWebSocket(request: $0) }
    ) {
        self.socketFactory = socketFactory
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeServerEvent.self)
        self.events = stream
        self.continuation = continuation
    }

    func connect(token: String, model: String) async throws {
        var comps = URLComponents()
        comps.scheme = "wss"
        comps.host = "api.openai.com"
        comps.path = "/v1/realtime"
        comps.queryItems = [URLQueryItem(name: "model", value: model)]
        guard let url = comps.url else { throw RealtimeTransportError.badURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let socket = socketFactory(request)
        self.socket = socket
        let continuation = self.continuation
        receiveTask = Task {
            while !Task.isCancelled {
                do {
                    let text = try await socket.receiveText()
                    continuation.yield(RealtimeServerEvent.decode(Data(text.utf8)))
                } catch {
                    if !Task.isCancelled {
                        continuation.yield(.error(code: "transport", message: error.localizedDescription))
                    }
                    continuation.finish()
                    return
                }
            }
        }
    }

    func send(_ event: RealtimeClientEvent) async throws {
        guard let socket else { throw RealtimeTransportError.notConnected }
        let data = try event.encoded()
        try await socket.send(text: String(decoding: data, as: UTF8.self))
    }

    func close() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.close()
        socket = nil
        continuation.finish()
    }
}
```

Implementation notes (why each choice, so the implementer doesn't "improve" them away):
- `nonisolated let events` satisfies the synchronous `var events { get }` protocol requirement on an actor; `AsyncStream` is `Sendable`, so nonisolated storage is legal and the controller can grab the stream without an actor hop.
- The receive loop captures the local `socket` and a local copy of `continuation` — never `self` — so a leaked loop can't retain the actor after `close()`.
- The `Task.isCancelled` guard in the `catch` prevents `close()` (which cancels the task and then closes the socket, causing the pending receive to throw) from injecting a bogus `.error` before the stream finishes; double-`finish()` on an `AsyncStream.Continuation` is a documented no-op.
- `String(decoding:as:)` instead of failable `String(data:encoding:)` on the send path: `JSONEncoder` output is always valid UTF-8, so no extra error case.
- `close()` is declared synchronous on the actor; a synchronous actor method satisfies the `func close() async` protocol requirement (callers hop to the actor).

- [ ] **Step 5: Regenerate the project so the new source file joins the app target.**
  Run in Bash: `cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate`
  Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 6: Run tests.**
  Run tests: `test_sim` (scheme `Glutt`) — expected: **PASS**, includes `testConnectPassesModelQueryAndBearerTokenToSocketFactory`, `testScriptedServerFramesArriveDecodedInOrder`, `testSendResponseCreateEncodesResponseCreateJSON`, `testExhaustedScriptYieldsTransportErrorThenFinishesStream`, `testSendBeforeConnectThrowsNotConnected` (and all pre-existing tests still green).

- [ ] **Step 7: Commit.**
  ```bash
  cd /Users/omarlahmimi/Documents/Glutt
  git add Glutt.xcodeproj Glutt/Services/Polly/RealtimeTransport.swift GluttTests/RealtimeTransportTests.swift
  git commit -m "$(cat <<'EOF'
feat(polly): add websocket realtime transport with socket seam

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
EOF
)"
  ```

---

### Task 8: PollyAudioEngine + PCM helpers

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyAudioEngine.swift`
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/PCMTests.swift`

**Interfaces:**
- Consumes: nothing from earlier Polly tasks — AVFoundation + Observation only. The wire constants (24 kHz mono PCM16, 4 800-byte ≈ 100 ms chunks, tap bufferSize 2 400) are fixed by the Realtime GA protocol and live in this file; `PollyConfig` (Task 2) deliberately carries no audio constants.
- Produces (Task 13 `PollySessionController` calls `start/stop/enqueue/interruptPlayback` and reads `isMuted`; Task 15 `PollySessionView` orb reads `inputLevel`/`isPlaying` — signatures are locked by the Shared Contracts):

```swift
enum PCM {
    static func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data
    static func buffer(fromPCM16 data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer?
    static func resample(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer?
}

@MainActor @Observable final class PollyAudioEngine {
    private(set) var isRunning: Bool
    var isMuted: Bool
    private(set) var isPlaying: Bool
    private(set) var inputLevel: Float
    func start(onChunk: @escaping @Sendable (String) -> Void) throws
    func stop()
    func enqueue(base64: String)
    @discardableResult func interruptPlayback() -> Int
}
```

Tests cover only the pure `PCM` helpers — `PollyAudioEngine` touches `AVAudioSession`/`AVAudioEngine` hardware that does not exist reliably on the simulator, so it is compile-verified here (it builds as part of `test_sim`) and exercised live during the on-device TestFlight pass called out in the spec's testing section. No test in this task instantiates the engine.

- [ ] **Step 1: Write the failing PCM tests**

Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PCMTests.swift` with exactly:

```swift
import AVFoundation
import XCTest
@testable import Glutt

final class PCMTests: XCTestCase {

    // MARK: - Helpers

    private func floatFormat(sampleRate: Double) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    private func int16Format(sampleRate: Double) -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    /// Mono float32 sine wave at 440 Hz, amplitude 0.5.
    private func sineBuffer(format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frames) {
            channel[frame] = 0.5 * sin(2 * .pi * 440 * Float(frame) / Float(format.sampleRate))
        }
        return buffer
    }

    /// Reads little-endian Int16 samples back out of wire-format data.
    private func int16Samples(from data: Data) -> [Int16] {
        data.withUnsafeBytes { raw in
            (0..<(data.count / 2)).map { i in
                Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
            }
        }
    }

    // MARK: - Tests

    func testFloatSineRoundTripsThroughPCM16WithinOne() throws {
        let format = floatFormat(sampleRate: 24_000)
        let source = sineBuffer(format: format, frames: 2_400)

        let data = PCM.pcm16Data(from: source)
        XCTAssertEqual(data.count, 4_800, "2400 frames x 2 bytes per sample")

        let decoded = try XCTUnwrap(PCM.buffer(fromPCM16: data, format: int16Format(sampleRate: 24_000)))
        XCTAssertEqual(decoded.frameLength, 2_400)

        let decodedSamples = try XCTUnwrap(decoded.int16ChannelData?[0])
        let floats = source.floatChannelData![0]
        var maxDelta = 0
        for frame in 0..<2_400 {
            let expected = Int((floats[frame] * 32_767).rounded())
            maxDelta = max(maxDelta, abs(Int(decodedSamples[frame]) - expected))
        }
        XCTAssertLessThanOrEqual(maxDelta, 1)
    }

    func testPCM16DataClampsOutOfRangeFloats() throws {
        let format = floatFormat(sampleRate: 24_000)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        channel[0] = 2.5
        channel[1] = -3.0
        channel[2] = 1.0
        channel[3] = -1.0

        let samples = int16Samples(from: PCM.pcm16Data(from: buffer))
        XCTAssertEqual(samples, [32_767, -32_767, 32_767, -32_767])
    }

    func testResample48kTo24kHalvesFrameCount() throws {
        let source = sineBuffer(format: floatFormat(sampleRate: 48_000), frames: 4_800)
        let resampled = try XCTUnwrap(PCM.resample(source, to: int16Format(sampleRate: 24_000)))

        XCTAssertEqual(resampled.format.sampleRate, 24_000)
        XCTAssertEqual(resampled.format.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(Int(resampled.frameLength), 2_400, accuracy: 2)
    }

    func testPCM16DataPassesThroughInt16BufferUnchanged() throws {
        let format = int16Format(sampleRate: 24_000)
        let values: [Int16] = [0, 1, -1, 12_345, -12_345, .max, .min]
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)))
        buffer.frameLength = AVAudioFrameCount(values.count)
        let channel = try XCTUnwrap(buffer.int16ChannelData?[0])
        for (frame, value) in values.enumerated() { channel[frame] = value }

        XCTAssertEqual(int16Samples(from: PCM.pcm16Data(from: buffer)), values)
    }
}
```

Then regenerate the project so the new test file joins the `GluttTests` target:

```bash
cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate
```

Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 2: Run tests — expect red.** Run tests: `test_sim` (scheme `Glutt`) — expected: FAIL (build error in `PCMTests.swift`: `cannot find 'PCM' in scope`).

- [ ] **Step 3: Implement the PCM helpers and the audio engine**

Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyAudioEngine.swift` with exactly:

```swift
import AVFoundation
import Observation
import os

// MARK: - PCM helpers

/// Pure PCM conversion utilities for the Realtime wire format (16-bit
/// little-endian mono at 24 kHz). No hardware access — fully unit-testable.
enum PCM {
    /// Extracts channel 0 of a float32 or int16 buffer as little-endian
    /// 16-bit mono `Data`. Float samples are clamped to -1...1 first.
    static func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return Data() }
        var samples = [Int16](repeating: 0, count: frames)

        if let floatChannels = buffer.floatChannelData {
            let channel = floatChannels[0]
            let step = buffer.stride
            for frame in 0..<frames {
                let clamped = max(-1, min(1, channel[frame * step]))
                samples[frame] = Int16((clamped * 32_767).rounded()).littleEndian
            }
        } else if let intChannels = buffer.int16ChannelData {
            let channel = intChannels[0]
            let step = buffer.stride
            for frame in 0..<frames {
                samples[frame] = channel[frame * step].littleEndian
            }
        } else {
            return Data()
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Rebuilds an int16 mono buffer from little-endian PCM16 bytes.
    /// `format` must be a 1-channel `.pcmFormatInt16` format.
    static func buffer(fromPCM16 data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard format.commonFormat == .pcmFormatInt16, format.channelCount == 1 else { return nil }
        let frames = data.count / MemoryLayout<Int16>.size
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.int16ChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            for frame in 0..<frames {
                channel[frame] = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: frame * 2, as: Int16.self))
            }
        }
        return buffer
    }

    /// Converts a buffer to another sample rate and/or sample format via
    /// `AVAudioConverter`. Returns nil on any conversion failure.
    static func resample(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        // No priming latency: per-buffer streaming conversion must not eat frames.
        converter.primeMethod = .none

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var fedSource = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if fedSource {
                outStatus.pointee = .endOfStream
                return nil
            }
            fedSource = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, status != .error else { return nil }
        return output
    }
}

// MARK: - Errors

enum PollyAudioError: LocalizedError {
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "The microphone isn't available right now."
        }
    }
}

// MARK: - Engine

/// Owns the echo-cancelled voice pipeline for a live Polly session: mic
/// capture (emitted as ~100 ms base64 PCM16 24 kHz chunks for the Realtime
/// socket) and assistant audio playback through a player node. Everything
/// hardware-touching is confined to `start()`/`stop()`; failures throw from
/// `start()` and never crash.
@MainActor
@Observable
final class PollyAudioEngine {
    private(set) var isRunning = false
    /// While muted the tap stays installed; chunk emission is gated off.
    var isMuted = false {
        didSet { mutedFlag.withLock { $0 = isMuted } }
    }
    /// True while any assistant audio buffer is scheduled and unplayed.
    private(set) var isPlaying = false
    /// Smoothed mic RMS in 0...1, for the session orb.
    private(set) var inputLevel: Float = 0

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let playerNode = AVAudioPlayerNode()
    @ObservationIgnored private var isPlayerAttached = false
    @ObservationIgnored private var outstandingBuffers = 0
    @ObservationIgnored private let mutedFlag = OSAllocatedUnfairLock(initialState: false)
    /// 4 800 bytes = 2 400 Int16 samples = ~100 ms at 24 kHz.
    @ObservationIgnored private let accumulator = PCMChunkAccumulator(chunkByteCount: 4_800)

    /// PCM16 mono 24 kHz — what the Realtime socket speaks in both directions.
    /// Force-unwraps are safe: these initializers only fail for invalid parameters.
    @ObservationIgnored private let wireFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false
    )!
    /// Float mono 24 kHz — what the player node feeds the main mixer.
    @ObservationIgnored private let playbackFormat = AVAudioFormat(
        standardFormatWithSampleRate: 24_000, channels: 1
    )!

    // MARK: Capture

    func start(onChunk: @escaping @Sendable (String) -> Void) throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw PollyAudioError.microphoneUnavailable
        }

        if !isPlayerAttached {
            engine.attach(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
            isPlayerAttached = true
        }

        accumulator.reset()
        let wire = wireFormat
        let muted = mutedFlag
        let accumulator = self.accumulator
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_400, format: inputFormat) { [weak self] buffer, _ in
            // Audio render thread: PCM math + lock-guarded state only.
            let level = Self.rms(of: buffer)
            Task { @MainActor [weak self] in self?.smoothLevel(level) }
            guard !muted.withLock({ $0 }) else { return }
            guard let converted = PCM.resample(buffer, to: wire) else { return }
            accumulator.append(PCM.pcm16Data(from: converted), emit: onChunk)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
        playerNode.play()
        isRunning = true
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if isPlayerAttached { playerNode.stop() }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        accumulator.reset()
        outstandingBuffers = 0
        isPlaying = false
        isRunning = false
        inputLevel = 0
    }

    // MARK: Playback

    /// Decodes a base64 PCM16 24 kHz chunk from the socket and queues it.
    func enqueue(base64: String) {
        guard isRunning,
              let data = Data(base64Encoded: base64),
              let wireBuffer = PCM.buffer(fromPCM16: data, format: wireFormat),
              let playable = PCM.resample(wireBuffer, to: playbackFormat) else { return }

        outstandingBuffers += 1
        isPlaying = true
        playerNode.scheduleBuffer(playable) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.outstandingBuffers = max(0, self.outstandingBuffers - 1)
                self.isPlaying = self.outstandingBuffers > 0
            }
        }
        if !playerNode.isPlaying { playerNode.play() }
    }

    /// Stops assistant playback (barge-in) and reports how many milliseconds
    /// have actually rendered, for `conversation.item.truncate`.
    @discardableResult
    func interruptPlayback() -> Int {
        outstandingBuffers = 0
        isPlaying = false
        guard isPlayerAttached else { return 0 }

        var playedMs = 0
        if let nodeTime = playerNode.lastRenderTime,
           let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
           playerTime.sampleRate > 0 {
            playedMs = max(0, Int(Double(playerTime.sampleTime) * 1_000 / playerTime.sampleRate))
        }
        playerNode.stop()
        return playedMs
    }

    // MARK: Level metering

    private func smoothLevel(_ rawRMS: Float) {
        // Voice RMS rarely exceeds ~0.25; boost before clamping so the orb
        // has range, then smooth so it breathes instead of flickering.
        let boosted = min(1, rawRMS * 4)
        inputLevel = inputLevel * 0.8 + boosted * 0.2
    }

    nonisolated private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0, let channel = buffer.floatChannelData?[0] else { return 0 }
        let step = buffer.stride
        var sum: Float = 0
        for frame in 0..<frames {
            let sample = channel[frame * step]
            sum += sample * sample
        }
        return sqrt(sum / Float(frames))
    }
}

// MARK: - Chunk accumulator

/// Collects converted mic bytes on the audio tap thread and emits fixed-size
/// base64 chunks. Lock-guarded because the tap thread and `reset()` race.
private final class PCMChunkAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let chunkByteCount: Int
    private var pending = Data()

    init(chunkByteCount: Int) {
        self.chunkByteCount = chunkByteCount
    }

    func append(_ data: Data, emit: (String) -> Void) {
        lock.lock()
        pending.append(data)
        var chunks: [Data] = []
        while pending.count >= chunkByteCount {
            chunks.append(Data(pending.prefix(chunkByteCount)))
            pending.removeFirst(chunkByteCount)
        }
        lock.unlock()
        for chunk in chunks {
            emit(chunk.base64EncodedString())
        }
    }

    func reset() {
        lock.lock()
        pending.removeAll()
        lock.unlock()
    }
}
```

Implementation notes locked to the contract (do not deviate):
- `pcm16Data(from:)` reads channel 0 only, honoring `buffer.stride` so interleaved buffers work; floats are clamped to -1...1 before scaling by 32 767, so ±out-of-range maps to ±32 767 (never traps on `Int16` overflow).
- The tap block runs on the audio render thread. It never touches `@MainActor` state directly: mute is mirrored into an `OSAllocatedUnfairLock<Bool>` by `isMuted.didSet`, accumulation happens in the lock-guarded `PCMChunkAccumulator`, and only the RMS level hops to the main actor (ordering there is irrelevant for a meter). Chunks are emitted synchronously from the tap thread in order — `onChunk` is `@Sendable` per the contract, and Task 13's controller forwards them to the transport actor.
- `isMuted` gates emission only; the tap stays installed so unmuting is instant and the echo-canceller keeps its reference signal.
- `enqueue(base64:)` silently drops undecodable chunks (a malformed frame must never kill playback); the outstanding-buffer counter flips `isPlaying` on the main actor from the schedule-completion callback.
- `interruptPlayback()` computes played milliseconds from `playerNode.lastRenderTime` → `playerTime(forNodeTime:)` `sampleTime` before stopping, returning 0 when either is unavailable — exactly what the controller needs for `truncateItem(itemId:audioEndMs:)` after barge-in.
- `stop()` ignores deactivation errors (`try?`) and is safe to call at any time, including before a successful `start()`.

Then regenerate the project so the new source file joins the `Glutt` target:

```bash
cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate
```

Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 4: Run tests — expect green.** Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, includes `testFloatSineRoundTripsThroughPCM16WithinOne`, `testPCM16DataClampsOutOfRangeFloats`, `testResample48kTo24kHalvesFrameCount`, `testPCM16DataPassesThroughInt16BufferUnchanged` (plus all pre-existing suites still green). This also compile-verifies `PollyAudioEngine` in the app target.

- [ ] **Step 5: Commit**

```bash
cd /Users/omarlahmimi/Documents/Glutt
git add Glutt.xcodeproj Glutt/Services/Polly/PollyAudioEngine.swift GluttTests/PCMTests.swift
git commit -m "$(cat <<'EOF'
feat(polly): add echo-cancelled audio engine and PCM utilities

PCM enum converts AVAudioPCMBuffers (float32/int16) to and from the
Realtime wire format (PCM16 LE mono 24 kHz) with clamping, plus
AVAudioConverter-backed resampling. PollyAudioEngine runs the
.playAndRecord/.voiceChat session, taps the mic into ~100 ms base64
chunks with smoothed RMS metering and mute gating, and plays assistant
audio through an AVAudioPlayerNode with barge-in interruption that
reports played milliseconds for conversation.item.truncate.

PCM helpers are unit-tested; the hardware paths are compile-verified
and exercised on-device per the spec's TestFlight testing plan.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
EOF
)"
```

---

### Task 9: PollyCameraController + WatchModeScheduler

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyCameraController.swift` (new file; the `Glutt/Services/Polly/` folder exists since Task 2)
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/WatchModeSchedulerTests.swift` (new file)
- Modify: none. Do **not** touch `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/AI/ImagePrep.swift` — we only copy its `UIGraphicsImageRenderer` downscale pattern (lines 6–20) into the camera controller, because `ImagePrep.prepareForVision` takes `Data` and hardcodes quality 0.65, while we start from a `UIImage` and must use `PollyConfig` knobs.

**Interfaces:**

Consumes (from Task 2 `Glutt/Services/Polly/PollyConfig.swift`):
```swift
PollyConfig.watchFrameInterval: TimeInterval   // 10
PollyConfig.frameMaxDimension: CGFloat         // 1024
PollyConfig.frameJPEGQuality: CGFloat          // 0.6
```

Produces (Task 13 `PollySessionController` owns a `PollyCameraController` + a `WatchModeScheduler`; Task 15 `PollySessionView` renders `previewLayer` and binds the flip/watch controls):
```swift
struct WatchModeScheduler: Equatable {
    var isEnabled: Bool
    var interval: TimeInterval
    private(set) var lastSent: Date?
    init(isEnabled: Bool = false, interval: TimeInterval = PollyConfig.watchFrameInterval)
    mutating func shouldSendFrame(now: Date) -> Bool
}

@MainActor @Observable final class PollyCameraController: NSObject {
    private(set) var isRunning: Bool
    private(set) var isAuthorized: Bool
    let previewLayer: AVCaptureVideoPreviewLayer
    func start() async
    func stop()
    func flip()
    func captureFrame() async -> Data?   // JPEG ≤ PollyConfig.frameMaxDimension, q = frameJPEGQuality
}
```

Simulator/testing boundary (spec: "simulator has no camera"): unit tests cover **only** the pure `WatchModeScheduler`. The controller is written so every hardware touch is guarded — on simulator `AVCaptureDevice.default(...)` returns `nil`, so `start()` leaves `isRunning == false` and `captureFrame()` returns `nil` without crashing. Live camera behavior is verified on device per the plan's device-testing note; no XCTest asserts against capture hardware.

- [ ] **Step 1: Write the failing scheduler tests**

  Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/WatchModeSchedulerTests.swift` with exactly:

  ```swift
  import XCTest
  @testable import Glutt

  final class WatchModeSchedulerTests: XCTestCase {
      private func date(_ seconds: TimeInterval) -> Date {
          Date(timeIntervalSinceReferenceDate: seconds)
      }

      func testDisabledNeverSends() {
          var scheduler = WatchModeScheduler(isEnabled: false, interval: 10)
          XCTAssertFalse(scheduler.shouldSendFrame(now: date(0)))
          XCTAssertFalse(scheduler.shouldSendFrame(now: date(100)))
          XCTAssertNil(scheduler.lastSent, "disabled calls must not record a send")
      }

      func testFirstCallWhenEnabledSends() {
          var scheduler = WatchModeScheduler(isEnabled: true, interval: 10)
          XCTAssertTrue(scheduler.shouldSendFrame(now: date(0)))
          XCTAssertEqual(scheduler.lastSent, date(0))
      }

      func testSecondCallInsideIntervalIsSuppressed() {
          var scheduler = WatchModeScheduler(isEnabled: true, interval: 10)
          XCTAssertTrue(scheduler.shouldSendFrame(now: date(0)))
          XCTAssertFalse(scheduler.shouldSendFrame(now: date(9.9)))
          XCTAssertEqual(scheduler.lastSent, date(0), "a suppressed call must not move lastSent")
      }

      func testCallAfterIntervalSendsAgain() {
          var scheduler = WatchModeScheduler(isEnabled: true, interval: 10)
          XCTAssertTrue(scheduler.shouldSendFrame(now: date(0)))
          XCTAssertTrue(scheduler.shouldSendFrame(now: date(10)), "exactly `interval` later is due (>=)")
          XCTAssertEqual(scheduler.lastSent, date(10))
      }

      func testReEnableKeepsLastSentGate() {
          var scheduler = WatchModeScheduler(isEnabled: true, interval: 10)
          XCTAssertTrue(scheduler.shouldSendFrame(now: date(0)))
          scheduler.isEnabled = false
          XCTAssertFalse(scheduler.shouldSendFrame(now: date(5)))
          scheduler.isEnabled = true
          XCTAssertFalse(scheduler.shouldSendFrame(now: date(5)), "re-enabling must not reset the gate")
          XCTAssertTrue(scheduler.shouldSendFrame(now: date(12)))
      }

      func testDefaultsMatchPollyConfig() {
          let scheduler = WatchModeScheduler()
          XCTAssertFalse(scheduler.isEnabled)
          XCTAssertEqual(scheduler.interval, PollyConfig.watchFrameInterval)
          XCTAssertNil(scheduler.lastSent)
      }
  }
  ```

- [ ] **Step 2: Regenerate the project and watch the tests fail**

  Run `xcodegen generate` from `/Users/omarlahmimi/Documents/Glutt` (Bash) so the new test file joins the `GluttTests` target. Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

  Run tests: `test_sim` (scheme `Glutt`) — expected: **FAIL** — the `GluttTests` target does not compile: `cannot find 'WatchModeScheduler' in scope` in `WatchModeSchedulerTests.swift`. Do not proceed until you have seen this failure.

- [ ] **Step 3: Implement `WatchModeScheduler` + `PollyCameraController`**

  Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyCameraController.swift` with exactly:

  ```swift
  import AVFoundation
  import CoreImage
  import Observation
  import UIKit

  /// Sliding-gate policy for watch mode: at most one frame per `interval` while
  /// enabled. Pure and synchronous — the session controller drives it with its
  /// injected clock, and tests drive it with fixed dates. No timers in here.
  struct WatchModeScheduler: Equatable {
      var isEnabled: Bool
      var interval: TimeInterval
      private(set) var lastSent: Date?

      init(isEnabled: Bool = false, interval: TimeInterval = PollyConfig.watchFrameInterval) {
          self.isEnabled = isEnabled
          self.interval = interval
      }

      /// True when a frame is due right now; records `now` as the send time on
      /// true. Toggling `isEnabled` never resets `lastSent` — re-enabling watch
      /// mode mid-interval must not burst an extra frame (cost control).
      mutating func shouldSendFrame(now: Date) -> Bool {
          guard isEnabled else { return false }
          if let last = lastSent, now.timeIntervalSince(last) < interval { return false }
          lastSent = now
          return true
      }
  }

  /// Live camera for Polly sessions: 720p capture, back wide camera by default,
  /// flippable, keeps only the latest frame for on-demand JPEG snapshots.
  /// Every hardware touch is guarded so the simulator (no camera) just leaves
  /// `isRunning == false` and `captureFrame()` returning nil.
  @MainActor
  @Observable
  final class PollyCameraController: NSObject {
      private(set) var isRunning = false
      private(set) var isAuthorized = false
      let previewLayer: AVCaptureVideoPreviewLayer

      private let session = AVCaptureSession()
      private let output = AVCaptureVideoDataOutput()
      private let frameSink = LatestFrameSink()
      private let sampleQueue = DispatchQueue(label: "com.omarlahmimi.glutt.polly.camera")
      private var position: AVCaptureDevice.Position = .back

      override init() {
          previewLayer = AVCaptureVideoPreviewLayer(session: session)
          previewLayer.videoGravity = .resizeAspectFill
          super.init()
      }

      /// Requests camera permission if needed, then configures and starts the
      /// session off-main (`startRunning` blocks). On simulator or when denied,
      /// returns with `isRunning == false`.
      func start() async {
          guard !isRunning else { return }
          isAuthorized = await requestAuthorization()
          guard isAuthorized, configureSession(position: position) else { return }

          let session = self.session
          await Task.detached { session.startRunning() }.value
          isRunning = session.isRunning
      }

      func stop() {
          guard isRunning else { return }
          isRunning = false
          let session = self.session
          Task.detached { session.stopRunning() }
      }

      /// Swaps to the opposite camera. Reconfiguration happens inside
      /// beginConfiguration/commitConfiguration so the session never tears down.
      func flip() {
          guard isRunning else { return }
          position = (position == .back) ? .front : .back
          configureSession(position: position)
      }

      /// Latest frame as a JPEG, downscaled to `PollyConfig.frameMaxDimension`
      /// at `PollyConfig.frameJPEGQuality` — same UIGraphicsImageRenderer
      /// approach as `ImagePrep.prepareForVision`. Nil when not running or no
      /// frame has arrived yet.
      func captureFrame() async -> Data? {
          guard isRunning, let image = frameSink.latestImage() else { return nil }
          let maxDimension = PollyConfig.frameMaxDimension
          let quality = PollyConfig.frameJPEGQuality

          return await Task.detached { () -> Data? in
              let largestSide = max(image.size.width, image.size.height)
              guard largestSide > 0 else { return nil }

              let scale = min(1, maxDimension / largestSide)
              let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

              let format = UIGraphicsImageRendererFormat()
              format.scale = 1
              let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                  image.draw(in: CGRect(origin: .zero, size: newSize))
              }
              return resized.jpegData(compressionQuality: quality)
          }.value
      }

      // MARK: - Session plumbing

      private func requestAuthorization() async -> Bool {
          switch AVCaptureDevice.authorizationStatus(for: .video) {
          case .authorized: return true
          case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
          default: return false
          }
      }

      /// Installs the input for `position` (replacing any existing input) and
      /// the shared data output. Returns false when no camera device exists
      /// (simulator) or the session rejects the input.
      @discardableResult
      private func configureSession(position: AVCaptureDevice.Position) -> Bool {
          session.beginConfiguration()
          defer { session.commitConfiguration() }

          session.sessionPreset = .hd1280x720
          for input in session.inputs { session.removeInput(input) }
          guard
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
          else { return false }
          session.addInput(input)

          if !session.outputs.contains(output) {
              output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
              output.alwaysDiscardsLateVideoFrames = true
              output.setSampleBufferDelegate(frameSink, queue: sampleQueue)
              guard session.canAddOutput(output) else { return false }
              session.addOutput(output)
          }

          // Portrait-only app: keep frames upright so Polly isn't judging
          // sideways pancakes.
          if let connection = output.connection(with: .video),
             connection.isVideoRotationAngleSupported(90) {
              connection.videoRotationAngle = 90
          }
          return true
      }

      /// Sample-buffer delegate that retains only the most recent pixel buffer.
      /// Callbacks land on the capture serial queue; the lock makes reads safe
      /// from the main actor. Explicitly nonisolated — it must never hop to the
      /// main actor the enclosing controller lives on.
      private final class LatestFrameSink: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
          private nonisolated(unsafe) let lock = NSLock()
          private nonisolated(unsafe) var latestBuffer: CVPixelBuffer?

          nonisolated func captureOutput(_ output: AVCaptureOutput,
                                         didOutput sampleBuffer: CMSampleBuffer,
                                         from connection: AVCaptureConnection) {
              guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
              lock.lock()
              latestBuffer = buffer
              lock.unlock()
          }

          nonisolated func latestImage() -> UIImage? {
              lock.lock()
              let buffer = latestBuffer
              lock.unlock()
              guard let buffer else { return nil }

              let ciImage = CIImage(cvPixelBuffer: buffer)
              guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
              return UIImage(cgImage: cgImage)
          }
      }
  }
  ```

- [ ] **Step 4: Regenerate and run the tests green**

  Run `xcodegen generate` from `/Users/omarlahmimi/Documents/Glutt` (Bash) so the new source file joins the `Glutt` target. Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

  Run tests: `test_sim` (scheme `Glutt`) — expected: **PASS**, includes `WatchModeSchedulerTests/testDisabledNeverSends`, `testFirstCallWhenEnabledSends`, `testSecondCallInsideIntervalIsSuppressed`, `testCallAfterIntervalSendsAgain`, `testReEnableKeepsLastSentGate`, `testDefaultsMatchPollyConfig`, plus all pre-existing suites still green.

  If the app target fails to compile, fix within this file only (the contract surface above must not change) and re-run `test_sim` until green.

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/omarlahmimi/Documents/Glutt
  git add Glutt.xcodeproj Glutt/Services/Polly/PollyCameraController.swift GluttTests/WatchModeSchedulerTests.swift
  git commit -m "$(cat <<'EOF'
  feat(polly): add live camera controller and watch-mode frame scheduler

  WatchModeScheduler is a pure sliding gate (>= interval, lastSent survives
  toggles) driven by the session controller's clock. PollyCameraController
  wraps a 720p AVCaptureSession (back wide default, flippable inside
  begin/commitConfiguration) with a latest-frame sink and captureFrame()
  producing PollyConfig-sized JPEGs; all hardware paths are guarded so the
  simulator stays isRunning == false with nil frames.

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
  EOF
  )"
  ```

---

### Task 10: PollyToolRegistry + CookState (the chef's hands)

**Files:**
- Create: `Glutt/Services/Polly/PollyToolRegistry.swift`
- Test: `GluttTests/PollyToolRegistryTests.swift`
- Modify: none.
- Read-only dependencies (do NOT modify): `Glutt/Services/PantryMatcher.swift:27` (`match(recipe:pantry:)` + `MatchResult`), `Glutt/Services/SubstitutionService.swift:87-109` (`isEssential(_:)`, `availableSubstitutions(for:pantry:rules:allergies:)`), `Glutt/Services/NutritionEstimator.swift:71` (`estimate(for:) -> Estimate?`), `Glutt/Services/TimerManager.swift:30-41` (`start(label:seconds:)`, `cancel(_:)`, `timers`, `CookTimer.remainingSeconds(at:)`), `Glutt/Models/UserPrefs.swift:13-14` (`dietaryRules`, `allergies`), `Glutt/Models/Kitchen.swift:4-42` (`PantryItem`), `Glutt/Models/Recipe.swift:36-37` (`calories`, `proteinGrams`), `Glutt/Services/DietGuard.swift:131` (`isAllowed(ingredientName:rules:allergies:)`, used by the test assertions only).

**Interfaces:**
- Consumes:
  - Task 2: `CookPlan` (`title`, `servings`, `steps`), `CookPlan.PlanStep` (memberwise `init(id:index:title:instruction:kind:estimatedSeconds:timerSeconds:dependsOn:visualCheck:recovery:ingredientNames:)`, `kind: StepKind`, `timerSeconds: Int?`, `visualCheck: String?`, `ingredientNames: [String]`), `CookPlan.StepKind` rawValues.
  - Task 3: `enum MemoryKind: String, Codable, CaseIterable { case equipment, technique, pantryHabit, preference, outcome }`; `@Model final class PollyMemory`; `PollyMemoryStore.upsert(kind:text:confidence:sourceRecipeTitle:in:) -> PollyMemory` (`@discardableResult`).
  - Task 6: `RealtimeToolDefinition(name: String, description: String, parameters: JSONValue)`; `enum JSONValue` (`.string/.number/.bool/.null/.array/.object`).
  - Existing services listed under Files above.
- Produces (consumed by Task 11 prompt builder policy text, Task 13 controller, Task 15 UI):

```swift
struct CookState: Equatable {
    var stepIndex: Int = 0
    var completedStepIDs: Set<String> = []
    var substitutions: [String] = []
    var servings: Int
}
@MainActor final class PollyToolRegistry {
    static let toolDefinitions: [RealtimeToolDefinition]   // all 13, names locked
    private(set) var state: CookState
    var onRequestFrame: (() async -> Bool)?    // controller captures+sends; true on success
    var onEndSession: (() -> Void)?
    init(plan: CookPlan, recipe: Recipe, pantry: [PantryItem], prefs: UserPrefs,
         timers: TimerManager, context: ModelContext)
    func handle(name: String, argumentsJSON: String) async -> String  // JSON string result
}
// Tool names (locked): get_current_step, mark_step_done, go_to_step, start_timer,
// check_timers, cancel_timer, check_pantry, find_substitutes, get_nutrition,
// adjust_servings, remember_fact, request_camera_frame, end_session
```

Locked behavioral decisions (do not improvise):
- Argument parsing is lenient: empty/whitespace `argumentsJSON` is treated as `{}`; anything that isn't a JSON object → `{"error":"bad arguments"}`. A missing/mistyped required field (e.g. `go_to_step` without `index`) is also `{"error":"bad arguments"}`. Unknown tool name → `{"error":"unknown tool"}`.
- `find_substitutes` never writes to `state.substitutions`. The ONLY path into `state.substitutions` is `remember_fact` with text starting `"substituted"` (case-insensitive, after trimming). The `remember_fact` tool description tells the model to use exactly that phrasing.
- `remember_fact` with an unknown `kind` string degrades to `.outcome` (mirrors `PollyMemory.kind`'s fallback); missing `confidence` defaults to `0.7`, and values clamp to `0...1`.
- `get_nutrition` order: recipe `calories` present → echo stored macros (no confidence key); else `NutritionEstimator.estimate(for:)` → calories/protein/confidence; else `{"available":false}`.
- `adjust_servings.scaleFromOriginal` is `Double(newServings) / Double(max(1, recipe.servings))` — "original" means the recipe as written, which is what the model needs to scale written quantities.
- All results are built with `JSONSerialization` (+`.sortedKeys` for stable output); tests parse results back into dictionaries and never string-compare.

- [ ] **Step 1: Write the failing test file**

Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyToolRegistryTests.swift` with exactly this content:

```swift
import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PollyToolRegistryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var recipe: Recipe!
    private var prefs: UserPrefs!
    private var pantry: [PantryItem]!
    private var plan: CookPlan!
    private var timers: TimerManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
            PantryItem.self, UserPrefs.self, PollyMemory.self, PollyCookLog.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        context = ModelContext(container)

        recipe = Recipe(title: "Lemon Garlic Chicken", servings: 2)
        recipe.calories = 520
        recipe.proteinGrams = 42
        context.insert(recipe)
        recipe.ingredients = [
            RecipeIngredient(name: "chicken breast", sortIndex: 0),
            RecipeIngredient(name: "butter", sortIndex: 1),
            RecipeIngredient(name: "heavy cream", sortIndex: 2),
            RecipeIngredient(name: "parsley", isOptional: true, sortIndex: 3),
        ]

        // Owns 2 of the 3 required ingredients (heavy cream missing), plus the
        // stock needed for the substitution assertions.
        pantry = [
            PantryItem(name: "chicken breast"),
            PantryItem(name: "butter"),
            PantryItem(name: "olive oil"),
            PantryItem(name: "sour cream"),
            PantryItem(name: "greek yogurt"),
        ]
        pantry.forEach { context.insert($0) }

        prefs = UserPrefs.current(in: context)
        prefs.dietaryRules = [.halal]
        prefs.allergies = ["yogurt"]

        plan = CookPlan(
            title: "Lemon Garlic Chicken",
            servings: 2,
            steps: [
                CookPlan.PlanStep(
                    id: "s1", index: 0, title: "Sear the chicken",
                    instruction: "Sear the chicken breast in butter, 4 minutes per side.",
                    kind: .active, ingredientNames: ["chicken breast", "butter"]
                ),
                CookPlan.PlanStep(
                    id: "s2", index: 1, title: "Simmer the sauce",
                    instruction: "Pour in the cream and simmer gently for 5 minutes.",
                    kind: .passive, timerSeconds: 300, dependsOn: ["s1"],
                    ingredientNames: ["heavy cream"]
                ),
                CookPlan.PlanStep(
                    id: "s3", index: 2, title: "Rest and serve",
                    instruction: "Rest for a few minutes, garnish, and serve.",
                    kind: .checkpoint, dependsOn: ["s2"],
                    visualCheck: "Sauce should coat the back of a spoon.",
                    ingredientNames: ["parsley"]
                ),
            ]
        )
        timers = TimerManager()
    }

    override func tearDownWithError() throws {
        timers.cancelAll()
        timers = nil
        plan = nil
        pantry = nil
        prefs = nil
        recipe = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeRegistry() -> PollyToolRegistry {
        PollyToolRegistry(plan: plan, recipe: recipe, pantry: pantry, prefs: prefs,
                          timers: timers, context: context)
    }

    /// Parses a handler result back into a dictionary so assertions never
    /// depend on JSON key order.
    private func result(of json: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(object as? [String: Any], "handler must return a JSON object")
    }

    // MARK: - (g) Tool definitions

    func testToolDefinitionsMatchLockedNames() {
        let names = PollyToolRegistry.toolDefinitions.map(\.name)
        XCTAssertEqual(names, [
            "get_current_step", "mark_step_done", "go_to_step", "start_timer",
            "check_timers", "cancel_timer", "check_pantry", "find_substitutes",
            "get_nutrition", "adjust_servings", "remember_fact",
            "request_camera_frame", "end_session",
        ])
        XCTAssertEqual(PollyToolRegistry.toolDefinitions.count, 13)

        for definition in PollyToolRegistry.toolDefinitions {
            XCTAssertFalse(definition.description.isEmpty, definition.name)
            guard case .object(let schema) = definition.parameters else {
                XCTFail("\(definition.name) parameters must be an object schema")
                continue
            }
            XCTAssertEqual(schema["type"], .string("object"), definition.name)
        }
    }

    // MARK: - (a) Step navigation

    func testStepNavigationFlow() async throws {
        let registry = makeRegistry()
        XCTAssertEqual(registry.state.stepIndex, 0)
        XCTAssertEqual(registry.state.servings, 2)
        XCTAssertTrue(registry.state.substitutions.isEmpty)

        let first = try result(of: await registry.handle(name: "get_current_step", argumentsJSON: "{}"))
        XCTAssertEqual(first["index"] as? Int, 0)
        XCTAssertEqual(first["total"] as? Int, 3)
        XCTAssertEqual(first["title"] as? String, "Sear the chicken")
        XCTAssertEqual(first["kind"] as? String, "active")
        XCTAssertEqual(first["ingredients"] as? [String], ["chicken breast", "butter"])
        XCTAssertNil(first["timerSeconds"], "step 1 has no timer, so the key is omitted")
        XCTAssertNil(first["visualCheck"])

        let second = try result(of: await registry.handle(name: "mark_step_done", argumentsJSON: "{}"))
        XCTAssertEqual(second["index"] as? Int, 1)
        XCTAssertEqual(second["kind"] as? String, "passive")
        XCTAssertEqual(second["timerSeconds"] as? Int, 300)
        XCTAssertTrue(registry.state.completedStepIDs.contains("s1"))
        XCTAssertEqual(registry.state.stepIndex, 1)

        let clampedHigh = try result(of: await registry.handle(name: "go_to_step", argumentsJSON: #"{"index": 99}"#))
        XCTAssertEqual(clampedHigh["index"] as? Int, 2, "out-of-range index clamps to the last step")
        XCTAssertEqual(clampedHigh["visualCheck"] as? String, "Sauce should coat the back of a spoon.")

        let clampedLow = try result(of: await registry.handle(name: "go_to_step", argumentsJSON: #"{"index": -5}"#))
        XCTAssertEqual(clampedLow["index"] as? Int, 0, "negative index clamps to the first step")

        _ = await registry.handle(name: "go_to_step", argumentsJSON: #"{"index": 2}"#)
        let done = try result(of: await registry.handle(name: "mark_step_done", argumentsJSON: "{}"))
        XCTAssertEqual(done["done"] as? Bool, true)
        XCTAssertTrue(registry.state.completedStepIDs.contains("s3"))
        XCTAssertEqual(registry.state.stepIndex, 2, "index stays clamped at the last step")

        let doneAgain = try result(of: await registry.handle(name: "mark_step_done", argumentsJSON: "{}"))
        XCTAssertEqual(doneAgain["done"] as? Bool, true, "marking done at the end is idempotent")
    }

    // MARK: - (b) Timers

    func testTimerStartCheckCancel() async throws {
        let registry = makeRegistry()

        let started = try result(of: await registry.handle(
            name: "start_timer", argumentsJSON: #"{"label": "Simmer sauce", "seconds": 300}"#))
        XCTAssertEqual(started["started"] as? Bool, true)
        XCTAssertEqual(started["label"] as? String, "Simmer sauce")
        XCTAssertEqual(started["seconds"] as? Int, 300)
        XCTAssertEqual(timers.timers.count, 1)

        let checked = try result(of: await registry.handle(name: "check_timers", argumentsJSON: "{}"))
        let running = try XCTUnwrap(checked["timers"] as? [[String: Any]])
        XCTAssertEqual(running.count, 1)
        XCTAssertEqual(running[0]["label"] as? String, "Simmer sauce")
        let remaining = try XCTUnwrap(running[0]["remainingSeconds"] as? Int)
        XCTAssertTrue((295...300).contains(remaining), "just-started 300s timer, got \(remaining)")

        let cancelled = try result(of: await registry.handle(
            name: "cancel_timer", argumentsJSON: #"{"label": "simmer SAUCE"}"#))
        XCTAssertEqual(cancelled["cancelled"] as? Bool, true, "label match is case-insensitive")
        XCTAssertEqual(cancelled["label"] as? String, "Simmer sauce")
        XCTAssertTrue(timers.timers.isEmpty)

        let missing = try result(of: await registry.handle(
            name: "cancel_timer", argumentsJSON: #"{"label": "Simmer sauce"}"#))
        XCTAssertEqual(missing["error"] as? String, "no such timer")
    }

    // MARK: - (c) Pantry

    func testCheckPantryCountsAndMissingNames() async throws {
        let registry = makeRegistry()
        let payload = try result(of: await registry.handle(name: "check_pantry", argumentsJSON: "{}"))
        XCTAssertEqual(payload["ownedCount"] as? Int, 2)
        XCTAssertEqual(payload["totalCount"] as? Int, 3, "optional ingredients never count toward the total")
        XCTAssertEqual(payload["missing"] as? [String], ["heavy cream"])
        XCTAssertEqual(payload["missingOptional"] as? [String], ["parsley"])
    }

    // MARK: - (d) Substitutes

    func testFindSubstitutesRespectsPantryAndDietGuard() async throws {
        let registry = makeRegistry()

        let butter = try result(of: await registry.handle(
            name: "find_substitutes", argumentsJSON: #"{"ingredient": "butter"}"#))
        let butterSubs = try XCTUnwrap(butter["substitutes"] as? [[String: Any]])
        XCTAssertEqual(butterSubs.compactMap { $0["name"] as? String }, ["olive oil"])
        XCTAssertEqual(butter["isEssential"] as? Bool, false)
        for sub in butterSubs {
            let name = try XCTUnwrap(sub["name"] as? String)
            XCTAssertTrue(DietGuard.isAllowed(ingredientName: name, rules: [.halal], allergies: ["yogurt"]),
                          "every returned substitute must pass DietGuard")
            XCTAssertFalse((sub["explanation"] as? String ?? "").isEmpty)
        }

        // "Greek yogurt + butter" trips the yogurt allergy; only sour cream survives.
        let cream = try result(of: await registry.handle(
            name: "find_substitutes", argumentsJSON: #"{"ingredient": "heavy cream"}"#))
        let creamSubs = try XCTUnwrap(cream["substitutes"] as? [[String: Any]])
        XCTAssertEqual(creamSubs.compactMap { $0["name"] as? String }, ["sour cream"])

        let chicken = try result(of: await registry.handle(
            name: "find_substitutes", argumentsJSON: #"{"ingredient": "chicken"}"#))
        XCTAssertEqual(chicken["isEssential"] as? Bool, true)
        XCTAssertEqual((chicken["substitutes"] as? [[String: Any]])?.count, 0)

        XCTAssertTrue(registry.state.substitutions.isEmpty,
                      "find_substitutes must never record a substitution by itself")
    }

    // MARK: - (e) Memory

    func testRememberFactWritesMemoryAndRecordsSubstitutions() async throws {
        let registry = makeRegistry()

        let remembered = try result(of: await registry.handle(
            name: "remember_fact",
            argumentsJSON: #"{"kind": "equipment", "text": "Owns a cast iron skillet", "confidence": 0.9}"#))
        XCTAssertEqual(remembered["remembered"] as? Bool, true)

        var memories = try context.fetch(FetchDescriptor<PollyMemory>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].kind, .equipment)
        XCTAssertEqual(memories[0].confidence, 0.9)
        XCTAssertEqual(memories[0].sourceRecipeTitle, "Lemon Garlic Chicken")
        XCTAssertTrue(registry.state.substitutions.isEmpty, "a plain fact is not a substitution")

        _ = await registry.handle(
            name: "remember_fact",
            argumentsJSON: #"{"kind": "outcome", "text": "Substituted olive oil for butter in Lemon Garlic Chicken"}"#)
        XCTAssertEqual(registry.state.substitutions,
                       ["Substituted olive oil for butter in Lemon Garlic Chicken"],
                       "text starting with 'Substituted' lands in state.substitutions")

        // Unknown kind degrades to .outcome; missing confidence defaults to 0.7.
        _ = await registry.handle(
            name: "remember_fact",
            argumentsJSON: #"{"kind": "horoscope", "text": "Prefers crispy edges"}"#)
        memories = try context.fetch(FetchDescriptor<PollyMemory>())
        XCTAssertEqual(memories.count, 3)
        let fallback = try XCTUnwrap(memories.first { $0.text == "Prefers crispy edges" })
        XCTAssertEqual(fallback.kind, .outcome)
        XCTAssertEqual(fallback.confidence, 0.7)
    }

    // MARK: - (f) Error paths

    func testUnknownToolAndBadArguments() async throws {
        let registry = makeRegistry()

        let unknown = try result(of: await registry.handle(name: "fly_to_the_moon", argumentsJSON: "{}"))
        XCTAssertEqual(unknown["error"] as? String, "unknown tool")

        let badJSON = try result(of: await registry.handle(name: "go_to_step", argumentsJSON: "step two please"))
        XCTAssertEqual(badJSON["error"] as? String, "bad arguments")

        let missingField = try result(of: await registry.handle(name: "go_to_step", argumentsJSON: "{}"))
        XCTAssertEqual(missingField["error"] as? String, "bad arguments")

        let wrongTypes = try result(of: await registry.handle(
            name: "start_timer", argumentsJSON: #"{"label": 7, "seconds": "soon"}"#))
        XCTAssertEqual(wrongTypes["error"] as? String, "bad arguments")

        let noText = try result(of: await registry.handle(
            name: "remember_fact", argumentsJSON: #"{"kind": "equipment"}"#))
        XCTAssertEqual(noText["error"] as? String, "bad arguments")

        let emptyArgs = try result(of: await registry.handle(name: "get_current_step", argumentsJSON: ""))
        XCTAssertEqual(emptyArgs["index"] as? Int, 0, "empty arguments string is treated as {}")
    }

    // MARK: - Nutrition

    func testGetNutritionPrefersRecipeMacrosThenEstimatorThenUnavailable() async throws {
        // Stored macros win.
        let direct = try result(of: await makeRegistry().handle(name: "get_nutrition", argumentsJSON: "{}"))
        XCTAssertEqual(direct["available"] as? Bool, true)
        XCTAssertEqual(direct["calories"] as? Int, 520)
        XCTAssertEqual(direct["protein"] as? Int, 42)

        // No stored macros -> NutritionEstimator over the ingredients.
        recipe.calories = nil
        recipe.proteinGrams = nil
        let estimated = try result(of: await makeRegistry().handle(name: "get_nutrition", argumentsJSON: "{}"))
        XCTAssertEqual(estimated["available"] as? Bool, true)
        let calories = try XCTUnwrap(estimated["calories"] as? Int)
        XCTAssertGreaterThan(calories, 0)
        let confidence = try XCTUnwrap(estimated["confidence"] as? Double)
        XCTAssertTrue((0...1).contains(confidence))

        // No macros and no recognizable ingredients -> honest unavailable.
        let bare = Recipe(title: "Mystery Dish")
        context.insert(bare)
        let bareRegistry = PollyToolRegistry(
            plan: CookPlan(title: "Mystery Dish", servings: 2),
            recipe: bare, pantry: [], prefs: prefs, timers: timers, context: context
        )
        let unavailable = try result(of: await bareRegistry.handle(name: "get_nutrition", argumentsJSON: "{}"))
        XCTAssertEqual(unavailable["available"] as? Bool, false)
    }

    // MARK: - Servings

    func testAdjustServingsUpdatesStateAndReturnsScale() async throws {
        let registry = makeRegistry()
        let payload = try result(of: await registry.handle(
            name: "adjust_servings", argumentsJSON: #"{"servings": 4}"#))
        XCTAssertEqual(payload["servings"] as? Int, 4)
        let scale = try XCTUnwrap(payload["scaleFromOriginal"] as? Double)
        XCTAssertEqual(scale, 2.0, accuracy: 0.0001, "recipe is written for 2 servings")
        XCTAssertEqual(registry.state.servings, 4)

        let bad = try result(of: await registry.handle(
            name: "adjust_servings", argumentsJSON: #"{"servings": 0}"#))
        XCTAssertEqual(bad["error"] as? String, "bad arguments")
        XCTAssertEqual(registry.state.servings, 4, "rejected call must not touch state")
    }

    // MARK: - Camera + end hooks

    func testRequestCameraFrameAndEndSessionHooks() async throws {
        let registry = makeRegistry()

        let noCamera = try result(of: await registry.handle(name: "request_camera_frame", argumentsJSON: "{}"))
        XCTAssertEqual(noCamera["captured"] as? Bool, false)
        XCTAssertEqual(noCamera["reason"] as? String, "camera unavailable")

        registry.onRequestFrame = { true }
        let captured = try result(of: await registry.handle(name: "request_camera_frame", argumentsJSON: "{}"))
        XCTAssertEqual(captured["captured"] as? Bool, true)

        registry.onRequestFrame = { false }
        let failed = try result(of: await registry.handle(name: "request_camera_frame", argumentsJSON: "{}"))
        XCTAssertEqual(failed["captured"] as? Bool, false)
        XCTAssertEqual(failed["reason"] as? String, "frame capture failed")

        var ended = false
        registry.onEndSession = { ended = true }
        let ending = try result(of: await registry.handle(name: "end_session", argumentsJSON: "{}"))
        XCTAssertEqual(ending["ending"] as? Bool, true)
        XCTAssertTrue(ended)
    }
}
```

- [ ] **Step 2: Run the tests — expect the red failure**

Run `xcodegen generate` (Bash, from the repo root) so the new test file joins the `GluttTests` target. Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`. If this is the session's first XcodeBuildMCP call, call `session_show_defaults` first (project `Glutt.xcodeproj`, scheme `Glutt`, an iOS 17+ iPhone simulator).

Run tests: `test_sim` (scheme `Glutt`) — expected: FAIL — the test target does not compile: `cannot find 'PollyToolRegistry' in scope` (and `cannot find 'CookState' in scope`) in `PollyToolRegistryTests.swift`. This is the red step; do not proceed until you have seen this exact failure.

- [ ] **Step 3: Implement the registry**

Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyToolRegistry.swift` with exactly this content:

```swift
import Foundation
import SwiftData

/// Live cook-session state that the realtime tools read and mutate.
/// Owned by the registry; the controller reads it when writing the cook log.
struct CookState: Equatable {
    var stepIndex: Int = 0
    var completedStepIDs: Set<String> = []
    var substitutions: [String] = []
    var servings: Int
}

/// Polly's hands: maps Realtime function calls onto Glutt's existing pure
/// services (plan steps, timers, pantry, substitutions, nutrition, memory).
/// Every handler returns a compact JSON string ready to ship back as a
/// `function_call_output` item.
@MainActor
final class PollyToolRegistry {

    // MARK: - State

    private(set) var state: CookState
    /// Controller hook: capture + send a camera frame; true on success.
    var onRequestFrame: (() async -> Bool)?
    /// Controller hook: the model asked to end the session.
    var onEndSession: (() -> Void)?

    private let plan: CookPlan
    private let recipe: Recipe
    private let pantry: [PantryItem]
    private let prefs: UserPrefs
    private let timers: TimerManager
    private let context: ModelContext

    init(plan: CookPlan, recipe: Recipe, pantry: [PantryItem], prefs: UserPrefs,
         timers: TimerManager, context: ModelContext) {
        self.plan = plan
        self.recipe = recipe
        self.pantry = pantry
        self.prefs = prefs
        self.timers = timers
        self.context = context
        self.state = CookState(servings: plan.servings > 0 ? plan.servings : max(1, recipe.servings))
    }

    // MARK: - Tool definitions (13, names locked)

    static let toolDefinitions: [RealtimeToolDefinition] = [
        RealtimeToolDefinition(
            name: "get_current_step",
            description: "Get the step the cook is on right now: title, instruction, kind, timer, and the ingredients it uses.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "mark_step_done",
            description: "Mark the current step complete and move to the next one. Returns the next step, or {\"done\":true} after the final step.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "go_to_step",
            description: "Jump to a step by zero-based index. Out-of-range indexes clamp to the first or last step.",
            parameters: schema(
                properties: ["index": .object([
                    "type": .string("integer"),
                    "description": .string("Zero-based step index"),
                ])],
                required: ["index"]
            )
        ),
        RealtimeToolDefinition(
            name: "start_timer",
            description: "Start a countdown timer with a short label the cook will recognize.",
            parameters: schema(
                properties: [
                    "label": .object([
                        "type": .string("string"),
                        "description": .string("Short label, e.g. 'Simmer sauce'"),
                    ]),
                    "seconds": .object([
                        "type": .string("integer"),
                        "description": .string("Countdown length in seconds"),
                    ]),
                ],
                required: ["label", "seconds"]
            )
        ),
        RealtimeToolDefinition(
            name: "check_timers",
            description: "List every running timer and its remaining seconds.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "cancel_timer",
            description: "Cancel a running timer by label (case-insensitive).",
            parameters: schema(
                properties: ["label": .object(["type": .string("string")])],
                required: ["label"]
            )
        ),
        RealtimeToolDefinition(
            name: "check_pantry",
            description: "Check the recipe's ingredients against the cook's pantry: how many they own, and what's missing.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "find_substitutes",
            description: "Find substitutes for an ingredient that the cook has on hand and that respect their dietary rules and allergies.",
            parameters: schema(
                properties: ["ingredient": .object([
                    "type": .string("string"),
                    "description": .string("Ingredient name as written in the recipe"),
                ])],
                required: ["ingredient"]
            )
        ),
        RealtimeToolDefinition(
            name: "get_nutrition",
            description: "Get per-serving calories and protein for this recipe, with a confidence score when the numbers are estimated.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "adjust_servings",
            description: "Change the number of servings being cooked. Returns the scale factor versus the recipe as written.",
            parameters: schema(
                properties: ["servings": .object([
                    "type": .string("integer"),
                    "description": .string("New serving count, at least 1"),
                ])],
                required: ["servings"]
            )
        ),
        RealtimeToolDefinition(
            name: "remember_fact",
            description: "Save one durable fact about the cook's kitchen, technique, habits, or how this dish turned out. When the cook substitutes an ingredient, call this with text starting: Substituted X for Y in <recipe>.",
            parameters: schema(
                properties: [
                    "kind": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("equipment"), .string("technique"), .string("pantryHabit"),
                            .string("preference"), .string("outcome"),
                        ]),
                    ]),
                    "text": .object([
                        "type": .string("string"),
                        "description": .string("One short sentence, third person"),
                    ]),
                    "confidence": .object([
                        "type": .string("number"),
                        "description": .string("0 to 1, how sure you are"),
                    ]),
                ],
                required: ["kind", "text"]
            )
        ),
        RealtimeToolDefinition(
            name: "request_camera_frame",
            description: "Request a fresh photo from the cook's camera when you need to see the food before answering.",
            parameters: emptySchema
        ),
        RealtimeToolDefinition(
            name: "end_session",
            description: "End the cooking session. Call only when the cook says they are finished or asks to stop.",
            parameters: emptySchema
        ),
    ]

    private static let emptySchema: JSONValue = .object([
        "type": .string("object"),
        "properties": .object([:]),
        "required": .array([]),
    ])

    private static func schema(properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
        ])
    }

    // MARK: - Dispatch

    func handle(name: String, argumentsJSON: String) async -> String {
        guard let args = Self.parseArguments(argumentsJSON) else {
            return Self.json(["error": "bad arguments"])
        }
        switch name {
        case "get_current_step": return getCurrentStep()
        case "mark_step_done": return markStepDone()
        case "go_to_step": return goToStep(args)
        case "start_timer": return startTimer(args)
        case "check_timers": return checkTimers()
        case "cancel_timer": return cancelTimer(args)
        case "check_pantry": return checkPantry()
        case "find_substitutes": return findSubstitutes(args)
        case "get_nutrition": return getNutrition()
        case "adjust_servings": return adjustServings(args)
        case "remember_fact": return rememberFact(args)
        case "request_camera_frame": return await requestCameraFrame()
        case "end_session": return endSession()
        default: return Self.json(["error": "unknown tool"])
        }
    }

    // MARK: - Steps

    private func clampedIndex(_ index: Int) -> Int {
        min(max(index, 0), max(plan.steps.count - 1, 0))
    }

    private func stepPayload(at index: Int) -> [String: Any] {
        let step = plan.steps[index]
        var payload: [String: Any] = [
            "index": index,
            "total": plan.steps.count,
            "title": step.title,
            "instruction": step.instruction,
            "kind": step.kind.rawValue,
            "ingredients": step.ingredientNames,
        ]
        if let timerSeconds = step.timerSeconds { payload["timerSeconds"] = timerSeconds }
        if let visualCheck = step.visualCheck { payload["visualCheck"] = visualCheck }
        return payload
    }

    private func getCurrentStep() -> String {
        guard !plan.steps.isEmpty else { return Self.json(["done": true]) }
        return Self.json(stepPayload(at: clampedIndex(state.stepIndex)))
    }

    private func markStepDone() -> String {
        guard !plan.steps.isEmpty else { return Self.json(["done": true]) }
        let current = clampedIndex(state.stepIndex)
        state.completedStepIDs.insert(plan.steps[current].id)
        guard current + 1 < plan.steps.count else {
            state.stepIndex = current
            return Self.json(["done": true])
        }
        state.stepIndex = current + 1
        return Self.json(stepPayload(at: state.stepIndex))
    }

    private func goToStep(_ args: [String: Any]) -> String {
        guard !plan.steps.isEmpty else { return Self.json(["done": true]) }
        guard let index = (args["index"] as? NSNumber)?.intValue else {
            return Self.json(["error": "bad arguments"])
        }
        state.stepIndex = clampedIndex(index)
        return Self.json(stepPayload(at: state.stepIndex))
    }

    // MARK: - Timers

    private func startTimer(_ args: [String: Any]) -> String {
        guard let label = args["label"] as? String, !label.isEmpty,
              let seconds = (args["seconds"] as? NSNumber)?.intValue, seconds > 0 else {
            return Self.json(["error": "bad arguments"])
        }
        timers.start(label: label, seconds: seconds)
        return Self.json(["started": true, "label": label, "seconds": seconds])
    }

    private func checkTimers() -> String {
        let now = Date()
        let running: [[String: Any]] = timers.timers.map { timer in
            ["label": timer.label, "remainingSeconds": timer.remainingSeconds(at: now)]
        }
        return Self.json(["timers": running])
    }

    private func cancelTimer(_ args: [String: Any]) -> String {
        guard let label = args["label"] as? String, !label.isEmpty else {
            return Self.json(["error": "bad arguments"])
        }
        guard let timer = timers.timers.first(where: {
            $0.label.caseInsensitiveCompare(label) == .orderedSame
        }) else {
            return Self.json(["error": "no such timer"])
        }
        timers.cancel(timer)
        return Self.json(["cancelled": true, "label": timer.label])
    }

    // MARK: - Pantry + substitutions

    private func checkPantry() -> String {
        let match = PantryMatcher.match(recipe: recipe, pantry: pantry)
        return Self.json([
            "ownedCount": match.ownedCount,
            "totalCount": match.totalCount,
            "missing": match.missing.map(\.name),
            "missingOptional": match.missingOptional.map(\.name),
        ])
    }

    private func findSubstitutes(_ args: [String: Any]) -> String {
        guard let ingredient = args["ingredient"] as? String, !ingredient.isEmpty else {
            return Self.json(["error": "bad arguments"])
        }
        let substitutes = SubstitutionService.availableSubstitutions(
            for: ingredient,
            pantry: pantry,
            rules: prefs.dietaryRules,
            allergies: prefs.allergies
        )
        return Self.json([
            "substitutes": substitutes.map { ["name": $0.name, "explanation": $0.explanation] },
            "isEssential": SubstitutionService.isEssential(ingredient),
        ])
    }

    // MARK: - Nutrition + servings

    private func getNutrition() -> String {
        if let calories = recipe.calories {
            var payload: [String: Any] = ["available": true, "calories": calories]
            if let protein = recipe.proteinGrams { payload["protein"] = protein }
            return Self.json(payload)
        }
        guard let estimate = NutritionEstimator.estimate(for: recipe) else {
            return Self.json(["available": false])
        }
        return Self.json([
            "available": true,
            "calories": estimate.calories,
            "protein": estimate.proteinGrams,
            "confidence": estimate.confidence,
        ])
    }

    private func adjustServings(_ args: [String: Any]) -> String {
        guard let servings = (args["servings"] as? NSNumber)?.intValue, servings > 0 else {
            return Self.json(["error": "bad arguments"])
        }
        state.servings = servings
        return Self.json([
            "servings": servings,
            "scaleFromOriginal": Double(servings) / Double(max(1, recipe.servings)),
        ])
    }

    // MARK: - Memory

    private func rememberFact(_ args: [String: Any]) -> String {
        guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return Self.json(["error": "bad arguments"])
        }
        let kind = (args["kind"] as? String).flatMap(MemoryKind.init(rawValue:)) ?? .outcome
        let confidence = (args["confidence"] as? NSNumber)?.doubleValue ?? 0.7
        PollyMemoryStore.upsert(
            kind: kind,
            text: text,
            confidence: min(max(confidence, 0), 1),
            sourceRecipeTitle: recipe.title,
            in: context
        )
        if text.lowercased().hasPrefix("substituted") {
            state.substitutions.append(text)
        }
        return Self.json(["remembered": true])
    }

    // MARK: - Camera + session

    private func requestCameraFrame() async -> String {
        guard let onRequestFrame else {
            return Self.json(["captured": false, "reason": "camera unavailable"])
        }
        let captured = await onRequestFrame()
        return captured
            ? Self.json(["captured": true])
            : Self.json(["captured": false, "reason": "frame capture failed"])
    }

    private func endSession() -> String {
        onEndSession?()
        return Self.json(["ending": true])
    }

    // MARK: - JSON plumbing

    /// Lenient argument parsing: empty string means "no arguments"; anything
    /// that isn't a JSON object is rejected (the caller answers the model
    /// with {"error":"bad arguments"} so it can retry).
    private static func parseArguments(_ json: String) -> [String: Any]? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"error":"encoding failed"}"#
        }
        return string
    }
}
```

- [ ] **Step 4: Run the tests — expect green**

Run `xcodegen generate` (Bash, from the repo root) so the new source file joins the `Glutt` target. Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, includes `PollyToolRegistryTests/testToolDefinitionsMatchLockedNames`, `testStepNavigationFlow`, `testTimerStartCheckCancel`, `testCheckPantryCountsAndMissingNames`, `testFindSubstitutesRespectsPantryAndDietGuard`, `testRememberFactWritesMemoryAndRecordsSubstitutions`, `testUnknownToolAndBadArguments`, `testGetNutritionPrefersRecipeMacrosThenEstimatorThenUnavailable`, `testAdjustServingsUpdatesStateAndReturnsScale`, `testRequestCameraFrameAndEndSessionHooks`, and all pre-existing suites still green.

- [ ] **Step 5: Commit**

```bash
git add Glutt.xcodeproj Glutt/Services/Polly/PollyToolRegistry.swift GluttTests/PollyToolRegistryTests.swift
git commit -m "feat(polly): add realtime tool registry wired to pantry, timers, and memory

All 13 locked tools with JSON-schema parameters and lenient argument
parsing. CookState tracks step index, completed step IDs, substitutions
(recorded only via remember_fact texts starting 'Substituted'), and
servings. Handlers delegate to PantryMatcher, SubstitutionService (diet-
and allergy-filtered), NutritionEstimator, TimerManager, and
PollyMemoryStore; camera and end-session run through controller hooks.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9"
```

`Glutt.xcodeproj` is git-tracked and regenerated by `xcodegen generate`, so it is staged alongside the new files. Do not commit `project.yml` (untouched by this task).

---

### Task 11: PollyPromptBuilder

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyPromptBuilder.swift`
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyPromptBuilderTests.swift`

**Interfaces:**

Consumes (exact signatures from earlier tasks / existing code):
- Task 2 `PollyConfig`: `static let watchFrameInterval: TimeInterval = 10`, `static let maxSessionMinutes = 52`, `static let wrapUpWarningMinutes = 47`, `static let memoryFactLimit = 12` (`Glutt/Services/Polly/PollyConfig.swift`)
- Task 2 `struct CookPlan: Codable, Equatable` (fields `title: String`, `servings: Int`, `mise: [MiseItem]`, `equipment: [String]`, `steps: [PlanStep]`, `isFallback: Bool`) and `static func linear(from recipe: Recipe, scale: Double) -> CookPlan` (`Glutt/Services/Polly/CookPlan.swift`)
- Task 3 `@Model final class PollyMemory` — `var kind: MemoryKind { get }`, `var text: String`, `init(kind: MemoryKind, text: String, confidence: Double, sourceRecipeTitle: String?)` (`Glutt/Models/Polly.swift`)
- Existing `PantryMatcher.MatchResult` — `owned/missing/missingOptional: [RecipeIngredient]`, `ownedCount: Int`, `totalCount: Int` (`Glutt/Services/PantryMatcher.swift:16`)
- Existing `UserPrefs` — `dietaryRules: [DietaryRule]` (`String`-raw enum), `allergies: [String]`, `dislikedIngredients: [String]` (`Glutt/Models/UserPrefs.swift`)
- Existing `CookSession` — `date: Date`, `rating: Int?`, `notes: String?` (`Glutt/Models/Planning.swift:101`)
- Existing `Recipe` — `title: String`, `timeLabel: String` (`Glutt/Models/Recipe.swift`)

Produces (later tasks rely on this exact signature — Task 13 `PollySessionController.start(context:)` passes its output into `RealtimeSessionConfig.instructions`):

```swift
enum PollyPromptBuilder {
    static func instructions(recipe: Recipe, plan: CookPlan,
                             pantryMatch: PantryMatcher.MatchResult,
                             prefs: UserPrefs, memories: [PollyMemory],
                             pastSessions: [CookSession]) -> String
}
```

Guaranteed output properties later tasks/tests depend on: the cook plan is embedded as compact sorted-keys JSON between the literal markers `<cook_plan>` and `</cook_plan>`; memory bullets are the ONLY lines in the prompt that begin with `- [` (format `- [<kind.rawValue>] <text>`), capped at `PollyConfig.memoryFactLimit`; when `pastSessions` is empty the prompt contains the exact line `First time cooking this together.`.

- [ ] **Step 1: Write the failing test file**

Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyPromptBuilderTests.swift` with the full contents below. Note the in-memory Schema list explicitly includes every `@Model` the fixtures touch — including the new `PollyMemory` from Task 3 (plan rule: new `@Model` types used in a test must appear in that test's Schema list).

```swift
import XCTest
import SwiftData
@testable import Glutt

@MainActor
final class PollyPromptBuilderTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: Schema([
                Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
                UserPrefs.self, CookSession.self, PollyMemory.self,
            ]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        container = nil
    }

    // MARK: - Fixtures

    /// 3 ingredients: chicken (owned), onion (missing, required), parsley (missing, optional).
    private func makeRecipe() -> Recipe {
        let recipe = Recipe(title: "Harissa Chicken Skillet", servings: 2, prepMinutes: 10, cookMinutes: 25)
        context.insert(recipe)
        recipe.ingredients = [
            RecipeIngredient(name: "chicken thighs", quantity: 500, unit: "g", sortIndex: 0),
            RecipeIngredient(name: "onion", quantity: 1, sortIndex: 1),
            RecipeIngredient(name: "parsley", isOptional: true, sortIndex: 2),
        ]
        recipe.steps = [
            RecipeStep(index: 0, text: "Sear the chicken until deeply browned."),
            RecipeStep(index: 1, text: "Add onion and harissa, simmer 15 minutes.", durationSeconds: 900),
        ]
        return recipe
    }

    private func makePrefs() -> UserPrefs {
        let prefs = UserPrefs.current(in: context)
        prefs.dietaryRules = [.halal]
        prefs.allergies = ["peanut"]
        prefs.dislikedIngredients = ["cilantro"]
        return prefs
    }

    private func makeMatch(for recipe: Recipe) -> PantryMatcher.MatchResult {
        let sorted = recipe.ingredients.sorted { $0.sortIndex < $1.sortIndex }
        return PantryMatcher.MatchResult(
            owned: [sorted[0]],
            missing: [sorted[1]],
            missingOptional: [sorted[2]]
        )
    }

    private func makeMemories() -> [PollyMemory] {
        let facts = [
            PollyMemory(kind: .equipment, text: "Owns a cast iron skillet", confidence: 0.9, sourceRecipeTitle: nil),
            PollyMemory(kind: .technique, text: "Chops slowly, pad prep estimates", confidence: 0.7, sourceRecipeTitle: nil),
            PollyMemory(kind: .preference, text: "Likes food spicier than recipes suggest", confidence: 0.8, sourceRecipeTitle: nil),
        ]
        facts.forEach(context.insert)
        return facts
    }

    private func makePastSession(recipe: Recipe) -> CookSession {
        let session = CookSession(date: Date(timeIntervalSince1970: 1_700_000_000), servingsMade: 2, recipe: recipe)
        session.rating = 4
        session.notes = "Came out great, went heavier on harissa"
        context.insert(session)
        return session
    }

    private func instructions(
        recipe: Recipe,
        memories: [PollyMemory] = [],
        pastSessions: [CookSession] = []
    ) -> String {
        PollyPromptBuilder.instructions(
            recipe: recipe,
            plan: CookPlan.linear(from: recipe, scale: 1.0),
            pantryMatch: makeMatch(for: recipe),
            prefs: makePrefs(),
            memories: memories,
            pastSessions: pastSessions
        )
    }

    // MARK: - Tests

    func testInstructionsIncludeDishPantryAndHardRules() {
        let recipe = makeRecipe()
        let plan = CookPlan.linear(from: recipe, scale: 1.0)
        let prompt = instructions(recipe: recipe)

        XCTAssertTrue(prompt.contains("Harissa Chicken Skillet"))
        XCTAssertTrue(prompt.contains("\(plan.servings) servings"))
        XCTAssertTrue(prompt.contains("has 1 of 2"), "ownedCount/totalCount from the pantry match")
        XCTAssertTrue(prompt.contains("onion"), "missing required ingredient is listed")
        XCTAssertTrue(prompt.contains("parsley"), "missing optional ingredient is listed")
        XCTAssertTrue(prompt.contains("halal"), "DietaryRule rawValue, not the display label")
        XCTAssertTrue(prompt.contains("peanut"))
        XCTAssertTrue(prompt.contains("cilantro"), "dislikes appear as a soft preference")
    }

    func testInstructionsIncludeMemoriesAndPastSessionHistory() {
        let recipe = makeRecipe()
        let memories = makeMemories()
        let prompt = instructions(recipe: recipe, memories: memories,
                                  pastSessions: [makePastSession(recipe: recipe)])

        for memory in memories {
            XCTAssertTrue(prompt.contains(memory.text), "missing memory: \(memory.text)")
        }
        XCTAssertTrue(prompt.contains("- [equipment] Owns a cast iron skillet"))
        XCTAssertTrue(prompt.contains("4/5"), "past-session rating string")
        XCTAssertTrue(prompt.contains("Came out great, went heavier on harissa"))
        XCTAssertFalse(prompt.contains("First time cooking this together."))
    }

    func testCookPlanJSONRoundTripsBetweenMarkers() throws {
        let recipe = makeRecipe()
        let plan = CookPlan.linear(from: recipe, scale: 1.0)
        let prompt = instructions(recipe: recipe)

        let start = try XCTUnwrap(prompt.range(of: "<cook_plan>"))
        let end = try XCTUnwrap(prompt.range(of: "</cook_plan>"))
        XCTAssertTrue(start.upperBound <= end.lowerBound, "markers appear in order")
        let json = prompt[start.upperBound..<end.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, plan)
    }

    func testFirstTimeLineWhenNoPastSessions() {
        let prompt = instructions(recipe: makeRecipe(), pastSessions: [])
        XCTAssertTrue(prompt.contains("First time cooking this together."))
    }

    func testMemoryBulletsAreCappedAtConfigLimit() {
        let memories = (0..<20).map { i in
            PollyMemory(kind: .outcome, text: "Durable kitchen fact number \(i)",
                        confidence: 0.5, sourceRecipeTitle: nil)
        }
        memories.forEach(context.insert)
        let prompt = instructions(recipe: makeRecipe(), memories: memories)

        let bullets = prompt.components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        XCTAssertEqual(bullets.count, PollyConfig.memoryFactLimit)
        XCTAssertTrue(prompt.contains("Durable kitchen fact number 0"))
        XCTAssertFalse(prompt.contains("Durable kitchen fact number \(PollyConfig.memoryFactLimit)"),
                       "facts past the cap must not leak into the prompt")
    }
}
```

- [ ] **Step 2: Regenerate the project and confirm the tests fail**

Run: `cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate` (new file under the globbed `GluttTests/` folder). Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

Run tests: `test_sim` (scheme `Glutt`) — expected: **FAIL** — the `GluttTests` target does not compile: `cannot find 'PollyPromptBuilder' in scope` in `PollyPromptBuilderTests.swift`. This is the required red state; do not proceed until you see exactly this failure (any other failure means a fixture or an earlier task's contract is wrong — fix that first).

- [ ] **Step 3: Implement the prompt builder**

Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyPromptBuilder.swift` with the full contents below.

```swift
import Foundation

/// Builds the system instructions for a live Polly cooking session.
///
/// Everything here is static for the whole session: it is assembled once,
/// sent in the initial `session.update`, and never mutated mid-cook, so the
/// Realtime prompt cache can reuse the prefix on every turn. The cook plan is
/// embedded as compact sorted-keys JSON between `<cook_plan>` markers so the
/// output is byte-stable for the same plan.
enum PollyPromptBuilder {

    static func instructions(
        recipe: Recipe,
        plan: CookPlan,
        pantryMatch: PantryMatcher.MatchResult,
        prefs: UserPrefs,
        memories: [PollyMemory],
        pastSessions: [CookSession]
    ) -> String {
        [
            personaSection(),
            dishSection(recipe: recipe, plan: plan),
            planSection(plan),
            pantrySection(pantryMatch),
            hardRulesSection(prefs),
            memorySection(memories),
            historySection(pastSessions),
            runPolicySection(),
        ].joined(separator: "\n\n")
    }

    // MARK: - Sections

    private static func personaSection() -> String {
        """
        # Who you are
        You are Polly, Glutt's live cooking chef. You are calm, expert, and warm — you speak
        like a good chef standing at the counter beside the user, never condescending.
        Default to 1-2 short sentences per reply; go longer only when teaching a technique.
        Be honest about food-safety uncertainty: when in doubt about the doneness of meat or
        fish, say so plainly and suggest a temperature check instead of guessing.
        """
    }

    private static func dishSection(recipe: Recipe, plan: CookPlan) -> String {
        let time = recipe.timeLabel == "—" ? "total time unknown" : "about \(recipe.timeLabel) total"
        return """
        # The dish
        \(recipe.title) — \(plan.servings) servings, \(time).
        """
    }

    private static func planSection(_ plan: CookPlan) -> String {
        let encoder = JSONEncoder()
        // Sorted keys keep the output byte-stable for the same plan (prompt caching).
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(plan)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        # The cook plan
        Follow this compiled plan. Step "id" values are what the step tools
        (get_current_step, mark_step_done, go_to_step) operate on.
        <cook_plan>
        \(json)
        </cook_plan>
        """
    }

    private static func pantrySection(_ match: PantryMatcher.MatchResult) -> String {
        var lines = [
            "# Pantry",
            "The user has \(match.ownedCount) of \(match.totalCount) required ingredients.",
        ]
        if match.missing.isEmpty {
            lines.append("Nothing required is missing.")
        } else {
            lines.append("Missing (required): \(match.missing.map(\.name).joined(separator: ", ")).")
        }
        if !match.missingOptional.isEmpty {
            lines.append("Missing but optional: \(match.missingOptional.map(\.name).joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func hardRulesSection(_ prefs: UserPrefs) -> String {
        var lines = ["# Hard rules"]
        if prefs.dietaryRules.isEmpty && prefs.allergies.isEmpty {
            lines.append("No dietary rules or allergies on file.")
        } else {
            lines.append("These are ABSOLUTE constraints on every suggestion, substitution, and tip:")
            if !prefs.dietaryRules.isEmpty {
                lines.append("- Dietary rules: \(prefs.dietaryRules.map(\.rawValue).joined(separator: ", "))")
            }
            if !prefs.allergies.isEmpty {
                lines.append("- Allergies (never include, never suggest): \(prefs.allergies.joined(separator: ", "))")
            }
        }
        if !prefs.dislikedIngredients.isEmpty {
            lines.append("Soft preference — avoid when reasonable, not a safety issue: \(prefs.dislikedIngredients.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    private static func memorySection(_ memories: [PollyMemory]) -> String {
        var lines = ["# What you remember about this kitchen"]
        if memories.isEmpty {
            lines.append("Nothing yet — this is a fresh start.")
        } else {
            for memory in memories.prefix(PollyConfig.memoryFactLimit) {
                lines.append("- [\(memory.kind.rawValue)] \(memory.text)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func historySection(_ pastSessions: [CookSession]) -> String {
        var lines = ["# History with this dish"]
        if pastSessions.isEmpty {
            lines.append("First time cooking this together.")
        } else {
            for session in pastSessions.prefix(3) {
                var line = "* \(session.date.formatted(date: .abbreviated, time: .omitted))"
                if let rating = session.rating {
                    line += " — rated \(rating)/5"
                }
                if let notes = session.notes,
                   !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    line += " — \"\(notes)\""
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func runPolicySection() -> String {
        """
        # How to run the cook
        - Greet by confirming the dish, then do a quick conversational check of the missing
          ingredients BEFORE step 1. Offer find_substitutes for anything missing; the user
          can always choose to start anyway.
        - Drive progress with mark_step_done and go_to_step. Start timers for passive steps
          with start_timer.
        - Use check_pantry and find_substitutes before improvising with ingredients.
        - Call remember_fact for durable kitchen facts (stove heat, equipment, the user's
          pace) and for substitutions, phrased like "Substituted X for Y in <dish>".
        - Camera frames arrive from the user's shutter, from watch mode (~every
          \(Int(PollyConfig.watchFrameInterval))s while enabled), or from your own
          request_camera_frame call. Comment on what you SEE — browning, cut size,
          texture. Never pretend to see without a frame.
        - Wrap up and call end_session when the dish is plated or the user asks to stop.
        - The session ends around minute \(PollyConfig.maxSessionMinutes); start wrapping
          up by minute \(PollyConfig.wrapUpWarningMinutes).
        """
    }
}
```

Two invariants this file must keep (the tests and later tasks rely on them): only `memorySection` emits lines starting with `- [` (the hard-rules bullets are `- Dietary`/`- Allergies`, the run-policy bullets never open a bracket, history uses `* `); and the plan JSON sits alone between the `<cook_plan>`/`</cook_plan>` marker lines.

- [ ] **Step 4: Regenerate and run the tests to green**

Run: `cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate` (new file under the globbed `Glutt/` folder). Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

Run tests: `test_sim` (scheme `Glutt`) — expected: **PASS**, includes `testInstructionsIncludeDishPantryAndHardRules`, `testInstructionsIncludeMemoriesAndPastSessionHistory`, `testCookPlanJSONRoundTripsBetweenMarkers`, `testFirstTimeLineWhenNoPastSessions`, `testMemoryBulletsAreCappedAtConfigLimit`, plus the full existing suite (no regressions).

- [ ] **Step 5: Commit**

```bash
cd /Users/omarlahmimi/Documents/Glutt
git add Glutt.xcodeproj Glutt/Services/Polly/PollyPromptBuilder.swift GluttTests/PollyPromptBuilderTests.swift
git commit -m "$(cat <<'EOF'
feat(polly): add session instruction builder

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
EOF
)"
```

---

### Task 12: CookPlanCompiler (LLM compile + cache + fallback)

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/CookPlanCompiler.swift`
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/CookPlanCompilerTests.swift`
- Modify: `/Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj/project.pbxproj` — never by hand; regenerated by `xcodegen generate` after each new file (both new files land in already-globbed folders, so no `project.yml` edit is needed).

**Interfaces:**

Consumes (exact signatures — do not improvise):
- From Task 2 (`Glutt/Services/Polly/CookPlan.swift`):
  ```swift
  struct CookPlan: Codable, Equatable {
      var isFallback: Bool
      static func linear(from recipe: Recipe, scale: Double) -> CookPlan
  }
  ```
  (Decoding is optional-tolerant per the Shared Contracts: missing arrays → `[]`, missing scalars → `nil`/`0`, missing `isFallback` → `false`, unknown `kind` → `.active`.)
- Existing `Glutt/Services/AI/LLMClient.swift`:
  ```swift
  static var isConfigured: Bool
  static func chatJSON<T: Decodable>(_ type: T.Type, system: String, user: String,
      imageData: Data? = nil, temperature: Double = 0.2, timeout: TimeInterval = 30) async throws -> T
  ```
- Existing `Glutt/Services/UnitConverter.swift`:
  ```swift
  static func display(quantity: Double?, unit: String?, scale: Double = 1,
      system: MeasurementSystem = .original) -> String?
  ```
- Existing `@Model` types `Recipe` / `RecipeIngredient` / `RecipeStep` (`Glutt/Models/Recipe.swift`): `recipe.title`, `recipe.servings`, `recipe.prepMinutes`, `recipe.cookMinutes`, `recipe.sortedSteps` (line 90, sorted by `index`), `recipe.ingredients` (`name`, `quantity`, `unit`, `sortIndex`).

Produces (Task 13's `Dependencies.compilePlan` live value is `{ await CookPlanCompiler.compile(recipe: $0, scale: $1) }`):
```swift
enum CookPlanCompiler {
    static var cacheDirectory: URL                                   // test seam
    static func cacheKey(recipe: Recipe, scale: Double) -> String    // SHA256 hex
    static func cachedPlan(forKey key: String) -> CookPlan?
    static func store(_ plan: CookPlan, forKey key: String)
    static func compile(recipe: Recipe, scale: Double,
        llm: (String, String) async throws -> CookPlan = { system, user in
            try await LLMClient.chatJSON(CookPlan.self, system: system, user: user,
                                         temperature: 0.2, timeout: 45)
        }) async -> CookPlan
}
```
The defaulted `llm` parameter keeps the Shared Contracts call shape `compile(recipe:scale:)` intact while giving tests a network-free seam (Plates closure-DI pattern).

Note for the implementer: `LLMClient.isConfigured` is `true` in the test bundle (`Secrets.aiProxyBaseURL` is a committed non-empty constant), so the injected `llm` stubs below WILL be called; the `isConfigured == false` guard is a production-only degradation path and is deliberately untested (no deterministic seam exists for a `static let` secret — do not invent one).

- [ ] **Step 1: Write the failing test file**

  Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/CookPlanCompilerTests.swift` with exactly:

  ```swift
  import XCTest
  import SwiftData
  @testable import Glutt

  @MainActor
  final class CookPlanCompilerTests: XCTestCase {

      private var container: ModelContainer!
      private var tempDir: URL!
      private var originalCacheDirectory: URL!

      override func setUpWithError() throws {
          container = try ModelContainer(
              for: Schema([Recipe.self, RecipeIngredient.self, RecipeStep.self]),
              configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
          )
          tempDir = FileManager.default.temporaryDirectory
              .appendingPathComponent("polly-plan-cache-\(UUID().uuidString)", isDirectory: true)
          originalCacheDirectory = CookPlanCompiler.cacheDirectory
          CookPlanCompiler.cacheDirectory = tempDir
      }

      override func tearDownWithError() throws {
          CookPlanCompiler.cacheDirectory = originalCacheDirectory
          try? FileManager.default.removeItem(at: tempDir)
          tempDir = nil
          container = nil
      }

      // MARK: - Fixtures

      private func makeRecipe(
          title: String = "Shakshuka",
          stepTexts: [String] = ["Sauté the onions.", "Add the tomatoes.", "Crack in the eggs and cover."]
      ) -> Recipe {
          let recipe = Recipe(title: title, servings: 2, prepMinutes: 10, cookMinutes: 20)
          recipe.ingredients = [
              RecipeIngredient(name: "eggs", quantity: 4, sortIndex: 0),
              RecipeIngredient(name: "crushed tomatoes", quantity: 400, unit: "g", sortIndex: 1),
              RecipeIngredient(name: "onion", quantity: 1, sortIndex: 2),
          ]
          recipe.steps = stepTexts.enumerated().map { RecipeStep(index: $0.offset, text: $0.element) }
          container.mainContext.insert(recipe)
          return recipe
      }

      /// Built through the decoder (house pattern, like PlateCard tests) because
      /// CookPlan's custom init(from:) suppresses the memberwise initializer.
      private func fixturePlan() throws -> CookPlan {
          let json = """
          {"title": "Shakshuka", "servings": 2,
           "mise": [{"name": "onion", "prep": "diced"}],
           "equipment": ["skillet with lid"],
           "steps": [{"id": "s1", "index": 0, "title": "Sauté onions",
                      "instruction": "Sauté the onions until soft.", "kind": "active",
                      "estimatedSeconds": 300, "dependsOn": [],
                      "visualCheck": "translucent and lightly golden",
                      "ingredientNames": ["onion"]}]}
          """
          return try JSONDecoder().decode(CookPlan.self, from: Data(json.utf8))
      }

      private struct Boom: Error {}

      // MARK: - cacheKey

      func testCacheKeyIsStableForSameContent() {
          let a = makeRecipe()
          let b = makeRecipe()  // separate object, identical content
          XCTAssertEqual(CookPlanCompiler.cacheKey(recipe: a, scale: 1.0),
                         CookPlanCompiler.cacheKey(recipe: a, scale: 1.0))
          XCTAssertEqual(CookPlanCompiler.cacheKey(recipe: a, scale: 1.0),
                         CookPlanCompiler.cacheKey(recipe: b, scale: 1.0),
                         "key must depend on content, not object identity")
      }

      func testCacheKeyChangesWithScale() {
          let recipe = makeRecipe()
          XCTAssertNotEqual(CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.0),
                            CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.5))
      }

      func testCacheKeyChangesWhenStepTextChanges() {
          let recipe = makeRecipe()
          let before = CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.0)
          recipe.sortedSteps[0].text = "Char the onions hard."
          XCTAssertNotEqual(before, CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.0))
      }

      // MARK: - File cache

      func testStoreThenCachedPlanRoundTrips() throws {
          let plan = try fixturePlan()
          CookPlanCompiler.store(plan, forKey: "roundtrip")
          XCTAssertEqual(CookPlanCompiler.cachedPlan(forKey: "roundtrip"), plan)
      }

      func testCachedPlanReturnsNilWhenMissing() {
          XCTAssertNil(CookPlanCompiler.cachedPlan(forKey: "never-stored"))
      }

      // MARK: - compile

      func testCompileUsesLLMThenServesFromCache() async throws {
          let recipe = makeRecipe()
          let fixture = try fixturePlan()

          var llmCalls = 0
          var capturedUser = ""
          let first = await CookPlanCompiler.compile(recipe: recipe, scale: 1.0) { _, user in
              llmCalls += 1
              capturedUser = user
              return fixture
          }
          XCTAssertEqual(llmCalls, 1)
          XCTAssertFalse(first.isFallback)
          XCTAssertEqual(first, fixture)
          XCTAssertTrue(capturedUser.contains("Shakshuka"), "user prompt must carry the recipe")

          // Second compile: the llm throws, so only a cache hit can return this plan.
          let second = await CookPlanCompiler.compile(recipe: recipe, scale: 1.0) { _, _ in
              throw Boom()
          }
          XCTAssertEqual(second, first, "second compile must be served from the file cache")
      }

      func testCompileFallsBackToLinearAndDoesNotCache() async {
          let recipe = makeRecipe()
          let plan = await CookPlanCompiler.compile(recipe: recipe, scale: 1.0) { _, _ in
              throw Boom()
          }
          XCTAssertTrue(plan.isFallback, "a failed compile must degrade to the linear plan")
          let key = CookPlanCompiler.cacheKey(recipe: recipe, scale: 1.0)
          XCTAssertNil(CookPlanCompiler.cachedPlan(forKey: key), "fallback plans must never be cached")
      }
  }
  ```

- [ ] **Step 2: Regenerate the project so the test file joins the GluttTests target**

  Run in `/Users/omarlahmimi/Documents/Glutt`:
  ```bash
  xcodegen generate
  ```
  Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 3: Run tests — confirm the red state**

  Run tests: `test_sim` (scheme `Glutt`) — expected: FAIL. The test target does not compile: `cannot find 'CookPlanCompiler' in scope` in `CookPlanCompilerTests.swift`. (A compile error in the test target is this step's expected "failing test" signal — do not "fix" it by weakening the tests.)

- [ ] **Step 4: Implement CookPlanCompiler**

  Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/CookPlanCompiler.swift` with exactly:

  ```swift
  import CryptoKit
  import Foundation

  /// Compiles a Recipe into a `CookPlan` execution graph with one LLM call,
  /// cached on disk so repeat cooks are instant and work offline. Any failure —
  /// proxy unconfigured, network down, malformed JSON — degrades to the
  /// deterministic `CookPlan.linear(from:scale:)` so a session can always run.
  enum CookPlanCompiler {

      /// Where compiled plans live between launches. `var` so tests can point
      /// it at a throwaway temp directory; created on demand by `store`.
      static var cacheDirectory: URL = {
          let base = FileManager.default
              .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
              ?? FileManager.default.temporaryDirectory
          return base.appendingPathComponent("PollyPlans", isDirectory: true)
      }()

      // MARK: - Cache

      /// Content hash of everything that shapes a plan: title, step texts,
      /// ingredient names, and the serving scale. Stable across launches
      /// (unlike persistentModelID) and changes whenever the recipe does.
      static func cacheKey(recipe: Recipe, scale: Double) -> String {
          let ingredientNames = recipe.ingredients
              .sorted { $0.sortIndex < $1.sortIndex }
              .map(\.name)
              .joined(separator: "|")
          let material = recipe.title
              + "|" + recipe.sortedSteps.map(\.text).joined(separator: "|")
              + "|" + ingredientNames
              + "|" + String(format: "%.2f", scale)
          let digest = SHA256.hash(data: Data(material.utf8))
          return digest.map { String(format: "%02x", $0) }.joined()
      }

      static func cachedPlan(forKey key: String) -> CookPlan? {
          let url = cacheDirectory.appendingPathComponent("\(key).json")
          guard let data = try? Data(contentsOf: url) else { return nil }
          return try? JSONDecoder().decode(CookPlan.self, from: data)
      }

      static func store(_ plan: CookPlan, forKey key: String) {
          guard let data = try? JSONEncoder().encode(plan) else { return }
          try? FileManager.default.createDirectory(
              at: cacheDirectory, withIntermediateDirectories: true
          )
          try? data.write(
              to: cacheDirectory.appendingPathComponent("\(key).json"),
              options: .atomic
          )
      }

      // MARK: - Compile

      /// Cache hit → cached plan. Otherwise one LLM call; success is stored
      /// for next time, ANY failure returns the linear fallback — never
      /// cached, so the next attempt retries the real compile.
      static func compile(
          recipe: Recipe,
          scale: Double,
          llm: (String, String) async throws -> CookPlan = { system, user in
              try await LLMClient.chatJSON(CookPlan.self, system: system, user: user,
                                           temperature: 0.2, timeout: 45)
          }
      ) async -> CookPlan {
          let key = cacheKey(recipe: recipe, scale: scale)
          if let cached = cachedPlan(forKey: key) { return cached }
          guard LLMClient.isConfigured else {
              return CookPlan.linear(from: recipe, scale: scale)
          }
          do {
              var plan = try await llm(systemPrompt, userPrompt(recipe: recipe, scale: scale))
              plan.isFallback = false
              store(plan, forKey: key)
              return plan
          } catch {
              // AI is never load-bearing: the linear plan narrates the raw steps.
              return CookPlan.linear(from: recipe, scale: scale)
          }
      }

      // MARK: - Prompts

      private static let systemPrompt = """
      You are an expert chef converting a home recipe into a strict JSON execution graph
      that a live cooking assistant will follow step by step, out loud, in a real kitchen.
      Return JSON only, with this exact shape:
      {"title": str, "servings": int,
       "mise": [{"name": str, "prep": str}],
       "equipment": [str],
       "steps": [{"id": str, "index": int, "title": str, "instruction": str,
                  "kind": "prep"|"active"|"passive"|"checkpoint",
                  "estimatedSeconds": int|null, "timerSeconds": int|null,
                  "dependsOn": [str], "visualCheck": str|null, "recovery": str|null,
                  "ingredientNames": [str]}]}

      Field docs:
      - title: the dish name, unchanged.
      - servings: the scaled serving count you were given.
      - mise: the full mise en place — every ingredient that needs washing, chopping, \
      measuring, or bringing to temperature before any heat goes on. "prep" is the \
      action, e.g. "diced", "minced", "at room temperature".
      - equipment: the pans, trays, and tools to stage before starting.
      - steps: the recipe as an ordered graph. "id" is a short stable slug like "s1", \
      "s2"; "index" is the 0-based order.
      - kind: "prep" = knife/board work, "active" = hands-on heat work, "passive" = \
      unattended waiting (simmer, bake, rest, marinate), "checkpoint" = a judgement \
      moment (taste, doneness test).
      - timerSeconds: REQUIRED on every "passive" step — the unattended wait in seconds. \
      null on other kinds unless a precise timer genuinely helps.
      - estimatedSeconds: your realistic hands-on estimate for the step, null if unknowable.
      - dependsOn: ids of steps that must be finished first; [] when only the previous \
      step matters.
      - visualCheck: REQUIRED on browning, searing, caramelizing, and doneness-critical \
      steps — one sentence describing exactly what the food should look like. null otherwise.
      - recovery: for common failure points (burning, sticking, breaking, over-salting), \
      one sentence on how to rescue the dish. null otherwise.
      - ingredientNames: the ingredient names this step touches, matching the given list.

      Rules:
      - Preserve the recipe's intent and order; split run-on instructions into single \
      actions; do NOT invent ingredients or steps that aren't implied by the source.
      - Keep instructions short, imperative, and natural to speak aloud.
      """

      private static func userPrompt(recipe: Recipe, scale: Double) -> String {
          let scaledServings = max(1, Int((Double(recipe.servings) * scale).rounded()))
          let ingredientLines = recipe.ingredients
              .sorted { $0.sortIndex < $1.sortIndex }
              .map { ingredient in
                  if let amount = UnitConverter.display(
                      quantity: ingredient.quantity, unit: ingredient.unit, scale: scale
                  ) {
                      return "- \(amount) \(ingredient.name)"
                  }
                  return "- \(ingredient.name)"
              }
              .joined(separator: "\n")
          let stepLines = recipe.sortedSteps
              .enumerated()
              .map { "\($0.offset + 1). \($0.element.text)" }
              .joined(separator: "\n")
          return """
          RECIPE: \(recipe.title)
          SERVINGS: \(scaledServings)
          PREP MINUTES: \(recipe.prepMinutes)
          COOK MINUTES: \(recipe.cookMinutes)
          INGREDIENTS:
          \(ingredientLines)
          STEPS:
          \(stepLines)
          """
      }
  }
  ```

- [ ] **Step 5: Regenerate the project so the new source file joins the Glutt target**

  Run in `/Users/omarlahmimi/Documents/Glutt`:
  ```bash
  xcodegen generate
  ```
  Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.

- [ ] **Step 6: Run tests — confirm green**

  Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, includes `testCacheKeyIsStableForSameContent`, `testCacheKeyChangesWithScale`, `testCacheKeyChangesWhenStepTextChanges`, `testStoreThenCachedPlanRoundTrips`, `testCachedPlanReturnsNilWhenMissing`, `testCompileUsesLLMThenServesFromCache`, `testCompileFallsBackToLinearAndDoesNotCache`, plus all pre-existing suites still green.

- [ ] **Step 7: Commit**

  ```bash
  git add Glutt.xcodeproj Glutt/Services/Polly/CookPlanCompiler.swift GluttTests/CookPlanCompilerTests.swift
  git commit -m "feat(polly): add cook-plan compiler with file cache and offline fallback

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9"
  ```

---

### Task 13: PollySessionController (the session brain)

The `@MainActor @Observable` orchestrator for one "Cook with Polly" session: compile plan → snapshot pantry/prefs/memories/past-cooks → mint token → connect transport → `session.update` → greet → live event loop (barge-in truncation, transcripts, tool round-trips, one silent reconnect, watch-mode frames, 47-minute wrap-up warning, 52-minute honest hard stop) → `end()` writes memories + `PollyCookLog`. All behavior is tested against a push-based `FakeRealtimeTransport` — no network, no live audio/camera assertions.

**Execution-order prerequisite:** Tasks 2, 3, 4, 6, 7, 8, 9, 10, 11, 12 **and 14** must be complete before this task. Task 14 (`PollyMemoryExtractor`) is numbered after this one, but this controller compiles against `PollyMemoryExtractor.Extraction` / `.Fact` / `.apply(_:recipeTitle:in:)` and `Dependencies.live` calls `PollyMemoryExtractor.extract` — so implement Task 14 first (its section is self-contained and does not depend on this one).

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Features/Polly/PollySessionController.swift` (first file in a new `Glutt/Features/Polly/` folder — picked up by the `Glutt/` glob on `xcodegen generate`)
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollySessionControllerTests.swift`
- Modify: none.
- Read-only references (do NOT modify): `/Users/omarlahmimi/Documents/Glutt/Glutt/Features/Recipes/RecipesView.swift:445-452` — the `extension Recipe { func cookSessions(in:) -> [CookSession] }` helper is **internal** (no access modifier), so the controller calls it directly; `/Users/omarlahmimi/Documents/Glutt/Glutt/Features/Plates/PlatesFeedViewModel.swift` — the `Dependencies`-of-closures + `static let live` house pattern this controller copies.

**Interfaces:**

Consumes (exact signatures from earlier tasks — all are in Shared Contracts):
```swift
// Task 2
PollyConfig.realtimeModel / .voice / .watchFrameInterval / .maxSessionMinutes / .memoryFactLimit
struct CookPlan { let title: String; let servings: Int; let steps: [PlanStep]; var isFallback: Bool; ... }
// Task 3
PollyMemoryStore.topFacts(limit: Int, in: ModelContext) -> [PollyMemory]
@Model final class PollyCookLog { init(startedAt: Date, recipe: Recipe?); var endedAt/summary/stepsCompleted/stepsTotal/substitutions/endedEarly }
// Task 4
struct PollySessionToken: Decodable, Equatable { let value: String; let expiresAt: Int?; let model: String; let voice: String }
PollyTokenService.live.mint() async throws -> PollySessionToken
// Task 6
struct RealtimeSessionConfig: Equatable { var instructions; var tools: [RealtimeToolDefinition]; var voice; var model; var transcribeInput: Bool }
enum RealtimeClientEvent: Equatable { .sessionUpdate, .appendAudio, .createUserImage(dataURI:itemId:), .createFunctionOutput(callId:output:), .deleteItem(itemId:), .responseCreate, .truncateItem(itemId:audioEndMs:) }
enum RealtimeServerEvent: Equatable { .speechStarted, .speechStopped, .inputTranscript, .outputAudioDelta(itemId:base64:), .outputTranscriptDelta(itemId:delta:), .responseDone(status:calls:), .error(code:message:), ... }
struct RealtimeFunctionCall: Equatable { let name: String; let callId: String; let argumentsJSON: String }
// Task 7
protocol RealtimeTransporting: AnyObject, Sendable {
    func connect(token: String, model: String) async throws
    func send(_ event: RealtimeClientEvent) async throws
    var events: AsyncStream<RealtimeServerEvent> { get }   // single-consumer, fresh per transport instance
    func close() async
}
actor RealtimeWebSocketTransport: RealtimeTransporting { init(socketFactory:) }   // default init() via default arg
// Task 8 — enqueue/interruptPlayback are safe no-ops (return 0) when the engine
// isn't running. Mic permission is requested by PollySessionView BEFORE start()
// (Task 15); audio.start() itself neither checks nor prompts — it just throws
// if the engine can't run.
@MainActor @Observable final class PollyAudioEngine {
    init()
    var isMuted: Bool
    func start(onChunk: @escaping @Sendable (String) -> Void) throws
    func stop()
    func enqueue(base64: String)
    @discardableResult func interruptPlayback() -> Int
}
// Task 9 — init is side-effect free; start() requests permission; captureFrame()
// returns nil on the simulator (no camera). WatchModeScheduler exposes the
// memberwise init(isEnabled:interval:) with lastSent starting nil.
@MainActor @Observable final class PollyCameraController: NSObject {
    override init()
    private(set) var isRunning: Bool
    func start() async
    func stop()
    func flip()
    func captureFrame() async -> Data?
}
struct WatchModeScheduler: Equatable {
    init(isEnabled: Bool, interval: TimeInterval)
    var isEnabled: Bool
    mutating func shouldSendFrame(now: Date) -> Bool
}
// Task 10 — the get_current_step result JSON includes the current step's title
// (locked by Task 10's own tests); end_session invokes onEndSession.
@MainActor final class PollyToolRegistry {
    static let toolDefinitions: [RealtimeToolDefinition]   // exactly 13 tools
    private(set) var state: CookState                       // stepIndex, completedStepIDs, substitutions, servings
    var onRequestFrame: (() async -> Bool)?
    var onEndSession: (() -> Void)?
    init(plan: CookPlan, recipe: Recipe, pantry: [PantryItem], prefs: UserPrefs, timers: TimerManager, context: ModelContext)
    func handle(name: String, argumentsJSON: String) async -> String
}
// Task 11
PollyPromptBuilder.instructions(recipe:plan:pantryMatch:prefs:memories:pastSessions:) -> String   // embeds recipe title
// Task 12
CookPlanCompiler.compile(recipe: Recipe, scale: Double) async -> CookPlan   // never throws; falls back to linear
// Task 14
PollyMemoryExtractor.Fact / .Extraction (synthesized memberwise inits — Task 14 keeps any custom Decodable in an extension)
PollyMemoryExtractor.extract(transcript: String, recipeTitle: String) async throws -> Extraction
PollyMemoryExtractor.apply(_ extraction: Extraction, recipeTitle: String, in context: ModelContext)
// Existing app code
Recipe.cookSessions(in: ModelContext) -> [CookSession]     // RecipesView.swift:445-452, internal
UserPrefs.current(in: ModelContext) -> UserPrefs
PantryMatcher.match(recipe: Recipe, pantry: [PantryItem]) -> PantryMatcher.MatchResult
TimerManager (class): start(label:seconds:), cancelAll(), timers
```

Produces (Tasks 15 `PollySessionView` and 16 `PollyTabView` consume exactly this):
```swift
@MainActor @Observable final class PollySessionController {
    enum Phase: Equatable { case idle, compiling, connecting, live, reconnecting, ended, failed(String) }
    struct Dependencies {
        var mintToken: () async throws -> PollySessionToken
        var makeTransport: () -> RealtimeTransporting
        var compilePlan: (Recipe, Double) async -> CookPlan
        var extractMemories: (String, String) async throws -> PollyMemoryExtractor.Extraction
        var now: () -> Date
        static let live: Dependencies
    }
    private(set) var phase: Phase
    private(set) var plan: CookPlan?
    private(set) var captionText: String
    private(set) var isPollySpeaking: Bool
    private(set) var isListening: Bool
    private(set) var isThinking: Bool          // true from any response.create until the first audio delta / response.done
    private(set) var missingIngredients: [String]  // PantryMatcher misses, snapshotted during start()
    private(set) var wantsEnd: Bool            // set by the end_session tool; the view observes it and calls end()
    var isWatching: Bool
    let audio: PollyAudioEngine
    let camera: PollyCameraController
    let timers: TimerManager
    var registry: PollyToolRegistry?
    var stepIndex: Int { get }                 // registry?.state.stepIndex ?? 0
    init(recipe: Recipe, scale: Double, deps: Dependencies = .live,
         audio: PollyAudioEngine = PollyAudioEngine(),
         camera: PollyCameraController = PollyCameraController())
    func start(context: ModelContext, requireMic: Bool = true) async
    // start() runs once per controller instance (guard phase == .idle);
    // a retry after .failed must create a NEW controller (Task 15 does this).
    func end(context: ModelContext, endedEarly: Bool) async
    func tick(context: ModelContext) async     // 1 Hz loop body (session clock + watch frames); internal so tests drive it with a scripted `now`
    func sendShowPolly() async
    func toggleMute()
    func flipCamera()
}
```

Locked design decisions (do not "improve" these away):
- **`requireMic` parameter (contract addendum, locked):** the Shared Contracts signature `start(context:)` gains a defaulted `requireMic: Bool = true`, so every contract call site still compiles. Production keeps the default: `audio.start` throwing → `phase = .failed(...)` (spec: mic denied → no session). Tests pass `requireMic: false` because the sim test host has no granted mic; a mic failure then only sets a caption note. `phase` may become `.failed` **only** on `mintToken`/transport errors (or mic-with-`requireMic`) — never on camera problems.
- **Camera never gates the session:** camera denied → voice-only session (spec degradation ladder), and a permission prompt must never block the greeting or hang a unit test — so `camera.start()` runs as a fire-and-forget `Task`, not awaited, before `phase = .live`.
- **Reconnect lives here, not in the transport:** exactly one silent reconnect on a `.error` while `.live` (re-mint, fresh `makeTransport()` result, re-`connect`, re-send `session.update`, back to `.live`); any other error → `.failed(message)`. Transport streams are single-consumer, which is why reconnect calls `makeTransport()` again and re-enters the event loop.
- **`Dependencies.live` is only touched at the default-argument site** — tests that inject `deps` never construct `PollyTokenService.live` or a real transport.

**Steps:**

- [ ] **Step 1: Write the failing test file.** Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollySessionControllerTests.swift` with exactly this content:

```swift
import XCTest
import SwiftData
@testable import Glutt

// MARK: - FakeRealtimeTransport

/// Push-based scripted transport (test-only). `connect` records token/model and
/// hands out a *fresh* event stream; tests control interleaving exactly by
/// calling `push(_:)` at the moments they choose. Every client send is
/// recorded. The fresh-stream-per-connect design lets the controller's single
/// silent reconnect (which receives this same instance again from
/// `makeTransport`) re-consume the events cleanly — `AsyncStream` is
/// single-consumer, so reusing one stream across connects would drop events.
final class FakeRealtimeTransport: RealtimeTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var sentEvents: [RealtimeClientEvent] = []
    private var tokens: [String] = []
    private var models: [String] = []
    private var closeCount = 0
    private var stream: AsyncStream<RealtimeServerEvent>
    private var continuation: AsyncStream<RealtimeServerEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: RealtimeServerEvent.self)
        self.stream = stream
        self.continuation = continuation
    }

    var events: AsyncStream<RealtimeServerEvent> { lock.withLock { stream } }
    var sent: [RealtimeClientEvent] { lock.withLock { sentEvents } }
    var connectedToken: String? { lock.withLock { tokens.last } }
    var connectedModel: String? { lock.withLock { models.last } }
    var connectCount: Int { lock.withLock { tokens.count } }
    var isClosed: Bool { lock.withLock { closeCount > 0 } }

    /// Sends minus mic audio. The sim test host may or may not deliver mic
    /// chunks — tests must never assert on their presence or absence.
    var sentNonAudio: [RealtimeClientEvent] {
        sent.filter { if case .appendAudio = $0 { return false }; return true }
    }

    func connect(token: String, model: String) async throws {
        lock.withLock {
            tokens.append(token)
            models.append(model)
            continuation.finish()   // ends any previous consumer's loop
            let (stream, continuation) = AsyncStream.makeStream(of: RealtimeServerEvent.self)
            self.stream = stream
            self.continuation = continuation
        }
    }

    func send(_ event: RealtimeClientEvent) async throws {
        lock.withLock { sentEvents.append(event) }
    }

    /// Deliver a scripted server event to whoever is consuming `events`.
    func push(_ event: RealtimeServerEvent) {
        lock.withLock { continuation }.yield(event)
    }

    func close() async {
        lock.withLock {
            closeCount += 1
            continuation.finish()
        }
    }
}

// MARK: - Tests

@MainActor
final class PollySessionControllerTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Full graph: the controller fetches PantryItem/UserPrefs/CookSession,
        // hands the registry the ModelContext, and end() writes PollyCookLog +
        // PollyMemory — so every connected model rides along.
        let schema = Schema([
            Recipe.self, RecipeIngredient.self, RecipeStep.self, RecipeCollection.self,
            PantryItem.self, GroceryItem.self, Leftover.self,
            PlannedMeal.self, FoodLog.self, CookSession.self, UserPrefs.self,
            PollyMemory.self, PollyCookLog.self,
        ])
        container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    // MARK: Fixtures

    private static let fixtureToken = PollySessionToken(
        value: "ek_test", expiresAt: 1_751_500_000, model: "gpt-realtime-2", voice: "marin")

    private static func planStep(_ id: String, _ index: Int, _ title: String) -> CookPlan.PlanStep {
        CookPlan.PlanStep(
            id: id, index: index, title: title, instruction: "\(title) until done.",
            kind: .active, estimatedSeconds: 120, timerSeconds: nil,
            dependsOn: [], visualCheck: nil, recovery: nil, ingredientNames: [])
    }

    private static let fixturePlan = CookPlan(
        title: "Creamy Lemon Chicken", servings: 2, mise: [], equipment: [],
        steps: [
            planStep("s1", 0, "Sear the chicken"),
            planStep("s2", 1, "Make the sauce"),
            planStep("s3", 2, "Finish and rest"),
        ],
        isFallback: false)

    private static let fixtureExtraction = PollyMemoryExtractor.Extraction(
        facts: [PollyMemoryExtractor.Fact(
            kind: "equipment", text: "Owns a cast iron skillet", confidence: 0.8)],
        summary: "great cook")

    private func insertRecipe() -> Recipe {
        let recipe = Recipe(title: "Creamy Lemon Chicken", servings: 2)
        context.insert(recipe)
        recipe.ingredients = [RecipeIngredient(name: "chicken thighs", sortIndex: 0)]
        recipe.steps = [RecipeStep(index: 0, text: "Sear the chicken, make the sauce, rest.")]
        return recipe
    }

    private func makeController(
        recipe: Recipe,
        transport: FakeRealtimeTransport,
        mintToken: (() async throws -> PollySessionToken)? = nil,
        now: (() -> Date)? = nil
    ) -> PollySessionController {
        let mint: () async throws -> PollySessionToken = mintToken ?? { Self.fixtureToken }
        let deps = PollySessionController.Dependencies(
            mintToken: mint,
            makeTransport: { transport },
            compilePlan: { _, _ in Self.fixturePlan },
            extractMemories: { _, _ in Self.fixtureExtraction },
            now: now ?? { Date(timeIntervalSince1970: 1_751_400_000) }
        )
        return PollySessionController(recipe: recipe, scale: 1.0, deps: deps)
    }

    /// Deterministically waits for the controller's main-actor event task to
    /// process pushed events: polls `condition` (bounded, max 2 s), then
    /// asserts it. Sleeping yields the main actor so the event loop can run.
    private func waitUntil(
        _ condition: () -> Bool,
        _ message: String = "condition not met in time",
        timeout: TimeInterval = 2,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)   // 10 ms
        }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    // MARK: (1) start -> session.update + greeting + .live

    func testStartSendsSessionUpdateThenGreetingAndGoesLive() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)

        await controller.start(context: context, requireMic: false)

        XCTAssertEqual(controller.phase, .live)
        XCTAssertTrue(controller.isThinking, "the greeting response is in flight")
        XCTAssertEqual(controller.missingIngredients, ["chicken thighs"],
                       "empty pantry -> the one ingredient is missing")
        XCTAssertEqual(transport.connectedToken, "ek_test")
        XCTAssertEqual(transport.connectedModel, "gpt-realtime-2")
        XCTAssertEqual(controller.plan?.steps.count, 3)
        XCTAssertNotNil(controller.registry)

        let sent = transport.sentNonAudio
        XCTAssertGreaterThanOrEqual(sent.count, 2)
        guard case .sessionUpdate(let config) = sent[0] else {
            return XCTFail("first send must be session.update, got \(sent[0])")
        }
        XCTAssertTrue(config.instructions.contains("Creamy Lemon Chicken"),
                      "instructions must embed the recipe")
        XCTAssertEqual(config.tools.count, 13, "all 13 locked tools advertised")
        XCTAssertEqual(config.voice, "marin")
        XCTAssertEqual(config.model, "gpt-realtime-2")
        XCTAssertTrue(config.transcribeInput)
        XCTAssertEqual(sent[1], .responseCreate, "Polly greets first")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (2) tool round-trip

    func testFunctionCallRoundTripSendsOutputThenResponseCreate() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        XCTAssertEqual(controller.phase, .live)
        let countBefore = transport.sentNonAudio.count

        transport.push(.responseDone(status: "completed", calls: [
            RealtimeFunctionCall(name: "get_current_step", callId: "call_1", argumentsJSON: "{}"),
        ]))
        await waitUntil({ transport.sentNonAudio.count >= countBefore + 2 },
                        "expected function output + response.create")

        let newSends = Array(transport.sentNonAudio.dropFirst(countBefore))
        guard case .createFunctionOutput(let callId, let output) = newSends[0] else {
            return XCTFail("expected createFunctionOutput first, got \(newSends[0])")
        }
        XCTAssertEqual(callId, "call_1")
        XCTAssertTrue(output.contains("Sear the chicken"), "tool result carries plan step 1")
        XCTAssertEqual(newSends[1], .responseCreate)

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (3) barge-in truncation

    func testBargeInTruncatesTheInterruptedAssistantItem() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        let silence = Data(repeating: 0, count: 4_800).base64EncodedString()  // ~100 ms PCM16 24k
        transport.push(.outputAudioDelta(itemId: "item_7", base64: silence))
        await waitUntil({ controller.isPollySpeaking }, "audio delta marks Polly speaking")

        transport.push(.speechStarted)
        await waitUntil({ controller.isListening }, "speech_started marks listening")

        XCTAssertFalse(controller.isPollySpeaking)
        let truncates = transport.sent.compactMap { event -> (itemId: String, ms: Int)? in
            if case .truncateItem(let itemId, let ms) = event { return (itemId, ms) }
            return nil
        }
        XCTAssertEqual(truncates.count, 1)
        XCTAssertEqual(truncates[0].itemId, "item_7")
        XCTAssertGreaterThanOrEqual(truncates[0].ms, 0)

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (4) end_session tool + end() persistence

    func testEndSessionToolThenEndWritesCookLogAndMemories() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        XCTAssertFalse(controller.wantsEnd)

        transport.push(.responseDone(status: "completed", calls: [
            RealtimeFunctionCall(name: "end_session", callId: "call_9", argumentsJSON: "{}"),
        ]))
        await waitUntil({ controller.wantsEnd }, "end_session tool must set wantsEnd")

        await controller.end(context: context, endedEarly: false)

        XCTAssertEqual(controller.phase, .ended)
        XCTAssertTrue(transport.isClosed)

        let logs = try context.fetch(FetchDescriptor<PollyCookLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].stepsTotal, 3)
        XCTAssertEqual(logs[0].summary, "great cook")
        XCTAssertFalse(logs[0].endedEarly)
        XCTAssertNotNil(logs[0].endedAt)
        XCTAssertEqual(logs[0].recipe?.title, "Creamy Lemon Chicken")

        let memories = try context.fetch(FetchDescriptor<PollyMemory>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].kind, .equipment)
        XCTAssertEqual(memories[0].text, "Owns a cast iron skillet")

        // Idempotent: a second end() must not write a second log.
        await controller.end(context: context, endedEarly: false)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PollyCookLog>()).count, 1)
    }

    // MARK: (5) mint failure

    func testMintTokenFailureFailsThePhase() async throws {
        struct MintBoom: LocalizedError {
            var errorDescription: String? { "token mint exploded" }
        }
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport,
                                        mintToken: { throw MintBoom() })

        await controller.start(context: context, requireMic: false)

        guard case .failed(let message) = controller.phase else {
            return XCTFail("expected .failed, got \(controller.phase)")
        }
        XCTAssertTrue(message.contains("token mint exploded"))
        XCTAssertEqual(transport.connectCount, 0, "must not connect without a token")
        XCTAssertTrue(transport.sent.isEmpty)
    }

    // MARK: (6) one silent reconnect

    func testTransportErrorWhileLiveReconnectsOnce() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)
        XCTAssertEqual(transport.connectCount, 1)

        transport.push(.error(code: "transport", message: "socket dropped"))
        await waitUntil({ transport.connectCount == 2 }, "exactly one silent reconnect")
        await waitUntil({ controller.phase == .live }, "phase returns to .live")

        XCTAssertTrue(controller.captionText.localizedCaseInsensitiveContains("hiccup"))
        let sessionUpdates = transport.sent.filter {
            if case .sessionUpdate = $0 { return true }
            return false
        }
        XCTAssertEqual(sessionUpdates.count, 2, "session.update re-sent on the new socket")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (7) protocol errors don't kill a live session

    func testProtocolErrorWhileLiveDoesNotKillTheSession() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        let controller = makeController(recipe: recipe, transport: transport)
        await controller.start(context: context, requireMic: false)

        transport.push(.error(code: "invalid_request_error", message: "item not found"))
        // The stream is ordered: once this later event lands, the error was processed.
        transport.push(.speechStarted)
        await waitUntil({ controller.isListening }, "follow-up event processed")

        XCTAssertEqual(controller.phase, .live, "a protocol error must not fail a live session")
        XCTAssertEqual(transport.connectCount, 1, "and must not trigger a reconnect")

        await controller.end(context: context, endedEarly: true)
    }

    // MARK: (8) wrap-up warning + honest hard stop

    func testTickSendsWrapUpWarningOnceThenHardStops() async throws {
        let recipe = insertRecipe()
        let transport = FakeRealtimeTransport()
        var nowValue = Date(timeIntervalSince1970: 1_751_400_000)
        let controller = makeController(recipe: recipe, transport: transport, now: { nowValue })
        await controller.start(context: context, requireMic: false)
        let before = transport.sentNonAudio.count

        nowValue = nowValue.addingTimeInterval(Double(PollyConfig.wrapUpWarningMinutes * 60) + 1)
        await controller.tick(context: context)
        let warning = Array(transport.sentNonAudio.dropFirst(before))
        XCTAssertEqual(warning.count, 2, "wrap-up note + response.create")
        guard case .createUserText(let text) = warning[0] else {
            return XCTFail("expected the wrap-up system note, got \(warning[0])")
        }
        XCTAssertTrue(text.localizedCaseInsensitiveContains("wrapping up"))
        XCTAssertEqual(warning[1], .responseCreate)

        await controller.tick(context: context)
        XCTAssertEqual(transport.sentNonAudio.count, before + 2, "the warning is sent exactly once")

        nowValue = nowValue.addingTimeInterval(
            Double((PollyConfig.maxSessionMinutes - PollyConfig.wrapUpWarningMinutes) * 60) + 1)
        await controller.tick(context: context)
        XCTAssertEqual(controller.phase, .ended, "the session cap ends the session")
        let logs = try context.fetch(FetchDescriptor<PollyCookLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].endedEarly, "no steps were completed — honest endedEarly")
    }
}
```

Why the tests are shaped this way: everything runs on the main actor (controller, its event-loop `Task`, and the tests), so `Task.sleep` polling in `waitUntil` deterministically yields the actor until the pushed event has been fully handled — no arbitrary "sleep and hope" without a condition. `sentNonAudio` exists because `audio.start` may or may not succeed on the sim test host (`requireMic: false` tolerates both), so mic chunks must never break index-based assertions.

- [ ] **Step 2: Regenerate the project so the new test file joins the target.**
  Run in Bash: `cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate`

- [ ] **Step 3: Run tests — confirm the expected failure.**
  Run tests: `test_sim` (scheme `Glutt`) — expected: **FAIL** — the `GluttTests` target does not compile: `cannot find 'PollySessionController' in scope` (the fake transport, fixtures, and all consumed Polly types from Tasks 2–12/14 compile fine; only the controller is missing). This is the red state; do not proceed until you have seen it.

- [ ] **Step 4: Implement the controller.** Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Features/Polly/PollySessionController.swift` with exactly this content:

```swift
import Foundation
import Observation
import SwiftData

/// The session brain for one "Cook with Polly" session.
///
/// Orchestrates four isolated units — the realtime transport, the audio
/// engine, the camera controller, and the tool registry — plus plan
/// compilation and durable kitchen memory. All state is main-actor; the
/// session view (Task 15) renders it directly. Dependencies are closures
/// with a `.live` default (Plates pattern) so tests script every seam.
@MainActor
@Observable
final class PollySessionController {
    enum Phase: Equatable {
        case idle, compiling, connecting, live, reconnecting, ended, failed(String)
    }

    struct Dependencies {
        var mintToken: () async throws -> PollySessionToken
        var makeTransport: () -> RealtimeTransporting
        var compilePlan: (Recipe, Double) async -> CookPlan
        var extractMemories: (String, String) async throws -> PollyMemoryExtractor.Extraction
        var now: () -> Date

        static let live = Dependencies(
            mintToken: { try await PollyTokenService.live.mint() },
            makeTransport: { RealtimeWebSocketTransport() },
            compilePlan: { await CookPlanCompiler.compile(recipe: $0, scale: $1) },
            extractMemories: { try await PollyMemoryExtractor.extract(transcript: $0, recipeTitle: $1) },
            now: { .now }
        )
    }

    private(set) var phase: Phase = .idle
    private(set) var plan: CookPlan?
    /// Rolling last utterance line (user transcript or Polly's live caption).
    private(set) var captionText = ""
    private(set) var isPollySpeaking = false
    private(set) var isListening = false
    /// True from any response.create until the first audio delta / response.done —
    /// drives the orb's "thinking" state.
    private(set) var isThinking = false
    /// PantryMatcher misses, snapshotted during start() — drives the preflight card.
    private(set) var missingIngredients: [String] = []
    /// Set by the `end_session` tool; the session view observes it and calls `end`.
    private(set) var wantsEnd = false
    /// Watch-mode toggle (the eye button). Read once per watch tick.
    var isWatching = false

    let audio: PollyAudioEngine
    let camera: PollyCameraController
    let timers = TimerManager()
    var registry: PollyToolRegistry?

    var stepIndex: Int { registry?.state.stepIndex ?? 0 }

    private let recipe: Recipe
    private let scale: Double
    private let deps: Dependencies

    private var transport: RealtimeTransporting?
    private var eventTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var startedAt: Date?
    /// Config sent at session start; re-sent verbatim (new token's voice/model)
    /// on the single silent reconnect. Instructions/tools never mutate mid-cook
    /// so the realtime prompt cache stays warm.
    private var liveConfig: RealtimeSessionConfig?

    private var transcriptLog: [String] = []
    private var pendingAssistantItemId: String?
    private var pendingAssistantLine = ""
    /// The assistant audio item currently playing — the barge-in truncate target.
    private var currentAudioItemId: String?

    private var watchScheduler = WatchModeScheduler(
        isEnabled: false, interval: PollyConfig.watchFrameInterval)
    private var watchFrameCount = 0
    private var lastWatchFrameItemId: String?
    private var didAttemptReconnect = false
    private var didSendWrapUpWarning = false
    private var isEnding = false

    init(
        recipe: Recipe,
        scale: Double,
        deps: Dependencies = .live,
        audio: PollyAudioEngine = PollyAudioEngine(),
        camera: PollyCameraController = PollyCameraController()
    ) {
        self.recipe = recipe
        self.scale = scale
        self.deps = deps
        self.audio = audio
        self.camera = camera
    }

    // MARK: - Lifecycle

    /// Compile -> snapshot -> mint -> connect -> session.update -> greet.
    ///
    /// `requireMic` stays true in production: mic denied means no session
    /// (spec). Tests pass false so the sim test host's missing mic can't fail
    /// the phase. Only mint/transport errors (or a mic failure with
    /// `requireMic`) may set `.failed` — camera problems never do.
    func start(context: ModelContext, requireMic: Bool = true) async {
        guard phase == .idle else { return }
        startedAt = deps.now()

        // 1. Execution plan (compiler never fails — it falls back to linear).
        phase = .compiling
        let plan = await deps.compilePlan(recipe, scale)
        self.plan = plan

        // 2. Session snapshot: pantry, prefs, memories, past cooks of this recipe.
        let pantry = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        let prefs = UserPrefs.current(in: context)
        let memories = PollyMemoryStore.topFacts(limit: PollyConfig.memoryFactLimit, in: context)
        let pastSessions = recipe.cookSessions(in: context)
        let pantryMatch = PantryMatcher.match(recipe: recipe, pantry: pantry)
        missingIngredients = pantryMatch.missing.map(\.name)

        // 3. Tool registry; side effects that need the session come back here.
        let registry = PollyToolRegistry(
            plan: plan, recipe: recipe, pantry: pantry, prefs: prefs,
            timers: timers, context: context)
        registry.onRequestFrame = { [weak self] in
            guard let self, let jpeg = await self.camera.captureFrame() else { return false }
            let dataURI = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            do {
                try await self.transport?.send(.createUserImage(dataURI: dataURI, itemId: nil))
                return true
            } catch {
                return false
            }
        }
        registry.onEndSession = { [weak self] in self?.wantsEnd = true }
        self.registry = registry

        // 4. Mint + connect + configure. Only these failures fail the session.
        phase = .connecting
        let token: PollySessionToken
        do {
            token = try await deps.mintToken()
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        let config = RealtimeSessionConfig(
            instructions: PollyPromptBuilder.instructions(
                recipe: recipe, plan: plan, pantryMatch: pantryMatch,
                prefs: prefs, memories: memories, pastSessions: pastSessions),
            tools: PollyToolRegistry.toolDefinitions,
            voice: token.voice,
            model: token.model,
            transcribeInput: true)
        liveConfig = config

        let transport = deps.makeTransport()
        self.transport = transport
        do {
            try await transport.connect(token: token.value, model: token.model)
            try await transport.send(.sessionUpdate(config))
            try await transport.send(.responseCreate)   // Polly speaks first
            isThinking = true
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }

        // 5. Mic. Denied mic in production means no session (spec).
        do {
            try audio.start { [weak transport] chunk in
                Task { try? await transport?.send(.appendAudio(base64: chunk)) }
            }
        } catch {
            if requireMic {
                phase = .failed("Polly needs the microphone to cook with you. Enable it in Settings, or cook without Polly.")
                await transport.close()
                return
            }
            captionText = "Microphone unavailable — Polly can't hear you."
        }

        // 6. Camera is optional (denied -> voice-only session) and its
        //    permission prompt must never block the greeting: fire-and-forget.
        Task { [camera] in await camera.start() }

        phase = .live
        consumeEvents(from: transport, context: context)
        startWatchLoop(context: context)
    }

    /// Idempotent teardown: stop the pipelines, close the socket, extract
    /// memories from the transcript, and write the PollyCookLog.
    func end(context: ModelContext, endedEarly: Bool) async {
        guard !isEnding, phase != .ended, phase != .idle else { return }
        isEnding = true

        watchTask?.cancel()
        watchTask = nil
        eventTask?.cancel()
        eventTask = nil
        audio.stop()
        camera.stop()
        timers.cancelAll()
        await transport?.close()
        transport = nil

        flushPendingAssistantLine()
        let transcript = transcriptLog.joined(separator: "\n")
        let extraction = try? await deps.extractMemories(transcript, recipe.title)
        if let extraction {
            PollyMemoryExtractor.apply(extraction, recipeTitle: recipe.title, in: context)
        }

        let log = PollyCookLog(startedAt: startedAt ?? deps.now(), recipe: recipe)
        log.endedAt = deps.now()
        log.summary = extraction?.summary ?? ""
        log.stepsCompleted = registry?.state.completedStepIDs.count ?? 0
        log.stepsTotal = plan?.steps.count ?? 0
        log.substitutions = registry?.state.substitutions ?? []
        log.endedEarly = endedEarly
        context.insert(log)
        try? context.save()

        phase = .ended
    }

    // MARK: - User actions

    /// The "Show Polly" shutter: one frame straight into the conversation,
    /// then ask her to react to it.
    func sendShowPolly() async {
        guard phase == .live, let jpeg = await camera.captureFrame() else { return }
        let dataURI = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        try? await transport?.send(.createUserImage(dataURI: dataURI, itemId: nil))
        try? await transport?.send(.responseCreate)
        isThinking = true
    }

    func toggleMute() { audio.isMuted.toggle() }   // haptic lives in the view

    func flipCamera() { camera.flip() }

    // MARK: - Event loop

    private func consumeEvents(from transport: RealtimeTransporting, context: ModelContext) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in transport.events {
                guard let self, !Task.isCancelled else { return }
                await self.handle(event, context: context)
            }
        }
    }

    private func handle(_ event: RealtimeServerEvent, context: ModelContext) async {
        switch event {
        case .sessionCreated, .sessionUpdated, .responseCancelled, .unhandled:
            break

        case .outputAudioDelta(let itemId, let base64):
            audio.enqueue(base64: base64)
            currentAudioItemId = itemId
            isPollySpeaking = true
            isThinking = false

        case .speechStarted:
            // Barge-in: stop playback and tell the server how much was heard
            // so the truncated tail never pollutes the conversation state.
            let playedMs = audio.interruptPlayback()
            if let itemId = currentAudioItemId {
                try? await transport?.send(.truncateItem(itemId: itemId, audioEndMs: playedMs))
                currentAudioItemId = nil
            }
            isPollySpeaking = false
            isListening = true

        case .speechStopped:
            isListening = false

        case .inputTranscript(let text):
            captionText = text
            transcriptLog.append("USER: \(text)")

        case .outputTranscriptDelta(let itemId, let delta):
            if pendingAssistantItemId != itemId {
                flushPendingAssistantLine()
                pendingAssistantItemId = itemId
            }
            pendingAssistantLine += delta
            captionText = pendingAssistantLine

        case .responseDone(_, let calls):
            isPollySpeaking = false
            isThinking = false
            flushPendingAssistantLine()
            for call in calls {
                guard let registry else { continue }
                let output = await registry.handle(name: call.name, argumentsJSON: call.argumentsJSON)
                try? await transport?.send(.createFunctionOutput(callId: call.callId, output: output))
                try? await transport?.send(.responseCreate)
                isThinking = true
            }

        case .error(let code, let message):
            // Only the transport's own failure (code "transport", Task 7) means the
            // socket died. Server protocol errors (e.g. deleting an already-gone
            // item) must not kill a live cook — log them and keep going.
            if code == "transport" || phase != .live {
                await handleTransportError(message: message, context: context)
            } else {
                transcriptLog.append("[error] \(message)")
            }
        }
    }

    private func flushPendingAssistantLine() {
        if !pendingAssistantLine.isEmpty {
            transcriptLog.append("POLLY: \(pendingAssistantLine)")
        }
        pendingAssistantLine = ""
        pendingAssistantItemId = nil
    }

    /// One silent reconnect (spec degradation ladder); anything after that
    /// fails the session and the view offers "Cook without Polly".
    private func handleTransportError(message: String, context: ModelContext) async {
        guard !isEnding, phase != .ended else { return }
        guard phase == .live, !didAttemptReconnect else {
            phase = .failed(message)
            return
        }
        didAttemptReconnect = true
        captionText = "Connection hiccup — getting Polly back…"
        phase = .reconnecting
        do {
            let token = try await deps.mintToken()
            let transport = deps.makeTransport()
            try await transport.connect(token: token.value, model: token.model)
            if var config = liveConfig {
                config.voice = token.voice
                config.model = token.model
                try await transport.send(.sessionUpdate(config))
                liveConfig = config
            }
            self.transport = transport
            // A reconnect opens a NEW realtime conversation: item ids from the
            // old one are gone, so forget them — otherwise the next watch tick
            // would delete a nonexistent item and trigger a server error.
            lastWatchFrameItemId = nil
            currentAudioItemId = nil
            isThinking = false
            consumeEvents(from: transport, context: context)
            phase = .live
        } catch {
            phase = .failed(message)
        }
    }

    // MARK: - Watch mode + session cap

    private func startWatchLoop(context: ModelContext) {
        watchTask?.cancel()
        watchScheduler = WatchModeScheduler(
            isEnabled: isWatching, interval: PollyConfig.watchFrameInterval)
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.tick(context: context)
            }
        }
    }

    /// 1 Hz loop body — internal (not private) so tests drive it with a scripted `now`.
    func tick(context: ModelContext) async {
        guard phase == .live else { return }

        let elapsed = startedAt.map { deps.now().timeIntervalSince($0) } ?? 0

        // Hard stop safely before OpenAI's 60-minute session cap. Honest
        // bookkeeping: ending mid-plan is endedEarly even when the clock ran out.
        if elapsed > Double(PollyConfig.maxSessionMinutes * 60) {
            let finished = (registry?.state.completedStepIDs.count ?? 0) >= (plan?.steps.count ?? .max)
            await end(context: context, endedEarly: !finished)
            return
        }

        // One in-conversation nudge near the cap — the model has no clock and the
        // instructions are static, so the warning must arrive as a message.
        if !didSendWrapUpWarning, elapsed > Double(PollyConfig.wrapUpWarningMinutes * 60) {
            didSendWrapUpWarning = true
            try? await transport?.send(.createUserText(
                "[system note] This cooking session has to end in about five minutes. Start wrapping up naturally, and call end_session when the dish is done."))
            try? await transport?.send(.responseCreate)
            isThinking = true
        }

        watchScheduler.isEnabled = isWatching
        guard camera.isRunning, watchScheduler.shouldSendFrame(now: deps.now()) else { return }
        guard let jpeg = await camera.captureFrame() else { return }

        watchFrameCount += 1
        let itemId = "wf_\(watchFrameCount)"
        let dataURI = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
        try? await transport?.send(.createUserImage(dataURI: dataURI, itemId: itemId))
        // Drop the previous watch frame — stale frames only burn tokens.
        if let previous = lastWatchFrameItemId {
            try? await transport?.send(.deleteItem(itemId: previous))
        }
        lastWatchFrameItemId = itemId
    }
}
```

Implementation notes (why each choice, so the implementer doesn't "improve" them away):
- The event loop `Task` is created inside a `@MainActor` method, so it inherits the main actor — `handle` mutations of observable state are race-free and the view animates them directly.
- `consumeEvents` cancels the previous `eventTask` on reconnect. That cancel targets the task currently executing `handleTransportError` (called from the old loop) — harmless: after `handle` returns, the old transport's finished stream yields `nil` and the loop exits; the new task consumes the new transport's fresh stream.
- The mic chunk closure captures the transport `weak` and sends through a detached-ish `Task` per chunk: `send` is async and the audio tap callback must never block; `try?` because a dropped chunk during teardown is not an error.
- `flushPendingAssistantLine()` turns per-item transcript deltas into one `POLLY:` transcript line — flushed on item change and on `response.done` — so `extractMemories` sees clean alternating `USER:`/`POLLY:` lines.
- `tick` checks `camera.isRunning` **before** consuming a scheduler slot so a stopped camera doesn't burn the 10-second cadence, and the elapsed-time guards (wrap-up nudge + hard stop) run even when watch mode is off — the 1 Hz loop doubles as the session-cap clock. `tick` is internal, not private, so the wrap-up test can drive it with a scripted `now`.
- `end()` guards on `isEnding` (not just `phase`) because it suspends at `transport?.close()` and `extractMemories` — a second call during those awaits must be a no-op, which the idempotency test locks.

- [ ] **Step 5: Regenerate the project so the new source file (and new folder) join the app target.**
  Run in Bash: `cd /Users/omarlahmimi/Documents/Glutt && xcodegen generate`

- [ ] **Step 6: Run tests.**
  Run tests: `test_sim` (scheme `Glutt`) — expected: **PASS**, includes `PollySessionControllerTests.testStartSendsSessionUpdateThenGreetingAndGoesLive`, `testFunctionCallRoundTripSendsOutputThenResponseCreate`, `testBargeInTruncatesTheInterruptedAssistantItem`, `testEndSessionToolThenEndWritesCookLogAndMemories`, `testMintTokenFailureFailsThePhase`, `testTransportErrorWhileLiveReconnectsOnce`, `testProtocolErrorWhileLiveDoesNotKillTheSession`, `testTickSendsWrapUpWarningOnceThenHardStops` — and all pre-existing suites still green.

- [ ] **Step 7: Commit.**
  ```bash
  git -C /Users/omarlahmimi/Documents/Glutt add Glutt/Features/Polly/PollySessionController.swift GluttTests/PollySessionControllerTests.swift Glutt.xcodeproj/project.pbxproj
  git -C /Users/omarlahmimi/Documents/Glutt commit -m "$(cat <<'EOF'
  feat(polly): add live session controller with scripted-transport tests

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
  EOF
  )"
  ```

---

### Task 14: PollyMemoryExtractor

**Files:**
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyMemoryExtractor.swift`
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyMemoryExtractorTests.swift`

No Modify entries — this task only adds new files (the `Glutt/Services/Polly/` folder already exists from Task 2, and both folders are globbed in `project.yml`, so `xcodegen generate` picks the new files up automatically).

**Interfaces:**

Consumes (existing + earlier tasks — exact signatures):
```swift
// Glutt/Services/AI/LLMClient.swift (existing)
LLMClient.isConfigured: Bool
LLMClient.LLMError.notConfigured
static func LLMClient.chatJSON<T: Decodable>(_ type: T.Type, system: String, user: String,
    imageData: Data? = nil, temperature: Double = 0.2, timeout: TimeInterval = 30) async throws -> T

// Glutt/Models/Polly.swift (Task 3)
enum MemoryKind: String, Codable, CaseIterable { case equipment, technique, pantryHabit, preference, outcome }
@Model final class PollyMemory   // kindRaw, text, confidence, timesReinforced, createdAt, updatedAt, sourceRecipeTitle

// Glutt/Services/Polly/PollyMemoryStore.swift (Task 3)
@discardableResult
static func PollyMemoryStore.upsert(kind: MemoryKind, text: String, confidence: Double,
    sourceRecipeTitle: String?, in context: ModelContext) -> PollyMemory
```

Produces (Task 13's `Dependencies.extractMemories: (String, String) async throws -> PollyMemoryExtractor.Extraction` and `PollySessionController.end(context:endedEarly:)` rely on these):
```swift
enum PollyMemoryExtractor {
    struct Fact: Decodable, Equatable { let kind: String; let text: String; let confidence: Double }
    struct Extraction: Decodable, Equatable { let facts: [Fact]; let summary: String }
    typealias LLM = (_ system: String, _ user: String) async throws -> Extraction
    static func extract(transcript: String, recipeTitle: String, llm: LLM = /* LLMClient.chatJSON wrapper */) async throws -> Extraction
    static func apply(_ extraction: Extraction, recipeTitle: String, in context: ModelContext)
}
```
The `llm` parameter is defaulted, so Task 13's live dependency calls it exactly as the shared contract states: `PollyMemoryExtractor.extract(transcript:recipeTitle:)`.

- [ ] **Step 1: Write the failing test file**

  Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyMemoryExtractorTests.swift` with exactly:

  ```swift
  import XCTest
  import SwiftData
  @testable import Glutt

  @MainActor
  final class PollyMemoryExtractorTests: XCTestCase {
      private var container: ModelContainer!

      override func setUpWithError() throws {
          try super.setUpWithError()
          let schema = Schema([PollyMemory.self])
          container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
      }
      override func tearDownWithError() throws { container = nil; try super.tearDownWithError() }

      /// Wire-shaped fixture: two facts, the second with a kind the model made up.
      private let fixtureJSON = """
      { "facts": [
          { "kind": "equipment", "text": "Their stove runs hot on the front-left burner.", "confidence": 0.9 },
          { "kind": "stove-vibes", "text": "They like to taste as they go.", "confidence": 1.4 }
        ],
        "summary": "Cooked lemon chicken for four. The sear ran long because the pan was crowded. They were happy with the final dish." }
      """

      // MARK: - Decode contract

      func testExtractionDecodesFromFixture() throws {
          let extraction = try JSONDecoder().decode(PollyMemoryExtractor.Extraction.self, from: Data(fixtureJSON.utf8))
          XCTAssertEqual(extraction.facts.count, 2)
          XCTAssertEqual(extraction.facts[0].kind, "equipment")
          XCTAssertEqual(extraction.facts[0].text, "Their stove runs hot on the front-left burner.")
          XCTAssertEqual(extraction.facts[0].confidence, 0.9, accuracy: 0.0001)
          // Unknown kind strings survive decode untouched; apply() maps them later.
          XCTAssertEqual(extraction.facts[1].kind, "stove-vibes")
          XCTAssertEqual(extraction.facts[1].confidence, 1.4, accuracy: 0.0001)
          XCTAssertFalse(extraction.summary.isEmpty)
      }

      // MARK: - apply

      func testApplyMapsKindsClampsConfidenceAndSkipsShortText() throws {
          let context = container.mainContext
          let extraction = PollyMemoryExtractor.Extraction(
              facts: [
                  .init(kind: "equipment", text: "Their stove runs hot on the front-left burner.", confidence: 0.9),
                  .init(kind: "stove-vibes", text: "They like to taste as they go.", confidence: 1.4),
                  .init(kind: "technique", text: "They chop vegetables slowly and carefully.", confidence: -0.3),
                  .init(kind: "preference", text: "Salty.", confidence: 0.5),
              ],
              summary: "A calm, tidy cook."
          )

          PollyMemoryExtractor.apply(extraction, recipeTitle: "Lemon Chicken", in: context)

          let rows = try context.fetch(FetchDescriptor<PollyMemory>())
          XCTAssertEqual(rows.count, 3, "the 6-char fact must be skipped (min 8 chars)")

          let stove = try XCTUnwrap(rows.first { $0.text == "Their stove runs hot on the front-left burner." })
          XCTAssertEqual(stove.kind, .equipment)
          XCTAssertEqual(stove.confidence, 0.9, accuracy: 0.0001)
          XCTAssertEqual(stove.sourceRecipeTitle, "Lemon Chicken")

          let taste = try XCTUnwrap(rows.first { $0.text == "They like to taste as they go." })
          XCTAssertEqual(taste.kind, .outcome, "invalid kind string falls back to .outcome")
          XCTAssertEqual(taste.confidence, 1.0, accuracy: 0.0001, "confidence clamps to 1")

          let chop = try XCTUnwrap(rows.first { $0.text == "They chop vegetables slowly and carefully." })
          XCTAssertEqual(chop.kind, .technique)
          XCTAssertEqual(chop.confidence, 0.0, accuracy: 0.0001, "confidence clamps to 0")

          XCTAssertNil(rows.first { $0.text == "Salty." })
      }

      // MARK: - extract (stubbed llm, no network)

      func testExtractUsesInjectedLLMAndBuildsPrompts() async throws {
          let fixture = try JSONDecoder().decode(PollyMemoryExtractor.Extraction.self, from: Data(fixtureJSON.utf8))
          var capturedSystem = ""
          var capturedUser = ""

          let result = try await PollyMemoryExtractor.extract(
              transcript: "Polly: How did the sear go?\nUser: Pan was crowded, took forever.",
              recipeTitle: "Lemon Chicken",
              llm: { system, user in
                  capturedSystem = system
                  capturedUser = user
                  return fixture
              }
          )

          XCTAssertEqual(result, fixture)
          XCTAssertTrue(capturedSystem.contains("DURABLE"))
          // All five kinds must be offered to the model by rawValue.
          for kind in MemoryKind.allCases {
              XCTAssertTrue(capturedSystem.contains(kind.rawValue), "system prompt missing kind \(kind.rawValue)")
          }
          XCTAssertTrue(capturedSystem.contains("third person"))
          XCTAssertTrue(capturedUser.contains("Lemon Chicken"))
          XCTAssertTrue(capturedUser.contains("Pan was crowded"))
      }
  }
  ```

- [ ] **Step 2: Regenerate the project and watch the test fail**
  - Run: `xcodegen generate` (from `/Users/omarlahmimi/Documents/Glutt`). Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.
  - Run tests: `test_sim` (scheme `Glutt`) — expected: **FAIL** — the `GluttTests` target does not compile: `cannot find 'PollyMemoryExtractor' in scope`. This proves the test exercises code that doesn't exist yet.

- [ ] **Step 3: Minimal implementation**

  Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Services/Polly/PollyMemoryExtractor.swift` with exactly:

  ```swift
  import Foundation
  import SwiftData

  /// Post-cook memory: one `chatJSON` pass over the session transcript pulls
  /// out durable kitchen facts (stove runs hot, owns cast iron, chops slowly)
  /// plus a short summary for the cook log. `apply` lands the facts in
  /// `PollyMemory` through the store's dedup/reinforce upsert — the LLM
  /// proposes, the store disposes.
  enum PollyMemoryExtractor {

      struct Fact: Decodable, Equatable {
          let kind: String
          let text: String
          let confidence: Double
      }

      struct Extraction: Decodable, Equatable {
          let facts: [Fact]
          let summary: String
      }

      typealias LLM = (_ system: String, _ user: String) async throws -> Extraction

      /// One-shot extraction over the full session transcript.
      /// `llm` is injectable for tests; the default routes through the proxy.
      static func extract(
          transcript: String,
          recipeTitle: String,
          llm: LLM = { system, user in
              try await LLMClient.chatJSON(Extraction.self, system: system, user: user, temperature: 0.2, timeout: 30)
          }
      ) async throws -> Extraction {
          guard LLMClient.isConfigured else { throw LLMClient.LLMError.notConfigured }

          let system = """
          You read the transcript of a live cooking session and extract DURABLE kitchen facts
          a chef should remember about this specific cook and this cook's kitchen.

          Return JSON: {"facts": [{"kind": str, "text": str, "confidence": num}], "summary": str}

          Rules:
          - kind: one of "equipment", "technique", "pantryHabit", "preference", "outcome".
          - text: one sentence, third person ("Their stove runs hot", "They own a cast-iron skillet").
          - confidence: 0 to 1 — how sure you are the fact holds beyond this one session.
          - Only durable facts: equipment they own, how their appliances behave, techniques they
            struggle with or excel at, what they keep stocked, what they like, how their dishes
            tend to turn out.
          - Ignore one-off chatter, jokes, and anything specific to just this dish today.
          - Return an empty facts array when nothing durable came up.
          - summary: 2-3 sentences describing how this cook went, for the session log.
          """

          let user = """
          Recipe: \(recipeTitle)

          Transcript:
          \(transcript)
          """

          return try await llm(system, user)
      }

      /// Write extracted facts into on-device memory. Unknown kinds fall back
      /// to `.outcome`, confidence is clamped to 0...1, and fragments under
      /// 8 characters are dropped as noise. Dedup/reinforce lives in the store.
      static func apply(_ extraction: Extraction, recipeTitle: String, in context: ModelContext) {
          for fact in extraction.facts {
              guard fact.text.count >= 8 else { continue }
              let kind = MemoryKind(rawValue: fact.kind) ?? .outcome
              let confidence = min(max(fact.confidence, 0), 1)
              PollyMemoryStore.upsert(
                  kind: kind,
                  text: fact.text,
                  confidence: confidence,
                  sourceRecipeTitle: recipeTitle,
                  in: context
              )
          }
      }
  }
  ```

- [ ] **Step 4: Regenerate and run the tests green**
  - Run: `xcodegen generate` (picks up the new source file). Expected output ends with `Created project at /Users/omarlahmimi/Documents/Glutt/Glutt.xcodeproj`.
  - Run tests: `test_sim` (scheme `Glutt`) — expected: **PASS**, includes `PollyMemoryExtractorTests/testExtractionDecodesFromFixture`, `PollyMemoryExtractorTests/testApplyMapsKindsClampsConfidenceAndSkipsShortText`, `PollyMemoryExtractorTests/testExtractUsesInjectedLLMAndBuildsPrompts`, with all pre-existing suites (incl. `PollyMemoryStoreTests` from Task 3) still green.

- [ ] **Step 5: Commit**

  ```bash
  cd /Users/omarlahmimi/Documents/Glutt
  git add Glutt.xcodeproj Glutt/Services/Polly/PollyMemoryExtractor.swift GluttTests/PollyMemoryExtractorTests.swift
  git commit -m "$(cat <<'EOF'
  feat(polly): add post-cook memory extraction

  One chatJSON pass over the session transcript extracts durable kitchen
  facts (kind/text/confidence) plus a 2-3 sentence summary; apply() maps
  unknown kinds to .outcome, clamps confidence to 0...1, skips sub-8-char
  fragments, and upserts through PollyMemoryStore's dedup/reinforce rule.
  LLM call is closure-injected so tests run without network.

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
  EOF
  )"
  ```

---

### Task 15: Session UI + app wiring (cover, detail button, paywall seam, banner suppression)

**Files:**
- Create: `Glutt/Features/Polly/PollySessionView.swift`
- Create: `Glutt/Features/Polly/PollySessionSubviews.swift`
- Create: `Glutt/Features/Polly/PollyPaywallHook.swift`
- Modify: `Glutt/App/Router.swift` (insert `PollyLaunch` struct above the `Router` doc comment at line 71; insert two new vars after `var pendingPresentPlates = false`, line 95)
- Modify: `Glutt/App/RootView.swift` (add a fullScreenCover after the Plates cover, lines 62–64)
- Modify: `Glutt/App/GluttApp.swift` (`willPresent`, lines 24–30)
- Modify: `Glutt/Features/Recipes/RecipeDetailView.swift` (`cookBar`, lines 434–448)
- Test: none new — this is a live-UI task. The gate is: full existing suite stays green (`test_sim`) plus a scripted simulator verification with screenshots (steps below).

**Interfaces:**

Consumes (exact signatures from earlier tasks / existing code):
- `PollySessionController` (Task 13): `init(recipe: Recipe, scale: Double, deps: Dependencies = .live, audio: PollyAudioEngine = PollyAudioEngine(), camera: PollyCameraController = PollyCameraController())`, `func start(context: ModelContext, requireMic: Bool = true) async` (runs once per controller instance — a retry after `.failed` must create a NEW controller; mic permission is requested by THIS VIEW before calling it), `func end(context: ModelContext, endedEarly: Bool) async`, `func sendShowPolly() async`, `func toggleMute()`, `func flipCamera()`, `private(set) var phase: Phase` (`case idle, compiling, connecting, live, reconnecting, ended, failed(String)`), `private(set) var plan: CookPlan?`, `private(set) var captionText: String`, `private(set) var isPollySpeaking: Bool`, `private(set) var isListening: Bool`, `private(set) var isThinking: Bool`, `private(set) var wantsEnd: Bool` (set by the `end_session` tool — this view MUST observe it and call `end`), `private(set) var missingIngredients: [String]`, `var isWatching: Bool`, `let audio: PollyAudioEngine`, `let camera: PollyCameraController`, `let timers: TimerManager`, `var stepIndex: Int`
- `PollyAudioEngine` (Task 8): `var isMuted: Bool`, `private(set) var inputLevel: Float`
- `PollyCameraController` (Task 9): `private(set) var isRunning: Bool`, `let previewLayer: AVCaptureVideoPreviewLayer`, `func start() async`, `func stop()`
- `CookPlan.PlanStep` (Task 2): `id`, `index`, `title`, `instruction`, `timerSeconds: Int?`
- Vendored `Ph` cases added in Task 1: `chefHat`, `microphone`, `videoCamera`, `eye` (fill + regular); `microphoneSlash`, `videoCameraSlash`, `eyeSlash`, `cameraRotate` (REGULAR ONLY — Task 1 does not vendor their fill variants). Pre-existing cases used: `camera`, `x`, `timer`, `bellRinging`, `xCircle`.
- Existing app code: `CookModeView(recipe:scale:)`, `CookFinishView(recipe: Recipe, scale: Double, onComplete: @escaping () -> Void)`, `TimerManager` (`start(label:seconds:)`, `cancel(_:)`, `timers`, `now`, `CookTimer.remainingSeconds(at:)`, `TimerManager.format(seconds:)`), `LLMClient.isConfigured`, `Haptics.*`, `Theme.*`, `Font.glutt*`, `.gluttPrimary`/`.gluttSecondary`, `GluttTabBar.reservedHeight`, `Router.floatingButtonSuppressors`.

Produces (later tasks rely on these exact signatures):
```swift
// Glutt/App/Router.swift
struct PollyLaunch: Identifiable, Equatable {
    let id = UUID()          // excluded from the memberwise init
    let recipe: Recipe
    let scale: Double
}                            // memberwise init: PollyLaunch(recipe:scale:)
// Router gains:
var pollyLaunch: PollyLaunch?
var isPollySessionActive = false

// Glutt/Features/Polly/PollySessionView.swift
struct PollySessionView: View { /* init(recipe: Recipe, scale: Double) */ }

// Glutt/Features/Polly/PollyPaywallHook.swift
enum PollyPaywallHook { static func run(completion: @escaping () -> Void) }
```
> **Contract amendment (locked):** `PollyLaunch` **supersedes** the `pendingPollyRecipeID: PersistentIdentifier?` sketch in the Shared Contracts — a bare id cannot carry the detail screen's serving scale. Task 16's recipe picker must launch sessions with `router.pollyLaunch = PollyLaunch(recipe: r, scale: 1)`. `isPollySessionActive` is unchanged from the contract.

- [ ] **Step 1: Verify dependencies before writing any code.**
  Read `Glutt/Features/Cook/CookModeView.swift` (top bar / exit dialog / timers bar / idle-timer patterns), `Glutt/Features/Plates/RecipeFeedView.swift` (suppressor + circle-button patterns), `Glutt/DesignSystem/Theme.swift`, `Typography.swift`, `Components/Buttons.swift`, `Glutt/Features/Assistant/InventionPaywallHook.swift`, `Glutt/App/GluttApp.swift:8–30` and `:63–69`, `Glutt/Features/Recipes/RecipeDetailView.swift:43–77` and `:434–448`. Then confirm Task 1's vendored icon cases exist:
  ```
  grep -n "chefHat\|microphoneSlash\|microphone \|eyeSlash\|cameraRotate\|case eye " Glutt/DesignSystem/Phosphor.swift
  ```
  Expected: cases `chefHat`, `microphone`, `microphoneSlash`, `eye`, `eyeSlash`, `cameraRotate` all present. If any is missing, STOP — Task 1 is incomplete; finish it first (this task's UI renders empty images without those imagesets).

- [ ] **Step 2: Baseline — confirm the suite is green before touching anything.**
  Call `session_show_defaults` (confirm project `Glutt.xcodeproj`, scheme `Glutt`, a booted iPhone simulator; set with `session_set_defaults` if not).
  Run tests: `test_sim` (scheme `Glutt`) — expected: PASS (all suites from Tasks 2–14 green).

- [ ] **Step 3: Create the paywall seam (no test — it's a documented no-op).**
  Create `Glutt/Features/Polly/PollyPaywallHook.swift` with exactly:
  ```swift
  /// Gates live "Cook with Polly" sessions.
  ///
  /// ⚠️ PAYWALL TEMPORARILY DISABLED FOR THE FREE LAUNCH.
  /// While Glutt ships free (Paid Apps Agreement pending — DUNS in progress),
  /// Polly sessions are unlocked for everyone. The completion block always runs.
  ///
  /// Kept as a single no-op seam so the Premium gate can be switched back on with
  /// a one-line change. To re-enable, see `docs/REENABLE-PAYMENTS.md`.
  enum PollyPaywallHook {
      static func run(completion: @escaping () -> Void) {
          // Free launch: feature unlocked for everyone — always run.
          // Re-enable the gate per docs/REENABLE-PAYMENTS.md:
          //   Superwall.shared.register(placement: "polly_session") {
          //       guard Superwall.shared.subscriptionStatus.isActive else { return }
          //       completion()
          //   }
          completion()
      }
  }
  ```
  Run `xcodegen generate` (new file under the globbed `Glutt/` folder).
  Build: `build_sim` — expected: succeeds.

- [ ] **Step 4: Router — add `PollyLaunch` and the two session vars.**
  In `Glutt/App/Router.swift`, insert the struct directly above the Router doc comment. Before (line 71):
  ```swift
  /// App-wide navigation state + deep link routing skeleton.
  /// Deep links: glutt://today, glutt://recipes, glutt://import?url=..., etc.
  /// The share extension (Phase 2) will route imports through here.
  @Observable
  final class Router {
  ```
  After:
  ```swift
  /// A "Cook with Polly" request: the recipe plus the serving scale chosen on
  /// the detail screen. Identifiable so RootView can present the session with
  /// `.fullScreenCover(item:)` — a fresh `id` per tap means re-launching the
  /// same recipe always starts a fresh session.
  struct PollyLaunch: Identifiable, Equatable {
      let id = UUID()
      let recipe: Recipe
      let scale: Double
  }

  /// App-wide navigation state + deep link routing skeleton.
  /// Deep links: glutt://today, glutt://recipes, glutt://import?url=..., etc.
  /// The share extension (Phase 2) will route imports through here.
  @Observable
  final class Router {
  ```
  Then add the vars. Before (lines 92–97):
  ```swift
      /// Set by the Today launcher card, the glutt://plates deep link, or the
      /// daily "Today's Plate" notification. RootView presents the Plates feed
      /// (a fullScreenCover, not a tab) whenever this is true.
      var pendingPresentPlates = false
      /// Dev/testing hook (`-demoCook`): opens Cook Mode for the first recipe on launch.
      var demoCookOnLaunch = false
  ```
  After:
  ```swift
      /// Set by the Today launcher card, the glutt://plates deep link, or the
      /// daily "Today's Plate" notification. RootView presents the Plates feed
      /// (a fullScreenCover, not a tab) whenever this is true.
      var pendingPresentPlates = false
      /// Set by the "Cook with Polly" button on recipe detail (and, in Task 16,
      /// the Polly tab's recipe picker). RootView presents the live session
      /// (a fullScreenCover) whenever this is non-nil; carries the serving
      /// scale the user chose so Polly cooks the right amounts.
      var pollyLaunch: PollyLaunch?
      /// True while a live Polly session is on screen. GluttApp's notification
      /// delegate suppresses foreground banners while it's set — in-session
      /// timers already render natively over the camera.
      var isPollySessionActive = false
      /// Dev/testing hook (`-demoCook`): opens Cook Mode for the first recipe on launch.
      var demoCookOnLaunch = false
  ```

- [ ] **Step 5: GluttApp — suppress banners during a live session.**
  In `Glutt/App/GluttApp.swift`, before (lines 24–30):
  ```swift
      func userNotificationCenter(
          _ center: UNUserNotificationCenter,
          willPresent notification: UNNotification
      ) async -> UNNotificationPresentationOptions {
          [.banner, .sound]
      }
  ```
  After:
  ```swift
      func userNotificationCenter(
          _ center: UNUserNotificationCenter,
          willPresent notification: UNNotification
      ) async -> UNNotificationPresentationOptions {
          // A live Polly session renders its timers natively over the camera —
          // a banner on top would announce the same thing twice. Stay quiet
          // until the session ends.
          if router?.isPollySessionActive == true { return [] }
          return [.banner, .sound]
      }
  ```
  Build: `build_sim` — expected: succeeds (Router + delegate changes compile; nothing presents the cover yet).

- [ ] **Step 6: Create the session subviews.**
  Create `Glutt/Features/Polly/PollySessionSubviews.swift` with exactly:
  ```swift
  import AVFoundation
  import SwiftUI

  // MARK: - Camera preview

  /// Hosts the session camera's AVCaptureVideoPreviewLayer full-bleed behind
  /// the overlay chrome. The UIKit hop is unavoidable: preview layers are CALayers.
  struct CameraPreviewView: UIViewRepresentable {
      let previewLayer: AVCaptureVideoPreviewLayer

      final class LayerHostView: UIView {
          var hostedLayer: AVCaptureVideoPreviewLayer? {
              didSet {
                  guard hostedLayer !== oldValue else { return }
                  oldValue?.removeFromSuperlayer()
                  if let hostedLayer {
                      hostedLayer.videoGravity = .resizeAspectFill
                      layer.addSublayer(hostedLayer)
                      setNeedsLayout()
                  }
              }
          }

          override func layoutSubviews() {
              super.layoutSubviews()
              hostedLayer?.frame = bounds
          }
      }

      func makeUIView(context: Context) -> LayerHostView {
          let view = LayerHostView()
          view.hostedLayer = previewLayer
          return view
      }

      func updateUIView(_ uiView: LayerHostView, context: Context) {
          uiView.hostedLayer = previewLayer
      }
  }

  // MARK: - Orb

  /// Polly's presence: a 64 pt herb-green orb. Swells with the mic level while
  /// listening, breathes gently while Polly speaks, dims in a slow pulse while
  /// she thinks, sits still when idle.
  struct PollyOrb: View {
      let inputLevel: Float
      let isListening: Bool
      let isSpeaking: Bool
      let isThinking: Bool

      @State private var breathe = false
      @State private var thinkingPulse = false

      private var micScale: CGFloat {
          guard isListening else { return 1 }
          return 1 + 0.25 * CGFloat(min(max(inputLevel, 0), 1))
      }

      private var showsThinking: Bool { isThinking && !isSpeaking && !isListening }

      var body: some View {
          Circle()
              .fill(Theme.Colors.accent)
              .overlay(
                  Ph.chefHat.fill
                      .resizable().scaledToFit()
                      .frame(width: 26, height: 26)
                      .foregroundStyle(Theme.Colors.creamText)
              )
              .frame(width: 64, height: 64)
              .scaleEffect(isSpeaking ? (breathe ? 1.12 : 1.0) : micScale)
              .opacity(showsThinking ? (thinkingPulse ? 0.55 : 1.0) : 1.0)
              .animation(.easeOut(duration: 0.1), value: micScale)
              .onChange(of: isSpeaking) { _, speaking in
                  if speaking {
                      withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                          breathe = true
                      }
                  } else {
                      withAnimation(.easeOut(duration: 0.2)) { breathe = false }
                  }
              }
              .onChange(of: showsThinking) { _, thinking in
                  if thinking {
                      withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                          thinkingPulse = true
                      }
                  } else {
                      withAnimation(.easeOut(duration: 0.2)) { thinkingPulse = false }
                  }
              }
              .accessibilityLabel(
                  isSpeaking ? "Polly is speaking"
                      : isListening ? "Polly is listening"
                      : showsThinking ? "Polly is thinking"
                      : "Polly"
              )
      }
  }

  // MARK: - Step card

  /// The current CookPlan step, floated above the camera near the controls.
  /// Polly narrates out loud; this card is the glanceable "where are we" anchor.
  struct PollyStepCard: View {
      let step: CookPlan.PlanStep
      let totalSteps: Int
      let onStartTimer: (Int) -> Void

      var body: some View {
          VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
              SectionLabel(text: "Step \(step.index + 1) of \(totalSteps)")
              Text(step.title)
                  .font(.gluttHeadline)
                  .foregroundStyle(Theme.Colors.textPrimary)
              Text(step.instruction)
                  .font(.gluttCaption)
                  .foregroundStyle(Theme.Colors.textSecondary)
                  .lineLimit(3)
                  .fixedSize(horizontal: false, vertical: true)
              if let seconds = step.timerSeconds {
                  Button {
                      Haptics.selection()
                      onStartTimer(seconds)
                  } label: {
                      HStack(spacing: Theme.Spacing.xs) {
                          Ph.timer.regular
                              .resizable().scaledToFit()
                              .frame(width: 15, height: 15)
                          Text("Start \(TimerManager.format(seconds: seconds)) timer")
                              .font(.gluttCaption.weight(.semibold))
                      }
                      .foregroundStyle(.white)
                      .padding(.horizontal, Theme.Spacing.md)
                      .padding(.vertical, 9)
                      .background(Theme.Colors.warning)
                      .clipShape(Capsule())
                  }
                  .buttonStyle(.plain)
              }
          }
          .padding(Theme.Spacing.md)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.Colors.card.opacity(0.94))
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))
      }
  }

  // MARK: - Preflight card

  /// Missing-ingredients checklist shown while Polly talks through the
  /// preflight conversationally. Dismissible — Polly and the cook may well
  /// decide to press on with substitutions.
  struct PreflightCard: View {
      let missing: [String]
      let onDismiss: () -> Void

      var body: some View {
          VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
              SectionLabel(text: "Before you start")
              Text("You're missing:")
                  .font(.gluttHeadline)
                  .foregroundStyle(Theme.Colors.textPrimary)
              ForEach(missing, id: \.self) { name in
                  HStack(spacing: Theme.Spacing.xs) {
                      Circle()
                          .fill(Theme.Colors.tomato)
                          .frame(width: 6, height: 6)
                      Text(name)
                          .font(.gluttCaption)
                          .foregroundStyle(Theme.Colors.textSecondary)
                  }
              }
              Button {
                  Haptics.selection()
                  onDismiss()
              } label: {
                  Text("Got it")
                      .font(.gluttCaption.weight(.semibold))
                      .foregroundStyle(Theme.Colors.accent)
              }
              .buttonStyle(.plain)
          }
          .padding(Theme.Spacing.md)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Theme.Colors.card.opacity(0.94))
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.photo, style: .continuous))
      }
  }

  // MARK: - Timers row

  /// Compact mirror of CookModeView's activeTimersBar, driven by the
  /// session-owned TimerManager.
  struct PollyTimersRow: View {
      let manager: TimerManager

      var body: some View {
          ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: Theme.Spacing.sm) {
                  ForEach(manager.timers) { timer in
                      let remaining = timer.remainingSeconds(at: manager.now)
                      HStack(spacing: 6) {
                          if remaining == 0 {
                              Ph.bellRinging.fill
                                  .resizable().scaledToFit()
                                  .frame(width: 14, height: 14)
                                  .foregroundStyle(.white)
                                  .onAppear { Haptics.notify(.success) }
                          } else {
                              Ph.timer.regular
                                  .resizable().scaledToFit()
                                  .frame(width: 14, height: 14)
                                  .foregroundStyle(.white)
                          }
                          Text(remaining == 0 ? "Done!" : TimerManager.format(seconds: remaining))
                              .monospacedDigit()
                          Button {
                              Haptics.impact(.light)
                              manager.cancel(timer)
                          } label: {
                              Ph.xCircle.fill
                                  .resizable().scaledToFit()
                                  .frame(width: 14, height: 14)
                                  .foregroundStyle(.white.opacity(0.7))
                          }
                      }
                      .font(.gluttCaption.weight(.semibold))
                      .foregroundStyle(.white)
                      .padding(.horizontal, 10)
                      .padding(.vertical, 6)
                      .background(remaining == 0 ? Theme.Colors.tomato : Theme.Colors.accent)
                      .clipShape(Capsule())
                  }
              }
          }
      }
  }

  // MARK: - Control button

  /// Circular glass control for the session bar. Every tap gives haptic feedback.
  struct PollyControlButton: View {
      let icon: Image
      var tint: Color = .white
      let label: String
      let action: () -> Void

      var body: some View {
          Button {
              Haptics.impact(.light)
              action()
          } label: {
              icon
                  .resizable().scaledToFit()
                  .frame(width: 20, height: 20)
                  .foregroundStyle(tint)
                  .frame(width: 52, height: 52)
                  .background(.ultraThinMaterial, in: Circle())
          }
          .accessibilityLabel(label)
      }
  }
  ```

- [ ] **Step 7: Create the session screen.**
  Create `Glutt/Features/Polly/PollySessionView.swift` with exactly:
  ```swift
  import AVFAudio
  import SwiftData
  import SwiftUI

  /// Live "Cook with Polly" session: full-bleed camera preview behind a
  /// voice-first overlay — orb, rolling caption, current step, timers, controls.
  /// Presented as a fullScreenCover from RootView via `router.pollyLaunch`.
  /// The screen stays awake for the whole cook (wet hands, no taps needed).
  struct PollySessionView: View {
      @Environment(\.dismiss) private var dismiss
      @Environment(\.modelContext) private var context
      @Environment(Router.self) private var router

      let recipe: Recipe
      /// Serving scale carried over from the detail screen.
      var scale: Double = 1

      @State private var controller: PollySessionController?
      @State private var startedAt = Date.now
      @State private var isConfirmingExit = false
      @State private var isShowingFinish = false
      @State private var isEndingWithoutSaving = false
      @State private var micDenied = false
      @State private var didDismissPreflight = false
      /// Set by "Cook without Polly": swaps the session for classic Cook Mode
      /// inside the same cover, so the user never loses their place.
      @State private var isCookingWithoutPolly = false

      var body: some View {
          Group {
              if isCookingWithoutPolly {
                  CookModeView(recipe: recipe, scale: scale)
              } else {
                  sessionContent
              }
          }
          .task {
              guard controller == nil else { return }
              await startSession()
          }
          .onAppear {
              router.isPollySessionActive = true
              router.floatingButtonSuppressors += 1
              UIApplication.shared.isIdleTimerDisabled = true
          }
          .onDisappear {
              router.isPollySessionActive = false
              router.floatingButtonSuppressors -= 1
              UIApplication.shared.isIdleTimerDisabled = false
          }
          .onChange(of: controller?.phase) { _, phase in
              // Controller-initiated end that already ran end() (e.g. the
              // session-cap hard stop): route into the same finish-and-log flow.
              guard phase == .ended, !isShowingFinish, !isEndingWithoutSaving,
                    !isCookingWithoutPolly else { return }
              isShowingFinish = true
          }
          .onChange(of: controller?.wantsEnd) { _, wants in
              // Polly-initiated end (the end_session tool): the tool only sets
              // the flag — this view owns the teardown + finish-and-log flow.
              guard wants == true, !isShowingFinish, !isEndingWithoutSaving,
                    !isCookingWithoutPolly else { return }
              isShowingFinish = true
              Task { await controller?.end(context: context, endedEarly: false) }
          }
          .sheet(isPresented: $isShowingFinish) {
              CookFinishView(recipe: recipe, scale: scale) {
                  dismiss()
              }
              .interactiveDismissDisabled()
          }
          .confirmationDialog(
              "End cooking with Polly?", isPresented: $isConfirmingExit, titleVisibility: .visible
          ) {
              Button("Keep cooking", role: .cancel) {}
              Button("Finish & log") {
                  isShowingFinish = true
                  Task { await controller?.end(context: context, endedEarly: false) }
              }
              Button("End without saving", role: .destructive) {
                  isEndingWithoutSaving = true
                  Task {
                      await controller?.end(context: context, endedEarly: true)
                      dismiss()
                  }
              }
          }
      }

      // MARK: - Session startup

      /// Mic permission is requested HERE, before the controller exists — the
      /// engine itself never prompts. Denied mic means no session (spec), so
      /// the user gets a clear card instead of a silently deaf Polly. Also the
      /// "Try again" path: a fresh controller every time, because start() runs
      /// once per instance.
      private func startSession() async {
          let granted = await AVAudioApplication.requestRecordPermission()
          guard granted else {
              micDenied = true
              return
          }
          let session = PollySessionController(recipe: recipe, scale: scale)
          controller = session
          await session.start(context: context)
      }

      // MARK: - Layers

      private var sessionContent: some View {
          ZStack {
              background
              if micDenied {
                  micDeniedCard
              } else if let controller {
                  overlayChrome(for: controller)
                  phaseOverlay(for: controller)
              }
          }
      }

      /// Camera preview when running; otherwise a calm dark backdrop with a
      /// chef-hat watermark (voice-only sessions, permission denied, simulator).
      @ViewBuilder
      private var background: some View {
          if let controller, controller.camera.isRunning {
              CameraPreviewView(previewLayer: controller.camera.previewLayer)
                  .ignoresSafeArea()
          } else {
              ZStack {
                  Theme.Colors.textPrimary.ignoresSafeArea()
                  Ph.chefHat.fill
                      .resizable().scaledToFit()
                      .frame(width: 180, height: 180)
                      .foregroundStyle(Theme.Colors.creamText.opacity(0.08))
              }
          }
      }

      private func overlayChrome(for controller: PollySessionController) -> some View {
          VStack(spacing: 0) {
              topBar
              Spacer()
              bottomStack(for: controller)
          }
      }

      // MARK: - Top bar

      private var topBar: some View {
          HStack {
              Button {
                  Haptics.impact(.light)
                  isConfirmingExit = true
              } label: {
                  Ph.x.regular
                      .resizable().scaledToFit()
                      .frame(width: 16, height: 16)
                      .foregroundStyle(.white)
                      .frame(width: 40, height: 40)
                      .background(.ultraThinMaterial, in: Circle())
              }
              Spacer()
              VStack(spacing: 1) {
                  Text(recipe.title)
                      .font(.system(size: 13, weight: .heavy))
                      .foregroundStyle(.white)
                      .lineLimit(1)
                  TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                      Text(elapsedLabel(at: timeline.date))
                          .font(.system(size: 11.5, weight: .bold))
                          .monospacedDigit()
                          .foregroundStyle(.white.opacity(0.85))
                  }
              }
              Spacer()
              // Invisible twin of the X button so the title stays centered.
              Color.clear.frame(width: 40, height: 40)
          }
          .padding(.horizontal, Theme.Spacing.md)
          .padding(.vertical, Theme.Spacing.sm)
      }

      private func elapsedLabel(at date: Date) -> String {
          TimerManager.format(seconds: max(0, Int(date.timeIntervalSince(startedAt))))
      }

      // MARK: - Bottom stack

      private func bottomStack(for controller: PollySessionController) -> some View {
          VStack(spacing: Theme.Spacing.sm) {
              PollyOrb(
                  inputLevel: controller.audio.inputLevel,
                  isListening: controller.isListening,
                  isSpeaking: controller.isPollySpeaking,
                  isThinking: controller.isThinking
              )
              if !controller.captionText.isEmpty {
                  captionLine(controller.captionText)
              }
              if controller.phase == .live, !controller.missingIngredients.isEmpty,
                 !didDismissPreflight {
                  PreflightCard(missing: controller.missingIngredients) {
                      didDismissPreflight = true
                  }
              }
              if let step = currentStep(of: controller) {
                  PollyStepCard(step: step, totalSteps: controller.plan?.steps.count ?? 0) { seconds in
                      controller.timers.start(
                          label: "Step \(step.index + 1): \(String(step.title.prefix(40)))",
                          seconds: seconds
                      )
                  }
              }
              if !controller.timers.timers.isEmpty {
                  PollyTimersRow(manager: controller.timers)
              }
              controlsRow(for: controller)
          }
          .padding(.horizontal, Theme.Spacing.md)
          .padding(.bottom, Theme.Spacing.md)
          .background(alignment: .bottom) {
              LinearGradient(
                  colors: [Theme.Colors.textPrimary.opacity(0), Theme.Colors.textPrimary.opacity(0.6)],
                  startPoint: .top, endPoint: .bottom
              )
              .padding(.top, -Theme.Spacing.xl)
              .ignoresSafeArea(edges: .bottom)
              .allowsHitTesting(false)
          }
      }

      private func captionLine(_ text: String) -> some View {
          Text(text)
              .font(.gluttCaption.weight(.semibold))
              .foregroundStyle(Theme.Colors.creamText)
              .lineLimit(2)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(Theme.Colors.textPrimary.opacity(0.55))
              .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
      }

      private func currentStep(of controller: PollySessionController) -> CookPlan.PlanStep? {
          guard let plan = controller.plan,
                plan.steps.indices.contains(controller.stepIndex) else { return nil }
          return plan.steps[controller.stepIndex]
      }

      private func controlsRow(for controller: PollySessionController) -> some View {
          HStack(spacing: Theme.Spacing.sm) {
              PollyControlButton(
                  icon: controller.audio.isMuted ? Ph.microphoneSlash.regular : Ph.microphone.fill,
                  label: controller.audio.isMuted ? "Unmute" : "Mute"
              ) {
                  controller.toggleMute()
              }
              PollyControlButton(
                  icon: controller.isWatching ? Ph.eye.fill : Ph.eyeSlash.regular,
                  label: "Polly watches while you cook"
              ) {
                  controller.isWatching.toggle()
              }
              PollyControlButton(icon: Ph.camera.regular, label: "Show Polly") {
                  Task { await controller.sendShowPolly() }
              }
              // Privacy control: turning the camera OFF is as important as flip.
              PollyControlButton(
                  icon: controller.camera.isRunning ? Ph.videoCamera.fill : Ph.videoCameraSlash.regular,
                  label: "Camera on or off"
              ) {
                  if controller.camera.isRunning {
                      controller.camera.stop()
                  } else {
                      Task { await controller.camera.start() }
                  }
              }
              PollyControlButton(icon: Ph.cameraRotate.regular, label: "Flip camera") {
                  controller.flipCamera()
              }
              PollyControlButton(icon: Ph.x.regular, tint: Theme.Colors.tomato, label: "End session") {
                  isConfirmingExit = true
              }
          }
      }

      // MARK: - Phase overlays

      @ViewBuilder
      private func phaseOverlay(for controller: PollySessionController) -> some View {
          switch controller.phase {
          case .idle, .compiling:
              statusCard("Polly is reading the recipe…")
          case .connecting:
              statusCard("Calling Polly…")
          case .reconnecting:
              VStack {
                  Text("One sec — reconnecting…")
                      .font(.gluttCaption.weight(.semibold))
                      .foregroundStyle(Theme.Colors.creamText)
                      .padding(.horizontal, 14)
                      .padding(.vertical, 8)
                      .background(Theme.Colors.textPrimary.opacity(0.55))
                      .clipShape(Capsule())
                      .padding(.top, 60)
                  Spacer()
              }
          case .failed(let message):
              failedCard(message: message, controller: controller)
          case .live, .ended:
              EmptyView()
          }
      }

      private func statusCard(_ message: String) -> some View {
          VStack(spacing: Theme.Spacing.md) {
              ProgressView()
                  .tint(Theme.Colors.accent)
              Text(message)
                  .font(.gluttHeadline)
                  .foregroundStyle(Theme.Colors.textPrimary)
                  .multilineTextAlignment(.center)
          }
          .padding(Theme.Spacing.lg)
          .frame(maxWidth: 300)
          .background(Theme.Colors.card)
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
      }

      private func failedCard(message: String, controller: PollySessionController) -> some View {
          VStack(spacing: Theme.Spacing.md) {
              Ph.chefHat.regular
                  .resizable().scaledToFit()
                  .frame(width: 32, height: 32)
                  .foregroundStyle(Theme.Colors.accent)
              Text("Polly couldn't pick up")
                  .font(.gluttTitle)
                  .foregroundStyle(Theme.Colors.textPrimary)
              Text(message)
                  .font(.gluttBody)
                  .foregroundStyle(Theme.Colors.textSecondary)
                  .multilineTextAlignment(.center)
              Button("Try again") {
                  Haptics.impact(.medium)
                  // start() runs once per controller instance — retry means a
                  // fresh controller (startSession builds one).
                  controller = nil
                  Task { await startSession() }
              }
              .buttonStyle(.gluttPrimary)
              Button("Cook without Polly") {
                  Haptics.impact(.light)
                  isCookingWithoutPolly = true
                  router.isPollySessionActive = false
                  Task { await controller.end(context: context, endedEarly: true) }
              }
              .buttonStyle(.gluttSecondary)
          }
          .padding(Theme.Spacing.lg)
          .frame(maxWidth: 320)
          .background(Theme.Colors.card)
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
      }

      private var micDeniedCard: some View {
          VStack(spacing: Theme.Spacing.md) {
              Ph.microphoneSlash.regular
                  .resizable().scaledToFit()
                  .frame(width: 32, height: 32)
                  .foregroundStyle(Theme.Colors.accent)
              Text("Polly can't hear you")
                  .font(.gluttTitle)
                  .foregroundStyle(Theme.Colors.textPrimary)
              Text("Polly needs the microphone to cook with you. You can enable it in Settings, or cook without her.")
                  .font(.gluttBody)
                  .foregroundStyle(Theme.Colors.textSecondary)
                  .multilineTextAlignment(.center)
              Button("Cook without Polly") {
                  Haptics.impact(.light)
                  isCookingWithoutPolly = true
                  router.isPollySessionActive = false
              }
              .buttonStyle(.gluttPrimary)
          }
          .padding(Theme.Spacing.lg)
          .frame(maxWidth: 320)
          .background(Theme.Colors.card)
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
      }
  }
  ```
  Run `xcodegen generate` (two new files this batch).
  Build: `build_sim` — expected: succeeds. (Nothing presents the view yet; this proves the new files compile against the Task 13 controller.)

- [ ] **Step 8: RootView — present the session cover.**
  In `Glutt/App/RootView.swift`, before (lines 62–64):
  ```swift
          .fullScreenCover(isPresented: $router.pendingPresentPlates) {
              RecipeFeedView()
          }
  ```
  After:
  ```swift
          .fullScreenCover(isPresented: $router.pendingPresentPlates) {
              RecipeFeedView()
          }
          .fullScreenCover(item: $router.pollyLaunch) { launch in
              PollySessionView(recipe: launch.recipe, scale: launch.scale)
          }
  ```

- [ ] **Step 9: RecipeDetailView — "Cook with Polly" entry point.**
  In `Glutt/Features/Recipes/RecipeDetailView.swift`, replace the cook bar. Before (lines 434–448):
  ```swift
      // MARK: - Cook bar

      private var cookBar: some View {
          Button {
              Haptics.impact(.medium)
              if pantryMatch.missing.isEmpty { isCooking = true } else { isShowingPreCookChecklist = true }
          } label: {
              Label("Cook", systemImage: "frying.pan").frame(maxWidth: .infinity)
          }
          .buttonStyle(.gluttPrimary)
          .padding(.horizontal, Theme.Spacing.md)
          .padding(.top, Theme.Spacing.sm)
          .padding(.bottom, GluttTabBar.reservedHeight)
          .background(Theme.Colors.background.opacity(0.95))
      }
  ```
  After:
  ```swift
      // MARK: - Cook bar

      /// Bottom action bar. "Cook with Polly" leads when AI is configured and
      /// the classic Cook button demotes to secondary — but keeps working
      /// (restyle golden rule: never remove a feature). Without AI, Cook
      /// stays primary and nothing changes.
      private var cookBar: some View {
          VStack(spacing: Theme.Spacing.sm) {
              if LLMClient.isConfigured {
                  Button {
                      Haptics.impact(.medium)
                      PollyPaywallHook.run {
                          router.pollyLaunch = PollyLaunch(recipe: recipe, scale: scale)
                      }
                  } label: {
                      HStack(spacing: 6) {
                          Ph.chefHat.fill
                              .resizable().scaledToFit()
                              .frame(width: 18, height: 18)
                          Text("Cook with Polly")
                      }
                      .frame(maxWidth: .infinity)
                  }
                  .buttonStyle(.gluttPrimary)
                  classicCookButton
                      .buttonStyle(.gluttSecondary)
              } else {
                  classicCookButton
                      .buttonStyle(.gluttPrimary)
              }
          }
          .padding(.horizontal, Theme.Spacing.md)
          .padding(.top, Theme.Spacing.sm)
          .padding(.bottom, GluttTabBar.reservedHeight)
          .background(Theme.Colors.background.opacity(0.95))
      }

      private var classicCookButton: some View {
          Button {
              Haptics.impact(.medium)
              if pantryMatch.missing.isEmpty { isCooking = true } else { isShowingPreCookChecklist = true }
          } label: {
              Label("Cook", systemImage: "frying.pan").frame(maxWidth: .infinity)
          }
      }
  ```
  (`router` is already in scope — `@Environment(Router.self) private var router`, line 7. The `frying.pan` systemImage is pre-existing, not new Polly UI — leave it.)
  Build: `build_sim` — expected: succeeds.

- [ ] **Step 10: Full suite must stay green.**
  Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, same test count as the Step 2 baseline (no new tests in this task; every suite from Tasks 2–14 still green).

- [ ] **Step 11: Simulator verification with screenshots (degradation path — no Realtime backend on sim).**
  1. `build_run_sim` (scheme `Glutt`) — expected: app boots to the Today tab.
  2. `stop_app_sim`, then `launch_app_sim` with bundleId `com.omarlahmimi.glutt` and args `["-seed", "-tab", "recipes"]` — the `-seed` flag seeds demo recipes (same flag the "Glutt Beta" scheme passes, see `GluttApp.swift:63–69`); `-tab recipes` lands on the Recipes tab.
  3. `snapshot_ui`, tap the first recipe card → detail opens.
  4. `screenshot` → save `polly-detail-cookbar.png`. Expected: bottom bar shows a filled green "Cook with Polly" (chef-hat glyph) above an outlined "Cook" button (`Secrets.aiProxyBaseURL` is non-empty, so `LLMClient.isConfigured == true`).
  5. Tap "Cook with Polly" → the microphone permission alert appears FIRST (the view calls `AVAudioApplication.requestRecordPermission()` before creating the controller) — tap Allow via `snapshot_ui` + tap. The fullScreenCover then shows a dark chef-hat-watermark backdrop (simulator has no camera). Expected phase progression: "Polly is reading the recipe…" → "Calling Polly…" → failed card "Polly couldn't pick up" (the `/polly/session` mint fails on sim — backend not deployed). `screenshot` → save `polly-session-failed.png`. Optional extra check: deny the mic on a fresh install instead and expect the "Polly can't hear you" card with its own "Cook without Polly" button.
  6. Tap "Cook without Polly" → classic `CookModeView` replaces the session inside the cover (cream background, "Step 1 of N" top bar). `screenshot` → save `polly-classic-fallback.png`.
  7. Tap the X → "Stop cooking?" dialog → "Exit without saving" → back on the recipe detail; confirm the floating + button is visible again on the Recipes list (suppressors balanced).
  Expected: all three screenshots match the descriptions; no crash, no stuck cover.

- [ ] **Step 12: Commit.**
  ```
  git add Glutt/Features/Polly/PollySessionView.swift Glutt/Features/Polly/PollySessionSubviews.swift Glutt/Features/Polly/PollyPaywallHook.swift Glutt/App/Router.swift Glutt/App/RootView.swift Glutt/App/GluttApp.swift Glutt/Features/Recipes/RecipeDetailView.swift Glutt.xcodeproj/project.pbxproj
  git commit -m "$(cat <<'EOF'
  feat(polly): add live session screen and cook-with-polly entry point

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9
  EOF
  )"
  ```

---

### Task 16: The Polly tab

**Files:**
- Modify: `/Users/omarlahmimi/Documents/Glutt/Glutt/App/Router.swift` — `AppTab` enum (case list line 6, `label` switch lines 9–17, `icon` switch lines 19–27) and `handle(url:)` (lines 130–156). Line anchors are from the pre-Polly tree; Task 15's Router additions (`pollyLaunch`, `isPollySessionActive`) shift the class body but not the `AppTab` enum — locate by the before-snippets below.
- Modify: `/Users/omarlahmimi/Documents/Glutt/Glutt/App/RootView.swift` — `tabContent(for:)` switch (lines 84–93 pre-Polly; Task 15's `fullScreenCover` addition shifts it slightly).
- Modify: `/Users/omarlahmimi/Documents/Glutt/Glutt/DesignSystem/Components/GluttTabBar.swift` — `glyph(for:active:)` switch (lines 49–57).
- Modify: `/Users/omarlahmimi/Documents/Glutt/Glutt/App/GluttApp.swift` — `NotificationRoutingDelegate.userNotificationCenter(_:didReceive:)` (lines 11–22 pre-Polly; Task 15 adds an `isPollySessionActive` check to `willPresent` just below — locate by snippet).
- Create: `/Users/omarlahmimi/Documents/Glutt/Glutt/Features/Polly/PollyTabView.swift`
- Test: `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyRouterTests.swift`

**Interfaces:**

Consumes:
- `Ph.chefHat` (Task 1): `case chefHat = "chef-hat"` in the `Ph` enum, with `.regular` and `.fill` variants vendored in `Glutt/Resources/Assets.xcassets/Phosphor/`.
- `@Model final class PollyMemory` and `@Model final class PollyCookLog` (Task 3; both already in the `Schema([...])` list in `GluttApp.swift`). Fields used here: `PollyMemory.text: String`; `PollyCookLog.startedAt: Date`, `recipe: Recipe?`, `summary: String`, `stepsCompleted: Int`, `stepsTotal: Int`.
- `PollyMemoryStore.topFacts(limit: Int, in context: ModelContext) -> [PollyMemory]` (Task 3).
- `Router.pollyLaunch: PollyLaunch?` and `struct PollyLaunch { init(recipe: Recipe, scale: Double) }` (Task 15) — setting `router.pollyLaunch` makes RootView present the `PollySessionView` full-screen cover.
- `PollyPaywallHook.run(completion: @escaping () -> Void)` (Task 15) — no-op seam, calls `completion()` immediately.
- Existing: `LLMClient.isConfigured: Bool` (`Glutt/Services/AI/LLMClient.swift:25`), `RecipeCard(recipe:pantryMatch:)` (`pantryMatch: (owned: Int, total: Int)?` — nil hides the pill), `PantryMatcher.match(recipe:pantry:) -> MatchResult` (`.ownedCount`/`.totalCount`), `@Model PantryItem`, `EmptyStateView(icon:title:message:actionLabel:action:)`, `SectionHeader(title:)`, `GluttTabBar.reservedHeight`, `Haptics.impact(_:)`, `Router.perform(_:)`, `.cardStyle()`, `Theme.Colors/Spacing/Radius`, `Font.glutt*`.

Produces:
- `AppTab.polly` — rawValue `"polly"`, label `"Polly"`, index 2 of `AppTab.allCases` (order: today, recipes, polly, plan, kitchen, progress). The `-tab polly` launch argument works automatically via the existing `AppTab(rawValue:)` hook in `Router.init()`.
- Deep link `glutt://polly` → `router.selectedTab = .polly`.
- Notification destination `"polly"` → `router.selectedTab = .polly` (used by any future Polly notification content).
- `struct PollyTabView: View` (parameterless init) — hosted by `RootView.tabContent(for:)`.

- [ ] **Step 1: Write the failing router test (full file)**

  Create `/Users/omarlahmimi/Documents/Glutt/GluttTests/PollyRouterTests.swift`. No SwiftData models are touched, so no in-memory container is needed (matches `RouterImportNavigationTests` style — `@MainActor`, plain `Router()` instances):

  ```swift
  import XCTest
  @testable import Glutt

  @MainActor
  final class PollyRouterTests: XCTestCase {

      func testPollyTabExistsThirdWithLabel() {
          XCTAssertEqual(AppTab.allCases.count, 6)
          XCTAssertEqual(AppTab.allCases[2], .polly)
          XCTAssertEqual(AppTab.polly.label, "Polly")
          XCTAssertEqual(
              AppTab.allCases.map(\.id),
              ["today", "recipes", "polly", "plan", "kitchen", "progress"]
          )
      }

      func testPollyDeepLinkSelectsTab() {
          let router = Router()
          router.handle(url: URL(string: "glutt://polly")!)
          XCTAssertEqual(router.selectedTab, .polly)
      }

      /// Covers the `-tab polly` launch-argument hook: `Router.init()` resolves
      /// the argument through `AppTab(rawValue:)`, so a clean round-trip is the
      /// contract that hook relies on.
      func testPollyRawValueRoundTrips() {
          XCTAssertEqual(AppTab(rawValue: "polly"), .polly)
          XCTAssertEqual(AppTab.polly.rawValue, "polly")
      }
  }
  ```

- [ ] **Step 2: Regenerate the project**

  Run `xcodegen generate` via Bash in `/Users/omarlahmimi/Documents/Glutt` — XcodeGen bakes file lists into `Glutt.xcodeproj`, so the new test file needs a regeneration.

- [ ] **Step 3: Run tests — expect failure**

  Run tests: `test_sim` (scheme `Glutt`) — expected: FAIL. The `GluttTests` target does not compile: `type 'AppTab' has no member 'polly'` in `PollyRouterTests.swift` (three references).

- [ ] **Step 4: Add `AppTab.polly` to Router.swift**

  In `/Users/omarlahmimi/Documents/Glutt/Glutt/App/Router.swift`, four edits.

  Edit 1 — insert the case THIRD in the case list. Before:

  ```swift
  enum AppTab: String, CaseIterable, Identifiable {
      case today, recipes, plan, kitchen, progress
      var id: String { rawValue }
  ```

  After:

  ```swift
  enum AppTab: String, CaseIterable, Identifiable {
      case today, recipes, polly, plan, kitchen, progress
      var id: String { rawValue }
  ```

  Edit 2 — the `label` switch. Before:

  ```swift
      var label: String {
          switch self {
          case .today: "Today"
          case .recipes: "Recipes"
          case .plan: "Plan"
  ```

  After:

  ```swift
      var label: String {
          switch self {
          case .today: "Today"
          case .recipes: "Recipes"
          case .polly: "Polly"
          case .plan: "Plan"
  ```

  Edit 3 — the `icon` switch (this SF-string property is not used by the custom `GluttTabBar`, which renders Phosphor glyphs; the placeholder string keeps the switch exhaustive). Before:

  ```swift
      var icon: String {
          switch self {
          case .today: "sun.max"
          case .recipes: "book"
          case .plan: "calendar"
  ```

  After:

  ```swift
      var icon: String {
          switch self {
          case .today: "sun.max"
          case .recipes: "book"
          case .polly: "chef-hat" // placeholder — GluttTabBar draws Ph.chefHat
          case .plan: "calendar"
  ```

  Edit 4 — the deep link in `handle(url:)`. Before:

  ```swift
          switch url.host {
          case "today": selectedTab = .today
          case "recipes": selectedTab = .recipes
          case "plan": selectedTab = .plan
  ```

  After:

  ```swift
          switch url.host {
          case "today": selectedTab = .today
          case "recipes": selectedTab = .recipes
          case "polly": selectedTab = .polly
          case "plan": selectedTab = .plan
  ```

- [ ] **Step 5: Add the chef-hat glyph to GluttTabBar.swift**

  In `/Users/omarlahmimi/Documents/Glutt/Glutt/DesignSystem/Components/GluttTabBar.swift`, extend the exhaustive glyph switch. Before:

  ```swift
      private func glyph(for tab: AppTab, active: Bool) -> Image {
          switch tab {
          case .today:    return active ? Ph.house.fill : Ph.house.regular
          case .recipes:  return active ? Ph.bookOpen.fill : Ph.bookOpen.regular
          case .plan:     return active ? Ph.calendarBlank.fill : Ph.calendarBlank.regular
  ```

  After:

  ```swift
      private func glyph(for tab: AppTab, active: Bool) -> Image {
          switch tab {
          case .today:    return active ? Ph.house.fill : Ph.house.regular
          case .recipes:  return active ? Ph.bookOpen.fill : Ph.bookOpen.regular
          case .polly:    return active ? Ph.chefHat.fill : Ph.chefHat.regular
          case .plan:     return active ? Ph.calendarBlank.fill : Ph.calendarBlank.regular
  ```

- [ ] **Step 6: Create PollyTabView.swift (full file)**

  Create `/Users/omarlahmimi/Documents/Glutt/Glutt/Features/Polly/PollyTabView.swift`:

  ```swift
  import SwiftData
  import SwiftUI

  /// The Polly tab: what Polly knows about your kitchen, a recipe picker that
  /// launches a live cooking session, and the recent-cooks log. When the AI
  /// service isn't configured the tab degrades to a single setup card (house
  /// `LLMClient.isConfigured` convention).
  struct PollyTabView: View {
      @Environment(Router.self) private var router
      @Environment(\.modelContext) private var context
      @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
      @Query(sort: \PollyCookLog.startedAt, order: .reverse) private var cookLogs: [PollyCookLog]
      @Query private var pantryItems: [PantryItem]

      var body: some View {
          ScrollView {
              VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                  header
                  if LLMClient.isConfigured {
                      memoryCard
                      cookSection
                      recentCooksSection
                  } else {
                      setupCard
                  }
              }
              .padding(Theme.Spacing.md)
          }
          .contentMargins(.bottom, GluttTabBar.reservedHeight, for: .scrollContent)
          .background(Theme.Colors.background)
      }

      // MARK: - Header

      private var header: some View {
          VStack(alignment: .leading, spacing: 2) {
              Text("Polly")
                  .font(.gluttLargeTitle)
                  .foregroundStyle(Theme.Colors.textPrimary)
              Text("Your live cooking chef")
                  .font(.gluttCaption)
                  .foregroundStyle(Theme.Colors.textSecondary)
          }
      }

      // MARK: - Setup card (AI not configured)

      private var setupCard: some View {
          EmptyStateView(
              icon: "sparkles",
              title: "Polly needs the AI service",
              message: "This build isn't connected to Glutt's AI yet, so live cooking sessions are unavailable. Your recipes and Cook Mode still work everywhere else."
          )
          .padding(.top, Theme.Spacing.xl)
      }

      // MARK: - What Polly knows

      private var memoryCount: Int {
          (try? context.fetchCount(FetchDescriptor<PollyMemory>())) ?? 0
      }

      private var memoryCard: some View {
          let facts = PollyMemoryStore.topFacts(limit: 3, in: context)
          return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
              HStack {
                  Text("What Polly knows")
                      .font(.gluttHeadline)
                      .foregroundStyle(Theme.Colors.textPrimary)
                  Spacer()
                  if memoryCount > 0 {
                      Text(memoryCount == 1 ? "1 kitchen note" : "\(memoryCount) kitchen notes")
                          .font(.gluttCaption)
                          .foregroundStyle(Theme.Colors.textSecondary)
                  }
              }
              if facts.isEmpty {
                  Text("Polly learns your kitchen every time you cook together.")
                      .font(.gluttBody)
                      .foregroundStyle(Theme.Colors.textSecondary)
              } else {
                  VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                      ForEach(facts) { fact in
                          HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                              Circle()
                                  .fill(Theme.Colors.accent)
                                  .frame(width: 5, height: 5)
                                  .padding(.top, 7)
                              Text(fact.text)
                                  .font(.gluttBody)
                                  .foregroundStyle(Theme.Colors.textPrimary)
                          }
                      }
                  }
              }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .cardStyle()
      }

      // MARK: - Cook something together

      @ViewBuilder
      private var cookSection: some View {
          SectionHeader(title: "Cook something together")
          if recipes.isEmpty {
              EmptyStateView(
                  icon: "book",
                  title: "No recipes yet",
                  message: "Save a recipe first — share one from TikTok or paste a link.",
                  actionLabel: "Import a recipe",
                  action: { router.perform(.importRecipe) }
              )
          } else {
              ForEach(recipes.prefix(20)) { recipe in
                  let match = PantryMatcher.match(recipe: recipe, pantry: pantryItems)
                  Button {
                      Haptics.impact(.medium)
                      PollyPaywallHook.run {
                          router.pollyLaunch = PollyLaunch(recipe: recipe, scale: 1)
                      }
                  } label: {
                      RecipeCard(recipe: recipe, pantryMatch: (match.ownedCount, match.totalCount))
                  }
                  .buttonStyle(.plain)
                  .accessibilityHint("Starts a live cooking session with Polly")
              }
          }
      }

      // MARK: - Recent cooks with Polly

      @ViewBuilder
      private var recentCooksSection: some View {
          if !cookLogs.isEmpty {
              SectionHeader(title: "Recent cooks with Polly")
              let recent = Array(cookLogs.prefix(5))
              VStack(spacing: 0) {
                  ForEach(recent) { log in
                      cookLogRow(log)
                      if log !== recent.last {
                          Divider().overlay(Theme.Colors.border)
                      }
                  }
              }
              .padding(.horizontal, Theme.Spacing.md)
              .cardStyle(padding: Theme.Spacing.xs)
          }
      }

      private func cookLogRow(_ log: PollyCookLog) -> some View {
          HStack(spacing: Theme.Spacing.sm) {
              Ph.chefHat.regular
                  .resizable()
                  .scaledToFit()
                  .frame(width: 18, height: 18)
                  .foregroundStyle(Theme.Colors.accent)
              VStack(alignment: .leading, spacing: 1) {
                  Text(logTitle(log))
                      .font(.gluttBody)
                      .foregroundStyle(Theme.Colors.textPrimary)
                      .lineLimit(1)
                  Text(log.startedAt.formatted(date: .abbreviated, time: .shortened))
                      .font(.caption2)
                      .foregroundStyle(Theme.Colors.textSecondary)
              }
              Spacer()
              Text("\(log.stepsCompleted)/\(log.stepsTotal) steps")
                  .font(.gluttCaption.weight(.medium))
                  .foregroundStyle(Theme.Colors.textSecondary)
          }
          .padding(.vertical, Theme.Spacing.sm)
      }

      private func logTitle(_ log: PollyCookLog) -> String {
          if let title = log.recipe?.title, !title.isEmpty { return title }
          if !log.summary.isEmpty { return String(log.summary.prefix(60)) }
          return "Cooking session"
      }
  }

  #Preview {
      PollyTabView()
          .environment(Router())
          .modelContainer(for: [Recipe.self, PantryItem.self, PollyMemory.self, PollyCookLog.self], inMemory: true)
  }
  ```

- [ ] **Step 7: Host the tab in RootView.swift**

  In `/Users/omarlahmimi/Documents/Glutt/Glutt/App/RootView.swift`, extend the exhaustive `tabContent` switch. Before:

  ```swift
      @ViewBuilder
      private func tabContent(for tab: AppTab) -> some View {
          switch tab {
          case .today: TodayView()
          case .recipes: RecipesView()
          case .plan: PlanView()
  ```

  After:

  ```swift
      @ViewBuilder
      private func tabContent(for tab: AppTab) -> some View {
          switch tab {
          case .today: TodayView()
          case .recipes: RecipesView()
          case .polly: PollyTabView()
          case .plan: PlanView()
  ```

- [ ] **Step 8: Route the "polly" notification destination in GluttApp.swift**

  In `/Users/omarlahmimi/Documents/Glutt/Glutt/App/GluttApp.swift`, inside `NotificationRoutingDelegate.userNotificationCenter(_:didReceive:)`. Before:

  ```swift
          if destination == "plan" {
              router?.selectedTab = .plan
          } else if destination == "plates" {
              router?.selectedTab = .today
              router?.pendingPresentPlates = true
          }
  ```

  After:

  ```swift
          if destination == "plan" {
              router?.selectedTab = .plan
          } else if destination == "plates" {
              router?.selectedTab = .today
              router?.pendingPresentPlates = true
          } else if destination == "polly" {
              router?.selectedTab = .polly
          }
  ```

- [ ] **Step 9: Regenerate the project again**

  Run `xcodegen generate` via Bash in `/Users/omarlahmimi/Documents/Glutt` (picks up `Glutt/Features/Polly/PollyTabView.swift`; the `Glutt/Features/Polly/` folder already exists from Tasks 13/15).

- [ ] **Step 10: Run tests — expect pass**

  Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, includes `testPollyTabExistsThirdWithLabel`, `testPollyDeepLinkSelectsTab`, `testPollyRawValueRoundTrips`, and the entire pre-existing suite (nothing else regresses: the three modified switches were exhaustive, so the compiler enforced every call site).

- [ ] **Step 11: Commit**

  ```
  git add Glutt/App/Router.swift Glutt/App/RootView.swift Glutt/App/GluttApp.swift Glutt/DesignSystem/Components/GluttTabBar.swift Glutt/Features/Polly/PollyTabView.swift GluttTests/PollyRouterTests.swift Glutt.xcodeproj
  git commit -m "feat(polly): add the Polly tab with kitchen memory and recipe launcher

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9"
  ```

- [ ] **Step 12: Simulator verification — six tabs with the chef hat**

  If not already done this session, call `session_show_defaults` (project `Glutt.xcodeproj`, scheme `Glutt`, an iPhone simulator). Then `build_run_sim` with launch arguments `["-seed", "-tab", "polly"]` — expected: succeeds; the app boots with seeded demo recipes directly on the Polly tab. Capture `screenshot` — verify: the bottom bar shows SIX tabs (Today, Recipes, Polly, Plan, Kitchen, Progress) with the chef-hat glyph third and active (filled, light-green); the screen shows the "Polly" header with "Your live cooking chef", the "What Polly knows" card (fresh install → "Polly learns your kitchen every time you cook together."), and the "Cook something together" recipe cards. If the local build has an empty `Secrets.aiProxyBaseURL`, the header + setup card ("Polly needs the AI service") is the correct degraded render instead — note which state was verified.

- [ ] **Step 13: Simulator verification — recipe tap opens the session cover**

  With the app still running and `LLMClient.isConfigured` true: `snapshot_ui` to locate the first recipe card in "Cook something together", tap it — expected: `Haptics.impact(.medium)` fires (no-op on simulator), `PollyPaywallHook.run` calls through immediately, `router.pollyLaunch` is set to `PollyLaunch(recipe: recipe, scale: 1)`, and RootView (Task 15) presents the `PollySessionView` full-screen cover (compiling/preflight state — the socket will fail without a deployed proxy, which surfaces Task 15's "Cook without Polly" fallback; that failure is expected on simulator). Capture `screenshot` of the cover. Dismiss/end the session afterwards.

---

### Task 17: Docs amendment + full verification pass

**Files:**
- Modify: `/Users/omarlahmimi/Documents/Glutt/product.md` — "Core Navigation" section (lines 49–59: "maximum of five main tabs" + the 5-item list). The "Avoid" list (lines 262–269, contains "Cartoon chef mascots." and "Too many tabs.") stays untouched — the amendment note covers the exception.
- Modify: `/Users/omarlahmimi/Documents/Glutt/README.md` — intro feature sentence (line 3) and the `Glutt/Features` structure bullet (line 35).
- Modify: `/Users/omarlahmimi/Documents/Glutt/docs/superpowers/specs/2026-07-02-polly-live-chef-design.md` — four factual corrections the implementation surfaced (session cap, token payload field name, cost knobs, tab position); see Step 8.
- Modify: `/Users/omarlahmimi/Documents/Glutt/structure.md` — prepend one amendment note at line 1. (Checked: it DOES repeat the 5-tab list verbatim — the whole document is duplicated inside itself; the tab table appears at lines 5–10 and again at lines 576–581, and line 1 "The app’s actual structure" reappears glued mid-file at line 572. One note at the top covers every repeat; do NOT touch the body.)
- Test: none new — this task runs the FULL existing suite plus a live simulator verification pass.

**Interfaces:**
- Consumes: `AppTab.polly` (rawValue `"polly"`, label "Polly", icon `chef-hat` — Task 15/16); `Router.init()` launch-arg hook `-tab <rawValue>` (`Glutt/App/Router.swift` lines 104–110, sets `selectedTab` via `AppTab(rawValue:)`, so `-tab polly` works with zero new code); `PollyTabView` (Task 16); the "Cook with Polly" button on `RecipeDetailView` (Task 15/16); the classic cook bar `RecipeDetailView.cookBar` (lines 436–448, `Label("Cook", systemImage: "frying.pan")`) and its `fullScreenCover` → `CookModeView(recipe:scale:)` (lines 55–57); the 14 Polly test suites from Tasks 1–16.
- Produces: nothing code-level. This is the final task; its output is amended docs, verification screenshots under `docs/superpowers/verify-screenshots/`, and the closing commit.

> TDD note: this task has no production code, so there is no failing-test step. The "red → green" here is the verification checklist: docs edits first, then the full suite and a live simulator pass must come back green before the commit.

- [ ] **Step 1: Amend `product.md` — navigation contract goes from five tabs to six.**

  Read `/Users/omarlahmimi/Documents/Glutt/product.md` (the whole file was read while planning; the section to change is lines 49–59), then apply exactly one Edit:

  Before (exact, lines 49–59):
  ```markdown
  ## Core Navigation

  Use a simple bottom navigation with a maximum of five main tabs:

  1. **Today**
  2. **Recipes**
  3. **Plan**
  4. **Kitchen**
  5. **Progress**

  There should also be one main universal action button for adding/importing/scanning/logging.
  ```

  After:
  ```markdown
  ## Core Navigation

  Use a simple bottom navigation with a maximum of six main tabs:

  1. **Today**
  2. **Recipes**
  3. **Polly**
  4. **Plan**
  5. **Kitchen**
  6. **Progress**

  Polly is the app's live-chef persona — an approved exception to the no-mascot rule (2026-07). It is the sixth tab added, but it sits third (center) in the bar — this list is the implemented order (`AppTab.allCases`: today, recipes, polly, plan, kitchen, progress).

  There should also be one main universal action button for adding/importing/scanning/logging.
  ```

  Do not edit anything else in `product.md` — in particular leave the "Main Tabs" detail sections and the "Avoid" list exactly as they are; the one-line note is the whole contract amendment (matches the spec: "product.md gets a short amendment noting the new contract").

- [ ] **Step 2: Amend `README.md` — add the Polly feature line in the file's existing styles.**

  Read `/Users/omarlahmimi/Documents/Glutt/README.md`, then apply exactly two Edits. The README has no bulleted feature list — its "feature list" is the comma-list intro sentence (line 3) plus the Architecture structure bullets (lines 32–36), so amend both in place.

  Edit 1 — intro sentence. Before (exact, line 3):
  ```markdown
  A mobile-first cooking assistant. Import recipes from anywhere, know what's in your kitchen, plan your week, cook with guidance, and track what you actually ate — without the app forcing gym culture on you.
  ```
  After:
  ```markdown
  A mobile-first cooking assistant. Import recipes from anywhere, know what's in your kitchen, plan your week, cook with guidance or live with Polly (a realtime voice + camera AI chef), and track what you actually ate — without the app forcing gym culture on you.
  ```

  Edit 2 — Features folder bullet. Before (exact, line 35, note the two-space indent):
  ```markdown
    - `Glutt/Features` — one folder per tab: Today, Recipes, Plan, Kitchen, Progress, plus Capture (universal + button)
  ```
  After:
  ```markdown
    - `Glutt/Features` — one folder per tab: Today, Recipes, Polly (live cooking sessions), Plan, Kitchen, Progress, plus Capture (universal + button)
  ```

- [ ] **Step 3: Amend `structure.md` — one prepended note, nothing else.**

  `structure.md` repeats the 5-tab list verbatim (tab table at lines 5–10 and duplicated at lines 576–581; "only five main places" at lines 17 and 588; the Level-1 tab list at lines 471–475 and 1042–1046), so per the plan rule it must be amended — minimally. A unique Edit anchor does not exist at the top of the file (its opening line "The app’s actual structure\n\nI would make the bottom navigation:" occurs twice — at line 1 and glued mid-file at line 572), so prepend the note with a single Bash command instead of the Edit tool:

  ```bash
  printf '> Amendment (2026-07): the bottom navigation now has six tabs — Today, Recipes, Polly (the live AI chef tab, third/center), Plan, Kitchen, Progress. The five-tab lists below predate Polly; see product.md for the current navigation contract.\n\n' | cat - /Users/omarlahmimi/Documents/Glutt/structure.md > /Users/omarlahmimi/Documents/Glutt/structure.md.tmp && mv /Users/omarlahmimi/Documents/Glutt/structure.md.tmp /Users/omarlahmimi/Documents/Glutt/structure.md
  ```

  Verify the edit is exactly two added lines at the top and nothing else:
  ```bash
  head -3 /Users/omarlahmimi/Documents/Glutt/structure.md
  git -C /Users/omarlahmimi/Documents/Glutt diff --stat structure.md
  ```
  Expected: `head` shows the `> Amendment (2026-07): …` line, a blank line, then `The app’s actual structure`; `diff --stat` shows `structure.md | 2 ++` (2 insertions, 0 deletions). If the deletion count is non-zero, restore with `git -C /Users/omarlahmimi/Documents/Glutt checkout -- structure.md` and redo this step.

- [ ] **Step 4: Run the FULL test suite.**

  Run tests: `test_sim` (scheme `Glutt`) — expected: PASS, entire suite green, including all 14 Polly suites added by Tasks 1–16:
  `PollyIconAssetTests`, `CookPlanTests`, `PollyMemoryStoreTests`, `PollyTokenServiceTests`, `RealtimeEventCodecTests`, `RealtimeTransportTests`, `PCMTests`, `WatchModeSchedulerTests`, `PollyToolRegistryTests`, `PollyPromptBuilderTests`, `CookPlanCompilerTests`, `PollySessionControllerTests`, `PollyMemoryExtractorTests`, `PollyRouterTests` —
  plus all pre-existing suites (`AskGluttTests`, `DiscoverFeedViewModelTests`, `DiscoverSaverTests`, `DiscoverServiceTests`, `DiscoverVideoTests`, `GluttTests`, `HeadlineWordStyleTests`, `ImportInboxDrainerTests`, `ImportInboxTests`, `ImportPipelineTests`, `MacroBreakdownTests`, `OnboardingStateTests`, `PlateCardDecodeTests`, `PlatesDeckFilterTests`, `PlatesFeedViewModelTests`, `PlatesSaverTests`, `PlatesSeedDeckTests`, `PlatesServiceTests`, `PlatesStreakTests`, `RecipeFactoryMacroTests`, `RecipeFactoryTests`, `RecipeImageBackfillTests`, `RouterImportNavigationTests`, `ShareImportViewModelTests`, `TutorialFlowModelTests`, `YouTubeEmbedTests`).
  Any failure: stop, fix with superpowers:systematic-debugging, re-run until green. Do not proceed to Step 5 on a red suite.

- [ ] **Step 5: Simulator pass 1 — the Polly tab renders.**

  1. If not already done this session, call `session_show_defaults`; if project/scheme/simulator are unset, use `discover_projs` / `list_schemes` / `list_sims` then `session_set_defaults` (project `Glutt.xcodeproj`, scheme `Glutt`, an iPhone iOS 17+ simulator).
  2. Build & run: `build_run_sim` — expected: succeeds, app launches on the simulator.
  3. `stop_app_sim`, then `launch_app_sim` with args `["-tab", "polly"]` — `Router.init()` (Glutt/App/Router.swift lines 104–110) maps `-tab polly` through `AppTab(rawValue:)` to `selectedTab = .polly`; no new hook code is needed.
  4. `screenshot` → save as `/Users/omarlahmimi/Documents/Glutt/docs/superpowers/verify-screenshots/polly-tab.png`.
  Expected: the Polly tab is selected in the bottom bar (chef-hat glyph active) and `PollyTabView` renders — the "Polly" header with the "Your live cooking chef" subtitle, the "What Polly knows" memory card, and the "Cook something together" saved-recipe picker (exact strings from Task 16 Step 6). If this simulator build has `LLMClient.isConfigured == false`, the tab must instead show the setup card (that is the designed degraded state — note which state was captured; a blank screen or the Today tab is a FAIL).

- [ ] **Step 6: Simulator pass 2 — recipe detail shows BOTH cook buttons.**

  1. `stop_app_sim`, then `launch_app_sim` with args `["-tab", "recipes"]`.
  2. `snapshot_ui`, tap the first recipe card in the Recipes list (Debug builds seed sample data, so at least one recipe exists).
  3. `screenshot` → save as `/Users/omarlahmimi/Documents/Glutt/docs/superpowers/verify-screenshots/polly-recipe-detail-cook-buttons.png`.
  Expected: the bottom cook bar shows the new "Cook with Polly" button AND the classic "Cook" button side by side. (If `LLMClient.isConfigured == false` on this build, "Cook with Polly" is hidden by design — capture the classic-only bar, and record in the task summary that the Polly button was verified hidden, matching the degradation ladder.)

- [ ] **Step 7: Degraded path — the classic Cook button still opens `CookModeView`, untouched.**

  1. From the recipe detail of Step 6: `snapshot_ui`, tap the classic "Cook" button (the `Label("Cook", systemImage: "frying.pan")` bar button).
  2. If the pantry is missing ingredients, `PreCookChecklistView` appears as a sheet first — `snapshot_ui`, tap its "Cook anyway" button (its completion sets `isCooking = true`).
  3. `snapshot_ui` + `screenshot` → save as `/Users/omarlahmimi/Documents/Glutt/docs/superpowers/verify-screenshots/polly-classic-cook-mode.png`.
  Expected: the classic full-screen `CookModeView` is presented (step-by-step cook UI with its own timers) — no Polly orb, no camera preview, no Polly session UI. This proves the restyle golden rule held: the no-AI cook path is byte-for-byte the pre-Polly flow (`RecipeDetailView.swift` lines 53–57 were never modified by this plan).
  4. `stop_app_sim`.

- [ ] **Step 8: Correct the approved spec — four facts the implementation overtook.**

  Edit `/Users/omarlahmimi/Documents/Glutt/docs/superpowers/specs/2026-07-02-polly-live-chef-design.md` with exactly three Edits (the third fixes two facts that share one sentence). Line anchors are from the current file.

  Edit 1 — entry-points table row (line 25): Polly sits third, six tabs total. Before (exact):
  ```markdown
  | Entry points | New **6th bottom tab "Polly"** + **Cook with Polly** button on recipe detail |
  ```
  After:
  ```markdown
  | Entry points | A new **Polly** bottom tab (third position, six tabs total) + **Cook with Polly** button on recipe detail |
  ```

  Edit 2 — session-token payload field name (`replace_all: true`; the string occurs exactly twice, lines 77 and 128 — both must change). Before (exact):
  ```
  {clientSecret, expiresAt, model, voice}
  ```
  After:
  ```
  {value, expiresAt, model, voice}
  ```

  Edit 3 — cost knobs + max session length (one sentence spanning lines 168–169; corrects both the knob list — server VAD already discards silent mic audio, so idle-mic policy is not a knob — and the session cap, since OpenAI caps realtime sessions at 60 min). Before (exact, spans two lines):
  ```markdown
  watch mode ≈ **$0.50–$2.00/session**. Knobs (constants in `PollyConfig`): watch-mode frame interval
  (10 s), frame size (1024 px), idle-mic policy, max session length (90 min hard stop).
  ```
  After:
  ```markdown
  watch mode ≈ **$0.50–$2.00/session**. The watch-frame interval (10 s) and image size (1024 px) are
  the knobs (constants in `PollyConfig`; server VAD already discards silent mic audio), plus max
  session length (52 min — OpenAI caps realtime sessions at 60).
  ```

  Verify nothing else changed: `git -C /Users/omarlahmimi/Documents/Glutt diff --stat docs/superpowers/specs/2026-07-02-polly-live-chef-design.md` — expected: one file, ~5 insertions / ~4 deletions.

- [ ] **Step 9: Commit, then prove the tree is clean.**

  ```bash
  git -C /Users/omarlahmimi/Documents/Glutt add product.md README.md structure.md docs/superpowers/specs/2026-07-02-polly-live-chef-design.md
  git -C /Users/omarlahmimi/Documents/Glutt commit -m "docs(polly): amend navigation contract and feature docs for the Polly tab

  Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0118kSFcUYXUo6i8hzgTGEd9"
  ```

  Then verify the tree:
  ```bash
  git -C /Users/omarlahmimi/Documents/Glutt status --porcelain
  ```
  Expected: NO modified (` M`), staged, or deleted entries remain — every file this plan created or touched must be committed by now (if anything Polly-related shows up here, a previous task's commit was missed: stop and commit it under that task's message before finishing). The only acceptable output lines are `??` untracked entries that predate this plan on the branch (`CLAUDE.md`, `design_handoff_glutt_redesign/`, `docs/superpowers/verify-screenshots/` — the Step 5–7 screenshots live inside that last pre-existing untracked folder on purpose, so they don't dirty the tracked tree). Confirm the commit landed with:
  ```bash
  git -C /Users/omarlahmimi/Documents/Glutt log --oneline -1
  ```
  Expected: `docs(polly): amend navigation contract and feature docs for the Polly tab`.

---

