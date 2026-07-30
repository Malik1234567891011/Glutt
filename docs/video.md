This is ambitious, but it is technically feasible **provided you separate “playing a segment” from “creating and owning a clip.”** Those are very different systems.

My strongest recommendation is:

> **For the first version, do not download, cut, crop, or rehost arbitrary YouTube videos. Store a YouTube video ID plus a start and end timestamp, then play that interval through YouTube’s official embedded player.**

To the user, it feels like a 15-second clip. Technically, Glutt is opening the original YouTube video at `06:42` and stopping it at `06:57`.

Then build the intelligence layer that determines:

> Recipe step 4, “wrap the beef in duxelles and prosciutto”
> → Gordon Ramsay video
> → `06:42–06:57`

That is the right MVP. The long-term version can use genuinely clipped, licensed footage from creators.

---

# The system is really three separate problems

1. **Where are you legally and technically getting the footage?**
2. **How do you identify and label useful moments inside videos?**
3. **How do you present those moments without ruining the Polly experience?**

The second problem sounds hardest, but the first one determines your entire architecture.

# 1. Do not physically clip ordinary YouTube videos

YouTube permits showing videos through its embedded player. However, its terms prohibit downloading, reproducing, modifying, or otherwise using content outside the functionality YouTube provides unless you have permission from YouTube and the relevant rights holder. Its API policies also prohibit separating audio from video, altering the player, blocking ads, background playback, and modifying the audiovisual stream. ([YouTube][1])

That means the dangerous architecture is:

> Find Gordon Ramsay video
> → download using `yt-dlp`
> → cut 15-second MP4
> → upload to Glutt CDN
> → crop vertically or remove audio
> → show inside Glutt

You would be reproducing and modifying copyrighted content outside YouTube’s player.

It also means that, for arbitrary public YouTube videos, I would **not** build the indexing pipeline around:

> download audio → send to ElevenLabs Scribe

YouTube’s policies specifically prohibit downloading or isolating audio/video through the API ecosystem, and the official captions API only allows downloading a caption track when the authenticated user has permission to edit that video. Merely knowing that captions exist does not give you access to their text through the official API. ([Google for Developers][2])

## What you can do

Store:

```text
youtubeVideoId
startSeconds
endSeconds
```

Then use YouTube’s IFrame Player API:

```javascript
player.cueVideoById({
  videoId: "VIDEO_ID",
  startSeconds: 402,
  endSeconds: 417
});
```

The official player supports start and end seconds, inline playback, play/pause events, seeking and player-state callbacks. YouTube notes that the start may resolve to the nearest keyframe rather than the exact frame, so you should expect slight boundary imprecision. ([Google for Developers][3])

Do not build around YouTube’s own “Clips” feature. YouTube announced in April 2026 that “Share at Timestamp” would replace Clips, and there is no stable documented Clips-management API that should be foundational to Glutt. ([Google Support][4])

## When physical clips are acceptable

Use actual MP4 clips only when one of these is true:

* Glutt recorded and owns the footage.
* A creator has given Glutt a commercial licence and supplied the original files.
* The video is genuinely available under a licence that permits reuse, such as CC BY, and you follow its attribution terms.
* You receive another explicit legal right to use it.

YouTube allows creators to designate videos under a Creative Commons Attribution licence, and its search API can filter for Creative Commons videos. But do not assume a famous chef’s video is reusable merely because it is publicly watchable. ([Google Support][5])

This leads to two content modes:

| Mode                          | Playback                 | Editing                                  | Best use                     |
| ----------------------------- | ------------------------ | ---------------------------------------- | ---------------------------- |
| **YouTube reference segment** | Official embedded player | No cropping, downloading or rehosting    | MVP and broad coverage       |
| **Glutt-licensed clip**       | Native video player/CDN  | Crop, preload, loop, caption, mute, edit | Premium long-term experience |

That distinction should exist directly in your database.

---

# 2. The best source hierarchy

Do not begin by searching all of YouTube independently for every step. Prioritize sources in this order.

## Priority 1: The video the recipe came from

Suppose the user imports Gordon Ramsay’s beef Wellington video.

That video should be the first and usually only source used for its steps. This solves several problems:

