/**
 * Service-role Supabase REST + Storage helpers for the media worker.
 * Never import this from client code.
 */
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import path from "node:path";
import { config } from "./config.js";

export function supabaseConfigured() {
  return Boolean(config.supabase.url && config.supabase.serviceRoleKey);
}

function base() {
  return config.supabase.url.replace(/\/$/, "");
}

function key() {
  return config.supabase.serviceRoleKey;
}

export async function sb(pathname, { method = "GET", body, prefer } = {}) {
  const headers = {
    apikey: key(),
    Authorization: `Bearer ${key()}`,
  };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    headers.Prefer = prefer || "return=representation";
  } else if (prefer) {
    headers.Prefer = prefer;
  }
  const r = await fetch(`${base()}/rest/v1/${pathname}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  if (!r.ok) {
    const err = new Error(json?.message || json?.error || text || `supabase ${r.status}`);
    err.status = r.status;
    err.body = json;
    throw err;
  }
  return json;
}

/** Upsert rows. `onConflict` is a comma-separated column list matching a UNIQUE/PK. */
export async function sbUpsert(table, rows, onConflict) {
  const list = Array.isArray(rows) ? rows : [rows];
  if (!list.length) return [];
  const q = onConflict ? `?on_conflict=${encodeURIComponent(onConflict)}` : "";
  return sb(`${table}${q}`, {
    method: "POST",
    body: list,
    prefer: "resolution=merge-duplicates,return=representation",
  });
}

const CONTENT_TYPES = {
  ".mp4": "video/mp4",
  ".m4a": "audio/mp4",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".json": "application/json",
};

/**
 * Upload a local file into the private `glutt-media` bucket at objectKey.
 * Uses upsert so re-syncs are idempotent.
 */
export async function uploadStorageObject(objectKey, absolutePath, { bucket = "glutt-media" } = {}) {
  const ext = path.extname(absolutePath).toLowerCase();
  const contentType = CONTENT_TYPES[ext] || "application/octet-stream";
  const size = (await stat(absolutePath)).size;
  const encodedKey = objectKey.split("/").map(encodeURIComponent).join("/");
  const url = `${base()}/storage/v1/object/${bucket}/${encodedKey}`;
  const r = await fetch(url, {
    method: "POST",
    headers: {
      apikey: key(),
      Authorization: `Bearer ${key()}`,
      "Content-Type": contentType,
      "x-upsert": "true",
      "Content-Length": String(size),
    },
    body: createReadStream(absolutePath),
    duplex: "half",
  });
  const text = await r.text();
  if (!r.ok) {
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = { raw: text };
    }
    const err = new Error(json?.message || json?.error || text || `storage upload ${r.status}`);
    err.status = r.status;
    err.body = json;
    throw err;
  }
  return { bucket, objectKey, bytes: size };
}

export async function createSignedUrls(paths, { bucket = "glutt-media", expiresIn = 3600 } = {}) {
  const list = [...new Set((paths || []).filter(Boolean))];
  if (!list.length) return {};
  const r = await fetch(`${base()}/storage/v1/object/sign/${bucket}`, {
    method: "POST",
    headers: {
      apikey: key(),
      Authorization: `Bearer ${key()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ paths: list, expiresIn }),
  });
  const json = await r.json().catch(() => ({}));
  if (!r.ok) {
    const err = new Error(json?.message || json?.error || `sign ${r.status}`);
    err.status = r.status;
    err.body = json;
    throw err;
  }
  const out = {};
  for (const row of json || []) {
    if (!row?.path || !row?.signedURL) continue;
    const signed = String(row.signedURL).startsWith("http")
      ? row.signedURL
      : `${base()}/storage/v1${row.signedURL}`;
    out[row.path] = signed;
  }
  return out;
}
