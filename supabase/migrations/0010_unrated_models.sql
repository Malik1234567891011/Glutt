-- A model logged with no `ai_rates` row prices at $0 and looks like a free
-- feature rather than a bug. That is how `gpt-4o` went unpriced from the day
-- usage logging shipped (fixed in 0009). This view makes the next one visible
-- instead of invisible.
--
-- Quota vendors are excluded by design: `discover` and `plates` are logged with
-- a `vendor:endpoint` model string that deliberately matches no rate row, so
-- they cost $0 by construction. Every other unmatched model is a mistake.
--
-- `security_invoker = on` for the same reason as `ai_usage_costed`: without it
-- the view runs as its owner and hands the RLS-locked `ai_usage` to any client.

create or replace view public.ai_usage_unrated
with (security_invoker = on) as
select
  u.model,
  count(*)          as calls,
  min(u.created_at) as first_seen,
  max(u.created_at) as last_seen
from public.ai_usage u
left join public.ai_rates r on r.model = u.model
where u.model is not null
  and r.model is null
  and u.model not like '%:%'   -- vendor:endpoint quota calls, $0 on purpose
group by u.model
order by calls desc;

comment on view public.ai_usage_unrated is
  'Models logged to ai_usage with no ai_rates row — their spend is silently costing $0. Should always be empty; anything here needs a rate seeded.';
