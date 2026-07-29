-- Vendors bill audio tokens and text tokens at very different rates on the SAME
-- model -- gpt-realtime-2.1 is $32/M for audio input but $4/M for text input, an
-- 8x gap. The original two-rate shape could not express that, which would have
-- forced a fudge on the dominant cost term. Both tables were still empty, so
-- widening was free.

alter table public.ai_usage
  add column audio_input_tokens  integer,
  add column audio_output_tokens integer;

comment on column public.ai_usage.audio_input_tokens is
  'Audio tokens billed, from the Realtime response.done usage object. Distinct from input_tokens (text), which is priced far lower.';

alter table public.ai_rates
  add column audio_input_per_1k  numeric default 0,
  add column audio_output_per_1k numeric default 0;

-- Recreated rather than replaced: u.* now yields more columns, so the view's
-- column order changes and create-or-replace would reject it.
drop view public.ai_usage_costed;

create view public.ai_usage_costed with (security_invoker = on) as
select
  u.*,
  coalesce(u.input_tokens, 0)         / 1000.0 * coalesce(r.input_per_1k, 0)
+ coalesce(u.output_tokens, 0)        / 1000.0 * coalesce(r.output_per_1k, 0)
+ coalesce(u.audio_input_tokens, 0)   / 1000.0 * coalesce(r.audio_input_per_1k, 0)
+ coalesce(u.audio_output_tokens, 0)  / 1000.0 * coalesce(r.audio_output_per_1k, 0)
+ coalesce(u.audio_input_seconds, 0)  / 60.0   * coalesce(r.audio_input_per_min, 0)
+ coalesce(u.audio_output_seconds, 0) / 60.0   * coalesce(r.audio_output_per_min, 0)
  as cost_usd
from public.ai_usage u
left join public.ai_rates r on r.model = u.model;

revoke all on public.ai_usage_costed from anon, authenticated;
