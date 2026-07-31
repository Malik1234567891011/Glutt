# Download Plan — Implementation Phases

Source of truth for *what* and *why*: [`donwloadplan.md`](./donwloadplan.md).  
This file is the *when / in what order* plan. If anything here is thin, open the linked section in the source doc — do not invent a smaller system.

**Pilot recipe (Glutt first test):** Eggs Benedict — Gordon Ramsay  
`https://www.youtube.com/watch?v=gBJjRYk0yC0` (`gBJjRYk0yC0`, ~274s).  
Rights assumed cleared per product decision. Expand to the five-recipe set in Phase F after the pilot player works.

**North star** (from source §Final / §25):

> Download and archive the complete video once → analyse once → reuse approved semantic moments across recipes → only materialize separate clip files after a moment proves useful.  
> Promise: *when seeing the technique helps more than reading, Polly can show the exact moment* — not “every step has a video.”

**Architecture split** (source §1):

| Plane | Owns |
| --- | --- |
| **Control (Vercel)** | URL intake, auth, rights check, job create/status, admin review UI, playback-token minting |
| **Media (container worker)** | yt-dlp, FFmpeg/ffprobe, R2 upload, Stream ingest, transcription, scenes/frames, Gemini segmentation |
| **Storage** | Postgres (jobs/metadata/segments/matches/rights), R2 (immutable originals + derivatives), Cloudflare Stream (HLS + clips) |
| **Client** | Native `AVPlayer` + Polly media state machine — **not** YouTube IFrame as the product player |

Scrap / do not extend as the long-term path: YouTube embed start/end as the primary Polly clip system (inconsistency across YT/TikTok/IG). Embed may remain for Discover browsing only until migrated.

---

## Phase map (quick)

| Phase | Name | Goal | Source anchors |
| --- | --- | --- | --- |
| **0** | Foundations & contracts | Schemas, rights, queue, worker skeleton, security baseline | §1–2, §18–19, §21–22 |
| **A** | Acquire & archive | Probe → download master → SHA-256 → private R2 original | §3–4, §20 |
| **B** | Normalize & Stream playback | Mezzanine + analysis proxy → Stream → signed HLS → iOS `AVPlayer` | §5–6, §15 (player only) |
| **C** | Manual clips (Eggs Benedict) | Human-labeled ranges → Level 1/2/3 assets → Polly “Show me” | §10, §13–17, §23 Stage 1–2 |
| **D** | Evidence package | Transcript + scenes + frames (no auto-match yet) | §7 |
| **E** | Auto-segment + review | Gemini candidates → boundary refine → review UI | §8–11, §23 Stage 3 |
| **F** | Step matching library | StepIntent → retrieval/rerank → 5-recipe expansion | §12, §23 Stage 4–5 |
| **G** | Hardening & scale | Dedup, revocation, analytics, ontology growth | §19–22, §23–25 |

Idempotent stage names used across workers (source §19):

```text
ACQUIRE_SOURCE → ARCHIVE_ORIGINAL → NORMALIZE_SOURCE → UPLOAD_PLAYBACK_ASSET
→ TRANSCRIBE → DETECT_SCENES → ANALYSE_VIDEO → REFINE_SEGMENTS
→ REVIEW_SEGMENTS → MATCH_TO_STEPS → MATERIALIZE_CLIPS
```

---

## Phase 0 — Foundations & contracts

**Outcome:** Nothing downloads yet, but every later phase has a place to hang state, rights, and jobs.

### Deliverables

1. **Postgres tables** (full column list in source §18)  
   `source_assets`, `ingestion_jobs`, `transcript_words`, `video_scenes`, `semantic_segments`, `segment_crops`, `clip_assets`, `recipe_step_intents`, `step_segment_matches`  
   Plus a **`rights_records`** table referenced by `source_assets.rights_record_id` (required before any ingest).

2. **`SourceAsset` model** (source §2) — statuses:  
   `queued | probing | downloading | uploaded | normalizing | analysing | review_required | ready | failed`  
   (+ later `revoked` from §22).

3. **Object key convention** (never title-based):

   ```text
   source_assets/{sourceAssetId}/original.<ext>
   source_assets/{sourceAssetId}/normalized.mp4
   source_assets/{sourceAssetId}/analysis-proxy.mp4
   source_assets/{sourceAssetId}/audio.m4a
   source_assets/{sourceAssetId}/metadata.json
   ```

