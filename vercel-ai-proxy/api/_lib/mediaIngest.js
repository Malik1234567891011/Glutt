/**
 * Control-plane media ingest API.
 * Creates rights/jobs in Supabase; optional Gemini index for YouTube (fast path).
 * Native MP4 materialization stays on media-worker (claimSupabaseJobs).
 */
import { isAuthorized } from "./auth.js";
import { sb, sbUpsert, supabaseConfigured } from "./supabase.js";
import { resolveGeminiKey, resolveGeminiModel } from "./gemini.js";
import { indexYouTubeClips } from "./cookClips.js";
import { logUsage, installIdFrom } from "./usage.js";

function youtubeId(url) {
  try {
    const u = new URL(url);
    if (u.hostname.includes("youtu.be")) return u.pathname.split("/").filter(Boolean)[0] || null;
    if (u.hostname.includes("youtube.com")) return u.searchParams.get("v");
  } catch {
    /* ignore */
  }
  return null;
}

function tiktokId(url) {
  try {
    const u = new URL(url);
    if (!u.hostname.toLowerCase().includes("tiktok.com")) return null;
    const parts = u.pathname.split("/").filter(Boolean);
    const idx = parts.indexOf("video");
    if (idx >= 0 && parts[idx + 1] && /^\d+$/.test(parts[idx + 1])) return parts[idx + 1];
  } catch {
    /* ignore */
  }
  return null;
}

function detectPlatform(url) {
  try {
    const h = new URL(url).hostname.toLowerCase();
    if (h.includes("youtube") || h === "youtu.be") return "youtube";
    if (h.includes("tiktok")) return "tiktok";
    if (h.includes("instagram")) return "instagram";
    return "web";
  } catch {
    return "other";
  }
}

function externalIdFor(url, platform) {
  if (platform === "youtube") return youtubeId(url);
  if (platform === "tiktok") return tiktokId(url);
  return null;
}

async function findAssetByExternal(platform, externalId) {
  if (!externalId) return null;
  const rows = await sb(
    `source_assets?platform=eq.${encodeURIComponent(platform)}&external_id=eq.${encodeURIComponent(externalId)}&status=neq.revoked&select=*&order=created_at.desc&limit=1`
  );
  return rows?.[0] || null;
}

async function latestJobForAsset(assetId) {
  const rows = await sb(
    `ingestion_jobs?source_asset_id=eq.${encodeURIComponent(assetId)}&select=*&order=created_at.desc&limit=1`
  );
  return rows?.[0] || null;
}

async function ensureRights(sourceUrl, platform, externalId, body) {
  const rows = await sb("rights_records", {
    method: "POST",
    body: {
      source_url: sourceUrl,
      platform,
      external_id: externalId,
      clearance_notes: body.clearance_notes || "User-imported recipe source (product-cleared ingest).",
      cleared_by: body.cleared_by || "import",
      license_type: body.license_type || "user_import",
    },
  });
  return rows?.[0] || rows;
}

async function enqueueIngest(sourceUrl, body) {
  const platform = detectPlatform(sourceUrl);
  const externalId = externalIdFor(sourceUrl, platform);
  if (!externalId) {
    const err = new Error("Could not extract media id from URL (need YouTube watch or TikTok /video/<id>)");
    err.status = 400;
    throw err;
  }

  let asset = await findAssetByExternal(platform, externalId);
  if (asset) {
    const job = await latestJobForAsset(asset.id);
    return {
      ok: true,
      reused: true,
      platform,
      external_id: externalId,
      source_asset: asset,
      job: job || null,
    };
  }

  const rights = await ensureRights(sourceUrl, platform, externalId, body);
  const assets = await sb("source_assets", {
    method: "POST",
    body: {
      platform,
      source_url: sourceUrl,
      external_id: externalId,
      rights_record_id: rights.id,
      status: "queued",
      title: body.title || null,
      creator_name: body.creator_name || null,
    },
  });
  asset = assets?.[0];
  const jobs = await sb("ingestion_jobs", {
    method: "POST",
    body: {
      source_asset_id: asset.id,
      job_type: "full_ingest",
      status: "queued",
      stage: "queued",
      progress: 0,
    },
  });
  const job = jobs?.[0];

  // Optional: poke a worker webhook (non-blocking best-effort).
  const webhook = (process.env.MEDIA_WORKER_WEBHOOK || "").trim();
  if (webhook) {
    fetch(webhook, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        action: "claim",
        source_asset_id: asset.id,
        job_id: job?.id,
        source_url: sourceUrl,
        external_id: externalId,
        platform,
      }),
    }).catch(() => {});
  }

  return {
    ok: true,
    reused: false,
    platform,
    external_id: externalId,
    source_asset: asset,
    job,
  };
}

