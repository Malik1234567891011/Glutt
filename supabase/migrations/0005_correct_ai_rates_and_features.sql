-- Corrections after reading every proxy endpoint. The original spec assumed all
-- 10 endpoints were token/audio-billed AI calls against one vendor. They are not.
--
-- 1. import/transcribe uses ElevenLabs Scribe v2, NOT gpt-4o-transcribe.
--    Scribe bills per minute of audio. ElevenLabs is a second paying vendor.
-- 2. gpt-4o-transcribe IS still used -- inside the Polly realtime session for
--    input transcription (api/polly/session.js:91), not on the import path.
-- 3. polly_realtime is a new feature: session-end audio seconds reported by the
--    app via POST /api/polly/usage. polly_session is only the token mint, and
--    cannot know the duration of the WebRTC session it unlocks.
-- 4. plates/* is Spoonacular and discover/* is YouTube Data -- quota-billed, not
--    dollar-billed, and edge-cached, so logged rows are cache MISSES only.
-- 5. discover_player is NOT instrumented -- it renders static HTML, makes no
--    upstream API call, and has no proxy-key gate to attribute by.

insert into public.ai_rates (model, audio_input_per_min)
values ('scribe_v2', 0)
on conflict (model) do nothing;

comment on table public.ai_rates is
  'USD rates per model. Rows are joined by ai_usage.model; an unmatched model costs $0. Quota-billed vendors (spoonacular:*, youtube:*) deliberately have no row -- their cost is API quota, not dollars.';

comment on column public.ai_usage.feature is
  'polly_session (token mint) | polly_realtime (session-end audio seconds) | polly_speak | chat | transcribe | import_reddit | plates_deck | plates_search | discover_search | discover_suggested';

comment on column public.ai_usage.model is
  'OpenAI/ElevenLabs model id for dollar-billed calls; a vendor:endpoint string (spoonacular:complexSearch, youtube:search.list) for quota-billed ones, which never match ai_rates and so cost $0 by design.';
