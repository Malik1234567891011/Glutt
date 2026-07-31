/**
 * Runtime clip manifest for Polly native playback.
 * Reads approved segments + clip_assets from Supabase, mints signed Storage URLs.
 *
 * Shape matches iOS NativePilotClipsResponse (snake_case).
 */
import { isAuthorized } from "./auth.js";
import { sb, signStoragePaths, supabaseConfigured } from "./supabase.js";

const SIGN_TTL_SECONDS = 60 * 60; // 1 hour

function pickExternalId(req, body) {
  return (
    body.external_id ||
    body.media_id ||
    body.youtube_id ||
    req.query?.external_id ||
    req.query?.media_id ||
    req.query?.youtube_id ||
    ""
  )
    .toString()
    .trim();
}

function keywordsFrom(seg) {
  const raw = seg.step_keywords_json;
  if (Array.isArray(raw)) return raw.map(String);
  return [];
}

export async function handleMediaClips(req, res) {
  res.setHeader("x-glutt-proxy-version", "media-clips-2026-07-30-1");
  res.setHeader("Cache-Control", "private, max-age=60");

  if (req.method !== "GET" && req.method !== "POST") {
    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  if (!supabaseConfigured()) {
    return res.status(503).json({
      error: "Supabase not configured",
      hint: "Set SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY on the proxy",
    });
  }

  const body = req.body || {};
  const externalId = pickExternalId(req, body);
  if (!externalId) {
    return res.status(400).json({ error: "external_id (or media_id) required" });
  }

  try {
    const assets = await sb(
      `source_assets?external_id=eq.${encodeURIComponent(externalId)}&status=neq.revoked&select=*&limit=1`
    );
    const asset = assets?.[0];
    if (!asset) {
      return res.status(404).json({
        error: "source asset not found",
        external_id: externalId,
        hint: "Run media-worker npm run sync:supabase after applying migration 0011",
      });
    }

    const segments = await sb(
      `semantic_segments?source_asset_id=eq.${encodeURIComponent(asset.id)}&review_status=eq.approved&order=start_seconds.asc&select=*`
    );
    if (!segments?.length) {
      return res.status(404).json({
        error: "no approved segments",
        source_asset_id: asset.id,
        external_id: externalId,
      });
    }

    const segIds = segments.map((s) => s.id);
    const inList = `(${segIds.map((id) => `"${String(id).replace(/"/g, "")}"`).join(",")})`;
    const clips = await sb(
      `clip_assets?segment_id=in.${inList}&status=eq.ready&select=*`
    );
    const clipBySeg = Object.fromEntries((clips || []).map((c) => [c.segment_id, c]));

    const paths = [];
    for (const seg of segments) {
      const clip = clipBySeg[seg.id] || {};
      paths.push(clip.vertical_object_key || clip.object_key);
      paths.push(clip.poster_object_key);
    }
    const signed = await signStoragePaths(paths, { expiresIn: SIGN_TTL_SECONDS });

    const outClips = [];
    for (const seg of segments) {
      const clip = clipBySeg[seg.id] || {};
      const playbackKey = clip.vertical_object_key || clip.object_key;
      const playbackURL = playbackKey ? signed[playbackKey] : null;
      if (!playbackURL) continue;
      const posterKey = clip.poster_object_key;
      outClips.push({
        segment_id: seg.id,
        start_seconds: Number(seg.start_seconds),
        end_seconds: Number(seg.end_seconds),
        duration_seconds: Number(
          clip.duration_seconds ?? (Number(seg.end_seconds) - Number(seg.start_seconds))
        ),
        watch_label: clip.teaching_label || seg.watch_label || "Watch example",
        teaching_label: clip.teaching_label || seg.watch_label || null,
        notice: seg.notice || "",
        visual_cue: seg.visual_cue || "",
        step_keywords: keywordsFrom(seg),
        presentation_mode: clip.presentation_mode || (clip.vertical_object_key ? "nativeVertical" : "landscape"),
        playback_url: playbackURL,
        thumbnail_url: posterKey ? signed[posterKey] || null : null,
        master_url: null,
        uses_virtual_range: false,
        creator_attribution: asset.creator_name || null,
      });
    }

    if (!outClips.length) {
      return res.status(404).json({
        error: "clips not uploaded to storage",
        source_asset_id: asset.id,
        hint: "Run: cd media-worker && npm run sync:supabase",
      });
    }

    return res.status(200).json({
      source_asset_id: asset.id,
      status: asset.status,
      duration_seconds: asset.duration_seconds != null ? Number(asset.duration_seconds) : null,
      title: asset.title || null,
      external_id: externalId,
      expires_in: SIGN_TTL_SECONDS,
      clips: outClips,
    });
  } catch (err) {
    return res.status(err.status || 500).json({
      error: err.message || "media clips failed",
      details: err.body || undefined,
    });
  }
}
