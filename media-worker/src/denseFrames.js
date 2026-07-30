import fs from "node:fs/promises";
import path from "node:path";
import { config } from "./config.js";
import { runCommand } from "./spawn.js";
import { localObjectPath, putObject, objectExists } from "./storage.js";
import { store } from "./store.js";

/** Dense 6fps frames around an approved segment for boundary refinement (Phase E). */
export async function extractDenseAroundSegment(sourceAssetId, normalizedKey, segment, fps = 6) {
  const start = Math.max(0, Number(segment.start_seconds) - 5);
  const end = Number(segment.end_seconds) + 5;
  const dur = Math.max(0.5, end - start);
  const input = await localObjectPath(normalizedKey);
  const work = path.join(config.workDir, sourceAssetId, "frames-dense", segment.id);
  await fs.mkdir(work, { recursive: true });
  await runCommand(config.ffmpegBin, [
    "-y",
    "-ss", String(start),
    "-i", input,
    "-t", String(dur),
    "-vf", `fps=${fps}`,
    "-q:v", "4",
    path.join(work, "frame-%04d.jpg"),
  ], { timeoutMs: 10 * 60 * 1000 });

  const files = (await fs.readdir(work)).filter((f) => f.endsWith(".jpg")).sort();
  const keys = [];
  for (const f of files) {
    const objectKey = `source_assets/${sourceAssetId}/frames/dense/${segment.id}/${f}`;
    if (!(await objectExists(objectKey))) {
      await putObject(objectKey, path.join(work, f));
    }
    keys.push(objectKey);
  }
  return keys;
}

export async function extractDenseForApproved(sourceAssetId) {
  const asset = await store.getSourceAsset(sourceAssetId);
  if (!asset?.normalized_object_key) throw new Error("normalized required");
  const segs = await store.listApprovedSegments(sourceAssetId);
  const out = {};
  for (const seg of segs) {
    out[seg.id] = await extractDenseAroundSegment(sourceAssetId, asset.normalized_object_key, seg);
  }
  return out;
}
