# Accounts + AI usage tracking

Status: spec, not yet built. Written 2026-07-29.

Adds Sign in with Apple accounts (Supabase) after the paywall, and per-user AI
cost tracking logged server-side from the Vercel proxy.

## Why

Two questions we currently cannot answer:

1. **Who is paying us?** Superwall knows an entitlement is active; we have no
   durable record of a person.
2. **What does each user cost in AI?** Every Polly session, import, Plates deck
   and Discover call goes through `vercel-ai-proxy`, which forwards and forgets.
   Polly (OpenAI Realtime, audio-billed) is by far the most expensive feature
   and has zero visibility.

## Scope guard — what this does NOT do

**Recipes, Kitchen and cook history stay in local SwiftData.** Nothing syncs to
Supabase. A user who reinstalls or switches phones still loses their data.

This is deliberate: moving the SwiftData store to Postgres touches nearly every
screen and is weeks of work. Having an account is a prerequisite for that, not
the same job. If durability is wanted before then, SwiftData + CloudKit solves
it separately with no server (needs the iCloud entitlement, all `@Model`
properties optional/defaulted, no `@Attribute(.unique)`).

**Signing in does not unlock the app.** The subscription lives on the Apple ID
and is restored by StoreKit/Superwall regardless of account state. The account
is identity, not entitlement. Worth keeping straight — it drives the flow below.

## Flow

### New user

```
Onboarding 0–9  →  hasCompletedOnboarding = true
                →  gate.access == .locked, PaywallGateOverlay bounces to paywall
                →  ┌── pressed X / no purchase → stays locked, bounce loop. NO sign-in.
                   └── purchased → gate.access == .unlocked
                                 → SignInView (Apple, not dismissible)
                                 → home
```

Non-payers are never asked to sign up. They cannot use the app either way, so a
signup screen would lead nowhere. Consequence: **every row in `profiles` is a
paying customer.** Bounced users are still visible in PostHog as anonymous
events — analytics covers non-payers, the database holds payers.

### Returning user (new phone)

`WelcomeScreen` (onboarding screen 0) gets a small secondary action under the
primary CTA: *Already have an account? Log in.*

**Always shown; it restores before it signs in.** Signing in with Apple
*creates* the Supabase user when none exists (no sign-in-only mode exists for
OIDC), so the Apple sheet must never open for someone who has not paid, or
`profiles` stops being exactly the paying customers.

A first attempt hid the link unless `gate.access == .unlocked`. That closed the
hole but made the link invisible on every unsubscribed device, which is most of
them, including a returning user whose restore has not landed yet. So the link
is back and the check moved behind it:

1. Already entitled → present `SignInView`.
2. Otherwise → `gate.restorePurchases()`, showing "Looking for your
   subscription" in place of the link.
3. Restored → present `SignInView`. Nothing found → `login_no_subscription`, and
   Superwall's own "nothing to restore" alert is left to speak for itself rather
   than stacking a second one.

Restoring first is the right order regardless: the subscription lives on the
Apple ID, so it is the part that actually gets a returning user their app back.
The account only skips onboarding and re-links their spend history.

Verified on the simulator: the link is present on a clean install, and tapping it
with no subscription goes to StoreKit restore and **never reaches Apple
sign-in**. The simulator has no App Store account, so restore raises its own
credential prompt and can background the app; a real device is needed to see the
success path.

Presents `SignInView` as a sheet above the onboarding cover. On success:

- Set `hasCompletedOnboarding = true` and dismiss onboarding.
- Call `Superwall.shared.identify(userId:)` with the Supabase user id.
- StoreKit restores the entitlement from their Apple ID independently. If it
  resolves active → app. If not → the normal locked/bounce state.

Its real job is skipping onboarding and re-linking the account. The subscription
would restore without it.

### Launch state machine

`RootView`'s existing overlay switch extends from one axis to two:

| `gate.access` | `session.state` | Shown |
|---|---|---|
| `.resolving` | any | `GateSplashView` |
| `.locked` | any | `PaywallGateOverlay` (unchanged) |
| `.unlocked` | `.resolving` | `GateSplashView` |
| `.unlocked` | `.signedOut` | `SignInView` |
| `.unlocked` | `.signedIn` | `EmptyView` — full app |