* The clip and recipe are probably using the same ingredients.
* The technique order matches.
* Quantities and terminology are less likely to conflict.
* Attribution is clear.
* You only need to segment one video.
* The user already selected that creator.

This is a much more defensible first product than:

> Import one person’s recipe, then show instructions from three unrelated chefs.

Different chefs may use different temperatures, dough thicknesses, timings or techniques. A visually impressive but contradictory clip damages trust.

## Priority 2: Exact-recipe footage from a trusted source

When the imported recipe is textual, search for an exact dish:

```text
beef wellington full recipe duxelles prosciutto pastry
```

Then prefer channels you have reviewed or partnered with.

## Priority 3: Generic technique footage

When there is no exact recipe footage, match the technique rather than the dish:

```text
how to sear beef tenderloin
how dry should mushroom duxelles be
how to wrap beef wellington in puff pastry
```

But the UI must label it honestly:

> **Technique example: wrapping in puff pastry**

Not:

> **Your recipe, step 6**

That distinction matters whenever the clip is not demonstrating the exact recipe.

## Priority 4: No video

A wrong clip is much worse than no clip.

The matching engine must be allowed to return:

```text
no_safe_match
```

Do not force one video onto every step just because the feature promises “video for every step.”

---

# 3. Do not search YouTube live for every cook

The current YouTube Data API can filter searches to videos that are embeddable, playable outside YouTube, captioned, a particular duration and optionally Creative Commons licensed. However, the current documentation places `search.list` in a separate Search Queries bucket with a default limit of 100 calls per day. `videos.list` is cheaper and lets you verify metadata such as duration, embedding status and regional restrictions. ([Google for Developers][6])

So the architecture should not be:

> User enters step
> → search YouTube
> → analyse five videos
> → choose one live

It should be:

> Offline worker discovers videos
> → videos are analysed and indexed once
> → semantic segments are stored in Glutt’s database
> → recipe steps query the existing segment library

Search is an ingestion operation, not a runtime operation.

A candidate search might use:

```text
query: "beef wellington mushroom duxelles dry pan"
type: video
videoEmbeddable: true
videoSyndicated: true
videoCaption: closedCaption
videoDuration: medium
```

Then call `videos.list` on the returned IDs to verify:

* `status.embeddable`
* duration
* regional availability
* licence
* channel and title
* Made for Kids status
* current existence

YouTube API metadata generally needs to be refreshed or deleted after 30 days rather than treated as permanently cached. The policies also require checking that content still exists and displaying current metadata. ([Google for Developers][7])

---

# 4. How to automatically label the videos

There is now a surprisingly clean route for public YouTube videos.

As of July 2026, Google’s Gemini API officially supports passing a **public YouTube URL directly as video input**. It can describe and segment video content, answer questions about timestamps and process audio and visual information together. The feature is currently marked preview. Gemini samples visuals at approximately one frame per second by default, adds timestamps every second and warns that very fast actions may be missed. ([Google AI for Developers][8])

That means your ingestion pipeline can be:

```text
YouTube URL
    ↓
Gemini video understanding
    ↓
Timestamped cooking-action candidates
    ↓
Second-pass verification
    ↓
Human approval
    ↓
Glutt segment database
```

This is the cleanest supported technical route I found for analysing public YouTube URLs without Glutt downloading the media itself.

It is **not** a licence to rehost or modify the footage. Analysis and playback remain separate.

## First-pass segmentation prompt

Do not ask:

> “Split this video into recipe steps.”

That produces broad chapters and sloppy boundaries.

Ask it to detect **visually useful demonstrations**:

```text
Analyse this cooking video and identify every segment that would be
useful as a short visual demonstration to someone actively cooking.

Only include segments where the cooking action or target food state is
actually visible. Do not include introductions, talking-head narration,
ingredient lists without action, sponsor sections or finished-dish glamour shots
unless the finished state is necessary to judge doneness.

Return JSON matching this schema:

{
  "segments": [
    {
      "start_seconds": 0,
      "end_seconds": 0,
      "primary_action": "",
      "ingredients_visible": [],
      "tools_visible": [],
      "starting_state": "",
      "ending_state": "",
      "technique": "",
      "dish_stage": "",
      "visual_cue_taught": "",
      "spoken_instruction_summary": "",
      "is_action_clearly_visible": true,
      "different_techniques_shown": [],
      "visual_quality": 0.0,
      "boundary_confidence": 0.0
    }
  ]
}

Keep each segment temporally tight. Prefer 6–25 second segments.
Do not infer an action merely because the chef mentions it.
```

