-- Accounts + AI usage tracking — step 1 of docs/plan-accounts-and-ai-usage.md
-- Profiles: one row per paying customer.
--
-- Non-payers are never asked to sign in, so every row in this table is an
-- entitled user. Signing in is identity, not entitlement — the subscription
-- lives on the Apple ID and is restored by StoreKit/Superwall independently.

create table public.profiles (
  id            uuid primary key references auth.users on delete cascade,
  created_at    timestamptz not null default now(),
  display_name  text,
  email         text,
  install_id    text,
  goals         text[],
  dietary_rules text[]
);

comment on table public.profiles is
  'One row per paying customer. Created by the on_auth_user_created trigger.';
comment on column public.profiles.install_id is
  'Keychain-persisted per-install UUID, used to back-fill ai_usage rows logged before sign-in.';

-- Apple returns name and email only on the very first authorization, so the
-- profile row must be written at signup. security definer to bypass RLS.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data ->> 'full_name'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;

create policy "read own profile"   on public.profiles for select using (auth.uid() = id);
create policy "update own profile" on public.profiles for update using (auth.uid() = id);

-- Supports the sign-in back-fill: find the install that became this user.
create index profiles_install_idx on public.profiles (install_id);
