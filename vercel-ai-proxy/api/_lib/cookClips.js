// Auto-index short YouTube demonstration windows for CookPlan steps.
//
// Layers:
//   A) grounded (preferred): one Gemini video call that uses spoken audio +
//      visible action, with an explicit video duration ceiling so timestamps
//      cannot drift past the end of the video.
//   B) legacy two-pass: free segmentation → text match (kept as fallback).
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

const MIN_SEGMENT_S = 8;
const MAX_SEGMENT_S = 30;
const MIN_RECOMMEND_SCORE = 0.72;

/** Known lengths — Gemini often invents times past EOF without this. */
const KNOWN_DURATIONS = {
  gBJjRYk0yC0: 274, // How To Cook Eggs Benedict | Gordon Ramsay (4:34)
};

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

function normalizeYoutubeURL(_url, videoId) {
  return `https://www.youtube.com/watch?v=${videoId}`;
}

function videoDuration(videoId, bodyDuration) {
  const n = Number(bodyDuration);
  if (Number.isFinite(n) && n > 0) return Math.round(n);
  return KNOWN_DURATIONS[videoId] || null;
}

function clampWindow(startIn, endIn, durationSeconds) {
  let start = Math.round(Number(startIn));
  let end = Math.round(Number(endIn));
  if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start) return null;
  if (durationSeconds != null) {
    if (start >= durationSeconds) return null;
    end = Math.min(end, durationSeconds);
  }
  if (end <= start) return null;
  if (end - start < MIN_SEGMENT_S) {
    end = Math.min(start + MIN_SEGMENT_S, durationSeconds ?? start + MIN_SEGMENT_S);
  }
  if (end <= start) return null;
  if (end - start > MAX_SEGMENT_S) end = start + MAX_SEGMENT_S;
  // Reject classic junk intro window.
  if (start <= 5 && end - start <= 10) return null;
  return { start_seconds: start, end_seconds: end };
}

function clampSegment(seg, durationSeconds = null) {
  const win = clampWindow(seg.start_seconds, seg.end_seconds, durationSeconds);
  if (!win) return null;
  return { ...seg, ...win };
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
    // best-effort
  }
}

function clipsCacheKey(videoId, steps) {
  const payload = steps.map((s) => `${s.id}|${s.title}|${s.instruction}`).join("\n");
  let h = 0;
  for (let i = 0; i < payload.length; i++) h = (Math.imul(31, h) + payload.charCodeAt(i)) | 0;
  return `cook:clips:v3:${videoId}:${h}`;
}

function segmentsCacheKey(videoId) {
  return `cook:segments:v3:${videoId}`;
}

function segmentPrompt(durationSeconds) {
  const durLine = durationSeconds
    ? `This video is EXACTLY ${durationSeconds} seconds long. Every timestamp MUST be between 0 and ${durationSeconds}.`
    : `Use real timestamps from the video timeline.`;
  return `${durLine}

Analyse this cooking video using BOTH what is spoken and what is visibly demonstrated.
Identify up to 12 short segments useful as visual demos while someone cooks.

Only include segments where the cooking action or food state is clearly visible on camera.
Skip intros, title cards, talking heads with no food action, sponsors, and plating glamour shots unless needed for doneness.

Return JSON:
{"segments":[{"start_seconds":0,"end_seconds":0,"primary_action":"","ingredients_visible":[],"tools_visible":[],"starting_state":"","ending_state":"","technique":"","dish_stage":"","visual_cue_taught":"","spoken_instruction_summary":"","is_action_clearly_visible":true,"visual_quality":0.0,"boundary_confidence":0.0}]}

Prefer 8–25 second segments. Do not invent actions that are only mentioned off-camera.`;
}

