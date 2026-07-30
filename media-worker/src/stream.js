import { config, streamEnabled } from "./config.js";

/**
 * Cloudflare Stream ingest (Phase B cloud). No-op when CF_STREAM_* unset —
 * local progressive MP4 via serve-local covers the pilot.
 */
export async function ingestFromUrl(downloadableUrl, meta = {}) {
  if (!streamEnabled()) {
    return { ready: false, skipped: true, reason: "CF_STREAM_API_TOKEN not configured" };
  }
  const accountId = config.stream.accountId;
  const token = config.stream.apiToken;
  const r = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${accountId}/stream/copy`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        url: downloadableUrl,
        meta: { name: meta.name || meta.sourceAssetId || "glutt-source" },
        requireSignedURLs: true,
      }),
    }
  );
  const json = await r.json();
  if (!r.ok || !json.success) {
    const err = new Error(json?.errors?.[0]?.message || `Stream copy failed ${r.status}`);
    err.body = json;
    throw err;
  }
  const result = json.result || {};
  return {
    ready: result.readyToStream === true,
    streamUid: result.uid,
    hls: result.playback?.hls || null,
    duration: result.duration || null,
    skipped: false,
  };
}
