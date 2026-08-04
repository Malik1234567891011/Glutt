// Deletes the calling user's account. Apple requires an in-app deletion path
// for any app that offers account creation (App Review 5.1.1(v)) — shipping
// without this is a rejection.
//
// It has to live server-side: removing a row from `auth.users` needs the
// service-role key, which bypasses RLS and must never be in the app bundle.
// The key is injected into Edge Functions by Supabase; it is not committed.
//
// What goes with the user, by cascade: their `profiles` row, and every
// `profile_installs` link. Their `ai_usage` rows survive, because they are
// keyed to a random install UUID and — once the links are gone — no longer
// point at a person. That leaves our cost accounting intact while the account
// and everything identifying about it is genuinely deleted.
//
// PostHog goes too — see `forgetInPostHog`. It is the one other place that
// holds something identifying, because the email rides along as a person
// property.
//
// The recipe library goes too, and that used to be a line saying it never left
// the device — it does now (docs/plan-recipe-sync.md). Rows are free: `recipes`,
// `recipe_user_state` and `user_documents` all carry `on delete cascade`, so
// `deleteUser` takes them with it. **Storage objects are not.** Deleting an
// `auth.users` row does nothing to files in a bucket, so photos need an explicit
// step — see `purgeRecipeImages`.
//
// Cook history and Polly's logs stay out of sync entirely and remain on the
// device. Deleting the account also does NOT cancel the subscription, which
// lives on the Apple ID; the app says so before asking for confirmation.

import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

// PostHog project "Glutt" (533977) in the **US** region — the same installation
// the app writes to. US and EU are separate deployments and an id from one does
// not exist in the other, so this host is not a preference.
const POSTHOG_HOST = "https://us.posthog.com";
const POSTHOG_PROJECT_ID = "533977";

const IMAGE_BUCKET = "recipe-images";
/// `list` caps at 1000 per page, so a library larger than that has to be paged
/// rather than assumed away.
const LIST_PAGE = 1000;
/// How many previously-failed prefixes to retry per invocation. Bounded so a
/// backlog can never turn one person's deletion into a long request.
const RETRY_BUDGET = 5;

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// Removes the person and their events from PostHog.
///
/// Needed because PostHog holds the email and display name as person
/// properties, and this project runs with person-on-events: those properties
/// are stamped onto every event at ingest, not just held on the person row.
/// Deleting the person alone would leave the address on all of their history,
/// so `delete_events` is not optional here — it is the only thing that actually
/// removes the address.
///
/// The accepted cost: `identify` at sign-in merged the install's pre-account
/// history into this person, so their onboarding and paywall funnel goes with
/// them. Deletions are rare and deliberate; an honest one is worth more than
/// one person's funnel.
///
/// PostHog queues the deletion rather than performing it inline (Cloud runs the
/// batch off-peak), so a 202 here means accepted, not done.
///
/// Best-effort by design. The account is already gone by the time this runs and
/// a PostHog outage must not turn that into a visible failure. But a silent
/// failure is orphaned PII nobody knows about, so every non-success is logged
/// with the id needed to retry it by hand.
async function forgetInPostHog(userID: string): Promise<string> {
  const key = Deno.env.get("POSTHOG_PERSONAL_API_KEY");
  if (!key) {
    console.error(`posthog delete skipped for ${userID}: POSTHOG_PERSONAL_API_KEY is not set`);
    return "skipped";
  }

  // Deleting by `distinct_id` rather than PostHog's own person UUID, because
  // the distinct id IS the Supabase user id (see Analytics.swift) — so there is
  // nothing to look up first.
  //
  // Both cases are sent, and that is the whole trick. Swift's
  // `UUID.uuidString` is UPPERCASE, so every distinct id the app ever wrote
  // looks like `05C46670-…`; Postgres and this runtime hand back `05c46670-…`.
  // A PostHog distinct id is a case-sensitive string, so passing only what
  // Supabase gives us would match nothing and still answer 202 — a deletion
  // that silently deletes nobody. An id that does not exist is a no-op, so
  // sending the pair is free insurance.
  //
  // `delete_events` is sent in the query string *and* the body on purpose: the
  // single-person endpoint documents it as a query parameter, `bulk_delete`
  // declares it as a body field. Sending both removes the guess and costs
  // nothing.
  //
  // `delete_recordings` is defensive — session replay is off today, but if it
  // is ever switched on, a recording surviving a deletion would be the worst
  // version of this bug.
  const url =
    `${POSTHOG_HOST}/api/projects/${POSTHOG_PROJECT_ID}/persons/bulk_delete/?delete_events=true`;

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        distinct_ids: [userID.toUpperCase(), userID.toLowerCase()],
        delete_events: true,
        delete_recordings: true,
      }),
    });

    if (!res.ok) {
      console.error(
        `posthog delete failed for ${userID}: ${res.status} ${await res.text()}`,
      );
      return "failed";
    }

    return "queued";
  } catch (error) {
    console.error(`posthog delete errored for ${userID}: ${error}`);
    return "errored";
  }
}

