
okay we need to donwload videos, dw its safe and legal its okay, downloading videos is the only way were able to have consistency through varaious forms of content so we must do it. write up a plan of how ell do all this downloading in mind, ive sorted the legal stuff

Assuming every source is rights-cleared, **downloading the full source video should become the first stage of the pipeline—not an improvised step performed every time a recipe needs a clip.**

The architecture I would build is:

> **Download once → preserve the master → normalize it → understand it → divide it into semantic moments → match those moments to recipe steps → materialize only the useful clips → deliver them through a consistent Glutt player.**

The biggest correction from the earlier plan is that Glutt now owns a stable media copy. That gives you:

* predictable playback;
* no ads or deleted embeds;
* precise start and end frames;
* consistent volume, resolution and captions;
* the ability to crop or reformat licensed footage;
* fast preloading;
* offline caching later;
* one system for YouTube, TikTok, Instagram and creator uploads.

# The system at a glance

```text
Rights-cleared video URL or uploaded file
                ↓
       Source acquisition worker
                ↓
      Immutable original in storage
                ↓
       Technical normalization
                ↓
 Transcript + frames + scene detection
                ↓
   AI cooking-action segmentation
                ↓
       Human review and correction
                ↓
  Canonical reusable segment database
                ↓
 Recipe-step retrieval and reranking
                ↓
   Native Glutt clip or timestamp range
                ↓
        Polly-controlled playback
```

# 1. Separate the control plane from the media plane

Do **not** download or transcode videos inside your existing Vercel functions.

Vercel should remain the control plane:

* receive the video URL;
* authenticate the request;
* check that permission information exists;
* create an ingestion job;
* return the job ID;
* expose job progress;
* issue playback tokens.

Actual downloading, FFmpeg work and AI processing should happen in a dedicated container worker. Vercel’s writable filesystem is limited to `/tmp` with up to 500 MB, and function packaging and execution limits make it a poor place for multi-gigabyte media processing. ([Vercel][1])

## Recommended components

```text
Next.js/Vercel
    └── API and admin dashboard

Postgres
    └── jobs, metadata, segments, matches, rights records

Queue
    └── ingestion and analysis jobs

Container worker
    ├── yt-dlp
    ├── FFmpeg / ffprobe
    ├── upload client
    └── AI API clients

Cloudflare R2
    └── immutable original files and analysis derivatives

Cloudflare Stream
    └── encoding, HLS delivery, signed playback and finalized clips
```

Cloudflare Stream can accept uploaded files or files hosted at a URL, encode them for adaptive playback and deliver them to native mobile players using HLS. It also supports generating clips from uploaded videos. ([Cloudflare Docs][2])

I would choose this over building your own HLS encoding stack right now.

# 2. Treat every video as a permanent source asset

A submitted URL should produce one stable internal object:

```typescript
interface SourceAsset {
  id: string;

  sourcePlatform:
    | "youtube"
    | "tiktok"
    | "instagram"
    | "creator_upload"
    | "web"
    | "other";

  sourceUrl: string;
  externalId?: string;
  creatorId?: string;

  rightsRecordId: string;

  ingestStatus:
    | "queued"
    | "probing"
    | "downloading"
    | "uploaded"
    | "normalizing"
    | "analysing"
    | "review_required"
    | "ready"
    | "failed";

  originalObjectKey?: string;
  normalizedObjectKey?: string;
  cloudflareStreamUid?: string;

  sourceDurationSeconds?: number;
  sha256?: string;
  perceptualHash?: string;

  title?: string;
  creatorName?: string;
  originalDescription?: string;
  originalPublishedAt?: string;

  createdAt: Date;
}
```

## Rule: never identify the file by its title

Titles change and collide.

Use:

```text
source_assets/{sourceAssetId}/original.<ext>
source_assets/{sourceAssetId}/normalized.mp4
source_assets/{sourceAssetId}/analysis-proxy.mp4
source_assets/{sourceAssetId}/audio.m4a
source_assets/{sourceAssetId}/metadata.json
```

# 3. The acquisition layer

You need a provider interface rather than scattering downloading logic throughout the app.

```typescript
interface SourceDownloader {
  canHandle(url: URL): boolean;

  probe(url: URL): Promise<SourceProbe>;

  download(
    url: URL,
    destinationDirectory: string
  ): Promise<DownloadedSource>;
}
```

Implement:

