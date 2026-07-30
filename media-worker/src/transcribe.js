import fs from "node:fs";
import { config } from "./config.js";
import { localObjectPath } from "./storage.js";
import { store } from "./store.js";

/**
 * ElevenLabs Scribe v2 word-level transcript (Phase D).
 * Skips cleanly when ELEVENLABS_API_KEY is unset.
 */
export async function transcribeSourceAsset(sourceAssetId) {
  const key = (process.env.ELEVENLABS_API_KEY || process.env.ELEVEN_LABS_API_KEY || "").trim();
  if (!key) {
    return { skipped: true, reason: "ELEVENLABS_API_KEY not set" };
  }
  const asset = await store.getSourceAsset(sourceAssetId);
  if (!asset?.audio_object_key) throw new Error("audio.m4a missing — run ingest first");
  const audioPath = await localObjectPath(asset.audio_object_key);

  const form = new FormData();
  const blob = new Blob([fs.readFileSync(audioPath)], { type: "audio/mp4" });
  form.append("file", blob, "audio.m4a");
  form.append("model_id", "scribe_v2");
  form.append("timestamps_granularity", "word");

  const r = await fetch("https://api.elevenlabs.io/v1/speech-to-text", {
    method: "POST",
    headers: { "xi-api-key": key },
    body: form,
  });
  const json = await r.json();
  if (!r.ok) {
    const err = new Error(json?.detail?.message || json?.message || `transcribe ${r.status}`);
    err.body = json;
    throw err;
  }

  await store.load();
  for (const [id, row] of Object.entries(store.data.transcript_words)) {
    if (row.source_asset_id === sourceAssetId) delete store.data.transcript_words[id];
  }
  const words = json.words || json.alignment?.words || [];
  let count = 0;
  for (const w of words) {
    const text = w.text || w.word || "";
    if (!text) continue;
    const id = globalThis.crypto.randomUUID();
    store.data.transcript_words[id] = {
      id,
      source_asset_id: sourceAssetId,
      start_seconds: Number(w.start ?? w.start_time ?? 0),
      end_seconds: Number(w.end ?? w.end_time ?? 0),
      text,
      speaker_id: w.speaker_id || null,
      word_type: w.type === "audio_event" ? "audio_event" : "word",
      created_at: new Date().toISOString(),
    };
    count += 1;
  }
  await store.save();
  return { skipped: false, words: count };
}
