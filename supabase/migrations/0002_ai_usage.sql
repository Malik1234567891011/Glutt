-- Accounts + AI usage tracking — step 1 of docs/plan-accounts-and-ai-usage.md
-- One row per AI call through vercel-ai-proxy. Written ONLY by the proxy
-- (service role, which bypasses RLS). No client ever reads or writes this.

create table public.ai_usage (
  id                   bigint generated always as identity primary key,
  user_id              uuid references auth.users on delete set null,
  install_id           text,
  feature              text not null,
  model                text,
  input_tokens         integer,
  output_tokens        integer,
  audio_input_seconds  numeric,
  audio_output_seconds numeric,
  duration_ms          integer,
  ok                   boolean not null default true,
  created_at           timestamptz not null default now()
);

comment on column public.ai_usage.feature is
  'polly_session | polly_speak | chat | import_reddit | transcribe | plates_deck | plates_search | discover_search | discover_suggested | discover_player';
comment on column public.ai_usage.user_id is
  'Null for calls made before sign-in, and for the GluttShare extension which has no Supabase session. Back-fill via install_id.';

create index ai_usage_user_created_idx    on public.ai_usage (user_id, created_at desc);
create index ai_usage_feature_created_idx on public.ai_usage (feature, created_at desc);
create index ai_usage_install_idx         on public.ai_usage (install_id) where user_id is null;

-- Prices live here, not on the rows, so a price change does not rewrite history.
-- An unknown model left-joins to nothing and costs 0 — visible as $0 in the
-- per-feature query, which is the signal to add a row here.
create table public.ai_rates (
  model                text primary key,
  input_per_1k         numeric default 0,
  output_per_1k        numeric default 0,
  audio_input_per_min  numeric default 0,
  audio_output_per_min numeric default 0
);

-- security_invoker: without it the view runs as its owner and would expose
-- ai_usage to any client despite the RLS lock-down below.
create view public.ai_usage_costed with (security_invoker = on) as
select
  u.*,
  coalesce(u.input_tokens, 0)         / 1000.0 * coalesce(r.input_per_1k, 0)
+ coalesce(u.output_tokens, 0)        / 1000.0 * coalesce(r.output_per_1k, 0)
+ coalesce(u.audio_input_seconds, 0)  / 60.0   * coalesce(r.audio_input_per_min, 0)
+ coalesce(u.audio_output_seconds, 0) / 60.0   * coalesce(r.audio_output_per_min, 0)
  as cost_usd
from public.ai_usage u
left join public.ai_rates r on r.model = u.model;

-- RLS on with zero policies: no client can read or write. The proxy uses the
-- service role, which bypasses RLS.
alter table public.ai_usage enable row level security;
alter table public.ai_rates enable row level security;

revoke all on public.ai_usage        from anon, authenticated;
revoke all on public.ai_rates        from anon, authenticated;
revoke all on public.ai_usage_costed from anon, authenticated;