The `.unlocked` + `.signedOut` cell is the edge case that will otherwise bite:
someone pays, then kills the app before signing in. Next launch they are
entitled with no account, and this rule catches them.

`SubscriptionGate` stays exactly as-is. Account state is a separate
`@Observable` so the two gates remain independently testable.

## iOS changes

### New files

| Path | Purpose |
|---|---|
| `Glutt/Services/Auth/Supabase.swift` | Configured `SupabaseClient` singleton |
| `Glutt/Services/Auth/AccountSession.swift` | `@Observable`; `.resolving/.signedOut/.signedIn(User)`; restores session at launch |
| `Glutt/Features/Auth/SignInView.swift` | Full-screen Apple sign-in |
| `Glutt/Features/Auth/AppleSignIn.swift` | Nonce generation + `ASAuthorizationController` wrapper |
| `Glutt/Services/Analytics/InstallID.swift` | Keychain-persisted UUID (see below) |

### Edits

- **`project.yml`** — add `supabase-swift` (`https://github.com/supabase/supabase-swift`, from 2.0.0) to `packages` and to the `Glutt` target. Run `xcodegen generate` after.
- **`Glutt/Glutt.entitlements`** — add `com.apple.developer.applesignin` = `[Default]`. Currently only carries the app group.
- **`Glutt/App/RootView.swift`** — extend the overlay switch per the table above; add `@State private var session = AccountSession()` and `.task { await session.restore() }`.
- **`Glutt/Features/Onboarding/Screens/WelcomeScreen.swift`** — add the "Log in" secondary action.
- **`Glutt/Services/AI/Secrets.swift`** — add `supabaseURL` and `supabaseAnonKey` (anon key is publishable; the service-role key must never ship in the app).
- **`LLMClient.swift`, `DiscoverService.swift`, `PlatesService.swift`, `PollyTokenService.swift`** — attach `Authorization: Bearer <supabase access token>` alongside the existing `x-glutt-proxy-key`.

### Install ID

**One already exists.** `GluttDeviceID` in `PollyTokenService.swift:6` is a
UserDefaults UUID sent as `x-glutt-device-id`, minted for the Polly abuse cap.
Step 2 reuses it as `ai_usage.install_id`, so Polly attribution works today.

`InstallID.swift` should therefore be a *migration* of that value into the
Keychain, not a fresh mint — **read the existing `glutt.device.id` default first
and promote it**. Minting a new UUID would make every existing install look
brand new and orphan its accumulated cost history. The other services
(`LLMClient`, `DiscoverService`, `PlatesService`) need the header added; only
`PollyTokenService` sends it today.

The Keychain is the right home (not `UserDefaults`, which dies with the app; not
`identifierForVendor`, which resets when all our apps are deleted). Two jobs:

- PostHog `distinct_id` before an account exists.
- `ai_usage.install_id`, so proxy calls made before sign-in still attribute, and
  can be back-filled to a `user_id` at sign-in.

### Sign in with Apple gotchas

- **Apple returns name and email only on the very first authorization.** Persist
  them to `profiles` immediately — they are unrecoverable afterwards without the
  user revoking access in their Apple ID settings.
- Nonce: generate a random string, pass its **SHA256** to
  `ASAuthorizationAppleIDRequest.nonce`, pass the **raw** value to
  `supabase.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken:, nonce:))`.
- The Supabase dashboard's Apple provider needs the bundle ID
  `com.omarlahmimi.glutt` registered as a client id. Native and web flows use
  different client ids — only the native one matters here.
- Apple requires an account **deletion** path in-app once accounts exist. This
  is a review-rejection risk. Add a "Delete account" row in Settings calling a
  Supabase Edge Function that removes the auth user (the `profiles` cascade
  handles the rest).

## Supabase schema