```text
YouTubeDownloader
TikTokDownloader
InstagramDownloader
DirectFileDownloader
CreatorUploadDownloader
GenericWebVideoDownloader
```

For compatible public URLs, use `yt-dlp` inside the worker. It supports extractor-based downloading, format selection and outputting source metadata as JSON. Its documentation specifically recommends choosing formats intelligently rather than simply requesting a file extension such as `-f mp4`; it can merge separate video and audio streams through FFmpeg. ([GitHub][3])

## Stage A: probe without downloading

First retrieve:

* canonical platform ID;
* title;
* uploader;
* duration;
* thumbnail;
* subtitle availability;
* formats;
* resolution;
* frame rate;
* whether it is a playlist;
* estimated file size.

Conceptually:

```bash
yt-dlp \
  --dump-single-json \
  --skip-download \
  --no-playlist \
  "$SOURCE_URL"
```

Reject or manually review:

* playlists;
* livestreams still in progress;
* videos longer than your configured maximum;
* unsupported URLs;
* private or access-controlled sources;
* files exceeding your storage ceiling;
* missing rights records.

## Stage B: download one full-quality master

For cooking footage, I would initially cap acquisition at **1080p**. Most users will watch a relatively small demonstration inside the cooking UI, and 4K increases download, storage, analysis and processing costs without meaningfully improving most technique clips.

Conceptually:

```bash
yt-dlp \
  --no-playlist \
  -S "res:1080,vcodec:h264,acodec:aac" \
  --merge-output-format mp4 \
  --write-info-json \
  --write-thumbnail \
  --write-subs \
  --write-auto-subs \
  --sub-langs "en.*,fr.*,es.*" \
  -o "/work/$ASSET_ID/source.%(ext)s" \
  "$SOURCE_URL"
```

Do not hardcode the final extension before downloading; let the downloader identify and merge the best compatible formats.

For supplied creator files, skip `yt-dlp` and use resumable direct upload.

## No source-specific tricks in the core pipeline

The downloader must not depend on:

* a human opening DevTools;
* copying temporary CDN links;
* manually renaming files;
* browser automation for every job;
* credentials hardcoded in the worker;
* platform-specific output directory structures.

When an extractor breaks, only its adapter should fail.

# 4. Preserve the exact original before changing anything

Immediately after download:

1. Calculate SHA-256.
2. Run `ffprobe`.
3. Record file size, codecs, duration, dimensions, rotation and frame rate.
4. Upload the untouched file to a private R2 bucket.
5. Mark it immutable at the application level.
6. Delete the temporary worker copy only after the upload is verified.

R2 supports multipart uploads, which is the correct path for large video files. ([Cloudflare Docs][4])

## Why keep the original?

Because later you may need to:

* regenerate clips with different dimensions;
* improve your encoding;
* re-run analysis with better models;
* repair a bad crop;
* extract a higher-quality frame;
* generate French or Spanish captions;
* change the amount of context before and after an action.

Cloudflare Stream does **not** let you retrieve the exact original uploaded file, so Stream should not be your sole archival source. It can generate an encoded downloadable MP4, but not return the original input byte-for-byte. ([Cloudflare Docs][5])

# 5. Normalize every source into one technical format

Your source videos will arrive as:

* horizontal YouTube videos;
* vertical TikToks;
* screen recordings;
* 24, 25, 29.97, 30 or 60 fps;
* variable frame rate;
* HEVC, H.264, VP9 or AV1;
* mono or stereo;
* inconsistent audio volume;
* different rotation metadata.

Generate a normalized mezzanine:

```text
Container:       MP4
Video:           H.264
Audio:           AAC
Max resolution:  1080p
Frame rate:      30 fps constant
Pixel format:    yuv420p
Audio:           48 kHz stereo
Fast start:      enabled
Aspect ratio:    preserve original
```

Example:

```bash
ffmpeg \
  -i source.mp4 \
  -map 0:v:0 \
  -map 0:a:0? \
  -vf "fps=30,scale='min(1920,iw)':'-2'" \
  -c:v libx264 \
  -preset medium \
  -crf 20 \
  -pix_fmt yuv420p \
  -c:a aac \
  -b:a 160k \
  -ar 48000 \
  -movflags +faststart \
  normalized.mp4
```

The real command must account for portrait versus landscape dimensions. Do **not** stretch portrait footage into landscape.

FFmpeg supports accurate seeking while transcoding by decoding and discarding frames before the desired boundary. Stream-copy cuts, by contrast, can begin at nearby keyframes instead of the requested exact frame. ([FFmpeg][6])

