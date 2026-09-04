/**
 * Local progressive MP4 + JSON API for Phase B/C iOS testing before Cloudflare Stream.
 * Serves archived objects and approved segment metadata from LocalStore.
 */
import http from "node:http";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { config } from "./config.js";
import { store } from "./store.js";
import { reviewHTML } from "./reviewPage.js";

/// Pilot path -> YouTube/TikTok id. A map rather than a chain of ternaries,
/// which is what it was: adding the gnocchi demo meant a fourth nested branch
/// and a hand-edited log line that had already drifted.
const PILOT_ROUTES = {
  "/v1/pilot/eggs-benedict": "gBJjRYk0yC0",
  "/v1/pilot/beef-wellington": "Cyskqnp1j64",
  "/v1/pilot/creme-brulee": "6tSdlo0r0Io",
  "/v1/pilot/tiktok-scrambled-eggs": "7333706662634704161",
  "/v1/pilot/gnocchi-brown-butter": "3sUJwjvmzk8",
  "/v1/pilot/butter-chicken": "hDjK5C2aoSs",
};


const ROOT_OBJECTS = path.join(config.dataDir, "objects");

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const raw = Buffer.concat(chunks).toString("utf8");
  if (!raw) return {};
  return JSON.parse(raw);
}

function sendJson(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(data),
    "Access-Control-Allow-Origin": "*",
  });
  res.end(data);
}

