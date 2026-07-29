# PollyNewGuide

How Polly’s live cook voice works **now** — after the conversational rework (wake → multi-turn → quiet dormant), the client-owned gate, and the Tools / Prep plan split.

This is the working guide for the **shipped** stack (WebSocket + custom `AVAudioEngine` + on-device wake). Older plans in `docs/plan-polly-v2-voice.md` describe a possible WebRTC future; don’t confuse that with production.

---

## One-line north star

Say **“Polly” once** to start a conversation — not before every sentence. She stays with you through follow-ups, then goes quiet. Prefer **false silence** over interrupting kitchen chatter.

Knock on the chef’s shoulder → talk → she answers → you can keep talking without the name → silence / “thanks Polly” → dormant again.

---

## Why we reworked it

### What broke

| Old behavior | Felt like |
|---|---|
| Binary `dormant` / `listening` + fixed ~3s sleep after she spoke | “She stopped listening” |
| Wake-only mic with no follow-up | Had to say “Polly” every turn |
| Open mic to the model with no addressee filter | Background chatter / TV / self-talk became answers |
| Eager barge-in on raw sound | Pan clanks cut her mid-sentence |
| Server auto-`create_response` | Client couldn’t decide *whether* to answer |

### What we own now

**Client owns** when the mic is open, when a turn becomes a response, barge-in, follow-up timers, and “is this even for Polly?”

**Model owns** cooking advice and spoken words — **only after** the gate commits a user turn.

Realtime session config (`RealtimeEvent.swift`):

- `turn_detection.type = semantic_vad`
- `create_response: false` — we call `response.create` ourselves
- `interrupt_response: false` — we cancel playback ourselves when barge-in is real

---

## Architecture (who does what)

```
┌─────────────────────────────────────────────────────────────┐
│ PollySessionController (session brain)                      │
│  · ListeningMode: dormant → listening → followUp            │
│  · follow-up deadlines, expectsAnswer, barge candidates     │
│  · commits turns → transport.send(.responseCreate)          │
├──────────────┬──────────────┬──────────────┬────────────────┤
│ WakeWord     │ Conversational│ PollyAudio  │ Tool registry  │
│ Listener     │ Gate          │ Engine      │ + CookPlan     │
│ (on-device    │ (classify     │ (AEC, RMS   │ (steps,        │
│  SFSpeech)   │  transcript)  │  floors,    │  checklists,   │
│              │               │  playback)  │  timers)       │
└──────────────┴──────────────┴──────────────┴────────────────┘
         │                │
         ▼                ▼
   OpenAI Realtime   PollyDebugLog / PollyVoiceEvent
   (gpt-realtime-2.1, voice marin)
```

### Key files

| File | Role |
|---|---|
| `Glutt/Features/Polly/PollySessionController.swift` | Session state machine |
| `Glutt/Services/Polly/ConversationalGate.swift` | Addressee / intent before speak |
| `Glutt/Services/Polly/PollyConfig.swift` | All timing / RMS knobs |
| `Glutt/Services/Polly/WakeWordListener.swift` | On-device “Polly” (+ mishears) |
| `Glutt/Services/Polly/PollyAudioEngine.swift` | Mic, AEC (VPIO), playback, RMS gates |
| `Glutt/Services/Polly/RealtimeEvent.swift` | WS events; VAD create/interrupt off |
| `Glutt/Services/Polly/PollyPromptBuilder.swift` | System prompt for the cook |
| `Glutt/Services/Polly/CookPlanCompiler.swift` / `CookPlan.swift` | Steps + Tools/Prep |
| `Glutt/Services/Polly/PollyVoiceEvent.swift` | Structured `evt=` debug lines |
| `Glutt/Features/Polly/PollySessionView.swift` | UI pills / captions |

Tests: `ConversationalGateTests`, `PollySessionControllerTests`, plus tool/prompt suites.

---

## Listening modes

```
dormant ──"Polly" / pill tap──► listening ──she answers──► followUp
   ▲                              │                         │
   │                              │                         │ silence / explicit end
   └──────── timeout / rejects / “thanks Polly” / leave cook ┘
```

| Mode | Mic → Realtime? | Wake word? | Meaning |
|---|---|---|---|
| **dormant** | No (muted) | Yes (on-device) | Quiet; only listening for her name |
| **listening** | Yes | — | Engaged turn (after wake or mid-chat) |
| **followUp** | Yes | — | Soft window after she spoke — no name needed |

Also:

- **`expectsAnswer`** — her last line asked a question; short “yeah” / “no” count as real turns; window is longer (~14s).
- **`isHardMuted`** — mic button; kills wake *and* engagement until unmuted.
- **Tap the state pill** — manual reopen / extend without saying “Polly” (also the fallback when Speech auth / simulator has no wake word).

---

## Timers (`PollyConfig`)