## Also create an analysis proxy

The AI does not need the full 1080p master.

Generate something such as:

```text
540p
15 fps
low-to-medium bitrate
AAC mono
```

That drastically lowers:

* AI upload time;
* frame extraction time;
* storage of temporary analysis files;
* repeated analysis expense.

# 6. Upload the normalized asset for playback

Upload the normalized file to R2, then tell Cloudflare Stream to ingest it from a temporary signed R2 URL. Cloudflare supports uploading a video from a link and returns the HLS information used for playback. ([Cloudflare Docs][7])

The worker waits until Stream reports:

```text
state = ready
```

Then store:

```typescript
interface PlaybackAsset {
  sourceAssetId: string;
  streamUid: string;
  hlsManifestUrl: string;
  width: number;
  height: number;
  durationSeconds: number;
  ready: boolean;
}
```

Mark playback as requiring signed URLs. The Glutt API should mint a short-lived token for the authenticated user. Cloudflare allows signed access to HLS manifests and lets the application determine token expiration. ([Cloudflare Docs][8])

# 7. Extract all available evidence

Do not ask a video model to understand a 15-minute video from pixels alone. Build an evidence package.

## Evidence layer 1: original metadata

Keep:

* title;
* description;
* creator;
* tags;
* chapters;
* original captions;
* platform timestamps;
* associated recipe URL.

## Evidence layer 2: transcription

Extract a separate audio file:

```bash
ffmpeg -i normalized.mp4 -vn -c:a aac -b:a 96k audio.m4a
```

Send that to ElevenLabs Scribe v2.

Scribe v2 provides word-level timestamps, diarization and keyterm prompting, which are valuable for recipe terminology and exact temporal alignment. ([ElevenLabs][9])

Pass keyterms generated from:

* title;
* description;
* recipe ingredient list;
* known dish name;
* chef name;
* likely techniques;
* unusual ingredient names.

For beef Wellington:

```json
[
  "duxelles",
  "beef tenderloin",
  "prosciutto",
  "Dijon mustard",
  "puff pastry",
  "egg wash",
  "Wellington"
]
```

Store every word:

```typescript
interface TranscriptWord {
  text: string;
  startSeconds: number;
  endSeconds: number;
  speakerId?: string;
  type: "word" | "audio_event";
}
```

Do not store only a paragraph transcript. The timestamps are what let you align language with visual action.

## Evidence layer 3: shot boundaries

Use FFmpeg scene-change detection to find major edits and camera cuts.

Generate:

```text
scene 1: 00:00–00:08
scene 2: 00:08–00:21
scene 3: 00:21–00:34
...
```

This prevents a segment from accidentally starting in one shot and ending halfway through an unrelated shot.

## Evidence layer 4: sampled frames

Use two sampling passes.

### Coarse pass

One frame every one or two seconds across the entire video.

Used for:

* locating visible actions;
* detecting talking-head sections;
* identifying ingredient layouts;
* finding final dish shots;
* creating a rough visual index.

### Dense pass

Once a candidate action is located, sample around it at 4–8 fps.

Used for:

* finding the exact moment a knife first touches the food;
* identifying when a finished state becomes visible;
* tightening segment boundaries;
* choosing the best thumbnail;
* checking whether an action is truly demonstrated.

# 8. Segment the video into cooking moments

You are **not** creating recipe steps yet.

First create an objective inventory of everything visibly occurring in the video.

Gemini’s video-understanding API can process uploaded video, reference specific timestamps, segment content and accept customized sampling settings. For large or reusable files, Google recommends uploading through its File API rather than including the bytes inline. ([Google AI for Developers][10])

Feed it:

* analysis proxy;
* transcript;
* scene boundaries;
* source metadata;
* known recipe, when available.

Request JSON such as:

```json
{
  "segments": [
    {
      "candidate_start": 258.2,
      "candidate_end": 278.6,
      "primary_action": "cook mushroom duxelles",
      "secondary_actions": [
        "stir",
        "scrape pan",
        "spread mixture"
      ],
      "ingredients": [
        "mushrooms",
        "shallot"
      ],
      "tools": [
        "frying pan",
        "spatula"
      ],
      "starting_state": "wet finely chopped mushroom mixture",
      "ending_state": "dark dry paste with no visible free moisture",
      "technique": "moisture reduction",
      "dish_stage": "filling preparation",
      "visual_cue": "the pan should appear dry when the spatula moves through it",
      "spoken_summary": "cook out all of the water",
      "action_visibility": 0.95,
      "visual_quality": 0.89,
      "boundary_confidence": 0.78,
      "exact_recipe_context": "beef Wellington",
      "warnings": []
    }
  ]
}
```

