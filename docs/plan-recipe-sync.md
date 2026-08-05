# Recipe sync

Status: **built**, all five phases. Written 2026-07-31, implemented 2026-08-01.

Where it lives: `Glutt/Services/Sync/` (identity, body codec, engine, images,
bundled-content state, Kitchen documents, coordinator), `Glutt/Models/SyncTombstone.swift`,
`supabase/migrations/0012_recipes.sql` and `0013_recipe_images.sql`, and the
storage cleanup in `supabase/functions/delete-account/index.ts`. Tests in
`GluttTests/RecipeSyncTests.swift`.

Four things ended up different from the spec below, all noted inline where they
happen:

- `remoteID` is assigned in `Recipe.init` rather than at each
  `context.insert(recipe)` site. Same result, one place instead of a dozen, and
  it cannot be forgotten by a future call site. The migration stays lightweight
  because the *property* is still optional; `init` runs per instance and never
  when materializing a stored row.
- `createdAt` was added to `body`. Without it a restored library all arrives at
  the same second, and the recipes feed is sorted by it.
- Pull refuses to overwrite a recipe with unsent local edits. The spec accepted
  losing one edit; this costs nothing and avoids the common case.
- The `pending_purges` sweep is opportunistic (every `delete-account`
  invocation) rather than a cron. A cron would need a scheduler, a second
  function and a shared secret in Vault; the queue only grows on deletion, which
  is the same event that drains it. The 90-day tombstone purge *is* a pg_cron
  job, because it is pure SQL and needs none of that.

Backs the user's recipe library with Supabase so it survives a logout, a
reinstall, or a new phone. Supersedes the scope guard in
`plan-accounts-and-ai-usage.md`, which deliberately left recipes local until
accounts existed. They exist now.

## Goal

Log out, log back in, see the same recipes. That is the whole feature. Everything
below is in service of that one sentence.

## What syncs, and what does not

Not every `Recipe` row is user data. Three kinds live in the same table:

| Kind | Where it comes from | Sync? |
|---|---|---|
| Imported / manual / AI-generated | Share sheet, Discover, editor, pantry | **Yes.** Cost real money or real effort to create. |
| Cooking Basics, chef recipes | `GluttApp.swift:80-86`, reinstalled from code every launch | **No.** Ships in the binary. Only the user's heart/rating syncs. |
| `-seed` demo data | Beta scheme only | **No.** |

Bundled content is identified by tag: `isCookingBasic` (`CookingBasics.swift:211`)
and `chefSlug` (`Chefs.swift:668`). Anything carrying those tags is skipped by the
push.

## The blocker: recipes have no stable id

`Recipe` has no id of its own. SwiftData's `persistentModelID` is local and dies
with the store, so after a reinstall there is nothing to match a server row
against. **Nothing else in this plan can be built until this lands.**

Add to `Recipe`:

```swift
/// Stable cross-device identity. Optional only so the SwiftData migration is
/// lightweight; backfilled on first launch and never nil afterwards.
var remoteID: UUID?
```

Optional, not `= UUID()`. A defaulted value in a lightweight migration risks
every existing row getting the *same* generated UUID. An explicit backfill sweep
on first launch after the update is boring and correct.

Set it at every `RecipeFactory.make` and every `context.insert(recipe)` site
thereafter.

### Matching on restore

When a pulled row has no local match by `remoteID`, fall back in order:

1. `sourceURL` — this dedup already exists (`DiscoverSaver.swift:8`)
2. normalized `title` + `sourceCreator`

Then adopt the server's `remoteID` onto the local row.

## Schema

One row per recipe. Not three normalized tables. A recipe is a document, the
server never queries its insides (SwiftData is the query engine), and
normalizing would cost a multi-table transactional upsert on every save for no
benefit.

