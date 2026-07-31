#!/usr/bin/env node
/**
 * Promote LocalStore pilots → Supabase Postgres + private Storage.
 *
 * Prereqs:
 *   1. Apply supabase/migrations/0011_media_source_assets.sql in the SQL editor
 *   2. media-worker/.env with SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
 *
 * Usage:
 *   cd media-worker && npm run sync:supabase
 *   npm run sync:supabase -- --external-id=gBJjRYk0yC0
 *   npm run sync:supabase -- --metadata-only
 */
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

async function loadDotEnv() {
  try {
    const raw = await fs.readFile(path.join(root, ".env"), "utf8");
    for (const line of raw.split("\n")) {
      const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
      if (!m) continue;
      const k = m[1];
      let v = m[2].trim();
      if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
        v = v.slice(1, -1);
      }
      if (process.env[k] == null || process.env[k] === "") process.env[k] = v;
    }
  } catch {
    // optional
  }
}

function parseArgs(argv) {
  const out = { externalId: null, metadataOnly: false };
  for (const a of argv) {
    if (a === "--metadata-only") out.metadataOnly = true;
    else if (a.startsWith("--external-id=")) out.externalId = a.slice("--external-id=".length);
  }
  return out;
}

function asArray(obj) {
  return Object.values(obj || {});
}

function rightsRow(r) {
  return {
    id: r.id,
    source_url: r.source_url,
    platform: r.platform || null,
    external_id: r.external_id || null,
    clearance_notes: r.clearance_notes || null,
    cleared_by: r.cleared_by || null,
    cleared_at: r.cleared_at || new Date().toISOString(),
    license_type: r.license_type || null,
    expires_at: r.expires_at || null,
    metadata_json: r.metadata_json || {},
    created_at: r.created_at || new Date().toISOString(),
  };
}

function assetRow(a) {
  return {
    id: a.id,
    platform: a.platform,
    source_url: a.source_url,
    external_id: a.external_id || null,
    creator_id: a.creator_id || null,
    rights_record_id: a.rights_record_id,
    status: a.status || "ready",
    title: a.title || null,
    description: a.description || null,
    creator_name: a.creator_name || null,
    original_published_at: a.original_published_at || null,
    duration_seconds: a.duration_seconds ?? null,
    sha256: a.sha256 || null,
    perceptual_hash: a.perceptual_hash || null,
    original_object_key: a.original_object_key || null,
    normalized_object_key: a.normalized_object_key || null,
    analysis_proxy_object_key: a.analysis_proxy_object_key || null,
    audio_object_key: a.audio_object_key || null,
    stream_uid: a.stream_uid || null,
    width: a.width ?? null,
    height: a.height ?? null,
    probe_json: a.probe_json || {},
    error_code: a.error_code || null,
    error_details: a.error_details || null,
    created_at: a.created_at || new Date().toISOString(),
    updated_at: a.updated_at || new Date().toISOString(),
  };
}

function segmentRow(s) {
  return {
    id: s.id,
    source_asset_id: s.source_asset_id,
    start_seconds: s.start_seconds,
    end_seconds: s.end_seconds,
    primary_action: s.primary_action || null,
    secondary_actions_json: s.secondary_actions_json || [],
    ingredients_json: s.ingredients_json || [],
    tools_json: s.tools_json || [],
    starting_state: s.starting_state || null,
    ending_state: s.ending_state || null,
    technique: s.technique || null,
    dish_stage: s.dish_stage || null,
    visual_questions_json: s.visual_questions_json || [],
    visual_cue: s.visual_cue || null,
    audio_useful: Boolean(s.audio_useful),
    visual_quality: s.visual_quality ?? null,
    boundary_confidence: s.boundary_confidence ?? null,
    review_status: s.review_status || "pending",
    model_version: s.model_version || null,
    notice: s.notice || null,
    watch_label: s.watch_label || null,
    step_keywords_json: s.step_keywords || s.step_keywords_json || [],
    created_at: s.created_at || new Date().toISOString(),
    updated_at: s.updated_at || new Date().toISOString(),
  };
}