## Segment length

Start with:

* target: **8–20 seconds**;
* allowed: **5–30 seconds**;
* over 30 seconds: split or require human approval.

The segment should include:

```text
one second of setup
→ the useful motion or transformation
→ one to two seconds showing the result
```

Not:

```text
chef talks for eight seconds
→ action occurs for two seconds
→ sponsor transition
```

# 9. Tighten boundaries automatically

The model’s timestamps will often be off by two or three seconds.

Use a deterministic boundary-refinement stage:

1. Expand the proposed interval by five seconds on both sides.
2. Load dense frames and transcript words.
3. Detect the first visible frame of the action.
4. Detect the first stable frame showing the result.
5. Snap away from unrelated scene cuts.
6. Add a small context pad.
7. Ensure there is no abrupt spoken sentence cut unless playback is muted.
8. Save the refined candidate.

```typescript
interface SegmentBoundary {
  modelStartSeconds: number;
  modelEndSeconds: number;

  refinedStartSeconds: number;
  refinedEndSeconds: number;

  startsOnSceneBoundary: boolean;
  endsOnSceneBoundary: boolean;
  cutsSpeechMidSentence: boolean;
  confidence: number;
}
```

# 10. Build a human-review interface

Full automation will create embarrassing mismatches at first.

The review tool should show:

```text
┌─────────────────────────────────────┐
│ Source video                        │
│ [ player with timeline ]            │
├─────────────────────────────────────┤
│ Proposed clip: 04:18.2 – 04:34.7    │
│                                     │
│ Action: Reduce mushroom duxelles    │
│ Start: Wet mixture                  │
│ End: Dry paste                      │
│ Visual cue: No visible moisture     │
│                                     │
│ [−1s] [+1s]  [Set start] [Set end]  │
│ [Approve] [Reject] [Split]           │
└─────────────────────────────────────┘
```

Reviewers should be able to:

* move boundaries;
* correct labels;
* mark the exact dish;
* mark it as generic technique;
* identify conflicts;
* mute source audio by default;
* choose a thumbnail;
* assign reusable ontology tags;
* approve native clipping.

For the first 100–300 clips, Malik or Omar should review all of them. That review data becomes the evaluation set for your automated segmenter.

# 11. Normalize segments into reusable cooking concepts

Do not store:

```text
Gordon Ramsay beef Wellington step 3
```

Store:

```text
action: reduce
object: finely chopped mushrooms
starting_state: wet loose mixture
target_state: dry concentrated paste
technique: duxelles moisture reduction
visual_question: how dry should it be?
dish_context: beef Wellington
```

That means the same clip may match:

* beef Wellington;
* mushroom ravioli filling;
* mushroom tart;
* stuffed chicken;
* another duxelles-based recipe.

Your canonical ontology should include:

## Actions

```text
chop
slice
dice
mince
whisk
fold
knead
roll
wrap
sear
sauté
reduce
deglaze
emulsify
temper
score
shape
rest
test-doneness
```

## State changes

```text
wet → dry
pale → browned
loose → thick
grainy → emulsified
sticky → smooth
flat → risen
soft peaks → stiff peaks
raw → cooked
ragged dough → elastic dough
```

## Visual questions

```text
How fine?
How brown?
How thick?
How dry?
How tight?
How smooth?
How much?
What shape?
What does done look like?
```

Those visual questions are extremely useful for matching a recipe step to a clip.

# 12. Match segments to Glutt’s CookPlan

Compile each recipe step into a `StepIntent`.

```typescript
interface StepIntent {
  recipeId: string;
  stepId: string;

  primaryAction: string;
  secondaryActions: string[];

  ingredients: string[];
  tools: string[];

  startingState?: string;
  targetState?: string;
  technique?: string;
  dishStage: string;

  visualQuestions: string[];

  exactDishPreferred: boolean;
  videoValue:
    | "none"
    | "optional"
    | "high"
    | "essential";
}
```

Example:

