/**
 * Service-role Supabase REST helpers for the Vercel proxy.
 * Presence-only env checks; never log key material.
 */

export function supabaseConfig() {
  const url = (process.env.SUPABASE_URL || "").trim().replace(/\/$/, "");
  const key = (process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim();
  return url && key ? { url, key } : null;
}

export function supabaseConfigured() {
  return Boolean(supabaseConfig());
}

export async function sb(pathname, { method = "GET", body, prefer } = {}) {
  const cfg = supabaseConfig();
  if (!cfg) {
    const err = new Error("Supabase not configured");
    err.status = 503;
    throw err;
  }
  const headers = {
    apikey: cfg.key,
    Authorization: `Bearer ${cfg.key}`,
  };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    headers.Prefer = prefer || "return=representation";
  } else if (prefer) {
    headers.Prefer = prefer;
  }
  const r = await fetch(`${cfg.url}/rest/v1/${pathname}`, {
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

/** Mint short-lived signed URLs for private Storage objects. */
export async function signStoragePaths(paths, { bucket = "glutt-media", expiresIn = 3600 } = {}) {
  const cfg = supabaseConfig();
  if (!cfg) {
    const err = new Error("Supabase not configured");
    err.status = 503;
    throw err;
  }
  const list = [...new Set((paths || []).filter(Boolean))];
  if (!list.length) return {};
  const r = await fetch(`${cfg.url}/storage/v1/object/sign/${bucket}`, {
    method: "POST",
    headers: {
      apikey: cfg.key,
      Authorization: `Bearer ${cfg.key}`,
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
      : `${cfg.url}/storage/v1${row.signedURL}`;
    out[row.path] = signed;
  }
  return out;
}
