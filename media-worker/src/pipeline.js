import fs from "node:fs/promises";
import path from "node:path";
import { config } from "./config.js";
import { store } from "./store.js";
import { downloaderFor } from "./downloaders/index.js";
import { objectKeys } from "./security.js";
import { objectExists, putObject, sha256File, writeJsonObject, localObjectPath } from "./storage.js";
import {
  extractAudio,
  ffprobeJson,
  makeAnalysisProxy,
  materializeClip,
  normalizeMezzanine,
  summarizeProbe,
  extractThumbnail,
} from "./ffmpeg.js";

async function setProgress(jobId, assetId, { stage, progress, status }) {
  if (jobId) {
    await store.updateJob(jobId, {
      stage,
      progress,
      status: status || "running",
    });
  }
  if (assetId && status === "running") {
    // map stage → asset status coarsely
  }
}

export async function runFullIngest(job) {
  const asset = await store.getSourceAsset(job.source_asset_id);
  if (!asset) throw Object.assign(new Error("source asset missing"), { code: "ASSET_MISSING" });
  if (asset.status === "revoked") {
    throw Object.assign(new Error("asset revoked"), { code: "REVOKED" });
  }

  const rights = await store.getRights(asset.rights_record_id);
  if (!rights) throw Object.assign(new Error("rights record missing"), { code: "RIGHTS_REQUIRED" });

  const workRoot = path.join(config.workDir, asset.id);
  await fs.mkdir(workRoot, { recursive: true });
  const keys = objectKeys(asset.id);

  try {
    // ACQUIRE_SOURCE — probe
    await store.updateSourceAsset(asset.id, { status: "probing" });
    await setProgress(job.id, asset.id, { stage: "ACQUIRE_SOURCE", progress: 0.05, status: "running" });
    const { downloader, url } = downloaderFor(asset.source_url);

    let probe = asset.probe_json?.durationSeconds ? asset.probe_json : null;
    if (!probe || !probe.durationSeconds) {
      probe = await downloader.probe(url);
      await store.updateSourceAsset(asset.id, {
        probe_json: probe,
        title: probe.title,
        creator_name: probe.uploader,
        duration_seconds: probe.durationSeconds,
        external_id: probe.externalId || asset.external_id,
        width: probe.width || null,
        height: probe.height || null,
      });
    }

    // Download (idempotent if original already archived)
    let originalKey = asset.original_object_key;
    if (originalKey && (await objectExists(originalKey))) {
      await setProgress(job.id, asset.id, { stage: "ARCHIVE_ORIGINAL", progress: 0.35, status: "running" });
    } else {
      await store.updateSourceAsset(asset.id, { status: "downloading" });
      await setProgress(job.id, asset.id, { stage: "ACQUIRE_SOURCE", progress: 0.15, status: "running" });
      const downloaded = await downloader.download(url, path.join(workRoot, "download"));

      // ARCHIVE_ORIGINAL
      await setProgress(job.id, asset.id, { stage: "ARCHIVE_ORIGINAL", progress: 0.3, status: "running" });
      const sha = await sha256File(downloaded.filePath);
      const existing = await store.findBySha256(sha);
      if (existing && existing.id !== asset.id) {
        await store.updateSourceAsset(asset.id, {
          status: "failed",
          error_code: "DUPLICATE_SHA256",
          error_details: `Duplicate of ${existing.id}`,
          sha256: sha,
        });
        throw Object.assign(new Error(`Duplicate of ${existing.id}`), { code: "DUPLICATE_SHA256" });
      }

      const tech = summarizeProbe(await ffprobeJson(downloaded.filePath));
      originalKey = `${keys.originalPrefix}.${downloaded.ext}`;
      if (!(await objectExists(originalKey))) {
        await putObject(originalKey, downloaded.filePath);
      }
      await writeJsonObject(keys.metadata, {
        assetId: asset.id,
        probe: downloaded.probe,
        tech,
        sha256: sha,
        archivedAt: new Date().toISOString(),
      });

      await store.updateSourceAsset(asset.id, {
        status: "uploaded",
        sha256: sha,
        original_object_key: originalKey,
        duration_seconds: tech.durationSeconds || downloaded.probe.durationSeconds,
        width: tech.width,
        height: tech.height,
        title: downloaded.probe.title || asset.title,
        creator_name: downloaded.probe.uploader || asset.creator_name,
        probe_json: downloaded.probe,
      });
    }

    // NORMALIZE_SOURCE
    await store.updateSourceAsset(asset.id, { status: "normalizing" });
    await setProgress(job.id, asset.id, { stage: "NORMALIZE_SOURCE", progress: 0.5, status: "running" });
    const originalPath = await localObjectPath(originalKey);
    const normalizedPath = path.join(workRoot, "normalized.mp4");
    const proxyPath = path.join(workRoot, "analysis-proxy.mp4");
    const audioPath = path.join(workRoot, "audio.m4a");

    if (!(await objectExists(keys.normalized))) {
      await normalizeMezzanine(originalPath, normalizedPath);
      await putObject(keys.normalized, normalizedPath);
    } else {
      // ensure local work copy for later stages
      try {
        await fs.copyFile(await localObjectPath(keys.normalized), normalizedPath);
      } catch {
        await normalizeMezzanine(originalPath, normalizedPath);
        await putObject(keys.normalized, normalizedPath);
      }
    }

    if (!(await objectExists(keys.analysisProxy))) {
      const normSrc = (await objectExists(keys.normalized))
        ? await localObjectPath(keys.normalized)
        : normalizedPath;
      await makeAnalysisProxy(normSrc, proxyPath);
      await putObject(keys.analysisProxy, proxyPath);
    }

    if (!(await objectExists(keys.audio))) {
      const normSrc = (await objectExists(keys.normalized))
        ? await localObjectPath(keys.normalized)
        : normalizedPath;
      const audioOut = await extractAudio(normSrc, audioPath);
      if (!audioOut?.skipped) {
        await putObject(keys.audio, audioPath);
      }
    }

    await store.updateSourceAsset(asset.id, {
      normalized_object_key: keys.normalized,
      analysis_proxy_object_key: keys.analysisProxy,
      audio_object_key: (await objectExists(keys.audio)) ? keys.audio : null,
      status: "review_required",
    });

    // Seed manual pilot segments for known technique videos.
    const pilotFixtures = {
      gBJjRYk0yC0: () => import("../fixtures/eggsBenedictSegments.js").then((m) => m.eggsBenedictSegments),
      Cyskqnp1j64: () => import("../fixtures/beefWellingtonSegments.js").then((m) => m.beefWellingtonSegments),
    };
    const fixtureLoader = pilotFixtures[asset.external_id]
      || Object.entries(pilotFixtures).find(([id]) => asset.source_url?.includes(id))?.[1];
    if (fixtureLoader) {
      await setProgress(job.id, asset.id, { stage: "REVIEW_SEGMENTS", progress: 0.85, status: "running" });
      const segments = await fixtureLoader();
      await store.upsertSegments(asset.id, segments);
      await materializePilotClips(asset.id, keys.normalized, workRoot);
      // Prefer blur-fill 9:16 canvases for Adaptive Video Canvas.
      try {
        const { makeVerticalBlurFill, extractThumbnail } = await import("./ffmpeg.js");
        for (const seg of segments) {
          const landscapeKey = `source_assets/${asset.id}/clips/${seg.id}.mp4`;
          const verticalKey = landscapeKey.replace(/\.mp4$/i, ".vertical.mp4");
          const posterKey = landscapeKey.replace(/\.mp4$/i, ".poster.jpg");
          if (!(await objectExists(verticalKey))) {
            const landscapePath = await localObjectPath(landscapeKey);
            const tmpVert = path.join(workRoot, `${seg.id}.vertical.mp4`);
            const tmpPoster = path.join(workRoot, `${seg.id}.poster.jpg`);
            await makeVerticalBlurFill(landscapePath, tmpVert);
            await putObject(verticalKey, tmpVert);
            const mid = Math.max(0.4, (Number(seg.end_seconds) - Number(seg.start_seconds)) * 0.45);
            await extractThumbnail(tmpVert, tmpPoster, mid);
            await putObject(posterKey, tmpPoster);
          }
          await store.load();
          const clip = store.data.clip_assets[seg.id];
          if (clip) {
            clip.vertical_object_key = verticalKey;
            clip.poster_object_key = posterKey;
            clip.presentation_mode = "blurFill";
            if (seg.teaching_label) clip.teaching_label = seg.teaching_label;
            if (seg.visual_cue) clip.visual_cue = seg.visual_cue;
            await store.save();
          }
        }
      } catch (vertErr) {
        console.warn("[pipeline] vertical blur-fill skipped:", vertErr.message);
      }
      try {
        const { runEvidencePackage } = await import("./evidence.js");
        await setProgress(job.id, asset.id, { stage: "DETECT_SCENES", progress: 0.92, status: "running" });
        await runEvidencePackage(asset.id);
      } catch (evidenceErr) {
        console.warn("[pipeline] evidence package skipped:", evidenceErr.message);
      }
      await store.updateSourceAsset(asset.id, { status: "ready" });
    }

    await store.updateJob(job.id, {
      status: "succeeded",
      progress: 1,
      stage: "DONE",
      completed_at: new Date().toISOString(),
      lease_owner: null,
      lease_expires_at: null,
    });

    return store.getSourceAsset(asset.id);
  } catch (err) {
    await store.updateSourceAsset(asset.id, {
      status: "failed",
      error_code: err.code || "INGEST_FAILED",
      error_details: String(err.message || err).slice(0, 2000),
    });
    await store.updateJob(job.id, {
      status: "failed",
      error_code: err.code || "INGEST_FAILED",
      error_details: String(err.message || err).slice(0, 2000),
      completed_at: new Date().toISOString(),
    });
    throw err;
  } finally {
    // Keep work dir for debugging overnight runs; cleanup later.
  }
}