```json
{
  "primaryAction": "wrap",
  "secondaryActions": ["spread", "roll", "tighten"],
  "ingredients": [
    "beef tenderloin",
    "mushroom duxelles",
    "prosciutto"
  ],
  "tools": ["plastic wrap"],
  "startingState": "seared beef coated with mustard",
  "targetState": "tight even cylinder fully enclosed in prosciutto",
  "technique": "plastic-wrap tightening",
  "dishStage": "assembly",
  "visualQuestions": [
    "How tightly should it be wrapped?",
    "How should the prosciutto overlap?"
  ],
  "exactDishPreferred": true,
  "videoValue": "essential"
}
```

## Retrieval order

1. Segment from the exact source recipe video.
2. Segment from another video of the exact dish.
3. Segment demonstrating the exact technique and state transition.
4. Generic technique demonstration.
5. No clip.

## Scoring

```text
30% action match
20% ingredient/context match
20% start-to-target state match
15% technique match
10% visual-question match
 5% visual quality
```

Then apply hard penalties:

```text
− contradictory ingredient
− wrong stage
− materially different technique
− finished result does not match
− action mentioned but not visible
− obstructed or low-quality footage
```

A model should rerank only the strongest candidates and explicitly identify contradictions.

# 13. Do not immediately render a new file for every candidate segment

Downloading the full source does **not** mean you should create 40 separate MP4s immediately.

Use three asset levels.

## Level 1: semantic range

```text
master source asset
start = 258.2
end = 274.8
```

This is cheap and sufficient during review.

## Level 2: approved virtual clip

The app plays the master HLS asset, seeks to the selected timestamp and stops at the end time.

Useful for:

* internal testing;
* rarely used segments;
* clips still being evaluated.

## Level 3: materialized native clip

Generate an independent, tightly encoded asset only when:

* the clip has been approved;
* it is assigned to a recipe;
* exact boundaries matter;
* it will be played by real users;
* you need cropping, captions or consistent audio;
* it becomes a commonly reused technique.

Cloudflare Stream can generate an on-demand clip from a video asset and return it as another Stream video. ([Cloudflare Docs][11])

Alternatively, your worker can generate it through FFmpeg:

```bash
ffmpeg \
  -ss 258.20 \
  -i normalized.mp4 \
  -t 16.60 \
  -map 0:v:0 \
  -map 0:a:0? \
  -c:v libx264 \
  -preset medium \
  -crf 19 \
  -c:a aac \
  -b:a 160k \
  -movflags +faststart \
  clip.mp4
```

Re-encode approved clips. Stream-copying may produce inaccurate boundaries because video can only begin cleanly at an existing keyframe. ([FFmpeg][6])

# 14. Create consistent presentation derivatives

For each materialized clip, produce:

## Primary derivative

Preserves the source’s full frame.

```text
1080p maximum
original aspect ratio
H.264/AAC
```

## Optional vertical derivative

Only when the relevant action remains visible inside a 9:16 crop.

Do not automatically centre-crop. A cooking action might occur on the left while the chef’s face is centred.

Store a time-aware crop:

```typescript
interface CropTrack {
  aspectRatio: "9:16" | "4:5" | "1:1";
  keyframes: Array<{
    timeSeconds: number;
    centreX: number;
    centreY: number;
    zoom: number;
  }>;
}
```

Eventually a vision model can track:

* hands;
* knife;
* pan;
* bowl;
* food;
* target transformation.

For the MVP, manually choose one crop box per clip.

## Thumbnail

Select a frame where:

* the action is clear;
* hands are visible;
* the food is not motion-blurred;
* the desired target state is visible;
* there are no unnecessary title cards.

Cloudflare can also generate still or animated thumbnails from specific timestamps. ([Cloudflare Docs][12])

## Captions

Generate a short Glutt caption that describes **what to notice**, not a full replacement transcript:

> **Keep cooking until no visible moisture remains.**

The source transcript can remain available separately.

# 15. Runtime playback inside Polly

The app should use a native `AVPlayer` with Cloudflare’s signed HLS manifest. Cloudflare explicitly supports HLS playback through native iOS players. ([Cloudflare Docs][13])

## Step card

```text
STEP 4 OF 9

Cook the mushroom mixture until all
visible moisture has evaporated.

┌─────────────────────────────────┐
│ [thumbnail]                     │
│ See how dry it should look      │
│ 13 seconds                      │
└─────────────────────────────────┘

Ask Polly
```

## Polly interaction

Polly:

> “Cook it until the pan looks dry when you drag the spatula through it. I have a 13-second example if you want to see the final texture.”

User:

> “Show me.”

