#!/usr/bin/env node
/**
 * Read-only snapshot of the cloud clip queue: assets, jobs, segments, clip_assets.
 * Usage: node scripts/queueDoctor.js [--external-id=abc]
 */
import fs from "node:fs/promises";
import path from "node:path";
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

await loadDotEnv();
const { sb, supabaseConfigured } = await import("../src/supabaseAdmin.js");
if (!supabaseConfigured()) {
  console.error("Need SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in media-worker/.env");
  process.exit(1);
}

const filter = process.argv.find((a) => a.startsWith("--external-id="))?.split("=")[1];
const requeue = process.argv.find((a) => a.startsWith("--requeue="))?.split("=")[1];

if (requeue) {
  const rows = await sb(
    `source_assets?external_id=eq.${encodeURIComponent(requeue)}&select=id&order=created_at.desc`
  );
  for (const a of rows || []) {
    const updated = await sb(`ingestion_jobs?source_asset_id=eq.${encodeURIComponent(a.id)}`, {
      method: "PATCH",
      body: {
        status: "queued",
        lease_owner: null,
        lease_expires_at: null,
        error_code: null,
        error_details: null,
        updated_at: new Date().toISOString(),
      },
    });
    console.log(`requeued ${updated?.length || 0} job(s) for asset ${a.id}`);
  }
  process.exit(0);
}

const assets = await sb(
  `source_assets?select=*&order=created_at.desc&limit=40${filter ? `&external_id=eq.${encodeURIComponent(filter)}` : ""}`
);
console.log(`\n=== source_assets (${assets.length}) ===`);
for (const a of assets) {
  const jobs = await sb(
    `ingestion_jobs?source_asset_id=eq.${encodeURIComponent(a.id)}&select=id,status,stage,progress,error_code,error_details,created_at,updated_at&order=created_at.desc`
  );
  const segs = await sb(
    `semantic_segments?source_asset_id=eq.${encodeURIComponent(a.id)}&select=id,review_status`
  );
  const approved = segs.filter((s) => s.review_status === "approved");
  let clips = [];
  if (approved.length) {
    const inList = `(${approved.map((s) => `"${String(s.id).replace(/"/g, "")}"`).join(",")})`;
    clips = await sb(`clip_assets?segment_id=in.${inList}&select=id,status`).catch(() => []);
  }
  const ready = clips.filter((c) => c.status === "ready").length;
  console.log(
    `\n${a.external_id}  [${a.platform}]  status=${a.status}  "${(a.title || "").slice(0, 48)}"`
  );
  console.log(`  created=${a.created_at}  updated=${a.updated_at}`);
  console.log(`  segments=${segs.length} approved=${approved.length}  clip_assets=${clips.length} ready=${ready}`);
  for (const j of jobs) {
    console.log(
      `  job ${j.status}/${j.stage} p=${j.progress} ${j.error_code || ""} ${(j.error_details || "").slice(0, 120)}`
    );
  }
}

const queued = await sb("ingestion_jobs?status=eq.queued&select=id,created_at&order=created_at.asc");
const running = await sb("ingestion_jobs?status=eq.running&select=id,stage,updated_at&order=updated_at.asc");
const failed = await sb("ingestion_jobs?status=eq.failed&select=id,error_code&order=updated_at.desc&limit=10");
console.log(`\n=== queue totals ===`);
console.log(`queued=${queued.length} running=${running.length} failed(recent)=${failed.length}`);
for (const j of running) console.log(`  running stuck? ${j.id} stage=${j.stage} updated=${j.updated_at}`);
