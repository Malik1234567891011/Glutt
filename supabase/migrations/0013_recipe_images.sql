-- Recipe photos in Storage, and the machinery that guarantees they are deleted
-- with the account. Phase 3 of docs/plan-recipe-sync.md.
--
-- These ship together on purpose: never upload a user's photos before there is
-- a path that deletes them.
--
-- Why upload at all, when `imageURL` is already stored and re-fetching costs
-- nothing? Because re-fetching fails in exactly the cases that matter. YouTube
-- and og:image URLs are permanent, but Instagram and TikTok thumbnails are
-- signed CDN URLs that rot in days, and camera-roll photos and share-sheet
-- preview bytes have no URL at all. `imageURL` is kept as the free fallback.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'recipe-images',
  'recipe-images',
  false,                       -- private. No public read, ever.
  5242880,                     -- 5 MB. ImagePrep emits 1280px q0.65, ~100-250 KB.
  array['image/jpeg']
)
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Path is `recipes/{user_id}/{recipe_id}.jpg`, so one rule covers the feature
-- and account deletion has a single prefix to remove.
--
-- Caching a creator's thumbnail on the user's own device is a personal copy;
-- serving it from a shared public bucket would be closer to redistribution. A
-- private per-user path with no public read keeps this as close to the
-- on-device posture as storage allows.
drop policy if exists "own recipe images read" on storage.objects;
create policy "own recipe images read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'recipe-images'
    and (storage.foldername(name))[1] = 'recipes'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "own recipe images insert" on storage.objects;
create policy "own recipe images insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'recipe-images'
    and (storage.foldername(name))[1] = 'recipes'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "own recipe images update" on storage.objects;
create policy "own recipe images update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'recipe-images'
    and (storage.foldername(name))[1] = 'recipes'
    and (storage.foldername(name))[2] = auth.uid()::text
  )
  with check (
    bucket_id = 'recipe-images'
    and (storage.foldername(name))[1] = 'recipes'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

drop policy if exists "own recipe images delete" on storage.objects;
create policy "own recipe images delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'recipe-images'
    and (storage.foldername(name))[1] = 'recipes'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- Deleting an `auth.users` row cascades through every table, but does nothing
-- at all to files in a bucket. Without an explicit step, every deleted account
-- would leave its photos behind forever: a privacy failure, not a leak.
--
-- `delete-account` removes them inline. When that fails, it records the prefix
-- here and deletes the user anyway -- blocking deletion on a bucket error would
-- mean a user who cannot delete their account, which breaks the Apple
-- requirement outright.
create table if not exists public.pending_purges (
  path       text primary key,      -- storage prefix, e.g. 'recipes/<uuid>'
  created_at timestamptz not null default now(),
  attempts   int not null default 0,
  last_error text
);

comment on table public.pending_purges is
  'Storage prefixes whose objects outlived their account. Retried by the delete-account function on every invocation. Service role only: no policies, and RLS on, so the anon and authenticated keys cannot see it.';

alter table public.pending_purges enable row level security;

-- Tombstone purge. A phone that has been switched off needs the delete to
-- survive long enough to learn about it; 90 days is far longer than that, and
-- keeping them forever means a library that only ever grows.
create extension if not exists pg_cron;

select cron.unschedule('purge-recipe-tombstones')
where exists (select 1 from cron.job where jobname = 'purge-recipe-tombstones');

select cron.schedule(
  'purge-recipe-tombstones',
  '17 4 * * *',
  $$select public.purge_recipe_tombstones()$$
);