The important fields are not merely `action` and `ingredient`.

You need:

> **starting state → action → ending state**

For example:

```json
{
  "primary_action": "cook mushrooms until dry",
  "ingredients_visible": ["finely chopped mushrooms"],
  "tools_visible": ["wide frying pan", "spatula"],
  "starting_state": "wet, loose mushroom mixture",
  "ending_state": "dark, paste-like mixture with no visible liquid",
  "technique": "reducing mushroom duxelles",
  "visual_cue_taught": "the pan should look dry and the mixture should hold together"
}
```

That is dramatically more useful than the label:

```text
cooking mushrooms
```

## Second-pass verification

The first model pass finds candidates. A separate pass should verify each candidate against the actual recipe step.

Input:

```text
Recipe step:
"Cook the chopped mushrooms over medium-high heat until all moisture has
evaporated and the mixture forms a dry paste."

Candidate video segment:
Video ID: ...
Start: 04:18
End: 04:36
Detected action: ...
```

Expected result:

```json
{
  "action_match": 0.94,
  "ingredient_match": 0.98,
  "state_transition_match": 0.91,
  "tool_match": 0.80,
  "visual_usefulness": 0.93,
  "conflicts": [],
  "shows_action_not_just_mentions_it": true,
  "recommended": true
}
```

Do not let the same model call both propose and approve its own answer. Independent verification reduces confident bad mappings.

## Human review remains necessary

Gemini’s default one-frame-per-second video sampling is sufficient for broad actions like rolling pastry or sautéing mushrooms, but it may not reliably identify frame-tight boundaries for quick cuts, knife motions or jump-edited Shorts. ([Google AI for Developers][8])

For your first database, build a small internal review screen:

```text
Video player
Timeline with AI candidate segments
Current segment metadata
Recipe-step matches
[Adjust start] [Adjust end] [Approve] [Reject]
```

The model does 80% of the locating. A person fixes the last two seconds and catches contradictions.

That is much more realistic than attempting full unsupervised correctness immediately.

---

# 5. When TwelveLabs becomes useful

For creator-supplied, Glutt-owned or otherwise licensed raw files, TwelveLabs is worth testing. Its current Pegasus video-segmentation system supports custom segment definitions, timestamped JSON metadata, duration limits and semantic video search. Its ingestion documentation expects uploaded files or direct raw-media URLs rather than ordinary video-platform pages. ([TwelveLabs Developer Documentation][9])

It could let you define cooking-specific segments such as:

```json
{
  "id": "visible_cooking_actions",
  "description": "A temporally tight segment in which a cooking action is clearly demonstrated",
  "fields": [
    {
      "name": "action",
      "type": "string",
      "description": "The principal cooking action being visibly performed"
    },
    {
      "name": "target_state",
      "type": "string",
      "description": "The visible food state achieved at the end"
    },
    {
      "name": "ingredients",
      "type": "array",
      "description": "Ingredients visibly involved in the action"
    }
  ]
}
```

My provider split would be:

* **Public YouTube URL:** Gemini URL analysis → official YouTube playback.
* **Licensed raw footage:** TwelveLabs or your own frame/transcript pipeline → native Glutt clips.
* **High-precision boundary cleanup:** human review and eventually cooking-specific evaluation data.

You do not need TwelveLabs merely to prove that users value the feature.

---

# 6. The ontology Glutt actually needs

The system should not think in “recipe step number.” Step numbers are recipe-specific.

It should understand reusable cooking concepts.

## Step intent

```typescript
interface StepIntent {
  stepId: string;
  recipeId: string;

  primaryAction: string;          // "wrap"
  secondaryActions: string[];     // ["spread", "roll", "tighten"]
  ingredients: string[];          // ["beef tenderloin", "duxelles", "prosciutto"]
  tools: string[];                // ["plastic wrap"]
  startingState?: string;         // "seared beef coated in mustard"
  targetState?: string;           // "tight cylindrical parcel"
  technique?: string;             // "prosciutto wrapping"
  dishStage: string;              // "assembly"
  visualQuestion?: string;        // "How tightly should it be wrapped?"
  exactDishRequired: boolean;
}
```