4. **Control-plane API (Vercel only)**  
   - Create ingest job (URL + rightsRecordId) → return `jobId`  
   - Job progress / status  
   - Playback token mint (stub OK until Phase B)  
   - **No** yt-dlp / FFmpeg inside Vercel functions (§1)

5. **Queue + container worker skeleton**  
   Image with: `yt-dlp`, `ffmpeg`, `ffprobe`, upload SDK, AI clients (wired later).  
   Job lease + attempt_count + error_code/details.

6. **Downloader interface** (source §3) — stubs only in Phase 0:

   ```text
   YouTubeDownloader
   TikTokDownloader
   InstagramDownloader
   DirectFileDownloader
   CreatorUploadDownloader
   GenericWebVideoDownloader
   ```

7. **Security baseline** (source §21) — enforce from day one:  
   HTTPS-only, platform/domain allowlist, SSRF / no private IPs, max duration/size/redirects, arg-array spawn (never string-interpolated shell), disposable work dir, keys only on worker.

8. **Removal / revoke contract** (source §22) — API + status = `revoked` must exist even if cascade is stubbed; retrieval always excludes revoked.

### Acceptance

- [ ] Can create a rights record + queued `SourceAsset` for Eggs Benedict URL without downloading.  
- [ ] Worker can claim a no-op job and mark progress.  
- [ ] Vercel has zero media binaries.

### Explicit non-goals

Downloading, Stream, Polly video UI.

---

## Phase A — Acquire & archive (one master per source)

**Outcome:** Rights-cleared URL → immutable original in private R2 + probe metadata. Eggs Benedict is the first real job.

### Deliverables

1. **Stage A — Probe** (`yt-dlp --dump-single-json --skip-download --no-playlist`)  
   Capture: platform ID, title, uploader, duration, thumbnail, subs availability, formats, resolution, fps, playlist?, estimated size (§3).

2. **Reject / manual-review gates**  
   Playlists, live-in-progress, over max duration, unsupported URL, private/access-controlled, over storage ceiling, **missing rights record**.

3. **Stage B — Download master**  
   Cap **1080p**; format selection via `-S "res:1080,vcodec:h264,acodec:aac"`; merge to mp4; write info-json, thumbnail, subs (`en.*,fr.*,es.*`).  
   Do **not** hardcode extension before download. Creator uploads skip yt-dlp → resumable direct upload.

4. **No source-specific tricks in core pipeline** (§3) — adapter failure only when extractor breaks; no DevTools CDN links, no browser automation for every job, no hardcoded credentials.

5. **ARCHIVE_ORIGINAL** (§4)  
   SHA-256 → ffprobe (size, codecs, duration, dimensions, rotation, fps) → multipart upload to private R2 → mark immutable → delete temp only after verified upload.  
   **Why R2 original:** Stream cannot return byte-for-byte original (§4).

6. **Dedup hooks** (§20)  
   Exact: SHA-256. Near-dupe fields stubbed (perceptual hash, frame hashes, audio fingerprint) — full near-dupe policy in Phase G.

### Acceptance

- [ ] Eggs Benedict job reaches `uploaded` with `original_object_key`, `sha256`, `duration_seconds ≈ 274`.  
- [ ] Re-running the same job is idempotent (object exists + checksum match → skip re-download).  
- [ ] Failed probe/download surfaces `error_code` without leaving orphan temp files.

### Pilot note

TikTok/Instagram adapters can remain “probe returns unsupported” until YouTube path is solid — interface must already exist so they plug in without redesign.

---

## Phase B — Normalize & signed Stream playback

**Outcome:** One technical mezzanine + Stream HLS; iOS plays a range with precise start/stop via native player.

### Deliverables

1. **NORMALIZE_SOURCE** (§5)  

   | Spec | Value |
   | --- | --- |
   | Container | MP4 |
   | Video | H.264, yuv420p |
   | Audio | AAC 48 kHz stereo |
   | Max res | 1080p |
   | FPS | 30 constant |
   | Fast start | yes |
   | Aspect | **preserve** (no stretch portrait→landscape) |

2. **Analysis proxy** (§5) — ~540p, 15 fps, low bitrate, AAC mono — for AI/frame work later.

3. **UPLOAD_PLAYBACK_ASSET** (§6)  
   Upload normalized → R2 → Stream ingest via temporary signed URL → wait `state = ready` → store `PlaybackAsset` (`streamUid`, HLS URL, dims, duration).