function matchPrompt(recipeTitle, steps, segments) {
  return `Match recipe cook-steps to video demonstration segments.

Recipe: ${recipeTitle}

Steps:
${JSON.stringify(steps)}

Segments (use these exact indexes and timestamps — do not invent new times):
${JSON.stringify(segments.map((s, i) => ({
    index: i,
    start_seconds: s.start_seconds,
    end_seconds: s.end_seconds,
    primary_action: s.primary_action,
    technique: s.technique,
    spoken_instruction_summary: s.spoken_instruction_summary,
    visual_cue_taught: s.visual_cue_taught,
  })))}

Rules:
- segment_index MUST be the segment that visually shows the step's action.
- Prefer segments whose spoken_instruction_summary also refers to the same action.
- Never recommend intro/title segments.
- Wrong clip is worse than none.

Return JSON:
{"matches":[{"step_id":"","segment_index":0,"match_type":"exact_recipe|technique|target_state|no_safe_match","action_match":0.0,"ingredient_match":0.0,"state_transition_match":0.0,"visual_usefulness":0.0,"conflicts":[],"shows_action_not_just_mentions_it":true,"recommended":true,"watch_label":"short label","notice":"one sentence about what to notice"}]}

One entry per step. recommended:false + no_safe_match when unsure.`;
}

function groundPrompt(recipeTitle, steps, durationSeconds) {
  const durLine = durationSeconds
    ? `This video is EXACTLY ${durationSeconds} seconds long. start_seconds and end_seconds MUST be integers in [0, ${durationSeconds}].`
    : `Use real timeline seconds from the video.`;
  return `${durLine}

You are locating short technique clips for a cook-along app.
Use BOTH:
1) what the chef SAYS (audio / narration), and
2) what is VISIBLY happening on screen.

For each recipe step, choose the single best 8–25 second window where the step's action is clearly demonstrated on camera.
If the chef only talks about it without showing it, do not recommend that step.

Recipe: ${recipeTitle}

Steps:
${JSON.stringify(steps)}

Return JSON:
{"clips":[{"step_id":"","start_seconds":0,"end_seconds":0,"spoken_evidence":"short quote or paraphrase of relevant speech","visual_evidence":"what is on screen in this window","confidence":0.0,"watch_label":"short UI label","notice":"one sentence about what to notice","recommended":true}]}

Include one object per step. Set recommended:false when there is no safe visual match.
Never return a window that starts at 0 unless cooking action truly begins in the opening seconds.`;
}

function normalizeSteps(stepsIn) {
  return stepsIn.slice(0, 24).map((s, i) => ({
    id: String(s.id || `s${i + 1}`),
    title: String(s.title || "").slice(0, 120),
    instruction: String(s.instruction || s.text || "").slice(0, 500),
    kind: s.kind ? String(s.kind) : undefined,
  }));
}

function buildClipsFromMatches(matches, segments, videoId) {
  const clips = [];
  for (const m of matches) {
    if (!m || m.recommended === false || m.match_type === "no_safe_match") continue;
    const idx = Number(m.segment_index);
    if (!Number.isInteger(idx) || idx < 0 || idx >= segments.length) continue;
    if (m.shows_action_not_just_mentions_it === false) continue;
    const seg = segments[idx];
    if (!seg) continue;
    const scores = [
      Number(m.action_match) || 0,
      Number(m.ingredient_match) || 0,
      Number(m.state_transition_match) || 0,
      Number(m.visual_usefulness) || 0,
    ];
    const avg = scores.reduce((a, b) => a + b, 0) / scores.length;
    if (avg < MIN_RECOMMEND_SCORE) continue;
    const duration = Math.max(1, seg.end_seconds - seg.start_seconds);
    clips.push({
      step_id: String(m.step_id || ""),
      youtube_video_id: videoId,
      start_seconds: seg.start_seconds,
      end_seconds: seg.end_seconds,
      duration_seconds: duration,
      match_type: String(m.match_type || "technique"),
      confidence: Math.round(avg * 1000) / 1000,
      watch_label: String(m.watch_label || `Watch · ${duration}s`).slice(0, 80),
      notice: String(m.notice || "").slice(0, 240),
      primary_action: seg.primary_action || "",
      visual_cue: seg.visual_cue_taught || "",
    });
  }
  const byStep = new Map();
  for (const c of clips) {
    if (!c.step_id) continue;
    const prev = byStep.get(c.step_id);
    if (!prev || c.confidence > prev.confidence) byStep.set(c.step_id, c);
  }
  return Array.from(byStep.values());
}