| Knob | Default | Purpose |
|---|---|---|
| `initialListenWindowSeconds` | **15s** | After wake — time to form the first ask |
| `followUpWindowSeconds` | **7s** | After a normal answer |
| `expectedAnswerWindowSeconds` | **14s** | After she asked something |
| `acknowledgmentGraceSeconds` | **2.5s** | After bare “okay / thanks” — linger then quiet |
| `maxEngagedIdleSeconds` | **45s** | Absolute idle while engaged → close |
| `unfinishedTurnHoldMs` | **750ms** | Hold if transcript ends in “and” / “uh” / … |
| `onsetCaptureGateSeconds` | **1.0s** | Mute mic at *start* of her utterance (AEC adapt) |
| `greetingMicHoldSeconds` | **2.5s** | Hold mic around opening greeting |
| `bargeInSpeakingRMSFloor` | **0.10** | While she talks — clanks stay under this |
| `bargeInSustainedMs` | **280ms** | Must stay loud that long to count as barge-in |

**Activity-based follow-up:** when the user starts speaking, `noteUserActivity()` **extends** the deadline (never shrinks it). Closing waits on `awaitingTranscript` so we don’t go dormant while ASR is still in flight. Late transcripts after a race-to-dormant can briefly re-wake so we don’t drop “tools are on the counter.”

Close reasons: silence timeout · explicit end phrases · ~4 uncertain/background rejects · leave cook screen · audio interrupt · max idle · session time cap (~52 min, wrap-up from ~47).

---

## Wake word

- On-device `SFSpeechRecognizer` (`requiresOnDeviceRecognition` when supported).
- Matcher accepts **Polly** plus common mishears (`paula`, `poly`, `paulie`, …) — see `WakeWordMatcher` / `nameMishears`.
- Fed from the **same** mic tap as Realtime (`PollyAudioEngine`); while dormant, Realtime input is muted but the wake listener still hears.
- Each return to dormant **restarts** the recognition segment so the *next* “Polly” wakes (running transcripts don’t grow forever).
- Saying **only** her name while already engaged → `nameOnly`: extend listen, don’t speak, don’t count as a reject.

---

## Conversational gate

Every finished user transcript hits `ConversationalGate.classify` **before** we ask the model to speak.

| Decision | What happens |
|---|---|
| `directFollowUp` | Commit turn → `response.create` |
| `acknowledgment` | Delete item; soft “Got it”; short grace; no spoken reply |
| `nameOnly` | Extend window; no speak |
| `explicitEnd` | Immediate dormant (“that’s all”, “thanks Polly”, “stop listening”, …) |
| `background` / `selfTalk` / `uncertain` | Ignore (delete item); prefer silence |

### Context the gate uses

- `expectsAnswer` — she asked a question
- `pollySpokeRecently` — session still warm
- `onSetupStep` — current step is Tools or Prep (readiness phrases are for her)
- `topicWords` — recipe / step / timer nouns

### What counts as “for Polly”

- Cook progress / setup: “tools are on the counter”, “board is ready”, “what’s left”, “I finished cutting…”
- Questions / commands that look **cook-related** (“Should I flip…”, “how long…”, prep/recipe nouns)
- Continuity right after she spoke (“what about the sauce then”)
- Short answers when `expectsAnswer`

### What should stay silent

- Bare acks after an *instruction* (“okay”, “thank you”) — not after a *question*
- Off-topic (“Why is the sky blue?”) — even with `?`
- Long side chatter with no kitchen overlap
- Self-talk (“let me see…”, measuring aloud)

### Important implementation note (apostrophes)

Normalize **deletes** apostrophes *before* stripping other punctuation so `"that's all"` → `thats all` (matches explicit end) and `"what's left"` → `whats left`.

A raw-string pattern like `#"\u{2019}"#` does **not** expand in Swift — that bug turned `"that's"` into `"that s"`, broke stop phrases, and made continuity falsely fire. Fixed in `ConversationalGate.normalize`. Keep phrase lists apostrophe-free.

### “Meant Polly?” chip — removed

We briefly showed a tappable recovery chip when the gate rejected uncertain speech. That was a **bandaid for a bad gate** (tools-ready / “okay thank you” wrongly rejected). Chip path is gone; fix the classifier instead. Event cases `ui.recoverable_*` may still exist for old dumps — don’t reintroduce the UX without a strong reason.

---

## Barge-in (two-stage)

While Polly speaks, the mic stays open with **AEC** (voice processing / VPIO on `.playAndRecord` + `.videoChat`).

1. **Candidate:** server VAD / sustained loud mic marks `bargeInCandidate` — does **not** cancel her yet.
2. **Accept:** gate says `directFollowUp` **or** clear interrupt phrase (“Polly wait”, “stop”, “hold on”, …) → cancel playback, truncate at playhead, `response.cancel`, commit user turn, answer.

Raw clanks under the speaking RMS floor / shorter than `bargeInSustainedMs` should not cut her off.

---

## Turn assembly

1. User speech → Realtime commits audio → ASR transcript arrives.
2. If `looksUnfinished` (ends with and / because / uh / …) → hold ~750ms for a continuation.
3. Gate classifies.
4. On accept → `turn.committed` → `response.create` (tools allowed except greeting, which is speech-only).
5. She may call tools (`get_current_step`, `check_step_actions`, `mark_step_done`, timers, pantry, …) then speak.
6. When her audio drains → `assistant.speech_end` → re-arm follow-up (longer if she asked a question).

