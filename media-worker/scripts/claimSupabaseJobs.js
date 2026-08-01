#!/usr/bin/env node
/**
 * Claim queued Supabase ingestion_jobs, run the local full ingest pipeline, and
 * sync playback objects back to Storage.
 *
 * The cloud row is mirrored into the LocalStore under its own id so the sync
 * back up merges instead of creating a second source_assets row for the same
 * video (two rows for one external_id makes /api/media/clips non-deterministic).
 *
 * Segments come from the Gemini index the app triggers at import time and live
 * only in Postgres, so they are pulled down before the cut. A job with no
 * approved segments yet is returned to the queue rather than marked ready —
 * "ready with zero clips" reads as success to the app and hides the banner.
 *
 * Usage:
 *   cd media-worker && npm run claim:supabase
 *   npm run claim:supabase -- --loop --interval=30
 */
import fs from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Give the app's Gemini index this many claim passes to land before failing. */
const MAX_SEGMENT_WAIT_ATTEMPTS = 20;
/** Cooldown before re-claiming a job that is still waiting on the index. */
const SEGMENT_RETRY_BACKOFF_MS = 2 * 60 * 1000;

async function loadDotEnv() {
  try {
    const raw = await fs.readFile(path.join(root, ".env"), "utf8");
    for (const line of raw.split("\n")) {
      const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
      if (!m) continue;
      let v = m[2].trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
        v = v.slice(1, -1);
      }
      if (process.env[m[1]] == null || process.env[m[1]] === "") process.env[m[1]] = v;
    }
  } catch {
    /* optional */
  }
}

function parseArgs(argv) {
  const out = { once: true, intervalSec: 30 };
  for (const a of argv) {
    if (a === "--loop") out.once = false;
    else if (a === "--once") out.once = true;
    else if (a.startsWith("--interval=")) out.intervalSec = Number(a.slice("--interval=".length)) || 30;
  }
  return out;
}

const nowISO = () => new Date().toISOString();