function buildClipsFromGround(rawClips, videoId, durationSeconds) {
  const clips = [];
  for (const c of rawClips || []) {
    if (!c || c.recommended === false) continue;
    const win = clampWindow(c.start_seconds, c.end_seconds, durationSeconds);
    if (!win) continue;
    const confidence = Number(c.confidence) || 0;
    if (confidence < MIN_RECOMMEND_SCORE) continue;
    const duration = win.end_seconds - win.start_seconds;
    clips.push({
      step_id: String(c.step_id || ""),
      youtube_video_id: videoId,
      start_seconds: win.start_seconds,
      end_seconds: win.end_seconds,
      duration_seconds: duration,
      match_type: "grounded",
      confidence: Math.round(confidence * 1000) / 1000,
      watch_label: String(c.watch_label || `Watch · ${duration}s`).slice(0, 80),
      notice: String(c.notice || c.visual_evidence || "").slice(0, 240),
      primary_action: String(c.visual_evidence || "").slice(0, 120),
      visual_cue: String(c.spoken_evidence || "").slice(0, 240),
    });
  }
  const byStep = new Map();
  for (const c of clips) {
    if (!c.step_id) continue;
    const prev = byStep.get(c.step_id);
    if (!prev || c.confidence > prev.confidence) byStep.set(c.step_id, c);
  }
  return Array.from(byStep.values());
}

async function runGround({ apiKey, model, videoId, canonicalURL, recipeTitle, steps, durationSeconds, force }) {
  const key = clipsCacheKey(videoId, steps) + ":ground";
  if (!force) {
    const cached = await redisGet(key);
    if (cached?.clips) return { ...cached, cached: true };
  }

  const pass = await geminiGenerate({
    apiKey,
    model,
    parts: [
      { file_data: { file_uri: canonicalURL } },
      { text: groundPrompt(recipeTitle, steps, durationSeconds) },
    ],
    json: true,
    temperature: 0.1,
  });
  const doc = parseJSONText(pass.text);
  const clips = buildClipsFromGround(doc.clips, videoId, durationSeconds);
  const result = {
    youtube_video_id: videoId,
    youtube_url: canonicalURL,
    recipe_title: recipeTitle,
    clips,
    model,
    method: "grounded_av",
    duration_seconds: durationSeconds,
  };
  await redisSet(key, result);
  return { ...result, cached: false };
}

async function runSegment({ apiKey, model, videoId, canonicalURL, durationSeconds, force }) {
  const segKey = segmentsCacheKey(videoId);
  if (!force) {
    const cached = await redisGet(segKey);
    if (cached?.segments) return { segments: cached.segments, cached: true, model: cached.model || model };
  }

  const pass1 = await geminiGenerate({
    apiKey,
    model,
    parts: [
      { file_data: { file_uri: canonicalURL } },
      { text: segmentPrompt(durationSeconds) },
    ],
    json: true,
    temperature: 0.2,
  });
  const segDoc = parseJSONText(pass1.text);
  const segments = (Array.isArray(segDoc.segments) ? segDoc.segments : [])
    .filter((s) => s && s.is_action_clearly_visible !== false)
    .map((s) => clampSegment(s, durationSeconds))
    .filter(Boolean)
    .slice(0, 12);

  const payload = { youtube_video_id: videoId, youtube_url: canonicalURL, segments, model };
  await redisSet(segKey, payload);
  return { segments, cached: false, model };
}

