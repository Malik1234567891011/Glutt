#!/usr/bin/env node
/**
 * Frame-QA for approved pilot segments.
 * Pulls start+1.5s, mid, and end-1.5s stills so a human (or later a vision
 * model) can reject speech-lead / talking-head windows before they ship.
 *
 * Usage: node scripts/verifySegmentFrames.js Cyskqnp1j64
 */
import path from "node:path";
import fs from "node:fs/promises";
import { store } from "../src/store.js";
import { config } from "../src/config.js";
import { localObjectPath } from "../src/storage.js";
import { extractThumbnail } from "../src/ffmpeg.js";

const FIXTURES = {
  gBJjRYk0yC0: () => import("../fixtures/eggsBenedictSegments.js").then((m) => m.eggsBenedictSegments),
  Cyskqnp1j64: () => import("../fixtures/beefWellingtonSegments.js").then((m) => m.beefWellingtonSegments),
  "7333706662634704161": () =>
    import("../fixtures/tiktokScrambledEggsSegments.js").then((m) => m.tiktokScrambledEggsSegments),
};

async function main() {
  const externalId = process.argv[2];
  if (!externalId || !FIXTURES[externalId]) {
    console.error("usage: node scripts/verifySegmentFrames.js <gBJjRYk0yC0|Cyskqnp1j64>");
    process.exit(1);
  }
  await store.load();
  const asset = Object.values(store.data.source_assets).find(
    (a) => a.external_id === externalId && a.status !== "revoked"
  );
  if (!asset?.normalized_object_key) throw new Error("normalized master missing");

  const segments = await FIXTURES[externalId]();
  const input = await localObjectPath(asset.normalized_object_key);
  const outRoot = path.join(config.workDir, `qa-frames-${externalId}`);
  await fs.mkdir(outRoot, { recursive: true });

  console.log(`# Frame QA pack → ${outRoot}`);
  console.log(`# Rule: start+1.5s MUST already show the technique (food/hands/tools), not a face.`);
  console.log("");

  for (const seg of segments) {
    const start = Number(seg.start_seconds);
    const end = Number(seg.end_seconds);
    const mid = start + (end - start) * 0.45;
    const samples = [
      ["start", Math.min(start + 1.5, end - 0.5)],
      ["mid", mid],
      ["end", Math.max(end - 1.5, start + 0.5)],
    ];
    const dir = path.join(outRoot, seg.id);
    await fs.mkdir(dir, { recursive: true });
    console.log(`## ${seg.id}  ${start}–${end}s  (${seg.teaching_label || seg.watch_label})`);
    if (seg.action_visible_from_seconds != null) {
      console.log(`   expected action visible from ~${seg.action_visible_from_seconds}s`);
      if (start + 1.5 < Number(seg.action_visible_from_seconds) - 1) {
        console.log(`   WARN: start+1.5s is before action_visible_from — likely speech lead-in`);
      }
    }
    for (const [label, t] of samples) {
      const dest = path.join(dir, `${label}-${t.toFixed(1)}.jpg`);
      await extractThumbnail(input, dest, t);
      console.log(`   ${label.padEnd(5)} t=${t.toFixed(1)}s → ${dest}`);
    }
    console.log("");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
