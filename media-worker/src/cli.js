#!/usr/bin/env node
import fs from "node:fs/promises";
import { config } from "./config.js";
import { store } from "./store.js";
import { createIngestJob, runFullIngest } from "./pipeline.js";

async function ensureDirs() {
  await fs.mkdir(config.dataDir, { recursive: true });
  await fs.mkdir(config.workDir, { recursive: true });
}

async function pilotEggsBenedict() {
  await ensureDirs();
  const sourceUrl = "https://www.youtube.com/watch?v=gBJjRYk0yC0";
  console.log("[pilot] creating rights + ingest job for Eggs Benedict…");
  const { asset, job, rightsRecordId } = await createIngestJob({
    sourceUrl,
    clearanceNotes: "Pilot clearance for Glutt Eggs Benedict (product-confirmed).",
  });
  console.log("[pilot] rights=", rightsRecordId);
  console.log("[pilot] asset=", asset.id);
  console.log("[pilot] job=", job.id);
  console.log("[pilot] running full ingest (download → archive → normalize → manual segments)…");
  const ready = await runFullIngest(job);
  console.log("[pilot] status=", ready.status);
  console.log("[pilot] original=", ready.original_object_key);
  console.log("[pilot] normalized=", ready.normalized_object_key);
  console.log("[pilot] duration=", ready.duration_seconds);
  const segs = await store.listApprovedSegments(ready.id);
  console.log(`[pilot] approved segments=${segs.length}`);
  for (const s of segs) {
    console.log(`  - ${s.watch_label}: ${s.start_seconds}-${s.end_seconds}`);
  }
  console.log(`[pilot] store=${config.storePath}`);
  console.log(`[pilot] objects=${config.dataDir}/objects`);
  console.log("[pilot] next: npm run serve-local");
}

async function workerLoop() {
  await ensureDirs();
  console.log(`[worker] id=${config.workerId} polling ${config.storePath}`);
  for (;;) {
    const job = await store.claimNextJob(config.workerId, config.leaseSeconds);
    if (!job) {
      await new Promise((r) => setTimeout(r, 2000));
      continue;
    }
    console.log(`[worker] claimed ${job.id} asset=${job.source_asset_id}`);
    try {
      await runFullIngest(job);
      console.log(`[worker] succeeded ${job.id}`);
    } catch (err) {
      console.error(`[worker] failed ${job.id}`, err.code || "", err.message);
    }
  }
}

async function ingestOnce(url) {
  await ensureDirs();
  const { asset, job } = await createIngestJob({ sourceUrl: url });
  console.log("asset", asset.id, "job", job.id);
  const ready = await runFullIngest(job);
  console.log(JSON.stringify(ready, null, 2));
}

async function evidenceOnce(assetId) {
  await ensureDirs();
  const { runEvidencePackage } = await import("./evidence.js");
  let id = assetId;
  if (!id) {
    await store.load();
    const asset = Object.values(store.data.source_assets).find(
      (a) => a.external_id === "gBJjRYk0yC0" && a.status !== "revoked"
    );
    if (!asset) throw new Error("no Eggs Benedict asset — run pilot first");
    id = asset.id;
  }
  console.log("[evidence] asset=", id);
  const out = await runEvidencePackage(id);
  console.log("[evidence] scenes=", out.scenes, "coarse_frames=", out.frames);
}

const [cmd, arg] = process.argv.slice(2);
if (cmd === "pilot-eggs-benedict") {
  await pilotEggsBenedict();
} else if (cmd === "worker") {
  await workerLoop();
} else if (cmd === "ingest") {
  if (!arg) {
    console.error("usage: node src/cli.js ingest <url>");
    process.exit(1);
  }
  await ingestOnce(arg);
} else if (cmd === "evidence") {
  await evidenceOnce(arg);
} else if (cmd === "dense-frames") {
  await ensureDirs();
  const { extractDenseForApproved } = await import("./denseFrames.js");
  await store.load();
  const asset = Object.values(store.data.source_assets).find(
    (a) => a.external_id === "gBJjRYk0yC0" && a.status !== "revoked"
  );
  if (!asset) throw new Error("no pilot asset");
  const out = await extractDenseForApproved(asset.id);
  for (const [id, keys] of Object.entries(out)) {
    console.log(`[dense] ${id}: ${keys.length} frames`);
  }
} else {
  console.log(`usage:
  npm run pilot
  npm run worker
  npm run ingest -- <url>
  npm run evidence
  npm run serve-local`);
  process.exit(cmd ? 1 : 0);
}