4. **Signed playback**  
   Glutt API mints short-lived tokens; app never holds long-lived Stream keys.

5. **iOS**  
   Replace Polly’s YouTube IFrame clip path for this feature with **`AVPlayer` + HLS** (§15). Prove seek-to-start / stop-at-end accuracy (re-encode cuts later; virtual range OK here).

### Acceptance

- [ ] Eggs Benedict normalized + Stream-ready.  
- [ ] Simulator/device plays a hard-coded range (e.g. ham fry ~145–201s) via signed HLS with no YouTube chrome/ads.  
- [ ] Portrait and landscape fixtures both keep correct aspect.

### Explicit non-goals

Auto-segmentation, transcription, review UI (stubs OK).

---

## Phase C — Manual clips + Polly interaction (prove the product)

**Outcome:** Eggs Benedict cooks with 4–6 **manually reviewed** moments; Polly “Show me” feels instant. This is the product gate before automation.

Aligns with source §23 Stages 1–2 and Days 5–8 of §24 — but **Eggs Benedict first**, then expand.

### Deliverables

1. **Three asset levels** (§13) — do **not** explode into 40 MP4s:

   | Level | What | When |
   | --- | --- | --- |
   | 1 Semantic range | `sourceAssetId + start + end` | Review / cheap storage |
   | 2 Virtual clip | Play master HLS, seek + stop | Testing / rare clips |
   | 3 Materialized clip | Stream clip API **or** FFmpeg re-encode (`-ss` before `-i`, re-encode not stream-copy) | Approved + assigned + real users |

2. **Manual labels for Eggs Benedict** (store as `semantic_segments` with `review_status=approved`)  
   Target useful moments (adjust after watching master; use oracle windows as starting hypotheses, not hardcodes in production code):  
   - Hollandaise emulsion  
   - Parma ham crisp (~145–201)  
   - Muffin toast in fat  
   - Poach / whirlpool  
   - Plate-up (optional)

3. **Presentation derivatives** (§14) for materialized clips  
   - Primary: full-frame ≤1080p  
   - Optional vertical: **manual** crop box only in MVP (`CropTrack` schema ready)  
   - Thumbnail: clear action / hands / target state  
   - Glutt caption = **what to notice**, not full transcript

4. **Review UI minimum** (§10)  
   Player + proposed range + nudge ±1s + set start/end + approve/reject/split + mute default + thumbnail pick.  
   First 100–300 clips: human review (Malik/Omar) — this data becomes the eval set.

5. **Polly runtime** (§15–17)  
   - Step card with thumbnail / “See how…” / duration  
   - Tool / flow: finish sentence → pause realtime → expand clip → prebuffer → play **muted by default** → end → brief Polly note → resume listen  
   - **Hear original audio** control  
   - `PollyMediaState`: idle | preparing | playing | paused | finished  
   - While playing: no source audio into Realtime ASR; no wake on clip saying “Polly”; interrupt/pause; duck/stop if user calls Polly  
   - Selective preload on step enter (+ opportunistic next high-value); cancel on skip; don’t preload whole recipe (§17 billing)

6. **Analytics events** (§23 Stage 2)  
   `clip_offered`, `clip_opened`, `clip_started`, `clip_completed`, `clip_replayed`, `clip_unmuted`, `clip_interrupted`, `clip_helpful_yes/no`, `step_completed_after_clip`, `question_asked_after_clip`, `cook_completed`

### Acceptance

- [ ] Cook Eggs Benedict with Polly; ham (and ≥3 other) clips play natively, muted, interrupt-safe.  
- [ ] “Show me” starts without multi-second spinner on preheated step.  
- [ ] No YouTube IFrame on the Polly clip path for this recipe.  
- [ ] Wrong-clip / bad-boundary bugs logged against review UI, not “fixed” by hardcoding in the app.

### Then expand (still Phase C / early F)

Five-recipe set from §23: beef Wellington, chicken katsu, carbonara, butter chicken, cinnamon rolls — same manual path (~25 clips).

---

## Phase D — Evidence package (automatic, still no auto-attach)

**Outcome:** Every ready source gets a reusable evidence pack for later AI. Source §7.

### Deliverables

1. **Layer 1 — Original metadata**  
   title, description, creator, tags, chapters, captions, platform timestamps, associated recipe URL.