async function persistGeminiClips(asset, clips) {
  const now = new Date().toISOString();
  const segments = [];
  for (const c of clips || []) {
    if (c.recommended === false) continue;
    const start = Number(c.start_seconds);
    const end = Number(c.end_seconds);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) continue;
    const stepId = String(c.step_id || "").trim() || `t${start}`;
    const id = `seg-${asset.external_id}-${stepId}`.replace(/[^a-zA-Z0-9_-]/g, "-").slice(0, 120);
    const keywords = [
      ...(Array.isArray(c.ingredients) ? c.ingredients : []),
      c.primary_action,
      ...(String(c.watch_label || "").toLowerCase().split(/\s+/)),
    ]
      .filter(Boolean)
      .map(String)
      .slice(0, 12);
    segments.push({
      id,
      source_asset_id: asset.id,
      start_seconds: start,
      end_seconds: end,
      primary_action: c.primary_action || null,
      secondary_actions_json: [],
      ingredients_json: Array.isArray(c.ingredients) ? c.ingredients : [],
      tools_json: [],
      technique: c.technique || null,
      visual_cue: c.notice || c.visual_evidence || null,
      audio_useful: true,
      visual_quality: Number(c.confidence) || 0.7,
      boundary_confidence: Number(c.confidence) || 0.7,
      review_status: "approved",
      model_version: "gemini-ground-refine",
      notice: c.notice || null,
      watch_label: c.watch_label || "Watch example",
      step_keywords_json: keywords,
      created_at: now,
      updated_at: now,
    });
  }
  if (segments.length) {
    await sbUpsert("semantic_segments", segments, "id");
  }
  return segments.length;
}

async function statusByExternal(externalId) {
  const rows = await sb(
    `source_assets?external_id=eq.${encodeURIComponent(externalId)}&status=neq.revoked&select=*&order=created_at.desc&limit=1`
  );
  const asset = rows?.[0] || null;
  if (!asset) return { ok: true, found: false, external_id: externalId };
  const job = await latestJobForAsset(asset.id);
  const segs = await sb(
    `semantic_segments?source_asset_id=eq.${encodeURIComponent(asset.id)}&review_status=eq.approved&select=id`
  );
  const approvedCount = segs?.length || 0;
  let readyClips = 0;
  if (approvedCount > 0) {
    const inList = `(${segs.map((s) => `"${String(s.id).replace(/"/g, "")}"`).join(",")})`;
    const clips = await sb(
      `clip_assets?segment_id=in.${inList}&status=eq.ready&select=id`
    ).catch(() => []);
    readyClips = clips?.length || 0;
  }
  const nativeReady = readyClips > 0;
  const indexed = approvedCount > 0;
  return {
    ok: true,
    found: true,
    external_id: externalId,
    source_asset: asset,
    job,
    approved_segments: approvedCount,
    ready_clips: readyClips,
    // Client-facing rollup
    media_status: asset.status === "failed"
      ? "failed"
      : nativeReady
        ? "ready"
        : indexed
          ? "indexed"
          : asset.status || "queued",
    progress: nativeReady
      ? 1
      : indexed
        ? 0.55
        : Number(job?.progress || 0),
    detail: nativeReady
      ? "Technique clips ready"
      : indexed
        ? "Moments indexed — preparing HD clips…"
        : (job?.stage || asset.status || "queued"),
  };
}