Opening greeting uses **speech-only** (`tool_choice: none`) so she doesn’t tool-call before saying hello.

---

## Cook plan: Tools + Prep (not one mega mise)

Setup used to dump tools + spice measuring + knife work into one huge checklist. That’s wrong for cooking flow.

**Now** (when applicable):

1. **Tools** (`id: tools`) — grab gear only  
2. **Prep** (`id: prep`) — board work only (dice / mince / pat dry)  
3. Then heat / cook steps  

Spices / salt / oil measuring stay **at cook time**, not in Prep. `CookPlan.ensuringLeadingPrep()` rebuilds Tools → Prep; compiler + Polly prompts teach that. Gate treats setup-complete phrases specially when `onSetupStep` is true.

---

## UI (what the cook sees)

| Pill / copy | When |
|---|---|
| Sleeping / quiet | `dormant` |
| Listening | Engaged, hearing you |
| Still with you… | `followUp` |
| Thinking… | Waiting on `response.create` / tools |
| Polly is talking | Playback active |
| Got it | Soft flash after suppressed ack |

Large **Polly caption** = her last line (doesn’t get overwritten by your ASR). Live on-device transcript can show while listening. Mic button = hard mute. Camera / watch mode still exist in the controller but are secondary to voice reliability.

Long-press debug still dumps `PollyDebugLog` (structured `evt=` lines).

---

## Debug & events

Privacy-safe structured events (`PollyVoiceEvent`), e.g.:

- `wake.detected` / `wake.manual_reopen`
- `followup.armed` / `.speech` / `.accepted` / `.rejected` / `.timeout` / `.ack` / `.explicit_end`
- `turn.committed` / `turn.unfinished_hold`
- `barge.candidate` / `.accepted` / `.ignored`
- `assistant.speech_start` / `.speech_end`
- `session.closed` (+ reason)
- `audio.interrupted` / `audio.mic_lost`

Read dumps as a timeline: wake → speech → gate decision → commit → her reply → follow-up armed → timeout/dormant.

---

## Session lifecycle (happy path)

1. Cook with Polly → compile / cache `CookPlan` (Tools → Prep → cook).
2. Mint ephemeral Realtime token (model + voice from proxy).
3. Connect WS, `session.update`, start audio engine + AEC, greeting mic hold.
4. Greeting (speech-only) → then **dormant** + wake listening.
5. “Polly” → listening (15s) → cook talks → gate accepts → she answers (maybe tools).
6. Follow-up window → more turns without the name.
7. Quiet timeout or “thanks Polly” → dormant; wake armed again.
8. End session (✕ / tool / time cap) → memory extract, cook log, recap.

---

## Target environment

Phone on the counter with loudspeaker **or** AirPods / Bluetooth headset.

- Built-in: mic + speaker, AEC on (`.videoChat` + voice processing).
- Bluetooth: HFP duplex (`.allowBluetooth`) so AirPods own mic and playback.
  Speaker override is cleared while a BT headset is on the route, and re-applied
  when it disconnects (`PollyAudioSession`).

Locked-screen / background audio is still not a requirement.

---

## Product rules to protect

1. **Client gate before model speak** — never re-enable server auto-respond without a new design.
2. **Prefer false silence** over chatting with the room.
3. **Don’t resurrect “Meant Polly?”** as cover for gate bugs — fix classify / normalize / timers.
4. **Acks ≠ answers** unless she asked a question.
5. **Follow-up extends on speech**; don’t shrink the deadline mid-utterance.
6. **Tools ≠ Prep ≠ cook** — keep setup checklists short.
7. Tune RMS / windows with a real kitchen corpus (alone, two people, TV, sizzle, speakerphone, AirPods) before changing defaults casually.

---

## Related docs

| Doc | What it is |
|---|---|
| `pollyFixestodo.md` | Task checklist that drove this rework (Phase 1 mostly done) |
| `docs/plan-polly-v2-voice.md` | Aspirational WebRTC / never-silent rebuild — **not** current production |
| `docs/plan-redesign-app-and-polly.md` | Broader app + Polly UI redesign notes |

When in doubt, trust **this guide + the code** over older plans.

---

## Quick “is it broken?” checklist

- Saying “Polly” does nothing → Speech auth / hard mute / wake not armed (check `wakeWordAvailable`).
- Must repeat “Polly” every sentence → follow-up not re-arming after `assistant.speech_end`, or timeout too aggressive.
- Answers off-topic / TV → gate too loose (`directFollowUp` / cook-related filter).
- Ignores “tools are on the counter” → setup cues / `onSetupStep` / normalize.
- Cuts herself off → onset gate / speaking RMS / AEC failed to enable.
- “that’s all” doesn’t end → apostrophe normalize / `explicitEndPhrases`.
- Late ASR after timeout → `awaitingTranscript` / late-transcript re-wake path.
