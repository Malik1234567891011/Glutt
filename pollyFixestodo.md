# Polly conversational follow-up — task breakdown

**Goal:** `"Polly"` starts a conversation, not one sentence. Wake-word once → natural multi-turn → quiet return to dormant.

**Root cause today:** Binary `dormant`/`listening` + fixed **3s** dormancy timer that cancels on speech but only re-arms on `responseDone`. Feels like Polly “stopped listening.” Barge-in is too eager on raw sound. No client conversational gate — once unmuted, everything hits the model.

**North star (one line):** Knock on the chef’s shoulder to begin a conversation — not a verbal button before every sentence.

---

## Phase 0 — Instrument & baseline (do first)

### 0.1 Structured voice events
- [x] Log privacy-safe events via `PollyVoiceEvent` + `PollyDebugLog.event` (wake, follow-up accept/reject, barge, session closed, recoverable, …)
- [x] Track timestamps: `lastWakeWordAt`, `lastUserSpeechStartedAt`, `lastUserTurnCommittedAt`, `lastAssistantSpeechEndedAt`, `followUpDeadline`, `lastValidInteractionAt`
- [x] Dump path (`PollyDebugLog`) — typed `evt=` reason codes
- [ ] Aggregate metrics dashboard / export (post-launch)

### 0.2 Metrics to watch
- [ ] Derive from `evt=` dumps: repeat-Polly %, false-response, false-interrupt, tap reopen, turns/session, explicit vs timeout
- [ ] Wire product analytics later (privacy-safe)

### 0.3 Kitchen test corpus
- [ ] Alone / two people / TV / music / exhaust / sink / sizzle
- [ ] Phone speaker + BT earbuds + phone far away + facing away
- [ ] Replay corpus after every voice change

---

## Phase 1 — Launch-critical (START HERE)

### 1.1 Explicit conversation states (code-owned, not prompt-owned)
- [x] Spec states: `DORMANT` · `LISTENING` · `SPEAKING` · `FOLLOW_UP_WINDOW` (+ expected-answer)
- [x] Expand `ListeningMode` beyond binary: `dormant` · `listening` · `followUp` (+ `expectsAnswer`)
- [x] Own in client: wake, session active, follow-up timeout, VAD handoff, addressee gate, interruption eligibility, ack suppression, expected-answer, explicit close
- [x] Model owns: cooking advice / spoken replies — only after gate commits (`create_response: false`)

**Suggested internal phases:**
`dormant` → `wakeDetected` → `listeningForInitialTurn` → `processingTurn` → `assistantSpeaking` → `possibleBargeIn` → `followUpListening` → `expectedAnswerListening` → `closingSession`

### 1.2 Follow-up window (Alexa-style)
- [x] Replace fixed 3s one-shot sleep with **activity-based** follow-up (~**7s** after answers; **15s** after wake)
- [x] On user speech start during window: **extend** deadline (`noteUserActivity`)
- [x] After every genuine Polly answer: **reopen** follow-up window (after audio drains)
- [x] If Polly asked a question: enter **expected-answer** mode (~14s)
- [x] No arbitrary max turn count while conversation is flowing
- [x] Close on: silence timeout · explicit end · several uncertain rejects (4+)
- [x] Close on: leave cook screen · audio session interrupt · idle max (45s)
- [x] Mic start failure logged as `audio.mic_lost`

### 1.3 Conversational gate (before main model answers)
Classify each transcript (fast rules first, not an LLM round-trip):

| Class | Action |
|---|---|
| `directFollowUp` | Commit + respond |
| `acknowledgment` | No spoken reply; UI can flash “got it”; soft 2–3s then close if quiet |
| `background` | Ignore; keep/shorten remaining deadline |
| `selfTalk` | Ignore |
| `uncertain` | Prefer silence; optional tap-to-recover chip |
| `explicitEnd` | Close session immediately |

Signals for the gate:
- [x] Polly spoke within last 8–12s
- [x] Polly’s last line was a question (awaiting answer)
- [x] Utterance has question/command shape (`Should I`, `Can I`, `How long`, `Wait`, `No I meant`…)
- [x] Refers to active topic (`it`, `that`, `then`, recipe/step words)
- [x] Connected to current step title / ingredients
- [ ] ASR confidence
- [ ] (Later) proximity / voice similarity / multi-speaker

**Implemented:** `Glutt/Services/Polly/ConversationalGate.swift` + wired in `PollySessionController.handleGatedTranscript`.

### 1.4 Acknowledgments & “Okay”
- [x] “okay / perfect / got it / thanks / alright / yeah” after an *instruction* → **no** spoken reply (delete item)
- [x] Same words after Polly **asked a question** → treat as answer (expected-answer mode)
- [x] Soft UI “Got it” flash; no beep

### 1.5 Barge-in (two-stage, not raw VAD)
- [x] Keep mic open with AEC while Polly speaks (already `.playAndRecord` + `.videoChat` + VPIO)
- [x] Do **not** cancel on pan clank / sizzle / short noise (`interrupt_response: false`)
- [x] Stage 1: VAD marks `bargeInCandidate` only
- [x] Stage 2: gate / clear interrupt phrases cancel + truncate + `response.cancel` + answer
- [x] Stricter RMS (`bargeInSpeakingRMSFloor` 0.10) + sustained 280ms while speaking
- [x] On valid interrupt: cancel playback, truncate at playhead, commit user turn, answer
- [x] Explicit `response.cancel` on gated barge-in
- [ ] Retune floors with kitchen corpus