## Video segment

```typescript
interface VideoSegment {
  id: string;
  videoSourceId: string;

  startSeconds: number;
  endSeconds: number;

  primaryAction: string;
  ingredients: string[];
  tools: string[];
  startingState?: string;
  endingState?: string;
  technique?: string;
  dishStage?: string;

  visualCue?: string;
  audioUseful: boolean;
  visualQuality: number;
  boundaryConfidence: number;

  rightsMode: "youtube_embed" | "licensed" | "owned" | "cc_by";
  reviewStatus: "unreviewed" | "approved" | "rejected";
}
```

## Match

```typescript
interface StepSegmentMatch {
  stepId: string;
  segmentId: string;

  actionScore: number;
  ingredientScore: number;
  stateScore: number;
  techniqueScore: number;
  visualScore: number;

  conflicts: string[];
  totalScore: number;

  matchType: "exact_recipe" | "exact_technique" | "general_example";
  approvedBy: "model" | "human";
}
```

The video’s title, channel name, thumbnail and YouTube availability metadata should live separately from Glutt’s own semantic analysis. That makes the 30-day YouTube metadata refresh requirement much easier to respect.

---

# 7. Matching the right segment to the right step

Use a three-stage retrieval process.

## Stage A: Hard filtering

Remove candidates when:

* the video is unavailable or no longer embeddable;
* the user’s region is blocked;
* the action is not actually visible;
* the ingredient or technique materially conflicts;
* the clip comes from a different stage;
* the segment is too long or visually unclear;
* exact-dish footage is required but the segment is generic.

Example:

Recipe says:

> Place the wrapped beef on puff pastry and roll it once.

Reject a segment that shows:

> wrapping raw beef directly in pastry without duxelles or prosciutto.

It might look similar semantically, but it teaches the wrong assembly.

## Stage B: Semantic retrieval

Create embeddings from a canonical description:

```text
Wrap seared beef coated with mushroom duxelles tightly inside overlapping
prosciutto slices using plastic wrap, creating an even cylinder.
```

Retrieve the nearest 20 approved segments.

Do not embed only the literal recipe text. Embed the normalized action, objects and target state.

## Stage C: Reranking

A model compares the top candidates against the current recipe.

A reasonable starting score is:

```text
35% action
20% ingredients
20% starting/ending state
10% technique
5% tools
10% visual quality
− hard conflict penalties
```

The precise weights should eventually come from human judgments.

I would require something like:

```text
Exact-recipe segment:       total ≥ 0.82 and no hard conflict
Generic-technique segment:  total ≥ 0.88 and clearly labelled as generic
Anything below threshold:   no clip
```

The generic threshold should be higher because generic clips have a greater chance of contradicting the recipe.

---

# 8. Two different types of visual help

This is an important product insight.

Not every visual question is:

> “How do I perform this motion?”

Sometimes it is:

> “What is this supposed to look like?”

So Glutt should support two segment types.

## Demonstration

> **Watch how to wrap it tightly — 18 sec**

Shows the motion.

## Target state

> **See how dry the mushrooms should be — 9 sec**

Shows the correct appearance at the end.

For many cooking problems, the second is more valuable.

Examples:

* How finely should the onion be chopped?
* How dark should the roux be?
* How thick should the sauce become?
* What does “stiff peaks” look like?
* How tightly should the Wellington be wrapped?
* How brown should the sear be?

The `CookPlan` can mark whether a step has:

```text
visualDemonstrationRecommended
targetStateReferenceRecommended
```

You do not necessarily need both.

---

# 9. The UI I would build

I would **not** continuously play a video beside Polly for every step.

That creates several problems:

* competing voices;
* the user starts watching instead of cooking;
* ads can appear;
* loading becomes distracting;
* many steps do not need demonstrations;
* Glutt begins feeling like a YouTube wrapper;
* users may leave to watch the complete video.

Instead, make video an on-demand visual tool controlled by Polly.

## Default step state

```text
STEP 4 OF 9

Spread the duxelles over the prosciutto,
then place the beef near the bottom edge.

[ Watch the wrapping technique · 17 sec ]

Timer / checklist content

──────────────
      Ask Polly
```

