import fs from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import { config } from "./config.js";

function uuid() {
  return crypto.randomUUID();
}

function now() {
  return new Date().toISOString();
}

async function ensureParent(filePath) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
}

const emptyStore = () => ({
  rights_records: {},
  source_assets: {},
  ingestion_jobs: {},
  transcript_words: {},
  video_scenes: {},
  semantic_segments: {},
  clip_assets: {},
  recipe_step_intents: {},
  step_segment_matches: {},
});

export class LocalStore {
  constructor(filePath = config.storePath) {
    this.filePath = filePath;
    this.data = emptyStore();
    this._loaded = false;
  }

  async load() {
    if (this._loaded) return this;
    await ensureParent(this.filePath);
    try {
      const raw = await fs.readFile(this.filePath, "utf8");
      this.data = { ...emptyStore(), ...JSON.parse(raw) };
    } catch (err) {
      if (err.code !== "ENOENT") throw err;
      await this.save();
    }
    this._loaded = true;
    return this;
  }

  async save() {
    await ensureParent(this.filePath);
    const tmp = `${this.filePath}.tmp`;
    await fs.writeFile(tmp, JSON.stringify(this.data, null, 2));
    await fs.rename(tmp, this.filePath);
  }

  async createRightsRecord({ sourceUrl, platform, externalId, clearanceNotes, clearedBy, licenseType }) {
    await this.load();
    const id = uuid();
    const row = {
      id,
      source_url: sourceUrl,
      platform,
      external_id: externalId || null,
      clearance_notes: clearanceNotes || "",
      cleared_by: clearedBy || "system",
      cleared_at: now(),
      license_type: licenseType || "pilot_cleared",
      metadata_json: {},
      created_at: now(),
    };
    this.data.rights_records[id] = row;
    await this.save();
    return row;
  }

  async getRights(id) {
    await this.load();
    return this.data.rights_records[id] || null;
  }

  async createSourceAsset({ platform, sourceUrl, externalId, rightsRecordId }) {
    await this.load();
    if (!this.data.rights_records[rightsRecordId]) {
      throw Object.assign(new Error("rights_record_id required / missing"), { code: "RIGHTS_REQUIRED" });
    }
    const id = uuid();
    const row = {
      id,
      platform,
      source_url: sourceUrl,
      external_id: externalId || null,
      creator_id: null,
      rights_record_id: rightsRecordId,
      status: "queued",
      title: null,
      description: null,
      creator_name: null,
      duration_seconds: null,
      sha256: null,
      perceptual_hash: null,
      original_object_key: null,
      normalized_object_key: null,
      analysis_proxy_object_key: null,
      audio_object_key: null,
      stream_uid: null,
      width: null,
      height: null,
      probe_json: {},
      error_code: null,
      error_details: null,
      created_at: now(),
      updated_at: now(),
    };
    this.data.source_assets[id] = row;
    await this.save();
    return row;
  }

  async updateSourceAsset(id, patch) {
    await this.load();
    const row = this.data.source_assets[id];
    if (!row) throw new Error(`source_asset not found: ${id}`);
    Object.assign(row, patch, { updated_at: now() });
    await this.save();
    return row;
  }

  async getSourceAsset(id) {
    await this.load();
    return this.data.source_assets[id] || null;
  }

  async findBySha256(sha) {
    await this.load();
    return Object.values(this.data.source_assets).find(
      (a) => a.sha256 === sha && a.status !== "revoked"
    ) || null;
  }

  async createJob({ sourceAssetId, jobType = "full_ingest" }) {
    await this.load();
    const id = uuid();
    const row = {
      id,
      source_asset_id: sourceAssetId,
      job_type: jobType,
      status: "queued",
      attempt_count: 0,
      progress: 0,
      stage: null,
      lease_owner: null,
      lease_expires_at: null,
      error_code: null,
      error_details: null,
      started_at: null,
      completed_at: null,
      created_at: now(),
      updated_at: now(),
    };
    this.data.ingestion_jobs[id] = row;
    await this.save();
    return row;
  }

  async getJob(id) {
    await this.load();
    return this.data.ingestion_jobs[id] || null;
  }

  async updateJob(id, patch) {
    await this.load();
    const row = this.data.ingestion_jobs[id];
    if (!row) throw new Error(`job not found: ${id}`);
    Object.assign(row, patch, { updated_at: now() });
    await this.save();
    return row;
  }

  async claimNextJob(workerId, leaseSeconds) {
    await this.load();
    const queued = Object.values(this.data.ingestion_jobs)
      .filter((j) => j.status === "queued" || (j.status === "leased" && j.lease_expires_at && j.lease_expires_at < now()))
      .sort((a, b) => a.created_at.localeCompare(b.created_at));
    const job = queued[0];
    if (!job) return null;
    const expires = new Date(Date.now() + leaseSeconds * 1000).toISOString();
    Object.assign(job, {
      status: "leased",
      lease_owner: workerId,
      lease_expires_at: expires,
      attempt_count: (job.attempt_count || 0) + 1,
      started_at: job.started_at || now(),
      updated_at: now(),
    });
    await this.save();
    return job;
  }

  async upsertSegments(sourceAssetId, segments) {
    await this.load();
    // Replace pending/manual pilot segments for this asset by watch_label+start
    for (const seg of segments) {
      const id = seg.id || uuid();
      this.data.semantic_segments[id] = {
        id,
        source_asset_id: sourceAssetId,
        start_seconds: seg.start_seconds,
        end_seconds: seg.end_seconds,
        primary_action: seg.primary_action || null,
        secondary_actions_json: seg.secondary_actions || [],
        ingredients_json: seg.ingredients || [],
        tools_json: seg.tools || [],
        starting_state: seg.starting_state || null,
        ending_state: seg.ending_state || null,
        technique: seg.technique || null,
        dish_stage: seg.dish_stage || null,
        visual_questions_json: seg.visual_questions || [],
        visual_cue: seg.visual_cue || null,
        audio_useful: Boolean(seg.audio_useful),
        visual_quality: seg.visual_quality ?? null,
        boundary_confidence: seg.boundary_confidence ?? null,
        review_status: seg.review_status || "approved",
        model_version: seg.model_version || "manual-pilot",
        notice: seg.notice || null,
        watch_label: seg.watch_label || null,
        step_keywords: seg.step_keywords || [],
        created_at: now(),
        updated_at: now(),
      };
    }
    await this.save();
  }

  async listApprovedSegments(sourceAssetId) {
    await this.load();
    return Object.values(this.data.semantic_segments).filter(
      (s) => s.source_asset_id === sourceAssetId && s.review_status === "approved"
    );
  }

  async revokeSourceAsset(id) {
    await this.load();
    const asset = this.data.source_assets[id];
    if (!asset) throw new Error("not found");
    asset.status = "revoked";
    asset.updated_at = now();
    for (const seg of Object.values(this.data.semantic_segments)) {
      if (seg.source_asset_id === id) seg.review_status = "rejected";
    }
    for (const clip of Object.values(this.data.clip_assets)) {
      const seg = this.data.semantic_segments[clip.segment_id];
      if (seg && seg.source_asset_id === id) clip.status = "revoked";
    }
    await this.save();
    return asset;
  }
}

export const store = new LocalStore();