async function runMatch({ apiKey, model, videoId, canonicalURL, recipeTitle, steps, segments, force }) {
  const key = clipsCacheKey(videoId, steps);
  if (!force) {
    const cached = await redisGet(key);
    if (cached?.clips) return { ...cached, cached: true };
  }

  if (!segments.length) {
    const empty = {
      youtube_video_id: videoId,
      youtube_url: canonicalURL,
      recipe_title: recipeTitle,
      segments: [],
      clips: [],
      model,
    };
    await redisSet(key, empty);
    return { ...empty, cached: false };
  }

  const pass2 = await geminiGenerate({
    apiKey,
    model,
    parts: [{ text: matchPrompt(recipeTitle, steps, segments) }],
    json: true,
    temperature: 0.1,
  });
  const matchDoc = parseJSONText(pass2.text);
  const matches = Array.isArray(matchDoc.matches) ? matchDoc.matches : [];
  const clips = buildClipsFromMatches(matches, segments, videoId);
  const result = {
    youtube_video_id: videoId,
    youtube_url: canonicalURL,
    recipe_title: recipeTitle,
    segments,
    clips,
    model,
    method: "segment_match",
  };
  await redisSet(key, result);
  return { ...result, cached: false };
}

export async function handleCookClips(req, res) {
  res.setHeader("x-glutt-proxy-version", "cook-clips-2026-07-29-3");

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
  const phase = (body.phase || "ground").toString(); // ground | segment | match | auto

  const videoId = youtubeVideoId(youtubeURL);
  if (!videoId) {
    return res.status(400).json({ error: "youtube_url must be a valid YouTube watch/youtu.be URL" });
  }

  const steps = normalizeSteps(stepsIn);
  const model = resolveGeminiModel();
  const startedAt = Date.now();
  const canonicalURL = normalizeYoutubeURL(youtubeURL, videoId);
  const durationSeconds = videoDuration(videoId, body.duration_seconds);

  try {
    if (phase === "ground") {
      if (steps.length === 0) {
        return res.status(400).json({ error: "steps[] required for ground phase" });
      }
      const out = await runGround({
        apiKey,
        model,
        videoId,
        canonicalURL,
        recipeTitle,
        steps,
        durationSeconds,
        force,
      });
      await logUsage({
        feature: "cook_clips_ground",
        model,
        install_id: installIdFrom(req),
        duration_ms: Date.now() - startedAt,
        ok: true,
      });
      return res.status(200).json({ ...out, phase: "ground" });
    }

    if (phase === "segment") {
      const out = await runSegment({ apiKey, model, videoId, canonicalURL, durationSeconds, force });
      await logUsage({
        feature: "cook_clips_segment",
        model: out.model || model,
        install_id: installIdFrom(req),
        duration_ms: Date.now() - startedAt,
        ok: true,
      });
      return res.status(200).json({
        phase: "segment",
        youtube_video_id: videoId,
        youtube_url: canonicalURL,
        segments: out.segments,
        cached: out.cached,
        model: out.model || model,
        duration_seconds: durationSeconds,
      });
    }

    if (phase === "match") {
      if (steps.length === 0) {
        return res.status(400).json({ error: "steps[] required for match phase" });
      }
      let segments = Array.isArray(body.segments)
        ? body.segments.map((s) => clampSegment(s, durationSeconds)).filter(Boolean)
        : null;
      if (!segments) {
        const cachedSeg = await redisGet(segmentsCacheKey(videoId));
        segments = cachedSeg?.segments || [];
      }
      const out = await runMatch({
        apiKey,
        model,
        videoId,
        canonicalURL,
        recipeTitle,
        steps,
        segments,
        force,
      });
      await logUsage({
        feature: "cook_clips_match",
        model,
        install_id: installIdFrom(req),
        duration_ms: Date.now() - startedAt,
        ok: true,
      });
      return res.status(200).json({ ...out, phase: "match" });
    }

    // auto → grounded path
    if (steps.length === 0) {
      return res.status(400).json({ error: "steps[] required" });
    }
    const out = await runGround({
      apiKey,
      model,
      videoId,
      canonicalURL,
      recipeTitle,
      steps,
      durationSeconds,
      force,
    });
    await logUsage({
      feature: "cook_clips",
      model,
      install_id: installIdFrom(req),
      duration_ms: Date.now() - startedAt,
      ok: true,
    });
    return res.status(200).json({ ...out, phase: "auto" });
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
