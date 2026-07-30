#!/usr/bin/env node
/**
 * Rebuild 9:16 canvas clips with blur-fill (sharp landscape + blurred edges).
 * Usage: node scripts/regenerateVerticalBlurFill.js
 */
import path from "node:path";
import fs from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { LocalStore } from "../src/store.js";
import { makeVerticalBlurFill, extractThumbnail } from "../src/ffmpeg.js";
import { localObjectPath, putObject } from "../src/storage.js";
import { config } from "../src/config.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(__dirname, "..");

async function main() {
  const store = new LocalStore();
  await store.load();

  const asset = Object.values(store.data.source_assets).find(
    (a) => a.external_id === "gBJjRYk0yC0" && a.status !== "revoked"
  );
  if (!asset) throw new Error("pilot asset missing — run npm run pilot");

  const clips = Object.values(store.data.clip_assets).filter((c) =>
    String(c.object_key || "").includes(asset.id)
  );
  if (!clips.length) throw new Error("no clip_assets for pilot");

  const work = path.join(config.workDir, "vertical-blur");
  await fs.mkdir(work, { recursive: true });

  for (const clip of clips) {
    const landscapeKey = clip.object_key;
    if (!landscapeKey) continue;
    const landscapePath = await localObjectPath(landscapeKey);
    const verticalKey = landscapeKey.replace(/\.mp4$/i, ".vertical.mp4");
    const posterKey = landscapeKey.replace(/\.mp4$/i, ".poster.jpg");
    const tmpVert = path.join(work, `${clip.id}.vertical.mp4`);
    const tmpPoster = path.join(work, `${clip.id}.poster.jpg`);

    console.log(`[vertical] ${clip.id}`);
    await makeVerticalBlurFill(landscapePath, tmpVert);
    await putObject(verticalKey, tmpVert);

    const mid = Math.max(0.4, Number(clip.duration_seconds || 4) * 0.45);
    await extractThumbnail(tmpVert, tmpPoster, mid);
    await putObject(posterKey, tmpPoster);

    clip.vertical_object_key = verticalKey;
    clip.poster_object_key = posterKey;
    clip.presentation_mode = "blurFill";
    clip.thumbnail_url = `/media/objects/${posterKey}`;
  }

  await store.save();
  console.log(`[vertical] wrote ${clips.length} blur-fill canvases → ${ROOT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