System:

1. Polly finishes the current sentence.
2. Realtime response creation pauses.
3. The clip expands.
4. Video prebuffering completes.
5. Playback begins.
6. Source audio is muted by default.
7. The clip reaches the end.
8. Playback collapses or remains available for replay.
9. Polly says one brief observation if helpful.
10. Conversational listening resumes.

## Why muted by default?

Because source videos will contain:

* different narrator voices;
* loud music;
* abrupt intros;
* different recording levels;
* unrelated commentary;
* speech that can wake or confuse Polly.

The default experience should be:

> **Source supplies the visual. Polly supplies the contextual explanation.**

Offer an obvious **Hear original audio** control when the original explanation is useful.

# 16. Integrate playback with Polly’s audio state machine

Add a media mode to the existing conversation controller.

```typescript
type PollyMediaState =
  | { type: "idle" }
  | { type: "preparing"; segmentId: string }
  | { type: "playing"; segmentId: string; muted: boolean }
  | { type: "paused"; segmentId: string }
  | { type: "finished"; segmentId: string };
```

While `playing`:

* do not feed source audio into Realtime ASR;
* do not classify the source narrator as the user;
* do not let wake recognition trigger on the clip saying “Polly”;
* allow a visible interrupt/pause button;
* optionally keep the device microphone active only for an explicit user interruption strategy;
* duck or stop the video if the user calls Polly;
* record playback analytics separately from conversation turns.

This needs to be treated as part of the duplex policy, not merely a SwiftUI video view.

# 17. Preloading

The magic disappears if “show me” produces a six-second spinner.

When the user enters a step:

1. Identify the best clip.
2. Mint its signed playback token.
3. Preload enough of the HLS asset for instant start.
4. Preload the next step’s high-value clip opportunistically.
5. Cancel preloading when the user skips forward.
6. Avoid downloading every clip in the recipe automatically.

Cloudflare bills delivered video based on segment requests, and client-side preloading counts as delivery, so preload selectively rather than fetching entire clips unnecessarily. ([Cloudflare Docs][14])

# 18. Database model

```sql
source_assets
-------------
id
platform
source_url
external_id
creator_id
rights_record_id
status
title
description
duration_seconds
sha256
perceptual_hash
original_object_key
normalized_object_key
analysis_proxy_object_key
stream_uid
created_at

ingestion_jobs
--------------
id
source_asset_id
job_type
status
attempt_count
progress
error_code
error_details
started_at
completed_at

transcript_words
----------------
id
source_asset_id
start_seconds
end_seconds
text
speaker_id
word_type

video_scenes
------------
id
source_asset_id
start_seconds
end_seconds
scene_score

semantic_segments
-----------------
id
source_asset_id
start_seconds
end_seconds
primary_action
secondary_actions_json
ingredients_json
tools_json
starting_state
ending_state
technique
dish_stage
visual_questions_json
visual_cue
audio_useful
visual_quality
boundary_confidence
review_status
embedding
model_version

segment_crops
-------------
id
segment_id
aspect_ratio
crop_track_json
approved

clip_assets
-----------
id
segment_id
stream_uid
object_key
aspect_ratio
duration_seconds
captions_json
thumbnail_url
requires_signed_url
status

recipe_step_intents
-------------------
id
recipe_id
step_id
step_hash
primary_action
secondary_actions_json
ingredients_json
tools_json
starting_state
target_state
technique
dish_stage
visual_questions_json
video_value
embedding

step_segment_matches
--------------------
id
step_intent_id
segment_id
match_type
action_score
ingredient_score
state_score
technique_score
visual_score
conflicts_json
total_score
review_status
```

# 19. Make every stage idempotent

Media pipelines fail.

The worker may die:

* halfway through download;
* during upload;
* after Stream receives the asset but before your database updates;
* during transcription;
* after AI analysis;
* during clipping.

Every stage needs a deterministic input and output.

```text
ACQUIRE_SOURCE
ARCHIVE_ORIGINAL
NORMALIZE_SOURCE
UPLOAD_PLAYBACK_ASSET
TRANSCRIBE
DETECT_SCENES
ANALYSE_VIDEO
REFINE_SEGMENTS
REVIEW_SEGMENTS
MATCH_TO_STEPS
MATERIALIZE_CLIPS
```

Each job should be safely retryable.

Before repeating work, check:

* does the object already exist?
* does its checksum match?
* does a Stream UID already exist?
* has this model version already analysed this file?
* has this exact segment already been materialized?
* is another worker currently holding the job lease?

