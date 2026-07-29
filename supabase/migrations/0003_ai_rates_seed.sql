-- Accounts + AI usage tracking — step 1 of docs/plan-accounts-and-ai-usage.md
-- Seed ai_rates with the models vercel-ai-proxy actually calls today.
--
-- SUPERSEDED IN PART BY 0005: the gpt-4o-transcribe attribution below is wrong.
-- import/transcribe uses ElevenLabs Scribe v2; gpt-4o-transcribe is used inside
-- the Polly realtime session config. Kept as applied, corrected in 0005.
--
-- PRICES ARE PLACEHOLDERS (0). Fill them from the current OpenAI pricing page
-- before trusting any cost number — until then ai_usage_costed reports $0 and
-- only the call counts are meaningful.
--
--   gpt-realtime-2.1  — api/polly/session.js  (POLLY_REALTIME_MODEL override)
--   gpt-4o-mini-tts   — api/polly/speak.js    (POLLY_TTS_MODEL override)
--   gpt-4o-transcribe — api/import/transcribe.js
--
-- api/chat/completions.js forwards a client-supplied model; add a row per model
-- the app sends. An unrecognised model costs 0 rather than erroring.

insert into public.ai_rates (model, input_per_1k, output_per_1k, audio_input_per_min, audio_output_per_min)
values
  ('gpt-realtime-2.1',  0, 0, 0, 0),
  ('gpt-4o-mini-tts',   0, 0, 0, 0),
  ('gpt-4o-transcribe', 0, 0, 0, 0)
on conflict (model) do nothing;