async function materializePilotClips(sourceAssetId, normalizedKey, workRoot) {
  const segments = await store.listApprovedSegments(sourceAssetId);
  const input = await localObjectPath(normalizedKey);
  for (const seg of segments) {
    const dur = Number(seg.end_seconds) - Number(seg.start_seconds);
    if (dur <= 0) continue;
    const clipRel = `source_assets/${sourceAssetId}/clips/${seg.id}.mp4`;
    const thumbRel = `source_assets/${sourceAssetId}/clips/${seg.id}.jpg`;
    if (!(await objectExists(clipRel))) {
      const out = path.join(workRoot, `clip-${seg.id}.mp4`);
      await materializeClip(input, out, Number(seg.start_seconds), dur);
      await putObject(clipRel, out);
    }
    if (!(await objectExists(thumbRel))) {
      const thumb = path.join(workRoot, `thumb-${seg.id}.jpg`);
      const mid = Number(seg.start_seconds) + dur / 2;
      await extractThumbnail(input, thumb, mid);
      await putObject(thumbRel, thumb);
    }
    // store clip asset row
    await store.load();
    store.data.clip_assets[seg.id] = {
      id: seg.id,
      segment_id: seg.id,
      stream_uid: null,
      object_key: clipRel,
      aspect_ratio: "source",
      duration_seconds: dur,
      captions_json: { notice: seg.notice, watch_label: seg.watch_label },
      thumbnail_url: `/media/objects/${thumbRel}`,
      requires_signed_url: false,
      status: "ready",
      created_at: new Date().toISOString(),
    };
    await store.save();
  }
}

