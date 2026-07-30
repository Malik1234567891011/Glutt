-- Media ingest control plane (docs/donwloadplan.md §18 + rights_records).
-- Service role / worker writes; clients never get direct R2/Stream credentials.

create extension if not exists pgcrypto;

create table public.rights_records (
  id              uuid primary key default gen_random_uuid(),
  source_url      text not null,
  platform        text,
  external_id     text,
  clearance_notes text,
  cleared_by      text,
  cleared_at      timestamptz not null default now(),
  license_type    text,
  expires_at      timestamptz,
  metadata_json   jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);

comment on table public.rights_records is
  'Required before any download. Product assumes rights are cleared externally.';

create table public.source_assets (
  id                         uuid primary key default gen_random_uuid(),
  platform                   text not null
    check (platform in ('youtube','tiktok','instagram','creator_upload','web','other')),
  source_url                 text not null,
  external_id                text,
  creator_id                 text,
  rights_record_id           uuid not null references public.rights_records(id),
  status                     text not null default 'queued'
    check (status in (
      'queued','probing','downloading','uploaded','normalizing','analysing',
      'review_required','ready','failed','revoked'
    )),
  title                      text,
  description                text,
  creator_name               text,
  original_published_at      timestamptz,
  duration_seconds           numeric,
  sha256                     text,
  perceptual_hash            text,
  original_object_key        text,
  normalized_object_key      text,
  analysis_proxy_object_key  text,
  audio_object_key           text,
  stream_uid                 text,
  width                      integer,
  height                     integer,
  probe_json                 jsonb not null default '{}'::jsonb,
  error_code                 text,
  error_details              text,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now()
);

create unique index source_assets_sha256_uidx
  on public.source_assets (sha256)
  where sha256 is not null and status <> 'revoked';

create index source_assets_status_idx on public.source_assets (status);
create index source_assets_external_id_idx on public.source_assets (platform, external_id);