2. **Layer 2 — TRANSCRIBE**  
   Extract `audio.m4a` from normalized → **ElevenLabs Scribe v2** (word-level timestamps, diarization, keyterm prompting).  
   Keyterms from title/description/ingredients/dish/chef/techniques.  
   Store **every** `TranscriptWord` (`text`, `startSeconds`, `endSeconds`, `speakerId?`, `type`).

3. **Layer 3 — DETECT_SCENES**  
   FFmpeg scene-change → `video_scenes` rows.

4. **Layer 4 — Sampled frames**  
   - Coarse: 1 frame / 1–2s whole video  
   - Dense: 4–8 fps around candidate actions (used heavily in Phase E)

### Acceptance

- [ ] Eggs Benedict has word-aligned transcript + scene list + coarse frame index in storage.  
- [ ] Re-run is idempotent per model/tool version.

---

## Phase E — AI segmentation + boundary refine + ontology

**Outcome:** Machine proposes cooking **moments** (not recipe steps); humans approve. Source §8–11, §23 Stage 3.

### Deliverables

1. **ANALYSE_VIDEO** — Gemini on **analysis proxy** + transcript + scenes + metadata (+ known recipe when available).  
   Structured segment JSON as in §8 (`primary_action`, states, tools, visibility scores, warnings, …).  
   Prefer File API for reusable uploads.

2. **Segment length policy**  
   Target 8–20s; allow 5–30s; \>30s → split or human approval.  
   Shape: ~1s setup → action → 1–2s result — not talk/sponsor padding.

3. **REFINE_SEGMENTS** (§9)  
   Expand ±5s → dense frames + words → first visible action → first stable result → snap away from bad cuts → context pad → speech-cut check → `SegmentBoundary` record.

4. **Ontology normalization** (§11)  
   Store reusable concepts (action / object / start→end state / technique / visual question / dish_context) — **not** “Gordon step 3”.  
   Seed action list, state changes, visual questions from §11.

5. **REVIEW_SEGMENTS**  
   Full review UI from §10 wired to AI candidates; approvals feed eval set.

### Acceptance

- [ ] Auto candidates for Eggs Benedict reach review; after human pass, quality ≥ manual Phase C clips on held-out moments.  
- [ ] Model version + confidence stored on every segment.

---

## Phase F — Match to CookPlan + technique library

**Outcome:** Steps get clips via retrieval, with “no clip” as a valid answer. Source §12, §23 Stages 4–5.

### Deliverables

1. **Compile `StepIntent`** per cook step (§12) — actions, ingredients, states, `visualQuestions`, `videoValue` (`none|optional|high|essential`).

2. **Retrieval order**  
   Exact source recipe video → exact dish other video → technique+state → generic technique → **none**.

3. **Scoring**  
   30% action / 20% ingredient / 20% state / 15% technique / 10% visual-question / 5% quality  
   + hard penalties (contradictory ingredient, wrong stage, different technique, result mismatch, mention-not-visible, low quality).

4. **Rerank** with explicit contradiction listing; never force a clip onto every step (§25).

5. **Technique library index** (§23 Stage 4): sear, fold, knead, emulsify, reduce, whip, wrap, score, doneness, roll pastry, …

6. **Auto-attach to arbitrary imports** only after hundreds of reviewed segments (§23 Stage 5).

### Acceptance

- [ ] Eggs Benedict CookPlan steps match approved segments without hardcoded timestamps in app code.  
- [ ] Steps with `videoValue=none` stay clip-free.  
- [ ] Five-recipe suite cooks cleanly; failures go back to review, not silent bad matches.

---

## Phase G — Hardening, dedup, ops, scale

**Outcome:** Safe to run many sources; removal and retries don’t corrupt the library.

### Deliverables

1. **Full idempotency** (§19) — every stage checks object existence, checksum, Stream UID, model version, materialize-once, job lease.

2. **Near-duplicate detection** (§20) — perceptual video hash + frame hashes + audio fingerprint + duration + metadata; relink mappings when higher-quality master arrives (don’t delete semantic history).

3. **Complete revocation cascade** (§22)  
   Disable tokens → remove from search → delete step matches → delete clip assets → delete Stream master → delete R2 derivatives → optional audit-only retain → block re-ingest.

4. **Upload malware scan** for direct creator files (§21).

5. **Ops** — CPU/mem limits, worker timeouts, MIME inspection, filename sanitization, automatic deletion cascades.

