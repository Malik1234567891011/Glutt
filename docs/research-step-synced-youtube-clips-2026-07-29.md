# Research: Step-synced YouTube clips during Polly cooks (2026-07-29)

**Status:** research only — do not implement yet.  
**Audience:** founders comparing approaches (incl. parallel ChatGPT answers).  
**Question:** While Polly coaches a cook, can we show a short, relevant YouTube clip for the *current* CookPlan step (e.g. Beef Wellington → Prep → Gordon doing prep)?

---

## 0. What Glutt already has (code truth)

| Asset | Path / fact | Reuse for this feature |
|---|---|---|
| Discover YouTube search | `vercel-ai-proxy/api/discover/search.js`, `suggested.js` → YouTube Data API `search.list` (100 quota units/call) | Candidate video discovery |
| Embed player | `Glutt/Features/Discover/YouTubePlayerView.swift` + `YouTubeEmbedTests` | Start here for Polly UI player |
| Discover model | `DiscoverVideo` (`videoId`, title, channel, thumb) | Same wire shape for clip candidates |
| Import from YT | `SocialMediaImport` + Scribe when caption thin | Provenance when a *saved* recipe came from a video |
| CookPlan steps | `CookPlan.PlanStep` (`id`, `title`, `instruction`, `kind`, Tools/Prep ids) | Natural join key for clip manifests |
| Polly session UI | `PollySessionView` / controller — mic, captions, checklist, step index | Host surface for optional clip pane |
| Supabase | Auth + `ai_usage` migrations (`supabase/migrations/*`); no recipe/clip tables yet | Right place for **clip manifests**, not for AV bytes |
| Usage / quota awareness | Proxy already logs Discover YouTube calls as `youtube:search.list` | Extend for clip-resolve endpoints |

**Important:** Glutt does **not** currently store per-step video timestamps. Discover embeds whole videos; Polly has no video surface.

---

## 1. Executive recommendation

### Build first (shippable, ambitious-enough)
**DB-backed clip manifests + official YouTube embed with `start`/`end`, default muted, synced to Polly’s current step.**

- Store only: `{ recipe_key / cook_plan_step_id → youtube_video_id, start_s, end_s, confidence, source, reviewed }`.
- Play via YouTube IFrame Player (already used in Discover), **not** by downloading/re-encoding.
- Cold-start content: **curated allowlist** (hand-labeled or partner channels), not “auto-clip every Gordon Ramsay video on earth.”
- Audio policy: **mute by default** so Polly’s voice wins; user can unmute (and mute Polly) if they want the chef audio.
- UI: **collapsed glanceable strip / optional expand** — never a competing full-screen second cook mode on day one.

### Never (or not without YouTube written approval + lawyers)
- Download, cache, clip, or rehost YouTube audiovisual content for offline or “clean” segment files.
- Scrape unofficial chapter APIs as a production dependency.
- Auto-attach random top-search hits to every user-imported recipe without human/partner review (wrong-clip + ToS + brand risk).
- Promise “Gordon for every step of every recipe” as a launch claim.

### Most ambitious *legal* dream path
1. Partner / license a small set of cooking channels (or shoot Glutt’s own demo clips).
2. For those videos only: run **offline** ASR/chapter/caption grounding to propose `(t0,t1)` → human approve → Supabase.
3. At cook time: embed+seek only; Polly stays primary.

That is still “magic” in-product, without becoming a YouTube pirate CDN.

---

## 2. Legal / product constraints matrix