async function handleRange(req, res, filePath) {
  const stat = await fsp.stat(filePath);
  const size = stat.size;
  const range = req.headers.range;
  if (!range) {
    res.writeHead(200, {
      "Content-Type": "video/mp4",
      "Content-Length": size,
      "Accept-Ranges": "bytes",
      "Access-Control-Allow-Origin": "*",
    });
    fs.createReadStream(filePath).pipe(res);
    return;
  }
  const m = /^bytes=(\d+)-(\d*)$/.exec(range);
  if (!m) {
    res.writeHead(416);
    return res.end();
  }
  const start = Number(m[1]);
  const end = m[2] ? Number(m[2]) : size - 1;
  if (start >= size || end >= size) {
    res.writeHead(416, { "Content-Range": `bytes */${size}` });
    return res.end();
  }
  res.writeHead(206, {
    "Content-Type": "video/mp4",
    "Content-Length": end - start + 1,
    "Content-Range": `bytes ${start}-${end}/${size}`,
    "Accept-Ranges": "bytes",
    "Access-Control-Allow-Origin": "*",
  });
  fs.createReadStream(filePath, { start, end }).pipe(res);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", `http://127.0.0.1:${config.localPlaybackPort}`);
    if (req.method === "OPTIONS") {
      res.writeHead(204, {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET,OPTIONS",
        "Access-Control-Allow-Headers": "*",
      });
      return res.end();
    }

    if (url.pathname === "/health") {
      return sendJson(res, 200, { ok: true, store: config.storePath });
    }

    if (url.pathname === "/review" || url.pathname === "/review/") {
      const html = reviewHTML();
      res.writeHead(200, {
        "Content-Type": "text/html; charset=utf-8",
        "Content-Length": Buffer.byteLength(html),
      });
      return res.end(html);
    }

    if (req.method === "POST" && url.pathname === "/v1/review/update-bounds") {
      const body = await readBody(req);
      const id = String(body.segment_id || "");
      const start = Number(body.start_seconds);
      const end = Number(body.end_seconds);
      if (!id || !Number.isFinite(start) || !Number.isFinite(end) || end <= start) {
        return sendJson(res, 400, { error: "segment_id, start_seconds, end_seconds required" });
      }
      await store.load();
      const seg = store.data.semantic_segments[id];
      if (!seg) return sendJson(res, 404, { error: "segment not found" });
      seg.start_seconds = start;
      seg.end_seconds = end;
      seg.updated_at = new Date().toISOString();
      seg.review_status = "approved";
      await store.save();
      return sendJson(res, 200, { ok: true, segment: seg });
    }

    if (PILOT_ROUTES[url.pathname]) {
      await store.load();
      const externalId = PILOT_ROUTES[url.pathname];
      const asset = Object.values(store.data.source_assets).find(
        (a) => a.external_id === externalId && a.status !== "revoked"
      );
      if (!asset) {
        return sendJson(res, 404, {
          error: `pilot asset not ready — run ingest + finishPilot for ${externalId}`,
        });
      }
      const segments = await store.listApprovedSegments(asset.id);
      // Prefer the Host the client actually used (phone → Mac LAN IP), not
      // hardcoded 127.0.0.1 — that only works in the iOS Simulator.
      const hostHeader = String(req.headers.host || `127.0.0.1:${config.localPlaybackPort}`);
      const base = `http://${hostHeader}/media/objects/`;
      const clips = segments.map((seg) => {
        const clip = store.data.clip_assets[seg.id] || {};
        const verticalKey = clip.vertical_object_key;
        const landscapeKey = clip.object_key;
        const playbackKey = verticalKey || landscapeKey || asset.normalized_object_key;
        const posterKey = clip.poster_object_key;
        return {
          segment_id: seg.id,
          start_seconds: seg.start_seconds,
          end_seconds: seg.end_seconds,
          duration_seconds: Number(clip.duration_seconds ?? (seg.end_seconds - seg.start_seconds)),
          watch_label: clip.teaching_label || seg.watch_label,
          teaching_label: clip.teaching_label || seg.watch_label,
          notice: seg.notice,
          visual_cue: clip.visual_cue || seg.visual_cue,
          step_keywords: seg.step_keywords || [],
          presentation_mode: clip.presentation_mode || "landscape",
          playback_url: playbackKey ? `${base}${playbackKey}` : null,
          landscape_playback_url: landscapeKey ? `${base}${landscapeKey}` : null,
          thumbnail_url: posterKey
            ? `${base}${posterKey}`
            : (clip.thumbnail_url ? `http://${hostHeader}${clip.thumbnail_url}` : null),
          master_url: asset.normalized_object_key ? `${base}${asset.normalized_object_key}` : null,
          uses_virtual_range: !landscapeKey && !verticalKey,
          creator_attribution: asset.creator_name || "Gordon Ramsay",
        };
      });
      return sendJson(res, 200, {
        source_asset_id: asset.id,
        status: asset.status,
        duration_seconds: asset.duration_seconds,
        title: asset.title,
        clips,
      });
    }

    if (url.pathname.startsWith("/media/objects/")) {
      const key = decodeURIComponent(url.pathname.slice("/media/objects/".length));
      if (key.includes("..")) {
        res.writeHead(400);
        return res.end("bad key");
      }
      const filePath = path.join(ROOT_OBJECTS, key);
      if (!filePath.startsWith(ROOT_OBJECTS)) {
        res.writeHead(400);
        return res.end("bad path");
      }
      try {
        await fsp.access(filePath);
      } catch {
        res.writeHead(404);
        return res.end("missing");
      }
      if (filePath.endsWith(".jpg") || filePath.endsWith(".jpeg")) {
        const buf = await fsp.readFile(filePath);
        res.writeHead(200, {
          "Content-Type": "image/jpeg",
          "Content-Length": buf.length,
          "Access-Control-Allow-Origin": "*",
        });
        return res.end(buf);
      }
      if (filePath.endsWith(".json")) {
        const buf = await fsp.readFile(filePath);
        res.writeHead(200, {
          "Content-Type": "application/json",
          "Content-Length": buf.length,
          "Access-Control-Allow-Origin": "*",
        });
        return res.end(buf);
      }
      return handleRange(req, res, filePath);
    }

    sendJson(res, 404, { error: "not found" });
  } catch (err) {
    sendJson(res, 500, { error: String(err.message || err) });
  }
});

await store.load();
server.listen(config.localPlaybackPort, "0.0.0.0", () => {
  console.log(`[local-playback] http://127.0.0.1:${config.localPlaybackPort}`);
  console.log(
    `[local-playback] pilots: ${Object.keys(PILOT_ROUTES).join(" · ")}`
  );
});