### 1.6 Echo / audio architecture
- [x] AEC path unchanged (still voice-chat session)
- [x] Sustained + higher floor while speaking reduces self-trigger risk
- [x] Full duplex: she can speak while mic stays eligible for *controlled* barge-in
- [ ] Tune `bargeInRMSFloor` / onset gate with kitchen corpus

### 1.7 Turn detection
- [x] Keep `semantic_vad` with conservative eagerness (`low`) + client-owned create/interrupt
- [x] Unfinished endings (`and`, `because`, `uh`, `wait`, …) hold ~750ms before commit
- [ ] Tune hold / eagerness with kitchen corpus

### 1.8 UI state clarity
- [x] Pill: sleeping · Listening · Still with you… · Your turn… · Thinking… · Polly is talking
- [x] Soft follow-up indicator (“Still with you…”) after she answers
- [x] Tap pill opens or **extends** conversation without wake word
- [x] “Meant Polly?” recoverable chip for uncertain/background rejects
- [x] Soft haptic on session close (no beep)

### 1.9 Explicit end phrases
- [x] “stop listening”, “that’s all”, “thanks Polly”, “go away”, … → close to dormant
- [x] Distinct from hang-up / end cook session

### 1.10 Launch acceptance criteria
- [x] Code path: say “Polly” once → multi-turn without repeating name
- [x] ~7s follow-up after each answer; extends when user talks
- [x] Expected-answer stays open longer when she asked a question
- [x] Simple acks suppressed
- [x] Require “Polly” again only after session visibly closes
- [x] AEC + voice processing on
- [x] Raw sound does not auto-interrupt
- [x] Clear UI states
- [x] Explicit endings work
- [x] Every accept/reject logged with reason
- [ ] Device kitchen soak-test (human)

---

## Phase 2 — Immediately after launch

### 2.1 Smarter gate
- [ ] Small on-device / proxy classifier for direct-follow-up vs background
- [ ] Context features: active step, last Polly utterance, recipe tokens
- [ ] Per-environment threshold packs: quiet / cooking noise / music / multi-speaker

### 2.2 Stronger barge-in
- [ ] Buffer-first interrupt (don’t cancel until confidence crosses threshold)
- [ ] Playback position sync hardened
- [ ] False-interrupt regression tests on corpus

### 2.3 Identity / proximity (opt-in)
- [ ] Voice similarity to wake-word speaker where consented
- [ ] Loudness / distance heuristics
- [ ] Personalize thresholds per kitchen over time

### 2.4 Semantic VAD tuning
- [ ] A/B eagerness + silence hypotheses on kitchen corpus
- [ ] Unfinished-utterance delay rules

---

## Phase 3 — Polish & product

### 3.1 Expected-answer UX
- [x] Longer window + lower gate threshold when last Polly message had `?`
- [x] “Yeah” meaningful when expecting answer; ack otherwise

### 3.2 Recovery affordances
- [x] Missed-you chip: tap to force-commit last rejected transcript
- [x] Soft haptic on session close (no earcon beep)

### 3.3 Docs & prompts
- [x] Shrink prompt “only answer when addressed” — client gate owns rejection
- [x] Rejected turns deleted via `conversation.item.delete` (not left as user messages)

---

## Implementation map (code)

| Area | Primary files |
|---|---|
| State machine / timers | `Glutt/Features/Polly/PollySessionController.swift` |
| Config knobs | `Glutt/Services/Polly/PollyConfig.swift` |
| Wake word | `Glutt/Services/Polly/WakeWordListener.swift` |
| Audio / AEC / barge-in floor | `Glutt/Services/Polly/PollyAudioEngine.swift` |
| Realtime VAD / cancel | `Glutt/Services/Polly/RealtimeEvent.swift` |
| Conversational gate (new) | `Glutt/Services/Polly/ConversationalGate.swift` |
| Prompt soft rules | `Glutt/Services/Polly/PollyPromptBuilder.swift` |
| UI pill / follow-up chrome | `Glutt/Features/Polly/PollySessionView.swift` |
| Tests | `GluttTests/PollySessionControllerTests.swift`, `WakeWordMatcherTests.swift`, new `ConversationalGateTests.swift` |

---

## Current constants to replace

| Knob | Today | Launch target |
|---|---|---|
| `followUpWindowSeconds` | **3** | **~7** activity-based |
| Expected-answer window | n/a | **~12–15s** |
| Ack grace after ack | n/a | **~2–3s** then dormant |
| `semantic_vad` eagerness | `low` | keep `low`, retune with corpus |
| Barge-in | speechStarted → interrupt immediately | two-stage + stricter while speaking |

---

## Decision flow (launch)

**After Polly finishes speaking**
1. Enter `followUpListening`
2. Deadline ≈ now + 7s
3. Speech starts → suspend deadline; wait for end-of-turn
4. Run conversational gate
5. Direct follow-up → respond → reopen window  
   Ack → no speak, +2–3s then close if quiet  
   Background → ignore  
   Uncertain → silence (+ optional chip)  
   Explicit end → dormant

**While Polly is speaking**
1. Mic + AEC on
2. Buffer speech; don’t cancel on noise
3. Clear interrupt / high addressee confidence → cancel + listen
4. Else discard as background; she continues

---

## Status

- [x] Spec captured in this file
- [x] Phase 1 launch-critical code landed
- [x] Phase 0 structured `evt=` logging landed
- [ ] Phase 2+ after kitchen soak + metrics
- [ ] Device kitchen soak-test (human)
