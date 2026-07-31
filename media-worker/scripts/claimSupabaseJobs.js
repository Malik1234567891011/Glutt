#!/usr/bin/env node
/**
 * Claim queued Supabase ingestion_jobs and run the local full ingest pipeline,
 * then sync playback objects back to Storage.
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

async function main() {
  await loadDotEnv();
  const args = parseArgs(process.argv.slice(2));
  const { supabaseConfigured, sb } = await import("../src/supabaseAdmin.js");
  const { createIngestJob, runFullIngest } = await import("../src/pipeline.js");
  const { store } = await import("../src/store.js");

  if (!supabaseConfigured()) {
    console.error("Need SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in media-worker/.env");
    process.exit(1);
  }

  async function claimOne() {
    const jobs = await sb(
      "ingestion_jobs?status=eq.queued&order=created_at.asc&limit=1&select=*"
    );
    const job = jobs?.[0];
    if (!job) {
      console.log("[claim] no queued jobs");
      return false;
    }
    const assets = await sb(`source_assets?id=eq.${encodeURIComponent(job.source_asset_id)}&select=*`);
    const asset = assets?.[0];
    if (!asset || asset.status === "revoked") {
      await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
        method: "PATCH",
        body: { status: "cancelled", error_code: "ASSET_MISSING", updated_at: new Date().toISOString() },
      });
      return true;
    }

    console.log(`[claim] job=${job.id} asset=${asset.external_id} url=${asset.source_url}`);
    await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
      method: "PATCH",
      body: {
        status: "running",
        stage: "worker_claim",
        progress: 0.1,
        started_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
    });
    await sb(`source_assets?id=eq.${encodeURIComponent(asset.id)}`, {
      method: "PATCH",
      body: { status: "downloading", updated_at: new Date().toISOString() },
    });

    try {
      await store.load();
      let local;
      try {
        local = await createIngestJob({
          sourceUrl: asset.source_url,
          clearanceNotes: "claimed from Supabase queue",
        });
      } catch (err) {
        // Dedup / rights edge cases — create rights then retry once.
        const rights = await store.createRightsRecord({
          sourceUrl: asset.source_url,
          platform: asset.platform,
          externalId: asset.external_id,
          clearanceNotes: "claimed from Supabase queue",
          clearedBy: "claimSupabaseJobs",
          licenseType: "user_import",
        });
        local = await createIngestJob({
          sourceUrl: asset.source_url,
          rightsRecordId: rights.id,
          clearanceNotes: "claimed from Supabase queue",
        });
        void err;
      }

      await runFullIngest(local.job);
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
        body: { status: "ready", updated_at: new Date().toISOString() },
      });
      await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
        method: "PATCH",
        body: {
          status: "succeeded",
          stage: "ready",
          progress: 1,
          completed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        },
      });
      console.log(`[claim] ready ${asset.external_id}`);
    } catch (err) {
      console.error("[claim] failed", err.message || err);
      await sb(`source_assets?id=eq.${encodeURIComponent(asset.id)}`, {
        method: "PATCH",
        body: {
          status: "failed",
          error_code: "WORKER_FAILED",
          error_details: String(err.message || err).slice(0, 500),
          updated_at: new Date().toISOString(),
        },
      });
      await sb(`ingestion_jobs?id=eq.${encodeURIComponent(job.id)}`, {
        method: "PATCH",
        body: {
          status: "failed",
          error_code: "WORKER_FAILED",
          error_details: String(err.message || err).slice(0, 500),
          updated_at: new Date().toISOString(),
        },
      });
    }
    return true;
  }

  if (args.once) {
    await claimOne();
    return;
  }
  console.log(`[claim] looping every ${args.intervalSec}s`);
  for (;;) {
    try {
      await claimOne();
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