export async function createIngestJob({ sourceUrl, rightsRecordId, clearanceNotes }) {
  const { url } = downloaderFor(sourceUrl);
  const platform = (await import("./security.js")).detectPlatform(url);
  const sec = await import("./security.js");
  let externalId = null;
  if (platform === "youtube") externalId = sec.youtubeExternalId(url);
  else if (platform === "tiktok") {
    const parts = new URL(url).pathname.split("/").filter(Boolean);
    const i = parts.indexOf("video");
    if (i >= 0 && parts[i + 1] && /^\d+$/.test(parts[i + 1])) externalId = parts[i + 1];
  }

  let rightsId = rightsRecordId;
  if (!rightsId) {
    const rights = await store.createRightsRecord({
      sourceUrl,
      platform,
      externalId,
      clearanceNotes: clearanceNotes || "Created with ingest request",
      clearedBy: "api",
    });
    rightsId = rights.id;
  } else if (!(await store.getRights(rightsId))) {
    throw Object.assign(new Error("rights_record_id not found"), { code: "RIGHTS_REQUIRED" });
  }

  const asset = await store.createSourceAsset({
    platform,
    sourceUrl,
    externalId,
    rightsRecordId: rightsId,
  });
  const job = await store.createJob({ sourceAssetId: asset.id, jobType: "full_ingest" });
  return { asset, job, rightsRecordId: rightsId };
}
