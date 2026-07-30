// Auto-index short YouTube demonstration windows for CookPlan steps.
//
// Layers (video.md Phase 2, no human labeling):
//   1) Gemini video understanding on a public YouTube URL → candidate segments
//   2) Separate Gemini text pass → match/reject segments per recipe step
//   3) Return only recommended matches as (videoId, start, end) for official embed
//
// Playback stays YouTube IFrame — we never download or rehost AV content.
import { isAuthorized } from "./auth.js";
import { logUsage, installIdFrom } from "./usage.js";
import {
  resolveGeminiKey,
  resolveGeminiModel,
  geminiGenerate,
  parseJSONText,
} from "./gemini.js";

const MIN_SEGMENT_S = 5;
const MAX_SEGMENT_S = 35;
const MIN_RECOMMEND_SCORE = 0.72;

function youtubeVideoId(url) {
  try {
    const u = new URL(String(url || ""));
    if (u.hostname.includes("youtu.be")) {
      return u.pathname.split("/").filter(Boolean)[0] || null;
    }
    if (u.hostname.includes("youtube.com")) {
      return u.searchParams.get("v");
    }
  } catch {
    // ignore
  }
  return null;
}

function normalizeYoutubeURL(url, videoId) {
  return `https://www.youtube.com/watch?v=${videoId}`;
}

function clampSegment(seg) {
  let start = Math.max(0, Math.round(Number(seg.start_seconds) || 0));
  let end = Math.max(0, Math.round(Number(seg.end_seconds) || 0));
  if (end <= start) end = start + MIN_SEGMENT_S;
  if (end - start < MIN_SEGMENT_S) end = start + MIN_SEGMENT_S;
  if (end - start > MAX_SEGMENT_S) end = start + MAX_SEGMENT_S;
  return { ...seg, start_seconds: start, end_seconds: end };
}

async function redisCommand(command) {
  const base = (process.env.UPSTASH_REDIS_REST_URL || "").trim();
  const token = (process.env.UPSTASH_REDIS_REST_TOKEN || "").trim();
  if (!base || !token) return null;
  const r = await fetch(base, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(command),
  });
  return r.json();
}

async function redisGet(key) {
  try {
    const j = await redisCommand(["GET", key]);
    if (!j?.result) return null;
    return JSON.parse(j.result);
  } catch {
    return null;
  }
}

async function redisSet(key, value, ttlSeconds = 60 * 60 * 24 * 14) {
  try {
    await redisCommand(["SET", key, JSON.stringify(value), "EX", ttlSeconds]);
  } catch {
    // cache is best-effort
  }
}

function cacheKey(videoId, steps) {
  const payload = steps.map((s) => `${s.id}|${s.title}|${s.instruction}`).join("\n");
  // cheap stable hash
  let h = 0;
  for (let i = 0; i < payload.length; i++) h = (Math.imul(31, h) + payload.charCodeAt(i)) | 0;
  return `cook:clips:v1:${videoId}:${h}`;
}

const SEGMENT_PROMPT = `Analyse this cooking video and identify every segment that would be
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
      "visual_quality": 0.0,
      "boundary_confidence": 0.0
    }
  ]
}

Keep each segment temporally tight. Prefer 6–25 second segments.
Do not infer an action merely because the chef mentions it.`;

function matchPrompt(recipeTitle, steps, segments) {
  return `You match recipe cook-steps to short video demonstration segments.

Recipe: ${recipeTitle}

Steps (JSON):
${JSON.stringify(steps, null, 2)}

Candidate segments (JSON):
${JSON.stringify(segments, null, 2)}

Rules:
- Prefer exact technique + ingredient matches for THIS recipe.
- If a step is mostly waiting/timer/bake with little visual value, return no_safe_match.
- A wrong clip is worse than no clip.
- Only recommend when the segment SHOWES the action, not just mentions it.
- One segment may match at most one step unless clearly reusable; prefer best step.
- Scores are 0..1.

Return JSON:
{
  "matches": [
    {
      "step_id": "",
      "segment_index": 0,
      "match_type": "exact_recipe" | "technique" | "target_state" | "no_safe_match",
      "action_match": 0.0,
      "ingredient_match": 0.0,
      "state_transition_match": 0.0,
      "visual_usefulness": 0.0,
      "conflicts": [],
      "shows_action_not_just_mentions_it": true,
      "recommended": true,
      "watch_label": "short UI label, e.g. Watch hollandaise emulsion",
      "notice": "one sentence Polly can say about what to notice"
    }
  ]
}

Include exactly one entry per step. Use recommended:false and match_type no_safe_match when unsure.`;
}