## Voice interaction

Polly:

> “Spread the mushrooms evenly, but leave a small border. I have a 17-second example if you want to see the wrapping technique.”

User:

> “Show me.”

Then the player expands and plays the window.

At the end:

> “Notice how he uses the plastic wrap to tighten the cylinder rather than squeezing the beef directly.”

Polly should explain **what to notice**, not narrate every visible movement.

## Recommended playback states

### Collapsed

A thumbnail or card:

> Watch how the pastry is sealed · 12 sec

### Expanded inline

A full-width 16:9 player inside the step.

### Full-screen

Available when the technique has fine visual details.

Do not use a tiny floating player beside Polly. YouTube requires embedded players to be at least 200×200 pixels and recommends approximately 480×270 for a 16:9 player. The player controls also cannot be obscured or replaced. ([Google for Developers][10])

## Audio behaviour

When the YouTube segment begins:

1. Polly stops speaking.
2. Polly does not generate responses to the video’s speech.
3. The user chooses whether the source video is muted.
4. When playback ends, Polly’s conversational gate reopens.
5. Polly can provide one short interpretation of the visual cue.

I would default to **muted visual playback** for clips where narration is unnecessary:

> “Show motion only”

And offer:

> “Hear original”

for clips whose verbal explanation matters.

Muting through the normal player controls is different from stripping or replacing the audio track, which YouTube prohibits.

## One player, not one player per step

Use a single persistent YouTube player view and cue a different video/segment when needed.

Google’s iOS guidance specifically recommends reusing an existing player and using the cue functions instead of repeatedly constructing new web views because reloading the player creates noticeable delay. It also advises against concurrent playback in multiple player views. ([Google for Developers][11])

For your Swift app, I would probably implement:

```text
SwiftUI
  ↓
UIViewRepresentable
  ↓
WKWebView
  ↓
YouTube IFrame Player API
  ↓
JavaScript bridge back to Swift
```

Events sent to Swift:

```text
playerReady
playing
paused
ended
error
currentTimeChanged
```

Commands sent to JavaScript:

```text
cue(videoId, start, end)
play()
pause()
mute()
unmute()
seek(seconds)
```

Use `playsinline=1`.

Remember that if the user manually seeks, YouTube’s documented `endSeconds` behaviour can stop applying, depending on the player call sequence. Keep your own current-time monitor and pause when:

```text
currentTime >= segment.endSeconds
```

Then reset to the start on “replay.”

---

# 10. Source attribution and subscription positioning

Every video card should visibly say:

```text
From Gordon Ramsay on YouTube
[Watch full video]
```

The button should open the YouTube app when available or the browser otherwise, and you should not obscure YouTube’s own player links or branding. ([Google for Developers][12])

YouTube may show ads in embedded videos. Glutt cannot remove or block them. ([Google for Developers][13])

This creates an unavoidable product trade-off:

* YouTube embeds give you enormous content coverage quickly.
* Licensed Glutt clips give you a clean, controlled and ad-free product.

Also, do not market the subscription as:

> “Pay to access Gordon Ramsay clips.”

YouTube’s policies require independent product value and prohibit charging users merely for functionality YouTube provides freely. Your paid value is:

* Polly’s guidance;
* recipe adaptation;
* timing;
* step orchestration;
* segment selection;
* personal cooking context;
* memory;
* troubleshooting.

The YouTube segment is supporting evidence inside that system. ([Google for Developers][12])

---

# 11. Beef Wellington example

A normalized Wellington cook might look like this:

| Glutt step                 | Best visual evidence                            | Clip rule                        |
| -------------------------- | ----------------------------------------------- | -------------------------------- |
| Trim and season tenderloin | How much silver skin to remove                  | Exact or generic tenderloin prep |
| Sear the beef              | Correct depth of browning                       | Generic technique acceptable     |
| Prepare duxelles           | Chop size and final dryness                     | Exact recipe strongly preferred  |
| Lay out prosciutto         | Overlap and dimensions                          | Exact recipe preferred           |
| Wrap beef in prosciutto    | Using plastic wrap to tighten                   | Exact Wellington clip            |
| Wrap in puff pastry        | Pastry thickness and seam position              | Exact Wellington clip            |
| Egg wash and score         | Scoring without cutting through                 | Exact or pastry technique        |
| Bake and rest              | Mostly timer/temperature, little visual value   | Probably no clip                 |
| Slice                      | Expected internal doneness and pastry structure | Target-state reference           |