```sql
create table public.recipes (
  id              uuid primary key,        -- generated on device
  user_id         uuid not null references auth.users(id) on delete cascade,
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,             -- tombstone
  title           text not null,
  image_url       text,
  image_path      text,                    -- storage object key, phase 3
  source_url      text,
  source_platform text,
  is_favorite     boolean not null default false,
  body            jsonb not null default '{}'::jsonb
);

create index on public.recipes (user_id, updated_at);

alter table public.recipes enable row level security;

create policy "own recipes" on public.recipes
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

Columns are promoted only when we want to read them without parsing the blob.
Everything else goes in `body`.

Hearts and ratings on bundled content, keyed by content slug rather than a copy
of the recipe:

```sql
create table public.recipe_user_state (
  user_id     uuid not null references auth.users(id) on delete cascade,
  content_key text not null,               -- "chef:<slug>" | "basics:<slug>"
  is_favorite boolean not null default false,
  rating      int,
  notes       text,
  updated_at  timestamptz not null default now(),
  primary key (user_id, content_key)
);
```

Same RLS policy.

### `body` shape

```json
{
  "v": 1,
  "summary": "…",
  "servings": 2,
  "prepMinutes": 10,
  "cookMinutes": 25,
  "difficulty": "beginner",
  "tags": ["weeknight"],
  "notes": "",
  "rating": 4,
  "sourceCreator": "…",
  "sourceCaption": "…",
  "importedAt": "2026-07-31T…",
  "importConfidence": 0.82,
  "imageAssetName": null,
  "nutrition": { "cal": 540, "p": 32, "c": 40, "f": 22, "estimated": true },
  "collections": ["Weeknights"],
  "parentRemoteID": null,
  "versionLabel": "pantry version",
  "ingredients": [
    { "i": 0, "name": "…", "qty": 1.5, "unit": "cup", "note": null,
      "optional": false, "estimated": false, "role": "…" }
  ],
  "steps": [ { "i": 0, "text": "…", "sec": 300 } ]
}
```

`v` is there so a future shape change is readable rather than a guess.

Collections travel as an array of names inside each recipe rather than a join
table. They are identified by name and recreated locally on pull. Consequence: an
empty collection does not survive. Acceptable.

`parentRemoteID` carries the "my version" chain (`Recipe.parentRecipe`). Apply
parents before children on pull.

### Deliberately left out of `body`

| Field | Why |
|---|---|
| `imageData` | Bytes never go in Postgres. Storage, phase 3. |
| `canonicalName` | `IngredientCanonicalizer` recomputes it on read. |
| `mediaExternalID`, `mediaJobID`, `mediaStatus`, `mediaProgress`, `mediaSourceAssetID` | Server already owns these in `source_assets`, keyed by platform + external id. Re-derived by `MediaClipEnqueue.ensure` from `source_url`. |
| `speechTranscript` | Can be many KB, never displayed. |
| `issues`, `stepsAreAISuggested` | Import-review scratch, meaningless after save. |

`sourceCaption` is kept but capped at 2000 characters.

### Size

A recipe serializes to roughly 2 to 4 KB, and jsonb is TOAST-compressed. 10,000
users at 100 recipes each is about 2 to 3 GB. Text is not the storage problem;
images are, and they are handled below.

## Change tracking

**Content hash, not dirty flags.** Recipe mutations happen inline all over the
view layer (`RecipeDetailView.swift:197` toggles `isFavorite` directly), so any
scheme requiring a `touch()` call at every mutation site will silently miss one.

Instead, on each sync sweep: serialize the body, SHA256 it, compare against a
locally stored `syncedHash`. Different means push. 100 recipes at 3 KB is nothing
to hash.

Add to `Recipe`:

```swift
var syncedHash: String?      // hash of the body as last pushed
var syncedAt: Date?          // nil = never pushed
```

### Deletes

A hash sweep cannot see a row that no longer exists, so deletes need explicit
tombstones. There are only two delete sites
(`RecipeDetailView.swift:154`, `CollectionDetailView.swift:82`), so this is
cheap. Record `remoteID` + `deletedAt` in a small `SyncTombstone` `@Model`,
push as `deleted_at`, clear the local tombstone once the push confirms.

Server-side, purge tombstones older than 90 days on a cron.

## Sync mechanics

Offline-first. SwiftData stays the source of truth for every screen; Supabase is
the backup. Last-write-wins per whole recipe. No CRDTs, no field-level merge —
this is a one-phone-per-person app, and the worst case is losing one edit.

**Push.** Debounced sweep on foreground and after save. Upsert changed rows.

**Pull.** `where user_id = auth.uid() and updated_at > :watermark`, tombstones
included. Watermark stored per user id in `UserDefaults`.

**First sign-in with local recipes.** Backfill `remoteID`, stamp `user_id`, push
everything. Silent. No merge dialog. This path only matters as a one-time
migration for people already installed today, since sign-in is mandatory after
purchase for everyone new.

**Sign out.** Flush the queue first. If the flush fails, say so and offer to stay
signed in rather than drop unsynced work. Once flushed, delete user-created
recipes locally and clear the watermark. Bundled content stays. Without this,
the next account inherits the previous one's library.

## Images

`RecipeImageBackfill` already downloads and caches image bytes locally, and its
own doc comment says why: "source-URL rot". That judgement still holds.

Re-fetching on restore is free in dollars (a plain `URLSession` GET against the
source's CDN, no AI call, no API quota), but it fails in the cases that matter
most:

- **Permanently re-fetchable:** YouTube (`i.ytimg.com/vi/{id}/…` is deterministic
  and never expires), Spoonacular, most sites' `og:image`.
- **Rots in days to weeks:** Instagram and TikTok oEmbed thumbnails
  (`SocialMediaImport.swift:59,90`) are signed CDN URLs.
- **Impossible:** camera-roll photos, and share-sheet preview bytes
  (`ShareImportViewModel.swift:54-55`). No URL exists, only bytes. This is the
  known Instagram reel case.

So: **upload every recipe that has bytes.** `ImagePrep` already downscales to
1280px at q0.65, so stored images are roughly 100 to 250 KB. 10,000 users at 100
recipes is about 150 GB, roughly $3/month on Supabase Storage. Egress only fires
on restore.

No clever tiering by platform. It would save a couple of dollars a month and add
a branch that will eventually be wrong about some platform.

- Private bucket, path `recipes/{user_id}/{recipe_id}.jpg`, no public read.
- Store the key in `recipes.image_path`.
- Keep `image_url` too, so `RecipeImageBackfill.sweep` stays the free fallback
  when an object is missing.
- Upload opportunistically, not in one burst. A 100-recipe library is ~15 MB and
  must not all go over cellular on first sign-in.

## Account deletion

The `delete-account` Edge Function must delete everything this feature creates.
Its current doc comment says "Recipes, Kitchen and cook history are not touched
here: they never left the device" — that stops being true in phase 2 and the
comment has to change with it.

**Database rows are free.** `recipes.user_id` and `recipe_user_state.user_id`
both carry `on delete cascade`, so `admin.auth.admin.deleteUser()` takes them
with it. Verified against `pg_constraint`: `profiles` and `profile_installs`
already cascade today, `ai_usage` sets null by design.

**Storage objects are not.** Deleting an `auth.users` row does nothing to files
in a bucket. Without an explicit step, every deleted account leaves its photos
behind forever — a privacy failure, not just a leak. So phase 3 must extend the
function:

```ts
// Before deleting the user, while we still hold their id.
const { data: files } = await admin.storage
  .from("recipe-images")
  .list(`recipes/${userId}`, { limit: 1000 });

