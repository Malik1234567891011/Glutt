-- Recipe sync. Backs the user's library so it survives a logout, a reinstall
-- or a new phone. See docs/plan-recipe-sync.md.
--
-- One row per recipe, not three normalized tables. A recipe is a document and
-- the server never queries its insides -- SwiftData is the query engine on the
-- device. Normalizing would cost a multi-table transactional upsert on every
-- save and buy nothing. Columns are promoted out of `body` only where we want
-- to read them without parsing the blob.
--
-- `id` is generated on the device (Recipe.remoteID), because a recipe exists
-- and is editable long before it is ever pushed.

create table if not exists public.recipes (
  id              uuid primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  updated_at      timestamptz not null default now(),
  -- Tombstone. A hash sweep on the device cannot see a row that no longer
  -- exists, so a delete has to be stated rather than inferred. Purged after 90
  -- days by the cron at the bottom of this file.
  deleted_at      timestamptz,
  title           text not null,
  image_url       text,
  -- Storage object key. Filled in phase 3; kept here from the start so the
  -- upload does not need its own migration.
  image_path      text,
  source_url      text,
  source_platform text,
  is_favorite     boolean not null default false,
  body            jsonb not null default '{}'::jsonb
);

comment on table public.recipes is
  'One row per user-created recipe. Bundled Cooking Basics and chef dishes are NOT here -- they ship in the app binary; only the state a user puts on them travels, in recipe_user_state.';

-- The only query the client makes: everything of mine changed since a
-- watermark, oldest first.
create index if not exists recipes_user_updated_idx
  on public.recipes (user_id, updated_at);

alter table public.recipes enable row level security;

drop policy if exists "own recipes" on public.recipes;
create policy "own recipes" on public.recipes
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- `updated_at` is the pull watermark, so it must never depend on the client
-- remembering to send it.
--
-- SECURITY INVOKER, and EXECUTE revoked: a trigger function runs as the table
-- owner anyway, and marking it DEFINER only publishes it on /rest/v1/rpc for
-- anon and authenticated to call directly.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.touch_updated_at() from public, anon, authenticated;

drop trigger if exists recipes_touch_updated_at on public.recipes;
create trigger recipes_touch_updated_at
  before insert or update on public.recipes
  for each row execute function public.touch_updated_at();

-- Hearts, ratings and notes on content that ships inside the app.
--
-- Keyed by content slug rather than by copying the recipe: a chef dish is the
-- same bytes for every user, and storing 10,000 identical copies of it to
-- remember one heart would be absurd.
create table if not exists public.recipe_user_state (
  user_id     uuid not null references auth.users(id) on delete cascade,
  content_key text not null,               -- 'chef:<slug>' | 'basics:<slug>'
  is_favorite boolean not null default false,
  rating      int,
  notes       text,
  updated_at  timestamptz not null default now(),
  primary key (user_id, content_key)
);

alter table public.recipe_user_state enable row level security;

drop policy if exists "own recipe state" on public.recipe_user_state;
create policy "own recipe state" on public.recipe_user_state
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists recipe_user_state_touch_updated_at on public.recipe_user_state;
create trigger recipe_user_state_touch_updated_at
  before insert or update on public.recipe_user_state
  for each row execute function public.touch_updated_at();

-- Kitchen and preferences: one small jsonb document per kind. Small, valuable
-- on a new phone, and never queried server-side -- so they get a document each
-- rather than tables of their own.
create table if not exists public.user_documents (
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null,                -- 'kitchen' | 'prefs'
  body       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, kind)
);

alter table public.user_documents enable row level security;

drop policy if exists "own documents" on public.user_documents;
create policy "own documents" on public.user_documents
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists user_documents_touch_updated_at on public.user_documents;
create trigger user_documents_touch_updated_at
  before insert or update on public.user_documents
  for each row execute function public.touch_updated_at();

-- Tombstones exist so a phone that has been switched off for a while learns
-- about a delete. 90 days is far longer than that takes, and keeping them
-- forever would mean a library that only ever grows.
create or replace function public.purge_recipe_tombstones()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.recipes
  where deleted_at is not null
    and deleted_at < now() - interval '90 days';
$$;

revoke all on function public.purge_recipe_tombstones() from public, anon, authenticated;