# 20. Deduplication

The same cooking video may arrive through:

* a YouTube URL;
* an Instagram repost;
* a TikTok repost;
* a creator-uploaded original;
* multiple recipes.

Use:

## Exact duplicate detection

```text
SHA-256 of downloaded bytes
```

## Near-duplicate detection

Combine:

* perceptual video hash;
* representative frame hashes;
* audio fingerprint;
* duration;
* creator/title metadata.

When the original creator file arrives later, do not delete prior semantic mappings. Relink them to the higher-quality master and regenerate derivatives.

# 21. Security and operational protection

A media downloader is a risky backend surface even when the content itself is authorized.

Implement:

* URL scheme allowlist: HTTPS only;
* platform/domain allowlist;
* SSRF protection;
* no requests to private IP ranges;
* maximum duration;
* maximum download size;
* maximum redirects;
* MIME inspection after downloading;
* filename sanitization;
* no user-controlled shell interpolation;
* disposable worker directory;
* per-job CPU and memory limits;
* worker process timeout;
* malware scanning for direct uploads;
* API keys held only by the worker;
* private original bucket;
* short-lived playback tokens;
* automatic deletion cascades.

Never construct:

```typescript
exec(`yt-dlp ${userUrl}`)
```

Use an argument array:

```typescript
spawn("yt-dlp", [
  "--no-playlist",
  "--dump-single-json",
  "--skip-download",
  validatedUrl
]);
```

# 22. Content removal must be immediate and complete

Even with rights handled, build a proper removal pathway now.

One action should:

1. Disable all playback tokens.
2. Remove the segment from search.
3. Remove every step match.
4. delete materialized clip assets;
5. delete the Stream master;
6. delete R2 derivatives;
7. optionally retain only a minimal rights/audit record;
8. prevent automatic re-ingestion of the same source.

```text
source_asset.status = revoked
```

Your retrieval query must always exclude revoked assets.

# 23. The MVP I would actually implement

Do **not** start with an automated worldwide content engine.

## Stage 1: five recipes, five full videos

Pick:

* beef Wellington;
* chicken katsu;
* carbonara;
* butter chicken;
* cinnamon rolls.

For each:

* one rights-cleared full video;
* four to six useful moments;
* manually reviewed labels;
* one clip attached to each visually difficult step;
* native Glutt playback;
* Polly voice command: “Show me.”

That is roughly 25 clips.

## Stage 2: prove the interaction

Measure:

```text
clip_offered
clip_opened
clip_started
clip_completed
clip_replayed
clip_unmuted
clip_interrupted
clip_helpful_yes
clip_helpful_no
step_completed_after_clip
question_asked_after_clip
cook_completed
```

You need to determine:

* Do people watch them?
* At which steps?
* Do they replay them?
* Is visual-only sufficient?
* Does Polly’s explanation improve comprehension?
* Does video distract them?
* Do users prefer the original recipe creator?
* Do exact-dish clips outperform generic technique clips?

## Stage 3: automate segmentation

After the player is validated:

* transcribe automatically;
* detect scenes;
* ask Gemini for candidate segments;
* run boundary refinement;
* send candidates to review.

## Stage 4: build the reusable technique library

Then index:

```text
searing
folding
kneading
emulsifying
reducing
whipping
wrapping
scoring
checking doneness
rolling pastry
```

## Stage 5: automate recipe matching

Only after you have hundreds of reviewed segments should Glutt automatically attach clips to arbitrary imported recipes.

# 24. A realistic two-week implementation sequence

## Days 1–2: acquisition foundation

* Add schemas.
* Create job queue.
* Build container image containing `yt-dlp`, FFmpeg and `ffprobe`.
* Implement probe and download stages.
* Upload originals to R2.
* Add checksums and retry behaviour.

## Days 3–4: normalization and playback

* Generate normalized MP4.
* Ingest it into Cloudflare Stream.
* Add signed HLS endpoint.
* Build basic `AVPlayer` view.
* Confirm precise start and stop behaviour.

## Days 5–6: first manual clips

* Choose five source videos.
* Manually label 20–30 segments.
* Create review page.
* Materialize clips.
* Generate thumbnails and captions.

## Days 7–8: Polly integration

* Add media playback state.
* Add `show_step_video` tool.
* Pause and reopen conversational policy correctly.
* Prevent clip audio from entering ASR.
* Add mute/original-audio controls.