export async function handleCookClips(req, res) {
  res.setHeader("x-glutt-proxy-version", "cook-clips-2026-07-29-1");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }
  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const apiKey = resolveGeminiKey();
  if (!apiKey) {
    return res.status(500).json({ error: "Server misconfigured: missing GEMINI_API_KEY" });
  }

  const body = req.body || {};
  const youtubeURL = (body.youtube_url || body.youtubeURL || "").toString().trim();
  const recipeTitle = (body.recipe_title || body.recipeTitle || "Recipe").toString().trim();
  const stepsIn = Array.isArray(body.steps) ? body.steps : [];
  const force = Boolean(body.force);

  const videoId = youtubeVideoId(youtubeURL);
  if (!videoId) {
    return res.status(400).json({ error: "youtube_url must be a valid YouTube watch/youtu.be URL" });
  }
  if (stepsIn.length === 0) {
    return res.status(400).json({ error: "steps[] required" });
  }

  const steps = stepsIn.slice(0, 24).map((s, i) => ({
    id: String(s.id || `s${i + 1}`),
    title: String(s.title || "").slice(0, 120),
    instruction: String(s.instruction || s.text || "").slice(0, 500),
    kind: s.kind ? String(s.kind) : undefined,
  }));

  const key = cacheKey(videoId, steps);
  if (!force) {
    const cached = await redisGet(key);
    if (cached?.clips) {
      return res.status(200).json({ ...cached, cached: true });
    }
  }

  const model = resolveGeminiModel();
  const startedAt = Date.now();
  const canonicalURL = normalizeYoutubeURL(youtubeURL, videoId);

  try {
    // Pass 1 — segment the public YouTube URL (no download by Glutt).
    const pass1 = await geminiGenerate({
      apiKey,
      model,
      parts: [
        { file_data: { file_uri: canonicalURL } },
        { text: SEGMENT_PROMPT },
      ],
      json: true,
      temperature: 0.2,
    });
    const segDoc = parseJSONText(pass1.text);
    const segments = (Array.isArray(segDoc.segments) ? segDoc.segments : [])
      .filter((s) => s && s.is_action_clearly_visible !== false)
      .map(clampSegment)
      .slice(0, 40);

    if (segments.length === 0) {
      const empty = {
        youtube_video_id: videoId,
        youtube_url: canonicalURL,
        recipe_title: recipeTitle,
        segments: [],
        clips: [],
        model,
      };
      await redisSet(key, empty);
      await logUsage({
        feature: "cook_clips",
        model,
        install_id: installIdFrom(req),
        duration_ms: Date.now() - startedAt,
        ok: true,
      });
      return res.status(200).json({ ...empty, cached: false });
    }

    // Pass 2 — independent match/verify against recipe steps (text only).
    const pass2 = await geminiGenerate({
      apiKey,
      model,
      parts: [{ text: matchPrompt(recipeTitle, steps, segments) }],
      json: true,
      temperature: 0.1,
    });
    const matchDoc = parseJSONText(pass2.text);
    const matches = Array.isArray(matchDoc.matches) ? matchDoc.matches : [];

    const clips = [];
    for (const m of matches) {
      if (!m || m.recommended === false || m.match_type === "no_safe_match") continue;
      const idx = Number(m.segment_index);
      if (!Number.isInteger(idx) || idx < 0 || idx >= segments.length) continue;
      if (m.shows_action_not_just_mentions_it === false) continue;

      const scores = [
        Number(m.action_match) || 0,
        Number(m.ingredient_match) || 0,
        Number(m.state_transition_match) || 0,
        Number(m.visual_usefulness) || 0,
      ];
      const avg = scores.reduce((a, b) => a + b, 0) / scores.length;
      if (avg < MIN_RECOMMEND_SCORE) continue;

      const seg = segments[idx];
      const start = seg.start_seconds;
      const end = seg.end_seconds;
      const duration = Math.max(1, end - start);
      clips.push({
        step_id: String(m.step_id || ""),
        youtube_video_id: videoId,
        start_seconds: start,
        end_seconds: end,
        duration_seconds: duration,
        match_type: String(m.match_type || "technique"),
        confidence: Math.round(avg * 1000) / 1000,
        watch_label: String(m.watch_label || `Watch technique · ${duration}s`).slice(0, 80),
        notice: String(m.notice || "").slice(0, 240),
        primary_action: seg.primary_action || "",
        visual_cue: seg.visual_cue_taught || "",
      });
    }

    // Deduplicate: keep highest-confidence clip per step.
    const byStep = new Map();
    for (const c of clips) {
      if (!c.step_id) continue;
      const prev = byStep.get(c.step_id);
      if (!prev || c.confidence > prev.confidence) byStep.set(c.step_id, c);
    }

    const result = {
      youtube_video_id: videoId,
      youtube_url: canonicalURL,
      recipe_title: recipeTitle,
      segments,
      clips: Array.from(byStep.values()),
      model,
    };

    await redisSet(key, result);
    await logUsage({
      feature: "cook_clips",
      model,
      install_id: installIdFrom(req),
      duration_ms: Date.now() - startedAt,
      ok: true,
    });

    return res.status(200).json({ ...result, cached: false });
  } catch (error) {
    await logUsage({
      feature: "cook_clips",
      model,
      install_id: installIdFrom(req),
      duration_ms: Date.now() - startedAt,
      ok: false,
    });
    const status = error.status && error.status >= 400 && error.status < 600 ? error.status : 502;
    return res.status(status).json({
      error: error.message || "Clip indexing failed",
      detail: error.body || undefined,
    });
  }
}