```sql
-- One row per paying customer.
create table public.profiles (
  id           uuid primary key references auth.users on delete cascade,
  created_at   timestamptz not null default now(),
  display_name text,
  email        text,
  install_id   text,
  goals        text[],
  dietary_rules text[]
);

-- Auto-create the profile row on signup.
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

-- One row per AI call. Written ONLY by the proxy (service role).
create table public.ai_usage (
  id                   bigint generated always as identity primary key,
  user_id              uuid references auth.users on delete set null,
  install_id           text,
  feature              text not null,   -- polly_session | polly_speak | chat |
                                        -- import_reddit | transcribe |
                                        -- plates_deck | plates_search |
                                        -- discover_search | discover_suggested
  model                text,
  input_tokens         integer,
  output_tokens        integer,
  audio_input_seconds  numeric,
  audio_output_seconds numeric,
  duration_ms          integer,
  ok                   boolean not null default true,
  created_at           timestamptz not null default now()
);

create index ai_usage_user_created_idx    on public.ai_usage (user_id, created_at desc);
create index ai_usage_feature_created_idx on public.ai_usage (feature, created_at desc);
create index ai_usage_install_idx         on public.ai_usage (install_id) where user_id is null;
```

Costs live in a rates table, not in the rows — so price changes do not require
rewriting history:

```sql
create table public.ai_rates (
  model                 text primary key,
  input_per_1k          numeric default 0,
  output_per_1k         numeric default 0,
  audio_input_per_min   numeric default 0,
  audio_output_per_min  numeric default 0
);

create view public.ai_usage_costed as
select
  u.*,
  coalesce(u.input_tokens, 0)         / 1000.0 * coalesce(r.input_per_1k, 0)
+ coalesce(u.output_tokens, 0)        / 1000.0 * coalesce(r.output_per_1k, 0)
+ coalesce(u.audio_input_seconds, 0)  / 60.0   * coalesce(r.audio_input_per_min, 0)
+ coalesce(u.audio_output_seconds, 0) / 60.0   * coalesce(r.audio_output_per_min, 0)
  as cost_usd
from public.ai_usage u
left join public.ai_rates r on r.model = u.model;
```

The two queries worth having on day one:

```sql
-- Cost per user, last 30 days
select p.email, sum(c.cost_usd) as usd, count(*) as calls
from ai_usage_costed c join profiles p on p.id = c.user_id
where c.created_at > now() - interval '30 days'
group by p.email order by usd desc;

-- Cost per feature
select feature, sum(cost_usd) as usd, count(*) as calls
from ai_usage_costed
where created_at > now() - interval '30 days'
group by feature order by usd desc;
```

### Row Level Security

```sql
alter table public.profiles enable row level security;
create policy "read own profile"   on public.profiles for select using (auth.uid() = id);
create policy "update own profile" on public.profiles for update using (auth.uid() = id);

-- RLS on, zero policies: no client can read or write. Only the service role
-- (the proxy) touches this table, and service role bypasses RLS.
alter table public.ai_usage enable row level security;
alter table public.ai_rates enable row level security;
```

## Proxy changes (`vercel-ai-proxy`)

### New

- **`api/_lib/supabase.js`** — service-role client. `SUPABASE_URL` +
  `SUPABASE_SERVICE_ROLE_KEY` as Vercel env vars. Server-only, never shipped.
- **`api/_lib/user.js`** — read `Authorization: Bearer <jwt>`, verify it, return
  `{ userId, installId }` or `{ userId: null }`. Verify the JWT **locally**
  against the project JWKS (`jose`) rather than calling
  `auth.getUser()` per request — a network round trip on every Polly turn is not
  acceptable latency.
- **`api/_lib/usage.js`** — `logUsage({...})`. Two hard rules:
  1. **It must never fail the AI request.** Wrap in try/catch, swallow errors.
  2. **Do not fire-and-forget on Vercel** — the function can freeze before the
     insert lands. Use `waitUntil` from `@vercel/functions`.

### Edits

Keep the existing `x-glutt-proxy-key` check in `_lib/auth.js` as the first-line
filter; the JWT is additive, and identifies rather than authorizes.

**Built 2026-07-29.** Reading every endpoint corrected a wrong assumption in the
original draft — that all ten are token-billed AI calls against one vendor.
The actual map:

| Endpoint | Vendor | Billed in | Edge-cached |
|---|---|---|---|
| `polly/session` | OpenAI Realtime | audio min | no |
| `polly/speak` | OpenAI TTS | tokens | no |
| `chat/completions` | OpenAI | tokens | no |
| `import/transcribe` | **ElevenLabs** Scribe v2 | audio min | no |
| `plates/deck`, `plates/search` | Spoonacular | points quota | 12h / 24h |
| `discover/search`, `discover/suggested` | YouTube Data | quota units | 24h / 6h |
| `import/reddit` | Reddit + PullPush | free | no |
| `discover/player` | none — static HTML | — | 24h |

Three consequences. Only four endpoints can carry a dollar cost, and they span
**two** vendors, not one. The quota APIs are edge-cached, so the function does
not run on a hit — their rows count cache *misses*, i.e. quota spend, and must
never be read as user activity; PostHog answers that. And `discover/player` is
not instrumented at all: it makes no upstream call and has no proxy-key gate to
attribute by.

Quota vendors are logged with a `vendor:endpoint` model string that deliberately
matches no `ai_rates` row, so they cost $0 by construction rather than by
oversight.

Polly needed the most care — cost is audio-seconds and the WebRTC session runs
device-to-OpenAI where the proxy sees nothing. `polly/session` logs the token
**mint** (`feature = polly_session`); the app reports duration on teardown via
`POST /api/polly/usage` (`feature = polly_realtime`). A `polly_session` row with
no matching `polly_realtime` row is a crash, force-quit, or lost network. Note
the mid-session token re-mint path, which makes `polly_session` rows outnumber
`polly_realtime` rows even when everything works.

`waitUntil` was specified but not used: the proxy has no `package.json`, and
adding one would make Vercel start running an install step on every deploy of a
currently dependency-free service. `logUsage` is awaited instead, bounded by a
1.2s timeout with all errors swallowed. Against upstream calls that already take
seconds, the added latency is noise.

### Share extension caveat

`RedditImport.swift` is compiled into the `GluttShare` target and calls
`/api/import/reddit`. The extension has no Supabase session, so those calls log
with `install_id` and a null `user_id`.

Two options: accept it (a nightly job back-fills `user_id` by `install_id`), or
give the Supabase client a shared keychain access group so both targets read the
same session. **Start with option 1** — it is free, and Reddit-share imports are
a minor path.

## Where PostHog fits

Unchanged from the earlier plan and independent of this work. PostHog answers
*are people using the app* (including the anonymous non-payers this spec
deliberately excludes from the database); Supabase answers *what does each payer
cost me*. Use the install ID as `distinct_id`, then call
`PostHog.shared.identify(_:)` with the Supabase user id at sign-in so the
pre-account and post-account events join up.

**Built 2026-07-29.** `posthog-ios` (from 3.68.4) on the app target only — the
share extension runs under a tight memory budget and has nothing to report.
Everything goes through `Glutt/Services/Analytics/Analytics.swift`; no call site
imports the SDK.

The install id is seeded as PostHog's **anonymous** id via `PostHogConfig`'s
`bootstrap`, not by calling `identify(InstallID.current)`. Two reasons: an
anonymous event creates no person profile (cheaper, and there is no person to
profile before an account exists), and `bootstrap` is applied *before* `setup`
returns, so the `Application Installed` event PostHog captures during
initialization already carries the install id instead of an SDK-minted UUID.
`identify(userID:)` at sign-in then merges the whole pre-account history into
the account.

Events: `onboarding_screen_viewed` (`screen` 0–9 + `name`),
`onboarding_notifications` (granted/denied/skipped), `onboarding_completed`,
`gate_resolved` (locked/unlocked, once per launch), `paywall_presented`,
`paywall_dismissed`, `paywall_skipped`, `paywall_error`. Plus the SDK's own
lifecycle events; `captureScreenViews` is off, since swizzled UIKit screen views
are noise in a SwiftUI app.

Two traps found while verifying:

- A `build` super property (debug/release) is **stored but unreadable** —
  PostHog ships a core definition for that key typed as a *number* (the app
  build number), so a string value queries back as null. Renamed
  `build_config`. Anything registered as a super property needs a name that
  doesn't collide with PostHog's core taxonomy.
- `register(...)` runs after `setup(...)`, so `Application Installed` — captured
  during setup — is the one event without the super property.