## Days 9–10: automatic evidence extraction

* ElevenLabs transcription.
* Scene detection.
* Frame extraction.
* Store timestamp-aligned evidence.

## Days 11–12: AI segmentation

* Gemini structured segmentation.
* Boundary refinement.
* Review approval workflow.
* Save model versions and confidence.

## Days 13–14: recipe matching and testing

* Compile `StepIntent`.
* Build semantic retrieval.
* Add conflict-aware reranking.
* Cook the five recipes.
* Review every playback failure and wrong match.

# 25. The key product decision

The system should not promise:

> **Every step has a video.**

It should promise:

> **Whenever seeing the technique is more helpful than reading about it, Polly can instantly show you the exact moment that matters.**

That keeps the feature useful rather than noisy.

A nine-step recipe may contain:

* three essential demonstrations;
* two target-state examples;
* four steps requiring no video.

That is a better product than forcing nine clips.

# Final recommended architecture

```text
                     VERCEL
        ┌──────────────────────────────┐
        │ URL intake / rights record  │
        │ Job creation                │
        │ Admin review UI             │
        │ Playback-token endpoint     │
        └──────────────┬───────────────┘
                       │
                    QUEUE
                       │
        ┌──────────────▼───────────────┐
        │ DEDICATED MEDIA WORKER       │
        │                              │
        │ yt-dlp / direct upload       │
        │ ffprobe                      │
        │ FFmpeg                       │
        │ transcription               │
        │ frame + scene extraction    │
        │ Gemini segmentation         │
        └───────┬───────────┬──────────┘
                │           │
             R2 RAW      CLOUDFLARE STREAM
                │           │
       original/master      HLS + clips
                │           │
                └─────┬─────┘
                      │
             SEGMENT DATABASE
                      │
              STEP MATCHING
                      │
                 iOS / Polly
```

The crucial strategy is:

> **Download and archive the complete video once. Analyse it once. Reuse its approved semantic moments across many recipes. Only render separate clip assets after a moment proves useful.**

That gives you the consistency you are looking for without creating a giant pile of redundant MP4 files or forcing an expensive AI pipeline to rerun during somebody’s cooking session.

[1]: https://vercel.com/docs/functions/limitations?utm_source=chatgpt.com "Vercel Functions Limits"
[2]: https://developers.cloudflare.com/stream/?utm_source=chatgpt.com "Overview · Cloudflare Stream docs"
[3]: https://github.com/yt-dlp/yt-dlp/blob/master/README.md?utm_source=chatgpt.com "yt-dlp/README.md at master · yt-dlp/yt-dlp · GitHub"
[4]: https://developers.cloudflare.com/r2/objects/upload-objects/?utm_source=chatgpt.com "Upload objects · Cloudflare R2 docs"
[5]: https://developers.cloudflare.com/stream/faq/?utm_source=chatgpt.com "Frequently asked questions about Cloudflare Stream · Cloudflare Stream docs"
[6]: https://www.ffmpeg.org/ffmpeg.html?utm_source=chatgpt.com "ffmpeg Documentation"
[7]: https://developers.cloudflare.com/stream/uploading-videos/upload-via-link/?utm_source=chatgpt.com "Upload with a link · Cloudflare Stream docs"
[8]: https://developers.cloudflare.com/stream/viewing-videos/securing-your-stream/?utm_source=chatgpt.com "Secure your Stream · Cloudflare Stream docs"
[9]: https://elevenlabs.io/docs/overview/capabilities/speech-to-text/?utm_source=chatgpt.com "Transcription | ElevenLabs Documentation"
[10]: https://ai.google.dev/gemini-api/docs/video-understanding?hl=en&utm_source=chatgpt.com "Video understanding  |  Gemini API  |  Google AI for Developers"
[11]: https://developers.cloudflare.com/stream/edit-videos/video-clipping/?utm_source=chatgpt.com "Clip videos · Cloudflare Stream docs"
[12]: https://developers.cloudflare.com/stream/viewing-videos/displaying-thumbnails/?utm_source=chatgpt.com "Display thumbnails · Cloudflare Stream docs"
[13]: https://developers.cloudflare.com/stream/viewing-videos/using-own-player/?utm_source=chatgpt.com "Use your own player · Cloudflare Stream docs"
[14]: https://developers.cloudflare.com/stream/pricing/?utm_source=chatgpt.com "Pricing · Cloudflare Stream docs"