async function main() {
  await loadDotEnv();
  const args = parseArgs(process.argv.slice(2));
  const { supabaseConfigured, sb } = await import("../src/supabaseAdmin.js");
  const { runFullIngest } = await import("../src/pipeline.js");
  const { store } = await import("../src/store.js");
  const { config } = await import("../src/config.js");

  if (!supabaseConfigured()) {
    console.error("Need SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in media-worker/.env");
    process.exit(1);
  }

  /** Copy the cloud asset + its rights record into the LocalStore, keeping ids. */
  async function mirrorAssetDown(asset) {
    await store.load();
    let rightsId = asset.rights_record_id;
    if (rightsId && !store.data.rights_records[rightsId]) {
      const rows = await sb(`rights_records?id=eq.${encodeURIComponent(rightsId)}&select=*`);
      const cloud = rows?.[0];
      store.data.rights_records[rightsId] = cloud || {
        id: rightsId,
        source_url: asset.source_url,
        platform: asset.platform,
        external_id: asset.external_id,
        clearance_notes: "mirrored from Supabase queue",
        cleared_by: "claimSupabaseJobs",
        cleared_at: nowISO(),
        license_type: "user_import",
        metadata_json: {},
        created_at: nowISO(),
      };
    }
    if (!rightsId) {
      const rights = await store.createRightsRecord({
        sourceUrl: asset.source_url,
        platform: asset.platform,
        externalId: asset.external_id,
        clearanceNotes: "claimed from Supabase queue",
        clearedBy: "claimSupabaseJobs",
        licenseType: "user_import",
      });
      rightsId = rights.id;
      await store.load();
    }

    const existing = store.data.source_assets[asset.id];
    store.data.source_assets[asset.id] = {
      ...asset,
      ...existing,
      id: asset.id,
      rights_record_id: rightsId,
      // Cloud status words ("analysing", "queued") are control-plane state; the
      // pipeline drives the local one and would otherwise skip its own stages.
      status: existing?.status && existing.status !== "revoked" ? existing.status : "queued",
      updated_at: nowISO(),
    };
    await store.save();
    return store.data.source_assets[asset.id];
  }

  /** Pull approved Gemini segments into the LocalStore so the cut can see them. */
  async function mirrorApprovedSegments(assetId) {
    const rows = await sb(
      `semantic_segments?source_asset_id=eq.${encodeURIComponent(assetId)}&review_status=eq.approved&order=start_seconds.asc&select=*`
    );
    if (!rows?.length) return 0;
    await store.load();
    for (const s of rows) {
      store.data.semantic_segments[s.id] = {
        ...s,
        source_asset_id: assetId,
        step_keywords: s.step_keywords_json || s.step_keywords || [],
        review_status: "approved",
      };
    }
    await store.save();
    return rows.length;
  }

  /**
   * Oldest claimable job. A job parked on `awaiting_segments` is still queued,
   * so without a cooldown it would stay the oldest row forever and starve every
   * import behind it.
   */
  async function nextClaimable() {
    const jobs = await sb(
      "ingestion_jobs?status=in.(queued,running,leased)&order=created_at.asc&limit=40&select=*"
    );
    const segmentCutoff = Date.now() - SEGMENT_RETRY_BACKOFF_MS;
    const staleCutoff = Date.now() - config.leaseSeconds * 1000;
    return (
      (jobs || []).find((j) => {
        // A crashed worker leaves the job `running` forever; take it back once
        // the lease has lapsed.
        if (j.status !== "queued") {
          const lease = j.lease_expires_at ? new Date(j.lease_expires_at).getTime() : 0;
          if (lease > Date.now()) return false;
          return new Date(j.updated_at || 0).getTime() < staleCutoff;
        }
        if (j.stage !== "awaiting_segments") return true;
        return new Date(j.updated_at || 0).getTime() < segmentCutoff;
      }) || null
    );
  }

  async function claimOne() {
    const queued = await nextClaimable();
    if (!queued) {
      console.log("[claim] no claimable jobs");
      return "idle";
    }

    // Conditional claim: the filter pins the status we just read, so a racing
    // worker that got there first leaves us with an empty representation.
    const claimed = await sb(
      `ingestion_jobs?id=eq.${encodeURIComponent(queued.id)}&status=eq.${encodeURIComponent(queued.status)}`,
      {
        method: "PATCH",
        body: {
          status: "running",
          stage: "worker_claim",
          progress: 0.1,
          attempt_count: (queued.attempt_count || 0) + 1,
          lease_owner: config.workerId,
          lease_expires_at: new Date(Date.now() + config.leaseSeconds * 1000).toISOString(),
          started_at: queued.started_at || nowISO(),
          updated_at: nowISO(),
        },
      }
    );
    const job = claimed?.[0];
    if (!job) {
      console.log(`[claim] job ${queued.id} taken by another worker`);
      return "progress";
    }

    const assets = await sb(`source_assets?id=eq.${encodeURIComponent(job.source_asset_id)}&select=*`);
    const asset = assets?.[0];
    if (!asset || asset.status === "revoked") {
      await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
        method: "PATCH",
        body: { status: "cancelled", error_code: "ASSET_MISSING", updated_at: nowISO() },
      });
      return "progress";
    }

    console.log(`[claim] job=${job.id} asset=${asset.external_id} url=${asset.source_url}`);
    await sb(`source_assets?id=eq.${encodeURIComponent(asset.id)}`, {
      method: "PATCH",
      body: { status: "downloading", updated_at: nowISO() },
    });

    try {
      await store.load();
      await mirrorAssetDown(asset);
      const segCount = await mirrorApprovedSegments(asset.id);
      console.log(`[claim] mirrored ${segCount} approved segment(s) from Supabase`);

      let localJob = await store.getJob(job.id);
      if (!localJob) {
        await store.load();
        store.data.ingestion_jobs[job.id] = {
          ...job,
          source_asset_id: asset.id,
          status: "running",
          created_at: job.created_at || nowISO(),
          updated_at: nowISO(),
        };
        await store.save();
        localJob = await store.getJob(job.id);
      }

      const { clipCount } = await runFullIngest(localJob);

      if (clipCount === 0) {
        // Download + normalize are archived, so a later pass is cheap. Hand the
        // job back so it retries once the index writes segments.
        const attempts = job.attempt_count || 1;
        const giveUp = attempts >= MAX_SEGMENT_WAIT_ATTEMPTS;
        console.warn(
          `[claim] ${asset.external_id}: no approved segments yet (attempt ${attempts}) — ${giveUp ? "giving up" : "requeueing"}`
        );
        await sb(`source_assets?id=eq.${encodeURIComponent(asset.id)}`, {
          method: "PATCH",
          body: {
            // Back to `queued`, not `review_required`: the app only keeps its
            // progress banner (and the analyze retry) alive for statuses it
            // recognises, and an unknown one reads as finished.
            status: giveUp ? "failed" : "queued",
            error_code: giveUp ? "NO_SEGMENTS" : null,
            error_details: giveUp
              ? "Gemini index never produced approved segments for this video"
              : null,
            updated_at: nowISO(),
          },
        });
        await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
          method: "PATCH",
          body: {
            status: giveUp ? "failed" : "queued",
            stage: "awaiting_segments",
            progress: 0.6,
            error_code: giveUp ? "NO_SEGMENTS" : null,
            lease_owner: null,
            lease_expires_at: null,
            updated_at: nowISO(),
          },
        });
        return "progress";
      }

      await new Promise((resolve, reject) => {
        const p = spawn(
          process.execPath,
          ["scripts/syncToSupabase.js", `--external-id=${asset.external_id}`],
          { cwd: root, stdio: "inherit" }
        );
        p.on("exit", (c) => (c === 0 ? resolve() : reject(new Error(`sync exit ${c}`))));
      });

      await sb(`source_assets?id=eq.${encodeURIComponent(asset.id)}`, {
        method: "PATCH",
        body: { status: "ready", error_code: null, error_details: null, updated_at: nowISO() },
      });
      await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
        method: "PATCH",
        body: {
          status: "succeeded",
          stage: "ready",
          progress: 1,
          lease_owner: null,
          lease_expires_at: null,
          completed_at: nowISO(),
          updated_at: nowISO(),
        },
      });
      console.log(`[claim] ready ${asset.external_id} (${clipCount} clips)`);
    } catch (err) {
      console.error("[claim] failed", err.message || err);
      await sb(`source_assets?id=eq.${encodeURIComponent(asset.id)}`, {
        method: "PATCH",
        body: {
          status: "failed",
          error_code: err.code || "WORKER_FAILED",
          error_details: String(err.message || err).slice(0, 500),
          updated_at: nowISO(),
        },
      });
      await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
        method: "PATCH",
        body: {
          status: "failed",
          error_code: err.code || "WORKER_FAILED",
          error_details: String(err.message || err).slice(0, 500),
          lease_owner: null,
          lease_expires_at: null,
          updated_at: nowISO(),
        },
      });
    }
    return "progress";
  }

  if (args.once) {
    await claimOne();
    return;
  }
  console.log(`[claim] looping every ${args.intervalSec}s as ${config.workerId}`);
  for (;;) {
    try {
      // Drain the backlog before sleeping so a burst of imports isn't paced at
      // one video per interval.
      while ((await claimOne()) === "progress") { /* keep going while work remains */ }
    } catch (err) {
      console.error("[claim] loop error", err);
    }
    await new Promise((r) => setTimeout(r, args.intervalSec * 1000));
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
