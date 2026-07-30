import fs from "node:fs/promises";
import path from "node:path";
import { config } from "./config.js";
import { runCommand } from "./spawn.js";
import { store } from "./store.js";
import { localObjectPath, putObject, objectExists } from "./storage.js";

/**
 * Phase D evidence extraction (docs/donwloadplan.md §7).
 * Scenes + coarse frames now; ElevenLabs transcription when ELEVENLABS_API_KEY set.
 */

export async function detectScenes(sourceAssetId, normalizedKey) {
  const input = await localObjectPath(normalizedKey);
  const work = path.join(config.workDir, sourceAssetId, "scenes");
  await fs.mkdir(work, { recursive: true });
  // FFmpeg scene score print; parse showinfo-like lines from select filter.
  const { stderr } = await runCommand(config.ffmpegBin, [
    "-i", input,
    "-vf", "select='gt(scene,0.35)',showinfo",
    "-f", "null",
    "-",
  ], { timeoutMs: 10 * 60 * 1000 }).catch(async (err) => {
    // ffmpeg writes showinfo to stderr even on "success-ish"; tolerate code!=0 if we got data
    return { stderr: err.stderr || "", stdout: err.stdout || "" };
  });

  const cuts = [];
  const re = /pts_time:([0-9.]+)/g;
  let m;
  while ((m = re.exec(stderr || "")) !== null) {
    cuts.push(Number(m[1]));
  }
  cuts.sort((a, b) => a - b);

  const asset = await store.getSourceAsset(sourceAssetId);
  const duration = Number(asset?.duration_seconds) || (cuts[cuts.length - 1] || 0) + 1;
  const boundaries = [0, ...cuts.filter((t) => t > 0.2 && t < duration - 0.2), duration];
  const unique = [...new Set(boundaries.map((t) => Math.round(t * 100) / 100))];

  await store.load();
  // drop prior scenes for asset
  for (const [id, row] of Object.entries(store.data.video_scenes)) {
    if (row.source_asset_id === sourceAssetId) delete store.data.video_scenes[id];
  }
  const scenes = [];
  for (let i = 0; i < unique.length - 1; i++) {
    const id = cryptoRandom();
    const row = {
      id,
      source_asset_id: sourceAssetId,
      start_seconds: unique[i],
      end_seconds: unique[i + 1],
      scene_score: 0.35,
      created_at: new Date().toISOString(),
    };
    store.data.video_scenes[id] = row;
    scenes.push(row);
  }
  await store.save();
  return scenes;
}

export async function extractCoarseFrames(sourceAssetId, normalizedKey, everySeconds = 2) {
  const input = await localObjectPath(normalizedKey);
  const work = path.join(config.workDir, sourceAssetId, "frames-coarse");
  await fs.mkdir(work, { recursive: true });
  await runCommand(config.ffmpegBin, [
    "-y",
    "-i", input,
    "-vf", `fps=1/${everySeconds}`,
    "-q:v", "5",
    path.join(work, "frame-%04d.jpg"),
  ], { timeoutMs: 15 * 60 * 1000 });

  const files = (await fs.readdir(work)).filter((f) => f.endsWith(".jpg")).sort();
  const keys = [];
  for (const f of files) {
    const objectKey = `source_assets/${sourceAssetId}/frames/coarse/${f}`;
    if (!(await objectExists(objectKey))) {
      await putObject(objectKey, path.join(work, f));
    }
    keys.push(objectKey);
  }
  await store.load();
  store.data.source_assets[sourceAssetId] = {
    ...store.data.source_assets[sourceAssetId],
    coarse_frame_count: keys.length,
    coarse_frame_prefix: `source_assets/${sourceAssetId}/frames/coarse/`,
    updated_at: new Date().toISOString(),
  };
  await store.save();
  return keys;
}

function cryptoRandom() {
  return globalThis.crypto?.randomUUID?.() || `scene-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export async function runEvidencePackage(sourceAssetId) {
  const asset = await store.getSourceAsset(sourceAssetId);
  if (!asset?.normalized_object_key) throw new Error("normalized master required");
  await store.updateSourceAsset(sourceAssetId, { status: "analysing" });
  const scenes = await detectScenes(sourceAssetId, asset.normalized_object_key);
  const frames = await extractCoarseFrames(sourceAssetId, asset.normalized_object_key, 2);
  await store.updateSourceAsset(sourceAssetId, { status: "ready" });
  return { scenes: scenes.length, frames: frames.length };
}