## Locked state, revised 2026-07-29

The hard paywall no longer waits for a touch. Pressing Continue at the end of
the tutorial opens the paywall itself, because an unpaid user should never reach
the home feed, not even as inert scenery. Two changes:

- `RootView` presents automatically once entitlement resolves to `.locked` and
  onboarding is done, after a 350ms beat so the onboarding cover has finished
  dismissing (presenting into a view controller that is still going away gets
  the paywall torn down with it).
- **Once per launch,** via `presentPaywallOnce()`. Without that guard it re-fired
  every time the host view reappeared, which includes the moment the paywall is
  dismissed, so closing it reopened it instantly. The event log showed
  presented/dismissed/presented/dismissed in a loop, and a modal with no way out
  is something App Review reads as a trap.
- `PaywallGateOverlay` is now opaque: a lightly blurred still of a full recipe
  library (`paywallLockedHome`, a downscaled JPEG, 289KB rather than the 2.5MB
  source PNG), a bottom-weighted cream scrim, and a "See plans" button. Tapping
  anywhere reopens the paywall. Blur is deliberately light so the food and cards
  still read as recipes; past ~15 it becomes a beige smear and the point is lost.

Note the paywall itself currently has no visible close on its plans page, so in
practice a locked user stays on it. The blurred cover is what they see in the
moment before it presents, and if presentation ever fails.

## Sign-in as built (2026-07-29)

`supabase-swift` 2.54 on the app target only. Files: `Services/Auth/
SupabaseBackend.swift` (the client), `Services/Auth/AccountSession.swift`
(`@Observable`, `.resolving/.signedOut/.signedIn`), `Features/Auth/
AppleSignIn.swift` (nonce + credential unpacking), `Features/Auth/
SignInView.swift`.

Three deviations from the spec above, each for a reason:

**`SignInWithAppleButton` instead of an `ASAuthorizationController` wrapper.**
The SwiftUI button owns the controller; all that's left is the nonce dance.

**A "Continue without an account" escape, shown only after a failure.** The spec
made the post-purchase screen strictly non-dismissible. That means one broken
dependency — a disabled provider, an expired Apple key, an outage — locks out
every customer who just paid, with no way back. The link appears only once an
attempt has actually failed, is not persisted (next cold launch asks again), and
fires `sign_in_deferred`, which is a clean alarm: it can only rise if auth is
broken.

**Cost attribution goes through `profile_installs`, not `ai_usage.user_id`.**
The spec had the app send a bearer token for the proxy to verify against the
JWKS. Instead the client writes one `(user_id, install_id)` row at sign-in and
`ai_spend_by_user` joins through it (migration `0008`). Why: `ai_usage` is
written by the proxy, which authenticates a client key rather than a user, so an
unverified id in a column with a FK to `auth.users` turns a stale value into a
failed insert — and `logUsage` swallows errors, so the usage row would vanish
silently. Cost logging must not be that fragile. The mapping is also
**retroactive** (it attributes everything that install ever spent, including all
the pre-account history) and handles one person on several phones, which a
single `profiles.install_id` cannot. `ai_usage.user_id` stays unused, for a
future path where the proxy verifies the JWT.

Verified on the simulator: the state machine routes to `SignInView` on
`unlocked` + `signedOut`, the entitlement is live (the system Apple sheet
appears), cancel is silent, and a failure renders the error plus the escape and
fires `sign_in_failed`. **Not verified: a real sign-in** — the simulator has no
Apple Account and the Supabase provider is off.

### Google sign-in (added 2026-07-29)

Native, via `GoogleSignIn-iOS` 9.2, not the browser flow. The choice was made for
us: `/auth/v1/authorize?provider=google` answers `"Unsupported provider: missing
OAuth secret"`, because the Supabase Google provider is configured with a client
id and no secret, which is exactly the native (`id_token`) setup.

`GoogleAuth` (in `Features/Auth/`) wraps the SDK and hands
`AccountSession.signInWithGoogle` an id token plus an access token.
`Secrets.googleClientID` holds the iOS client id
(`326973383718-tmur4tp76aic…`), and the same value **reversed** is a URL scheme
in `project.yml`. Those two must always agree: GoogleSignIn gives that scheme to
`ASWebAuthenticationSession`, and the flow dead-ends silently without it. An
empty client id hides the button rather than offering a dead one.