function clipRow(c) {
  return {
    id: c.id,
    segment_id: c.segment_id,
    stream_uid: c.stream_uid || null,
    object_key: c.object_key || null,
    vertical_object_key: c.vertical_object_key || null,
    poster_object_key: c.poster_object_key || null,
    aspect_ratio: c.aspect_ratio || null,
    presentation_mode: c.presentation_mode || null,
    teaching_label: c.teaching_label || null,
    duration_seconds: c.duration_seconds ?? null,
    captions_json: c.captions_json || {},
    thumbnail_url: c.thumbnail_url || null,
    requires_signed_url: c.requires_signed_url !== false,
    status: c.status || "ready",
    created_at: c.created_at || new Date().toISOString(),
  };
}

async function main() {
  await loadDotEnv();
  const args = parseArgs(process.argv.slice(2));

  const { config } = await import("../src/config.js");
  const { store } = await import("../src/store.js");
  const { localObjectPath } = await import("../src/storage.js");
  const {
    supabaseConfigured,
    sbUpsert,
    uploadStorageObject,
  } = await import("../src/supabaseAdmin.js");

  if (!supabaseConfigured()) {
    console.error(`
Missing Supabase credentials.

Create media-worker/.env:

  SUPABASE_URL=https://mlgdtksukpifkmhqulnc.supabase.co
  SUPABASE_SERVICE_ROLE_KEY=<from Supabase → Project Settings → API>

Also apply supabase/migrations/0011_media_source_assets.sql in the SQL editor first.
`);
    process.exit(1);
  }

  await store.load();
  let assets = asArray(store.data.source_assets).filter((a) => a.status !== "revoked");
  if (args.externalId) {
    assets = assets.filter((a) => a.external_id === args.externalId);
    if (!assets.length) {
      console.error(`No local source_asset with external_id=${args.externalId}`);
      process.exit(1);
    }
  }

  const assetIds = new Set(assets.map((a) => a.id));
  const rightsIds = new Set(assets.map((a) => a.rights_record_id).filter(Boolean));
  const rights = asArray(store.data.rights_records).filter((r) => rightsIds.has(r.id));
  const segments = asArray(store.data.semantic_segments).filter((s) => assetIds.has(s.source_asset_id));
  const segmentIds = new Set(segments.map((s) => s.id));
  const clips = asArray(store.data.clip_assets).filter((c) => segmentIds.has(c.segment_id));

  console.log(`Syncing ${assets.length} asset(s), ${segments.length} segments, ${clips.length} clips → ${config.supabase.url}`);

  if (rights.length) {
    await sbUpsert("rights_records", rights.map(rightsRow), "id");
    console.log(`✓ rights_records (${rights.length})`);
  }
  if (assets.length) {
    await sbUpsert("source_assets", assets.map(assetRow), "id");
    console.log(`✓ source_assets (${assets.length})`);
  }
  if (segments.length) {
    await sbUpsert("semantic_segments", segments.map(segmentRow), "id");
    console.log(`✓ semantic_segments (${segments.length})`);
  }
  if (clips.length) {
    await sbUpsert("clip_assets", clips.map(clipRow), "id");
    console.log(`✓ clip_assets (${clips.length})`);
  }

  if (args.metadataOnly) {
    console.log("Metadata-only sync done (skipped Storage uploads).");
    return;
  }

  async function exists(objectKey) {
    if (!objectKey) return false;
    try {
      await fs.access(await localObjectPath(objectKey));
      return true;
    } catch {
      return false;
    }
  }

  const keys = [];
  for (const c of clips) {
    const playback = (await exists(c.vertical_object_key))
      ? c.vertical_object_key
      : c.object_key;
    keys.push(playback);
    keys.push(c.poster_object_key);
  }
  const unique = [...new Set(keys.filter(Boolean))];
  console.log(`Uploading ${unique.length} playback object(s) to storage.glutt-media …`);
  let ok = 0;
  for (const objectKey of unique) {
    const abs = await localObjectPath(objectKey);
    try {
      await fs.access(abs);
    } catch {
      console.warn(`  skip missing: ${objectKey}`);
      continue;
    }
    const result = await uploadStorageObject(objectKey, abs);
    console.log(`  ↑ ${(result.bytes / (1024 * 1024)).toFixed(1)}MB  ${objectKey}`);
    ok += 1;
  }
  console.log(`Done. Uploaded ${ok}/${unique.length}. App: GET/POST /api/media/clips?external_id=…`);
}

main().catch((err) => {
  console.error(err.body || err);
  process.exit(1);
});