Sources: [YouTube API Services Terms](https://developers.google.com/youtube/terms/api-services-terms-of-service), [Developer Policies](https://developers.google.com/youtube/terms/developer-policies), [Developer Policies Guide](https://developers.google.com/youtube/terms/developer-policies-guide).

| Action | Allowed? | Notes |
|---|---|---|
| Embed official YouTube player in iOS (WKWebView / IFrame API) | **Yes**, if compliant | Must not strip standard player affordances / ads / related-video behavior in ways the policies forbid; reflect “standard experience.” |
| Seek to `start` / stop at `end` via player params / API | **Yes** | Documented player parameters. |
| Store `videoId` + timestamps + titles in Supabase | **Yes** (metadata) | Not AV content. |
| Download / backup / cache / store copies of YT audiovisual content | **No** without prior written YouTube approval | Explicit Developer Policies prohibition. |
| Offline playback of YT content outside YT Premium | **No** | Policies guide: don’t allow download for offline play. |
| Separate/modify audio or video components (extract MP3, re-encode clips) | **No** | Policies guide examples forbid isolating A/V. |
| Background play when app minimized | **No** | Policies guide forbids background play of YT player. |
| Scrape YouTube / Google apps for chapters | **No** | Developer Policies forbid scraping. |
| Search with `videoLicense=creativeCommon` | **Yes** (API) | Narrower corpus; reuse rights still need care — CC ≠ “do anything forever,” but better than random Standard License. |
| Use captions.download for grounding | **API exists**, OAuth / ownership constraints | Caption *list* is metadata; *download* is restricted — not a free-for-all corpus scrape. Treat as partner/owned-video tooling, not mass Gordon mining. |

**Hard wall for the dream:** Auto-clipping Ramsay at scale implies either (a) illegal download/rehost, or (b) embed+seek into someone else’s Standard License video without a relationship — legally greyer for *branding* (“we show Gordon”) even if embed itself is permitted. Product + PR risk is as real as ToS risk.

---

## 3. Architecture options compared

| Option | How it works | Pros | Cons | Verdict |
|---|---|---|---|---|
| **A. Embed + seek (manifest in Supabase)** | Resolve step → `(videoId,t0,t1)` → IFrame `start`/`end` | Legal path; reuses Discover player; Polly-compatible if muted | Needs labeling quality; chapters not in official API; wrong clip kills trust | **Default MVP** |
| **B. Partner / licensed / Glutt-owned clips** | Contract or shoot; still embed YT *or* host own MP4 on CDN | Best brand control; can mute/edit legally if you own | Sales + production cost; slow coverage | **Scale quality path** |
| **C. AI-grounded timestamps on allowlisted videos** | Whisper / multimodal grounding proposes cuts; human approve | Ambitious labeling leverage | Must not download at scale for Standard License; grounding error rate; review bottleneck | **Ops accelerator for B/A allowlist** |
| **D. User-uploaded / recipe-source video** | If recipe imported from YT URL, segment *that* video | Strong provenance (“this is the video you saved”) | Many imports lack clean chapters; still embed-only | **Great for import-sourced cooks** |
| **E. Skip video in Polly** | Photos / diagram / none | Zero legal/UI chaos | Misses the wow | Keep as fallback when no reviewed clip |

**Recommended hybrid:** D when the recipe has a source `youtube` URL; else A from curated Supabase manifests; long-term B for hero dishes; C only as an internal labeling tool on allowlisted content.

---

## 4. Pipeline: Wellington “Prep” → `(videoId, t0, t1)`

### Reality check
YouTube Data API **`videos.list` does not expose chapters** as a first-class part ([videos resource](https://developers.google.com/youtube/v3/docs/videos)). Chapters often live as timestamped lines in the description (creator convention). Official path to “chapters JSON” does not exist; third-party chapter scrapers conflict with anti-scrape policy.

### Practical labeling pipeline (ops)

```
Recipe / CookPlan step
    │
    ├─(1) Candidate video
    │     • recipe.sourceURL if YouTube
    │     • else curated channel allowlist search (proxy, videoEmbeddable=true)
    │     • optional videoLicense=creativeCommon for reuse-safe pool
    │
    ├─(2) Candidate timestamps
    │     • Parse description timestamps (0:00 Prep, 2:15 Sear…) if present
    │     • Caption / ASR alignment (ONLY for allowlisted / licensed / owned)
    │     • Manual scrub in internal tool
    │
    ├─(3) Match step → segment
    │     • Embedding similarity: step.title+instruction ↔ chapter title / caption window
    │     • Heuristics: prep/tools/sear/oven keywords
    │     • Confidence score
    │
    └─(4) Human gate (required for v1)
          • Approve / reject / tweak t0/t1
          • Store reviewed=true in Supabase
```

**Auto-only is not launchable** for quality. Wrong clip while Polly says “dice the mushrooms” and the video shows dessert plating is worse than no video.

### AI grounding (research vs ship)
- **Research/prototype:** multimodal temporal grounding / WhisperX forced alignment against step text — high potential.
- **Ship constraint:** you need a **legal copy** of the audio/video (or caption download rights) to run that offline. That points to partner/owned content, not mass Standard License YouTube.

---

## 5. Supabase data model sketch

Lean into existing Supabase project; new tables (names illustrative):

```sql
-- Stable identity for a dish lineage (seed id, import hash, or recipe UUID sync later)
create table step_clip_videos (
  id uuid primary key default gen_random_uuid(),
  youtube_video_id text not null,
  channel_id text,
  title text,
  license text check (license in ('youtube','creativeCommon','partner','owned')),
  embeddable boolean default true,
  duration_s int,
  created_at timestamptz default now()
);

create table step_clips (
  id uuid primary key default gen_random_uuid(),
  -- Join strategy v1: cook_plan step kind+title template OR seed recipe slug
  recipe_key text not null,          -- e.g. 'seed:beef-wellington' or source video id
  step_key text not null,            -- e.g. 'prep' | 'tools' | 's3' | normalized title slug
  youtube_video_id text not null references step_clip_videos(youtube_video_id),
  start_s int not null check (start_s >= 0),
  end_s int not null check (end_s > start_s),
  confidence real not null default 0,
  source text not null,              -- 'manual' | 'description_chapter' | 'caption_align' | 'partner'
  reviewed boolean not null default false,
  reviewer note text,
  created_at timestamptz default now(),
  unique (recipe_key, step_key, youtube_video_id, start_s)
);

create index on step_clips (recipe_key, step_key) where reviewed = true;
```

**Client resolve:**  
`GET /api/cook/step-clip?recipeKey=&stepKey=` → reviewed row only → `{ videoId, start, end }`.

Do **not** store MP4s in Supabase Storage for YouTube-origin content.

---

## 6. Polly-session UI options (hands-messy cooking)

| Pattern | Description | Pros | Cons |
|---|---|---|---|
| **Glanceable muted loop strip** | ~120–160pt under step card; muted; tap to expand | Polly stays primary; low cognitive load | Small; hard to see fine knife work |
| **Expand sheet / half-sheet** | Tap “Show clip”; pause Polly optional | Explicit opt-in | Extra gesture with messy hands |
| **Side-by-side / split** | Video + Polly chrome | Demo wow | Cramped on iPhone; audio war |
| **PiP / system picture-in-picture** | OS PiP | Familiar | Policies/background constraints; fights cook UI |
| **Audio ducking** | Unmute clip → auto-hard-mute Polly | Clear priority | Complex session state |

**Recommendation:** glanceable **muted** strip default + expand; never autoplay loud YouTube under Polly. Prefer `playsinline=1`, `mute=1` for autoplay friendliness on iOS ([player parameters](https://developers.google.com/youtube/player_parameters)).

Looping a segment: native `loop=1` is awkward for start/end windows; use IFrame API `onStateChange` → `seekTo(start)` pattern (community practice on top of official events API).

**Player policy caution:** Developer Policies Guide says your service must reflect standard YT experience (don’t strip essential controls/ads recklessly). Prefer modest branding tweaks over a fully chrome-less pirate player.

---

## 7. Failure modes

| Failure | Mitigation |
|---|---|
| Wrong clip / wrong moment | `reviewed=true` gate; confidence threshold; easy “Not useful” → suppress |
| No clip for step | Hide strip; zero empty-state guilt |
| Video unembeddable / taken down | `videos.list` status check in resolve; fall back |
| Polly + YT audio fight | Mute default; exclusive audio focus |
| Quota blowups (`search.list` = 100 units) | Cache manifests; prefer known `videoId`; don’t search per step live |
| Chapter scrape dependency dies | Never depend on unofficial chapter APIs in prod |
| Brand claim “Gordon inside Glutt” | Legal/marketing review; prefer “Watch related technique” until partners exist |
| User thinks Glutt hosts the video | UI copy: YouTube logo / “Open on YouTube” |

---

## 8. Phased roadmap

| Phase | Scope | Effort | Risk |
|---|---|---|---|
| **P0 — Prove UI** | Muted embed strip in Polly for 1 seed recipe, hard-coded `(videoId,t0,t1)` | S | Low |
| **P1 — Supabase manifests** | Tables + proxy resolve + 5–10 hero dishes hand-labeled | M | Low–med |
| **P2 — Import-source sync** | If recipe from YT, offer segments from *that* video (description timestamps + manual refine) | M | Med |
| **P3 — Internal labeling tool** | Admin UI: scrubber, chapter parse, approve | M–L | Med |
| **P4 — Allowlisted AI assist** | Caption/ASR grounding for partner/owned only | L | Med–high |
| **P5 — Creator partnerships** | Contracts, co-branded packs | L (biz) | High payoff |

Skip any phase that requires mass download of Standard License YouTube.

---

## 9. Open questions for founders

1. Is the magic “famous chef on this step” or “visual of *this technique* even if unknown creator”?
2. Will you invest in creator deals / original filming, or only public YouTube embeds?
3. For import-from-YouTube recipes: is binding clips to the **source video** enough for v1 wow?
4. Audio: forever Polly-primary, or allow “watch mode” that pauses Polly?
5. Coverage goal: 10 hero dishes perfect vs 50% of library mediocre?
6. App Store narrative: are you comfortable requiring network + YouTube player (no offline clips)?
7. Who reviews labels — founders, contractors, creators?

---

## 10. Sources appendix

| Topic | Primary URL |
|---|---|
| API Terms | https://developers.google.com/youtube/terms/api-services-terms-of-service |
| Developer Policies | https://developers.google.com/youtube/terms/developer-policies |
| Policies guide (download/offline/modify examples) | https://developers.google.com/youtube/terms/developer-policies-guide |
| IFrame player parameters (`start`, `end`, `playsinline`, `mute`, `loop`) | https://developers.google.com/youtube/player_parameters |
| IFrame Player API reference | https://developers.google.com/youtube/iframe_api_reference |
| `search.list` + `videoLicense` | https://developers.google.com/youtube/v3/docs/search/list |
| `videos.list` / video resource (no chapters part) | https://developers.google.com/youtube/v3/docs/videos |
| Captions resource | https://developers.google.com/youtube/v3/docs/captions |
| Glutt Discover proxy notes | `docs/AI-PROXY-SETUP.md` |
| Glutt existing embed | `Glutt/Features/Discover/YouTubePlayerView.swift` |

---

## Bottom line (for ChatGPT bake-off)

**The product idea is right; the naive implementation (“clip Gordon, host MP4s, auto-label every step”) is legally and operationally wrong.**  
The ambitious shippable version is: **Supabase-reviewed timestamp manifests + official muted embeds + Polly-primary UI**, bootstrapped by hand/partner/import-source videos, with AI used as a *labeling assistant on content you’re allowed to process* — not as a YouTube ripping factory.