Notice that “bake for 35 minutes” probably does **not** need video.

The system should not pursue symmetry. It should pursue usefulness.

A typical nine-step recipe may contain:

* four high-value clips;
* two optional target-state images;
* three steps with no visual aid.

That is likely a better experience than nine forced videos.

---

# 12. The database structure

I would use something close to this:

```sql
video_sources
-------------
id
source_type                 -- youtube_embed, licensed, owned, cc_by
youtube_video_id
source_url
channel_id
channel_name
title
duration_seconds
license_type
embeddable
made_for_kids
region_restrictions_json
rights_document_id
last_verified_at
created_at

video_segments
--------------
id
video_source_id
start_seconds
end_seconds
primary_action
technique
starting_state
ending_state
dish_stage
visual_cue
ingredients_json
tools_json
audio_useful
visual_quality
boundary_confidence
review_status
semantic_embedding
model_version
created_at

recipe_step_intents
-------------------
id
recipe_id
step_id
step_hash
primary_action
technique
starting_state
target_state
dish_stage
ingredients_json
tools_json
visual_question
semantic_embedding

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
total_score
conflicts_json
approval_status
approved_by
created_at
```

The `step_hash` is important.

Recipes commonly express the same semantic instruction differently:

```text
Cook mushrooms until dry.
Reduce the mushroom mixture until no liquid remains.
Sauté the duxelles until it forms a paste.
```

They should resolve to one canonical intent:

```text
technique: reduce_mushroom_duxelles
target_state: dry_paste_no_visible_moisture
```

Then one approved segment can serve hundreds of imported recipes.

That is where the database becomes a real asset rather than a pile of one-off timestamp mappings.

---

# 13. Handling failure at runtime

Before displaying a segment:

```text
1. Check cached availability.
2. Ensure current region is allowed.
3. Load the official player.
4. Handle embedding-disabled/player errors.
5. If playback fails, remove the card immediately.
6. Fall back to Polly’s verbal explanation or a Glutt-owned image.
7. Queue the video for revalidation.
```

Do not show:

> Video unavailable

in the middle of cooking and leave the user stuck.

Your fallback hierarchy should be:

```text
Approved exact clip
→ Approved generic technique clip
→ Still visual reference
→ Polly verbal explanation
→ No media
```

---

# 14. The biggest risks

## Contradicting the actual recipe

A video might use:

* different temperatures;
* different pastry;
* different thickness;
* different ingredient order;
* different pan;
* different doneness.

The visual model may call it a match while a cook notices it is materially different.

That is why `conflicts` must be a first-class field, not an afterthought.

## Ads and loading time

You cannot guarantee immediate 12-second playback when YouTube decides to show an ad or when the embedded player needs to load.

This limits how seamless the YouTube-backed version can ever become.

## Video deletion and embedding changes

Creators can delete videos, disable embedding or restrict regions. Your mappings must be revalidated.

## Cognitive overload

There is a real possibility that users do not want Polly, instructions, timers and videos simultaneously.

The feature should be invoked when needed, not constantly demanding attention.

## Losing the user to YouTube

The full video can be more entertaining than Glutt. The user may stop interacting with Polly and watch the creator instead.

The winning interaction is:

> **Polly identifies the exact 12 seconds that answer the user’s immediate question.**

Not:

> **Glutt embeds another full cooking video.**

## Trust

A wrong video creates more distrust than an imperfect spoken answer because users can visibly see the contradiction.

Fail closed.

---

# 15. What I would build first

Do not begin with global YouTube search, fully automatic segmentation and thousands of clips.

Build a manually controlled experiment.

## Pilot

Choose five visually complex recipes:

* Beef Wellington
* Chicken katsu
* Carbonara
* Butter chicken
* Cinnamon rolls or croissants

For each:

1. Select one original YouTube video.
2. Manually identify four to seven useful intervals.
3. Store the video ID and timestamps.
4. Connect them to your existing `CookPlan`.
5. Build the `Watch 14s` step card.
6. Let Polly launch it through voice.
7. Test with real cooking sessions.

Instrument:

```text
clip_available
clip_opened
clip_started
clip_completed
clip_replayed
clip_failed
full_video_opened
question_asked_after_clip
step_completed
user_rated_clip_helpful
```

The first question is not:

> Can AI index every cooking video?

It clearly can help substantially.

The first question is:

> **When somebody is actually cooking, do they choose to watch these clips, and does the clip solve something Polly’s voice alone did not?**

Only after that signal should you automate ingestion.

## Build order

### Phase 1 — Manual timestamped embeds

Prove the UI and behaviour.

### Phase 2 — Gemini-assisted indexing

Public YouTube URL → structured candidate segments → human approval.

### Phase 3 — Canonical technique library

Approved reusable segments for:

* chopping;
* searing;
* folding;
* emulsifying;
* kneading;
* reducing;
* checking doneness;
* shaping;
* wrapping.

### Phase 4 — Creator partnerships

Offer creators:

* attribution;
* full-video traffic;
* a creator profile;
* potentially revenue sharing;
* analytics about which techniques users watch.

Request the original footage and a commercial licence.

### Phase 5 — Native Glutt video library

Serve short, preloaded clips without YouTube latency or ads. Support:

* vertical crops;
* silent loops;
* visual annotations;
* exact start/end;
* offline caching;
* frame-by-frame target states.

---

# My final recommendation

The winning architecture is:

```text
Imported recipe
    ↓
Normalized CookPlan steps
    ↓
StepIntent compiler
    ↓
Approved segment retrieval
    ↓
Compatibility reranker
    ↓
YouTube ID + timestamp window
    ↓
Single visible inline YouTube player
    ↓
Polly explains what to notice
```

For ingestion:

```text
Curated public YouTube video
    ↓
Gemini public-URL video analysis
    ↓
Timestamped action/state candidates
    ↓
Model verification
    ↓
Human boundary and conflict review
    ↓
Semantic segment database
```

Long term:

```text
Creator partnership
    ↓
Licensed raw footage
    ↓
True native Glutt clips
```

The mistake would be trying to build “AI automatically clips all of YouTube for every recipe” immediately. The correct first product is much narrower:

> **Polly can pull up the exact moment from the recipe’s original video when seeing the technique would help more than hearing another explanation.**

That alone could feel extremely powerful, and you can build and validate it without first solving the entire global cooking-video corpus.

[1]: https://www.youtube.com/static?template=terms&utm_source=chatgpt.com "Terms of Service"
[2]: https://developers.google.com/youtube/v3/docs/captions/download?utm_source=chatgpt.com "Captions: download | YouTube Data API"
[3]: https://developers.google.com/youtube/iframe_api_reference?utm_source=chatgpt.com "YouTube Player API Reference for iframe Embeds"
[4]: https://support.google.com/youtube/thread/425735532/updating-how-you-share-video-moments?hl=en&utm_source=chatgpt.com "Updating how you share video moments"
[5]: https://support.google.com/youtube/answer/2797468?hl=en-GB&utm_source=chatgpt.com "Licence types on YouTube - YouTube Help"
[6]: https://developers.google.com/youtube/v3/docs/search/list "Search: list  |  YouTube Data API  |  Google for Developers"
[7]: https://developers.google.com/youtube/terms/developer-policies "YouTube API Services - Developer Policies  |  Google for Developers"
[8]: https://ai.google.dev/gemini-api/docs/video-understanding "Video understanding  |  Gemini API  |  Google AI for Developers"
[9]: https://docs.twelvelabs.io/docs/get-started/quickstart/segment-videos?utm_source=chatgpt.com "Segment videos | TwelveLabs"
[10]: https://developers.google.com/youtube/player_parameters?utm_source=chatgpt.com "YouTube Embedded Players and Player Parameters"
[11]: https://developers.google.com/youtube/v3/guides/ios_youtube_helper "Embed YouTube Videos in iOS Applications with the YouTube Helper Library  |  YouTube IFrame Player API  |  Google for Developers"
[12]: https://developers.google.com/youtube/terms/developer-policies-guide?utm_source=chatgpt.com "Complying with YouTube's Developer Policies"
[13]: https://developers.google.com/youtube/terms/developer-policies?utm_source=chatgpt.com "YouTube API Services - Developer Policies"
