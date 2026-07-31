# mergePick.md — voice rebuild × media/clips merge

**Date:** 2026-07-31  
**Base (kept as trunk):** `origin/main` @ `76bef7c` — co-founder Polly voice rebuild  
**Merged in:** `feat/background-import-clips` (`8d8403a` + `b03c856`) — Supabase clips, pilots, background import  
**Result branch:** `main` (this merge commit)

Principle: **take his voice layer almost entirely**; bring back our media/clip pipeline and only the Polly mic fixes he did not already cover.

---

## What we kept from him (co-founder) — do not regress

| Area | Commits / symbols | Why |
|---|---|---|
| Live cook voice | `76bef7c` and voice-rebuild merge | Her actual voice in the live cook, not briefing-only |
| Chef / Gordon voice picker | `168e0e5` | Product surface we want |
| Echo cancellation in production | `c5e73d6` — `PollyAudioLab.fullDuplex` | Observable AEC; ours never shipped this |
| Audio interruption ownership | `f6ef1ed` | Stops three owners fighting the session |
| Wake-word deaf window (listener) | `15819ab` — `WakeWordListener` restart / availability | Different layer from our WebRTC greeting-hold fix; both needed |
| Unmuted clip stranding mic | `32eb76b` — `micHeldForClipAudio`, `releaseMicAfterClip`, failsafe | Fixes teardown `.idle` never releasing mic — we did not have this |
| `wait_for_user` silence | `fada5df` | Deliberate non-response; must not `responseCreate` after |
| Session mint body | `sessionBody(withReasoning)` in `session.js` | Richer than our inline body; already includes `create_response: false` / `interrupt_response: false` |
| Diagnostics / TTS fallback / latency | `eb35439`, `19893b5`, etc. | Keep his cook UX + observability |
| App Store / chefs flag / docs on main | assorted | Not touched by us; stay |

---

## What we kept from us (media / clips / import)

| Area | Why |
|---|---|
| Supabase media schema `0011` + Storage bucket | Control plane for clips |
| `mediaClips.js` + `/api/media/clips` | Signed playback URLs for devices (no LAN) |
| `mediaIngest.js` enqueue / status / analyze | Background import pipeline |
| `media-worker` sync + `claim:supabase` | HD MP4 materialization |
| Pilot fixtures (Eggs Benedict, Wellington, TikTok scramble) + Wellington window QA | Working content already in Storage |
| `NativeClipService` by `external_id` (no pilots allowlist) | Scale path |
| `MediaIngestClient` + `MediaClipEnqueue` | Fire-and-forget after import |
| Recipe `mediaStatus` / progress fields + detail banner | User sees clipping without blocking cook |
| `forceMicOpenForWake` / `isMicServerGated` | His wake-listener fix ≠ greeting-hold WebRTC gate |
| Quiet-mode unmute ack (`speakClipUnmuteQuietMode`, `requires_spoken_ack`) | Product ask; not in his branch |
| Word-boundary clip matching | Mustard ≠ sear via “seared” |
| Docs: `donwloadplan.md`, `downloadplanPhases.md`, `newDesign.md` | Specs we were building against |

---

## Conflict resolutions (the only two conflicted files)

### 1. `PollySessionController.updateMediaState` (unmuted clip → hard mute)

- **His:** always `micHeldForClipAudio` + hard mute + failsafe when clip unmuted.  
- **Ours:** only hard-mute when `listeningMode == .dormant` (don’t stomp wake).  
- **Pick:** **combine** — use his hold/failsafe machinery **inside** our dormant guard.

### 2. `PollySessionController.responseDone` (tools follow-up)

- **His:** `wait_for_user` early return + bare `responseCreate` (would double-fire with our branch).  
- **Ours:** unmute quiet-mode `responseCreateWithInstructions` vs normal `responseCreate`.  
- **Pick:** `wait_for_user` **first** (his), then unmute ack **or** normal create (ours). **Dropped** his duplicate trailing `responseCreate`.

### 3. `vercel-ai-proxy/api/polly/session.js`

- **Pick: his** `sessionBody(withReasoning)` — already has the VAD flags we added; plus reasoning / text-only path.

---

## Explicitly dropped / not re-applied

| Dropped | Why |
|---|---|
| Our inline `session.js` mint body | Superseded by his `sessionBody` |
| Hard-mute unmuted clips while Listening | Would undo wake; his stranding fix still runs when dormant |
| Replacing his `releaseMicAfterClip` with our simple `setMicMode(open)` | His teardown/idle path is more correct |
| Keeping `NativeClipService.pilots` allowlist as the only gate | We intentionally removed it for the real import path |
| Treating his wake-listener fix as a substitute for `forceMicOpenForWake` | Different bugs; both stay |

---

## Auto-merged (no conflict) — sanity notes

- `RealtimeWebRTCTransport.swift` — both `forceMicOpenForWake` (ours) and full-duplex AEC (his).  
- `PollyPromptBuilder` / `PollyToolRegistry` — his `wait_for_user` + our unmute coaching / clip autoplay rules.  
- `RecipeDetailView` — his chrome + our clip progress banner.  
- `Chefs.swift` — both sides’ Gordon content should coexist; verify if anything unexpected landed.

---

## Ops after merge

1. Deploy `vercel-ai-proxy` (glutt project) so enqueue/analyze/clips match the app.  
2. Keep `media-worker` `.env` + optionally `npm run claim:supabase -- --loop` for HD clips.  
3. Rebuild iOS after `xcodegen generate`.  
4. Smoke: import YouTube recipe → detail banner; Polly wake once; unmute clip → quiet-mode line; Eggs Benedict/Wellington still play native clips.

---

## If something feels wrong

```bash
# Restore point before this merge (co-founder tip only):
git checkout 76bef7c

# Our media-only tip (pre-merge with his voice):
git checkout feat/background-import-clips
```