create table public.ingestion_jobs (
  id               uuid primary key default gen_random_uuid(),
  source_asset_id  uuid not null references public.source_assets(id) on delete cascade,
  job_type         text not null,
  status           text not null default 'queued'
    check (status in ('queued','leased','running','succeeded','failed','cancelled')),
  attempt_count    integer not null default 0,
  progress         numeric not null default 0,
  stage            text,
  lease_owner      text,
  lease_expires_at timestamptz,
  error_code       text,
  error_details    text,
  started_at       timestamptz,
  completed_at     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index ingestion_jobs_claim_idx
  on public.ingestion_jobs (status, created_at)
  where status in ('queued','leased');

create table public.transcript_words (
  id               uuid primary key default gen_random_uuid(),
  source_asset_id  uuid not null references public.source_assets(id) on delete cascade,
  start_seconds    numeric not null,
  end_seconds      numeric not null,
  text             text not null,
  speaker_id       text,
  word_type        text not null default 'word'
    check (word_type in ('word','audio_event')),
  created_at       timestamptz not null default now()
);

create index transcript_words_asset_idx
  on public.transcript_words (source_asset_id, start_seconds);

create table public.video_scenes (
  id               uuid primary key default gen_random_uuid(),
  source_asset_id  uuid not null references public.source_assets(id) on delete cascade,
  start_seconds    numeric not null,
  end_seconds      numeric not null,
  scene_score      numeric,
  created_at       timestamptz not null default now()
);

create index video_scenes_asset_idx
  on public.video_scenes (source_asset_id, start_seconds);

create table public.semantic_segments (
  id                     uuid primary key default gen_random_uuid(),
  source_asset_id        uuid not null references public.source_assets(id) on delete cascade,
  start_seconds          numeric not null,
  end_seconds            numeric not null,
  primary_action         text,
  secondary_actions_json jsonb not null default '[]'::jsonb,
  ingredients_json       jsonb not null default '[]'::jsonb,
  tools_json             jsonb not null default '[]'::jsonb,
  starting_state         text,
  ending_state           text,
  technique              text,
  dish_stage             text,
  visual_questions_json  jsonb not null default '[]'::jsonb,
  visual_cue             text,
  audio_useful           boolean not null default false,
  visual_quality         numeric,
  boundary_confidence    numeric,
  review_status          text not null default 'pending'
    check (review_status in ('pending','approved','rejected','needs_split')),
  model_version          text,
  notice                 text,
  watch_label            text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index semantic_segments_asset_idx
  on public.semantic_segments (source_asset_id, start_seconds);
create index semantic_segments_review_idx
  on public.semantic_segments (review_status);

create table public.segment_crops (
  id               uuid primary key default gen_random_uuid(),
  segment_id       uuid not null references public.semantic_segments(id) on delete cascade,
  aspect_ratio     text not null,
  crop_track_json  jsonb not null default '{}'::jsonb,
  approved         boolean not null default false,
  created_at       timestamptz not null default now()
);

create table public.clip_assets (
  id                   uuid primary key default gen_random_uuid(),
  segment_id           uuid not null references public.semantic_segments(id) on delete cascade,
  stream_uid           text,
  object_key           text,
  aspect_ratio         text,
  duration_seconds     numeric,
  captions_json        jsonb not null default '{}'::jsonb,
  thumbnail_url        text,
  requires_signed_url  boolean not null default true,
  status               text not null default 'pending'
    check (status in ('pending','ready','failed','revoked')),
  created_at           timestamptz not null default now()
);

create table public.recipe_step_intents (
  id                     uuid primary key default gen_random_uuid(),
  recipe_id              text not null,
  step_id                text not null,
  step_hash              text,
  primary_action         text,
  secondary_actions_json jsonb not null default '[]'::jsonb,
  ingredients_json       jsonb not null default '[]'::jsonb,
  tools_json             jsonb not null default '[]'::jsonb,
  starting_state         text,
  target_state           text,
  technique              text,
  dish_stage             text,
  visual_questions_json  jsonb not null default '[]'::jsonb,
  video_value            text not null default 'optional'
    check (video_value in ('none','optional','high','essential')),
  created_at             timestamptz not null default now(),
  unique (recipe_id, step_id)
);

create table public.step_segment_matches (
  id               uuid primary key default gen_random_uuid(),
  step_intent_id   uuid not null references public.recipe_step_intents(id) on delete cascade,
  segment_id       uuid not null references public.semantic_segments(id) on delete cascade,
  match_type       text,
  action_score     numeric,
  ingredient_score numeric,
  state_score      numeric,
  technique_score  numeric,
  visual_score     numeric,
  conflicts_json   jsonb not null default '[]'::jsonb,
  total_score      numeric,
  review_status    text not null default 'pending'
    check (review_status in ('pending','approved','rejected')),
  created_at       timestamptz not null default now(),
  unique (step_intent_id, segment_id)
);

-- Service-role only for media tables (worker + proxy). No anon/authenticated policies.
alter table public.rights_records enable row level security;
alter table public.source_assets enable row level security;
alter table public.ingestion_jobs enable row level security;
alter table public.transcript_words enable row level security;
alter table public.video_scenes enable row level security;
alter table public.semantic_segments enable row level security;
alter table public.segment_crops enable row level security;
alter table public.clip_assets enable row level security;
alter table public.recipe_step_intents enable row level security;
alter table public.step_segment_matches enable row level security;

-- Pilot seed: Eggs Benedict Gordon Ramsay (rights assumed cleared by product).
insert into public.rights_records (id, source_url, platform, external_id, clearance_notes, cleared_by, license_type)
values (
  'a1111111-1111-4111-8111-111111111111',
  'https://www.youtube.com/watch?v=gBJjRYk0yC0',
  'youtube',
  'gBJjRYk0yC0',
  'Pilot clearance for Glutt Eggs Benedict step-clip pipeline (product-confirmed).',
  'malik',
  'pilot_cleared'
) on conflict (id) do nothing;