One difference from Apple worth knowing: **Google embeds the nonce in the token
verbatim**, so the same raw string goes to Google and to Supabase. Hashing one
side, which is what Apple requires, makes the comparison fail.

Two things to confirm on the Google/Supabase side, neither visible from the app:
the client id must be of type **iOS** in Google Cloud (a Web client id fails
audience validation), and that same id must appear in the Supabase Google
provider's **Client IDs** field.

### To make it actually work

1. Supabase dashboard → Authentication → Sign In / Providers → **Apple →
   Enable**, and put `com.omarlahmimi.glutt` in **Client IDs**. The native flow
   needs the bundle id only; the Services ID + secret key are for web OAuth.
2. Test on a **real iPhone** signed into iCloud. The simulator cannot do this.
3. Ship step 5 (below) before submitting: Apple requires in-app account
   deletion once accounts exist, and this is a common rejection.

## Build order

1. ~~**Supabase schema + RLS.**~~ **DONE 2026-07-29.** Applied to project
   `mlgdtksukpifkmhqulnc`; SQL recorded in `supabase/migrations/`. Two hardening
   changes on top of the spec above: the `ai_usage_costed` view is created
   `security_invoker = on` (without it the view runs as its owner and leaks the
   RLS-locked `ai_usage` to any client), and `EXECUTE` on `handle_new_user()` is
   revoked from `anon`/`authenticated` (SECURITY DEFINER functions in `public`
   are exposed at `/rest/v1/rpc/<name>`).
2. ~~**Proxy usage logging, `user_id` null.**~~ **DONE 2026-07-29.** Nine
   endpoints wired plus the new `polly/usage`. Attribution rides the existing
   `x-glutt-device-id` header, which today only `PollyTokenService` sends — so
   Polly rows carry an `install_id` immediately and the rest are null until
   step 3 adds the header to the other services.
3. ~~**Install ID + PostHog.**~~ **DONE 2026-07-29.** `InstallID` (Keychain +
   app group) was already shipped and every proxy-calling service sends
   `x-glutt-device-id`. This step added the SDK and the funnel instrumentation —
   see *Where PostHog fits* below. Verified live: a full onboarding walkthrough
   on the simulator landed all six event types in project 533977, every one
   carrying `distinct_id` = the install UUID, which survived two
   uninstall/reinstall cycles. `paywall_dismissed`/`skipped`/`error` are wired
   but were not exercised — the simulator would not register a tap on the
   paywall webview's close button.
4. **Sign in with Apple + `AccountSession` + `SignInView` + `RootView` wiring.**
   **BUILT 2026-07-29** — see *Sign-in as built* below. Blocked from working
   end-to-end on one dashboard switch: the Supabase Apple provider is still
   `"apple": false` (check with `GET /auth/v1/settings`).
5. ~~**Settings: sign out + delete account.**~~ **BUILT 2026-07-29.** An
   "Account" section in `SettingsView` (email, sign out, destructive delete
   behind a confirmation), backed by the `delete-account` Edge Function —
   removing an `auth.users` row needs the service-role key, which cannot ship
   in the app. `profiles` and `profile_installs` cascade; `ai_usage` rows
   survive keyed to a random install UUID that no longer points at anyone.
   Verified deployed and rejecting unauthenticated calls (401, and 401 on a
   malformed JWT). Not verified end-to-end — needs a real signed-in account.
   The confirmation copy states plainly that recipes stay on the device and
   that deletion does **not** cancel the subscription.

Steps 1–3 deliver most of the value and touch no user-facing flow. Step 4 is the
only one that changes what a user sees.

## Open decisions

- **Supabase free plan pauses projects after 1 week of inactivity.** Fine while
  building; a paused project is a broken app in production. Budget the $25/mo
  Pro plan before this ships.
- Should a signed-in user who lets their subscription lapse keep their account?
  (Recommend: yes — keeps the win-back path open.)
- Region: pick EU or US at project creation, it cannot be changed later. EU is
  the safer GDPR default given the App Store audience.