6. **Product analytics review** — decide mute-default vs hear-original, exact-dish vs generic, distraction vs help (§23 Stage 2 questions).

7. **Platform adapters** — production TikTok + Instagram + creator upload parity with YouTube path.

### Acceptance

- [ ] Kill worker mid-stage; resume produces one coherent asset.  
- [ ] Revoke Eggs Benedict → app cannot play; re-submit blocked.  
- [ ] Same file via two URLs collapses to one master (exact or near-dupe policy).

---

## Cross-cutting rules (every phase)

1. **Control ≠ media** — never put download/transcode in Vercel (§1).  
2. **Rights before bytes** — no probe/download without `rights_record_id`.  
3. **Archive original forever (until revoke)** — Stream is delivery, not archive (§4).  
4. **Re-encode for accurate clips** — no stream-copy for user-facing boundaries (§13 / FFmpeg docs).  
5. **Muted by default in Polly** — source = visual; Polly = explanation (§15).  
6. **Sparse clips** — essential / target-state only (§25).  
7. **Spawn argv arrays only** (§21).  
8. **Always exclude `revoked`** in retrieval (§22).

---

## Suggested calendar (maps source §24 → these phases)

| Days (indicative) | Phase work |
| --- | --- |
| 1–2 | Phase 0 + Phase A (Eggs Benedict archived) |
| 3–4 | Phase B (Stream + AVPlayer range proof) |
| 5–6 | Phase C manual segments + materialize + review page |
| 7–8 | Phase C Polly media state + show-me + ASR isolation |
| 9–10 | Phase D evidence |
| 11–12 | Phase E auto-segment + refine + review |
| 13–14 | Phase F StepIntent match + cook tests |
| Ongoing | Phase G + TikTok/IG adapters + 5-recipe / library scale |

Compress only after the **Phase C product gate** passes on Eggs Benedict.

---

## Coverage checklist (source § → phase)

| Source section | Topic | Phase(s) |
| --- | --- | --- |
| Opening / glance diagram | Download-once pipeline | All (north star) |
| §1 | Control vs media plane, components | 0 |
| §2 | SourceAsset, key layout | 0, A |
| §3 | Downloaders, probe, download, no tricks | 0, A |
| §4 | Preserve original, R2, why not Stream-only | A |
| §5 | Normalize + analysis proxy | B |
| §6 | Stream ingest, signed playback | B |
| §7 | Evidence layers 1–4 | D |
| §8 | Cooking-moment segmentation | E |
| §9 | Boundary refinement | E |
| §10 | Human review UI | C, E |
| §11 | Ontology / reusable concepts | E, F |
| §12 | StepIntent, retrieval, scoring | F |
| §13 | Asset levels 1–3, materialize | C |
| §14 | Derivatives, crop, thumb, captions | C |
| §15 | Polly UI / muted default | C |
| §16 | PollyMediaState / duplex | C |
| §17 | Preloading | C |
| §18 | Full DB model | 0 (+ fill as stages land) |
| §19 | Idempotent stages | 0, G |
| §20 | Dedup | A (exact), G (near) |
| §21 | Security | 0, G |
| §22 | Content removal | 0 (contract), G (full) |
| §23 | MVP stages 1–5 | C→F |
| §24 | Two-week sequence | Calendar above |
| §25 | Product promise (sparse clips) | C, F |
| Final architecture diagram | End-state topology | All |
| References [1]–[14] | Vendor docs | Cite when implementing that phase |

---

## Out of scope / deferred (called out, not lost)

- Building a custom HLS stack (use Cloudflare Stream) — §1.  
- Auto centre-crop to 9:16 (manual crop MVP; vision tracking later) — §14.  
- Worldwide automated ingest before review loop exists — §23.  
- Forcing a clip on every recipe step — §25.  
- Using Stream as sole archive — forbidden — §4.

---

## First concrete milestone (start coding here)

**M0 → M1:** Phase 0 schemas/API/queue + Phase A Eggs Benedict → object in R2 with checksum.  
**M2:** Phase B signed HLS plays ham window in `AVPlayer` inside Polly (virtual Level 2).  
**M3:** Phase C four approved moments + “Show me” + mute/ASR isolation + analytics.  

Do not start Phase E until M3 feels good in a real cook.

When implementing, re-read the matching `donwloadplan.md` section before writing code for that phase — this file orders work; that file specifies behavior.
