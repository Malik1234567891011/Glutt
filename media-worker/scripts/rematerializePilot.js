#!/usr/bin/env node
/**
 * Force-rematerialize pilot clips when segment windows change.
 * finishPilot.js skips existing files — this deletes then rebuilds.
 *
 * Usage: node scripts/rematerializePilot.js Cyskqnp1j64 [seg-id…]
 *        node scripts/rematerializePilot.js 7333706662634704161
 */
import path from "node:path";
import fs from "node:fs/promises";
import { store } from "../src/store.js";
import { config } from "../src/config.js";
import { localObjectPath, putObject } from "../src/storage.js";
import { materializeClip, extractThumbnail, makeVerticalBlurFill, ffprobeJson } from "../src/ffmpeg.js";

const FIXTURES = {
  gBJjRYk0yC0: () => import("../fixtures/eggsBenedictSegments.js").then((m) => m.eggsBenedictSegments),
  Cyskqnp1j64: () => import("../fixtures/beefWellingtonSegments.js").then((m) => m.beefWellingtonSegments),
  "7333706662634704161": () =>
    import("../fixtures/tiktokScrambledEggsSegments.js").then((m) => m.tiktokScrambledEggsSegments),
};

async function rmQuiet(p) {
  try {
    await fs.unlink(p);
  } catch {
    /* missing is fine */
  }
}

async function isPortrait(filePath) {
  const probe = await ffprobeJson(filePath);
  const v = (probe.streams || []).find((s) => s.codec_type === "video");
  return Boolean(v && Number(v.height) > Number(v.width));
}

async function main() {
  const externalId = process.argv[2];
  const only = process.argv.slice(3);
  if (!externalId || !FIXTURES[externalId]) {
    console.error(
      "usage: node scripts/rematerializePilot.js <gBJjRYk0yC0|Cyskqnp1j64|7333706662634704161> [seg-id…]"
    );
    process.exit(1);
  }
  await store.load();
  const asset = Object.values(store.data.source_assets).find(
    (a) => a.external_id === externalId && a.status !== "revoked"
  );
  if (!asset?.normalized_object_key) throw new Error("normalized master missing — ingest first");

  let segments = await FIXTURES[externalId]();
  if (only.length) segments = segments.filter((s) => only.includes(s.id));
  await store.upsertSegments(asset.id, await FIXTURES[externalId]());

  const workRoot = path.join(config.workDir, `rematerialize-${externalId}`);
  await fs.mkdir(workRoot, { recursive: true });
  const input = await localObjectPath(asset.normalized_object_key);
  const portraitSource = await isPortrait(input);

  for (const seg of segments) {
    const dur = Number(seg.end_seconds) - Number(seg.start_seconds);
    const clipRel = `source_assets/${asset.id}/clips/${seg.id}.mp4`;
    const thumbRel = `source_assets/${asset.id}/clips/${seg.id}.jpg`;
    const verticalKey = clipRel.replace(/\.mp4$/i, ".vertical.mp4");
    const posterKey = clipRel.replace(/\.mp4$/i, ".poster.jpg");

    for (const key of [clipRel, thumbRel, verticalKey, posterKey]) {
      const abs = path.join(config.dataDir, "objects", key);
      await rmQuiet(abs);
    }

    const out = path.join(workRoot, `${seg.id}.mp4`);
    console.log(`[remat] ${seg.id} ${seg.start_seconds}-${seg.end_seconds} (${dur}s)`);
    await materializeClip(input, out, Number(seg.start_seconds), dur);
    await putObject(clipRel, out);

    const thumb = path.join(workRoot, `${seg.id}.jpg`);
    await extractThumbnail(input, thumb, Number(seg.start_seconds) + dur / 2);
    await putObject(thumbRel, thumb);

    const tmpVert = path.join(workRoot, `${seg.id}.vertical.mp4`);
    const tmpPoster = path.join(workRoot, `${seg.id}.poster.jpg`);
    let presentation = "blurFill";
    if (portraitSource) {
      // Already 9:16 (TikTok etc.) — reuse the cut; blur-fill would only soften it.
      await fs.copyFile(out, tmpVert);
      presentation = "nativeVertical";
      console.log(`[remat] vertical ${seg.id} (native portrait copy)`);
    } else {
      console.log(`[remat] vertical ${seg.id} (blur-fill)`);
      await makeVerticalBlurFill(out, tmpVert);
    }
    await putObject(verticalKey, tmpVert);
    await extractThumbnail(tmpVert, tmpPoster, Math.max(0.4, dur * 0.45));
    await putObject(posterKey, tmpPoster);

    const qaMid = path.join(workRoot, `${seg.id}.qa-mid.jpg`);
    await extractThumbnail(input, qaMid, Number(seg.start_seconds) + dur * 0.45);
    await putObject(`source_assets/${asset.id}/clips/${seg.id}.qa-mid.jpg`, qaMid);

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
      presentation_mode: presentation,
      teaching_label: seg.teaching_label || seg.watch_label,
      visual_cue: seg.visual_cue,
      captions_json: { notice: seg.notice, watch_label: seg.watch_label },
      thumbnail_url: `/media/objects/${posterKey}`,
      requires_signed_url: false,
      status: "ready",
      start_seconds: seg.start_seconds,
      end_seconds: seg.end_seconds,
      model_version: seg.model_version || "manual-pilot",
      created_at: store.data.clip_assets[seg.id]?.created_at || new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    await store.save();
  }

  await store.updateSourceAsset(asset.id, {
    status: "ready",
    creator_name: asset.creator_name || asset.uploader || "Gordon Ramsay",
    title: asset.title || "Scrambled Eggs",
  });
  console.log(`[remat] done — ${segments.length} clip(s)`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