export async function handleMediaIngest(req, res) {
  res.setHeader("x-glutt-proxy-version", "media-ingest-2026-07-31-1");
  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const body = req.body || {};
  const action = (body.action || req.query?.action || "status").toString();

  try {
    if (req.method === "GET" || action === "status") {
      if (!supabaseConfigured()) {
        return res.status(503).json({ error: "Supabase not configured" });
      }
      const externalId = (body.external_id || req.query?.external_id || "").toString().trim();
      if (externalId) return res.status(200).json(await statusByExternal(externalId));
      const jobId = (body.job_id || req.query?.job_id || "").toString();
      const assetId = (body.source_asset_id || req.query?.source_asset_id || "").toString();
      if (jobId) {
        const rows = await sb(`ingestion_jobs?id=eq.${encodeURIComponent(jobId)}&select=*`);
        return res.status(200).json({ job: rows?.[0] || null });
      }
      if (assetId) {
        const rows = await sb(`source_assets?id=eq.${encodeURIComponent(assetId)}&select=*`);
        return res.status(200).json({ source_asset: rows?.[0] || null });
      }
      return res.status(400).json({ error: "external_id, job_id, or source_asset_id required" });
    }

    if (req.method !== "POST") {
      res.setHeader("Allow", "GET, POST");
      return res.status(405).json({ error: "Method not allowed" });
    }

    if (!supabaseConfigured()) {
      return res.status(503).json({ error: "Supabase not configured" });
    }

    if (action === "enqueue") {
      const sourceUrl = (body.source_url || "").toString().trim();
      if (!sourceUrl) return res.status(400).json({ error: "source_url required" });
      const out = await enqueueIngest(sourceUrl, body);
      return res.status(200).json(out);
    }

    if (action === "create_rights") {
      const sourceUrl = (body.source_url || "").toString().trim();
      if (!sourceUrl) return res.status(400).json({ error: "source_url required" });
      const platform = detectPlatform(sourceUrl);
      const externalId = externalIdFor(sourceUrl, platform);
      const rights = await ensureRights(sourceUrl, platform, externalId, body);
      return res.status(200).json({ rights_record: rights });
    }

    if (action === "create_job") {
      const sourceUrl = (body.source_url || "").toString().trim();
      if (!sourceUrl) return res.status(400).json({ error: "source_url required" });
      const out = await enqueueIngest(sourceUrl, body);
      return res.status(200).json(out);
    }

    if (action === "analyze") {
      // Fast path: Gemini ground+refine → semantic_segments (YouTube only).
      // Does not block import; client calls after enqueue with recipe steps.
      const sourceUrl = (body.source_url || "").toString().trim();
      const externalId = (body.external_id || "").toString().trim() || youtubeId(sourceUrl);
      if (!externalId) return res.status(400).json({ error: "external_id or youtube source_url required" });
      const platform = detectPlatform(sourceUrl || `https://www.youtube.com/watch?v=${externalId}`);
      if (platform !== "youtube") {
        return res.status(200).json({
          ok: true,
          skipped: true,
          reason: "Gemini URL analysis is YouTube-only; TikTok waits for media-worker download",
          external_id: externalId,
        });
      }
      const apiKey = resolveGeminiKey();
      if (!apiKey) return res.status(500).json({ error: "missing GEMINI_API_KEY" });

      let asset = await findAssetByExternal("youtube", externalId);
      if (!asset) {
        const enq = await enqueueIngest(
          sourceUrl || `https://www.youtube.com/watch?v=${externalId}`,
          body
        );
        asset = enq.source_asset;
      }

      await sb(`source_assets?id=eq.${encodeURIComponent(asset.id)}`, {
        method: "PATCH",
        body: { status: "analysing", updated_at: new Date().toISOString() },
      });
      if (asset.id) {
        const job = await latestJobForAsset(asset.id);
        if (job?.id) {
          await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
            method: "PATCH",
            body: {
              status: "running",
              stage: "gemini_index",
              progress: 0.35,
              updated_at: new Date().toISOString(),
            },
          });
        }
      }

      const steps = Array.isArray(body.steps) ? body.steps : [];
      const recipeTitle = (body.recipe_title || body.title || asset.title || "Recipe").toString();
      const startedAt = Date.now();
      const indexed = await indexYouTubeClips({
        apiKey,
        model: resolveGeminiModel(),
        youtubeURL: sourceUrl || `https://www.youtube.com/watch?v=${externalId}`,
        recipeTitle,
        steps,
        force: Boolean(body.force),
        durationSeconds: body.duration_seconds,
      });
      const count = await persistGeminiClips(asset, indexed.clips || []);
      await sb(`source_assets?id=eq.${encodeURIComponent(asset.id)}`, {
        method: "PATCH",
        body: {
          status: "analysing",
          title: asset.title || recipeTitle,
          duration_seconds: indexed.duration_seconds ?? asset.duration_seconds,
          updated_at: new Date().toISOString(),
        },
      });
      const job = await latestJobForAsset(asset.id);
      if (job?.id) {
        await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
          method: "PATCH",
          body: {
            status: "running",
            stage: "indexed_awaiting_native",
            progress: 0.55,
            updated_at: new Date().toISOString(),
          },
        });
      }
      await logUsage({
        feature: "media_analyze",
        model: indexed.model || resolveGeminiModel(),
        install_id: installIdFrom(req),
        duration_ms: Date.now() - startedAt,
        ok: true,
      });
      return res.status(200).json({
        ok: true,
        external_id: externalId,
        source_asset_id: asset.id,
        segments_written: count,
        clips: indexed.clips || [],
        media_status: "indexed",
        progress: 0.55,
        detail: "Moments indexed — preparing HD clips…",
      });
    }

    if (action === "revoke") {
      const assetId = (body.source_asset_id || "").toString().trim();
      if (!assetId) return res.status(400).json({ error: "source_asset_id required" });
      const rows = await sb(`source_assets?id=eq.${encodeURIComponent(assetId)}`, {
        method: "PATCH",
        body: { status: "revoked" },
      });
      return res.status(200).json({ source_asset: rows?.[0], status: "revoked" });
    }

    return res.status(400).json({ error: `Unknown action: ${action}` });
  } catch (err) {
    return res.status(err.status || 500).json({
      error: err.message || "media ingest failed",
      details: err.body || undefined,
    });
  }
}
