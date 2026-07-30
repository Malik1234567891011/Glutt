/**
 * Control-plane media ingest API (docs/downloadplanPhases.md Phase 0).
 * Does NOT download or transcode — only rights/jobs/status/revoke/token stubs.
 *
 * Backed by optional Supabase service role; falls back to forwarding job create
 * metadata to the media-worker when MEDIA_WORKER_WEBHOOK is set. For local
 * overnight work the worker CLI owns the LocalStore directly.
 */
import { isAuthorized } from "./auth.js";

function supabaseConfigured() {
  return Boolean(
    (process.env.SUPABASE_URL || "").trim() &&
      (process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim()
  );
}

async function sb(path, { method = "GET", body } = {}) {
  const base = (process.env.SUPABASE_URL || "").replace(/\/$/, "");
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const r = await fetch(`${base}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      Prefer: method === "POST" ? "return=representation" : "return=representation",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  if (!r.ok) {
    const err = new Error(json?.message || json?.error || text || `supabase ${r.status}`);
    err.status = r.status;
    err.body = json;
    throw err;
  }
  return json;
}

function youtubeId(url) {
  try {
    const u = new URL(url);
    if (u.hostname.includes("youtu.be")) return u.pathname.split("/").filter(Boolean)[0];
    return u.searchParams.get("v");
  } catch {
    return null;
  }
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

export async function handleMediaIngest(req, res) {
  res.setHeader("x-glutt-proxy-version", "media-ingest-2026-07-30-1");
  if (!isAuthorized(req)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const body = req.body || {};
  const action = (body.action || req.query?.action || "status").toString();

  try {
    if (req.method === "GET" || action === "status") {
      const jobId = (body.job_id || req.query?.job_id || "").toString();
      const assetId = (body.source_asset_id || req.query?.source_asset_id || "").toString();
      if (!supabaseConfigured()) {
        return res.status(200).json({
          ok: true,
          mode: "control_plane_stub",
          message: "Supabase not configured on proxy; use media-worker LocalStore / CLI for pilot.",
          action,
          job_id: jobId || null,
          source_asset_id: assetId || null,
        });
      }
      if (jobId) {
        const rows = await sb(`ingestion_jobs?id=eq.${encodeURIComponent(jobId)}&select=*`);
        return res.status(200).json({ job: rows?.[0] || null });
      }
      if (assetId) {
        const rows = await sb(`source_assets?id=eq.${encodeURIComponent(assetId)}&select=*`);
        return res.status(200).json({ source_asset: rows?.[0] || null });
      }
      return res.status(400).json({ error: "job_id or source_asset_id required" });
    }

    if (req.method !== "POST") {
      res.setHeader("Allow", "GET, POST");
      return res.status(405).json({ error: "Method not allowed" });
    }

    if (action === "create_rights") {
      const sourceUrl = (body.source_url || "").toString().trim();
      if (!sourceUrl) return res.status(400).json({ error: "source_url required" });
      if (!supabaseConfigured()) {
        return res.status(200).json({
          mode: "control_plane_stub",
          rights_record: {
            id: null,
            source_url: sourceUrl,
            note: "Create via media-worker CLI until Supabase is wired",
          },
        });
      }
      const platform = detectPlatform(sourceUrl);
      const externalId = platform === "youtube" ? youtubeId(sourceUrl) : null;
      const rows = await sb("rights_records", {
        method: "POST",
        body: {
          source_url: sourceUrl,
          platform,
          external_id: externalId,
          clearance_notes: body.clearance_notes || "",
          cleared_by: body.cleared_by || "api",
          license_type: body.license_type || "pilot_cleared",
        },
      });
      return res.status(200).json({ rights_record: rows?.[0] || rows });
    }

    if (action === "create_job") {
      const sourceUrl = (body.source_url || "").toString().trim();
      const rightsRecordId = (body.rights_record_id || "").toString().trim();
      if (!sourceUrl) return res.status(400).json({ error: "source_url required" });
      if (!rightsRecordId && supabaseConfigured()) {
        return res.status(400).json({ error: "rights_record_id required before ingest" });
      }
      if (!supabaseConfigured()) {
        return res.status(200).json({
          mode: "control_plane_stub",
          message: "Run: cd media-worker && npm run pilot",
          source_url: sourceUrl,
        });
      }
      const platform = detectPlatform(sourceUrl);
      const externalId = platform === "youtube" ? youtubeId(sourceUrl) : null;
      const assets = await sb("source_assets", {
        method: "POST",
        body: {
          platform,
          source_url: sourceUrl,
          external_id: externalId,
          rights_record_id: rightsRecordId,
          status: "queued",
        },
      });
      const asset = assets?.[0];
      const jobs = await sb("ingestion_jobs", {
        method: "POST",
        body: {
          source_asset_id: asset.id,
          job_type: "full_ingest",
          status: "queued",
        },
      });
      return res.status(200).json({ source_asset: asset, job: jobs?.[0] });
    }

    if (action === "revoke") {
      const assetId = (body.source_asset_id || "").toString().trim();
      if (!assetId) return res.status(400).json({ error: "source_asset_id required" });
      if (!supabaseConfigured()) {
        return res.status(200).json({
          mode: "control_plane_stub",
          source_asset_id: assetId,
          status: "revoked",
          note: "Local revoke via worker store.revokeSourceAsset",
        });
      }
      const rows = await sb(`source_assets?id=eq.${encodeURIComponent(assetId)}`, {
        method: "PATCH",
        body: { status: "revoked" },
      });
      return res.status(200).json({ source_asset: rows?.[0], status: "revoked" });
    }

    if (action === "playback_token") {
      // Phase B stub — Stream signed tokens land when CF_STREAM_* is configured.
      return res.status(200).json({
        token: null,
        expires_in: 0,
        mode: "stub",
        message: "Use local playback server for pilot; Stream tokens in Phase B cloud path.",
        playback_base: process.env.MEDIA_LOCAL_PLAYBACK_BASE || null,
      });
    }

    return res.status(400).json({ error: `Unknown action: ${action}` });
  } catch (err) {
    return res.status(err.status || 500).json({
      error: err.message || "media ingest failed",
      details: err.body || undefined,
    });
  }
}