if (files?.length) {
  await admin.storage
    .from("recipe-images")
    .remove(files.map((f) => `recipes/${userId}/${f.name}`));
}
```

**If the storage delete fails, still delete the user.** Blocking deletion on a
bucket error would mean a user who cannot delete their account, which breaks the
Apple requirement outright. Instead record the orphaned prefix in a small
`pending_purges (path, created_at)` table and sweep it on a cron. Deletion always
succeeds for the user; the files still get cleaned up.

Note `list` caps at 1000 per page — paginate if a library can exceed that.

### Local data

Open question, and it needs a product decision rather than a technical one.

`AccountSession.deleteAccount()` currently signs out and leaves local SwiftData
untouched. After phase 2 that produces a strange half-state: the server copy is
gone, the phone still has everything, and there is no longer any backup.

Recommendation: **wipe local user recipes on account deletion too**, and say so
in the confirmation dialog. "Delete my account" most honestly means everything is
gone. The alternative is defensible but the current dialog does not warn either
way, so whichever we pick, the copy has to change.

## Phases

1. `remoteID` + migration + backfill, `syncedHash`/`syncedAt`, tombstones. No
   network. Ships invisibly.
2. `recipes` table + RLS + push/pull + claim-on-sign-in. **This alone delivers
   the goal.**
3. Images to Storage, **plus the bucket cleanup in `delete-account`**. These ship
   together — never upload user photos before there is a path that deletes them.
4. `recipe_user_state` for hearted chef and basics content.
5. Kitchen (`PantryItem`, `GroceryItem`, `KitchenTool`) and `UserPrefs`, one
   small jsonb document each. Small, valuable, never queried server-side.

Out of scope: `CookSession`, `PollyCookLog`. Per-device, high volume, low restore
value. `PollyMemory` is a maybe for later — it is small and would make Polly
remember you across phones.

## Open questions

- **Re-hosting creator thumbnails.** Caching a thumbnail on the user's device is
  a personal copy; serving it from our bucket is closer to redistribution. A
  private per-user path with no public read keeps it about as close to the
  on-device posture as possible. Related: the `rights_records` table already
  gates video downloads.
- **Image dedupe.** If the same viral recipe gets saved by thousands of people we
  store thousands of copies of one thumbnail. Content-hash into a shared path
  fixes it, at the cost of shared-bucket RLS. Not worth it at launch scale.