/// Deletes every object under one `recipes/{user_id}` prefix.
///
/// Throws on failure so the caller can record the prefix and carry on. It must
/// never abort the deletion itself: blocking on a bucket error would produce a
/// user who cannot delete their account, which breaks the Apple requirement
/// outright.
async function purgeRecipeImages(admin: SupabaseClient, prefix: string): Promise<number> {
  let removed = 0;

  // Paged, because `list` returns at most 1000 and a library can exceed that.
  // Each pass lists from the top: the previous page has just been deleted, so
  // an offset would step over the files that moved up to take its place.
  for (;;) {
    const { data: files, error: listError } = await admin.storage
      .from(IMAGE_BUCKET)
      .list(prefix, { limit: LIST_PAGE });

    if (listError) throw listError;
    if (!files || files.length === 0) break;

    const paths = files.map((file) => `${prefix}/${file.name}`);
    const { error: removeError } = await admin.storage.from(IMAGE_BUCKET).remove(paths);
    if (removeError) throw removeError;

    removed += paths.length;
    if (files.length < LIST_PAGE) break;
  }

  return removed;
}

/// Retries a few prefixes left behind by earlier failures.
///
/// Opportunistic on purpose: it needs no scheduler, no second function and no
/// shared secret, and the queue only ever grows when a deletion happens, which
/// is the same event that drains it. Rows that keep failing accumulate an
/// `attempts` count and an error, which is what makes a stuck one visible.
async function retryPendingPurges(admin: SupabaseClient): Promise<number> {
  const { data: pending } = await admin
    .from("pending_purges")
    .select("path, attempts")
    .order("created_at", { ascending: true })
    .limit(RETRY_BUDGET);

  if (!pending?.length) return 0;

  let cleared = 0;
  for (const row of pending) {
    try {
      await purgeRecipeImages(admin, row.path);
      await admin.from("pending_purges").delete().eq("path", row.path);
      cleared += 1;
    } catch (error) {
      await admin
        .from("pending_purges")
        .update({ attempts: (row.attempts ?? 0) + 1, last_error: String(error) })
        .eq("path", row.path);
      console.error(`pending purge still failing for ${row.path}: ${error}`);
    }
  }
  return cleared;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return json({ error: "missing token" }, 401);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // The caller's own token decides whose account this is. Nothing in the
  // request body is trusted, so there is no way to ask for someone else's.
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) {
    return json({ error: "invalid token" }, 401);
  }

  // Photos first, while we still hold their id: after `deleteUser` there is
  // nothing left to tell us which prefix was theirs.
  const prefix = `recipes/${data.user.id}`;
  let images = "cleared";
  try {
    await purgeRecipeImages(admin, prefix);
  } catch (error) {
    // Recorded, not raised. The account still gets deleted; the files get
    // cleaned up on a later invocation.
    images = "deferred";
    console.error(`recipe image purge failed for ${prefix}: ${error}`);
    await admin
      .from("pending_purges")
      .upsert({ path: prefix, last_error: String(error) }, { onConflict: "path" });
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) {
    return json({ error: deleteError.message }, 500);
  }

  // Supabase first, always. If this order were reversed, a failure to delete
  // the account would leave someone with a live account and no analytics —
  // deleting the record of a user who still exists.
  const analytics = await forgetInPostHog(data.user.id);

  // Best-effort tail work, after everything this caller is waiting on.
  const retried = await retryPendingPurges(admin);

  return json({ deleted: true, analytics, images, retried }, 200);
});
