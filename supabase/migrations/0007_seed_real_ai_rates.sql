-- Real vendor prices, researched 2026-07-29 from official sources:
--   OpenAI:     https://developers.openai.com/api/docs/pricing
--   ElevenLabs: https://elevenlabs.io/pricing/api
--
-- Stored as USD per 1k tokens (vendors quote per 1M, so /1000) or per minute.
--
-- CAVEAT: updating a row re-prices ALL history at the new number. This table
-- answers "what would this usage cost at today's prices", not "what was I
-- actually billed". Fine for spotting which feature eats the money; not an
-- accounting ledger.

-- gpt-realtime-2.1 -- audio $32/$64 per 1M, text $4/$24 per 1M.
-- The 8x audio/text gap is why 0006 split the columns.
update public.ai_rates set
  input_per_1k         = 0.004,
  output_per_1k        = 0.024,
  audio_input_per_1k   = 0.032,
  audio_output_per_1k  = 0.064
where model = 'gpt-realtime-2.1';

-- gpt-4o-mini-tts -- text in $0.60/1M, audio out $12/1M.
-- NOTE: /audio/speech returns raw mp3 with no usage object, so audio output
-- tokens are never logged. polly_speak rows therefore cost only their (tiny)
-- text-input term and systematically UNDERCOUNT. Known gap.
update public.ai_rates set
  input_per_1k        = 0.0006,
  audio_output_per_1k = 0.012
where model = 'gpt-4o-mini-tts';

-- gpt-4o-transcribe -- audio in $2.50/1M, text out $10/1M (~$0.006/min).
-- Used INSIDE the Polly realtime session for input transcription and billed on
-- top of realtime audio. Not logged separately -- another known undercount.
update public.ai_rates set
  audio_input_per_1k = 0.0025,
  output_per_1k      = 0.010
where model = 'gpt-4o-transcribe';

-- ElevenLabs Scribe v2 -- $0.22 per hour of input audio = $0.0036667/min.
update public.ai_rates set
  audio_input_per_min = 0.00366667
where model = 'scribe_v2';
