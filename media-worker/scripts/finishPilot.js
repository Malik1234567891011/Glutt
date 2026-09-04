#!/usr/bin/env node
/**
 * Finish an already-downloaded pilot: upsert fixture segments, materialize
 * landscape clips + blur-fill verticals, mark asset ready.
 *
 * Usage: node scripts/finishPilot.js Cyskqnp1j64
 */
import path from "node:path";
import fs from "node:fs/promises";
import { store } from "../src/store.js";
import { config } from "../src/config.js";
import { localObjectPath, putObject, objectExists } from "../src/storage.js";
import { materializeClip, extractThumbnail, makeVerticalBlurFill } from "../src/ffmpeg.js";

const FIXTURES = {
  gBJjRYk0yC0: () => import("../fixtures/eggsBenedictSegments.js").then((m) => m.eggsBenedictSegments),
  Cyskqnp1j64: () => import("../fixtures/beefWellingtonSegments.js").then((m) => m.beefWellingtonSegments),
  "6tSdlo0r0Io": () => import("../fixtures/cremeBruleeSegments.js").then((m) => m.cremeBruleeSegments),
  "3sUJwjvmzk8": () =>
    import("../fixtures/gnocchiBrownButterSegments.js").then((m) => m.gnocchiBrownButterSegments),
  hDjK5C2aoSs: () =>
    import("../fixtures/butterChickenSegments.js").then((m) => m.butterChickenSegments),
};

async function main() {
  const externalId = process.argv[2];
  if (!externalId || !FIXTURES[externalId]) {
    console.error(`usage: node scripts/finishPilot.js <${Object.keys(FIXTURES).join("|")}>`);
    process.exit(1);
  }
  await store.load();
  const asset = Object.values(store.data.source_assets).find(
    (a) => a.external_id === externalId && a.status !== "revoked"
  );
  if (!asset) throw new Error(`no asset for ${externalId} — run ingest first`);
  if (!asset.normalized_object_key) throw new Error("normalized master missing");

  const segments = await FIXTURES[externalId]();
  await store.upsertSegments(asset.id, segments);
  console.log(`[finish] upserted ${segments.length} segments for ${asset.id}`);

  const workRoot = path.join(config.workDir, `finish-${externalId}`);
  await fs.mkdir(workRoot, { recursive: true });
  const input = await localObjectPath(asset.normalized_object_key);

  for (const seg of segments) {
    const dur = Number(seg.end_seconds) - Number(seg.start_seconds);
    const clipRel = `source_assets/${asset.id}/clips/${seg.id}.mp4`;
    const thumbRel = `source_assets/${asset.id}/clips/${seg.id}.jpg`;
    const verticalKey = clipRel.replace(/\.mp4$/i, ".vertical.mp4");
    const posterKey = clipRel.replace(/\.mp4$/i, ".poster.jpg");

    if (!(await objectExists(clipRel))) {
      const out = path.join(workRoot, `${seg.id}.mp4`);
      console.log(`[finish] clip ${seg.id} ${seg.start_seconds}-${seg.end_seconds}`);
      await materializeClip(input, out, Number(seg.start_seconds), dur);
      await putObject(clipRel, out);
    }
    if (!(await objectExists(thumbRel))) {
      const thumb = path.join(workRoot, `${seg.id}.jpg`);
      await extractThumbnail(input, thumb, Number(seg.start_seconds) + dur / 2);
      await putObject(thumbRel, thumb);
    }
    if (!(await objectExists(verticalKey))) {
      const landscapePath = await localObjectPath(clipRel);
      const tmpVert = path.join(workRoot, `${seg.id}.vertical.mp4`);
      const tmpPoster = path.join(workRoot, `${seg.id}.poster.jpg`);
      console.log(`[finish] vertical ${seg.id}`);
      await makeVerticalBlurFill(landscapePath, tmpVert);
      await putObject(verticalKey, tmpVert);
      await extractThumbnail(tmpVert, tmpPoster, Math.max(0.4, dur * 0.45));
      await putObject(posterKey, tmpPoster);
    }

    await store.load();
    store.data.clip_assets[seg.id] = {
      ...(store.data.clip_assets[seg.id] || {}),
      id: seg.id,
      segment_id: seg.id,
      object_key: clipRel,
      vertical_object_key: verticalKey,
      poster_object_key: posterKey,
      aspect_ratio: "source",
      duration_seconds: dur,
      presentation_mode: "blurFill",
      teaching_label: seg.teaching_label || seg.watch_label,
      visual_cue: seg.visual_cue,
      captions_json: { notice: seg.notice, watch_label: seg.watch_label },
      thumbnail_url: `/media/objects/${posterKey}`,
      requires_signed_url: false,
      status: "ready",
      created_at: store.data.clip_assets[seg.id]?.created_at || new Date().toISOString(),
    };
    await store.save();
  }

  await store.updateSourceAsset(asset.id, {
    status: "ready",
    creator_name: asset.creator_name || (externalId === "6tSdlo0r0Io" ? "Preppy Kitchen" : "Gordon Ramsay"),
    title: asset.title || (externalId === "6tSdlo0r0Io" ? "Crème Brûlée" : "Beef Wellington"),
  });
  console.log(`[finish] ready — asset ${asset.id}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
