-- Links a person to the installs they have signed in on, so AI spend recorded
-- against a device can be read as spend by a customer.
--
-- Why a mapping table rather than writing `ai_usage.user_id` at insert time:
--
--   * `ai_usage` is written by the proxy, which does not verify the caller's
--     identity (it trusts a client key, not a JWT). Putting an unverified id
--     into a column with a FK to auth.users means a stale or forged value
--     fails the insert -- and `logUsage` swallows errors, so the usage row
--     would vanish silently. Cost logging must never be that fragile.
--   * Attribution here is retroactive: the join covers every row that install
--     ever wrote, including all the spend from before the account existed.
--   * One person, several phones works. `profiles.install_id` holds only the
--     most recent.
--
-- `ai_usage.user_id` stays in place, unused, for a future path where the proxy
-- verifies the app's Supabase JWT and can be trusted to write it.

create table if not exists public.profile_installs (
  user_id    uuid        not null references auth.users on delete cascade,
  install_id text        not null,
  linked_at  timestamptz not null default now(),
  primary key (user_id, install_id)
);

create index if not exists profile_installs_install_idx
  on public.profile_installs (install_id);

alter table public.profile_installs enable row level security;

-- A signed-in client links its own install and reads its own links. The
-- `with check` stops anyone claiming a link on behalf of another user. It does
-- not stop someone claiming an install id that isn't theirs -- the blast radius
-- of that is muddying our own cost numbers, which nobody gains from, and the
-- table exposes nothing readable in return.
drop policy if exists "read own installs" on public.profile_installs;
create policy "read own installs" on public.profile_installs
  for select using (auth.uid() = user_id);

drop policy if exists "link own install" on public.profile_installs;
create policy "link own install" on public.profile_installs
  for insert with check (auth.uid() = user_id);

-- The headline question: what does each paying customer cost in AI?
--
-- security_invoker so the view runs as the caller. `ai_usage` has RLS on with
-- zero policies, so an app client reads nothing here; the service role (and you
-- in the SQL editor) reads everything. Without it the view would run as its
-- owner and hand every client the whole cost table.
drop view if exists public.ai_spend_by_user;
create view public.ai_spend_by_user with (security_invoker = on) as
select
  p.id                        as user_id,
  p.email,
  p.display_name,
  count(*)                    as calls,
  sum(c.cost_usd)             as cost_usd,
  min(c.created_at)           as first_call,
  max(c.created_at)           as last_call
from public.profiles p
join public.profile_installs pi on pi.user_id = p.id
join public.ai_usage_costed c   on c.install_id = pi.install_id
group by p.id, p.email, p.display_name;
